#!/usr/bin/env python3
"""Make one offline map file per country from OpenFreeMap's planet, for the app's offline maps.

Only each country's tiles are downloaded, not the whole planet (~90 GB): OpenFreeMap publishes the planet
as one PMTiles file, and `pmtiles extract` reads just the parts it needs over HTTP. With --upload, each
country goes to R2 as soon as it's made and is deleted locally, so the disk only ever holds one country.

Usage:
    python3 build_map_packs.py <out dir> [--countries PL,DE,CZ] [--maxzoom 13] [--upload r2:<bucket>/maps]

Writes:
    <out dir>/<CC>.mbtiles   one per country (ISO code): tiles from zoom 0 to --maxzoom that touch the country
                             or the 10 km around its border (deleted again after uploading, with --upload)
    <out dir>/index.json     the catalogue the app reads: version, maxzoom, and per country its name,
                             bounding box, size and file name (uploaded last, with --upload)

Without --upload, copy the folder to where `HWMapPacksBaseURL` (Info.plist) points, .mbtiles files first:
    rclone copy <out dir> r2:<bucket>/maps --exclude index.json && rclone copy <out dir>/index.json r2:<bucket>/maps

Runs can be stopped and started again: countries already in index.json for the same planet version are skipped
(--force makes them again). A newer planet version makes everything again, and the app offers the update.

Needs: brew install pmtiles rclone; pip install shapely pmtiles
Country shapes come from Natural Earth (public domain), downloaded on first run.
"""
import argparse, json, math, os, re, shutil, sqlite3, subprocess, sys, tempfile, urllib.request

try:
    from shapely.geometry import mapping, shape
    from pmtiles.reader import MmapSource, Reader, all_tiles
except ImportError:
    sys.exit('Needs: pip install shapely pmtiles')

OPENFREEMAP = 'https://btrfs.openfreemap.com'
NATURAL_EARTH = ('https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/'
                 'ne_50m_admin_0_countries.geojson')
USER_AGENT = 'HitchWise-map-builder/1.0 (offline maps for the HitchWise iOS app)'
# About 10 km, so roads and towns just across the border are on the map too.
BORDER_BUFFER_DEGREES = 0.1

ap = argparse.ArgumentParser()
ap.add_argument('outdir')
ap.add_argument('--countries', help='comma-separated ISO codes, e.g. PL,DE (default: all)')
ap.add_argument('--maxzoom', type=int, default=13,
                help="highest zoom to include (default 13; 14 is OpenFreeMap's highest and about 4x the size)")
ap.add_argument('--planet', help='PMTiles planet URL or file (default: the newest OpenFreeMap build)')
ap.add_argument('--upload', metavar='REMOTE', help='rclone destination, e.g. r2:hitchwise-maps/maps')
ap.add_argument('--force', action='store_true', help='make countries again even if index.json has them')
ap.add_argument('--shapes', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'output',
                                                 'ne_50m_admin_0_countries.geojson'))
args = ap.parse_args()

for tool in ['pmtiles'] + (['rclone'] if args.upload else []):
    if not shutil.which(tool):
        sys.exit(f'Needs {tool}: brew install {tool}')


def fetch(url):
    request = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
    with urllib.request.urlopen(request) as response:
        return response.read()


def latest_planet():
    """The newest planet run that has finished (has its `done` file) and a PMTiles file."""
    files = fetch(f'{OPENFREEMAP}/files.txt').decode().split()
    runs = {}
    for path in files:
        match = re.match(r'areas/planet/([^/]+)/(done|tiles\.pmtiles)$', path)
        if match:
            runs.setdefault(match.group(1), set()).add(match.group(2))
    finished = sorted(run for run, names in runs.items() if names >= {'done', 'tiles.pmtiles'})
    if not finished:
        sys.exit('No finished planet build found in OpenFreeMap files.txt')
    return f'{OPENFREEMAP}/areas/planet/{finished[-1]}/tiles.pmtiles'


planet = args.planet or latest_planet()
match = re.search(r'/(\d{8}_[^/]+)/', planet)
version = match.group(1) if match else 'unknown'
print(f'Planet {version}: {planet}')

os.makedirs(args.outdir, exist_ok=True)
os.makedirs(os.path.dirname(args.shapes), exist_ok=True)
if not os.path.exists(args.shapes):
    print('Downloading country shapes from Natural Earth...')
    with open(args.shapes, 'wb') as f:
        f.write(fetch(NATURAL_EARTH))

wanted = {c.strip().upper() for c in args.countries.split(',')} if args.countries else None

# Countries made earlier from the same planet are kept (and skipped unless --force).
index_path = os.path.join(args.outdir, 'index.json')
done = {}
if os.path.exists(index_path):
    with open(index_path) as f:
        previous = json.load(f)
    if previous.get('version') == version and previous.get('maxzoom') == args.maxzoom:
        done = {pack['id']: pack for pack in previous['packs']}


def country_code(properties):
    # Natural Earth leaves ISO_A2 as -99 for a few countries (France, Norway, Kosovo); ISO_A2_EH has them.
    for key in ('ISO_A2_EH', 'ISO_A2', 'WB_A2'):
        code = properties.get(key)
        if code and code != '-99' and len(code) == 2:
            return code.upper()
    return None


def main_part_bbox(geometry):
    """Bounding box of the biggest piece, so France's box is France and not France plus French Guiana."""
    parts = list(getattr(geometry, 'geoms', [geometry]))
    biggest = max(parts, key=lambda part: part.area)
    return [round(value, 4) for value in biggest.buffer(BORDER_BUFFER_DEGREES).bounds]


def save_index():
    packs = sorted(done.values(), key=lambda pack: pack['name'])
    with open(index_path, 'w') as f:
        json.dump({'version': version, 'maxzoom': args.maxzoom, 'packs': packs}, f, ensure_ascii=False, indent=1)


def make_country(code, name, area, path):
    """Downloads the country's tiles and writes them as MBTiles (what the app reads)."""
    with tempfile.TemporaryDirectory() as scratch:
        region = os.path.join(scratch, 'region.geojson')
        with open(region, 'w') as f:
            json.dump({'type': 'Feature', 'properties': {}, 'geometry': mapping(area)}, f)
        extract = os.path.join(scratch, f'{code}.pmtiles')
        # 4 parallel downloads at most, as OpenFreeMap asks.
        subprocess.run(['pmtiles', 'extract', planet, extract, f'--region={region}', f'--maxzoom={args.maxzoom}',
                        '--download-threads=4', '--quiet'], check=True)

        if os.path.exists(path):
            os.remove(path)
        out = sqlite3.connect(path)
        out.executescript('''
            CREATE TABLE metadata (name TEXT, value TEXT);
            CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);
        ''')
        count = 0
        with open(extract, 'r+b') as f:
            reader = Reader(MmapSource(f))
            planet_metadata = reader.metadata()
            batch = []
            # Tiles stay as stored (gzipped); the app unzips them. MBTiles counts rows from the bottom (TMS).
            for (z, x, y), data in all_tiles(reader.get_bytes):
                batch.append((z, x, (1 << z) - 1 - y, data))
                if len(batch) >= 5000:
                    out.executemany('INSERT INTO tiles VALUES (?, ?, ?, ?)', batch)
                    count += len(batch)
                    batch = []
            out.executemany('INSERT INTO tiles VALUES (?, ?, ?, ?)', batch)
            count += len(batch)

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
        if 'vector_layers' in planet_metadata:
            metadata['json'] = json.dumps({'vector_layers': planet_metadata['vector_layers']})
        out.executemany('INSERT INTO metadata VALUES (?, ?)', metadata.items())
        out.execute('CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row)')
        out.commit()
        out.execute('VACUUM')
        out.close()
        return count


with open(args.shapes) as f:
    features = json.load(f)['features']

for feature in sorted(features, key=lambda f: f['properties'].get('NAME_EN') or f['properties'].get('NAME', '')):
    properties = feature['properties']
    code = country_code(properties)
    if not code or (wanted and code not in wanted):
        continue
    if code in done and not args.force:
        print(f'{code}: already made from {version}, skipping')
        continue
    name = properties.get('NAME_EN') or properties.get('NAME') or code
    geometry = shape(feature['geometry'])
    area = geometry.buffer(BORDER_BUFFER_DEGREES)
    path = os.path.join(args.outdir, f'{code}.mbtiles')

    count = make_country(code, name, area, path)
    size = os.path.getsize(path)
    print(f'{code} {name}: {count:,} tiles, {size / 1e6:.0f} MB')

    if args.upload:
        subprocess.run(['rclone', 'copyto', path, f'{args.upload.rstrip("/")}/{code}.mbtiles'], check=True)
        os.remove(path)
    done[code] = {'id': code, 'name': name, 'bbox': main_part_bbox(geometry), 'bytes': size, 'file': f'{code}.mbtiles'}
    # Saved after every country, so a stopped run picks up where it left off.
    save_index()

save_index()
if args.upload:
    # Last, so the app never lists a country whose file isn't there yet.
    subprocess.run(['rclone', 'copyto', index_path, f'{args.upload.rstrip("/")}/index.json'], check=True)
print(f'{len(done)} countries, {sum(p["bytes"] for p in done.values()) / 1e9:.1f} GB in total -> {index_path}')
