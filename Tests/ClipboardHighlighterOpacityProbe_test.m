/*
 * ClipboardHighlighterOpacityProbe_test.m
 * Copyright (C) 2025 Daniel Boyd
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "TestEnvironmentHelpers.h"

// Expose the strokes property for testing purposes
@interface ScreenshotCanvasView (ClipboardOpacityProbe)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@end


@interface ClipboardHighlighterOpacityProbeTests : XCTestCase {
    BOOL _shouldSkip;
}
@end

@implementation ClipboardHighlighterOpacityProbeTests

// This logic is called before any tests run
+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    // Ensure we can connect to a window server, otherwise skip.
    @try {
        [NSApplication sharedApplication];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

#pragma mark - Helpers

- (NSImage *)createBaseImage:(NSSize)size fillColor:(NSColor *)fillColor {
    XCTAssertTrue(size.width > 0.0 && size.height > 0.0, @"Image size must be positive");
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[fillColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: fillColor ?: [NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    [image unlockFocus];
    return image;
}

- (MarkupStroke *)createHighlighterStroke:(NSColor *)color width:(CGFloat)width bounds:(NSRect)bounds {
    MarkupStroke *stroke = [[MarkupStroke alloc] initWithType:MarkupStrokeTypeHighlighter
                                                        color:color
                                                     lineWidth:width];
    CGFloat y = NSMidY(bounds);
    CGFloat inset = bounds.size.width * 0.1;
    [stroke addPoint:NSMakePoint(inset, y)];
    [stroke addPoint:NSMakePoint(bounds.size.width - inset, y)];
    return stroke;
}

- (NSColor *)samplePixelFromImage:(NSImage *)image atPoint:(NSPoint)point {
    XCTAssertNotNil(image, @"Image cannot be nil");
    NSData *tiff = [image TIFFRepresentation];
    XCTAssertNotNil(tiff, @"Failed to get TIFF representation from image");
    
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiff];
    XCTAssertNotNil(bitmap, @"Failed to create bitmap from TIFF data");

    NSInteger x = (NSInteger)lrint(point.x);
    NSInteger y = (NSInteger)lrint(point.y);

    XCTAssertTrue(x >= 0 && y >= 0 && x < bitmap.pixelsWide && y < bitmap.pixelsHigh, @"Sample point is out of bounds");
    
    return [bitmap colorAtX:x y:y];
}

- (NSColor *)compositeExpectedColor:(NSColor *)base
                             overlay:(NSColor *)overlay
                        overlayAlpha:(CGFloat)overlayAlpha
                           passCount:(NSUInteger)passCount {
    XCTAssertNotNil(base, @"Base color cannot be nil");
    XCTAssertNotNil(overlay, @"Overlay color cannot be nil");

    NSColorSpace *deviceSpace = [NSColorSpace deviceRGBColorSpace];
    NSColor *baseDevice = [base colorUsingColorSpace:deviceSpace] ?: base;
    NSColor *overlayDevice = [overlay colorUsingColorSpace:deviceSpace] ?: overlay;

    double remainFactor = pow(1.0 - overlayAlpha, (double)passCount);
    double blendFactor = 1.0 - remainFactor;

    double expectedR = baseDevice.redComponent * remainFactor + overlayDevice.redComponent * blendFactor;
    double expectedG = baseDevice.greenComponent * remainFactor + overlayDevice.greenComponent * blendFactor;
    double expectedB = baseDevice.blueComponent * remainFactor + overlayDevice.blueComponent * blendFactor;

    return [NSColor colorWithDeviceRed:(CGFloat)expectedR
                                 green:(CGFloat)expectedG
                                  blue:(CGFloat)expectedB
                                 alpha:1.0f];
}

#pragma mark - Test

- (void)testHighlighterOpacityBlending {
    if (_shouldSkip) {
        return;
    }
    NSRect frame = NSMakeRect(0.0, 0.0, 640.0, 480.0);
    ScreenshotCanvasView *canvas = [[ScreenshotCanvasView alloc] initWithFrame:frame];
    XCTAssertNotNil(canvas, @"Failed to allocate canvas view");

    NSColor *baseColor = [NSColor colorWithCalibratedRed:0.25f green:0.25f blue:0.25f alpha:1.0f];
    NSImage *baseImage = [self createBaseImage:frame.size fillColor:baseColor];
    XCTAssertNotNil(baseImage, @"Failed to construct base image");
    [canvas loadImage:baseImage];

    if (!canvas.strokes) {
        canvas.strokes = [[NSMutableArray alloc] init];
    }

    NSColor *highlighter = [NSColor colorWithCalibratedRed:0.99f green:0.94f blue:0.30f alpha:1.0f];

    const NSUInteger passCount = 5;
    for (NSUInteger pass = 0; pass < passCount; ++pass) {
        MarkupStroke *stroke = [self createHighlighterStroke:highlighter width:32.0f bounds:frame];
        XCTAssertNotNil(stroke, @"Failed to construct highlighter stroke");
        [canvas.strokes addObject:stroke];
    }

    NSImage *flattened = [canvas flattenedImageForSelection];
    XCTAssertNotNil(flattened, @"Canvas failed to flatten image");

    NSPoint samplePoint = NSMakePoint(NSMidX(frame), NSMidY(frame));
    NSColor *sampled = [self samplePixelFromImage:flattened atPoint:samplePoint];
    XCTAssertNotNil(sampled, @"Failed to sample flattened output");

    CGFloat overlayAlpha = 0.35f; // This is the value being tested
    NSColor *expected = [self compositeExpectedColor:baseColor overlay:highlighter overlayAlpha:overlayAlpha passCount:passCount];
    XCTAssertNotNil(expected, @"Failed to compute expected colour");

    NSColorSpace *deviceSpace = [NSColorSpace deviceRGBColorSpace];
    NSColor *sampledDevice = [sampled colorUsingColorSpace:deviceSpace] ?: sampled;
    NSColor *expectedDevice = [expected colorUsingColorSpace:deviceSpace] ?: expected;

    CGFloat tolerance = 0.05f;
    XCTAssertEqualWithAccuracy(sampledDevice.redComponent, expectedDevice.redComponent, tolerance, @"Red component mismatch");
    XCTAssertEqualWithAccuracy(sampledDevice.greenComponent, expectedDevice.greenComponent, tolerance, @"Green component mismatch");
    XCTAssertEqualWithAccuracy(sampledDevice.blueComponent, expectedDevice.blueComponent, tolerance, @"Blue component mismatch");
}

@end
