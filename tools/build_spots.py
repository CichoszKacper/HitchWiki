#!/usr/bin/env python3
"""Build hitchspots.sqlite, the app's database of hitchhiking spots, from the Hitchhiking Rides Dataset.

The dataset (rides.parquet) is published weekly by maps.hitchwiki.org at
https://huggingface.co/datasets/Hitchwiki/hitchhiking-rides-dataset and holds every ride logged on
maps.hitchwiki.org, hitchmap.com, the old Hitchwiki Maps and liftershalte.info since 2005.

Usage:
    python3 build_spots.py <rides.parquet> <out hitchspots.sqlite> [--min-version N] [--source-sha256 HEX]

A spot is every ride that started at the same place (the first stop of a ride, rounded to ~1 m, which is
how Hitchmap groups them: riders pick an existing spot on the map). Per spot the database keeps the
average rating, the median wait, the number of rides and the comments.

Personal data is left out on purpose: no gender, age, origin, travel reasons, vehicles or routes, and dates
only to the month. A comment keeps the nickname it was published under, because its CC BY-SA licence
requires crediting the author. Rides whose licence isn't one we know (e.g. "xxx") are dropped.

The output is itself an ODbL database (a Derivative Database of the rides dataset), so it is published
as-is next to the app (see .github/workflows/update-database.yml).

Tables:
    meta(key, value)        version, schema_version, generated_at, source_sha256, spots, rides, comments
    spots(id, lat, lng, rides, rating, wait_minutes, wait_count, last_ride, sources, licenses)
    comments(spot_id, position, date, nickname, rating, wait_minutes, text, source, license)
"""
import argparse, json, os, re, sqlite3, statistics, sys
from collections import defaultdict
from datetime import datetime, timezone

import pyarrow.parquet as pq

# Bump together with SpotsDatabase.supportedSchemaVersion in the app when tables or columns change.
SCHEMA_VERSION = 1

# Licences the rides dataset uses that allow redistribution; anything else is left out.
KNOWN_LICENSES = {'odbl', 'cc-by-sa-4.0', 'cc-by-4.0'}
# Longer than a day is a typo or a night's sleep, not a wait.
MAX_WAIT_MINUTES = 24 * 60
ANONYMOUS = {'', 'anonymous', 'anon', 'none', 'null'}

DURATION = re.compile(r'^P(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$')
TAG = re.compile(r'<[^>]{0,40}>')


def minutes(duration):
    """ISO 8601 duration ("PT90M", "PT1H30M") in whole minutes, or None."""
    if not duration:
        return None
    match = DURATION.match(duration.strip())
    if not match or not any(match.groups()):
        return None
    days, hours, mins, secs = (float(group) if group else 0.0 for group in match.groups())
    total = round(days * 1440 + hours * 60 + mins + secs / 60)
    return total if 0 <= total <= MAX_WAIT_MINUTES else None


def month(timestamp):
    """'2024-03-17T10:00:00' -> '2024-03'."""
    if not timestamp or not re.match(r'^\d{4}-\d{2}', timestamp):
        return None
    return timestamp[:7]


def clean_text(text):
    if not text:
        return None
    text = TAG.sub('', text).replace('\r\n', '\n').replace('\r', '\n')
    text = re.sub(r'[ \t]+\n', '\n', text)
    text = re.sub(r'\n{3,}', '\n\n', text).strip()
    return text or None


def nickname(hitchhikers_json):
    try:
        people = json.loads(hitchhikers_json) if hitchhikers_json else []
    except ValueError:
        return None
    for person in people or []:
        name = (person or {}).get('nickname')
        if name and name.strip().lower() not in ANONYMOUS:
            return name.strip()
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('rides', help='rides.parquet from the Hitchhiking Rides Dataset')
    ap.add_argument('output', help='hitchspots.sqlite to write (replaced if it exists)')
    ap.add_argument('--min-version', type=int, default=0, help='version must be at least this (last published + 1)')
    ap.add_argument('--source-sha256', default='', help='checksum of rides.parquet, stored in meta')
    args = ap.parse_args()

    columns = ['stops', 'rating', 'hitchhikers', 'comment', 'license', 'source', 'submission_time']
    rows = pq.read_table(args.rides, columns=columns).to_pylist()

    spots = defaultdict(lambda: {'ratings': [], 'waits': [], 'dates': [], 'sources': set(), 'licenses': set(), 'comments': []})
    skipped = defaultdict(int)
    for row in rows:
        license_ = (row['license'] or '').strip().lower()
        if license_ not in KNOWN_LICENSES:
            skipped['unknown licence'] += 1
            continue
        try:
            first = json.loads(row['stops'])[0]
            location = first['location']
            latitude, longitude = float(location['latitude']), float(location['longitude'])
        except (ValueError, TypeError, KeyError, IndexError):
            skipped['no position'] += 1
            continue
        if not (-90 <= latitude <= 90 and -180 <= longitude <= 180) or (abs(latitude) < 1e-6 and abs(longitude) < 1e-6):
            skipped['bad position'] += 1
            continue

        spot = spots[(round(latitude, 5), round(longitude, 5))]
        rating = row['rating']
        rating = int(round(rating)) if rating is not None and 1 <= rating <= 5 else None
        wait = minutes(first.get('waiting_duration'))
        date = month(first.get('departure_time')) or month(row['submission_time'])
        source = (row['source'] or '').strip() or 'unknown'
        if rating is not None:
            spot['ratings'].append(rating)
        if wait is not None:
            spot['waits'].append(wait)
        if date:
            spot['dates'].append(date)
        spot['sources'].add(source)
        spot['licenses'].add(license_)

        text = clean_text(row['comment'])
        if text:
            spot['comments'].append((date, nickname(row['hitchhikers']), rating, wait, text, source, license_))
        spot.setdefault('rides', 0)
        spot['rides'] += 1

    if os.path.exists(args.output):
        os.remove(args.output)
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    db = sqlite3.connect(args.output)
    db.executescript('''
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE spots (
            id INTEGER PRIMARY KEY,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            rides INTEGER NOT NULL,       -- rides logged here
            rating REAL,                  -- average, 1 (senseless) to 5 (very good)
            wait_minutes INTEGER,         -- median of the waits people logged
            wait_count INTEGER NOT NULL,  -- how many rides logged a wait
            last_ride TEXT,               -- YYYY-MM
            sources TEXT NOT NULL,        -- comma separated, e.g. "hitchmap.com,hitchwiki.org"
            licenses TEXT NOT NULL        -- comma separated, e.g. "cc-by-sa-4.0,odbl"
        );
        CREATE TABLE comments (
            spot_id INTEGER NOT NULL REFERENCES spots(id),
            position INTEGER NOT NULL,    -- 0 = newest
            date TEXT,                    -- YYYY-MM
            nickname TEXT,                -- NULL when posted anonymously
            rating INTEGER,
            wait_minutes INTEGER,
            text TEXT NOT NULL,
            source TEXT NOT NULL,
            license TEXT NOT NULL,
            PRIMARY KEY (spot_id, position)
        ) WITHOUT ROWID;
    ''')

    # West to east, then south to north: stable ids for an unchanged dataset, and nearby spots sit together on disk.
    spot_rows, comment_rows = [], []
    for spot_id, ((latitude, longitude), spot) in enumerate(sorted(spots.items()), start=1):
        ratings, waits = spot['ratings'], spot['waits']
        spot_rows.append((
            spot_id, latitude, longitude, spot['rides'],
            round(sum(ratings) / len(ratings), 2) if ratings else None,
            int(statistics.median(waits)) if waits else None, len(waits),
            max(spot['dates']) if spot['dates'] else None,
            ','.join(sorted(spot['sources'])), ','.join(sorted(spot['licenses'])),
        ))
        # Newest first; undated ones last.
        newest_first = sorted(spot['comments'], key=lambda c: c[0] or '', reverse=True)
        for position, comment in enumerate(newest_first):
            comment_rows.append((spot_id, position) + comment)

    db.executemany('INSERT INTO spots VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', spot_rows)
    db.executemany('INSERT INTO comments VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', comment_rows)
    db.executescript('''
        CREATE INDEX spots_position ON spots(lat, lng);
    ''')

    now = datetime.now(timezone.utc)
    version = max(int(now.strftime('%Y%m%d%H%M')), args.min_version)
    ride_count = sum(spot['rides'] for spot in spots.values())
    meta = {
        'kind': 'spots',
        'version': str(version),
        'schema_version': str(SCHEMA_VERSION),
        'generated_at': now.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'source': 'https://huggingface.co/datasets/Hitchwiki/hitchhiking-rides-dataset',
        'source_sha256': args.source_sha256,
        'license': 'ODbL-1.0 (database); comments CC BY-SA 4.0 or as given per row',
        'spots': str(len(spot_rows)),
        'rides': str(ride_count),
        'comments': str(len(comment_rows)),
    }
    db.executemany('INSERT INTO meta VALUES (?, ?)', meta.items())
    db.commit()
    db.execute('VACUUM')
    db.close()

    size = os.path.getsize(args.output) / 1e6
    print(f'{len(spot_rows)} spots, {ride_count} rides, {len(comment_rows)} comments -> {args.output} ({size:.1f} MB)')
    for reason, count in sorted(skipped.items()):
        print(f'skipped {count} rides: {reason}')
    if not spot_rows:
        sys.exit('No spots: is this the rides dataset?')


if __name__ == '__main__':
    main()
