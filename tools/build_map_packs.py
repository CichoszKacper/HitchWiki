#!/usr/bin/env python3
"""Cut one offline map file per country from OpenFreeMap's planet, for the app's offline maps.

Usage:
    python3 build_map_packs.py <planet.mbtiles> <out dir> [--countries PL,DE,CZ] [--maxzoom 13]

<planet.mbtiles> is OpenFreeMap's weekly planet build (about 105 GB):
    https://btrfs.openfreemap.com/areas/planet/<version>/tiles.mbtiles
The newest finished <version> is listed in https://btrfs.openfreemap.com/files.txt (a run counts once its
`done` file is there). The app loads the same tiles online, so downloaded and online maps match exactly.

Writes:
    <out dir>/<CC>.mbtiles   one per country (ISO code), tiles from zoom 0 to --maxzoom that touch the country
                             or the 10 km around its border
    <out dir>/index.json     the catalogue the app reads: version, maxzoom, and per country its name,
                             bounding box, size and file name

Upload everything in <out dir> to the folder `HWMapPacksBaseURL` (Info.plist) points at, e.g. with rclone:
    rclone copy <out dir> r2:<bucket>/maps --progress
Upload the .mbtiles files before index.json, so the app never sees a catalogue whose files aren't there yet.

Country shapes come from Natural Earth (public domain), downloaded on first run.
Needs: pip install shapely
"""
import argparse, json, math, os, re, sqlite3, sys, urllib.request

try:
    from shapely.geometry import box, shape
    from shapely.prepared import prep
except ImportError:
    sys.exit('Needs shapely: pip install shapely')

NATURAL_EARTH = ('https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/'
                 'ne_50m_admin_0_countries.geojson')
# About 10 km, so roads and towns just across the border are on the map too.
BORDER_BUFFER_DEGREES = 0.1

ap = argparse.ArgumentParser()
ap.add_argument('planet', help="OpenFreeMap's planet tiles.mbtiles")
ap.add_argument('outdir')
ap.add_argument('--countries', help='comma-separated ISO codes, e.g. PL,DE (default: all)')
ap.add_argument('--maxzoom', type=int, default=13,
                help='highest zoom to include (default 13; 14 is OpenFreeMap\'s highest and about 4x the size)')
ap.add_argument('--version', help="version for index.json (default: the planet's folder name or metadata)")
ap.add_argument('--shapes', default=os.path.join(os.path.dirname(__file__), 'output', 'ne_50m_admin_0_countries.geojson'))
args = ap.parse_args()

os.makedirs(args.outdir, exist_ok=True)
os.makedirs(os.path.dirname(args.shapes), exist_ok=True)
if not os.path.exists(args.shapes):
    print('Downloading country shapes from Natural Earth...')
    urllib.request.urlretrieve(NATURAL_EARTH, args.shapes)

planet = sqlite3.connect(f'file:{args.planet}?mode=ro', uri=True)
planet_meta = dict(planet.execute('SELECT name, value FROM metadata'))
folder = os.path.basename(os.path.dirname(os.path.abspath(args.planet)))
# OpenFreeMap's runs are named like 20261101_080013_pt; keep the planet in a folder with that name.
version = args.version or (folder if re.match(r'^\d{8}_', folder) else planet_meta.get('version', 'unknown'))

wanted = {c.strip().upper() for c in args.countries.split(',')} if args.countries else None


def country_code(properties):
    # Natural Earth leaves ISO_A2 as -99 for a few countries (France, Norway, Kosovo); ISO_A2_EH has them.
    for key in ('ISO_A2_EH', 'ISO_A2', 'WB_A2'):
        code = properties.get(key)
        if code and code != '-99' and len(code) == 2:
            return code.upper()
    return None


def lon_to_x(lon, n):
    return int(math.floor((lon + 180) / 360 * n))


def lat_to_y(lat, n):
    lat = max(min(lat, 85.0511), -85.0511)
    rad = math.radians(lat)
    return int(math.floor((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * n))


def tile_box(z, x, y):
    n = 2 ** z
    west = x / n * 360 - 180
    east = (x + 1) / n * 360 - 180
    north = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))
    south = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + 1) / n))))
    return box(west, south, east, north)


def tiles_for(area, maxzoom):
    """Every z/x/y up to maxzoom whose tile touches `area`."""
    prepared = prep(area)
    west, south, east, north = area.bounds
    for z in range(maxzoom + 1):
        n = 2 ** z
        x0, x1 = max(lon_to_x(west, n), 0), min(lon_to_x(east, n), n - 1)
        y0, y1 = max(lat_to_y(north, n), 0), min(lat_to_y(south, n), n - 1)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                if z < 6 or prepared.intersects(tile_box(z, x, y)):
                    yield z, x, y


def main_part_bbox(geometry):
    """Bounding box of the biggest piece, so France's box is France and not France plus French Guiana."""
    parts = list(getattr(geometry, 'geoms', [geometry]))
    biggest = max(parts, key=lambda part: part.area)
    return [round(value, 4) for value in biggest.buffer(BORDER_BUFFER_DEGREES).bounds]


with open(args.shapes) as f:
    features = json.load(f)['features']

packs = []
for feature in sorted(features, key=lambda f: f['properties'].get('NAME_EN') or f['properties'].get('NAME', '')):
    properties = feature['properties']
    code = country_code(properties)
    if not code or (wanted and code not in wanted):
        continue
    name = properties.get('NAME_EN') or properties.get('NAME') or code
    area = shape(feature['geometry']).buffer(BORDER_BUFFER_DEGREES)
    path = os.path.join(args.outdir, f'{code}.mbtiles')
    if os.path.exists(path):
        os.remove(path)

    out = sqlite3.connect(path)
    out.executescript('''
        CREATE TABLE metadata (name TEXT, value TEXT);
        CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);
        CREATE TEMP TABLE wanted (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER,
                                  PRIMARY KEY (zoom_level, tile_column, tile_row)) WITHOUT ROWID;
    ''')
    # MBTiles counts rows from the bottom (TMS).
    out.executemany('INSERT OR IGNORE INTO wanted VALUES (?, ?, ?)',
                    ((z, x, (2 ** z) - 1 - y) for z, x, y in tiles_for(area, args.maxzoom)))
    out.execute('ATTACH DATABASE ? AS planet', (f'file:{args.planet}?mode=ro',))
    out.execute('''
        INSERT INTO tiles
        SELECT p.zoom_level, p.tile_column, p.tile_row, p.tile_data
        FROM wanted w JOIN planet.tiles p
          ON p.zoom_level = w.zoom_level AND p.tile_column = w.tile_column AND p.tile_row = w.tile_row
    ''')
    out.commit()
    out.execute('DETACH DATABASE planet')
    west, south, east, north = area.bounds
    metadata = {
        'name': name,
        'format': 'pbf',
        'type': 'baselayer',
        'minzoom': '0',
        'maxzoom': str(args.maxzoom),
        'bounds': f'{west:.4f},{max(south, -85.05):.4f},{east:.4f},{min(north, 85.05):.4f}',
        'version': version,
        'attribution': '© OpenFreeMap © OpenMapTiles © OpenStreetMap contributors',
    }
    if 'json' in planet_meta:   # vector layer list, as in the planet
        metadata['json'] = planet_meta['json']
    out.executemany('INSERT INTO metadata VALUES (?, ?)', metadata.items())
    out.execute('CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row)')
    out.commit()
    count = out.execute('SELECT COUNT(*) FROM tiles').fetchone()[0]
    out.close()
    # Compact: the temporary table and index building leave free pages behind.
    sqlite3.connect(path).execute('VACUUM')

    size = os.path.getsize(path)
    packs.append({'id': code, 'name': name, 'bbox': main_part_bbox(shape(feature['geometry'])), 'bytes': size,
                  'file': f'{code}.mbtiles'})
    print(f'{code} {name}: {count:,} tiles, {size / 1e6:.0f} MB')

# Keep countries cut in earlier runs (when building a few at a time with --countries).
index_path = os.path.join(args.outdir, 'index.json')
if wanted and os.path.exists(index_path):
    with open(index_path) as f:
        previous = json.load(f)
    if previous.get('version') == version:
        built = {pack['id'] for pack in packs}
        packs += [pack for pack in previous['packs'] if pack['id'] not in built]

packs.sort(key=lambda pack: pack['name'])
with open(index_path, 'w') as f:
    json.dump({'version': version, 'maxzoom': args.maxzoom, 'packs': packs}, f, ensure_ascii=False, indent=1)
print(f'{len(packs)} countries, {sum(p["bytes"] for p in packs) / 1e9:.1f} GB in total -> {index_path}')
