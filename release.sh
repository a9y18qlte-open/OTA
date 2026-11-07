#!/bin/bash
# Publish a build to an OTA feed: upload the zip as a GitHub release asset,
# add it to the feed JSON and push the feed.
# Usage: release.sh <feed> <zip> [extra_assets...]
#        release.sh <feed> <build log> <source tree>
set -e
USAGE="usage: release.sh <feed> <zip> [extra_assets...] | <feed> <build log> <source tree>"
FEED=${1:?$USAGE}
ZIP=${2:?$USAGE}
REPO=a9y18qlte-open/OTA

case "$ZIP" in
*.zip)
	shift 2
	EXTRA_ASSETS=("$@")
	;;
*)
	LOG=$ZIP
	ZIP=$(grep -a -o 'Package Complete: .*' "$LOG" | tail -n 1 | sed 's/^Package Complete: //; s/\r$//')
	[ -n "$ZIP" ] || { echo "$LOG: no \"Package Complete:\" line" >&2; exit 1; }
	case "$ZIP" in
	/*) ;;
	*) ZIP="${3:?$USAGE}/$ZIP" ;;
	esac
	shift 3 2>/dev/null || shift $#
	EXTRA_ASSETS=("$@")
	;;
esac
[ -f "$ZIP" ] || { echo "$ZIP: not found" >&2; exit 1; }
ZIP=$(realpath "$ZIP")
cd "$(dirname "$0")"

NAME=$(basename "$ZIP")
DEVICE=$(echo "$NAME" | sed -E 's/.*-(UNOFFICIAL|OFFICIAL|NIGHTLY|EXPERIMENTAL)-(.+)\.zip$/\2/')

# Extract metadata from the OTA package
META=$(unzip -p "$ZIP" META-INF/com/android/metadata 2>/dev/null || true)
STAMP=$(echo "$META" | sed -n 's/^post-timestamp=//p')
[ -n "$STAMP" ] || { echo "$NAME: no post-timestamp in the zip metadata" >&2; exit 1; }

SDK_LEVEL=$(echo "$META" | sed -n 's/^post-sdk-level=//p')
SEC_PATCH=$(echo "$META" | sed -n 's/^post-security-patch-level=//p')

case "$SDK_LEVEL" in
36) ANDROID_VER="16" ;;
35) ANDROID_VER="15" ;;
34) ANDROID_VER="14" ;;
*)
	case "$FEED" in
	lineage-23*) ANDROID_VER="16" ;;
	lineage-22*) ANDROID_VER="15" ;;
	*) ANDROID_VER="$SDK_LEVEL" ;;
	esac
	;;
esac

SRC_TREE="${SRC_DIR:-${SRC:-/home/thongnguyen1809/lineage-22}}"
[ -d "$SRC_TREE" ] || SRC_TREE="$HOME/lineage-22"

DEV_REPO="$SRC_TREE/device/samsung/$DEVICE"
KERNEL_REPO="$SRC_TREE/kernel/samsung/$DEVICE"
VENDOR_REPO="$SRC_TREE/vendor/samsung/$DEVICE"

DEV_HASH=""
DEV_FULL=""
KERNEL_HASH=""
KERNEL_FULL=""
VENDOR_HASH=""
VENDOR_FULL=""

if [ -d "$DEV_REPO/.git" ]; then
	DEV_HASH=$(git -C "$DEV_REPO" rev-parse --short HEAD 2>/dev/null || true)
	DEV_FULL=$(git -C "$DEV_REPO" rev-parse HEAD 2>/dev/null || true)
fi
if [ -d "$KERNEL_REPO/.git" ]; then
	KERNEL_HASH=$(git -C "$KERNEL_REPO" rev-parse --short HEAD 2>/dev/null || true)
	KERNEL_FULL=$(git -C "$KERNEL_REPO" rev-parse HEAD 2>/dev/null || true)
fi
if [ -d "$VENDOR_REPO/.git" ]; then
	VENDOR_HASH=$(git -C "$VENDOR_REPO" rev-parse --short HEAD 2>/dev/null || true)
	VENDOR_FULL=$(git -C "$VENDOR_REPO" rev-parse HEAD 2>/dev/null || true)
fi

FEED_VER=$(echo "$FEED" | sed 's/^lineage-//')
if [ -n "$DEV_HASH" ]; then
	TAG="$FEED-$(date -u -d "@$STAMP" +%Y%m%d)-${DEV_HASH}"
	VERSION_STR="${FEED_VER}.${DEV_HASH}"
else
	TAG="$FEED-$(date -u -d "@$STAMP" +%Y%m%d-%H%M)"
	VERSION_STR=""
fi
URL="https://github.com/$REPO/releases/download/$TAG/$NAME"

NOTES_TMP=$(mktemp)
cat > "$NOTES_TMP" << EOF
## LineageOS $FEED_VER for Samsung Galaxy A9 (2018) (\`$DEVICE\`)

- **ROM Version**: \`${VERSION_STR:-$FEED_VER}\`
- **Build Date**: $(date -u -d "@$STAMP" +%Y-%m-%d)
- **Android Version**: $ANDROID_VER
EOF

if [ -n "$SEC_PATCH" ]; then
	echo "- **Security Patch**: $SEC_PATCH" >> "$NOTES_TMP"
fi

cat >> "$NOTES_TMP" << EOF

### Source Repositories
EOF

if [ -n "$DEV_HASH" ]; then
	echo "- **Device Tree**: [\`$DEV_HASH\`](https://github.com/a9y18qlte-open/android_device_samsung_$DEVICE/commit/$DEV_FULL)" >> "$NOTES_TMP"
fi
if [ -n "$KERNEL_HASH" ]; then
	echo "- **Kernel Tree**: [\`$KERNEL_HASH\`](https://github.com/a9y18qlte-open/android_kernel_samsung_$DEVICE/commit/$KERNEL_FULL)" >> "$NOTES_TMP"
fi
if [ -n "$VENDOR_HASH" ]; then
	echo "- **Vendor Tree**: [\`$VENDOR_HASH\`](https://github.com/a9y18qlte-open/android_vendor_samsung_$DEVICE/commit/$VENDOR_FULL)" >> "$NOTES_TMP"
fi

cat >> "$NOTES_TMP" << EOF

### Assets
- \`$NAME\`: Signed LineageOS $FEED_VER ROM OTA package
EOF

for extra in "${EXTRA_ASSETS[@]}"; do
	if [ -f "$extra" ]; then
		case "$(basename "$extra")" in
		*BakaSU*)
			echo "- \`$(basename "$extra")\`: BakaSU + SUSFS v2.3.0 AnyKernel3 installer for Linux 4.4" >> "$NOTES_TMP"
			;;
		*KernelSU*|*AnyKernel3*)
			echo "- \`$(basename "$extra")\`: KernelSU-Next AnyKernel3 installer for Linux 4.4" >> "$NOTES_TMP"
			;;
		*)
			echo "- \`$(basename "$extra")\`" >> "$NOTES_TMP"
			;;
		esac
	fi
done

git pull -q --ff-only

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
	gh release upload "$TAG" "$ZIP" -R "$REPO" --clobber
	gh release edit "$TAG" -R "$REPO" --notes-file "$NOTES_TMP"
else
	gh release create "$TAG" "$ZIP" -R "$REPO" --title "$TAG" --notes-file "$NOTES_TMP"
fi
rm -f "$NOTES_TMP"

for extra in "${EXTRA_ASSETS[@]}"; do
	if [ -f "$extra" ]; then
		echo "Uploading extra release asset: $extra"
		gh release upload "$TAG" "$extra" -R "$REPO" --clobber
	fi
done

# The feed must only list a build once its download works
curl -sfIL -o /dev/null "$URL" || { echo "$URL is not downloadable" >&2; exit 1; }

if [ -n "$VERSION_STR" ]; then
	python3 -I ota_json.py "$ZIP" "$FEED/$DEVICE.json" "$URL" "$VERSION_STR"
else
	python3 -I ota_json.py "$ZIP" "$FEED/$DEVICE.json" "$URL"
fi

git add "$FEED/$DEVICE.json"
git commit -q -m "$FEED: Add $NAME"
git push -q
echo "Published $TAG"
