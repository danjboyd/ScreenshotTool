/*
 * CanvasStageProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (CanvasStageTesting)
- (void)setupWindowAndContent;
- (void)layoutContentSubviews;
- (NSWindow *)window;
- (NSScrollView *)scrollView;
- (ScreenshotCanvasView *)canvasView;
- (void)resizeWindowToImageSize:(NSSize)size;
@end

/// The stage (v0.2.0, #221): the image on a backdrop, centred with a margin, display only.
@interface CanvasStageProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation CanvasStageProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        _appDelegate = [[AppDelegate alloc] init];
        [_appDelegate setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    _appDelegate = nil;
    [super tearDown];
}

/// An image whose pixels all differ, so any change in an export shows.
- (NSImage *)patternImageOfSize:(NSSize)size {
    NSInteger width = (NSInteger)size.width;
    NSInteger height = (NSInteger)size.height;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:width
                                                                    pixelsHigh:height
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:width * 4
                                                                  bitsPerPixel:32];
    unsigned char *data = [rep bitmapData];
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            unsigned char *pixel = data + (y * width * 4) + (x * 4);
            pixel[0] = (unsigned char)((x * 7) & 0xff);
            pixel[1] = (unsigned char)((y * 5) & 0xff);
            pixel[2] = (unsigned char)(((x + y) * 3) & 0xff);
            pixel[3] = 255;
        }
    }
    [rep setSize:size];
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image addRepresentation:rep];
    return image;
}

- (void)setViewportSize:(NSSize)size {
    [_appDelegate.window setContentSize:size];
    [_appDelegate layoutContentSubviews];
    [_appDelegate.canvasView updateForEnclosingBoundsChange];
}

- (STCanvasStageView *)stage {
    id documentView = _appDelegate.scrollView.documentView;
    return [documentView isKindOfClass:[STCanvasStageView class]] ? documentView : nil;
}

- (void)testCanvasSitsOnTheStage {
    XCTSkipIf(_shouldSkip, @"No window server");

    STCanvasStageView *stage = [self stage];
    XCTAssertNotNil(stage, @"The scroll view's document view should be the stage");
    XCTAssertEqual(stage.canvasView, _appDelegate.canvasView);
    XCTAssertEqual(_appDelegate.canvasView.superview, stage);
}

- (void)testFitLeavesTheMarginAndCentresTheImage {
    XCTSkipIf(_shouldSkip, @"No window server");

    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self patternImageOfSize:NSMakeSize(2400.0, 1600.0)]];
    [self setViewportSize:NSMakeSize(900.0, 700.0)];

    STCanvasStageView *stage = [self stage];
    NSSize viewport = _appDelegate.scrollView.contentView.bounds.size;
    NSRect image = stage.imageFrame;
    XCTAssertTrue(canvas.isFitToWindow);
    XCTAssertEqualWithAccuracy(stage.frame.size.width, viewport.width, 1.0, @"Fit: the stage should fill the viewport, no more");
    XCTAssertEqualWithAccuracy(stage.frame.size.height, viewport.height, 1.0, @"Fit: the stage should fill the viewport, no more");
    XCTAssertGreaterThanOrEqual(NSMinX(image), STCanvasStageMargin);
    XCTAssertGreaterThanOrEqual(NSMinY(image), STCanvasStageMargin);
    XCTAssertGreaterThanOrEqual(NSWidth(stage.frame) - NSMaxX(image), STCanvasStageMargin);
    XCTAssertGreaterThanOrEqual(NSHeight(stage.frame) - NSMaxY(image), STCanvasStageMargin);
    XCTAssertEqualWithAccuracy(NSMinX(image), NSWidth(stage.frame) - NSMaxX(image), 1.0, @"The image should be centred across");
    XCTAssertEqualWithAccuracy(NSMinY(image), NSHeight(stage.frame) - NSMaxY(image), 1.0, @"The image should be centred down");
}

- (void)testSmallImageIsCentredOnAStageFillingTheViewport {
    XCTSkipIf(_shouldSkip, @"No window server");

    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self patternImageOfSize:NSMakeSize(200.0, 120.0)]];
    [self setViewportSize:NSMakeSize(900.0, 700.0)];

    STCanvasStageView *stage = [self stage];
    NSSize viewport = _appDelegate.scrollView.contentView.bounds.size;
    NSRect image = stage.imageFrame;
    XCTAssertEqualWithAccuracy(NSWidth(image), 200.0 * canvas.zoomScale, 1.0);
    XCTAssertEqualWithAccuracy(stage.frame.size.width, viewport.width, 1.0);
    XCTAssertEqualWithAccuracy(stage.frame.size.height, viewport.height, 1.0);
    XCTAssertEqualWithAccuracy(NSMidX(image), NSWidth(stage.frame) * 0.5, 1.0);
    XCTAssertEqualWithAccuracy(NSMidY(image), NSHeight(stage.frame) * 0.5, 1.0);
}

- (void)testZoomedInImageKeepsItsMarginWhenScrolling {
    XCTSkipIf(_shouldSkip, @"No window server");

    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self patternImageOfSize:NSMakeSize(2400.0, 1600.0)]];
    [self setViewportSize:NSMakeSize(900.0, 700.0)];
    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;

    STCanvasStageView *stage = [self stage];
    NSRect image = stage.imageFrame;
    XCTAssertEqualWithAccuracy(NSWidth(stage.frame), NSWidth(image) + (2.0 * STCanvasStageMargin), 1.0,
                               @"Past the viewport, the stage is the image plus its margin");
    XCTAssertEqualWithAccuracy(NSHeight(stage.frame), NSHeight(image) + (2.0 * STCanvasStageMargin), 1.0);
    XCTAssertEqualWithAccuracy(NSMinX(image), STCanvasStageMargin, 1.0);
    XCTAssertEqualWithAccuracy(NSMinY(image), STCanvasStageMargin, 1.0);
}

/// The window opens with room for the margin, so a screenshot that fits the screen opens at 100%.
- (void)testWindowSizedForAnImageOpensItAtActualSize {
    XCTSkipIf(_shouldSkip, @"No window server");

    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSSize size = NSMakeSize(860.0, 520.0);
    [canvas loadImage:[self patternImageOfSize:size]];
    [_appDelegate resizeWindowToImageSize:size];
    [canvas updateForEnclosingBoundsChange];

    XCTAssertTrue(canvas.isFitToWindow);
    XCTAssertEqualWithAccuracy(canvas.zoomScale, 1.0 / canvas.screenPixelsPerPoint, 0.0001,
                               @"Sized for the image and its margin, Fit should show it at actual size");
}

/// The stage is display only: the export is the image's own pixels, not the backdrop's.
- (void)testExportIsTheImageUnchanged {
    XCTSkipIf(_shouldSkip, @"No window server");

    NSSize size = NSMakeSize(64.0, 48.0);
    NSImage *source = [self patternImageOfSize:size];
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:source];
    [self setViewportSize:NSMakeSize(900.0, 700.0)];
    XCTAssertNotNil([self stage]);

    NSImage *exported = [canvas flattenedImage];
    XCTAssertNotNil(exported);
    NSBitmapImageRep *exportRep = [[NSBitmapImageRep alloc] initWithData:[exported TIFFRepresentation]];
    NSBitmapImageRep *sourceRep = [[NSBitmapImageRep alloc] initWithData:[source TIFFRepresentation]];
    XCTAssertEqual(exportRep.pixelsWide, sourceRep.pixelsWide, @"The export should be the image's size, without the margin");
    XCTAssertEqual(exportRep.pixelsHigh, sourceRep.pixelsHigh);
    NSInteger differing = 0;
    for (NSInteger y = 0; y < sourceRep.pixelsHigh; y++) {
        for (NSInteger x = 0; x < sourceRep.pixelsWide; x++) {
            NSUInteger expected[4] = {0, 0, 0, 0};
            NSUInteger actual[4] = {0, 0, 0, 0};
            [sourceRep getPixel:expected atX:x y:y];
            [exportRep getPixel:actual atX:x y:y];
            if (expected[0] != actual[0] || expected[1] != actual[1] || expected[2] != actual[2] || expected[3] != actual[3]) {
                differing++;
            }
        }
    }
    XCTAssertEqual(differing, 0, @"Every exported pixel should be the image's own");
}

@end
