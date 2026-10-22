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

@end

/// The lines' text, a line each, in reading order.
FOUNDATION_EXPORT NSString *STRecognizedText(NSArray<STRecognizedLine *> *lines);

/// The lines of tesseract's TSV output (`tesseract image stdout tsv`): its words, grouped by
/// block, paragraph and line. Words with no text are left out.
FOUNDATION_EXPORT NSArray<STRecognizedLine *> *STLinesFromTesseractTSV(NSString *tsv);

/// The boxes of the email addresses and phone numbers in the lines, each the union of the words
/// it spans, a little larger: what Redact Emails and Phone Numbers covers.
FOUNDATION_EXPORT NSArray<NSValue *> *STSensitiveTextRects(NSArray<STRecognizedLine *> *lines);

NS_ASSUME_NONNULL_END
