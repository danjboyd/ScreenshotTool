/*
 * LargeImageDrawingProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

@interface LargeImageDrawingProbeTests : XCTestCase
@end

@implementation LargeImageDrawingProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

/// A 480x320-pixel bitmap that, like a 96-dpi PNG, says it is 360x240 points.
- (NSImage *)ninetySixDpiImage {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:480
                                                                    pixelsHigh:320
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    [rep setSize:NSMakeSize(360.0, 240.0)];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(480.0, 320.0)];
    [image addRepresentation:rep];
    return image;
}

- (void)testCanvasDrawsItsImageUncachedAtPixelSize {
#if defined(GNUSTEP)
    [NSApplication sharedApplication];
    ScreenshotCanvasView *canvas = [[ScreenshotCanvasView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 200.0)];
    NSImage *image = [self ninetySixDpiImage];
    [canvas loadImage:image];

    // An image-sized cache window can't be bigger than the screen on Windows, so a screenshot
    // larger than the screen drew with misplaced patches.
    XCTAssertEqual(canvas.image.cacheMode, NSImageCacheNever, @"The canvas image draws from its bitmap, not a cache window");
    // Uncached, a bitmap smaller in points than the image is resampled; at pixel size it copies 1:1.
    NSImageRep *rep = canvas.image.representations.firstObject;
    XCTAssertEqualWithAccuracy(rep.size.width, 480.0, 0.001, @"The bitmap is sized in pixels");
    XCTAssertEqualWithAccuracy(rep.size.height, 320.0, 0.001, @"The bitmap is sized in pixels");
#endif
}

@end
