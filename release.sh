#!/bin/bash
# Publish a build to an OTA feed: upload the zip as a GitHub release asset,
# add it to the feed JSON and push the feed.
# Usage: release.sh <feed> <zip>
#        release.sh <feed> <build log> <source tree>
#   e.g. release.sh lineage-22.2 ~/build_lineage22.log ~/lineage-20
# With a build log, the zip is the one its last "Package Complete:" line
# names. bacon hardlinks the OTA package to the zip name of each build, so
# the zips of earlier builds hold the newest build too, under their old names.
# The release is tagged <feed>-<yyyymmdd>-<HHMM> from the build time (UTC).
set -e
USAGE="usage: release.sh <feed> <zip> | <feed> <build log> <source tree>"
FEED=${1:?$USAGE}
ZIP=${2:?$USAGE}
REPO=a9y18qlte-open/OTA

case "$ZIP" in
*.zip) ;;
*)
	LOG=$ZIP
	ZIP=$(grep -a -o 'Package Complete: .*' "$LOG" | tail -n 1 | sed 's/^Package Complete: //; s/\r$//')
	[ -n "$ZIP" ] || { echo "$LOG: no \"Package Complete:\" line" >&2; exit 1; }
	case "$ZIP" in
	/*) ;;
	*) ZIP="${3:?$USAGE}/$ZIP" ;;
	esac
	;;
esac
[ -f "$ZIP" ] || { echo "$ZIP: not found" >&2; exit 1; }
ZIP=$(realpath "$ZIP")
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
