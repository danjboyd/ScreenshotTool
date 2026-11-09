/*
 * TextLabelZoomProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * A label's background fits the text as drawn at every zoom. The canvas draws text with a font
 * scaled to the zoom, whose hinted advances don't scale evenly, while Copy draws at 1x.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "MarkupText.h"
#import "ScreenshotCanvasView.h"
#import "ScreenshotToolSettings.h"
#import "TestEnvironmentHelpers.h"


@interface AppDelegate (TextLabelZoomTesting)
- (void)setupWindowAndContent;
- (void)layoutContentSubviews;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
@end

@interface ScreenshotCanvasView (TextLabelZoomTesting)
@property (nonatomic, strong) NSMutableArray<MarkupText *> *texts;
- (NSArray *)selectedAnnotationObjects;
- (NSRect)boundsOfAnnotation:(id)annotation;
@end

@interface TextLabelZoomProbeTests : XCTestCase
@end

@implementation TextLabelZoomProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
}

/// The label drawn at `scale` on a white canvas of `canvas` points, read back one pixel per canvas point. Drawn
/// and read in strips STCaptureStripWidth points wide: on a CI runner with a small desktop, GNUstep's Windows
/// backend read back columns past about 1050 px as non-white, which the scans below took for the pill. Each
/// strip keeps the canvas's full height, so the unflipped y the label draws at is unchanged.
static const CGFloat STCaptureStripWidth = 512.0;

static NSBitmapImageRep *STCaptureLabel(MarkupText *label, CGFloat scale, NSSize canvas) {
    NSInteger width = (NSInteger)canvas.width, height = (NSInteger)canvas.height;
    NSBitmapImageRep *whole = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    // One image, drawn and read once per strip.
    NSInteger fullStrip = MIN((NSInteger)STCaptureStripWidth, width);
    NSImage *strip = [[NSImage alloc] initWithSize:NSMakeSize(fullStrip, height)];
    for (NSInteger x0 = 0; x0 < width; x0 += (NSInteger)STCaptureStripWidth) {
        NSInteger stripWidth = MIN((NSInteger)STCaptureStripWidth, width - x0);
        [strip lockFocus];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0.0, 0.0, fullStrip, height));
        // Saved and restored: GNUstep doesn't reset the transform on the next lockFocus of this image.
        [NSGraphicsContext saveGraphicsState];
        NSAffineTransform *shift = [NSAffineTransform transform];
        [shift translateXBy:-(CGFloat)x0 yBy:0.0];
        [shift concat];
        [label drawAtScale:scale unflippedHeight:canvas.height decorationsOnly:NO];
        [NSGraphicsContext restoreGraphicsState];
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0.0, 0.0, stripWidth, height)];
        [strip unlockFocus];
        // Pixels per canvas point: 1 unless the backend backs the image at a higher density, when each point is
        // sampled at its pixel's centre so the scans still count canvas points.
        CGFloat densityX = (CGFloat)rep.pixelsWide / stripWidth, densityY = (CGFloat)rep.pixelsHigh / height;
        if (x0 == 0) {
            NSLog(@"STCaptureLabel: scale %.3f canvas %ldx%ld, strip %ld pt read back %ldx%ld px (density %.2f x %.2f)",
                  scale, (long)width, (long)height, (long)stripWidth, (long)rep.pixelsWide, (long)rep.pixelsHigh, densityX, densityY);
        }
        if (rep.pixelsWide < stripWidth || rep.pixelsHigh < height || rep.pixelsWide > STCaptureStripWidth * 2.0) {
            NSLog(@"STCaptureLabel: strip at %ld read back %ldx%ld for %ldx%ld points", (long)x0, (long)rep.pixelsWide,
                  (long)rep.pixelsHigh, (long)stripWidth, (long)height);
            return nil;
        }
        for (NSInteger y = 0; y < height; y++) {
            NSInteger py = MIN((NSInteger)floor((y + 0.5) * densityY), rep.pixelsHigh - 1);
            for (NSInteger x = 0; x < stripWidth; x++) {
                NSInteger px = MIN((NSInteger)floor((x + 0.5) * densityX), rep.pixelsWide - 1);
                NSColor *c = [[rep colorAtX:px y:py] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
                [whole setColor:c atX:x0 + x y:y];
            }
        }
    }
    return whole;
}

/// The capture's four corners are the white it was filled with: the readback is whole.
static BOOL STCornersAreWhite(NSBitmapImageRep *rep) {
    if (!rep) {
        return NO;
    }
    NSInteger w = rep.pixelsWide - 1, h = rep.pixelsHigh - 1;
    BOOL white = YES;
    for (NSArray<NSNumber *> *p in @[ @[ @0, @0 ], @[ @(w), @0 ], @[ @0, @(h) ], @[ @(w), @(h) ] ]) {
        NSColor *c = [[rep colorAtX:p[0].integerValue y:p[1].integerValue] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
        // Written so a transparent pixel, whose components read back as NaN, isn't taken for white.
        if (!(c.redComponent >= 0.95 && c.greenComponent >= 0.95 && c.blueComponent >= 0.95 && c.alphaComponent >= 0.95)) {
            NSLog(@"STCornersAreWhite: corner %@,%@ is %.2f %.2f %.2f a %.2f", p[0], p[1], c.redComponent, c.greenComponent,
                  c.blueComponent, c.alphaComponent);
            white = NO;
        }
    }
    return white;
}

/// Space, in pixels, between the ends of the pill and the ends of the glyphs.
static void STMeasureGaps(XCTestCase *self, MarkupText *label, CGFloat scale, CGFloat *left, CGFloat *right, CGFloat *height) {
    NSSize canvas = NSMakeSize(ceil(1100.0 * scale), ceil(200.0 * scale));
    NSBitmapImageRep *rep = STCaptureLabel(label, scale, canvas);
    XCTAssertNotNil(rep, @"capture at %.3f", scale);
    XCTAssertTrue(STCornersAreWhite(rep), @"capture at %.3f isn't white at its corners", scale);
    NSInteger pillFirst = -1, pillLast = -1, glyphFirst = -1, glyphLast = -1, top = -1, bottom = -1;
    for (NSInteger x = 0; x < rep.pixelsWide; x++) {
        for (NSInteger y = 0; y < rep.pixelsHigh; y++) {
            NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
            if (c.blueComponent > 0.9) {
                continue; // The white around the pill.
            }
            pillFirst = pillFirst < 0 ? x : pillFirst;
            pillLast = x;
            top = (top < 0 || y < top) ? y : top;
            bottom = MAX(bottom, y);
            if (c.redComponent < 0.8) {
                glyphFirst = glyphFirst < 0 ? x : glyphFirst;
                glyphLast = x;
            }
        }
    }
    // Found, and inside the capture: a scan that reaches its edge measured the background.
    XCTAssertTrue(pillFirst > 0 && glyphFirst > pillFirst, @"pill %ld glyph %ld at %.3f", (long)pillFirst, (long)glyphFirst, scale);
    XCTAssertTrue(pillLast < rep.pixelsWide - 1 && glyphLast < pillLast, @"pill ends %ld of %ld, glyphs %ld at %.3f",
                  (long)pillLast, (long)rep.pixelsWide, (long)glyphLast, scale);
    XCTAssertTrue(top > 0 && bottom < rep.pixelsHigh - 1, @"pill rows %ld..%ld of %ld at %.3f", (long)top, (long)bottom,
                  (long)rep.pixelsHigh, scale);
    *left = glyphFirst - pillFirst;
    *right = pillLast - glyphLast;
    if (height) {
        *height = bottom - top + 1;
    }
}

- (void)testThePillFitsTheTextAtEveryZoom {
    NSArray<NSNumber *> *zooms = @[ @1.0, @0.947, @0.75, @0.5, @2.0, @1.5, @0.33, @0.8, @1.1 ];
    NSString *words = @"when in the course of human events";
    for (NSNumber *size in @[ @14, @18, @24, @36 ]) {
        NSFont *font = [NSFont systemFontOfSize:size.doubleValue];
        MarkupText *label = [[MarkupText alloc] initWithText:words font:font color:[NSColor yellowColor]
                                                      origin:NSMakePoint(40.0, 40.0) boxSize:NSMakeSize(200.0, 40.0)];
        label.style = MarkupTextStyleBackground;
        [label fitToTextWithinCanvasSize:NSMakeSize(1100.0, 200.0)];
        CGFloat pad = label.decorationOutset;
        for (NSNumber *zoom in zooms) {
            CGFloat scale = zoom.doubleValue, left = 0.0, right = 0.0;
            STMeasureGaps(self, label, scale, &left, &right, NULL);
            NSLog(@"LABELGAP %@ pt zoom %.3f: left %.0f right %.0f (padding %.1f)", size, scale, left, right, pad * scale);
            XCTAssertLessThanOrEqual(fabs(left - right), MAX(3.0, ceil(size.doubleValue * scale * 0.2)), @"%@ pt at %.3f: left %.0f right %.0f", size, scale, left, right);
        }
    }
}

- (void)testAlignedLabelsStayEvenInAWideBox {
    NSFont *font = [NSFont systemFontOfSize:18.0];
    for (NSNumber *alignment in @[ @(NSTextAlignmentLeft), @(NSTextAlignmentCenter), @(NSTextAlignmentRight) ]) {
        MarkupText *label = [[MarkupText alloc] initWithText:@"when in the course of human events" font:font color:[NSColor yellowColor]
                                                      origin:NSMakePoint(40.0, 40.0) boxSize:NSMakeSize(700.0, 40.0)];
        label.style = MarkupTextStyleBackground;
        label.alignment = alignment.integerValue;
        label.widthIsFixed = YES;
        [label fitToTextWithinCanvasSize:NSMakeSize(1100.0, 200.0)];
        for (NSNumber *zoom in @[ @0.947, @0.75, @0.5, @2.0 ]) {
            CGFloat left = 0.0, right = 0.0;
            STMeasureGaps(self, label, zoom.doubleValue, &left, &right, NULL);
            XCTAssertLessThanOrEqual(fabs(left - right), 3.0, @"alignment %@ at %@: left %.0f right %.0f", alignment, zoom, left, right);
        }
    }
}

- (void)testAWrappedLabelKeepsItsLinesAtEveryZoom {
    NSFont *font = [NSFont systemFontOfSize:18.0];
    MarkupText *label = [[MarkupText alloc] initWithText:@"when in the course of human events\nit becomes necessary for one people" font:font color:[NSColor yellowColor]
                                                  origin:NSMakePoint(40.0, 10.0) boxSize:NSMakeSize(230.0, 40.0)];
    label.style = MarkupTextStyleBackground;
    label.widthIsFixed = YES;
    [label fitToTextWithinCanvasSize:NSMakeSize(1100.0, 200.0)];
    CGFloat full = 0.0, left = 0.0, right = 0.0;
    STMeasureGaps(self, label, 1.0, &left, &right, &full);
    XCTAssertGreaterThan(full, label.lineHeight * 3.0, @"The label should wrap for this test");
    for (NSNumber *zoom in @[ @0.947, @0.75, @0.5, @1.1, @1.5, @2.0 ]) {
        CGFloat height = 0.0;
        STMeasureGaps(self, label, zoom.doubleValue, &left, &right, &height);
        XCTAssertEqualWithAccuracy(height, full * zoom.doubleValue, label.lineHeight * zoom.doubleValue * 0.5, @"at %@", zoom);
    }
}

/// The ends of the pill as drawn at `scale`, in image points.
static void STPillEnds(XCTestCase *self, MarkupText *label, CGFloat scale, CGFloat *minX, CGFloat *maxX) {
    NSSize canvas = NSMakeSize(ceil(1100.0 * scale), ceil(200.0 * scale));
    NSBitmapImageRep *rep = STCaptureLabel(label, scale, canvas);
    XCTAssertNotNil(rep, @"capture at %.3f", scale);
    XCTAssertTrue(STCornersAreWhite(rep), @"capture at %.3f isn't white at its corners", scale);
    NSInteger first = -1, last = -1;
    for (NSInteger x = 0; x < rep.pixelsWide; x++) {
        for (NSInteger y = 0; y < rep.pixelsHigh; y++) {
            if ([[rep colorAtX:x y:y] colorUsingColorSpaceName:NSDeviceRGBColorSpace].blueComponent <= 0.9) {
                first = first < 0 ? x : first;
                last = x;
                break;
            }
        }
    }
    XCTAssertTrue(first > 0 && last < rep.pixelsWide - 1, @"pill %ld..%ld of %ld at %.3f", (long)first, (long)last,
                  (long)rep.pixelsWide, scale);
    *minX = first / scale;
    *maxX = (last + 1) / scale;
}

/// One paint of the canvas, the way the window asks for it.
static void STDrawCanvas(ScreenshotCanvasView *canvas) {
    [canvas lockFocus];
    [canvas drawRect:canvas.bounds];
    [canvas unlockFocus];
}

static NSEvent *STMouse(NSEventType type, NSPoint viewPoint, ScreenshotCanvasView *canvas) {
    return [NSEvent mouseEventWithType:type location:[canvas convertPoint:viewPoint toView:nil] modifierFlags:0 timestamp:0
                          windowNumber:[canvas.window windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1.0];
}

/// Every part of the pill you can see selects and drags the label, and its outline surrounds the pill.
/// A 36 pt label at 94.7% draws wider than it measures at full size.
- (void)testThePillAsDrawnIsWhatYouClickAndWhatsOutlined {
    AppDelegate *app = [[AppDelegate alloc] init];
    [app setupWindowAndContent];
    [app.window makeKeyAndOrderFront:nil];
    ScreenshotCanvasView *canvas = app.canvasView;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(1100.0, 200.0)];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 1100.0, 200.0));
    [image unlockFocus];
    NSFont *font = [NSFont fontWithName:@"DejaVuSans" size:36.0] ?: [NSFont systemFontOfSize:36.0];
    for (NSNumber *zoom in @[ @0.947, @0.75, @0.5, @1.5, @2.0 ]) {
        [canvas loadImage:image];
        [app layoutContentSubviews];
        canvas.fitToWindow = NO;
        canvas.activeTool = ScreenshotCanvasToolSelect;
        MarkupText *label = [[MarkupText alloc] initWithText:@"when in the course of human events" font:font color:[NSColor yellowColor]
                                                      origin:NSMakePoint(40.0, 40.0) boxSize:NSMakeSize(200.0, 40.0)];
        label.style = MarkupTextStyleBackground;
        [label fitToTextWithinCanvasSize:image.size];
        if (!canvas.texts) {
            canvas.texts = [[NSMutableArray alloc] init];
        }
        [canvas.texts addObject:label];
        NSRect exported = label.decoratedBounds;
        canvas.zoomScale = zoom.doubleValue;
        STDrawCanvas(canvas);

        CGFloat minX = 0.0, maxX = 0.0;
        STPillEnds(self, label, zoom.doubleValue, &minX, &maxX);
        NSRect outline = [canvas boundsOfAnnotation:label];
        XCTAssertLessThanOrEqual(NSMinX(outline), minX + 1.0, @"at %@", zoom);
        XCTAssertGreaterThanOrEqual(NSMaxX(outline), maxX - 1.0, @"at %@", zoom);
        XCTAssertTrue(NSEqualRects(label.decoratedBounds, exported), @"Export's bounds don't follow the zoom");

        // A press on the pill's last pixel selects, and a drag from it moves the label.
        CGFloat y = NSMidY(label.decoratedBounds) * zoom.doubleValue;
        NSPoint end = NSMakePoint((maxX - 1.0) * zoom.doubleValue, y);
        NSPoint moved = NSMakePoint(end.x + 20.0, end.y + 10.0);
        [canvas mouseDown:STMouse(NSLeftMouseDown, end, canvas)];
        XCTAssertTrue([canvas selectedAnnotationObjects].firstObject == label, @"at %@: the pill's right end should select it", zoom);
        NSPoint before = label.origin;
        [canvas mouseDragged:STMouse(NSLeftMouseDragged, moved, canvas)];
        [canvas mouseUp:STMouse(NSLeftMouseUp, moved, canvas)];
        XCTAssertGreaterThan(label.origin.x, before.x, @"at %@: a drag from it should move the label", zoom);

        // Well past the pill, nothing.
        STDrawCanvas(canvas);
        CGFloat newMin = 0.0, newMax = 0.0;
        STPillEnds(self, label, zoom.doubleValue, &newMin, &newMax);
        XCTAssertFalse([label containsPoint:NSMakePoint(newMax + 8.0, NSMidY(label.decoratedBounds))], @"at %@", zoom);
        canvas.zoomScale = 1.0;
    }
}

/// A capture wider than the cutoff seen on CI reads back white all the way across.
- (void)testAWideCaptureReadsBackWhole {
    MarkupText *label = [[MarkupText alloc] initWithText:@"x" font:[NSFont systemFontOfSize:14.0] color:[NSColor yellowColor]
                                                  origin:NSMakePoint(40.0, 40.0) boxSize:NSMakeSize(40.0, 40.0)];
    label.style = MarkupTextStyleBackground;
    [label fitToTextWithinCanvasSize:NSMakeSize(2600.0, 200.0)];
    NSBitmapImageRep *rep = STCaptureLabel(label, 1.0, NSMakeSize(2600.0, 200.0));
    XCTAssertNotNil(rep);
    XCTAssertEqual(rep.pixelsWide, 2600);
    XCTAssertTrue(STCornersAreWhite(rep));
    NSInteger lastPainted = -1;
    for (NSInteger x = 0; x < rep.pixelsWide; x++) {
        for (NSInteger y = 0; y < rep.pixelsHigh; y += 4) {
            NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
            if (!(c.blueComponent > 0.9 && c.alphaComponent > 0.9)) {
                lastPainted = x;
                break;
            }
        }
    }
    XCTAssertGreaterThan(lastPainted, 0, @"the label should be found");
    XCTAssertLessThan(lastPainted, 200, @"nothing past the label should read back as painted");
}

@end
