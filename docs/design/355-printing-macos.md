# Printing on macOS (#355, 0.5.0)

The macOS part of first-class printing. The shared parts are the same on every platform: STPrintLayout decides where pixels go, STPrintOptions holds the user's choices and their defaults keys, and STDrawPrintPage draws one page. Linux and Windows have their own panels and print paths. This note covers only what macOS does differently.

## Path

File ▸ Print… (⌘P) goes through `-[AppDelegate printDocument:]`, which:

1. Flattens the canvas once, and also flattens the selection as its own image if there is a selection.
2. Builds an STPrintLayout:
   - the paper and printer margins come from a copy of the shared NSPrintInfo (`STPrinterMarginsForPrintInfo` reads them on the portrait sheet);
   - the margins are 36 pt a side, the same as Linux;
   - the rest comes from the saved STPrintOptions, through `STPrintViewTakeOptions`.
3. Readies the print info with `STPreparePrintInfo`. It sets the layout's orientation and turns off NSPrintInfo's own margins, scaling, centring and pagination, because the layout's page rects already include all of them.
4. Runs an NSPrintOperation on an **STPrintView**. That is a flipped view the size of one sheet:
   - `knowsPageRange:` gives the layout's page count;
   - `rectForPage:` is always the whole sheet;
   - `drawRect:` draws the operation's current page with `STDrawPrintPage(…, YES)`.
5. Adds an **STPrintAccessoryController** to the panel, with:
   - Size: Fit to Page, Actual Size, or Custom Scale %;
   - "Enlarge small images to fill the page" (with Fit to Page only);
   - "Print only the selection" (only when there is a selection);
   - "Turn the page to suit the image".

   A change goes into the layout straight away, and the preview's page count follows.

## Decisions

- **The panel's Orientation is a choice.** STPrintView takes the paper and orientation from its operation's print info each time it paginates. If Apple's Portrait/Landscape control turns the sheet away from the layout's orientation, that becomes a set orientation and "Turn the page" goes off. With "Turn the page" on, the panel's sheet follows the layout. The saved key means the same thing as on the other platforms (`auto`, `portrait`, `landscape`).
- **Resolution:** a macOS image's points are 1/72 inch. A 1x capture prints at 72 ppi and a Retina one at 144, so both print at their size on screen. That's different from the 96 ppi default used where an image has no resolution of its own.
- **Saved only on success:** options and paper are saved after a print or a saved PDF, never after a cancel.

## Privacy

Printing never shows what a redaction hides. This is the lead's rule for every platform.

- There's no option to print without annotations, because a redaction is an annotation.
- A printed selection is drawn from the selection's own flattened image. Clipping the whole image would still embed all of it, invisible, in a saved PDF. PrintViewProbe walks the PDF's image XObjects to check this, and a control test shows the probe catches the clipped case.

## Probes (macOS only)

- **PrintViewProbe:**
  - Runs a real NSPrintOperation with the job saved to PDF. (PDFOperationWithView ignores `knowsPageRange:` and gives one page.)
  - Checks a sheet per page, with each tile the right way up, for 1x and Retina images.
  - Checks the print info setup, the selection's embedded images, and that a 1x image is 72 ppi.
  - Colours are compared by nearest palette colour, because a PDF goes through colour management.
- **PrintAccessoryProbe:** checks options in and out, that changes reach the layout, that the panel's orientation counts as a choice, the shared keys, the controls and their bindings, and that there's no annotations option.

## Resolution

The printed image is flattened again at the printed size, up to 300 dpi, by `-[ScreenshotCanvasView flattenedImageForPrintAtScale:withinRect:]`. The scale comes from STPrintLayout's `flattenScaleForImagePixelSize:`.

- The macOS branch of that method:
  1. pixelates the redactions on the capture's own pixels first, so a mosaic cell stays a cell of the capture;
  2. enlarges the result by whole-pixel blocks (no interpolation);
  3. draws the other annotations into a context scaled by the same factor;
  4. crops to the selection.
- STPrintViewTakeOptions asks a flattener block for the scale and clip, then counts the result's pixels at `ppi × scale`, so the page is the same size. The app's block keeps the last flatten, because the panel asks again on every change.
- PrintFlattenProbe checks this. Unredacted, the secret is there, as 3 × 3 blocks. Redacted, none of it is there, at scale 1 or 3. A mutant that skips the pixelation fails. Clips and the whole print path to the view are checked as well.

## Open

- Measure flatten time for a large capture at scale 4. The 8192 px cap bounds it. If the panel feels slow, flatten once at the final scale when the job runs, not on every change.
