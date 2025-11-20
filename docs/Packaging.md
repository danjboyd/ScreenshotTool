# Packaging (AppImage & macOS DMG)

## Prerequisites
- GNUstep toolchain (gnustep-make/base/gui/back) and build deps installed.
- Linux AppImage: `linuxdeploy` + `linuxdeploy-plugin-appimage` must be available and executable.
- macOS DMG: Xcode command line tools installed. No GNUstep runtime needed when using the Cocoa build.

## Build the App Bundles
- Linux: `make -j"$(nproc)"` to produce `ScreenshotTool.app/` (GNUstep).
- macOS (Cocoa-native): `scripts/build_cocoa.sh` → `build/cocoa/ScreenshotTool.app/`.

## Smoke Test on macOS
- `scripts/smoke_macos_app.sh [path/to/ScreenshotTool.app]`  
  Runs the binary for a few seconds and writes startup logs to `screenshottool-smoke.log`.

## Package an AppImage (Linux)
```bash
LINUXDEPLOY=/path/to/linuxdeploy-x86_64.AppImage \
LINUXDEPLOY_PLUGIN_APPIMAGE=/path/to/linuxdeploy-plugin-appimage-x86_64.AppImage \
scripts/package_appimage.sh
```
- Output: `Staging/ScreenshotTool-x86_64.AppImage` plus a SHA-256 checksum.

## Package a DMG (macOS)
```bash
scripts/package_macos_dmg.sh build/cocoa/ScreenshotTool.app
DMG_NAME=ScreenshotTool-preview.dmg scripts/package_macos_dmg.sh build/cocoa/ScreenshotTool.app
```
- Optional codesign: set `CODESIGN_IDENTITY="Developer ID Application: …"` to deep-sign the app and DMG.
- Optional notarization: set `NOTARIZE_APPLE_ID`, `NOTARIZE_TEAM_ID`, and `NOTARIZE_PASSWORD` to submit and staple.
- Output: `Staging/ScreenshotTool-macOS.dmg` (name overridable via `DMG_NAME`) plus SHA-256.

## CI Hooks
- `.github/workflows/build.yml` builds on Ubuntu (AppImage) and macOS (DMG), uploads artifacts, and reuses the scripts above to keep the release flow aligned with local builds.
