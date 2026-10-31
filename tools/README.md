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

## Automatic updates (GitHub Actions → app)

`.github/workflows/update-database.yml` rebuilds the database every Monday (or on demand from the Actions tab)
and publishes it to the release **`database-latest`**:

1. Downloads the dump from the `dump_url` input, else the `HITCHWIKI_DUMP_URL` repository variable,
   else the largest file uploaded to a release tagged **`dump-source`** (`.xml`, `.xml.gz`, `.xml.bz2` or `.7z`).
2. Skips the rest if the dump is identical to the last published one.
3. Runs `slim_dump.py` → `extract.py` (writes a `meta` table with `version` = YYYYMMDDHHMM and `schema_version`)
   → `package_database.py` (raw-DEFLATE copy, ~8 MB, plus `manifest.json` with size and SHA-256).

Free on public repositories. To set it up: add the dump URL as a repository variable, or create the `dump-source`
release and attach the dump, then run the workflow once by hand.

The app (`Networking/DatabaseUpdater.swift`, `Shared/DatabaseSync.swift`) downloads `manifest.json` when it opens
or returns to the foreground (at most every 30 minutes). If `version` is newer and `schema_version` matches
`HitchwikiDatabase.supportedSchemaVersion`, it downloads the database in the background (not on Low Data Mode),
checks it, swaps it in and shows a small "Syncing Hitchwiki data…" banner. Offline it silently keeps the data it has.

**When you change the tables or columns the app reads**, bump `SCHEMA_VERSION` in `extract.py` and
`supportedSchemaVersion` in `HitchwikiDatabase.swift` together, so older app versions don't download a database they can't read.
