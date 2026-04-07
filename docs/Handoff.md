# Handoff

Date: 2026-04-07

## Current State

- Phase 11 is implemented in the repo through `11H`.
- The remaining work is release execution and cross-platform verification, plus one active Windows MSI runtime blocker.
- The current release/update implementation lives in:
  - `packaging/package.manifest.json`
  - `scripts/build_release.ps1`
  - `scripts/stage_release.ps1`
  - `scripts/bootstrap_gnustep_linux_ci.sh`
  - `.github/workflows/release.yml`
  - `third_party/gnustep-packager-updater/objc/`
  - `docs/Packaging.md`

## Active Branch And Debug Track

- Current branch: `debug/windows-startup-log`
- Latest branch commits:
  - `25f64e1` `Use WinUITheme as Windows default theme`
  - `679b9f5` `Stage WinUXTheme for Windows runtime`
  - `5434a4d` `Add Windows bootstrap startup logging`
- `main` still points at:
  - `7c17518` `Fix Windows staged app launcher target`

This debug branch exists because Windows packaging/install works, but packaged
Windows app launch does not yet succeed.

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

## Windows MSI Debugging Already Done

- A preview MSI was successfully built and installed earlier from the packaging pipeline.
- MSI install itself succeeds on fresh Windows VMs.
- The prior Windows launcher issue (`Windows error code: 193`) was diagnosed and fixed by changing the package launch target to the real PE executable:
  - `app/ScreenshotTool.app/ScreenshotTool.exe`
- The packaged GNUstep backend lookup is now working:
  - the app loads `libgnustep-back-032.bundle` from the private runtime
- Bootstrap logging was added in `Source/main.m` to trace startup before the app's own logging comes online.
- Current startup trace on Windows reaches:
  - `main: entry argc=...`
  - `main: before sharedApplication`
- Then the process aborts inside `[NSApplication sharedApplication]`.

## Windows Preview Workflow History

- Successful preview package run on `main`:
  - `24097147727`
- Successful preview package run on `debug/windows-startup-log`:
  - `24101441578`
  - this produced the debug MSI used to confirm the app dies inside `sharedApplication`
- Failed preview package run trying to bundle `WinUXTheme`:
  - `24102320222`
  - failure: `WinUXTheme` build hit the Windows `mode_t` typedef conflict
- Failed preview package run after switching to `WinUITheme`:
  - `24105870853`
  - failure: `plugins-themes-winuitheme/Scripts/Prepare-GNUstepCompat.ps1` expects:
    - `C:\msys64\mingw64\lib\libgcc_s.a`
  - but the release runner is using MSYS2 `CLANG64`, so that path is absent

## Current Windows Theme Strategy

- We are no longer trying to make `WinUXTheme` the default.
- Current direction is to use `WinUITheme` as the Windows default theme.
- Current repo changes on the debug branch:
  - `Source/main.m`
    - defaults `GSTheme=WinUITheme` on Windows before AppKit startup
  - `packaging/package.manifest.json`
    - sets `launch.env.GSTheme = { value: "WinUITheme", policy: "ifUnset" }`
    - keeps Windows `entryRelativePath` on `app/ScreenshotTool.app/ScreenshotTool.exe`
    - validates for `runtime/lib/GNUstep/Themes/WinUITheme.theme/WinUITheme.dll`
  - `scripts/stage_release.ps1`
    - resolves/clones `danjboyd/plugins-themes-winuitheme`
    - runs its optional `Scripts/Prepare-GNUstepCompat.ps1`
    - installs `WinUITheme`
    - stages `WinUITheme.theme` into both:
      - `runtime/lib/GNUstep/Themes`
      - `runtime/System/Library/Themes`

## Current Blocker

- The Windows preview package is currently blocked by the `WinUITheme` repo's compatibility bootstrap, not by ScreenshotTool app code.
- Exact failure from run `24105870853`:
  - `Missing GNUstep compatibility library at C:\msys64\mingw64\lib\libgcc_s.a`
- Interpretation:
  - the theme repo's compatibility helper is assuming `mingw64`
  - our Windows packaging pipeline uses `msys2/clang64`
  - the next fix likely belongs in either:
    - ScreenshotTool's theme staging shim, to adapt the environment for `CLANG64`, or
    - the upstream `plugins-themes-winuitheme` compatibility script itself

## Windows VM Status

- The Windows VM is not ready for manual user testing.
- Reason:
  - no new fixed MSI has been produced after the switch to Windows theme bundling
  - the last two preview theme-bundling attempts failed during packaging
- Do not send the user to the VM until a new preview MSI is generated, installed, and launch-smoke-tested.

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

1. Fix the `WinUITheme` compatibility bootstrap for `CLANG64`.
2. Re-run `package-windows-preview.yml` on `debug/windows-startup-log`.
3. If that succeeds:
   - download the new MSI
   - install it on the disposable Windows VM
   - verify whether startup gets past `sharedApplication`
4. Only after Windows preview MSI launch is confirmed:
   - resume test-tag `release.yml` validation
   - run interactive VM QA

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

Windows preview workflow:

```bash
gh workflow run package-windows-preview.yml --ref debug/windows-startup-log -f package_version=0.1.0-debugX -f sign_artifacts=false
gh run list --workflow package-windows-preview.yml --limit 5
gh run view <run-id> --json jobs
gh api repos/danjboyd/ScreenshotTool/actions/jobs/<job-id>/logs > /tmp/windows-preview.log
tail -n 160 /tmp/windows-preview.log
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
- During this session, `gh` auth drifted to `dboyd-invitoep`; it was switched back to `danjboyd` before the last push.
