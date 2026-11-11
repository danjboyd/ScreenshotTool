# Mac print vector feasibility (#355)

`STDrawPrintVectorScene` is an isolated source proof. It accepts a physically cropped,
redacted bitmap and renders real `MarkupStroke` and `MarkupText` models over it in a PDF
graphics context. A focused offscreen probe verifies that the generated page has an
XObject draw, a stroked path and a text object. The helper refuses a base whose bitmap
dimensions differ from the selection crop. It clips the target and maps the original
canvas coordinates into that crop.

This is **not wired into printing**. The probe's black redaction patch is synthetic;
it does not exercise the canvas's pixelation algorithm. It does not prove that every
image inside a generated PDF is 80x60 or that all sensitive source bytes are absent.
It does not test pagination, print-preview reentry, physical printers or a native panel.
It deliberately skips text boxes intersecting the selection boundary, because PDF
clipping would hide their glyphs visually while retaining those characters in the PDF.
That visible partial text needs a safe raster fallback or glyph-level clipping before
integration. The same concern applies to callout text and any model whose bounds are
inside while its pointer extends beyond the crop.

The current macOS path in `AppDelegate printWithSelectionOnly:` starts with a fully
flattened image, and its flattener draws redactions plus annotations into one bitmap.
An integrated path needs a canvas API to return only the redacted base and an immutable
annotation snapshot. `STPrintViewTakeOptions` changes `layout.sourceRect` to the cropped
image's local coordinates; a vector pass must retain the original source offset for
selection and page tiling. `STPrintView drawRect:` caches raster tiles and flips the
sheet, so a vector pass must use a matching context transform, clip each page, and
avoid embedding an uncropped full image. The context Print Selection and Share Print
routes both call the same `printWithSelectionOnly:` path; any new scene choice must
apply to both and refresh when the accessory changes selection, paper or fit.
