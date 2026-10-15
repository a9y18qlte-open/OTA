#!/bin/bash
# Publish a build to an OTA feed: upload the zip as a GitHub release asset,
# add it to the feed JSON and push the feed.
# Usage: release.sh <feed> <zip>
#   e.g. release.sh lineage-22.2-4.19 ~/lineage-22.2-20261016-UNOFFICIAL-a9y18qlte.zip
# The release is tagged <feed>-<yyyymmdd>-<HHMM> from the build time (UTC).
set -e
FEED=${1:?usage: release.sh <feed> <zip>}
ZIP=${2:?usage: release.sh <feed> <zip>}
REPO=a9y18qlte-open/OTA
cd "$(dirname "$0")"

NAME=$(basename "$ZIP")
DEVICE=$(echo "$NAME" | sed -E 's/.*-(UNOFFICIAL|OFFICIAL|NIGHTLY|EXPERIMENTAL)-(.+)\.zip$/\2/')
# Tag by build time, not the file name's date: builds of the same day have
# the same file name, and must not replace each other's asset
STAMP=$(unzip -p "$ZIP" META-INF/com/android/metadata | sed -n 's/^post-timestamp=//p')
[ -n "$STAMP" ] || { echo "$NAME: no post-timestamp in the zip metadata" >&2; exit 1; }
TAG="$FEED-$(date -u -d "@$STAMP" +%Y%m%d-%H%M)"
URL="https://github.com/$REPO/releases/download/$TAG/$NAME"

git pull -q --ff-only

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
	gh release upload "$TAG" "$ZIP" -R "$REPO" --clobber
else
	gh release create "$TAG" "$ZIP" -R "$REPO" --title "$TAG" --notes "$NAME"
fi

# The feed must only list a build once its download works
curl -sfIL -o /dev/null "$URL" || { echo "$URL is not downloadable" >&2; exit 1; }

python3 -I ota_json.py "$ZIP" "$FEED/$DEVICE.json" "$URL"
git add "$FEED/$DEVICE.json"
git commit -q -m "$FEED: Add $NAME"
git push -q
echo "Published $TAG"
