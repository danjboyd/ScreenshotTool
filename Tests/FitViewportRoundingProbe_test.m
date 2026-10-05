/*
 * FitViewportRoundingProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Fit never makes the canvas a fraction of a point larger than the viewport. Rounding a 577.5pt
 * viewport up to a 578pt canvas set GNUstep's auto-hiding scrollers flipping on and off until the
 * stack overflowed (#49).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (FitViewportRoundingTesting)
- (void)setupWindowAndContent;
- (NSScrollView *)scrollView;
- (ScreenshotCanvasView *)canvasView;
@end

@interface FitViewportRoundingProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation FitViewportRoundingProbeTests

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

/// An image the size of a 12 MP phone photo, without allocating one: a small bitmap stretched.
- (NSImage *)photoSizedImage:(NSSize)size {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:16
                                                                    pixelsHigh:16
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    [rep setSize:size];
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image addRepresentation:rep];
    return image;
}

- (void)testFitStaysWithinFractionalViewports {
    if (_shouldSkip) { return; }
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSScrollView *scrollView = _appDelegate.scrollView;
    NSArray<NSImage *> *images = @[[self photoSizedImage:NSMakeSize(3024.0, 4032.0)],
                                   [self photoSizedImage:NSMakeSize(4032.0, 3024.0)],
                                   [self photoSizedImage:NSMakeSize(1217.0, 1284.0)]];
    for (NSImage *image in images) {
        [canvas loadImage:image];
        canvas.fitToWindow = YES;
        for (CGFloat width = 560.0; width <= 600.0; width += 0.5) {
            for (CGFloat height = 340.0; height <= 1000.0; height += 37.25) {
                [scrollView setFrame:NSMakeRect(0.0, 24.0, width, height)];
                [canvas updateForEnclosingBoundsChange];
                NSSize viewport = [NSScrollView contentSizeForFrameSize:scrollView.frame.size
                                                  hasHorizontalScroller:NO
                                                    hasVerticalScroller:NO
                                                             borderType:scrollView.borderType];
                NSSize canvasSize = canvas.frame.size;
                XCTAssertLessThanOrEqual(canvasSize.width, floor(viewport.width),
                                         @"%@ in %.2fx%.2f: canvas %@", NSStringFromSize(image.size), width, height, NSStringFromSize(canvasSize));
                XCTAssertLessThanOrEqual(canvasSize.height, floor(viewport.height),
                                         @"%@ in %.2fx%.2f: canvas %@", NSStringFromSize(image.size), width, height, NSStringFromSize(canvasSize));
                // ...while still filling it, to within the point that rounding can cost.
                BOOL fillsWidth = canvasSize.width >= floor(viewport.width) - 1.0;
                BOOL fillsHeight = canvasSize.height >= floor(viewport.height) - 1.0;
                XCTAssertTrue(fillsWidth || fillsHeight, @"%@ in %.2fx%.2f: canvas %@ should fill one side",
                              NSStringFromSize(image.size), width, height, NSStringFromSize(canvasSize));
            }
        }
    }
}

- (void)testFitDoesNotEnlargeSmallImages {
    if (_shouldSkip) { return; }
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self photoSizedImage:NSMakeSize(300.0, 200.0)]];
    canvas.fitToWindow = YES;
    [_appDelegate.scrollView setFrame:NSMakeRect(0.0, 24.0, 577.5, 401.5)];
    [canvas updateForEnclosingBoundsChange];
    XCTAssertEqualWithAccuracy(canvas.frame.size.width, 300.0, 0.01);
    XCTAssertEqualWithAccuracy(canvas.frame.size.height, 200.0, 0.01);
}

- (void)testFitTurnsOffAutohidingScrollers {
    if (_shouldSkip) { return; }
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSScrollView *scrollView = _appDelegate.scrollView;
    [canvas loadImage:[self photoSizedImage:NSMakeSize(3024.0, 4032.0)]];
    canvas.fitToWindow = YES;
    XCTAssertFalse(scrollView.autohidesScrollers, @"Fit fits by construction: nothing for scrollers to do");
    XCTAssertFalse(scrollView.hasVerticalScroller);
    XCTAssertFalse(scrollView.hasHorizontalScroller);

    // A fixed zoom that overflows gets its scrollers back.
    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;
    XCTAssertTrue(scrollView.autohidesScrollers);
    [scrollView reflectScrolledClipView:scrollView.contentView];
    XCTAssertTrue(scrollView.hasVerticalScroller || scrollView.hasHorizontalScroller, @"a 3024x4032 image at 100%% overflows");

    canvas.fitToWindow = YES;
    XCTAssertFalse(scrollView.autohidesScrollers);
    XCTAssertFalse(scrollView.hasVerticalScroller);
    XCTAssertFalse(scrollView.hasHorizontalScroller);
}

- (void)testFitSurvivesTheScrollerFlipFromTheCrash {
    if (_shouldSkip) { return; }
    // The sizes logged just before the crash: a 576x757 viewport, the canvas 568x757, and the
    // clip toggling between 576x757 and 562x743 as both scrollers came and went.
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSScrollView *scrollView = _appDelegate.scrollView;
    [canvas loadImage:[self photoSizedImage:NSMakeSize(3024.0, 4032.0)]];
    canvas.fitToWindow = YES;
    [scrollView setFrame:NSMakeRect(0.0, 24.0, 576.0, 757.0)];
    [canvas updateForEnclosingBoundsChange];
    for (NSInteger round = 0; round < 50; round++) {
        [scrollView setFrame:NSMakeRect(0.0, 24.0, (round % 2) ? 562.0 : 576.0, (round % 2) ? 743.0 : 757.0)];
        [scrollView tile];
        [scrollView reflectScrolledClipView:scrollView.contentView];
        XCTAssertFalse(scrollView.hasVerticalScroller || scrollView.hasHorizontalScroller, @"round %ld", (long)round);
    }
}

@end
