# OTA

Update feeds for the LineageOS Updater (Settings → System → Updates) on the Samsung Galaxy A9 (2018) (`a9y18qlte`).

| Feed | Builds |
|---|---|
| `lineage-22.2/a9y18qlte.json` | LineageOS 22.2 (Android 15, Linux 4.4 kernel) |
| `lineage-22.2-4.19/a9y18qlte.json` | LineageOS 22.2 on Linux 4.19 kernel |
| `lineage-23.2/a9y18qlte.json` | LineageOS 23.2 (Android 16, Linux 4.19 kernel) |
| `lineage-24.0/a9y18qlte.json` | LineageOS 24.0 (Android 17) |

---

## Versioning Scheme

Builds are versioned as:
```text
<major>.<minor>.<device_hash>
```
*Example*: `22.2.ff77069` (displayed in the phone UI as `LineageOS 22.2.ff77069`).

### Why this format:
1. **Updater Compatibility**: LineageOS Updater's `compareVersions()` splits by dots (`split("\\.")`) and parses `[0]` and `[1]` as integers (`Integer.parseInt()`). Trailing text after the second dot is preserved for display without causing a `NumberFormatException`.
2. **Same-Day Build Distinction**: Multiple builds produced on the same calendar day remain distinct in the Updater UI rather than showing identical titles.
3. **UI Layout Safe**: Stays well within the single-line constraint (`android:maxLines="1"`) in `update_item_view.xml`, preventing text truncation beside the download button.

---

## Releases & Assets

Each release is tagged as:
```text
<feed>-<yyyymmdd>-<device_hash>
```
*Example*: `lineage-22.2-20261107-ff77069`

### Release Contents:
- **ROM Package**: Signed LineageOS OTA zip (with package signature migration support for upgrade keys).
- **Companion KernelSU Package**: `AnyKernel3-KernelSU-a9y18qlte-<date>.zip` flashable package for users desiring root access via KernelSU-Next.
- **Traceability Notes**: The release notes automatically link the exact Git commit hashes across:
  - Device Tree (`device/samsung/a9y18qlte`)
  - Kernel Tree (`kernel/samsung/a9y18qlte`)
  - Vendor Tree (`vendor/samsung/a9y18qlte`)

---

## Publishing Builds

### Public Release (Immediate OTA Update)
```bash
./release.sh <feed> <zip> [extra_assets...]
# e.g.:
./release.sh lineage-22.2 lineage-22.2-20261107-UNOFFICIAL-a9y18qlte.zip AnyKernel3-KernelSU-a9y18qlte-20261107.zip
```

`release.sh` automates the release process:
1. Reads `post-timestamp`, `post-sdk-level`, and `post-security-patch-level` from the zip metadata.
2. Extracts current Git commit hashes from device, kernel, and vendor trees.
3. Creates the GitHub release with formatted notes and uploads the ROM zip and any companion assets.
4. Verifies asset availability.
5. Updates the device feed JSON with the `<major>.<minor>.<device_hash>` version and pushes to `main`.

### Testing / Draft Release
For builds currently under testing that should **not** appear immediately in users' OTA updater apps:
```bash
./release.sh --draft <feed> <zip> [extra_assets...]
```
- Creates a **GitHub Draft Release** and uploads the ROM zip and companion AnyKernel3/BakaSU assets.
- **Skips** updating the public feed JSON (`<feed>/<device>.json`), preventing users' updater apps from seeing unverified builds or getting 404 errors.
- Testers with repo permissions can download assets directly from the GitHub Releases tab.

### Promoting a Draft to Live OTA Update
Once testing is finished and the build is approved for all users:
```bash
./publish_draft.sh <release-tag>
# e.g.:
./publish_draft.sh lineage-23.2-20261115-d01e141
```
This will:
1. Undraft the GitHub release (making assets publicly downloadable without authentication).
2. Read the release metadata and automatically populate the corresponding `<feed>/<device>.json`.
3. Commit and push the feed to `main`, making the update instantly visible in **Settings → System → Updates**.

---

## Manual JSON Update
To update the JSON feed manually:
```bash
python3 ota_json.py <zip> <feed>/<device>.json <download_url> [version_override]
```
