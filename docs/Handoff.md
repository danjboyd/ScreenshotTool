# Handoff

Date: 2026-03-26

## Current State

- `main` is prepared for a public FOSS release.
- Latest AppImage packaging fix is commit `b449a8b` (`Fix AppImage GNUstep runtime packaging`).
- Latest local test artifact:
  - `Staging/ScreenshotTool-vtest-x86_64.AppImage`
  - `Staging/ScreenshotTool-vtest-x86_64.AppImage.sha256`
- Current AppImage SHA-256:
  - `6ad815215d4f1cb3a9d071a40e7e517cdd768dbb7b78d3a6215b8ae5b7503982`

## What Was Fixed Today

- The AppImage launcher now generates a runtime `GNUstep.conf` with absolute paths based on the mounted AppImage location.
- The AppImage no longer depends on host GNUstep configuration files.
- `linuxdeploy` now scans the GNUstep backend bundle (`libgnustep-back-032.bundle`) so backend-only dependencies are packaged too.
- This specifically pulled in missing backend-side libraries such as `libXft`, `libXmu`, and `libXt`.

## Validation Already Done

- `scripts/smoke_appimage.sh Staging/ScreenshotTool-vtest-x86_64.AppImage`
- Clean-environment launch:
  - `env -i HOME=/tmp PATH=/usr/bin:/bin DISPLAY=:0 XAUTHORITY=... APPIMAGE_EXTRACT_AND_RUN=1 Staging/ScreenshotTool-vtest-x86_64.AppImage ...`
- Both of those passed on the development machine after the final AppImage rebuild.

## First Step Tomorrow

Validate the rebuilt AppImage on the Debian live USB:

```bash
cd /path/to/copied/files
sha256sum -c ScreenshotTool-vtest-x86_64.AppImage.sha256
chmod +x ScreenshotTool-vtest-x86_64.AppImage
APPIMAGE_EXTRACT_AND_RUN=1 ./ScreenshotTool-vtest-x86_64.AppImage /usr/share/pixmaps/debian-logo.png
```

## Decision Tree

- If the Debian live USB launch succeeds:
  - AppImage packaging is in good shape.
  - Next likely step is tagging a real release and verifying the GitHub Actions release flow uploads the AppImage asset.
- If the Debian live USB launch fails:
  - Capture the full terminal output.
  - Compare it against the previous backend failure:
    - `Unable to find backend back`
  - The next debugging target is whatever dependency or runtime path the clean machine still lacks.

## Useful Context

- Release workflow support already exists from `c9770fc` (`Operationalize AppImage release packaging`).
- The normal release flow is intended to be:

```bash
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

- Before any future push, keep using the `danjboyd` GitHub account as required by `AGENTS.md`.
