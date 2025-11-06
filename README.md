# ScreenshotTool Developer Notes

## Highlights
- **Status Bar Controls**: The bottom bar now exposes a shared width slider for the pen and highlighter. It shows the active tool name, a live pixel readout, and hyperlink actions for *Reset* and *Set as Default*.
- **Tool Popovers**: Double‑click a toolbar button to open a mini settings sheet.
  - Pen & highlighter popovers surface width sliders, quick preset buttons, color pickers, and default/reset affordances.
  - The text popover lets you pick the default text color and font (launches the standard font panel).
- **Color Feedback**: Pen, highlighter, and text toolbar icons render a live colour badge so users always see the currently configured colours.
- **Preferences Window**: A dedicated window (App menu ▸ Preferences… or toolbar button) centralises defaults:
  - Sliders + colour wells for pen/highlighter defaults, quick width presets, and text defaults (colour + font).
  - Default save directory chooser (applies to Open/Save panels) and a global “Show status bar” toggle.
  - “Restore Defaults” resets everything to factory settings.
- **Workspace Defaults**: The default save directory persists between launches. Open/Save panels fall back to this directory when no image has been loaded yet.
- **Copy Workflow**: `copy:` flattens the canvas to PNG/TIFF formats to preserve transparency in downstream editors.
- **Zoom Control**: We keep the GNUstep-friendly `NSPopUpButton` with preset zoom options plus Fit-to-Window.

## Preferences & Environment
- Cursor debug logging is disabled by default. Set `SCREENSHOT_CURSOR_DEBUG=1` before launching the app to stream cursor transition logs to the console.
- Runtime logs (non-cursor) continue to append to `~/git/ScreenshotTool/screenshottool.log` unless `SCREENSHOT_TOOL_LOG_PATH` overrides the path.

## Code Map
- **AppDelegate**: Window management, toolbar wiring, status bar, preference plumbing, and persistence helpers.
- **ScreenshotToolSettings**: Centralises defaults and `NSUserDefaults` keys shared across controllers.
- **ToolSettingsPopoverController / TextToolPopoverController**: Popovers for brush/text configuration.
- **PreferencesWindowController**: Builds the preferences UI and relays user actions back to `AppDelegate`.
- **ScreenshotCanvasView**: Rendering pipeline, zoom handling, and cursor lifecycle.

## Daily Dev Reminders
- `make -j$(nproc)` rebuilds the GNUstep target.
- Default resources sit in `Resources/`; the preferences toolbar icon ships as `Preferences.png`.
- Manual QA checklist: status bar slider updates both tools, popovers stay in sync after preference edits, default save directory drives Open/Save, and hiding the status bar reflows the scroll view correctly.

## Development Process
- Roles: I serve as lead developer while you act as architect, driving design direction and final validation.
- Handoffs: when a feature or fix is ready for review, I rebuild with `make -j$(nproc)`, run the full test suite, and truncate `./debug.log` so you can launch the fresh build and pipe stdout/stderr into that log for inspection.
- Issue Tracking: active bugs live in `./OpenIssues.md`; once resolved they move to `./ClosedIssues.md`. I keep both files current throughout debugging.
- Feature Tracking: any new feature request you raise is recorded here in the README alongside roadmap notes so this document remains the authoritative product overview.
- Daily Status: `STATUS.md` captures in-flight initiatives and end-of-day notes so we always know where to pick up next session.
- Regression Guardrails: whenever we close a bug or finish a feature, I look for opportunities to add or extend tests to lock behaviour in and prevent future regressions.
- Test Harness: run `Tools/run_tests.sh [optional-log-path]` to build the probes and capture the suite output (stdout + stderr) in `tests.log` for Codex review.
