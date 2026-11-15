#!/bin/bash
# Promote a draft release in a9y18qlte-open/OTA into a public release and add it to the OTA feed.
# Usage: ./publish_draft.sh <release-tag>
set -euo pipefail

TAG="${1:?usage: publish_draft.sh <release-tag> [local-zip]}"
LOCAL_ZIP_ARG="${2:-${LOCAL_ZIP:-}}"
REPO="a9y18qlte-open/OTA"

cd "$(dirname "$0")"
git pull -q --ff-only

echo ">>> Fetching release info for tag: $TAG..."
RELEASE_JSON=$(gh release view "$TAG" -R "$REPO" --json tagName,isDraft,assets,body)
IS_DRAFT=$(echo "$RELEASE_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('isDraft', False))")

if [ "$IS_DRAFT" = "True" ] || [ "$IS_DRAFT" = "true" ]; then
    echo ">>> Undrafting GitHub release $TAG..."
    gh release edit "$TAG" -R "$REPO" --draft=false
    # Re-fetch release info after undrafting so asset URLs reflect public release tag
    RELEASE_JSON=$(gh release view "$TAG" -R "$REPO" --json tagName,isDraft,assets,body)
else
    echo ">>> Release $TAG is already public."
fi

# Locate the ROM zip name and download URL from assets
ASSETS_INFO=$(echo "$RELEASE_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assets = data.get('assets', [])
rom_zip = None
for a in assets:
    name = a.get('name', '')
    if name.endswith('.zip') and not name.startswith('AnyKernel3'):
        rom_zip = a
        break
if rom_zip:
    print(rom_zip['name'])
    print(rom_zip['url'])
else:
    sys.exit(1)
") || { echo "Error: Could not find main ROM zip in release assets" >&2; exit 1; }

ROM_NAME=$(echo "$ASSETS_INFO" | head -n 1)
ROM_URL=$(echo "$ASSETS_INFO" | tail -n 1)

FEED=$(echo "$TAG" | grep -o -E 'lineage-[0-9]+(\.[0-9]+)?(-4\.19)?' | head -n 1)
DEVICE=$(echo "$ROM_NAME" | sed -E 's/.*-(UNOFFICIAL|OFFICIAL|NIGHTLY|EXPERIMENTAL)-(.+)\.zip$/\2/')
[ -n "$DEVICE" ] || DEVICE="a9y18qlte"

JSON_FILE="$FEED/$DEVICE.json"
[ -f "$JSON_FILE" ] || { echo "Error: Feed JSON not found: $JSON_FILE" >&2; exit 1; }

echo ">>> Verifying asset download URL is reachable: $ROM_URL..."
for i in {1..15}; do
    if curl -sfIL -o /dev/null "$ROM_URL"; then
        break
    fi
    if [ $i -eq 15 ]; then
        echo "Error: $ROM_URL is not downloadable after undrafting" >&2
        exit 1
    fi
    sleep 2
done

# Download zip headers or inspect metadata to extract version / properties
CLEANUP_ZIP=false
if [ -n "$LOCAL_ZIP_ARG" ] && [ -f "$LOCAL_ZIP_ARG" ]; then
    TMP_ZIP="$LOCAL_ZIP_ARG"
    echo ">>> Using existing local zip for metadata: $TMP_ZIP"
else
    TMP_ZIP="/tmp/ota_inspect_$$.zip"
    echo ">>> Fetching zip metadata from release..."
    gh release download "$TAG" -R "$REPO" -p "$ROM_NAME" -O "$TMP_ZIP"
    CLEANUP_ZIP=true
fi

DEV_HASH=$(echo "$TAG" | awk -F'-' '{print $NF}')
FEED_VER=$(echo "$FEED" | sed 's/^lineage-//')
VERSION_STR=""
if [ -n "$DEV_HASH" ]; then
    VERSION_STR="${FEED_VER}.${DEV_HASH}"
fi

if [ -n "$VERSION_STR" ]; then
    python3 -I ota_json.py "$TMP_ZIP" "$JSON_FILE" "$ROM_URL" "$VERSION_STR"
else
    python3 -I ota_json.py "$TMP_ZIP" "$JSON_FILE" "$ROM_URL"
fi
[ "$CLEANUP_ZIP" = "true" ] && rm -f "$TMP_ZIP"

git add "$JSON_FILE"
git commit -m "$FEED: Promote $TAG to live OTA feed"
git push
echo ">>> Successfully promoted $TAG to live OTA update in $JSON_FILE!"
