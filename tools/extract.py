#!/usr/bin/env python3
"""Turn a (slimmed) Hitchwiki XML dump into structured data: JSON Lines + SQLite.

Usage:
    python3 -m venv .venv && .venv/bin/pip install mwparserfromhell mwxml
    .venv/bin/python extract.py output/hitchwiki-latest.xml output/ [--app-db ../HitchWise/hitchwiki.sqlite]
                     [--version 202610311200] [--source-sha256 <hash of the dump>] [--language pl]

Writes:
    output/pages.jsonl   one JSON object per article (ns 0), easy to grep / jq / load in pandas
    output/hitchwiki.sqlite   same data, normalised into tables + full-text search (FTS5)
"""
import json, re, sqlite3, sys, os
import mwxml, mwparserfromhell as mwp

import argparse
_ap = argparse.ArgumentParser()
_ap.add_argument('src'); _ap.add_argument('outdir')
_ap.add_argument('--app-db', help='also write a slim copy (no raw wikitext) for bundling in the iOS app, e.g. ../HitchWise/hitchwiki.sqlite')
_ap.add_argument('--version', type=int, help='data version stored in the meta table (default: time of the newest edit in the dump as YYYYMMDDHHMM); the app updates to a higher one')
_ap.add_argument('--source-sha256', default='', help='SHA-256 of the dump this was built from, stored in the meta table')
_ap.add_argument('--min-version', type=int, default=0, help='never use a lower version than this (the workflow passes the '
                                     'last published version + 1, so a rebuild of the same dump with a better parser still reaches the app)')
_ap.add_argument('--language', default='en', help="which Hitchwiki the dump is from ('en', 'pl'), stored in the meta table; the app checks it")
_ap.add_argument('--gazetteer', help='an English hitchwiki.sqlite; pages of another language without coordinates borrow them '
                                     'from the English page with the same title or a redirect to it (e.g. ../HitchWise/hitchwiki.sqlite)')
_args = _ap.parse_args()
src, outdir = _args.src, _args.outdir
MAP_RE = re.compile(r"""<map[^>]*?lat=['"]([-\d.]+)['"][^>]*?lng=['"]([-\d.]+)['"]""", re.I)

TEMPLATES = {}   # 'Apl' -> template wikitext, filled by a first pass over the dump
PARAM_RE = re.compile(r'\{\{\{\s*([^|{}]+?)\s*(?:\|([^{}]*))?\}\}\}')

def tkey(name):
    name = str(name).strip().replace('_', ' ')
    return name[:1].upper() + name[1:]

def expand(wikitext, depth=0):
    """Light template expansion: substitutes {{{1}}}-style params from the dump's own templates.
    Parser functions ({{#if:...}}) and Lua modules are not evaluated - good enough for road badges etc."""
    code = mwp.parse(str(wikitext))
    if depth > 4:
        return str(code)
    for t in code.filter_templates(recursive=False):
        body = TEMPLATES.get(tkey(t.name))
        for _ in range(3):   # follow template redirects
            r = re.match(r'\s*#REDIRECT\s*\[\[\s*(?:Template:)?([^\]|#]+)', body or '', re.I)
            if not r: break
            body = TEMPLATES.get(tkey(r.group(1)))
        if body is None:
            continue
        m = re.search(r'<onlyinclude>(.*?)</onlyinclude>', body, re.S)
        body = m.group(1) if m else re.sub(r'<noinclude>.*?(</noinclude>|$)', '', body, flags=re.S)
        body = body.replace('<includeonly>', '').replace('</includeonly>', '')
        args = {str(p.name).strip(): str(p.value).strip() for p in t.params}
        body = PARAM_RE.sub(lambda m: args.get(m.group(1), m.group(2) or ''), body)
        try:
            code.replace(t, expand(body, depth + 1))
        except ValueError:
            pass
    return str(code)

NON_TEXT_LINKS = ('file:', 'image:', 'media:', 'category:')
ARTICLES, REDIRECTS = set(), {}   # filled by the first pass; used to resolve link targets
LINK_OPEN, LINK_MID, LINK_CLOSE = '', '', ''   # private-use markers that survive strip_code

def norm_title(t):
    t = re.sub(r'[\s_]+', ' ', t).strip()
    return t[:1].upper() + t[1:]

def resolve_link(target):
    """Wiki link target -> title of an article in this dump (following redirects), or None."""
    t = target.strip().lstrip(':').split('#')[0]
    t = norm_title(t)
    if not t:
        return None
    for _ in range(3):
        if t in ARTICLES:
            return t
        if t not in REDIRECTS:
            return None
        t = norm_title(REDIRECTS[t].split('#')[0])
    return None

def utf16_len(s):
    return len(s.encode('utf-16-le')) // 2

def clean_with_links(wikicode_or_str, expand_templates=False):
    """Wikitext -> (plain text, links). Each link is {'start', 'length', 'target' or 'url'};
    start/length count UTF-16 code units, i.e. they are NSRange values for NSString/NSAttributedString in Swift."""
    if expand_templates:
        wikicode_or_str = expand(wikicode_or_str)
    # skip_style_tags: treat bold/italic quote runs as plain text so an unbalanced one can't swallow
    # templates (Warsaw's infobox); the quote runs are removed after strip_code
    code = mwp.parse(str(wikicode_or_str), skip_style_tags=True)
    destinations = []

    def marked(label, destination):
        # a link nested in this one's label (e.g. [https://... trip through [[Kazakhstan]]]) becomes plain text
        label = re.sub(f'{LINK_OPEN}(.*?){LINK_MID}\\d+{LINK_CLOSE}', r'\1', label, flags=re.S)
        label = re.sub(r"'{2,}", '', mwp.parse(label, skip_style_tags=True).strip_code()).strip()
        if not label:
            return ''
        destinations.append(destination)
        return f'{LINK_OPEN}{label}{LINK_MID}{len(destinations) - 1}{LINK_CLOSE}'

    for link in code.filter_wikilinks(recursive=True):
        title = str(link.title).strip()
        try:
            if title.lower().startswith(NON_TEXT_LINKS):
                code.remove(link)
                continue
            label = str(link.text) if link.text is not None else title.lstrip(':')
            target = resolve_link(title)
            # links to pages we don't have (red links, other wikis) stay plain text
            code.replace(link, marked(label, ('target', target)) if target else label)
        except ValueError:   # already removed together with a parent node
            pass
    for link in code.filter_external_links(recursive=True):
        url = str(link.url).strip()
        try:
            if not url.lower().startswith(('http://', 'https://', '//')):
                continue
            url = 'https:' + url if url.startswith('//') else url
            if link.brackets and link.title is None:
                code.remove(link)   # [https://...] without a label: MediaWiki shows a number, we drop it
            else:
                code.replace(link, marked(str(link.title) if link.title is not None else url, ('url', url)))
        except ValueError:
            pass

    text = code.strip_code(normalize=True, collapse=True)
    text = re.sub(r"'{2,}", '', text)
    text = re.sub(r'[ \t]+', ' ', text).strip()

    # take the markers out again, remembering where each link ended up
    out, links, i = [], [], 0
    pos = 0   # in UTF-16 units
    pattern = re.compile(f'{LINK_OPEN}(.*?){LINK_MID}(\\d+){LINK_CLOSE}', re.S)
    for m in pattern.finditer(text):
        before = text[i:m.start()]
        out.append(before); pos += utf16_len(before)
        label = m.group(1)
        kind, value = destinations[int(m.group(2))]
        links.append({'start': pos, 'length': utf16_len(label), kind: value})
        out.append(label); pos += utf16_len(label)
        i = m.end()
    out.append(text[i:])
    plain = ''.join(out)
    for marker in (LINK_OPEN, LINK_MID, LINK_CLOSE):   # stray markers from nested links
        plain = plain.replace(marker, '')
    return plain, links

def clean(wikicode_or_str, expand_templates=False):
    return clean_with_links(wikicode_or_str, expand_templates)[0]

def links_in(code):
    out = []
    for l in code.filter_wikilinks():
        t = str(l.title).strip()
        if ':' in t and t.split(':', 1)[0].lower() in ('file', 'image', 'category', 'media'):
            continue
        out.append(t.split('#')[0].strip())
    return [t for t in dict.fromkeys(out) if t]

def tname(t):
    return str(t.name).strip().lower().replace('_', ' ')

def to_float(s):
    try:
        f = float(str(s).strip()); return None if f == 0 else f   # 0|0 is the wiki's "unknown" placeholder
    except ValueError:
        return None

def parse_page(title, text):
    text = re.sub(r'\{\{\s*(?:FULL|BASE)?PAGENAMEE?\s*\}\}', title, text)   # '''{{FULLPAGENAME}}''' -> the title
    # skip_style_tags: an unbalanced ''' (e.g. in Warsaw's infobox) otherwise swallows the rest of the page
    code = mwp.parse(text, skip_style_tags=True)
    page = {'title': title, 'infobox': None, 'lat': None, 'lng': None, 'is_in': [],
            'categories': [], 'links': links_in(code), 'sections': [], 'spots': []}

    for t in code.filter_templates(recursive=False):
        n = tname(t)
        if n.startswith('infobox') and page['infobox'] is None:
            fields = {}
            for p in t.params:
                k, raw = str(p.name).strip(), str(p.value).strip()
                if k == 'map':
                    m = MAP_RE.search(raw)
                    if m: page['lat'], page['lng'] = to_float(m.group(1)), to_float(m.group(2))
                    continue
                if k == 'hitch':   # <rating country='pl'/> -> 'pl'
                    m = re.search(r"country=['\"](\w+)", raw); fields[k] = m.group(1) if m else raw; continue
                ex = mwp.parse(expand(raw))
                fields[k] = {'text': clean(ex), 'links': links_in(ex), 'raw': raw} if '[[' in str(ex) else clean(ex)
            page['infobox'] = {'type': n[len('infobox'):].strip() or 'generic', 'fields': fields}
        elif n in ('isin', 'jestw'):   # {{JestW|Polska}} is the Polish wiki's {{IsIn}}
            page['is_in'] += [clean(p.value) for p in t.params if not p.showkey]

    for l in code.filter_wikilinks():
        t = str(l.title).strip()
        if t.lower().startswith('category:'):
            page['categories'].append(t.split(':', 1)[1].strip())

    # Sections: walk headings in order, remember the heading path ("Hitchhiking out > West towards X > Option 1")
    path = []
    for sec in code.get_sections(flat=True, include_lead=True):
        heads = sec.filter_headings(recursive=False)
        if heads:
            h = heads[0]; lvl = h.level; htext, hlinks = clean_with_links(h.title, expand_templates=True)
            path = [p for p in path if p[0] < lvl] + [(lvl, htext)]
            body = mwp.parse(str(sec)[len(str(h)):], skip_style_tags=True)
        else:
            lvl, htext, hlinks, body = 0, '', [], mwp.parse(str(sec), skip_style_tags=True)
        sp = ' > '.join(p[1] for p in path)
        btext, blinks = clean_with_links(body)
        page['sections'].append({'level': lvl, 'title': htext, 'path': sp, 'text': btext,
                                 'title_links': hlinks, 'links': blinks, 'wikitext': str(body).strip()})
        for t in body.filter_templates(recursive=False):
            if tname(t) in ('coords', 'coord', 'geo'):
                vals = [str(p.value).strip() for p in t.params if not p.showkey]
                if len(vals) == 1 and vals[0].count(',') == 1:      # {{Coords|48.19, 16.26}}
                    vals = [v.strip() for v in vals[0].split(',')]
                vals = [v.replace(',', '.') for v in vals]           # {{Coords|59,44|17,90}}
                if len(vals) >= 2 and to_float(vals[0]) and to_float(vals[1]):
                    page['spots'].append({'section': sp, 'lat': to_float(vals[0]), 'lng': to_float(vals[1]),
                                          'description': clean(body)[:2000]})
    page['text'] = '\n\n'.join(s['text'] for s in page['sections'] if s['text'])
    return page

# ---------- run ----------
os.makedirs(outdir, exist_ok=True)
import tempfile, shutil
final_db = os.path.join(outdir, 'hitchwiki.sqlite')
dbp = os.path.join(tempfile.mkdtemp(), 'hitchwiki.sqlite')   # build locally; some synced/mounted folders can't lock SQLite
db = sqlite3.connect(dbp)
db.executescript("""
CREATE TABLE pages(id INTEGER PRIMARY KEY, title TEXT UNIQUE, infobox_type TEXT, country TEXT,
                   lat REAL, lng REAL, is_in TEXT, text TEXT, wikitext TEXT, updated TEXT);
CREATE TABLE redirects(title TEXT PRIMARY KEY, target TEXT);
CREATE TABLE infobox_fields(page_id INTEGER, name TEXT, value TEXT, links TEXT);
CREATE TABLE sections(page_id INTEGER, idx INTEGER, level INTEGER, title TEXT, path TEXT, text TEXT, wikitext TEXT);
CREATE TABLE spots(page_id INTEGER, section TEXT, lat REAL, lng REAL, description TEXT);
CREATE TABLE links(page_id INTEGER, target TEXT);
-- where links sit in sections.text / sections.title; start + length are UTF-16 offsets (NSRange in Swift)
CREATE TABLE section_links(page_id INTEGER, section_idx INTEGER, in_heading INTEGER, start INTEGER, length INTEGER, target TEXT, url TEXT);
CREATE TABLE categories(page_id INTEGER, name TEXT);
CREATE TABLE templates(title TEXT PRIMARY KEY, wikitext TEXT);
CREATE VIRTUAL TABLE pages_fts USING fts5(title, text, content='pages', content_rowid='id');
""")
for p in mwxml.Dump.from_file(open(src, encoding='utf-8')):
    if p.namespace == 10:
        for r in p: TEMPLATES[tkey(p.title.split(':', 1)[1])] = r.text or ''
    elif p.namespace == 0:
        if p.redirect: REDIRECTS[norm_title(p.title)] = p.redirect
        else: ARTICLES.add(norm_title(p.title))
n = 0
newest_edit = ''   # YYYYMMDDHHMM of the latest revision, the default data version
with open(os.path.join(outdir, 'pages.jsonl'), 'w', encoding='utf-8') as jl:
    for p in mwxml.Dump.from_file(open(src, encoding='utf-8')):
        rev = None
        for r in p: rev = r
        if rev is None: continue
        if rev.timestamp is not None:
            newest_edit = max(newest_edit, rev.timestamp.strftime('%Y%m%d%H%M'))
        text = rev.text or ''
        if p.namespace == 10:
            db.execute('INSERT OR REPLACE INTO templates VALUES(?,?)', (p.title, text)); continue
        if p.namespace != 0: continue
        if p.redirect:
            db.execute('INSERT OR REPLACE INTO redirects VALUES(?,?)', (p.title, p.redirect)); continue
        d = parse_page(p.title, text); d['id'] = p.id; d['updated'] = str(rev.timestamp)
        jl.write(json.dumps(d, ensure_ascii=False) + '\n')
        ib = d['infobox'] or {}
        country = (ib.get('fields') or {}).get('country')
        country = country['text'] if isinstance(country, dict) else country
        db.execute('INSERT INTO pages VALUES(?,?,?,?,?,?,?,?,?,?)',
                   (p.id, p.title, ib.get('type'), country, d['lat'], d['lng'], json.dumps(d['is_in']),
                    d['text'], text, d['updated']))
        for k, v in (ib.get('fields') or {}).items():
            db.execute('INSERT INTO infobox_fields VALUES(?,?,?,?)', (p.id, k, v['text'] if isinstance(v, dict) else v,
                       json.dumps(v['links']) if isinstance(v, dict) else None))
        for i, s in enumerate(d['sections']):
            db.execute('INSERT INTO sections VALUES(?,?,?,?,?,?,?)', (p.id, i, s['level'], s['title'], s['path'], s['text'], s['wikitext']))
            for in_heading, links in ((1, s['title_links']), (0, s['links'])):
                db.executemany('INSERT INTO section_links VALUES(?,?,?,?,?,?,?)',
                               [(p.id, i, in_heading, l['start'], l['length'], l.get('target'), l.get('url')) for l in links])
        db.executemany('INSERT INTO spots VALUES(?,?,?,?,?)', [(p.id, s['section'], s['lat'], s['lng'], s['description']) for s in d['spots']])
        db.executemany('INSERT INTO links VALUES(?,?)', [(p.id, l) for l in d['links']])
        db.executemany('INSERT INTO categories VALUES(?,?)', [(p.id, c) for c in d['categories']])
        n += 1
db.execute("INSERT INTO pages_fts(pages_fts) VALUES('rebuild')")

# ---------- wikis without infoboxes (e.g. Polish) ----------
# The app finds countries by infobox_type = 'country', places near the user by their coordinates and a
# place's country by pages.country. The Polish wiki has no infoboxes, so fill those in:
#   country    a page titled like a country ("Polska", "Niemcy": CLDR names via babel) or a UK nation
#              ("Szkocja", "Anglia"), as Hitchwiki treats those as countries too; its code ("pl", "gb-sct")
#              goes into a `hitch` field, which the app turns into a flag
#   location   any other page with coordinates
#   lat/lng    from the English page with the same title (--gazetteer), else the middle of the page's spots
#   country    by following IsIn/JestW upwards (Kraków -> małopolskie -> Polska). Many pages copied from the
#              English wiki still say {{IsIn|Scotland}}, so English country names count too; last resort is
#              the country of the English page with the same title.
if _args.language != 'en':
    # UK nations: English name, then names in other languages
    NATIONS = {'gb-eng': ['England', 'Anglia'], 'gb-sct': ['Scotland', 'Szkocja'],
               'gb-wls': ['Wales', 'Walia'], 'gb-nir': ['Northern Ireland', 'Irlandia Północna']}
    local_names, name_codes = {}, {}   # lower-case name -> code; local_names only in this wiki's language
    try:
        from babel import Locale
        for lang in (_args.language, 'en'):
            for code, name in Locale(lang).territories.items():
                if len(code) == 2 and code.isalpha():
                    name_codes.setdefault(name.lower(), code.lower())
                    if lang == _args.language:
                        local_names[name.lower()] = code.lower()
    except Exception as e:   # babel missing: only the names below
        print('babel unavailable, few countries detected:', e)
    # Spellings the English wiki uses that CLDR doesn't
    for name, code in {'usa': 'us', 'united states of america': 'us', 'uk': 'gb', 'great britain': 'gb',
                       'the netherlands': 'nl', 'holland': 'nl', 'czech republic': 'cz', 'republic of ireland': 'ie',
                       'turkey': 'tr', 'ivory coast': 'ci', 'macedonia': 'mk', 'republic of the congo': 'cg',
                       'democratic republic of the congo': 'cd', 'swaziland': 'sz', 'burma': 'mm', 'east timor': 'tl',
                       'vatican city': 'va', 'cape verde': 'cv'}.items():
        name_codes.setdefault(name, code)
    for code, names in NATIONS.items():
        for name in names:
            name_codes[name.lower()] = code
            local_names[name.lower()] = code

    def code_for(name):
        return name_codes.get(re.sub(r'\s+', ' ', str(name)).strip().lower()) if name else None

    gazetteer = sqlite3.connect(_args.gazetteer) if _args.gazetteer else None
    def english_position(title):
        if gazetteer is None:
            return None
        return gazetteer.execute("""
            SELECT lat, lng FROM pages WHERE title = ?1 COLLATE NOCASE AND lat IS NOT NULL
            UNION ALL
            SELECT p.lat, p.lng FROM redirects r JOIN pages p ON p.title = r.target
            WHERE r.title = ?1 COLLATE NOCASE AND p.lat IS NOT NULL LIMIT 1""", (title,)).fetchone()

    def english_country_position(code):
        """Where the English wiki puts the country with `code`."""
        if gazetteer is None:
            return None
        if code in NATIONS:
            return english_position(NATIONS[code][0])
        return gazetteer.execute("""SELECT p.lat, p.lng FROM infobox_fields f JOIN pages p ON p.id = f.page_id
                                    WHERE f.name = 'hitch' AND lower(f.value) = ? AND p.lat IS NOT NULL LIMIT 1""",
                                 ('uk' if code == 'gb' else code,)).fetchone()

    def english_country(title):
        """The `country` of the English page with this title (or a redirect to it), e.g. 'Scotland'."""
        if gazetteer is None:
            return None
        row = gazetteer.execute("""
            SELECT country FROM pages WHERE title = ?1 COLLATE NOCASE
            UNION ALL
            SELECT p.country FROM redirects r JOIN pages p ON p.title = r.target WHERE r.title = ?1 COLLATE NOCASE
            LIMIT 1""", (title,)).fetchone()
        return row[0] if row else None

    rows = db.execute('SELECT id, title, is_in, lat, lng FROM pages WHERE infobox_type IS NULL').fetchall()
    parents = {title: json.loads(is_in or '[]') for _, title, is_in, _, _ in rows}
    countries, country_by_code = {}, {}
    # Pages named in this wiki's language first, so "Wielka Brytania" wins over a stray "United Kingdom" page
    for page_id, title, _, _, _ in sorted(rows, key=lambda r: r[1].lower() not in local_names):
        code = code_for(title)
        if code and code not in country_by_code:
            countries[title] = code
            country_by_code[code] = title
            db.execute("UPDATE pages SET infobox_type = 'country', country = ? WHERE id = ?", (title, page_id))
            db.execute('INSERT INTO infobox_fields VALUES(?,?,?,?)', (page_id, 'hitch', code, None))

    def country_of(name, depth=0):
        """The country page for a page or an IsIn value, following IsIn/JestW upwards."""
        if name in countries:
            return name
        code = code_for(name)   # an IsIn value naming a country, possibly in English ("Scotland")
        if code in country_by_code:
            return country_by_code[code]
        if depth > 4:
            return None
        for parent in parents.get(name, []):
            found = country_of(resolve_link(parent) or parent, depth + 1)
            if found:
                return found
        return None

    located = borrowed = 0
    for page_id, title, _, lat, lng in rows:
        if lat is None:
            position = english_country_position(countries[title]) if title in countries else english_position(title)
            if position:
                borrowed += 1
            else:
                spots = db.execute('SELECT lat, lng FROM spots WHERE page_id = ?', (page_id,)).fetchall()
                position = (sum(s[0] for s in spots) / len(spots), sum(s[1] for s in spots) / len(spots)) if spots else None
            if position:
                db.execute('UPDATE pages SET lat = ?, lng = ? WHERE id = ?', (position[0], position[1], page_id))
                lat = position[0]
        if title in countries:
            continue
        country = country_of(title) or country_by_code.get(code_for(english_country(title)))
        if country:
            db.execute('UPDATE pages SET country = ? WHERE id = ?', (country, page_id))
        if lat is not None:
            located += 1
            db.execute("UPDATE pages SET infobox_type = 'location' WHERE id = ?", (page_id,))
    print(f'no-infobox wiki: {len(countries)} countries, {located} located places ({borrowed} positions from the gazetteer)')

# Version info the app reads to decide whether a downloaded database is newer / compatible.
# Bump SCHEMA_VERSION whenever tables or columns the app reads change (and the app's supportedSchemaVersion with it).
import datetime
SCHEMA_VERSION = 1
now = datetime.datetime.now(datetime.timezone.utc)
# Default: the newest edit in the dump, so the same dump always gives the same version wherever it's built.
version = max(_args.version or int(newest_edit or now.strftime('%Y%m%d%H%M')), _args.min_version)
db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)')
db.executemany('INSERT INTO meta VALUES(?,?)', [
    ('schema_version', str(SCHEMA_VERSION)),
    ('version', str(version)),
    ('generated_at', now.strftime('%Y-%m-%dT%H:%M:%SZ')),
    ('source_sha256', _args.source_sha256),
    ('language', _args.language),
    ('pages', str(n)),
    ('spots', str(db.execute('SELECT COUNT(*) FROM spots').fetchone()[0])),
])
print('version:', version, 'schema:', SCHEMA_VERSION, 'language:', _args.language)
# What the app keys on (infobox types such as 'country'), to spot a wiki that names its templates differently.
for row in db.execute('SELECT infobox_type, COUNT(*) FROM pages GROUP BY 1 ORDER BY 2 DESC LIMIT 12'):
    print('  infobox', row[0], row[1])
db.executescript("CREATE INDEX i1 ON infobox_fields(page_id); CREATE INDEX i2 ON sections(page_id); "
                 "CREATE INDEX i3 ON spots(page_id); CREATE INDEX i4 ON links(target); CREATE INDEX i5 ON categories(name); CREATE INDEX i6 ON section_links(page_id);")
db.commit(); db.execute('VACUUM'); db.close()
shutil.copyfile(dbp, final_db)
if _args.app_db:
    slim = sqlite3.connect(dbp)
    # the app builds page text from `sections`, so drop the raw wikitext, the duplicate page text and the search index
    slim.executescript("UPDATE pages SET wikitext = NULL, text = NULL; UPDATE sections SET wikitext = NULL; "
                       "DELETE FROM templates; DROP TABLE pages_fts; VACUUM;")
    slim.close()
    shutil.copyfile(dbp, _args.app_db)
    print('app db:', _args.app_db, os.path.getsize(_args.app_db) // 1_000_000, 'MB')
print('articles:', n)
