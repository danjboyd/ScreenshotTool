# #330: selecting text in the image (0.4.0), design note

Status: reviewed by the lead, with its answers to the open questions folded in. No code yet; it merges as the first 0.4.0 PR. The split comes from the lead's plan.
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
  - Edit ▸ Select Text, shortcut ⇧⌘E (Ctrl+Shift+E on GNUstep and Windows), to confirm. ⇧⌘T, first proposed, is already Take Screenshot.
  - The same command in the canvas context menu.
  - No toolbar button in 0.4.0, to keep the narrow toolbar.
- **Not a new `ScreenshotCanvasTool` value.** The mode overlays the current tool, so leaving it puts the user back where they were, and the toolbar's tool switcher doesn't need another icon.
- **On entry:**
  - The canvas keeps a `textSelectionModel` (an `STTextSelection`) and a `textSelectionActive` flag.
  - AppDelegate reads the whole image once with `readTextInImageRect:NSZeroRect`, then hands the lines to the canvas. There's no second, scoped read path.
  - With a canvas selection on entry, the words whose middle is inside it start selected (`STLinesInsideRect` already picks them).
  - The lines are cached, keyed by the annotation fingerprint (as `savedAnnotationFingerprint` uses it). Entering the mode again with the same fingerprint doesn't read again.
  - "Reading text…" shows while the read runs.
  - No text: the canvas says "No text found in the image" (the #333 wording) and doesn't enter the mode.
- **Drawing:**
  - Each word gets a faint rounded outline.
  - Selected words get a filled selection-colour highlight, merged per line into one rect.
  - It's drawn in `drawRect:` above the annotations and below the selection bar.
  - The outlines are drawn at view scale, so they stay crisp at any zoom.
- **Leaving the mode:**
  - Esc (`cancelOperation:` on Cocoa; on GNUstep the canvas's `keyDown:`, because nothing on that path reaches `complete:`, as #357 found);
  - picking any tool;
  - opening another image.
- **Undo and redo don't leave the mode**, which would surprise people. Any edit invalidates the cache; if the fingerprint changed while the mode is on, the lines are read again lazily and the outlines redrawn.
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
  - Redact Selected Text, wired to one AppDelegate method, `redactSelectedText:`. Its body (grow the rects as `STSensitiveTextRects` does, add them as one undo) is the Windows agent's, with the 125% and 150% DPI check.
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

## Who does what

- **Linux:** `STTextSelection` (hit-testing, reading-order selection, `selectedText`, `selectedRects`). It lands first.
- **macOS (this note):** the canvas mode, the drawing, the Edit menu and context-menu entries and their validation, including the Redact Selected Text item and its wiring to `redactSelectedText:`.
- **Windows:** the body of `redactSelectedText:`, and the DPI check.

## Settled questions (lead's review of #342)

1. **Shortcut and button:** Edit menu, context menu and a shortcut; no toolbar button in 0.4.0. The shortcut is checked against all three platforms' bindings first.
2. **Selection rect:** always read the whole image once; a selection on entry preselects the words inside it.
3. **Cache:** yes, keyed by the annotation fingerprint and invalidated by any edit; undo and redo re-read lazily instead of leaving the mode.

## Still to confirm

- **The shortcut ⇧⌘E:** the Linux and Windows agents each check it against their platform's own bindings (GNUstep's key-equivalent mapping, GNOME's, and Windows' system and WinUITheme shortcuts) as part of their #330 pieces. If either clashes, it's picked again before merge.
