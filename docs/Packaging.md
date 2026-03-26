# Packaging (AppImage & macOS DMG)

## Prerequisites
- GNUstep toolchain (gnustep-make/base/gui/back) and build deps installed.
- Linux AppImage: `linuxdeploy` + `linuxdeploy-plugin-appimage` must be available and executable.
- macOS DMG: Xcode command line tools installed. No GNUstep runtime needed when using the Cocoa build.

## Build the App Bundles
- Linux: `git submodule update --init --recursive && make -j"$(nproc)"` to produce `ScreenshotTool.app/` (GNUstep with `libs-OpenSave` enabled by default).
  - Fallback GNUstep-only build: `make USE_OPENSAVE=0 -j"$(nproc)"`.
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
- Output: `Staging/ScreenshotTool-x86_64.AppImage` plus `Staging/ScreenshotTool-x86_64.AppImage.sha256`.

To smoke-test the packaged artifact:
```bash
scripts/smoke_appimage.sh Staging/ScreenshotTool-x86_64.AppImage
```

To emit a versioned filename for releases:
```bash
OUTPUT_NAME=ScreenshotTool-v0.1.0-x86_64.AppImage scripts/package_appimage.sh
```

## Package a DMG (macOS)
```bash
scripts/package_macos_dmg.sh build/cocoa/ScreenshotTool.app
DMG_NAME=ScreenshotTool-preview.dmg scripts/package_macos_dmg.sh build/cocoa/ScreenshotTool.app
```
- Optional codesign: set `CODESIGN_IDENTITY="Developer ID Application: …"` to deep-sign the app and DMG.
- Optional notarization: set `NOTARIZE_APPLE_ID`, `NOTARIZE_TEAM_ID`, and `NOTARIZE_PASSWORD` to submit and staple.
- Output: `Staging/ScreenshotTool-macOS.dmg` (name overridable via `DMG_NAME`) plus SHA-256.

## CI Hooks
- `.github/workflows/build.yml` builds the Ubuntu AppImage job on pushes, pull requests, and manual dispatches, smoke-tests the resulting AppImage, and uploads it as a workflow artifact.
- Pushing a version tag like `v0.1.0` also publishes the generated AppImage and `.sha256` file to a GitHub Release.
- The macOS DMG flow is scripted locally with `scripts/build_cocoa.sh` and `scripts/package_macos_dmg.sh`, but its CI job is still disabled.

## Release Flow
1. Make sure the target commit on `main` is the one you want to publish.
2. Create an annotated tag, for example:
   ```bash
   git tag -a v0.1.0 -m "v0.1.0"
   ```
3. Push the tag:
   ```bash
   git push origin v0.1.0
   ```
4. GitHub Actions will build `ScreenshotTool-v0.1.0-x86_64.AppImage`, smoke-test it, generate a checksum, and attach both files to the GitHub Release for that tag.
