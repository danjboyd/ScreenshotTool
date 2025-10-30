# ScreenshotTool Status — 2025-10-29

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
- Clipboard pipeline still rasterises via `NSBitmapImageRep` + CPU strokes to dodge GNUstep off-screen bugs; needs revalidation after today’s UI changes.
- Cursor tinting honours active tool colours; debug logging stays gated via `SCREENSHOT_CURSOR_DEBUG=1`.

## Open Questions / Follow-Ups
1. Regression sweep on GNUstep: ensure popovers, status bar slider, and Preferences stay in sync (including restored defaults) with the new Font Panel integration.
2. QA hiding/showing status bar, zoom/fitting, and toolbar colour badges to catch layout or refresh issues.
3. Verify default save directory behaviour on GNOME (permissions, network shares) now that the path auto-creates and drives Open/Save.
4. Clipboard QA: copy/paste annotated images into target editors to confirm no transparency regressions after today’s merges.
5. Cursor hotspot polishing for pen/highlighter still outstanding; revisit `markup-cursors.metadata.json` once asset tweaks land.
