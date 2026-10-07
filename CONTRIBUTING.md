# Contributing / Development Notes

Please follow `WORKFLOW.md` for the expected build/test handoff. Additional context lives here so the user-facing README can stay focused on people running the app.

## Environment & Debugging
- Cursor debug logging: `SCREENSHOT_CURSOR_DEBUG=1` before launch.
- Tooltip debug logging: `SCREENSHOT_TOOL_DEBUG_TOOLTIPS=1` before launch.
- Runtime log path: defaults to `~/.local/state/screenshottool/screenshottool.log` on GNUstep/Linux and `~/Library/Logs/ScreenshotTool/screenshottool.log` on macOS; override with `SCREENSHOT_TOOL_LOG_PATH`.

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
- Manual QA: status bar slider syncs pen/highlighter; popovers reflect preferences; default save directory drives Open/Save; hiding status bar reflows the scroll view; theme switches recolour the symbolic icons; zoom/fitting behave in View menu and pop-up.

## Issue & Status Tracking
- Bugs, features and planned work: [GitHub Issues](https://github.com/danjboyd/ScreenshotTool/issues).
- Older notes from before the move to GitHub Issues: `OpenIssues.md`, `ClosedIssues.md` and `STATUS.md` (archived).
- Tooltip specifics: `docs/GNUstepToolbarTooltips.md`.

## Daily Wrap-Up (internal)
1. Open or update a GitHub issue for unresolved work, with a synopsis and theory of the case.
2. Describe the change and its testing in the pull request.
3. Run `Tools/run_tests.sh` so `tests.log` reflects current state.
4. Stage/commit changes; truncate `debug.log` before handing off for manual testing.
