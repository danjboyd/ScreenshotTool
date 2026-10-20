/*
 * FitToWindowProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (FitToWindowTesting)
- (void)setupWindowAndContent;
- (void)layoutContentSubviews;
- (NSWindow *)window;
- (NSScrollView *)scrollView;
- (ScreenshotCanvasView *)canvasView;
- (void)resizeWindowToImageSize:(NSSize)size;
- (CGFloat)statusBarHeight;
- (void)zoomIn:(id)sender;
- (void)zoomOut:(id)sender;
- (CGFloat)nextZoomScaleBelow:(CGFloat)scale;
@end

@interface FitToWindowProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation FitToWindowProbeTests

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

- (NSImage *)imageOfSize:(NSSize)size {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    [image unlockFocus];
    return image;
}

- (void)setViewportSize:(NSSize)size {
    [_appDelegate.window setContentSize:size];
    [_appDelegate layoutContentSubviews];
    [_appDelegate.canvasView updateForEnclosingBoundsChange];
}

- (void)testFitNeverUpscalesSmallImages {
    XCTSkipIf(_shouldSkip, @"No window server");

    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self imageOfSize:NSMakeSize(300.0, 200.0)]];
    [self setViewportSize:NSMakeSize(1000.0, 800.0)];

    XCTAssertTrue(canvas.isFitToWindow, @"Loading an image should select Fit to Window");
    XCTAssertEqualWithAccuracy(canvas.zoomScale, 1.0, 0.0001, @"Fit should show a small image at 100%%, not enlarge it");
}

/// Zoom out from Fit goes to the step below the scale Fit shows. It went to a fixed 50%, so with
/// Fit at about 33% the first press zoomed in (#307).
- (void)testZoomOutFromAFitBelowHalfGoesLower {
    XCTSkipIf(_shouldSkip, @"No window server");

    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self imageOfSize:NSMakeSize(2580.0, 1560.0)]];
    [self setViewportSize:NSMakeSize(860.0, 600.0)];
    XCTAssertTrue(canvas.isFitToWindow);
    CGFloat fit = canvas.displayZoomScale;
    XCTAssertLessThan(fit, 0.5, @"the viewport makes Fit smaller than 50%%");

    [_appDelegate zoomOut:nil];
    XCTAssertFalse(canvas.isFitToWindow);
    XCTAssertLessThan(canvas.displayZoomScale, fit - 0.0001, @"zoom out from Fit at %.3f goes lower", fit);
    XCTAssertEqualWithAccuracy(canvas.displayZoomScale, [_appDelegate nextZoomScaleBelow:fit], 0.0001);
}

/// With Fit between 50% and 100%, zoom out goes to the step just below it, which is 50%, as before.
- (void)testZoomOutFromAFitAboveHalfGoesToTheNextStepDown {
    XCTSkipIf(_shouldSkip, @"No window server");

    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self imageOfSize:NSMakeSize(1000.0, 700.0)]];
    [self setViewportSize:NSMakeSize(860.0, 600.0)];
    XCTAssertTrue(canvas.isFitToWindow);
    CGFloat fit = canvas.displayZoomScale;
    XCTAssertGreaterThan(fit, 0.5, @"the viewport makes Fit larger than 50%%");

    [_appDelegate zoomOut:nil];
    XCTAssertEqualWithAccuracy(canvas.displayZoomScale, [_appDelegate nextZoomScaleBelow:fit], 0.0001,
                               @"zoom out from Fit at %.3f", fit);
    XCTAssertEqualWithAccuracy(canvas.displayZoomScale, 0.5, 0.0001, @"50%% is the step below Fit at %.3f", fit);
}

/// Zoom in from Fit still goes to 100%.
- (void)testZoomInFromFitGoesToActualSize {
    XCTSkipIf(_shouldSkip, @"No window server");

    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self imageOfSize:NSMakeSize(2580.0, 1560.0)]];
    [self setViewportSize:NSMakeSize(860.0, 600.0)];
    XCTAssertTrue(canvas.isFitToWindow);

    [_appDelegate zoomIn:nil];
    XCTAssertFalse(canvas.isFitToWindow);
    XCTAssertEqualWithAccuracy(canvas.displayZoomScale, 1.0, 0.0001);
}

- (void)testFitIgnoresScrollersLeftOverFromAPreviousZoom {
    XCTSkipIf(_shouldSkip, @"No window server");

    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self imageOfSize:NSMakeSize(800.0, 400.0)]];
    [self setViewportSize:NSMakeSize(800.0, 400.0 + [_appDelegate.window.contentView frame].size.height - _appDelegate.scrollView.frame.size.height)];

    // Overflow the viewport so autohiding scrollers appear, then return to Fit.
    canvas.fitToWindow = NO;
    canvas.zoomScale = 2.0;
    [_appDelegate.scrollView tile];
    canvas.fitToWindow = YES;
    [canvas updateForEnclosingBoundsChange];

    // The whole viewport, less a border the theme draws round the clip view and the stage's
    // margin round the image.
    NSSize viewport = _appDelegate.scrollView.frame.size;
    CGFloat border = NSMinX(_appDelegate.scrollView.contentView.frame);
    border = (border > 0.0 && border < 8.0) ? border : 0.0;
    viewport.width -= 2.0 * (STCanvasStageMargin + border);
    viewport.height -= 2.0 * (STCanvasStageMargin + border);
    CGFloat expected = MIN(1.0, MIN(viewport.width / 800.0, viewport.height / 400.0));
    XCTAssertEqualWithAccuracy(canvas.zoomScale, expected, 0.0001,
                               @"Fit should use the whole viewport, not the clip view shrunk by scrollers");
}

- (void)testSmallImageIsCentredInViewport {
    XCTSkipIf(_shouldSkip, @"No window server");

    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self imageOfSize:NSMakeSize(300.0, 200.0)]];
    [self setViewportSize:NSMakeSize(1000.0, 800.0)];

    NSClipView *clipView = _appDelegate.scrollView.contentView;
    XCTAssertTrue([clipView isKindOfClass:[STCanvasClipView class]], @"Canvas should be hosted in the centring clip view");
    [clipView scrollToPoint:[clipView constrainScrollPoint:clipView.bounds.origin]];

    NSRect canvasInClip = [clipView convertRect:canvas.bounds fromView:canvas];
    NSRect clipBounds = clipView.bounds;
    XCTAssertEqualWithAccuracy(NSMidX(canvasInClip), NSMidX(clipBounds), 1.0, @"Image should be centred horizontally");
    XCTAssertEqualWithAccuracy(NSMidY(canvasInClip), NSMidY(clipBounds), 1.0, @"Image should be centred vertically");
}

- (void)testTinyImageGetsAUsableWindow {
    XCTSkipIf(_shouldSkip, @"No window server");

    [_appDelegate.canvasView loadImage:[self imageOfSize:NSMakeSize(16.0, 16.0)]];
    [_appDelegate resizeWindowToImageSize:NSMakeSize(16.0, 16.0)];

    NSSize content = [_appDelegate.window.contentView frame].size;
    CGFloat barHeight = [_appDelegate statusBarHeight];
    XCTAssertTrue(content.width >= 640.0 - 0.5, @"A 16x16 image should still get a window wide enough for the toolbar (got %.0f)", content.width);
    XCTAssertTrue(content.height - barHeight >= 240.0 - 0.5, @"A 16x16 image should still get a usable canvas height (got %.0f)", content.height - barHeight);
    XCTAssertTrue(_appDelegate.window.contentMinSize.width >= 640.0 - 0.5, @"Manual resizing should not go below the minimum either");
    XCTAssertEqualWithAccuracy(_appDelegate.canvasView.zoomScale, 1.0, 0.0001, @"The tiny image itself stays at 100%%");
}


@end
