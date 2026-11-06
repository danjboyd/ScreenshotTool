#import "STTextRecognizer.h"
#import "STCustomActions.h"

#if defined(GNUSTEP) && !defined(_WIN32)
#define ST_TEXT_TESSERACT 1
#endif
#if !defined(GNUSTEP)
#define ST_TEXT_VISION 1
#import <Vision/Vision.h>
#endif
#if defined(_WIN32)
#define ST_TEXT_WINDOWS 1
#import "STWindowsIntegration.h"
#endif

#if ST_TEXT_TESSERACT && defined(ST_HAVE_CAIRO)
#include <cairo.h>
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

/// Whether `text` (a match as written, look-alike digits not yet read as digits) is a date, a date
/// and time, or a version rather than a phone number: 2026-10-22, 2026/10/22, 22.10.2026, 10/22/26,
/// "2026 10 22 13", 20261022-134507, 10.0.19045.3803, or an ISBN. One with a "+" country code or a
/// bracketed area code is a phone number whatever its digits.
static BOOL STLooksLikeDateOrVersion(NSString *text) {
    if ([text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"+()"]].location != NSNotFound) {
        return NO;
    }
    NSMutableArray<NSString *> *groups = [[NSMutableArray alloc] init];
    NSMutableString *separators = [[NSMutableString alloc] init];
    NSMutableString *group = [[NSMutableString alloc] init];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c >= '0' && c <= '9') {
            [group appendFormat:@"%C", c];
        } else if (group.length > 0) {
            [groups addObject:[group copy]];
            [group setString:@""];
            [separators appendFormat:@"%C", c];
        }
    }
    if (group.length > 0) {
        [groups addObject:[group copy]];
    }
    BOOL (^isYear)(NSString *) = ^BOOL(NSString *g) {
        return (g.length == 4 && g.integerValue >= 1900 && g.integerValue <= 2099) || g.length == 2;
    };
    BOOL (^isMonth)(NSString *) = ^BOOL(NSString *g) {
        return g.length <= 2 && g.integerValue >= 1 && g.integerValue <= 12;
    };
    BOOL (^isDay)(NSString *) = ^BOOL(NSString *g) {
        return g.length <= 2 && g.integerValue >= 1 && g.integerValue <= 31;
    };
    // A compact date at the start: 20261022, as in a timestamp.
    NSString *first = groups.firstObject;
    if (first.length == 8 && isYear([first substringToIndex:4]) && isMonth([first substringWithRange:NSMakeRange(4, 2)]) &&
        isDay([first substringFromIndex:6])) {
        return YES;
    }
    if (groups.count >= 3) {
        NSString *a = groups[0], *b = groups[1], *c = groups[2];
        // Year first (2026-10-22), or year last: day or month first, either order (22.10.2026,
        // 10/22/2026, 10/22/26). A time after it (2026-10-22 13:45) keeps it a date.
        BOOL yearFirst = a.length == 4 && isYear(a) && isMonth(b) && isDay(c);
        // A two-digit year only when the date is the whole match, with "/" or ".": "01.23.45.67.89" is
        // a French number.
        BOOL shortYear = c.length == 2 && groups.count == 3 && ([separators hasPrefix:@"/"] || [separators hasPrefix:@"."]);
        BOOL yearLast = (c.length == 4 || shortYear) && isYear(c) && ((isDay(a) && isMonth(b)) || (isMonth(a) && isDay(b)));
        if (yearFirst || yearLast) {
            return YES;
        }
    }
    // A version or build number: four or more groups split only by dots, with a one-digit group
    // after the first or a group of five or more (10.0.19045.3803). Not 1.512.555.0199 or
    // 01.23.45.67.89.
    if (groups.count >= 4 && [[separators stringByReplacingOccurrencesOfString:@"." withString:@""] length] == 0) {
        for (NSUInteger i = 0; i < groups.count; i++) {
            if ((i > 0 && groups[i].length == 1) || groups[i].length >= 5) {
                return YES;
            }
        }
    }
    // An ISBN: 978 or 979 and 13 digits.
    NSString *digits = [groups componentsJoinedByString:@""];
    return digits.length == 13 && ([digits hasPrefix:@"978"] || [digits hasPrefix:@"979"]);
}

/// Whether one word is a date, a version or an ISBN on its own ("2026-10-22,", "(22.10.2026)",
/// "10.0.19045.3803"). The phone pattern doesn't see it, so it can't join the phone number beside it.
static BOOL STWordIsDateOrVersion(NSString *word) {
    NSString *trimmed = [word stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"()[],;:"]];
    return trimmed.length >= 6 && STLooksLikeDateOrVersion(trimmed);
}

/// Whether a match of the phone pattern is a phone number as written: an optional country code, then
/// 7 to 15 digits in groups (counting digits keeps times out), and not a date, a time after a date, or
/// a version (`written` is the same text before look-alikes were read as digits).
static BOOL STIsPhoneNumber(NSString *match, NSString *written) {
    if (STLooksLikeDateOrVersion(match) || STLooksLikeDateOrVersion(written)) {
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

/// Whether two words, side by side, are one email address that the reader split: Vision puts a space
/// after a dot or around the "@" ("jane. doe@example.com", "Support@Example. COM", "doe @example.com").
/// Only where an "@" is part of it, so a sentence's full stop never joins two words.
static BOOL STWordsJoinIntoEmail(NSString *left, NSString *right) {
    if (left.length == 0 || right.length == 0) {
        return NO;
    }
    BOOL leftHasAt = [left rangeOfString:@"@"].location != NSNotFound;
    BOOL rightHasAt = [right rangeOfString:@"@"].location != NSNotFound;
    if (leftHasAt && rightHasAt) {
        return NO;
    }
    if ([left hasSuffix:@"@"] || [right hasPrefix:@"@"]) {
        return YES;
    }
    // "rachel.o'" + "neil@example.ie".
    if (([left hasSuffix:@"'"] || [left hasSuffix:@"’"]) && rightHasAt) {
        return YES;
    }
    // "jane." + "doe@example.com", or "Support@Example." + "COM".
    return [left hasSuffix:@"."] && left.length > 1 && (leftHasAt || rightHasAt) &&
           [[NSCharacterSet alphanumericCharacterSet] characterIsMember:[right characterAtIndex:0]];
}

/// A word as the phone number pattern sees it: where at least half of it is digits, the letters a reader puts
/// for digits are read as those digits ("/946" is 7946, "Ø123" is 0123, "55b-0100" is 556-0100), so
/// a misread digit doesn't leave the rest of the number unredacted. Same length as `word`.
static NSString *STPhoneDigitsInWord(NSString *word) {
    static NSDictionary<NSString *, NSString *> *lookalikes = nil;
    if (!lookalikes) {
        lookalikes = @{ @"O": @"0", @"o": @"0", @"Ø": @"0", @"ø": @"0", @"D": @"0", @"l": @"1", @"I": @"1", @"i": @"1",
                        @"|": @"1", @"!": @"1", @"Z": @"2", @"z": @"2", @"S": @"5", @"s": @"5", @"b": @"6", @"G": @"6",
                        @"/": @"7", @"B": @"8", @"g": @"9", @"q": @"9" };
    }
    NSUInteger digits = 0, others = 0;
    for (NSUInteger i = 0; i < word.length; i++) {
        unichar c = [word characterAtIndex:i];
        if (c >= '0' && c <= '9') {
            digits++;
        } else if (!(c == '+' || c == '(' || c == ')' || c == '-' || c == '.')) {
            if (!lookalikes[[NSString stringWithCharacters:&c length:1]]) {
                return word;
            }
            others++;
        }
    }
    if (others == 0 || digits == 0 || digits < others || word.length < 2) {
        return word;
    }
    NSMutableString *read = [word mutableCopy];
    for (NSUInteger i = 0; i < read.length; i++) {
        unichar c = [read characterAtIndex:i];
        NSString *digit = lookalikes[[NSString stringWithCharacters:&c length:1]];
        if (digit) {
            [read replaceCharactersInRange:NSMakeRange(i, 1) withString:digit];
        }
    }
    return read;
}

NSArray<NSValue *> *STSensitiveTextRects(NSArray<STRecognizedLine *> *lines) {
    static NSRegularExpression *email = nil;
    static NSRegularExpression *phone = nil;
    if (!email) {
        email = [NSRegularExpression regularExpressionWithPattern:@"[A-Za-z0-9._%+'/-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}"
                                                          options:0
                                                            error:NULL];
        // After a country code, the first group can be a single digit (+33 1 23 45 67 89, +49 30 901820);
        // without one, it's 2 to 4 digits or a bracketed area code.
        phone = [NSRegularExpression regularExpressionWithPattern:@"(\\+\\d{1,3}[ .-]?(\\(\\d{1,4}\\)|\\d{1,4})|\\(\\d{2,4}\\)|\\d{2,4})([ .-]?\\d{2,4}){1,4}"
                                                          options:0
                                                            error:NULL];
    }
    NSMutableArray<NSValue *> *rects = [[NSMutableArray alloc] init];
    for (STRecognizedLine *line in lines) {
        // Where each word is in the line's text, to map a match back to the words it covers. Words
        // the reader split out of one email address are joined again, with no space between.
        NSMutableArray<NSValue *> *ranges = [[NSMutableArray alloc] initWithCapacity:line.words.count];
        NSMutableString *text = [[NSMutableString alloc] init];
        NSMutableString *phoneText = [[NSMutableString alloc] init];
        STRecognizedWord *previous = nil;
        for (STRecognizedWord *word in line.words) {
            if (previous) {
                NSString *gap = STWordsJoinIntoEmail(previous.text, word.text) ? @"" : @" ";
                [text appendString:gap];
                [phoneText appendString:gap];
            }
            [ranges addObject:[NSValue valueWithRange:NSMakeRange(text.length, word.text.length)]];
            [text appendString:word.text];
            [phoneText appendString:STWordIsDateOrVersion(word.text) ? [@"" stringByPaddingToLength:word.text.length withString:@"_" startingAtIndex:0]
                                                                     : STPhoneDigitsInWord(word.text)];
            previous = word;
        }
        NSMutableArray<NSTextCheckingResult *> *matches = [[NSMutableArray alloc] init];
        [matches addObjectsFromArray:[email matchesInString:text options:0 range:NSMakeRange(0, text.length)]];
        for (NSTextCheckingResult *match in [phone matchesInString:phoneText options:0 range:NSMakeRange(0, phoneText.length)]) {
            if (STIsPhoneNumber([phoneText substringWithRange:match.range], [text substringWithRange:match.range])) {
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
                // Over the glyphs with room to spare, so their edges don't show around the pixelation:
                // a reader's word boxes can come back a little short, more so on larger text.
                CGFloat pad = MAX(3.0, round(NSHeight(box) * 0.15));
                [rects addObject:[NSValue valueWithRect:NSInsetRect(box, -pad, -pad)]];
            }
        }
    }
    return rects;
}

NSUInteger STTesseractUpscaleFactor(NSSize imagePixels) {
    return MAX(imagePixels.width, imagePixels.height) * 2.0 <= 8000.0 ? 2 : 1;
}

NSArray<STRecognizedLine *> *STLinesScaledDownBy(NSArray<STRecognizedLine *> *lines, NSUInteger factor) {
    if (factor <= 1) {
        return lines;
    }
    CGFloat scale = 1.0 / (CGFloat)factor;
    NSMutableArray<STRecognizedLine *> *scaled = [[NSMutableArray alloc] initWithCapacity:lines.count];
    for (STRecognizedLine *line in lines) {
        NSMutableArray<STRecognizedWord *> *words = [[NSMutableArray alloc] initWithCapacity:line.words.count];
        for (STRecognizedWord *word in line.words) {
            NSRect box = word.bounds;
            [words addObject:[[STRecognizedWord alloc] initWithText:word.text
                                                             bounds:NSMakeRect(NSMinX(box) * scale, NSMinY(box) * scale,
                                                                               NSWidth(box) * scale, NSHeight(box) * scale)]];
        }
        [scaled addObject:[[STRecognizedLine alloc] initWithWords:words]];
    }
    return scaled;
}

NSArray<STRecognizedLine *> *STLinesInsideRect(NSArray<STRecognizedLine *> *lines, NSRect rect) {
    if (NSIsEmptyRect(rect)) {
        return lines;
    }
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
    return inside;
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

/// Vision reads an image scaled down to its working size, so on a large capture small text is lost
/// (a 1x 4K screen's 11-13 pt text, half of it or all of it). Above this many pixels on the long
/// side, the image is read in overlapping tiles instead (#278 accuracy, 2026-11-05). Foundation
/// only, so any engine can tile the same way.
static const CGFloat STVisionTileThreshold = 1600.0;
static const CGFloat STVisionTileWidth = 2560.0;
static const CGFloat STVisionTileHeight = 720.0;

/// Tiles over `region`, each overlapping the next by half its width and a third of its height, so
/// any word, and any line up to half a tile wide, is whole in at least one of them.
NSArray<NSValue *> *STVisionTilesForRegion(NSRect region) {
    if (MAX(NSWidth(region), NSHeight(region)) <= STVisionTileThreshold) {
        return @[ [NSValue valueWithRect:region] ];
    }
    CGFloat width = MIN(NSWidth(region), STVisionTileWidth);
    CGFloat height = MIN(NSHeight(region), STVisionTileHeight);
    CGFloat stepX = floor(width / 2.0), stepY = floor(height * 2.0 / 3.0);
    NSMutableArray<NSNumber *> *xs = [NSMutableArray array], *ys = [NSMutableArray array];
    for (CGFloat x = NSMinX(region);; x += stepX) {
        CGFloat clamped = MIN(x, NSMaxX(region) - width);
        [xs addObject:@(clamped)];
        if (clamped + width >= NSMaxX(region)) {
            break;
        }
    }
    for (CGFloat y = NSMinY(region);; y += stepY) {
        CGFloat clamped = MIN(y, NSMaxY(region) - height);
        [ys addObject:@(clamped)];
        if (clamped + height >= NSMaxY(region)) {
            break;
        }
    }
    NSMutableArray<NSValue *> *tiles = [NSMutableArray array];
    for (NSNumber *y in ys) {
        for (NSNumber *x in xs) {
            [tiles addObject:[NSValue valueWithRect:NSMakeRect(x.doubleValue, y.doubleValue, width, height)]];
        }
    }
    return tiles;
}

/// One reading of the tiles: a word cut by a tile's inner edge is dropped (another tile has it
/// whole), a word read by two tiles is kept once, and words that were on one line in any tile stay
/// on one line, so a line longer than a tile is joined up again. Lines run top to bottom, and left
/// to right along a row.
NSArray<STRecognizedLine *> *STMergeTiledLines(NSArray<NSArray<STRecognizedLine *> *> *tileLines,
                                               NSArray<NSValue *> *tiles, NSRect region) {
    if (tiles.count == 1) {
        return tileLines.firstObject ?: @[];
    }
    const CGFloat edge = 2.0;
    NSMutableArray<STRecognizedWord *> *words = [NSMutableArray array];
    NSMutableArray<NSNumber *> *lineOfWord = [NSMutableArray array];
    NSUInteger lineCount = 0;
    for (NSUInteger t = 0; t < tileLines.count; t++) {
        NSRect tile = tiles[t].rectValue;
        BOOL innerLeft = NSMinX(tile) > NSMinX(region) + 0.5, innerRight = NSMaxX(tile) < NSMaxX(region) - 0.5;
        BOOL innerTop = NSMinY(tile) > NSMinY(region) + 0.5, innerBottom = NSMaxY(tile) < NSMaxY(region) - 0.5;
        for (STRecognizedLine *line in tileLines[t]) {
            for (STRecognizedWord *word in line.words) {
                NSRect b = word.bounds;
                BOOL cut = (innerLeft && NSMinX(b) <= NSMinX(tile) + edge) || (innerRight && NSMaxX(b) >= NSMaxX(tile) - edge) ||
                           (innerTop && NSMinY(b) <= NSMinY(tile) + edge) || (innerBottom && NSMaxY(b) >= NSMaxY(tile) - edge);
                if (!cut) {
                    [words addObject:word];
                    [lineOfWord addObject:@(lineCount)];
                }
            }
            lineCount++;
        }
    }
    // Lines joined through words read twice: a union-find over the tiles' lines.
    NSMutableArray<NSNumber *> *parent = [NSMutableArray arrayWithCapacity:lineCount];
    for (NSUInteger i = 0; i < lineCount; i++) {
        [parent addObject:@(i)];
    }
    NSUInteger (^find)(NSUInteger) = ^NSUInteger(NSUInteger i) {
        while (parent[i].unsignedIntegerValue != i) {
            i = parent[i].unsignedIntegerValue;
        }
        return i;
    };
    // Longer readings first, so a duplicate keeps the fuller text.
    NSMutableArray<NSNumber *> *indices = [NSMutableArray arrayWithCapacity:words.count];
    for (NSUInteger i = 0; i < words.count; i++) {
        [indices addObject:@(i)];
    }
    NSArray<NSNumber *> *order = [indices sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        NSUInteger la = words[a.unsignedIntegerValue].text.length, lb = words[b.unsignedIntegerValue].text.length;
        return la > lb ? NSOrderedAscending : (la < lb ? NSOrderedDescending : [a compare:b]);
    }];
    NSMutableArray<NSNumber *> *kept = [NSMutableArray array];
    for (NSNumber *index in order) {
        NSRect b = words[index.unsignedIntegerValue].bounds;
        NSNumber *same = nil;
        for (NSNumber *other in kept) {
            NSRect o = words[other.unsignedIntegerValue].bounds;
            NSRect overlap = NSIntersectionRect(b, o);
            CGFloat smaller = MIN(NSWidth(b) * NSHeight(b), NSWidth(o) * NSHeight(o));
            if (smaller > 0 && NSWidth(overlap) * NSHeight(overlap) > 0.6 * smaller) {
                same = other;
                break;
            }
        }
        if (same) {
            NSUInteger a = find(lineOfWord[index.unsignedIntegerValue].unsignedIntegerValue);
            NSUInteger c = find(lineOfWord[same.unsignedIntegerValue].unsignedIntegerValue);
            if (a != c) {
                parent[a] = @(c);
            }
        } else {
            [kept addObject:index];
        }
    }
    NSMutableDictionary<NSNumber *, NSMutableArray<STRecognizedWord *> *> *groups = [NSMutableDictionary dictionary];
    for (NSNumber *index in kept) {
        NSNumber *root = @(find(lineOfWord[index.unsignedIntegerValue].unsignedIntegerValue));
        NSMutableArray *group = groups[root] ?: (groups[root] = [NSMutableArray array]);
        [group addObject:words[index.unsignedIntegerValue]];
    }
    NSMutableArray<STRecognizedLine *> *lines = [NSMutableArray array];
    for (NSMutableArray<STRecognizedWord *> *group in groups.allValues) {
        [group sortUsingComparator:^NSComparisonResult(STRecognizedWord *a, STRecognizedWord *b) {
            return NSMinX(a.bounds) < NSMinX(b.bounds) ? NSOrderedAscending : (NSMinX(a.bounds) > NSMinX(b.bounds) ? NSOrderedDescending : NSOrderedSame);
        }];
        [lines addObject:[[STRecognizedLine alloc] initWithWords:group]];
    }
    [lines sortUsingComparator:^NSComparisonResult(STRecognizedLine *a, STRecognizedLine *b) {
        CGFloat tolerance = MIN(NSHeight(a.bounds), NSHeight(b.bounds)) / 2.0;
        if (fabs(NSMidY(a.bounds) - NSMidY(b.bounds)) > tolerance) {
            return NSMidY(a.bounds) < NSMidY(b.bounds) ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSMinX(a.bounds) < NSMinX(b.bounds) ? NSOrderedAscending : (NSMinX(a.bounds) > NSMinX(b.bounds) ? NSOrderedDescending : NSOrderedSame);
    }];
    return lines;
}

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
#elif ST_TEXT_WINDOWS
    return STWindowsTextRecognitionAvailable();
#else
    return NO;
#endif
}

#if ST_TEXT_TESSERACT
/// A PNG of the image at `path`, enlarged as STTesseractUpscaleFactor says, in `factor`; nil, with a
/// factor of 1, when it isn't enlarged. Cairo only, so it's safe off the main thread, where GNUstep's
/// image classes aren't.
+ (nullable NSString *)enlargedCopyOfPNGAtPath:(NSString *)path factor:(NSUInteger *)factor {
    *factor = 1;
#if defined(ST_HAVE_CAIRO)
    cairo_surface_t *source = cairo_image_surface_create_from_png(path.fileSystemRepresentation);
    if (cairo_surface_status(source) != CAIRO_STATUS_SUCCESS) {
        cairo_surface_destroy(source);
        return nil;
    }
    int width = cairo_image_surface_get_width(source);
    int height = cairo_image_surface_get_height(source);
    NSUInteger scale = STTesseractUpscaleFactor(NSMakeSize(width, height));
    NSString *copy = nil;
    if (scale > 1) {
        cairo_surface_t *target = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width * (int)scale, height * (int)scale);
        cairo_t *cr = cairo_create(target);
        cairo_scale(cr, scale, scale);
        cairo_set_source_surface(cr, source, 0.0, 0.0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_BEST);
        cairo_paint(cr);
        BOOL drawn = cairo_status(cr) == CAIRO_STATUS_SUCCESS;
        cairo_destroy(cr);
        if (drawn) {
            NSString *name = [NSString stringWithFormat:@"screenshottool-read-%@.png", [[NSUUID UUID] UUIDString]];
            NSString *path2 = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
            if (cairo_surface_write_to_png(target, path2.fileSystemRepresentation) == CAIRO_STATUS_SUCCESS) {
                copy = path2;
                *factor = scale;
            }
        }
        cairo_surface_destroy(target);
    }
    cairo_surface_destroy(source);
    return copy;
#else
    (void)path;
    return nil;
#endif
}

+ (void)runTesseractJob:(NSDictionary *)job {
    @autoreleasepool {
        NSString *path = job[@"path"];
        NSRect rect = [job[@"rect"] rectValue];
        STTextRecognitionCompletion finish = job[@"completion"];
        NSUInteger factor = 1;
        NSString *enlarged = [self enlargedCopyOfPNGAtPath:path factor:&factor];
        // One thread: tesseract's OpenMP threads wait on each other, and read the same words about
        // four times slower. For this command only; the app itself uses no OpenMP.
        // Two minutes is far more than a screenshot takes; it only stops one that hangs.
        [STCustomActionRunner runArguments:@[job[@"tesseract"], enlarged ?: path, @"stdout", @"tsv"]
                          extraEnvironment:@{ @"OMP_THREAD_LIMIT": @"1" }
                                   timeout:120.0
                                completion:^(STCustomActionResult *result) {
            if (enlarged) {
                [[NSFileManager defaultManager] removeItemAtPath:enlarged error:NULL];
            }
            if (!result.succeeded) {
                finish(nil, result.failureSummary);
                return;
            }
            // tesseract reads the whole image; the rect keeps its words.
            NSArray<STRecognizedLine *> *lines = STLinesScaledDownBy(STLinesFromTesseractTSV(result.standardOutput ?: @""), factor);
            finish(STLinesInsideRect(lines, rect), nil);
        }];
    }
}
#endif

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
    // Enlarging takes a moment on a large image, so it's on a thread of its own, as the read is.
    NSDictionary *job = @{ @"path": url.path, @"tesseract": tesseract, @"rect": [NSValue valueWithRect:rect],
                           @"completion": finish };
    [NSThread detachNewThreadSelector:@selector(runTesseractJob:) toTarget:self withObject:job];
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
                // Accurate, without language correction: it "corrects" email addresses into words and
                // doubles the time (the Redact A/B, 2026-11-05). A large region is read in tiles.
                NSArray<NSValue *> *tiles = STVisionTilesForRegion(region);
                NSMutableArray<NSArray<STRecognizedLine *> *> *tileLines = [NSMutableArray array];
                for (NSValue *tileValue in tiles) {
                    NSRect tile = tileValue.rectValue;
                    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];
                    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
                    request.usesLanguageCorrection = NO;
                    if (@available(macOS 13.0, *)) {
                        request.automaticallyDetectsLanguage = YES;
                    }
                    // Vision's region is normalised with a bottom-left origin.
                    request.regionOfInterest = CGRectMake(NSMinX(tile) / NSWidth(whole),
                                                          1.0 - NSMaxY(tile) / NSHeight(whole),
                                                          NSWidth(tile) / NSWidth(whole),
                                                          NSHeight(tile) / NSHeight(whole));
                    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
                    NSError *error = nil;
                    if (![handler performRequests:@[request] error:&error]) {
                        failure = error.localizedDescription ?: @"Vision couldn't read the image.";
                        tileLines = nil;
                        break;
                    }
                    [tileLines addObject:STLinesFromVisionObservations(request.results ?: @[], tile)];
                }
                if (tileLines) {
                    lines = STMergeTiledLines(tileLines, tiles, region);
                }
            }
            CGImageRelease(image);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            finish(lines, lines ? nil : failure);
        });
    });
#elif ST_TEXT_WINDOWS
    // Windows.Media.Ocr reads the rect, cropped; its boxes come back in the whole image.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *failure = nil;
        NSArray<STRecognizedLine *> *lines = STWindowsRecognizeText(url, rect, &failure);
        void (^call)(void) = ^{
            finish(lines, lines ? nil : failure);
        };
        // GNUstep's run loop doesn't drain GCD's main queue on Windows; back as an event would be.
        [STTextRecognizer performSelectorOnMainThread:@selector(runCompletion:) withObject:[call copy]
                                        waitUntilDone:NO modes:@[NSDefaultRunLoopMode]];
    });
#else
    (void)url;
    (void)rect;
    dispatch_async(dispatch_get_main_queue(), ^{
        finish(nil, @"Text recognition isn't available on this platform yet.");
    });
#endif
}

#if ST_TEXT_WINDOWS
+ (void)runCompletion:(void (^)(void))call {
    call();
}
#endif

@end
