#!/usr/bin/env python3
"""Package the app database for download: a compressed copy plus manifest.json describing it.

Usage:
    python3 package_database.py <app hitchwiki.sqlite> <out dir> --base-url <URL the files will be served from>

Writes:
    <out dir>/hitchwiki-<version>.sqlite.deflate   raw DEFLATE (what Apple's NSData.decompressed(using: .zlib) reads)
    <out dir>/manifest.json                        version, schema, checksum and download URL

The app downloads manifest.json on launch, and the database only when `version` is higher than its own
and `schema_version` is one it supports.
"""
import argparse, hashlib, json, os, sqlite3, zlib

ap = argparse.ArgumentParser()
ap.add_argument('database')
ap.add_argument('outdir')
ap.add_argument('--base-url', required=True, help='e.g. https://github.com/OWNER/REPO/releases/download/database-latest')
args = ap.parse_args()

db = sqlite3.connect(args.database)
meta = dict(db.execute('SELECT key, value FROM meta'))
db.close()
version = int(meta['version'])

data = open(args.database, 'rb').read()
compressor = zlib.compressobj(9, zlib.DEFLATED, -15)   # -15: raw DEFLATE, no zlib/gzip header
deflated = compressor.compress(data) + compressor.flush()

os.makedirs(args.outdir, exist_ok=True)
name = f'hitchwiki-{version}.sqlite.deflate'
with open(os.path.join(args.outdir, name), 'wb') as f:
    f.write(deflated)

manifest = {
    'schema_version': int(meta['schema_version']),
    'version': version,
    'generated_at': meta.get('generated_at', ''),
    'source_sha256': meta.get('source_sha256', ''),
    'database': {
        'url': args.base_url.rstrip('/') + '/' + name,
        'compression': 'deflate',
        'sha256': hashlib.sha256(data).hexdigest(),
        'size': len(data),
        'compressed_size': len(deflated),
    },
    'stats': {'pages': int(meta.get('pages', 0)), 'spots': int(meta.get('spots', 0))},
}
with open(os.path.join(args.outdir, 'manifest.json'), 'w') as f:
    json.dump(manifest, f, indent=2)
print(json.dumps(manifest, indent=2))
