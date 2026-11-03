# #330: selecting text in the image (0.4.0), design note

Status: a sketch for review, with no code yet. The split comes from the lead's plan.
- **Linux** builds `STTextSelection`, a model that uses only Foundation.
- **macOS** builds the canvas mode on top of it (this note).
- **Windows** builds Redact Selection.

## What's already there

- `STTextRecognizer` gives `STRecognizedLine`s of `STRecognizedWord`s in reading order. Boxes are in the image's pixels, top-left origin, on all three engines (Vision, tesseract and Windows.Media.Ocr).
- `readTextInImageRect:completion:` in AppDelegate exports `flattenedImage`, reads it off the main thread and handles `readingText`. Menu validation already disables the text commands while a read runs.
- Coordinates in the canvas:
  - The canvas is flipped.
  - Image points equal image pixels, because `openImageAtURL:` resets the size to `pixelsWide` × `pixelsHigh`.
  - `viewRectForImageRect:` is image × `zoomScale`, and `imagePointForEvent:` is the inverse, clamped to the image.
  - `flattenedImageWithinRect:` renders at `image.size`, so the boxes the recognizer returns are already in canvas image coordinates. No pixel-to-point step is needed.

## Retina check (the lead asked for one)

The chain is OCR pixels → image coordinates (1:1) → view points (× zoomScale), and AppKit handles the backing scale. That holds only while `image.size` equals the pixel size.

To verify:
1. A project opened through `loadProjectData:` goes through the same normalisation.
2. A 2× capture (screencapture on Retina gives 2× pixels) outlines correctly at Fit and at 100%.

The probe should load an image whose `size` differs from its pixel size, and check that the outlines still land on the words.

## The mode

- **Entry:**
  - Edit ▸ Select Text (⇧⌘T, or Ctrl+Shift+T on GNUstep and Windows; to be checked against the existing shortcuts).
  - The same command in the canvas context menu.
- **Not a new `ScreenshotCanvasTool` value.** The mode overlays the current tool, so leaving it puts the user back where they were, and the toolbar's tool switcher doesn't need another icon.
- **On entry:**
  - The canvas keeps a `textSelectionModel` (an `STTextSelection`) and a `textSelectionActive` flag.
  - AppDelegate reads the whole image once with `readTextInImageRect:NSZeroRect`, then hands the lines to the canvas.
  - "Reading text…" shows while the read runs.
  - No text: the canvas says "No text found in the image" (the #333 wording) and doesn't enter the mode.
- **Drawing:**
  - Each word gets a faint rounded outline.
  - Selected words get a filled selection-colour highlight, merged per line into one rect.
  - It's drawn in `drawRect:` above the annotations and below the selection bar.
  - The outlines are drawn at view scale, so they stay crisp at any zoom.
- **Leaving the mode:**
  - Esc (`cancelOperation:` on Cocoa, `complete:` on GNUstep, as the text box already handles it);
  - picking any tool;
  - opening another image;
  - undoing or redoing, since the words could move under an annotation edit.
- **Cursor:** I-beam over a word, arrow elsewhere.

## Hit-testing and selection (in the `STTextSelection` model, shared)

- `wordIndexAtImagePoint:` finds the word whose box, grown by a few pixels, contains the point. If none does, it picks the nearest word on the line whose vertical band contains the point.
- A drag from word A to word B selects everything between them in reading order (line by line, as text selection does), not only the words inside the rectangle the drag draws.
- Click: a single click selects nothing; a double click selects a word; a triple click selects a line. ⌘A selects all the words.
- The model gives `selectedText` (words joined with spaces, lines with "\n", as `STRecognizedText` does) and `selectedRects` (one per line, in image coordinates).

## Copy and the menu

- `copy:`, ⌘C and Ctrl+C, while the mode is on and words are selected, put `selectedText` on the pasteboard as a string. Feedback: "Copied text (read on this computer)".
- With nothing selected, Copy keeps doing what it does today (copies the image).
- The context menu on a selection offers:
  - Copy Text;
  - Redact Selected Text, which runs `addRedactionsInImageRects:` on `selectedRects` grown as `STSensitiveTextRects` grows them, as one undoable action. Windows' Redact Selection can share this entry point.
  - Select All Text.

## Probe test (with a canned recognition result, as in `RedactDetectedFeedbackProbe`)

- Subclass AppDelegate and override `readTextInImageRect:completion:` to return two or three lines of known boxes.
- Check:
  - entering the mode, and that it isn't entered with no text;
  - a drag across a line break selects in reading order;
  - `copy:` writes the expected string;
  - Esc and a tool change leave the mode;
  - Redact Selected Text adds N redactions under one undo;
  - the Retina case above.

## Open questions

1. The shortcut, and whether the mode needs a toolbar button.
2. Whether a canvas selection rect should limit the read to that area. Reading the whole image is simpler; with a selection, the mode could select the words inside it first.
3. Cache the lines until the next edit, so entering the mode again doesn't read again? Probably yes, invalidated by the same fingerprint that `savedAnnotationFingerprint` uses.
