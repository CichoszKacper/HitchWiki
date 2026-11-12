# Hitchwiki dump tools

Turns `HitchWiki/hitchwiki-full-en.xml` (790 MB, full edit history) into data that's easy to work with.

```sh
cd tools
python3 -m venv .venv && .venv/bin/pip install mwparserfromhell mwxml

# 1. Keep only the latest revision of articles (ns 0), templates (10) and categories (14): 790 MB -> 22 MB, ~7 s
python3 slim_dump.py ../HitchWiki/hitchwiki-full-en.xml output/hitchwiki-latest.xml          # --ns all to keep every namespace

# 2. Structured extraction: ~25 s. --app-db also refreshes the slim copy the iOS app bundles (~20 MB)
.venv/bin/python extract.py output/hitchwiki-latest.xml output/ --app-db ../HitchWiki/hitchwiki.sqlite
```

The app reads `HitchWiki/hitchwiki.sqlite` through `HitchWiki/Networking/HitchwikiDatabase.swift`.
That copy has no raw wikitext, duplicate page text or search index; the full `output/hitchwiki.sqlite` has everything.

## Outputs (`output/`, git-ignored)

| File | What |
|---|---|
| `hitchwiki-latest.xml` | Still a valid MediaWiki dump, so any MediaWiki tool reads it (WikiExtractor, importDump.php, ...) |
| `pages.jsonl` | One JSON object per article: `title, infobox{type, fields}, lat, lng, is_in, categories, links, sections[], spots[], text` |
| `hitchwiki.sqlite` | Same data in tables, ready for the iOS app (GRDB / SQLite.swift) |

SQLite tables: `pages` (title, infobox_type, country, lat, lng, plain text, wikitext), `infobox_fields`, `sections`
(with heading path like `Hitchhiking out > West towards Katowice > Option 1`), `spots` (lat/lng from `{{Coords}}` + the section it's in),
`links`, `categories`, `redirects`, `templates`, and `pages_fts` (FTS5 full-text search).

```sql
SELECT title, lat, lng FROM pages WHERE country = 'Poland' AND infobox_type LIKE '%location';
SELECT section, lat, lng FROM spots JOIN pages ON pages.id = spots.page_id WHERE title = 'Kraków';
SELECT title FROM pages_fts WHERE pages_fts MATCH 'mitfahrbank';
```

## Known limits
- Template expansion is light: `{{{1}}}`-style params are substituted, parser functions (`{{#if:}}`) aren't evaluated.
- ~4,900 of the ~5,900 `{{Coords}}` in articles are `0|0` placeholders on the wiki itself, so only ~870 spots have real coordinates.
- Highway tables (`{{ramp}}`, `{{gas}}`, `{{good}}`) are kept as wikitext in `sections.wikitext`, not yet parsed into rows.

## Languages

The app has one database per guide language. English is bundled with the app; Polish is downloaded when the
user picks it (first launch or Settings). Build a Polish one by hand with:

```sh
curl -L -o output/pl.xml.gz https://dumps.hitchwiki.org/hitchwiki-current-pl.xml.gz && gunzip -f output/pl.xml.gz
python3 slim_dump.py output/pl.xml output/hitchwiki-latest-pl.xml
.venv/bin/pip install babel
.venv/bin/python extract.py output/hitchwiki-latest-pl.xml output/pl --language pl \
    --gazetteer ../HitchWiki/hitchwiki.sqlite --app-db output/hitchwiki-pl.sqlite
```

The Polish wiki has no infoboxes, so for languages other than English `extract.py` fills in what the app needs:
pages titled like a country ("Polska", "Niemcy", names from CLDR via `babel`) become `country` pages with their flag code,
other pages with a position become `location`s, positions come from the English page with the same title (`--gazetteer`)
or the middle of the page's spots, and a place's country comes from `{{JestW}}`/`{{IsIn}}` or the English page.
With the October 2026 dump that gives 67 countries and 282 places with a position out of 569 articles.

`--language` is stored in the `meta` table; the app refuses a database whose language doesn't match the one it asked for.
`extract.py` prints the most common infobox types at the end: the app recognises countries by `infobox_type = 'country'`,
so check that line when adding a language.

## Hitchhiking spots (rides dataset)

The map also shows ~47,000 spots where people logged rides, with their rating, typical wait and comments.
They come from the [Hitchhiking Rides Dataset](https://huggingface.co/datasets/Hitchwiki/hitchhiking-rides-dataset)
(`rides.parquet`, published weekly by maps.hitchwiki.org: rides from maps.hitchwiki.org, Hitchmap, the old
Hitchwiki Maps and liftershalte.info since 2005) and go into their own database, the same for every guide language:

```sh
.venv/bin/pip install pyarrow
curl -L -o output/rides.parquet https://huggingface.co/datasets/Hitchwiki/hitchhiking-rides-dataset/resolve/main/rides.parquet
.venv/bin/python build_spots.py output/rides.parquet ../HitchWiki/hitchspots.sqlite   # ~5 s, ~19 MB
```

A spot is all rides that started at the same point (rounded to ~1 m, as Hitchmap groups them). Tables:
`spots` (lat, lng, rides, average rating 1–5, median wait in minutes, last ride month, sources, licences) and
`comments` (spot_id, newest first, month, nickname, rating, wait, text, source, licence), plus `meta` with
`kind = 'spots'`. The app reads it through `HitchWiki/Networking/SpotsDatabase.swift`.

What is left out on purpose: rides with an unknown licence (99 rows marked `xxx` in November 2026), and all personal
details beyond the nickname a comment was posted under (no gender, age, origin, routes or exact dates; months only).

**Licence.** The dataset is ODbL (with CC BY-SA 4.0 comments from the old Hitchwiki Maps), so `hitchspots.sqlite` is an
ODbL database too: the workflow publishes it as `hitchspots.sqlite.gz`, the map shows a visible credit, and Settings
explains the licences. When you change its tables, bump `SCHEMA_VERSION` in `build_spots.py` and
`SpotsDatabase.supportedSchemaVersion` together.

## Automatic updates (GitHub Actions → app)

`.github/workflows/update-database.yml` rebuilds the databases every Monday (or on demand from the Actions tab),
English first, then Polish, and publishes them to the release **`database-latest`**
(`manifest.json` + `hitchwiki-<version>.sqlite.deflate` for English, `manifest-pl.json` + `hitchwiki-pl-<version>.sqlite.deflate` for Polish,
`manifest-spots.json` + `hitchspots-<version>.sqlite.deflate` for the spots, rebuilt only when `rides.parquet` changed).
The Polish dump comes from https://dumps.hitchwiki.org/hitchwiki-current-pl.xml.gz unless the `dump_url_pl` input or the
`HITCHWIKI_DUMP_URL_PL` variable says otherwise. For English:

1. Downloads the dump from the `dump_url` input, else the `HITCHWIKI_DUMP_URL` repository variable,
   else the largest file uploaded to a release tagged **`dump-source`** (`.xml`, `.xml.gz`, `.xml.bz2` or `.7z`).
2. Skips the rest if the dump is identical to the last published one.
3. Runs `slim_dump.py` → `extract.py` (writes a `meta` table with `version` = YYYYMMDDHHMM and `schema_version`)
   → `package_database.py` (raw-DEFLATE copy, ~8 MB, plus `manifest.json` with size and SHA-256).

Free on public repositories. To set it up: add the dump URL as a repository variable, or create the `dump-source`
release and attach the dump, then run the workflow once by hand.

The app (`Networking/DatabaseUpdater.swift`, `Shared/DatabaseSync.swift`) downloads `manifest.json` (and `manifest-spots.json`) when it opens
or returns to the foreground (at most every 30 minutes). If `version` is newer and `schema_version` matches
`HitchwikiDatabase.supportedSchemaVersion`, it downloads the database in the background (not on Low Data Mode),
checks it, swaps it in and shows a small "Updating the guide…" banner. Offline it silently keeps the data it has.

**When you change the tables or columns the app reads**, bump `SCHEMA_VERSION` in `extract.py` and
`supportedSchemaVersion` in `HitchwikiDatabase.swift` together, so older app versions don't download a database they can't read.
