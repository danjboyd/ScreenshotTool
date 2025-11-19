# Custom Cursor Glyph Investigation

This document captures the current state of the GNUstep custom cursor regression, the experiments we have already performed, and an incremental strategy Codex can follow to bring the feature back without relying on manual spot checks.

## Problem Statement

Pen, highlighter, and text tools each request themed cursor images, but on GNUstep the pointer never changes away from the default arrow. Logs confirm that `ScreenshotCanvasView` still calls `-[NSCursor set]`, so either GNUstep never receives our cursor rects or the cursor assets fail to load/register once the app is packaged.

## Previous Findings

- `ScreenshotCanvasView` already chooses tool-specific cursors via `cursorForActiveTool` and updates cursor rects from `resetCursorRects`. The view tracks `mouseEntered:`/`mouseExited:` events, so the failure seems downstream of our code.
- Packaging audit shows the TIFF/PNG cursor assets plus `markup-cursors.metadata.json` exist in `Resources/Cursors/`.
- GNUstep logs show that `NSCursor` defaults stay in effect, suggesting either the custom cursor objects are `nil` or GNUstep requires explicit cursor registration at the window level rather than per view.
- Cursor debug logging is disabled by default; only the high-level `[Cursor]` logs in `ScreenshotCanvasView` are currently available when `SCREENSHOT_CURSOR_DEBUG=1`.

## Iterative Strategy

The goal is to let Codex loop on fixes autonomously: make a change, rebuild, run a deterministic validation command, and inspect machine-readable output before moving on.

### 1. Instrument and tighten logging

1. Extend `ScreenshotCanvasView` cursor logging (guarded by `SCREENSHOT_CURSOR_DEBUG`) so every phase writes structured messages:
   - `CursorAssetLoad`: tool key, bundle path, file existence, bitmap size.
   - `CursorConstructed`: tool key, hotspot, rep count.
   - `CursorRectApplied`: tool, bounds, `mouseInside` flag, tracking tag.
   - `CursorSet`: tool key, pointer of `NSCursor currentCursor]`.
2. Add a GNUstep-only warning when `customCursorForToolKey:` returns `nil` or falls back to the arrow cursor.
3. Ship a helper script (or Makefile target) that runs `SCREENSHOT_CURSOR_DEBUG=1 openapp ... | tee cursor.log` so every iteration reuses the same reproducible scenario.

**Self-check:** Each run should produce the full sequence (`CursorAssetLoad`, `CursorConstructed`, `CursorRectApplied`, `CursorSet`). Missing entries or repeated fallback warnings point straight to the component that still needs work.

### 2. Validate asset packaging automatically

1. Add a lightweight unit test (the new `CursorAssetProbe` in `Tests/`) that loads `Resources/Cursors`, enumerates `pen/highlighter/eraser` variants, and asserts that every metadata entry resolves to a readable file.
2. Run it directly (`make Tests/bin/CursorAssetProbe && Tests/bin/CursorAssetProbe`) or via `Tools/run_tests.sh` so Codex knows immediately whether a packaging change broke cursor assets.

**Self-check:** The probe should fail fast with explicit error messages (missing file, unexpected format, hotspot absent). Once it passes, Codex can focus on event handling instead of bundle plumbing.

### 3. Prove cursor rects fire on GNUstep

1. Build a small harness test (`CursorRectProbe`) that instantiates `ScreenshotCanvasView`, injects a mock window, toggles `mouseInsideCanvas`, and calls `resetCursorRects`.
2. Instrument the view so the probe can read back the last cursor object via an accessor (test-only category). The probe verifies that:
   - `mouseInsideCanvas` flips to `YES` when expected.
   - `addCursorRect:` received a non-arrow cursor for pen/highlighter tools.
3. The probe should exit with non-zero status if the cursor never changes, giving Codex an automated regression signal.

**Self-check:** Run `Tools/run_tests.sh CursorRectProbe` after every code change; green output means the view logic is intact and the issue likely sits in GNUstep’s window manager.

### 4. Drive an end-to-end GNUstep scenario with log assertions

1. After rebuilding, execute `./scripts/run_cursor_debug.sh` (it exports the GNUstep tool/lib paths, enables `SCREENSHOT_CURSOR_DEBUG=1`, and uses `xdotool`/`wmctrl` to activate the ScreenshotTool window + move the mouse over the canvas automatically). The script writes stdout to the terminal while teeing everything to `./debug.log`.
2. Post-process `debug.log` (a simple `rg "CursorSet"` is enough) to ensure the selected tool logged the custom cursor. If automation worked you should also see `[CursorEvent] event=mouseEntered` or `assumeInside=1`.
3. If the cursor still renders as an arrow visually, extend logging to capture GNUstep’s `-invalidateCursorRectsForView:` / `-resetCursorRects` flow or experiment with registering cursors at the window level while the log harness continues to report progress.

**Self-check:** Each iteration must end with `CursorSet tool=pen class=NSCursor tinted=YES` (or similar). If GNUstep still shows the arrow, Codex can compare iterations quickly to spot what changed.

> **Current observation (2025-11-19):** Even with the automated `xdotool` focus/mouse move, the latest `debug.log` still reports `isArrow=1` for every `[CursorSet]` entry, so GNUstep continues to swap our custom cursor out. Once the log starts showing `assumeInside=1` with `isArrow=0`, we’ll know the runtime side is finally honoring the custom glyphs.

> **Update (later 2025-11-19):** After forcing GNUstep builds to keep the canvas as first responder, always enabling `setAcceptsMouseMovedEvents:`, and letting `shouldShowCanvasCursor` return `YES` whenever the canvas window is key, the automated log finally reports `[CursorRectApplied ... isArrow=0]` followed by `[CursorSet ... mouseInside=1 ... isArrow=0]`. We still need to tighten the actual hover semantics (so we only show custom cursors when the mouse is truly over the canvas), but the current automation proves the tinted cursor construction path and resource packaging work end-to-end again.

### 5. Lock behaviour with a regression probe

1. Once GNUstep honours the custom cursors again, codify the fix in a new probe:
   - Launch a headless app.
   - Create a `ScreenshotCanvasView`, set `activeTool` to pen, and synthesize a `mouseEntered` event.
   - Assert that the cursor instance now equals the tinted pen cursor (e.g., check `[cursor.image TIFFRepresentation]` against the expected asset hash).
2. Add probe coverage for both pen (tinted) and eraser (untinted) to catch asset or tinting regressions separately.
3. Wire the probe into `Tools/run_tests.sh` so Codex notices failures immediately, even without UI testing.

**Self-check:** From here on, every CI or local test run guarantees that a regression (missing metadata, nil cursor, forgotten `invalidateCursorRects`) fails loudly.

## Measuring Success Per Iteration

| Stage | Command / Check | Expected Output |
| --- | --- | --- |
| Instrumentation | `SCREENSHOT_CURSOR_DEBUG=1 openapp …` | Structured `CursorAssetLoad` + `CursorSet` logs for each tool |
| Asset Probe | `Tools/run_tests.sh CursorAssetProbe` | Green pass; failures specify missing files |
| Cursor Rect Probe | `Tools/run_tests.sh CursorRectProbe` | Confirms view emits custom cursor objects |
| End-to-end | `rg "CursorSet" debug.log` | Shows tool names + cursor objects |
| Regression Test | `Tools/run_tests.sh` | Includes `CursorGlyphProbe` cases |

Codex can run these in sequence after every substantive change; stopping at the first failure keeps the investigation tight.

## Guardrails Against Future Regressions

1. Keep cursor metadata and assets co-located under `Resources/Cursors/` and update the asset probe whenever new cursors land.
2. Never skip `Tools/run_tests.sh`; the eventual cursor probe will fail if the GNUstep path slips.
3. Leave `SCREENSHOT_CURSOR_DEBUG` logging in place (gated by the env var) so QA can capture cursor transitions quickly whenever bugs reappear.
4. Document the standard reproduction recipe (command above) in `README.md` once the fix ships so the team remembers how to validate the feature interactively.

Following this flow ensures each root cause is either confirmed or eliminated with concrete evidence, and once the regression probe lands, future builds cannot silently lose the custom cursors again.
