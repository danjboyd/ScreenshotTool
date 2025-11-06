# GNUstep Bug Report Notes

## Environment
- App: ScreenshotTool (nibless Objective‑C, GNUstep backend)
- GNUstep-make: 2.9.3 (strict mode)
- Toolkit: `gnustep-corebase`, `gnustep-gui`
- Platform: Debian-based desktop (x86_64-linux-gnu)

## Issue 1 — Clipboard/Save Drops Text Overlays
- **Symptom:** After adding pen/highlighter strokes and text overlays, the clipboard PNG/TIFF and “Save As…” PNG omit the text while preserving strokes/highlighter.
- **Repro:**
  1. Launch `debugapp ./ScreenshotTool.app/ <image>`.
  2. Use the text tool to add text (resize box, include multiple lines).
  3. Press `Ctrl+C`, paste into GIMP → text missing.
  4. Choose File ▸ Save As…, open PNG in GIMP → text missing.
- **Diagnostics:**
  - When flattening via `NSAttributedString drawInRect:` into `NSBitmapImageRep`, the bitmap contains only transparent pixels for text.
  - Logging inside a CPU rasterizer reports: `STRasterizeTextOntoBitmap: no pixels drawn for text '…'`.
- **Workaround Implemented:** Gate a GNUstep-only FreeType/fontconfig rasterizer that resolves the font file and renders glyph coverage directly into the bitmap (bypassing GNUstep’s off-screen `NSAttributedString` drawing).
- **Action:** Report to GNUstep that rasterizing attributed strings into `NSBitmapImageRep` via `drawInRect:` yields no glyph data even though on-screen draws succeed.

## Issue 2 — Scroll View Crash While Toggling Zoom
- **Symptom:** Pressing `Ctrl−` twice followed by `Ctrl+=` twice crashed with a deep recursion. GDB stack shows `NSScrollView tile` repeatedly flipping `setHasHorizontalScroller:` / `setHasVerticalScroller:` and `reflectScrolledClipView:`.
- **Repro:**
  1. Launch `debugapp ./ScreenshotTool.app/ <image>`.
  2. Press `Ctrl−` twice, then `Ctrl+=` twice.
  3. Application crashes with SIGSEGV inside `objc_msgSend_fpret`.
- **Diagnostic Stack (excerpt):**
  ```
  -[NSScrollView setHasHorizontalScroller:]
  -[NSScrollView reflectScrolledClipView:]
  -[NSClipView setFrame:]
  -[NSScrollView tile]
  … (repeats hundreds of times) …
  ```
- **Cause:** GNUstep toggles the scrollers during `tile`; our code’s attempt to mirror the `fitToWindow` state magnified the loop, leading to runaway recursion and a segmentation fault.
- **Workaround Implemented:** Removed manual scroller toggling during zoom; allow GNUstep to manage scroller visibility.
- **Action:** File a bug noting that `NSScrollView` repeatedly toggles scrollers to the point of stack overflow when client code flips `hasHorizontalScroller`/`hasVerticalScroller` during `tile`. Include the reproduction sequence above.

## Suggested Report Attachments
- Console log showing `STRasterizeTextOntoBitmap` warning.
- GDB backtrace highlighting the scroller recursion.
- Minimal test case: lightweight app that draws text into `NSBitmapImageRep` and inspects the pixels.

## Issue 3 — Toolbar Containers Reattach Native Tooltips
- **Symptom:** Even after setting `NSToolbarItem.toolTip = nil`, clearing the custom view’s tooltip, and removing all tracking rects, GNUstep reinstates native tooltips on the container view (`GSToolbarBackView`). Hovering over toolbar buttons shows the native yellow bubble instead of the app’s custom tooltip window.
- **Repro:**
  1. Create a toolbar item with a custom `NSButton` view.
  2. Call `removeAllToolTips` + `setToolTip:nil` on the button and its immediate/super-super view.
  3. Register the custom view with a tracking-based controller (no native tooltip strings).
  4. Launch under GNUstep: hovering still triggers the native tooltip bubble.
- **Diagnostics:**
  - `GSToolbarBackView` retains a tooltip entry even after `removeAllToolTips`.
  - Regression probe (`TooltipsSuppressedProbe`) constructs a “native” container and confirms `setToolTip:nil` leaves the container with a tooltip string.
- **Workaround Implemented:** Before registering custom tooltips we now scrub `removeAllToolTips` / `setToolTip:nil` on the custom view and the first two ancestor views; the regression probe asserts those containers end up tooltip-free.
- **Action:** Report that GNUstep toolbar container views silently restore native tooltips after clients clear them, preventing custom tooltip controllers from taking over.

## Follow-Up
- Once GNUstep resolves the text rendering bug, we can remove the FreeType/fontconfig path and revert to the simpler `NSAttributedString` flattening.
- After the scroll-view issue is addressed upstream, consider reintroducing optional scroller hiding logic if needed.
