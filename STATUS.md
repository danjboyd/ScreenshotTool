# ScreenshotTool Status — 2025-10-27

## Clipboard Flattening
- Rebuilt the flattening pipeline to render into an explicit `NSBitmapImageRep` context so GNUstep preserves off-screen strokes (see `Source/ScreenshotCanvasView.m:953`).
- Explicitly clone the source screenshot pixels via `TIFFRepresentation` before drawing markup to work around GNUstep dropping `NSImage` draws into bitmap contexts (`Source/ScreenshotCanvasView.m:974`).
- Added a CPU-side rasterizer for strokes that paints straight into the bitmap data to bypass GNUstep’s `NSBezierPath` off-screen bug, while leaving the standard path as a fallback (`Source/ScreenshotCanvasView.m:146`).
- Skipped `-flushGraphics` on the bitmap context to stop GNUstep from dereferencing a null draw target after copy, with inline notes about the macOS path (`Source/ScreenshotCanvasView.m:880`).
- Documented the GNUstep-only device color normalization inside `MarkupStroke.renderInContext:canvasSize:` to keep highlighter/pen output visible (`Source/MarkupStroke.m:108`).
- Remaining work: manually validate the generated PNG/TIFF data includes markup in a few scenarios and capture a minimal repro for a GNUstep bug report; the macOS build can eventually revert to the simpler `-lockFocus` approach once the upstream issue is fixed.

## Text Overlays
- Text tool now mirrors MSPaint: drag to create a dotted text box, edit inline, and resize the box live while typing (`Source/ScreenshotCanvasView.m:506`).
- Text rendering flattens into the clipboard bitmap via `MarkupText.renderInContext:canvasSize:` and inherits the GNUstep flattening workarounds (`Source/MarkupText.m:45`).
- Toolbar wiring reuses the pen colour well so text colour stays in sync until a dedicated control ships (`Source/AppDelegate.m:401`).

## Selection & Cropping
- Added a marquee selection tool with resize and move handles; the dashed overlay persists across tools for clarity (`Source/ScreenshotCanvasView.m:694`).
- `Copy` now respects the active selection and exports only the marquee contents when present (`Source/AppDelegate.m:744`).
- Introduced `Crop Image` (File ▸ Crop Image / ⌘K) to trim the canvas without flattening strokes/text—markup is translated into the cropped coordinate space so editing can continue (`Source/AppDelegate.m:769`).
- Toolbar icons now use `AddText.png` and `MarqueeTool.png` so the text/select tools match the new workflow (`Source/AppDelegate.m:347`).

## Window/Layout & Menu
- Status bar anchors at the bottom while the scroll view fills the central strip.
- Fit-to-window remains the default with scrollers hidden when not needed.
- `main.m` now follows the nibless guidance: the app warms `NSUserDefaults`, sets the delegate, and drives the run loop with `[NSApp run]` so GNUstep can manage menu windows directly (`Source/main.m:6`).
- When GNUstep runs in `NSWindows95InterfaceStyle`, the main menu is explicitly attached to the content window so the bar embeds in-window without extra reveal workarounds (`Source/AppDelegate.m:316`).
- Window still leaves right-edge slack; needs further tightening once clipboard/selection QA stabilises.

## Action Items
1. QA copy/save output for strokes, text, and marquee selections to confirm pixels survive and watch for colour/alpha artifacts.
2. Verify the nibless menu behaviour on GNUstep (both global and Windows95 styles) now that the menu attaches automatically; capture screenshots for the eventual bug report.
3. Distill the failing `-lockFocus` scenario into a GNUstep bug report and keep the workaround gated for macOS parity.
4. Tighten the window width slack and polish selection UX (e.g., ESC-to-clear) once clipboard work is confirmed.
