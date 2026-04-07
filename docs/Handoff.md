# Handoff

Date: 2026-04-07

## Current State

- Phase 11 is implemented in the repo through `11H`.
- The remaining work is release execution and cross-platform verification, not missing repo scaffolding.
- The current release/update implementation lives in:
  - `packaging/package.manifest.json`
  - `scripts/build_release.ps1`
  - `scripts/stage_release.ps1`
  - `scripts/bootstrap_gnustep_linux_ci.sh`
  - `.github/workflows/release.yml`
  - `third_party/gnustep-packager-updater/objc/`
  - `docs/Packaging.md`

## What Is Implemented

- Shared `gnustep-packager` manifest for both `msi` and `appimage`
- Repo-owned build and stage commands
- Vendored updater runtime and helper
- App-level updater integration with `Check for Updates…`
- Linux CI bootstrap with GNUstep and `patchelf`
- Tag-driven packaging workflow for:
  - Windows MSI
  - Linux AppImage
- GitHub Release publication
- GitHub Pages stable feed publication
- MSI signing hooks and release checksum publication
- Release docs and validation checklist

## Local Validation Already Done

- `pwsh -NoProfile -File scripts/build_release.ps1 -ManifestPath packaging/package.manifest.json`
  - passed
- `find ScreenshotTool.app -maxdepth 1 -name 'gp-update-helper*'`
  - confirmed helper is present in the built app bundle
- `pwsh -NoProfile -File scripts/stage_release.ps1 -ManifestPath packaging/package.manifest.json -StageRoot dist/stage`
  - passed
- `find dist/stage/app/ScreenshotTool.app -maxdepth 1 -name 'gp-update-helper*'`
  - confirmed helper is present in the staged app bundle
- `pwsh -NoProfile -File /home/danboyd/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1 -Command validate -Manifest /home/danboyd/git/ScreenshotTool/packaging/package.manifest.json`
  - shared validation passed
- `pwsh -NoProfile -File /home/danboyd/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1 -Command resolve-manifest -Manifest /home/danboyd/git/ScreenshotTool/packaging/package.manifest.json -PackageVersion 1.2.3`
  - confirmed release-version override behavior

## What Still Needs Real-World Verification

- end-to-end `release.yml` run on a test tag
- Windows MSI packaging and signing on `windows-latest`
- Linux AppImage packaging and smoke validation through CI
- GitHub Pages deployment of:
  - `updates/windows/stable.json`
  - `updates/linux/stable.json`
- in-app upgrade flow against an actual newer release

## Important Local Limitation

- this development machine still does not have `patchelf`
- the local stage script warns and leaves the host `RUNPATH` in place
- the CI bootstrap script installs `patchelf`, so this should be a local-only limitation

## Release Failure Policy

- the release workflow publishes the release as a draft first
- it deploys GitHub Pages feeds next
- it only undrafts the release after Pages deployment succeeds

If Pages deployment fails:

- the workflow fails
- the release remains draft
- do not treat that tag as published until the workflow is fixed and rerun

## First Step Next Time

1. Push a disposable test tag such as `v0.1.0-rc1` or another agreed validation tag.
2. Watch `release.yml`.
3. Verify:
   - release artifacts were attached
   - `SHA256SUMS` was attached
   - both `stable.json` feeds deployed
4. Run manual install/update QA on both platforms.

## Useful Commands

Local rebuild and stage:

```bash
pwsh -NoProfile -File scripts/build_release.ps1 -ManifestPath packaging/package.manifest.json
pwsh -NoProfile -File scripts/stage_release.ps1 -ManifestPath packaging/package.manifest.json -StageRoot dist/stage
```

Shared validation:

```bash
pwsh -NoProfile -File /home/danboyd/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1 -Command validate -Manifest /home/danboyd/git/ScreenshotTool/packaging/package.manifest.json
```

Helper presence:

```bash
find ScreenshotTool.app -maxdepth 1 -name 'gp-update-helper*' | sort
find dist/stage/app/ScreenshotTool.app -maxdepth 1 -name 'gp-update-helper*' | sort
```

Runpath spot check:

```bash
readelf -d dist/stage/app/ScreenshotTool.app/ScreenshotTool | rg 'RUNPATH|RPATH'
```

## Notes

- Two vendored upstream fixes were required for this toolchain:
  - renaming local variables named `linux` to avoid the compiler macro collision
  - fixing one malformed `GPHelperReplaceFile(...)` call in `gp-update-helper`
- Those fixes currently live only in the vendored updater copy under `third_party/gnustep-packager-updater/objc/`.
