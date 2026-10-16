# OTA

Update feeds for the LineageOS Updater (Settings → System → Updates) on the
Samsung Galaxy A9 (2018) (`a9y18qlte`).

| Feed | Builds |
|---|---|
| `lineage-22.2/a9y18qlte.json` | LineageOS 22.2 (main feed, 4.4 kernel) |
| `lineage-22.2-4.19/a9y18qlte.json` | LineageOS 22.2 on the 4.19 kernel |

`lineage-22.2` is the main feed, for builds of the `lineage-22.2` device
branch (4.4 kernel). The 4.19 builds have their own feed for now. Once they
are stable, the 4.19 branch points its `lineage.updater.uri` at
`lineage-22.2` too and its builds are published there, so both kernels update
from the same feed.

Builds point the Updater at their feed with `lineage.updater.uri`. Each build
zip is a release asset of this repository, tagged `<feed>-<yyyymmdd>-<HHMM>`
from the build time (UTC).

## Adding a build

```
./release.sh lineage-22.2 <build log> <source tree>
```

`release.sh` publishes the zip that the build log's last `Package Complete:`
line names. Every build rewrites the OTA package in place, and the zips of
earlier builds are hardlinks to it, so the newest zip in the output directory
can carry an earlier build's name. A zip can also be given directly:
`./release.sh lineage-22.2 <zip>`.

It uploads the zip as the asset of release `<feed>-<yyyymmdd>-<HHMM>`
(using `gh`), checks that it downloads, adds it to the feed and pushes. To
only update a feed by hand:

```
python3 ota_json.py <zip> lineage-22.2/a9y18qlte.json \
    https://github.com/a9y18qlte-open/OTA/releases/download/<tag>/<zip name>
```

`ota_json.py` reads the build timestamp (`post-timestamp`, the build's
`ro.build.date.utc`) from the zip, and adds an entry with the zip's SHA-256 as
its id, its size, and the version and release type from the file name. The
Updater offers a build only when its `datetime` is newer than the installed
build's.

Upload the zip to the release before pushing the updated feed.
