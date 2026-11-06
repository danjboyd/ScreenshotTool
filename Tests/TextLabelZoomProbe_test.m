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

/// Space, in pixels, between the ends of the pill and the ends of the glyphs.
static void STMeasureGaps(MarkupText *label, CGFloat scale, CGFloat *left, CGFloat *right, CGFloat *height) {
    NSSize canvas = NSMakeSize(ceil(1100.0 * scale), ceil(200.0 * scale));
    NSImage *image = [[NSImage alloc] initWithSize:canvas];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, canvas.width, canvas.height));
    [label drawAtScale:scale unflippedHeight:canvas.height decorationsOnly:NO];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0.0, 0.0, canvas.width, canvas.height)];
    [image unlockFocus];
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
            STMeasureGaps(label, scale, &left, &right, NULL);
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
            STMeasureGaps(label, zoom.doubleValue, &left, &right, NULL);
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
    STMeasureGaps(label, 1.0, &left, &right, &full);
    XCTAssertGreaterThan(full, label.lineHeight * 3.0, @"The label should wrap for this test");
    for (NSNumber *zoom in @[ @0.947, @0.75, @0.5, @1.1, @1.5, @2.0 ]) {
        CGFloat height = 0.0;
        STMeasureGaps(label, zoom.doubleValue, &left, &right, &height);
        XCTAssertEqualWithAccuracy(height, full * zoom.doubleValue, label.lineHeight * zoom.doubleValue * 0.5, @"at %@", zoom);
    }
}

/// The ends of the pill as drawn at `scale`, in image points.
static void STPillEnds(MarkupText *label, CGFloat scale, CGFloat *minX, CGFloat *maxX) {
    NSSize canvas = NSMakeSize(ceil(1100.0 * scale), ceil(200.0 * scale));
    NSImage *image = [[NSImage alloc] initWithSize:canvas];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, canvas.width, canvas.height));
    [label drawAtScale:scale unflippedHeight:canvas.height decorationsOnly:NO];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0.0, 0.0, canvas.width, canvas.height)];
    [image unlockFocus];
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
        STPillEnds(label, zoom.doubleValue, &minX, &maxX);
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
        STPillEnds(label, zoom.doubleValue, &newMin, &newMax);
        XCTAssertFalse([label containsPoint:NSMakePoint(newMax + 8.0, NSMidY(label.decoratedBounds))], @"at %@", zoom);
        canvas.zoomScale = 1.0;
    }
}

@end
