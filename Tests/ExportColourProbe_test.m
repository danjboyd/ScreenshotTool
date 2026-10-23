/*
 * ExportColourProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * What Copy, Save and Share write keeps the image's pixels and its colour space (#229), and Save As
 * writes the format its name asks for, JPEG included (#277).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (ExportColourTesting)
- (void)setupWindowAndContent;
- (ScreenshotCanvasView *)canvasView;
- (NSData *)pngDataForImage:(NSImage *)image;
- (NSData *)imageDataForImage:(NSImage *)image path:(NSString *)path;
@end

@interface ScreenshotCanvasView (ExportColourTesting)
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
@end

@interface ExportColourProbeTests : XCTestCase {
    AppDelegate *_appDelegate;
}
@end

@implementation ExportColourProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    @try {
        [NSApplication sharedApplication];
        _appDelegate = [[AppDelegate alloc] init];
        [_appDelegate setupWindowAndContent];
    } @catch (NSException *exception) {
        _appDelegate = nil;
    }
}

#if !defined(GNUSTEP)
/// A 60x40 PNG in `space`, read back as an opened file is: red, green, blue and a grey stripe,
/// with non-premultiplied alpha, which Core Graphics can't draw into.
- (NSImage *)openedPNGInColorSpace:(NSColorSpace *)space {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:60 pixelsHigh:40
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace
                                                                   bytesPerRow:60 * 4 bitsPerPixel:32];
    unsigned char *data = rep.bitmapData;
    for (NSInteger y = 0; y < 40; y++) {
        for (NSInteger x = 0; x < 60; x++) {
            unsigned char *pixel = data + y * 60 * 4 + x * 4;
            NSInteger stripe = x / 15;
            pixel[0] = stripe == 0 ? 255 : (stripe == 3 ? 128 : 0);
            pixel[1] = stripe == 1 ? 255 : (stripe == 3 ? 128 : 0);
            pixel[2] = stripe == 2 ? 255 : (stripe == 3 ? 128 : 0);
            pixel[3] = 255;
        }
    }
    rep = [rep bitmapImageRepByRetaggingWithColorSpace:space];
    NSData *png = [rep representationUsingType:NSPNGFileType properties:@{}];
    return [[NSImage alloc] initWithData:png];
}

- (NSBitmapImageRep *)bitmapOf:(NSImage *)image {
    for (NSImageRep *rep in image.representations) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            return (NSBitmapImageRep *)rep;
        }
    }
    return nil;
}

- (void)assertExportKeepsPixelsInColorSpace:(NSColorSpace *)space {
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSImage *opened = [self openedPNGInColorSpace:space];
    [canvas loadImage:opened];
    NSBitmapImageRep *source = [self bitmapOf:opened];

    NSBitmapImageRep *exported = [NSBitmapImageRep imageRepWithData:[_appDelegate pngDataForImage:[canvas flattenedImageForSelection]]];
    XCTAssertEqualObjects(exported.colorSpace.localizedName, source.colorSpace.localizedName, @"Tagged as the file was");
    NSInteger worst = 0;
    for (NSInteger y = 0; y < 40; y++) {
        for (NSInteger x = 0; x < 60; x++) {
            NSUInteger before[5] = {0};
            NSUInteger after[5] = {0};
            [source getPixel:before atX:x y:y];
            [exported getPixel:after atX:x y:y];
            for (NSInteger channel = 0; channel < 3; channel++) {
                worst = MAX(worst, labs((long)before[channel] - (long)after[channel]));
            }
        }
    }
    XCTAssertEqual(worst, 0, @"With nothing drawn, every pixel is the file's (%@)", space.localizedName);

    canvas.selectionRect = NSMakeRect(5.0, 5.0, 20.0, 10.0);
    canvas.hasSelectionRect = YES;
    NSBitmapImageRep *selection = [NSBitmapImageRep imageRepWithData:[_appDelegate pngDataForImage:[canvas flattenedImageForSelection]]];
    XCTAssertEqual(selection.pixelsWide, 20);
    XCTAssertEqualObjects(selection.colorSpace.localizedName, source.colorSpace.localizedName, @"The selection too");
    NSUInteger red[5] = {0};
    [selection getPixel:red atX:2 y:2];
    XCTAssertTrue(red[0] == 255 && red[1] == 0 && red[2] == 0, @"Red stays 255,0,0, not %lu,%lu,%lu", red[0], red[1], red[2]);
}
#endif

- (void)testAnSRGBImageExportsUnchanged {
#if defined(GNUSTEP)
    XCTSkipIf(YES, @"GNUstep doesn't colour-match");
#else
    XCTSkipIf(_appDelegate == nil, @"No window server");
    [self assertExportKeepsPixelsInColorSpace:[NSColorSpace sRGBColorSpace]];
#endif
}

- (void)testADisplayP3ImageExportsUnchanged {
#if defined(GNUSTEP)
    XCTSkipIf(YES, @"GNUstep doesn't colour-match");
#else
    XCTSkipIf(_appDelegate == nil, @"No window server");
    [self assertExportKeepsPixelsInColorSpace:[NSColorSpace displayP3ColorSpace]];
#endif
}

/// A 40x30 image: transparent on the left, red on the right, as a bitmap the way the canvas
/// flattens one.
- (NSImage *)halfTransparentImage {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:30
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:40 * 4 bitsPerPixel:32];
    unsigned char *data = rep.bitmapData;
    for (NSInteger y = 0; y < 30; y++) {
        for (NSInteger x = 0; x < 40; x++) {
            unsigned char *pixel = data + y * 40 * 4 + x * 4;
            BOOL red = x >= 20;
            pixel[0] = red ? 255 : 0;
            pixel[1] = 0;
            pixel[2] = 0;
            pixel[3] = red ? 255 : 0;
        }
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(40.0, 30.0)];
    [image addRepresentation:rep];
    return image;
}

/// Save As to a .jpg writes JPEG, opaque, on white where the image was transparent (#277).
- (void)testSaveAsJPEGIsOpaqueOnWhite {
    XCTSkipIf(_appDelegate == nil, @"No window server");
    for (NSString *path in @[@"/tmp/Screenshot.jpg", @"/tmp/Screenshot.JPEG"]) {
        NSData *data = [_appDelegate imageDataForImage:[self halfTransparentImage] path:path];
        XCTAssertGreaterThan(data.length, (NSUInteger)2, @"%@", path);
        const unsigned char *bytes = data.bytes;
        XCTAssertTrue(data.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8, @"%@ is JPEG", path);

        NSBitmapImageRep *read = [NSBitmapImageRep imageRepWithData:data];
        XCTAssertEqual(read.pixelsWide, 40);
        XCTAssertEqual(read.pixelsHigh, 30);
        XCTAssertFalse(read.hasAlpha, @"JPEG has no alpha");
        XCTAssertEqual(read.samplesPerPixel, 3);
        NSUInteger left[5] = {0};
        NSUInteger right[5] = {0};
        [read getPixel:left atX:5 y:15];
        [read getPixel:right atX:35 y:15];
        XCTAssertTrue(left[0] > 240 && left[1] > 240 && left[2] > 240,
                      @"transparent is white, not %lu,%lu,%lu", left[0], left[1], left[2]);
        XCTAssertTrue(right[0] > 240 && right[1] < 30 && right[2] < 30,
                      @"red stays red, not %lu,%lu,%lu", right[0], right[1], right[2]);
    }
}

/// .png, a name with no extension and .tif keep their formats.
- (void)testSaveAsOtherFormats {
    XCTSkipIf(_appDelegate == nil, @"No window server");
    NSImage *image = [self halfTransparentImage];
    const unsigned char png[4] = {0x89, 'P', 'N', 'G'};
    for (NSString *path in @[@"/tmp/Screenshot.png", @"/tmp/Screenshot"]) {
        NSData *data = [_appDelegate imageDataForImage:image path:path];
        XCTAssertTrue(data.length > 4 && memcmp(data.bytes, png, 4) == 0, @"%@ is PNG", path);
    }
    NSData *tiff = [_appDelegate imageDataForImage:image path:@"/tmp/Screenshot.tif"];
    const unsigned char *bytes = tiff.bytes;
    XCTAssertTrue(tiff.length > 2 && ((bytes[0] == 'I' && bytes[1] == 'I') || (bytes[0] == 'M' && bytes[1] == 'M')), @"TIFF");
}

@end
