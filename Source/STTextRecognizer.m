#import "STTextRecognizer.h"
#import "STCustomActions.h"

#if defined(GNUSTEP) && !defined(_WIN32)
#define ST_TEXT_TESSERACT 1
#endif
#if !defined(GNUSTEP)
#define ST_TEXT_VISION 1
#import <Vision/Vision.h>
#endif

@implementation STRecognizedWord

- (instancetype)initWithText:(NSString *)text bounds:(NSRect)bounds {
    self = [super init];
    if (self) {
        _text = [text copy];
        _bounds = bounds;
    }
    return self;
}

@end

@implementation STRecognizedLine

- (instancetype)initWithWords:(NSArray<STRecognizedWord *> *)words {
    self = [super init];
    if (self) {
        _words = [words copy];
        NSMutableArray<NSString *> *texts = [[NSMutableArray alloc] initWithCapacity:words.count];
        NSRect bounds = NSZeroRect;
        for (STRecognizedWord *word in words) {
            [texts addObject:word.text];
            bounds = NSIsEmptyRect(bounds) ? word.bounds : NSUnionRect(bounds, word.bounds);
        }
        _text = [texts componentsJoinedByString:@" "];
        _bounds = bounds;
    }
    return self;
}

@end

NSString *STRecognizedText(NSArray<STRecognizedLine *> *lines) {
    NSMutableArray<NSString *> *texts = [[NSMutableArray alloc] initWithCapacity:lines.count];
    for (STRecognizedLine *line in lines) {
        [texts addObject:line.text];
    }
    return [texts componentsJoinedByString:@"\n"];
}

NSArray<STRecognizedLine *> *STLinesFromTesseractTSV(NSString *tsv) {
    // level page block par line word left top width height conf text; level 5 is a word.
    NSMutableArray<STRecognizedLine *> *lines = [[NSMutableArray alloc] init];
    NSMutableArray<STRecognizedWord *> *words = [[NSMutableArray alloc] init];
    NSString *lineKey = nil;
    for (NSString *row in [tsv componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSArray<NSString *> *fields = [row componentsSeparatedByString:@"\t"];
        if (fields.count < 12 || ![fields[0] isEqualToString:@"5"]) {
            continue;
        }
        NSString *text = [fields[11] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (text.length == 0) {
            continue;
        }
        NSString *key = [NSString stringWithFormat:@"%@.%@.%@.%@", fields[1], fields[2], fields[3], fields[4]];
        if (lineKey && ![key isEqualToString:lineKey] && words.count > 0) {
            [lines addObject:[[STRecognizedLine alloc] initWithWords:words]];
            [words removeAllObjects];
        }
        lineKey = key;
        NSRect bounds = NSMakeRect(fields[6].doubleValue, fields[7].doubleValue,
                                   fields[8].doubleValue, fields[9].doubleValue);
        [words addObject:[[STRecognizedWord alloc] initWithText:text bounds:bounds]];
    }
    if (words.count > 0) {
        [lines addObject:[[STRecognizedLine alloc] initWithWords:words]];
    }
    return lines;
}

/// Phone numbers as they're written: an optional country code, then 7 to 15 digits in groups,
/// with spaces, dots, dashes or brackets between. Counting digits keeps times and versions out
/// (too few); a date (2026-10-22, 2026.10.22) is left out by its shape.
static BOOL STIsPhoneNumber(NSString *match) {
    static NSRegularExpression *date = nil;
    if (!date) {
        date = [NSRegularExpression regularExpressionWithPattern:@"^\\d{4}[-./]\\d{1,2}[-./]\\d{1,2}$" options:0 error:NULL];
    }
    if ([date numberOfMatchesInString:match options:0 range:NSMakeRange(0, match.length)] > 0) {
        return NO;
    }
    NSUInteger digits = 0;
    for (NSUInteger i = 0; i < match.length; i++) {
        unichar c = [match characterAtIndex:i];
        if (c >= '0' && c <= '9') {
            digits++;
        }
    }
    return digits >= 7 && digits <= 15;
}

NSArray<NSValue *> *STSensitiveTextRects(NSArray<STRecognizedLine *> *lines) {
    static NSRegularExpression *email = nil;
    static NSRegularExpression *phone = nil;
    if (!email) {
        email = [NSRegularExpression regularExpressionWithPattern:@"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}"
                                                          options:0
                                                            error:NULL];
        phone = [NSRegularExpression regularExpressionWithPattern:@"(\\+\\d{1,3}[ .-]?)?(\\(\\d{2,4}\\)|\\d{2,4})([ .-]?\\d{2,4}){1,3}"
                                                          options:0
                                                            error:NULL];
    }
    NSMutableArray<NSValue *> *rects = [[NSMutableArray alloc] init];
    for (STRecognizedLine *line in lines) {
        // Where each word is in the line's text, to map a match back to the words it covers.
        NSMutableArray<NSValue *> *ranges = [[NSMutableArray alloc] initWithCapacity:line.words.count];
        NSUInteger offset = 0;
        for (STRecognizedWord *word in line.words) {
            [ranges addObject:[NSValue valueWithRange:NSMakeRange(offset, word.text.length)]];
            offset += word.text.length + 1;
        }
        NSString *text = line.text;
        NSMutableArray<NSTextCheckingResult *> *matches = [[NSMutableArray alloc] init];
        [matches addObjectsFromArray:[email matchesInString:text options:0 range:NSMakeRange(0, text.length)]];
        for (NSTextCheckingResult *match in [phone matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
            if (STIsPhoneNumber([text substringWithRange:match.range])) {
                [matches addObject:match];
            }
        }
        for (NSTextCheckingResult *match in matches) {
            NSRect box = NSZeroRect;
            for (NSUInteger i = 0; i < ranges.count; i++) {
                if (NSIntersectionRange(ranges[i].rangeValue, match.range).length > 0) {
                    NSRect wordBox = line.words[i].bounds;
                    box = NSIsEmptyRect(box) ? wordBox : NSUnionRect(box, wordBox);
                }
            }
            if (!NSIsEmptyRect(box)) {
                // A little over the glyphs, so their edges don't show around the pixelation.
                [rects addObject:[NSValue valueWithRect:NSInsetRect(box, -3.0, -3.0)]];
            }
        }
    }
    return rects;
}

#if ST_TEXT_VISION
/// Vision's box, normalised with a bottom-left origin in `region` (which is in pixels, top-left
/// origin), in the whole image's pixels with a top-left origin.
static NSRect STPixelRectFromVisionBox(CGRect box, NSRect region) {
    return NSMakeRect(NSMinX(region) + box.origin.x * NSWidth(region),
                      NSMinY(region) + (1.0 - box.origin.y - box.size.height) * NSHeight(region),
                      box.size.width * NSWidth(region),
                      box.size.height * NSHeight(region));
}

/// The observations' best readings as lines of words, each word boxed by Vision: a word is what
/// whitespace separates, as tesseract's are, so a line's text is its words joined with spaces.
static NSArray<STRecognizedLine *> *STLinesFromVisionObservations(NSArray<VNRecognizedTextObservation *> *observations,
                                                                 NSRect region) {
    NSMutableArray<STRecognizedLine *> *lines = [[NSMutableArray alloc] init];
    NSCharacterSet *spaces = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (VNRecognizedTextObservation *observation in observations) {
        VNRecognizedText *candidate = [observation topCandidates:1].firstObject;
        NSString *string = candidate.string;
        if (string.length == 0) {
            continue;
        }
        NSMutableArray<STRecognizedWord *> *words = [[NSMutableArray alloc] init];
        NSUInteger index = 0;
        while (index < string.length) {
            NSRange space = [string rangeOfCharacterFromSet:spaces options:0 range:NSMakeRange(index, string.length - index)];
            NSUInteger end = space.location == NSNotFound ? string.length : space.location;
            if (end > index) {
                NSRange range = NSMakeRange(index, end - index);
                // A word Vision can't box gets the line's box, rather than being lost.
                VNRectangleObservation *wordBox = [candidate boundingBoxForRange:range error:NULL];
                CGRect box = wordBox ? wordBox.boundingBox : observation.boundingBox;
                [words addObject:[[STRecognizedWord alloc] initWithText:[string substringWithRange:range]
                                                                 bounds:STPixelRectFromVisionBox(box, region)]];
            }
            index = end + (space.location == NSNotFound ? 0 : space.length);
        }
        if (words.count > 0) {
            [lines addObject:[[STRecognizedLine alloc] initWithWords:words]];
        }
    }
    return lines;
}
#endif

@implementation STTextRecognizer

#if ST_TEXT_TESSERACT
+ (nullable NSString *)tesseractPath {
    NSDictionary *environment = [STCustomActionRunner childEnvironmentFrom:[[NSProcessInfo processInfo] environment]];
    return [STCustomActionRunner resolvedExecutable:@"tesseract"
                                         searchPath:[STCustomActionRunner searchPathInEnvironment:environment]];
}
#endif

+ (BOOL)isAvailable {
#if ST_TEXT_TESSERACT
    return [self tesseractPath] != nil;
#elif ST_TEXT_VISION
    return YES;
#else
    // The Windows engine (Windows.Media.Ocr) comes from the Windows work.
    return NO;
#endif
}

+ (void)recognizeTextInImageAtURL:(NSURL *)url
                             rect:(NSRect)rect
                       completion:(STTextRecognitionCompletion)completion {
    STTextRecognitionCompletion finish = [completion copy];
#if ST_TEXT_TESSERACT
    NSString *tesseract = [self tesseractPath];
    if (!tesseract || !url.isFileURL) {
        dispatch_async(dispatch_get_main_queue(), ^{
            finish(nil, @"Text recognition isn't available: install tesseract.");
        });
        return;
    }
    // Two minutes is far more than a screenshot takes; it only stops one that hangs.
    [STCustomActionRunner runArguments:@[tesseract, url.path, @"stdout", @"tsv"]
                               timeout:120.0
                            completion:^(STCustomActionResult *result) {
        if (!result.succeeded) {
            finish(nil, result.failureSummary);
            return;
        }
        NSArray<STRecognizedLine *> *lines = STLinesFromTesseractTSV(result.standardOutput ?: @"");
        if (!NSIsEmptyRect(rect)) {
            // A line keeps the words whose middle is in the rect.
            NSMutableArray<STRecognizedLine *> *inside = [[NSMutableArray alloc] init];
            for (STRecognizedLine *line in lines) {
                NSMutableArray<STRecognizedWord *> *kept = [[NSMutableArray alloc] init];
                for (STRecognizedWord *word in line.words) {
                    if (NSPointInRect(NSMakePoint(NSMidX(word.bounds), NSMidY(word.bounds)), rect)) {
                        [kept addObject:word];
                    }
                }
                if (kept.count > 0) {
                    [inside addObject:[[STRecognizedLine alloc] initWithWords:kept]];
                }
            }
            lines = inside;
        }
        finish(lines, nil);
    }];
#elif ST_TEXT_VISION
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<STRecognizedLine *> *lines = nil;
        NSString *failure = nil;
        CGImageSourceRef source = url.isFileURL ? CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL) : NULL;
        CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
        if (source) {
            CFRelease(source);
        }
        if (!image) {
            failure = @"The image couldn't be opened for text recognition.";
        } else {
            NSRect whole = NSMakeRect(0.0, 0.0, CGImageGetWidth(image), CGImageGetHeight(image));
            NSRect region = NSIsEmptyRect(rect) ? whole : NSIntersectionRect(NSIntegralRect(rect), whole);
            if (NSIsEmptyRect(region)) {
                lines = @[];
            } else {
                VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];
                request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
                request.usesLanguageCorrection = YES;
                if (@available(macOS 13.0, *)) {
                    request.automaticallyDetectsLanguage = YES;
                }
                // Vision's region is normalised with a bottom-left origin.
                request.regionOfInterest = CGRectMake(NSMinX(region) / NSWidth(whole),
                                                      1.0 - NSMaxY(region) / NSHeight(whole),
                                                      NSWidth(region) / NSWidth(whole),
                                                      NSHeight(region) / NSHeight(whole));
                VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
                NSError *error = nil;
                if ([handler performRequests:@[request] error:&error]) {
                    lines = STLinesFromVisionObservations(request.results ?: @[], region);
                } else {
                    failure = error.localizedDescription ?: @"Vision couldn't read the image.";
                }
            }
            CGImageRelease(image);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            finish(lines, lines ? nil : failure);
        });
    });
#else
    (void)url;
    (void)rect;
    dispatch_async(dispatch_get_main_queue(), ^{
        finish(nil, @"Text recognition isn't available on this platform yet.");
    });
#endif
}

@end
