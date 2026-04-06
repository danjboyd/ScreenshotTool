# Handoff

Date: 2026-04-06

## Current State

- Phase 11 is in progress.
- Phase `11A` through `11C` are implemented locally.
- The repo now has a shared `gnustep-packager` manifest at `packaging/package.manifest.json`.
- The repo now has cross-platform packaging helpers at `scripts/build_release.ps1` and `scripts/stage_release.ps1`.
- The current worktree changes for this checkpoint are:
  - `.gitignore`
  - `docs/Handoff.md`
  - `packaging/package.manifest.json`
  - `scripts/build_release.ps1`
  - `scripts/stage_release.ps1`

## What Was Completed Today

- Added a single manifest for both `msi` and `appimage` packaging.
- Defined package identity, feed URLs, update provider, tag pattern, and a permanent MSI `upgradeCode`.
- Normalized the stage/output roots to repo-level `dist/` paths so `gnustep-packager` resolves the payload correctly.
- Added a cross-platform build wrapper that:
  - updates submodules
  - builds on Linux through `GNUstep.sh`
  - builds on Windows through MSYS2 `CLANG64`
- Added a cross-platform stage wrapper that:
  - copies the app bundle into a packager-compatible stage tree
  - normalizes the launch entry path to `app/ScreenshotTool.app/ScreenshotTool`
  - rewrites staged plist version fields from the requested package version
  - stages icon and license metadata
  - stages GNUstep runtime content for Linux and Windows
- Added Linux dependency-closure harvesting for AppImage staging.
- Added Windows runtime staging from MSYS2 `CLANG64`.
- Wired package-version override handling so repo-defined `build` and `stage` steps stay aligned with `gnustep-packager` release versions.

## Validation Already Done

- `pwsh -NoProfile -File scripts/build_release.ps1 -ManifestPath packaging/package.manifest.json`
  - passed on this Linux host
- `pwsh -NoProfile -File scripts/stage_release.ps1 -ManifestPath packaging/package.manifest.json -StageRoot dist/stage`
  - passed on this Linux host
- `pwsh -NoProfile -File /home/danboyd/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1 -Command validate -Manifest /home/danboyd/git/ScreenshotTool/packaging/package.manifest.json`
  - shared validation passed
- `pwsh -NoProfile -File scripts/stage_release.ps1 -ManifestPath packaging/package.manifest.json -StageRoot dist/stage-versioncheck -PackageVersion 9.9.9-test`
  - passed and confirmed staged plist versions follow the requested package version override

## Known Gaps

- `patchelf` is not installed on the current Linux machine.
- Because of that, the staged Linux binary still carries a host `RUNPATH`:
  - `/home/danboyd/git/ScreenshotTool/third_party/libs-OpenSave/Source/obj`
- `scripts/stage_release.ps1` already detects this and will patch the runpath when `patchelf` is available.
- Until `patchelf` is present on the release runner, AppImage backend validation and final AppImage packaging are expected to fail.
- The Windows build/stage paths are implemented but were not exercised today because this machine is Linux.

## Remaining Phase 11 Work

- `11D`: integrate the updater into the app and add `Check for Updates...`
- `11E`: add a tag-driven GitHub Actions release workflow for `msi` and `appimage`
- `11F`: publish release assets and hosted stable feeds
- `11G`: add signing, checksums, and release failure handling
- `11H`: run full install/update validation and finish release docs

## First Step Tomorrow

1. Make sure the Linux release environment has `patchelf`.
2. Run backend validation for AppImage against the staged payload.
3. If that passes, move directly into phase `11D` or `11E` depending on whether updater wiring or release automation should land first.

## Useful Commands

Rebuild and restage:

```bash
pwsh -NoProfile -File scripts/build_release.ps1 -ManifestPath packaging/package.manifest.json
pwsh -NoProfile -File scripts/stage_release.ps1 -ManifestPath packaging/package.manifest.json -StageRoot dist/stage
```

Shared validation:

```bash
pwsh -NoProfile -File /home/danboyd/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1 -Command validate -Manifest /home/danboyd/git/ScreenshotTool/packaging/package.manifest.json
```

Version-override spot check:

```bash
pwsh -NoProfile -File scripts/stage_release.ps1 -ManifestPath packaging/package.manifest.json -StageRoot dist/stage-versioncheck -PackageVersion 9.9.9-test
```

AppImage runpath check:

```bash
readelf -d dist/stage/app/ScreenshotTool.app/ScreenshotTool | rg 'RUNPATH|RPATH'
```

## Notes

- `runtimeSeedPaths` now includes both `runtime/bin/defaults` and `runtime/bin/defaults.exe` so the single manifest works for Linux and Windows staging.
- The repo-level handoff note supersedes the older AppImage-only handoff state from March 2026.
