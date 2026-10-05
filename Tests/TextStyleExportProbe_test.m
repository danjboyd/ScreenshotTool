/*
 * TextStyleExportProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Text styles (#24) and export fidelity (#26): exported text must match what the canvas draws.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "ScreenshotCanvasView.h"
#import "MarkupText.h"
#import "TestEnvironmentHelpers.h"

@interface ScreenshotCanvasView (TextStyleExportProbe)
@property (nonatomic, strong) NSMutableArray<MarkupText *> *texts;
@end

@interface TextStyleExportProbeTests : XCTestCase {
    BOOL _shouldSkip;
}
@end

@implementation TextStyleExportProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

#pragma mark - Helpers

static const NSSize STProbeCanvasSize = {320.0, 140.0};

- (NSImage *)whiteImage {
    NSImage *image = [[NSImage alloc] initWithSize:STProbeCanvasSize];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, STProbeCanvasSize.width, STProbeCanvasSize.height));
    [image unlockFocus];
    return image;
}

- (MarkupText *)labelWithStyle:(MarkupTextStyle)style {
    NSFont *font = [NSFont fontWithName:@"DejaVuSans" size:28.0] ?: [NSFont systemFontOfSize:28.0];
    MarkupText *text = [[MarkupText alloc] initWithText:@"Check this"
                                                   font:font
                                                  color:[NSColor colorWithDeviceRed:0.9 green:0.1 blue:0.15 alpha:1.0]
                                                 origin:NSMakePoint(30.0, 40.0)
                                                 boxSize:NSMakeSize(1.0, 1.0)];
    text.style = style;
    [text fitToTextWithinCanvasSize:STProbeCanvasSize];
    return text;
}

/// The canvas's own drawing of a label over white, read back through a locked image.
- (NSBitmapImageRep *)referenceRenderingOf:(MarkupText *)text {
    NSImage *image = [[NSImage alloc] initWithSize:STProbeCanvasSize];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, STProbeCanvasSize.width, STProbeCanvasSize.height));
    [text drawAtScale:1.0 unflippedHeight:STProbeCanvasSize.height decorationsOnly:NO];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0.0, 0.0, STProbeCanvasSize.width, STProbeCanvasSize.height)];
    [image unlockFocus];
    return rep;
}

- (NSBitmapImageRep *)exportOf:(MarkupText *)text {
    ScreenshotCanvasView *canvas = [[ScreenshotCanvasView alloc] initWithFrame:NSMakeRect(0.0, 0.0, STProbeCanvasSize.width, STProbeCanvasSize.height)];
    [canvas loadImage:[self whiteImage]];
    if (!canvas.texts) {
        canvas.texts = [[NSMutableArray alloc] init];
    }
    [canvas.texts addObject:text];
    NSImage *flattened = [canvas flattenedImage];
    return [NSBitmapImageRep imageRepWithData:[flattened TIFFRepresentation]];
}

static NSColor *STProbePixel(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    return [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
}

/// Fraction of pixels in the label's area whose colour differs by more than a small tolerance.
- (double)mismatchBetween:(NSBitmapImageRep *)a and:(NSBitmapImageRep *)b inRect:(NSRect)rect {
    NSInteger total = 0;
    NSInteger different = 0;
    for (NSInteger y = (NSInteger)NSMinY(rect); y < (NSInteger)NSMaxY(rect); y++) {
        for (NSInteger x = (NSInteger)NSMinX(rect); x < (NSInteger)NSMaxX(rect); x++) {
            NSColor *pa = STProbePixel(a, x, y);
            NSColor *pb = STProbePixel(b, x, y);
            if (!pa || !pb) {
                continue;
            }
            total++;
            double delta = MAX(fabs(pa.redComponent - pb.redComponent),
                               MAX(fabs(pa.greenComponent - pb.greenComponent), fabs(pa.blueComponent - pb.blueComponent)));
            if (delta > 0.12) {
                different++;
            }
        }
    }
    return total > 0 ? (double)different / (double)total : 1.0;
}

- (NSInteger)countPixelsIn:(NSBitmapImageRep *)rep rect:(NSRect)rect matching:(BOOL (^)(NSColor *))predicate {
    NSInteger count = 0;
    for (NSInteger y = (NSInteger)NSMinY(rect); y < (NSInteger)NSMaxY(rect); y++) {
        for (NSInteger x = (NSInteger)NSMinX(rect); x < (NSInteger)NSMaxX(rect); x++) {
            NSColor *pixel = STProbePixel(rep, x, y);
            if (pixel && predicate(pixel)) {
                count++;
            }
        }
    }
    return count;
}

#pragma mark - Export fidelity (#26)

- (void)testExportMatchesCanvasDrawingForEveryStyle {
    XCTSkipIf(_shouldSkip, @"No window server");

    NSArray<NSNumber *> *styles = @[@(MarkupTextStylePlain), @(MarkupTextStyleOutline), @(MarkupTextStyleShadow), @(MarkupTextStyleBackground)];
    for (NSNumber *styleNumber in styles) {
        MarkupText *text = [self labelWithStyle:(MarkupTextStyle)styleNumber.integerValue];
        NSBitmapImageRep *reference = [self referenceRenderingOf:text];
        NSBitmapImageRep *exported = [self exportOf:text];
        XCTAssertNotNil(reference);
        XCTAssertNotNil(exported);

        // Both bitmaps are top-down, so the label's canvas rect applies to both directly.
        NSRect area = NSIntersectionRect(NSInsetRect([text decoratedBounds], -2.0, -2.0),
                                         NSMakeRect(0.0, 0.0, STProbeCanvasSize.width, STProbeCanvasSize.height));
        NSInteger inked = [self countPixelsIn:exported rect:area matching:^BOOL(NSColor *p) {
            return p.redComponent < 0.9 || p.greenComponent < 0.9 || p.blueComponent < 0.9;
        }];
        XCTAssertTrue(inked > 150, @"Style %@: exported text should be drawn (found %ld inked pixels)", styleNumber, (long)inked);

        double mismatch = [self mismatchBetween:reference and:exported inRect:area];
        XCTAssertTrue(mismatch < 0.02, @"Style %@: export should match the canvas drawing (%.1f%% of pixels differ)", styleNumber, mismatch * 100.0);
    }
}

#pragma mark - Styles (#24)

- (void)testBackgroundStyleDrawsBoxWithContrastingText {
    XCTSkipIf(_shouldSkip, @"No window server");

    MarkupText *text = [self labelWithStyle:MarkupTextStyleBackground];
    NSBitmapImageRep *exported = [self exportOf:text];
    NSRect box = [text decoratedBounds];

    // The padding strip just inside the box edge is solid text colour.
    NSRect strip = NSMakeRect(NSMinX(box) + 6.0, NSMinY(box) + 2.0, NSWidth(box) - 12.0, 2.0);
    NSInteger red = [self countPixelsIn:exported rect:strip matching:^BOOL(NSColor *p) {
        return p.redComponent > 0.8 && p.greenComponent < 0.3;
    }];
    XCTAssertTrue(red > (NSInteger)(NSWidth(strip) * 2.0 * 0.9), @"The background box should fill with the text colour");

    // Glyphs are drawn in white over the red box.
    NSInteger white = [self countPixelsIn:exported rect:[text textBounds] matching:^BOOL(NSColor *p) {
        return p.redComponent > 0.9 && p.greenComponent > 0.9 && p.blueComponent > 0.9;
    }];
    XCTAssertTrue(white > 100, @"Glyphs on a red box should be drawn in a contrasting colour");
    XCTAssertEqualObjects([[text glyphColor] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]],
                          [[NSColor whiteColor] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]]);
}

- (void)testOutlineStyleDrawsContrastingEdge {
    XCTSkipIf(_shouldSkip, @"No window server");

    MarkupText *plain = [self labelWithStyle:MarkupTextStylePlain];
    MarkupText *outlined = [self labelWithStyle:MarkupTextStyleOutline];
    // A light (yellow) label gets a black outline; over white, dark pixels appear only with it.
    plain.color = [NSColor yellowColor];
    outlined.color = [NSColor yellowColor];
    BOOL (^dark)(NSColor *) = ^BOOL(NSColor *p) {
        return p.redComponent < 0.25 && p.greenComponent < 0.25 && p.blueComponent < 0.25;
    };
    NSInteger plainDark = [self countPixelsIn:[self exportOf:plain] rect:[plain decoratedBounds] matching:dark];
    NSInteger outlinedDark = [self countPixelsIn:[self exportOf:outlined] rect:[outlined decoratedBounds] matching:dark];
    XCTAssertTrue(outlinedDark > plainDark + 100, @"An outline should add a dark edge around light-on-white text (%ld vs %ld)", (long)outlinedDark, (long)plainDark);
}

- (void)testDecorationsCountForHitTestingAndStayOnTheImage {
    MarkupText *text = [self labelWithStyle:MarkupTextStyleBackground];
    NSRect textBounds = [text textBounds];
    NSRect decorated = [text decoratedBounds];
    XCTAssertTrue(NSContainsRect(decorated, textBounds) && NSWidth(decorated) > NSWidth(textBounds),
                  @"The background box extends past the glyphs");

    NSPoint inPadding = NSMakePoint(NSMinX(decorated) + 1.0, NSMidY(decorated));
    XCTAssertFalse(NSPointInRect(inPadding, textBounds));
    XCTAssertTrue([text containsPoint:inPadding], @"Clicking the visible box hits the annotation");

    MarkupText *atCorner = [self labelWithStyle:MarkupTextStyleBackground];
    atCorner.origin = NSZeroPoint;
    [atCorner fitToTextWithinCanvasSize:STProbeCanvasSize];
    NSRect cornerBox = [atCorner decoratedBounds];
    XCTAssertTrue(NSMinX(cornerBox) >= -0.5 && NSMinY(cornerBox) >= -0.5,
                  @"A box placed at the corner should be moved so its background stays on the image");
}

- (void)testStyleSurvivesCopy {
    MarkupText *text = [self labelWithStyle:MarkupTextStyleShadow];
    MarkupText *copy = [text copy];
    XCTAssertEqual(copy.style, MarkupTextStyleShadow, @"Undo snapshots copy the style");
}

@end
