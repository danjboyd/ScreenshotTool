# Packaging

## Current Packaging Model

ScreenshotTool now has two packaging paths:

- legacy local AppImage packaging through `scripts/package_appimage.sh`
- release packaging through `gnustep-packager` using:
  - `packaging/package.manifest.json`
  - `scripts/build_release.ps1`
  - `scripts/stage_release.ps1`
  - `.github/workflows/release.yml`

The release path is the authoritative one for phase 11. It is responsible for:

- Windows MSI packaging
- Linux AppImage packaging
- updater runtime config emission
- `.update-feed.json` sidecar generation
- GitHub Release asset publication
- GitHub Pages feed publication

## Local Build And Stage

Build the GNUstep app plus updater components:

```bash
pwsh -NoProfile -File scripts/build_release.ps1 -ManifestPath packaging/package.manifest.json
```

That builds:

- `third_party/libs-OpenSave`
- `third_party/gnustep-packager-updater/objc/GPUpdaterCore`
- `third_party/gnustep-packager-updater/objc/GPUpdaterUI`
- `third_party/gnustep-packager-updater/objc/gp-update-helper`
- `ScreenshotTool.app`

The built app bundle should contain:

```bash
find ScreenshotTool.app -maxdepth 1 -name 'gp-update-helper*' | sort
```

Stage the release payload:

```bash
pwsh -NoProfile -File scripts/stage_release.ps1 -ManifestPath packaging/package.manifest.json -StageRoot dist/stage
```

This produces the shared packager layout:

- `dist/stage/app/`
- `dist/stage/runtime/`
- `dist/stage/metadata/`

The staged app bundle should contain:

```bash
find dist/stage/app/ScreenshotTool.app -maxdepth 1 -name 'gp-update-helper*' | sort
```

## Local Validation

Shared layout validation:

```bash
pwsh -NoProfile -File /home/danboyd/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1 -Command validate -Manifest /home/danboyd/git/ScreenshotTool/packaging/package.manifest.json
```

Version-override spot check:

```bash
pwsh -NoProfile -File /home/danboyd/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1 -Command resolve-manifest -Manifest /home/danboyd/git/ScreenshotTool/packaging/package.manifest.json -PackageVersion 1.2.3
```

Linux runpath spot check:

```bash
readelf -d dist/stage/app/ScreenshotTool.app/ScreenshotTool | rg 'RUNPATH|RPATH'
```

Important local limitation:

- this development machine does not currently have `patchelf`
- `scripts/stage_release.ps1` therefore warns and leaves the host `RUNPATH` in place locally
- the CI bootstrap script installs `patchelf`, so release CI should not inherit that local limitation

## CI Workflows

### `build.yml`

`.github/workflows/build.yml` is now a non-tag build job:

- runs on pushes, pull requests, and manual dispatches
- ignores `v*` tags
- bootstraps GNUstep on Linux
- builds the app with `scripts/build_release.ps1`
- still produces the legacy AppImage artifact path for general CI feedback

### `release.yml`

`.github/workflows/release.yml` is the release workflow:

- triggers on `v*` tags and manual dispatch
- strips the leading `v` and passes the normalized package version into `gnustep-packager`
- packages:
  - `msi`
  - `appimage`
- publishes package artifacts to GitHub Releases
- publishes updater feeds to GitHub Pages at:
  - `updates/windows/stable.json`
  - `updates/linux/stable.json`

## Release Artifacts

The release workflow expects and publishes:

- `.msi`
- `.AppImage`
- `.AppImage.zsync`
- `.update-feed.json`
- backend diagnostics sidecars when present
- `SHA256SUMS`

The packaged updater reads the stable feed URLs from the packaged runtime config.
The feed documents themselves are published to GitHub Pages, while the asset URLs
inside those feed documents point back to GitHub Release downloads.

## Required Secrets

The Windows MSI path supports signing through the reusable packager workflow.

Configure these repository secrets before expecting signed MSI releases:

- `WINDOWS_SIGN_PFX_BASE64`
- `WINDOWS_SIGN_PFX_PASSWORD`
- `WINDOWS_SIGN_CERT_SHA1`

Current MSI signing metadata is declared in `packaging/package.manifest.json`.

## Failure Handling

The release workflow is designed to fail closed for feed publication:

- it first publishes release assets as a draft release
- it then uploads and deploys the GitHub Pages feed content
- it only undrafts the GitHub release after Pages deployment succeeds

If Pages deployment fails:

- the workflow fails
- the release stays draft
- the release must be fixed and rerun before being considered published

## Release Checklist

1. Make sure the target commit on `main` is the one you want to ship.
2. Confirm the manifest feed URLs still point at:
   - `https://danjboyd.github.io/ScreenshotTool/updates/windows/stable.json`
   - `https://danjboyd.github.io/ScreenshotTool/updates/linux/stable.json`
3. Confirm Windows signing secrets are present if a signed MSI is required.
4. Create an annotated tag:

```bash
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

5. In GitHub Actions, verify:
   - `package-windows` succeeded
   - `package-linux` succeeded
   - `publish-release-assets` succeeded
6. In the published release, verify:
   - `.msi` is attached
   - `.AppImage` is attached
   - `.AppImage.zsync` is attached
   - `SHA256SUMS` is attached
7. In Pages, verify:
   - `/updates/windows/stable.json` exists
   - `/updates/linux/stable.json` exists
8. Smoke-test:
   - fresh MSI install
   - fresh AppImage launch
   - in-app `Check for Updates…` against a newer release when available

## Validation Gaps

What has been validated locally:

- updater components build and link
- `gp-update-helper` lands in the app bundle
- `gp-update-helper` lands in the staged bundle
- shared manifest validation passes

What still needs CI or cross-platform confirmation:

- end-to-end Windows MSI packaging on `windows-latest`
- end-to-end AppImage packaging through `release.yml`
- GitHub Pages feed deployment
- full upgrade flow on both platforms
