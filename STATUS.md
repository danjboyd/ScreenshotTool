# ScreenshotTool Status — 2025-11-13

_Progress entries run newest → oldest._

## Progress (2025-11-13)
- Swapped in the DateTracker-style toolbar on GNUstep while keeping our original implementation available behind a flag so we can flip back once the custom container bug is fixed.
- Added a user-visible “Toolbar Theme” control in Preferences plus a persistent interface-theme default; toolbar icons now select the `*-dark`/`*-light` variants based on either the Sombre heuristic or the explicit preference.
- Investigated the clipped icon issue: GTK/GNUstep still constrains standard toolbar rows to ~24 px, so 32 px art is cropped; in-memory downscaling via `STRasterizeToolbarIcon` caused the icons to vanish, so we reverted and will experiment with GNUstep-specific 24 px assets next.
- `Tools/run_tests.sh` currently times out because each probe fails to create `/home/danboyd/GNUstep/Defaults/.lck/.GNUstepDefaults.lck` (permission denied); no automated results for today.
- Captured the toolbar-theme work in `README.md` (Highlights + Toolbar QA checklist) and logged the dark-theme/Sombre blank-toolbar regression in `OpenIssues.md` so the DateTracker fallback removal has a tracking item.
- Added GNUstep-specific 24 px toolbar assets plus a `scripts/generate_toolbar_icons.sh` helper, and clamped `ToolbarIconDimension` to 24 px on GNUstep builds so the DateTracker baseline renders crisp, unclipped icons while Cocoa keeps the full 32 px glyphs.
- Documented the full toolbar workflow in `docs/ToolbarIconsOnGNUstep.md`, generated DALL·E art + ImageMagick active variants, and simplified `AppDelegate` so GNUstep always uses the working DateTracker baseline.
- The Pen/Highlighter popovers now adopt Sombre-friendly colors, non-selectable labels, and aqua hyperlinks; the Text popover shares the same `STFloatingPopover`, wider layout, and a dedicated issue tracks the remaining swatch clipping.
- Replaced every dark toolbar glyph with DALL·E-generated art tailored to Sombre, regenerated light/dark + GNUstep variants, and layered ImageMagick-driven glow/outline “active” states via `scripts/generate_active_icons.sh`.
- Normalized every toolbar PNG to 8-bit RGBA (`scripts/normalize_toolbar_icons.sh`) so GNUstep’s bitmap loader stops reporting “no visible pixels,” then regenerated all active/light/dark GNUstep assets with the updated tooling.
- Relaxed the GNUstep `STBitmapRepHasVisiblePixels` check to treat any pixel with alpha > 0.05 as “visible” (instead of requiring brightness > 0.20), which keeps dark icons from being flagged as empty and fixes the corrupted toolbar rendering.

## Progress (2025-11-05)
- Hardened GNUstep tooltip flow: AppDelegate now routes Pen/Highlighter/Text/Select/Eraser buttons through custom `STToolbarButton` views so native hints stay nil while Cocoa builds retain default tooltips.
- Added snapshot accessors to `STToolbarTooltipController` and tightened registration logic; controller updates no longer rely on KVC into private dictionaries.
- Reworked `TooltipsSuppressedProbe` with a probe-only delegate and fake toolbar so the suite asserts tracking rect registration, verifies controller strings, and fails immediately if native tooltips return (without provoking the GNUstep toolbar crash).
- Full test suite passes via `Tools/run_tests.sh`; all clipboard/highlighter and toolbar badge probes still green.

## Progress (2025-11-03)
- Crop-to-selection now registers a proper undo snapshot and the window size re-expands when undo restores the original image.
- Status bar messages no longer contaminate the shared undo stack; the delegate now suppresses undo registration while touching the status text field.
- Added headless probes (`make tests`) to lock in crop/undo and window-resize behaviour; wiring is in place pending further clean-up of GNUstep defaults warnings.
- Restored custom GNUstep toolbar tooltips with a rounded panel, dynamic text wrapping, and proper show/hide cycles so hover feedback now persists beyond the first item.
- Disabled native GNUstep tooltips while keeping Cocoa builds unchanged, and gated all tooltip diagnostics behind `SCREENSHOT_TOOL_DEBUG_TOOLTIPS` to keep default logs quiet.
- Added `TooltipsSuppressedProbe` so the test suite asserts GNUstep keeps native tooltips disabled and the custom controller owns toolbar hover hints.
- Hardened `TooltipsSuppressedProbe` with a test-only toolbar harness so we assert controller registration plus nil tooltips on both the `NSToolbarItem` and its custom view.
- Rebuilt ScreenshotTool after the tooltip refactor; `openapp ./ScreenshotTool.app/ … 2>&1 | tee ./debug.log` validated minimal startup noise without the env var set.
- Follow-up: ensure the Highlighter, Pen, and Text toolbar icons reliably render the active colour badges (GNUstep caching still appears to hold onto stale artwork).
- Clipboard flattening on GNUstep now keeps highlighter strokes when copying; the direct bitmap raster path handles translucent overlays and the new `ClipboardHighlighterProbe` passes.
- Added `ClipboardHighlighterOpacityProbe` to capture the stacking-opacity regression, and updated GNUstep rasterisation so repeated strokes stay translucent; the probe now matches the on-screen blend.

## Tool Controls & Popovers
- Status bar exposes a unified width slider + readout, along with `Reset`/`Set as Default` links that sync with stored defaults. The bar can be hidden via Preferences; layout reflows when it’s off.
- Double-clicking Pen/Highlighter launches popovers with width presets, colour wells, and default management; double-clicking Text opens a popover with live colour preview and defers to the Font Panel for face/size changes.
- Toolbar icons render colour badges for Pen/Highlighter/Text so users get instant visual feedback even when the status bar is hidden.

## Preferences & Persistence
- Preferences window now hosts drawing defaults (sliders + quick presets), text defaults (colour + Font Panel button with live summary), interface options, and default save directory. “Restore Defaults” resets the full set.
- Default save directory drives both Open/Save panels when no image is loaded; path is created on demand and persisted via `NSUserDefaults`.
- Status bar visibility toggle persists; all sliders/colours remain in sync across status bar, popovers, and preferences.

## Menu & Navigation
- App menu exposes Preferences (⌘,) and the File menu shortcut is now case-insensitive (`Ctrl+s`/`Ctrl+S`). Edit ▸ Crop to Selection (⌘K / Ctrl+K) replaces the redundant File entry.
- Toolbar gained a Preferences item with the new `Preferences.png` asset.

## Clipboard & Rendering
- Clipboard pipeline still rasterises via `NSBitmapImageRep` + CPU strokes to dodge GNUstep off-screen bugs; highlighter overlays now match on-canvas translucency and both clipboard probes (`ClipboardHighlighterProbe`, `ClipboardHighlighterOpacityProbe`) pass.
- Cursor tinting honours active tool colours; debug logging stays gated via `SCREENSHOT_CURSOR_DEBUG=1`.

## Toolbar QA
- Custom tooltip window now replaces native GNUstep hints; confirm no regressions when switching tools rapidly or moving the window between monitors.
- Toolbar icons still show original colours despite badge overlay refresh; need to trace GNUstep caching or re-render workflow so Highlighter/Pen/Text artwork always reflects the selected colour.
- Today’s work: generated light/dark PNGs for every toolbar tool, added theme-aware icon selection, normalized NSImage rendering, and introduced `ToolbarIconThemeProbe` (currently failing) so the test suite now matches the “blank toolbar” bug we see in Sombre. Next up is fixing GNUstep to respect the custom container image + label colours so the probe and app both pass.

## Open Questions / Follow-Ups
1. Regression sweep on GNUstep: ensure popovers, status bar slider, and Preferences stay in sync (including restored defaults) with the new Font Panel integration.
2. QA hiding/showing status bar, zoom/fitting, and toolbar colour badges to catch layout or refresh issues.
3. Verify default save directory behaviour on GNOME (permissions, network shares) now that the path auto-creates and drives Open/Save.
4. Clipboard QA: copy/paste annotated images into target editors to confirm no transparency regressions after today’s merges (including the restored highlighter overlay).
5. Cursor hotspot polishing for pen/highlighter still outstanding; revisit `markup-cursors.metadata.json` once asset tweaks land.
6. Regression (toolbar colour badges): Pen/Highlighter/Text buttons no longer display the coloured indicator dots; re-enable badge rendering after the async refresh refactor.
