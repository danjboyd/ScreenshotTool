# ScreenshotTool

ScreenshotTool lets you open a screenshot (or any image), mark it up with pen/highlighter/text tools, and save or copy the annotated result. It is built with GNUstep for Linux/BSD desktops.

## Features
- Pen, highlighter, eraser, and text tools with adjustable width/colour plus live colour badges on toolbar icons.
- Status bar with shared width slider, pixel readout, and quick “Reset/Set as Default” actions.
- Tool popovers (double-click toolbar buttons) and a full Preferences window for defaults, toolbar theme, and status bar visibility.
- Theme-aware toolbar icons (light/dark/Auto) and a GNUstep-friendly toolbar layout.
- Fit-to-window and fixed zoom presets (25%, 50%, 100%, 200%) with matching View menu items.
- Copy-to-clipboard exports preserve transparency; Save As writes annotated PNG/TIFF output.

## Install & Build
Prerequisites: GNUstep GUI toolchain (gnustep-make, gnustep-base, gnustep-gui), Clang, and standard build tools.

```bash
make -j"$(nproc)"
```

The default GNUstep build links `third_party/libs-OpenSave`, so `NSOpenPanel` and `NSSavePanel` use the native GTK/GNOME dialogs when available:
```bash
git submodule update --init --recursive
make -j"$(nproc)"
```
Notes:
- `USE_OPENSAVE=0` disables `libs-OpenSave` and falls back to pure GNUstep panels.
- `SCREENSHOT_TOOL_OPENSAVE_MODE=gnustep` forces GNUstep panel mode at runtime for fallback troubleshooting.
- GTK4 development files are needed for GTK-backed dialogs; without them, dialogs fall back to GNUstep behavior.

### macOS (Cocoa-native, no GNUstep runtime)
```bash
scripts/build_cocoa.sh                              # builds build/cocoa/ScreenshotTool.app
scripts/smoke_macos_app.sh build/cocoa/ScreenshotTool.app    # writes ./screenshottool-smoke.log
scripts/package_macos_dmg.sh build/cocoa/ScreenshotTool.app  # optional DMG
```
Requires Xcode Command Line Tools; no GNUstep runtime needed on macOS.

If you want to run the automated probes:
```bash
Tools/run_tests.sh   # may require sudo on some systems for GNUstep defaults locks
```

## Run
Launch the bundled app with an image path:
```bash
openapp ./ScreenshotTool.app/ ~/Pictures/Screenshots/your-image.png
```

Runtime logs write to `./screenshottool.log` by default; override with `SCREENSHOT_TOOL_LOG_PATH=/tmp/screenshottool.log`.

## Usage Tips
- Double-click toolbar buttons to open tool popovers; use Preferences for persistent defaults (toolbar theme, default save folder, show/hide status bar).
- Fit the canvas with View ▸ Fit to Window or pick a fixed zoom (25/50/100/200%). Zoom In/Out shortcuts also step through scales.
- Crop to selection, copy annotated output, or Save As… PNG/TIFF. Default save directory persists across sessions.

### Keyboard Shortcuts (GNUstep)
- Copy: `Ctrl+C`
- Save As…: `Ctrl+S`
- Crop to Selection: `Ctrl+K`
- Zoom In/Out: `Ctrl+=` / `Ctrl+-`
- Preferences: `Ctrl+,`

## License
GNU GPL v2 or later (see `COPYING`).

## Contributing
Developer workflow, debugging knobs, and QA notes now live in `CONTRIBUTING.md` and `WORKFLOW.md`. Issues and closed items are tracked in `OpenIssues.md` / `ClosedIssues.md`.

## Packaging
AppImage + macOS DMG packaging scripts live in `docs/Packaging.md`; CI builds both artifacts on Ubuntu and macOS via `.github/workflows/build.yml`.
