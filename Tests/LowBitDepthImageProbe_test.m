/*
 * LowBitDepthImageProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Copy, export and crop work on images that aren't 8-bit RGB(A): 1-bit, 8-bit and 16-bit
 * grayscale, gray with alpha, 16-bit RGB and planar RGB (#46). The 1-bit case used to overflow
 * the heap when the image was copied.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (LowBitDepthTesting)
- (void)setupWindowAndContent;
- (ScreenshotCanvasView *)canvasView;
@end

@interface ScreenshotCanvasView (LowBitDepthTesting)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
@end

static const NSInteger STTestWidth = 40;
static const NSInteger STTestHeight = 20;

@interface LowBitDepthImageProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation LowBitDepthImageProbeTests

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

#pragma mark - Helpers

/// A 40x20 image: the left half dark, the right half light, in the given layout.
- (NSImage *)imageWithBitsPerSample:(NSInteger)bitsPerSample
                       colorSpace:(NSString *)colorSpace
                         hasAlpha:(BOOL)hasAlpha
                         isPlanar:(BOOL)isPlanar {
    BOOL isRGB = [colorSpace isEqualToString:NSDeviceRGBColorSpace] || [colorSpace isEqualToString:NSCalibratedRGBColorSpace];
    NSInteger colorSamples = isRGB ? 3 : 1;
    NSInteger samples = colorSamples + (hasAlpha ? 1 : 0);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:STTestWidth
                                                                    pixelsHigh:STTestHeight
                                                                 bitsPerSample:bitsPerSample
                                                               samplesPerPixel:samples
                                                                      hasAlpha:hasAlpha
                                                                      isPlanar:isPlanar
                                                                colorSpaceName:colorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    XCTAssertNotNil(rep);
    NSUInteger maxValue = (1u << bitsPerSample) - 1u;
    BOOL inverted = [colorSpace isEqualToString:NSDeviceBlackColorSpace];
    for (NSInteger y = 0; y < STTestHeight; y++) {
        for (NSInteger x = 0; x < STTestWidth; x++) {
            BOOL light = x >= STTestWidth / 2;
            NSUInteger level = (light != inverted) ? maxValue : 0;
            NSUInteger pixel[4] = { level, level, level, level };
            if (hasAlpha) {
                pixel[colorSamples] = maxValue;
            }
            [rep setPixel:pixel atX:x y:y];
        }
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(STTestWidth, STTestHeight)];
    [image addRepresentation:rep];
    return image;
}

- (ScreenshotCanvasView *)canvasWithImage:(NSImage *)image {
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:image];
    // A red stroke across the middle row, spanning both halves.
    MarkupStroke *stroke = [[MarkupStroke alloc] initWithType:MarkupStrokeTypePen color:[NSColor redColor] lineWidth:4.0];
    [stroke addPoint:NSMakePoint(4.0, 10.0)];
    [stroke addPoint:NSMakePoint(36.0, 10.0)];
    canvas.strokes = [@[stroke] mutableCopy];
    return canvas;
}

- (NSColor *)colorInImage:(NSImage *)image atX:(NSInteger)x y:(NSInteger)y {
    NSBitmapImageRep *rep = nil;
    for (NSImageRep *candidate in image.representations) {
        if ([candidate isKindOfClass:[NSBitmapImageRep class]]) {
            rep = (NSBitmapImageRep *)candidate;
            break;
        }
    }
    XCTAssertNotNil(rep);
    return [[rep colorAtX:x y:y] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
}

- (void)assertExportOf:(NSImage *)source named:(NSString *)name {
    ScreenshotCanvasView *canvas = [self canvasWithImage:source];
    NSImage *flattened = [canvas flattenedImage];
    XCTAssertNotNil(flattened, @"%@: flattening should succeed", name);
    if (!flattened) {
        return;
    }
    NSColor *dark = [self colorInImage:flattened atX:2 y:2];
    NSColor *light = [self colorInImage:flattened atX:STTestWidth - 3 y:2];
    NSColor *stroke = [self colorInImage:flattened atX:STTestWidth / 2 y:10];
    XCTAssertLessThan(dark.redComponent + dark.greenComponent + dark.blueComponent, 0.3, @"%@: the dark half stays dark (%@)", name, dark);
    XCTAssertGreaterThan(light.redComponent + light.greenComponent + light.blueComponent, 2.7, @"%@: the light half stays light (%@)", name, light);
    XCTAssertGreaterThan(stroke.redComponent, 0.8, @"%@: the stroke is exported (%@)", name, stroke);
    XCTAssertLessThan(stroke.greenComponent, 0.3, @"%@: the stroke is red (%@)", name, stroke);

    // Crop to the right half: the crop keeps the light pixels and the stroke.
    canvas.hasSelectionRect = YES;
    canvas.selectionRect = NSMakeRect(STTestWidth / 2, 0.0, STTestWidth / 2, STTestHeight);
    XCTAssertTrue([canvas cropToActiveSelection], @"%@: crop should succeed", name);
    XCTAssertEqualWithAccuracy(canvas.image.size.width, (CGFloat)(STTestWidth / 2), 0.5, @"%@", name);
    NSImage *cropped = [canvas flattenedImage];
    NSColor *croppedLight = [self colorInImage:cropped atX:STTestWidth / 2 - 3 y:2];
    XCTAssertGreaterThan(croppedLight.redComponent + croppedLight.greenComponent + croppedLight.blueComponent, 2.7,
                         @"%@: the cropped image keeps its pixels (%@)", name, croppedLight);
}

#pragma mark - Tests

- (void)testOneBitGrayscale {
    if (_shouldSkip) { return; }
    [self assertExportOf:[self imageWithBitsPerSample:1 colorSpace:NSDeviceWhiteColorSpace hasAlpha:NO isPlanar:NO] named:@"1-bit gray"];
}

- (void)testFourBitGrayscale {
    if (_shouldSkip) { return; }
    [self assertExportOf:[self imageWithBitsPerSample:4 colorSpace:NSCalibratedWhiteColorSpace hasAlpha:NO isPlanar:NO] named:@"4-bit gray"];
}

- (void)testEightBitGrayscaleWithAndWithoutAlpha {
    if (_shouldSkip) { return; }
    [self assertExportOf:[self imageWithBitsPerSample:8 colorSpace:NSCalibratedWhiteColorSpace hasAlpha:NO isPlanar:NO] named:@"8-bit gray"];
    [self assertExportOf:[self imageWithBitsPerSample:8 colorSpace:NSCalibratedWhiteColorSpace hasAlpha:YES isPlanar:NO] named:@"8-bit gray+alpha"];
}

- (void)testSixteenBitRGBAndGray {
    if (_shouldSkip) { return; }
    [self assertExportOf:[self imageWithBitsPerSample:16 colorSpace:NSDeviceRGBColorSpace hasAlpha:YES isPlanar:NO] named:@"16-bit RGBA"];
    [self assertExportOf:[self imageWithBitsPerSample:16 colorSpace:NSCalibratedWhiteColorSpace hasAlpha:NO isPlanar:NO] named:@"16-bit gray"];
}

- (void)testPlanarRGB {
    if (_shouldSkip) { return; }
    [self assertExportOf:[self imageWithBitsPerSample:8 colorSpace:NSDeviceRGBColorSpace hasAlpha:NO isPlanar:YES] named:@"planar RGB"];
}

- (void)testOrdinaryRGBAStillWorks {
    if (_shouldSkip) { return; }
    [self assertExportOf:[self imageWithBitsPerSample:8 colorSpace:NSDeviceRGBColorSpace hasAlpha:YES isPlanar:NO] named:@"8-bit RGBA"];
}

@end
