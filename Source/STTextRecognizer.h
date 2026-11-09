#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A word the recognizer read, with its box in the image's pixels (top-left origin, as the
/// canvas's image coordinates are).
@interface STRecognizedWord : NSObject
@property (nonatomic, copy, readonly) NSString *text;
@property (nonatomic, readonly) NSRect bounds;
- (instancetype)initWithText:(NSString *)text bounds:(NSRect)bounds;
@end

/// A line of words, in reading order.
@interface STRecognizedLine : NSObject
@property (nonatomic, copy, readonly) NSArray<STRecognizedWord *> *words;
/// The words joined with spaces.
@property (nonatomic, copy, readonly) NSString *text;
@property (nonatomic, readonly) NSRect bounds;
- (instancetype)initWithWords:(NSArray<STRecognizedWord *> *)words;
@end

typedef void (^STTextRecognitionCompletion)(NSArray<STRecognizedLine *> * _Nullable lines,
                                            NSString * _Nullable failure);

/// Reads the text in an image with the platform's own engine, on this computer: nothing is sent
/// anywhere (#278). Vision on macOS, Windows.Media.Ocr on Windows, tesseract on Linux when it's
/// installed.
@interface STTextRecognizer : NSObject

/// Whether this platform has an engine. The text commands are hidden when it doesn't.
+ (BOOL)isAvailable;

/// Reads `rect` of the image file (the whole image when it's NSZeroRect), off the main thread.
/// The completion is called once, on the main thread. Boxes are in the whole image's pixels. No
/// text is an empty array; `failure` is set only for a real error.
+ (void)recognizeTextInImageAtURL:(NSURL *)url
                             rect:(NSRect)rect
                       completion:(STTextRecognitionCompletion)completion;

#if !defined(GNUSTEP)
/// The same for an image already in memory (macOS, Vision): the app hands over its flattened image
/// instead of writing a PNG for Vision to read back (perf, 0.4.0). The image is retained until done.
+ (void)recognizeTextInCGImage:(CGImageRef)image
                          rect:(NSRect)rect
                    completion:(STTextRecognitionCompletion)completion;
#endif

@end

/// The lines' text, a line each, in reading order.
FOUNDATION_EXPORT NSString *STRecognizedText(NSArray<STRecognizedLine *> *lines);

/// The lines of tesseract's TSV output (`tesseract image stdout tsv`): its words, grouped by
/// block, paragraph and line. Words with no text are left out.
FOUNDATION_EXPORT NSArray<STRecognizedLine *> *STLinesFromTesseractTSV(NSString *tsv);

/// How many times to enlarge an image of this many pixels before tesseract reads it: 2, which finds much
/// more small text, unless its long side would then be over 8000 pixels; otherwise 1.
FOUNDATION_EXPORT NSUInteger STTesseractUpscaleFactor(NSSize imagePixels);
/// `lines` read from an image enlarged `factor` times, with their boxes back in the original's pixels.
FOUNDATION_EXPORT NSArray<STRecognizedLine *> *STLinesScaledDownBy(NSArray<STRecognizedLine *> *lines, NSUInteger factor);
/// The lines' words whose middle is in `rect` (image pixels), as lines; all of them for an empty
/// rect. For an engine that reads the whole image, or as a check after one that crops.
FOUNDATION_EXPORT NSArray<STRecognizedLine *> *STLinesInsideRect(NSArray<STRecognizedLine *> *lines, NSRect rect);

/// The boxes of the email addresses and phone numbers in the lines, each the union of the words
/// it spans, a little larger: what Redact Emails and Phone Numbers covers.
FOUNDATION_EXPORT NSArray<NSValue *> *STSensitiveTextRects(NSArray<STRecognizedLine *> *lines);

/// Tiles to read `region` (image pixels, top-left origin) in: just `region` up to 1600 px on its long
/// side, otherwise 2560 x 720 tiles overlapping by half their width and a third of their height.
/// An engine that scales a large image down (Vision) loses small text without them.
FOUNDATION_EXPORT NSArray<NSValue *> *STVisionTilesForRegion(NSRect region);

/// Tiles to read again after `tiles` were read as `tileLines`: for a tile that read under half the
/// characters a neighbour read where the two overlap (and the neighbour at least 40), the tile less
/// an eighth of its width on the left, and less an eighth on the right. A reader can miss a whole
/// column in one placement of a tile and read it fully from one shifted a little (Vision, a column
/// across a tile seam, 2026-11-06).
FOUNDATION_EXPORT NSArray<NSValue *> *STVisionRetryTiles(NSArray<NSValue *> *tiles,
                                                          NSArray<NSArray<STRecognizedLine *> *> *tileLines);

/// `lines`, in rows top down, in reading order for text in columns: each column top to bottom, the
/// columns left to right, with a line across them (a heading) starting a new run. Forms and tables
/// keep their rows; text in one column is unchanged. STMergeTiledLines orders its lines with it.
FOUNDATION_EXPORT NSArray<STRecognizedLine *> *STOrderLinesInColumns(NSArray<STRecognizedLine *> *lines);

/// The lines read in each of `tiles` (boxes in the whole image's pixels) as one reading of `region`:
/// words cut by an inner tile edge dropped, words read twice kept once, a line split by tiles joined
/// again, and lines in reading order: by rows, top to bottom and left to right, or column by column
/// where the text is in columns (STOrderLinesInColumns).
FOUNDATION_EXPORT NSArray<STRecognizedLine *> *STMergeTiledLines(NSArray<NSArray<STRecognizedLine *> *> *tileLines,
                                                                 NSArray<NSValue *> *tiles, NSRect region);

/// Two readings of one region as one: duplicates go as in STMergeTiledLines, and the lines stay in the
/// first reading's order, which keeps a column together, with the second's new lines where it had them.
FOUNDATION_EXPORT NSArray<STRecognizedLine *> *STMergeReadings(NSArray<STRecognizedLine *> *first, NSArray<STRecognizedLine *> *second, NSRect region);

NS_ASSUME_NONNULL_END
