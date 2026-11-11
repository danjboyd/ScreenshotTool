# Mac #355 vector print integration plan

Base for this plan: local `6d9f5cc` print entrypoints plus the isolated `3fcb760`
PDF scene proof. This is a source plan, not a wired product change. The current print
path still flattens all annotations into a bitmap.

## Scene contract

Capture one immutable scene when the native print operation starts: original image
pixel size and point size, a cropped redacted bitmap, the crop's original top-left
image-pixel rect, and copies of the ordered `MarkupStroke`/`MarkupText` models.
Before extracting that scene, commit any active text editor once, as flattening does.
All redactions must be applied to the original capture pixels before any scaling;
the bitmap must then be physically cropped to the print source rect. The PDF must
never receive the unredacted source or an uncropped full-image backing object when
printing a selection. The current `flattenedImageForPrintAtScale:withinRect:` can be
split after its redaction pass to produce this base without drawing other annotations.
Keep its existing fully flattened result as the safe fallback.

The scene should carry both `originalSourceRect` and `localRasterRect`. The first is
needed to map model points into the PDF; the second is what `STPrintLayout` currently
uses after `STPrintViewTakeOptions` resets `layout.sourceRect` to a crop-local rectangle.
Avoid reconstructing the original offset from a page index or from a scaled image.
For Retina images, convert between source pixels and `NSImage.size` points explicitly;
the `3fcb760` proof assumes one point per pixel and cannot be wired unchanged.

## Page drawing

Extend `STPrintView` with an optional immutable vector scene. For each page, obtain
`sourceRectForPage:` and `pageRectForPage:` from the same `STPrintLayout` used today.
Draw only the page's physical raster crop (or an already cropped tile) into the target
under a target clip, then map original image coordinates through the saved source
offset and page scale. Render non-redaction `MarkupStroke` and `MarkupText` using their
existing `renderInContext:canvasSize:` methods. The sheet is flipped in `STPrintView`;
use one verified transform matching `STDrawPrintPage` and cover portrait, landscape,
fit, actual size and multi-page tiles. Invalidate both raster tiles and vector scene
on accessory paper, orientation, fit, scale or selection changes. Avoid a second
snapshot of mutable canvas state during pagination or print-preview reentry.

Keep current annotation order and compositing: redactions are baked into the raster,
ordinary strokes follow, then text. There is no annotations-off option in current
`STPrintOptions` or accessory. If one is added later, it may suppress only ordinary
markup; it must never suppress the baked redactions.

## Selection boundary and private PDF data

The selection crop is a data boundary, not just a visual clip. A clipped PDF can still
retain outside pixels in an image XObject and hidden glyphs in a text object. Check
bitmap representation dimensions and physically crop before embedding. Only vectorize
an annotation if its full drawn bounds, including text decorations, shadow and callout
pointer, are contained in the selected source rect. Omit fully outside annotations.
If any annotation intersects the boundary, use the existing fully flattened, physically
cropped print image for that job or page. That fallback preserves the visible partial
annotation without leaving its hidden text or off-selection path in PDF objects. A later
glyph/path clipping implementation can replace the fallback after object-level proof.
Do not silently drop partial text as the `3fcb760` feasibility helper does.

When pagination clips a full selected image into pages, inspect page-level XObjects:
the current `STPrintView` caches raster tiles specifically to avoid embedding and
unpacking a full capture on every PDF page. The vector path must retain that property,
including when the selection spans several pages.

## Incremental gates

1. Extract a redaction-only base API from the existing macOS pixelation path. Compare
   its pixels with current flattening before ordinary markup for solid, checkerboard,
   transparent and Retina captures; prove crop dimensions and no source-pixel retention.
2. Add an immutable scene and wire it through `printWithSelectionOnly:`,
   `STPrintViewTakeOptions` and `STPrintView drawRect:`. Preserve a full-raster fallback
   for partial annotations, unsupported representations or allocation failures.
3. In an offscreen PDF probe, use real canvas redaction and markup models. Scan each
   page's content and nested XObjects for expected image dimensions and path/text
   operators; assert outside-selection text is absent from decoded PDF objects.
   Compare page rasterizations against the current print output, including selection
   edges, arrows, callouts, styled text, highlighter alpha, page tiles and orientation.
4. Run the existing focused print and context/share tests. Native print-panel,
   accessory persistence and Save as PDF behavior require a separately authorized
   shared-screen gate. No physical printer is needed for the source gate.

Success at the offscreen gate would prove the produced PDF objects and rendered pages
for tested cases. It would not prove native panel behavior, an installed package or a
live update. Keep the feature out of the release path until those later gates pass.
