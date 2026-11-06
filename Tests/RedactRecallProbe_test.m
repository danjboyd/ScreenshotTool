/*
 * RedactRecallProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Redact Emails and Phone Numbers finds what's there (#278 accuracy, 2026-11-05): five text-dense
 * 3840 x 2160 captures, each line prose with one email address or phone number in it, are read by the
 * app's own reader and matched by STSensitiveTextRects. An item counts as redacted when the redactions
 * cover at least 95% of its ink; each capture has a floor for how many must be. Also: Copy Text on a
 * large capture keeps its lines whole and in order, with nothing read twice where tiles overlap.
 *
 * macOS (Vision) only: the floors are Vision's, enforced with ST_REDACT_RECALL=1 (the release checklist);
 * without it the probe reads and logs its recall but doesn't fail. Set ST_WRITE_REDACT_CAPTURES to a directory to write
 * the captures and their ground truth (JSON) there, for the other platforms' engines.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if !defined(GNUSTEP)
#import "STTextRecognizer.h"

@interface STRecallItem : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic) NSRect ink;  // pixels, top-left origin
@property (nonatomic) BOOL isEmail;
@end
@implementation STRecallItem
@end

@interface RedactRecallProbeTests : XCTestCase
@end

@implementation RedactRecallProbeTests

/// Whether the floors are enforced: ST_REDACT_RECALL=1, as the release checklist runs it. Otherwise
/// (CI, whose VMs may read differently) the probe reads and logs its recall but doesn't fail on it.
static BOOL STRecallEnforced(void) {
    return [[[NSProcessInfo processInfo] environment][@"ST_REDACT_RECALL"] isEqualToString:@"1"];
}

static NSArray<NSString *> *STRecallEmails(void) {
    return @[ @"jane.doe@example.com", @"j.smith+billing@mail.example.co.uk", @"ops-team@sub.domain-name.io",
              @"first_last99@company.org", @"x7@y.dev", @"Support@Example.COM", @"a.b.c.d@e-f.museum",
              @"rachel.o'neil@example.ie", @"m.mueller@firma-gmbh.de", @"li.wei2024@qq.example.cn" ];
}

static NSArray<NSString *> *STRecallPhones(void) {
    return @[ @"+1 (512) 555-0134", @"512-555-0199", @"(512) 555 0123", @"512.555.0177", @"+44 20 7946 0958",
              @"+49 30 901820", @"+33 1 23 45 67 89", @"555-0100", @"+1-800-555-0199", @"07700 900123" ];
}

static NSArray<NSString *> *STRecallProse(void) {
    return @[ @"Please review the attached quarterly figures and reply before Friday",
              @"The deployment finished at 14:32 and all 3 regions report healthy",
              @"Meeting moved to room 4B; bring the printed agenda and your notes",
              @"Invoice 2026-10-22 was paid in full, reference INV-00412 for records" ];
}

/// The five captures: name, font, text and background colours, rows and columns, and the floor of
/// items (emails and phones together) that must be redacted.
+ (NSArray<NSDictionary *> *)captures {
    return @[
        @{ @"name": @"light-13pt-1x", @"font": [NSFont systemFontOfSize:13], @"fg": NSColor.blackColor,
           @"bg": NSColor.whiteColor, @"rows": @80, @"cols": @3 },
        @{ @"name": @"light-22pt-retina", @"font": [NSFont systemFontOfSize:22], @"fg": NSColor.blackColor,
           @"bg": NSColor.whiteColor, @"rows": @50, @"cols": @2 },
        @{ @"name": @"dark-18pt", @"font": [NSFont systemFontOfSize:18], @"fg": [NSColor colorWithCalibratedWhite:0.86 alpha:1],
           @"bg": [NSColor colorWithCalibratedWhite:0.12 alpha:1], @"rows": @60, @"cols": @2 },
        @{ @"name": @"terminal-mono-16pt",
           @"font": [NSFont fontWithName:@"Menlo" size:16] ?: [NSFont monospacedSystemFontOfSize:16 weight:NSFontWeightRegular],
           @"fg": [NSColor colorWithCalibratedRed:0.3 green:0.95 blue:0.4 alpha:1], @"bg": NSColor.blackColor, @"rows": @70, @"cols": @2 },
        @{ @"name": @"grey-on-grey-11pt", @"font": [NSFont systemFontOfSize:11], @"fg": [NSColor colorWithCalibratedWhite:0.45 alpha:1],
           @"bg": [NSColor colorWithCalibratedWhite:0.93 alpha:1], @"rows": @90, @"cols": @3 },
    ];
}

/// A capture's PNG, with its emails and phones as ground truth: each item's ink, its glyphs' own box.
- (NSData *)captureFrom:(NSDictionary *)spec items:(NSMutableArray<STRecallItem *> *)items {
    const NSInteger W = 3840, H = 2160;
    NSFont *font = spec[@"font"];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [(NSColor *)spec[@"bg"] setFill];
    NSRectFill(NSMakeRect(0, 0, W, H));
    NSDictionary *attrs = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: spec[@"fg"] };
    CGFloat lineHeight = ceil([@"Ag" sizeWithAttributes:attrs].height * 1.45);
    NSInteger columns = [spec[@"cols"] integerValue], rows = [spec[@"rows"] integerValue];
    CGFloat columnWidth = (W - 80.0) / columns;
    NSArray *emails = STRecallEmails(), *phones = STRecallPhones(), *prose = STRecallProse();
    NSInteger n = 0;
    for (NSInteger c = 0; c < columns; c++) {
        for (NSInteger r = 0; r < rows; r++, n++) {
            BOOL isEmail = n % 2 == 0;
            NSString *item = isEmail ? emails[(n / 2) % emails.count] : phones[(n / 2) % phones.count];
            NSArray<NSString *> *parts = [prose[n % prose.count] componentsSeparatedByString:@" "];
            NSInteger cut = MIN((NSInteger)parts.count, 4 + n % 3);
            NSString *before = [[[parts subarrayWithRange:NSMakeRange(0, cut)] componentsJoinedByString:@" "] stringByAppendingString:@" "];
            NSString *after = [@" " stringByAppendingString:[[parts subarrayWithRange:NSMakeRange(cut, parts.count - cut)]
                                                                componentsJoinedByString:@" "]];
            NSPoint origin = NSMakePoint(40 + c * columnWidth, H - 40 - (r + 1) * lineHeight);
            if (origin.y < 20) {
                continue;
            }
            [[NSString stringWithFormat:@"%@%@%@", before, item, after] drawAtPoint:origin withAttributes:attrs];
            NSRect ink = [[[NSAttributedString alloc] initWithString:item attributes:attrs]
                boundingRectWithSize:NSMakeSize(10000, 1000)
                             options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesDeviceMetrics];
            CGFloat x0 = origin.x + [before sizeWithAttributes:attrs].width;
            CGFloat baseline = origin.y - font.descender;
            NSRect inImage = NSMakeRect(x0 + NSMinX(ink), baseline + NSMinY(ink), NSWidth(ink), NSHeight(ink));
            STRecallItem *truth = [[STRecallItem alloc] init];
            truth.text = item;
            truth.isEmail = isEmail;
            truth.ink = NSMakeRect(NSMinX(inImage), H - NSMaxY(inImage), NSWidth(inImage), NSHeight(inImage));
            [items addObject:truth];
        }
    }
    [[NSGraphicsContext currentContext] flushGraphics];
    [NSGraphicsContext restoreGraphicsState];
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

- (NSArray<STRecognizedLine *> *)readPNG:(NSData *)png {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"capture.png"]];
    [png writeToURL:url atomically:YES];
    __block NSArray<STRecognizedLine *> *lines = nil;
    __block BOOL done = NO;
    [STTextRecognizer recognizeTextInImageAtURL:url rect:NSZeroRect completion:^(NSArray<STRecognizedLine *> *l, NSString *f) {
        (void)f;
        lines = l;
        done = YES;
    }];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:120.0];
    while (!done && [until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    XCTAssertTrue(done, @"the read finished");
    return lines ?: @[];
}

/// The share of `rect` inside the union of `rects`, sampled every 2 pixels.
static CGFloat STRecallCoverage(NSRect rect, NSArray<NSValue *> *rects) {
    NSUInteger inside = 0, total = 0;
    for (CGFloat y = NSMinY(rect) + 1; y < NSMaxY(rect); y += 2) {
        for (CGFloat x = NSMinX(rect) + 1; x < NSMaxX(rect); x += 2) {
            total++;
            for (NSValue *value in rects) {
                if (NSPointInRect(NSMakePoint(x, y), value.rectValue)) {
                    inside++;
                    break;
                }
            }
        }
    }
    return total ? (CGFloat)inside / total : 0;
}

/// The redacted share of a capture's items, logged with what was missed.
- (NSUInteger)redactedInCapture:(NSDictionary *)spec items:(NSMutableArray<STRecallItem *> *)items png:(NSData **)pngOut {
    NSData *png = [self captureFrom:spec items:items];
    if (pngOut) {
        *pngOut = png;
    }
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    NSArray<STRecognizedLine *> *readLines = [self readPNG:png];
    NSArray<NSValue *> *rects = STSensitiveTextRects(readLines);
    double seconds = CFAbsoluteTimeGetCurrent() - start;
    NSUInteger redacted = 0, emails = 0, phones = 0, emailsTotal = 0, partial = 0;
    NSMutableArray<NSString *> *missed = [NSMutableArray array];
    for (STRecallItem *item in items) {
        CGFloat coverage = STRecallCoverage(item.ink, rects);
        item.isEmail ? emailsTotal++ : 0;
        if (coverage >= 0.95) {
            redacted++;
            item.isEmail ? emails++ : phones++;
        } else {
            partial += coverage >= 0.5 ? 1 : 0;
            if (missed.count < 8) {
                NSString *near = @"(nothing)";
                for (STRecognizedLine *line in readLines) {
                    if (NSIntersectsRect(line.bounds, item.ink)) {
                        near = line.text;
                        break;
                    }
                }
                [missed addObject:[NSString stringWithFormat:@"%@ (%.0f%%) read \"%@\"", item.text, coverage * 100, near]];
            }
        }
    }
    NSLog(@"RECALL %@: %lu/%lu redacted (emails %lu/%lu, phones %lu/%lu), %lu partial, %.2f s; missed e.g. %@",
          spec[@"name"], (unsigned long)redacted, (unsigned long)items.count, (unsigned long)emails, (unsigned long)emailsTotal,
          (unsigned long)phones, (unsigned long)(items.count - emailsTotal), (unsigned long)partial, seconds,
          [missed componentsJoinedByString:@"; "]);
    return redacted;
}

- (void)writeCapture:(NSDictionary *)spec png:(NSData *)png items:(NSArray<STRecallItem *> *)items {
    NSString *dir = [[NSProcessInfo processInfo] environment][@"ST_WRITE_REDACT_CAPTURES"];
    if (dir.length == 0) {
        return;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    [png writeToFile:[dir stringByAppendingPathComponent:[spec[@"name"] stringByAppendingString:@".png"]] atomically:YES];
    NSMutableArray *truth = [NSMutableArray array];
    for (STRecallItem *item in items) {
        [truth addObject:@{ @"text": item.text, @"kind": item.isEmail ? @"email" : @"phone",
                            @"ink": @[ @(round(NSMinX(item.ink) * 10) / 10), @(round(NSMinY(item.ink) * 10) / 10),
                                       @(round(NSWidth(item.ink) * 10) / 10), @(round(NSHeight(item.ink) * 10) / 10) ] }];
    }
    NSDictionary *json = @{ @"capture": spec[@"name"], @"size": @[ @3840, @2160 ],
                            @"ink": @"x, y, width, height in pixels from the top left",
                            @"redacted_when": @"the redaction rects cover at least 95% of the ink",
                            @"items": truth };
    [[NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL]
        writeToFile:[dir stringByAppendingPathComponent:[spec[@"name"] stringByAppendingString:@".json"]] atomically:YES];
}

/// Each capture's floor: what the reader and matcher redacted on 2026-11-05 (232, 100, 120, 138 and
/// 264 items; before the tiled read and the matcher's fixes, 138, 88, 89, 63 and 0), less a margin
/// for Vision's version differences. A drop below it is a regression in what Redact hides.
- (void)testRedactFindsTheEmailsAndPhoneNumbers {
    NSDictionary<NSString *, NSNumber *> *floors = @{ @"light-13pt-1x": @220, @"light-22pt-retina": @95, @"dark-18pt": @114,
                                                      @"terminal-mono-16pt": @130, @"grey-on-grey-11pt": @250 };
    for (NSDictionary *spec in [[self class] captures]) {
        @autoreleasepool {
            NSMutableArray<STRecallItem *> *items = [NSMutableArray array];
            NSData *png = nil;
            NSUInteger redacted = [self redactedInCapture:spec items:items png:&png];
            [self writeCapture:spec png:png items:items];
            NSUInteger floor = floors[spec[@"name"]].unsignedIntegerValue;
            if (STRecallEnforced()) {
                XCTAssertGreaterThanOrEqual(redacted, floor, @"%@: %lu of %lu items redacted", spec[@"name"],
                                            (unsigned long)redacted, (unsigned long)items.count);
            } else if (redacted < floor) {
                NSLog(@"RECALL %@ is under its floor of %lu (not enforced without ST_REDACT_RECALL=1)", spec[@"name"], (unsigned long)floor);
            }
        }
    }
}

/// The text with spaces gone, upper case, O read as 0 and L and I as 1: a reader's small slips
/// ("Row 24", "RowO6ends", "Row1lends") aren't what this probe is about.
static NSString *STRecallFolded(NSString *text) {
    NSString *folded = [[text uppercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    folded = [folded stringByReplacingOccurrencesOfString:@"O" withString:@"0"];
    folded = [folded stringByReplacingOccurrencesOfString:@"L" withString:@"1"];
    return [folded stringByReplacingOccurrencesOfString:@"I" withString:@"1"];
}

/// Copy Text on a capture read in tiles: every line once, whole, in order, even lines longer than a
/// tile, which two tiles each read only part of.
/// An XCTAssert that, without ST_REDACT_RECALL=1, only logs: what a reader makes of a capture can
/// differ on CI's VMs.
#define STRecallCheck(condition, ...) do { \
    if (STRecallEnforced()) { XCTAssertTrue((condition), __VA_ARGS__); } \
    else if (!(condition)) { NSLog(@"RECALL check not met (not enforced): %@", [NSString stringWithFormat:__VA_ARGS__]); } \
} while (0)

- (void)testCopyTextKeepsLinesWholeAndInOrderAcrossTiles {
    const NSInteger W = 3840, H = 2160, rows = 23;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [NSColor.whiteColor setFill];
    NSRectFill(NSMakeRect(0, 0, W, H));
    NSDictionary *attrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:46], NSForegroundColorAttributeName: NSColor.blackColor };
    CGFloat widest = 0;
    for (NSInteger i = 0; i < rows; i++) {
        NSString *line = [NSString stringWithFormat:@"Row%02ld begins here and the quick brown fox jumps over the lazy dog while "
                                                    @"seven sleepy cats watch from the garden wall until Row%02ldends",
                                                    (long)i, (long)i];
        [line drawAtPoint:NSMakePoint(40, H - 40 - (i + 1) * 90) withAttributes:attrs];
        widest = MAX(widest, [line sizeWithAttributes:attrs].width);
    }
    [[NSGraphicsContext currentContext] flushGraphics];
    [NSGraphicsContext restoreGraphicsState];
    // Wider than a tile (2560), so every line is read in two parts and joined.
    XCTAssertGreaterThan(widest, 2600.0);

    NSArray<STRecognizedLine *> *lines = [self readPNG:[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]];
    NSString *text = STRecognizedText(lines);
    NSArray<NSString *> *read = [text componentsSeparatedByString:@"\n"];
    STRecallCheck(read.count == (NSUInteger)rows, @"a line each:\n%@", text);
    NSString *all = STRecallFolded(text);
    // "wall until" is in every line, once: none read twice where tiles overlap.
    STRecallCheck([all componentsSeparatedByString:@"WA11UNT11"].count - 1 == (NSUInteger)rows, @"nothing read twice:\n%@", text);
    NSInteger last = -1;
    for (NSInteger i = 0; i < rows; i++) {
        NSString *start = STRecallFolded([NSString stringWithFormat:@"Row%02ld", (long)i]);
        NSString *end = STRecallFolded([NSString stringWithFormat:@"Row%02ldends", (long)i]);
        NSInteger at = -1;
        for (NSInteger k = 0; k < (NSInteger)read.count; k++) {
            NSString *folded = STRecallFolded(read[k]);
            if ([folded hasPrefix:start] && [folded hasSuffix:end]) {
                at = k;
                break;
            }
        }
        STRecallCheck(at > last, @"line %ld whole, and after the one before:\n%@", (long)i, text);
        last = MAX(last, at);
    }
}

@end
#endif
