#!/usr/bin/env python3
"""Add a LineageOS build zip to an Updater OTA JSON file.

usage: ota_json.py <zip> <json> <url>

<url> is where the zip will be downloadable from. The entry gets the zip's
build timestamp (post-timestamp in META-INF/com/android/metadata, which is
ro.build.date.utc), its SHA-256 as the id, its size, and the version and
release type from the file name (lineage-<version>-<date>-<type>-<device>.zip).
The Updater lists builds as "LineageOS <version>" with only the date, so the
version gets the build time (UTC, matching the shown date) to tell builds of
one day apart: "22.2.0 (19:52 UTC)". The Updater parses the version as
<major>.<minor> by splitting at dots, so the ".0" keeps the minor a plain
number; "22.2 (19:52 UTC)" would make the build uninstallable.
An entry with the same id is replaced; entries are kept newest first.
"""
import hashlib
import json
import os
import re
import sys
import time
import zipfile


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    zip_path, json_path, url = sys.argv[1:]
    filename = os.path.basename(url)

    m = re.match(r'lineage-([0-9.]+)-\d{8}-([A-Z]+)-(.+)\.zip$', filename)
    if not m:
        sys.exit(f'{filename}: not a lineage-<version>-<date>-<type>-<device>.zip name')
    version, romtype = m.group(1), m.group(2)

    with zipfile.ZipFile(zip_path) as z:
        meta = z.read('META-INF/com/android/metadata').decode()
    props = dict(line.split('=', 1) for line in meta.splitlines() if '=' in line)
    datetime = int(props['post-timestamp'])

    sha = hashlib.sha256()
    with open(zip_path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            sha.update(chunk)

    entry = {
        'datetime': datetime,
        'filename': filename,
        'id': sha.hexdigest(),
        'romtype': romtype,
        'size': os.path.getsize(zip_path),
        'url': url,
        'version': f'{version}.0 ({time.strftime("%H:%M", time.gmtime(datetime))} UTC)',
    }

    data = {'response': []}
    if os.path.exists(json_path):
        with open(json_path) as f:
            data = json.load(f)
    builds = [b for b in data['response'] if b['id'] != entry['id']]
    builds.append(entry)
    builds.sort(key=lambda b: b['datetime'], reverse=True)
    data['response'] = builds

    os.makedirs(os.path.dirname(os.path.abspath(json_path)), exist_ok=True)
    with open(json_path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print(json.dumps(entry, indent=2))


if __name__ == '__main__':
    main()
