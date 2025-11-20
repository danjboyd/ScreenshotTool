# Contributing / Development Notes

Please follow `WORKFLOW.md` for the expected build/test handoff. Additional context lives here so the user-facing README can stay focused on people running the app.

## Environment & Debugging
- Cursor debug logging: `SCREENSHOT_CURSOR_DEBUG=1` before launch.
- Tooltip debug logging: `SCREENSHOT_TOOL_DEBUG_TOOLTIPS=1` before launch.
- Runtime log path: defaults to `./screenshottool.log`, override with `SCREENSHOT_TOOL_LOG_PATH`.

## Code Map
- `AppDelegate`: window management, toolbar wiring, status bar, preferences, persistence.
- `ScreenshotCanvasView`: rendering pipeline, zoom handling, cursor lifecycle.
- `ToolSettingsPopoverController` / `TextToolPopoverController`: brush/text configuration popovers.
- `PreferencesWindowController`: preferences UI.
- `ScreenshotToolSettings`: defaults and `NSUserDefaults` keys shared across controllers.

## Build & QA Reminders
- Rebuild: `make -j$(nproc)`.
- Full suite: `Tools/run_tests.sh` (sudo may be required on GNUstep for defaults locks).
- Toolbar assets: `scripts/generate_toolbar_icons.sh`, `scripts/generate_active_icons.sh`, `scripts/normalize_toolbar_icons.sh` as needed. See `docs/ToolbarIconsOnGNUstep.md`.
- Manual QA: status bar slider syncs pen/highlighter; popovers reflect preferences; default save directory drives Open/Save; hiding status bar reflows the scroll view; toolbar theme swaps icons; zoom/fitting behave in View menu and pop-up.

## Issue & Status Tracking
- Active/closed bugs: `OpenIssues.md` / `ClosedIssues.md`.
- Daily notes and next steps: `STATUS.md`.
- Tooltip specifics: `docs/GNUstepToolbarTooltips.md`.

## Daily Wrap-Up (internal)
1. Append progress + next steps to `STATUS.md`.
2. Capture unresolved tasks in `OpenIssues.md` with synopsis + theory of the case.
3. Run `Tools/run_tests.sh` so `tests.log` reflects current state.
4. Stage/commit changes; truncate `debug.log` before handing off for manual testing.
