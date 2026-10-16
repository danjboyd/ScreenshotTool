/*
 * CanvasDrawSpeedProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * A zoomed-out image is drawn from a copy scaled once for its zoom (GNUstep with cairo), so a
 * redraw is a 1:1 copy instead of cairo scaling, and first converting, the whole screenshot.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (CanvasDrawSpeedTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
- (void)layoutContentSubviews;
@end

@interface ScreenshotCanvasView (CanvasDrawSpeedTesting)
@property (nonatomic, strong, nullable) NSImage *scaledImageCache;
@property (nonatomic, assign) CGFloat scaledImageCacheScale;
@property (nonatomic, strong, nullable) NSBitmapImageRep *scaledImageSource;
@property (nonatomic, assign) NSTimeInterval lastZoomChange;
@end

@interface CanvasDrawSpeedProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation CanvasDrawSpeedProbeTests

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
    [_appDelegate.window orderOut:nil];
    _appDelegate = nil;
    [super tearDown];
}

/// An image of `size` pixels from a bitmap (as a PNG is read), the left half red and the right
/// half blue, with `bitsPerSample` 8 or 16 and non-premultiplied alpha, the layout PNGs get.
- (NSImage *)twoColourImageOfSize:(NSSize)size bitsPerSample:(NSInteger)bits {
    NSInteger width = (NSInteger)size.width, height = (NSInteger)size.height;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:width
                                                                    pixelsHigh:height
                                                                 bitsPerSample:bits
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace
                                                                  bitmapFormat:NSAlphaNonpremultipliedBitmapFormat
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            NSUInteger max = (bits == 16) ? 65535 : 255;
            NSUInteger pixel[4] = { x < width / 2 ? max : 0, 0, x < width / 2 ? 0 : max, max };
            [rep setPixel:pixel atX:x y:y];
        }
    }
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image addRepresentation:rep];
    return image;
}

/// The canvas showing `image` at `zoom`, drawn once.
- (ScreenshotCanvasView *)canvasShowing:(NSImage *)image atZoom:(CGFloat)zoom {
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:image];
    canvas.fitToWindow = NO;
    canvas.zoomScale = zoom;
    canvas.lastZoomChange = 0.0; // as if the zoom had long settled
    [_appDelegate layoutContentSubviews]; // the canvas in place of the empty state
    [_appDelegate.window orderFront:nil];
    [_appDelegate.window display];
    return canvas;
}

- (NSColor *)colourOf:(NSImage *)image atX:(NSInteger)x y:(NSInteger)y {
    NSBitmapImageRep *rep = (NSBitmapImageRep *)image.representations.firstObject;
    return [rep colorAtX:x y:y];
}

#if defined(GNUSTEP) && defined(ST_HAVE_CAIRO)
- (void)testAZoomedOutImageIsDrawnFromACopyScaledForTheZoom {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasShowing:[self twoColourImageOfSize:NSMakeSize(800, 400) bitsPerSample:8]
                                                atZoom:0.5];
    NSImage *cache = canvas.scaledImageCache;
    XCTAssertNotNil(cache, @"Drawn from a scaled copy");
    NSBitmapImageRep *rep = (NSBitmapImageRep *)cache.representations.firstObject;
    XCTAssertEqual(rep.pixelsWide, 400);
    XCTAssertEqual(rep.pixelsHigh, 200, @"Scaled for the zoom");
    XCTAssertEqual((NSUInteger)rep.bitmapFormat, (NSUInteger)0, @"Premultiplied, alpha last: what cairo draws as is");
    XCTAssertEqual(rep.bitsPerSample, 8);
    NSColor *left = [[self colourOf:cache atX:50 y:100] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    NSColor *right = [[self colourOf:cache atX:350 y:100] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    XCTAssertEqualWithAccuracy(left.redComponent, 1.0, 0.01);
    XCTAssertEqualWithAccuracy(left.blueComponent, 0.0, 0.01, @"The left half stays red");
    XCTAssertEqualWithAccuracy(right.blueComponent, 1.0, 0.01, @"The right half stays blue");

    [_appDelegate.window display];
    XCTAssertTrue(canvas.scaledImageCache == cache, @"Redrawn from the same copy");
}

- (void)testA16BitImageIsConvertedOnce {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasShowing:[self twoColourImageOfSize:NSMakeSize(400, 200) bitsPerSample:16]
                                                atZoom:0.5];
    XCTAssertNotNil(canvas.scaledImageCache);
    NSBitmapImageRep *source = canvas.scaledImageSource;
    XCTAssertEqual(source.bitsPerSample, 8, @"Its 8-bit copy is kept for the next zoom");
    canvas.zoomScale = 0.25;
    canvas.lastZoomChange = 0.0;
    [_appDelegate.window display];
    XCTAssertTrue(canvas.scaledImageSource == source, @"Not converted again");
    XCTAssertEqualWithAccuracy(canvas.scaledImageCacheScale, 0.25, 0.0001);
}

- (void)testWhileTheZoomChangesTheLastCopyIsStretchedUntilItSettles {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasShowing:[self twoColourImageOfSize:NSMakeSize(800, 400) bitsPerSample:8]
                                                atZoom:0.5];
    NSImage *first = canvas.scaledImageCache;

    canvas.zoomScale = 0.45; // just now, as a window being resized does
    [_appDelegate.window display];
    XCTAssertTrue(canvas.scaledImageCache == first, @"No new copy while the zoom is still changing");

    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];
    [_appDelegate.window display];
    XCTAssertTrue(canvas.scaledImageCache != first, @"A new copy once it has settled");
    XCTAssertEqualWithAccuracy(canvas.scaledImageCacheScale, 0.45, 0.0001);
}

- (void)testANewImageOrActualSizeHasNoCopy {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasShowing:[self twoColourImageOfSize:NSMakeSize(800, 400) bitsPerSample:8]
                                                atZoom:0.5];
    XCTAssertNotNil(canvas.scaledImageCache);
    [canvas loadImage:[self twoColourImageOfSize:NSMakeSize(300, 200) bitsPerSample:8]];
    XCTAssertNil(canvas.scaledImageCache, @"A new image drops the old one's copy");
    XCTAssertNil(canvas.scaledImageSource);

    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;
    [_appDelegate.window display];
    XCTAssertNil(canvas.scaledImageCache, @"At actual size the image is drawn as it is");
}
#endif

@end
