/*
 * ExportColourProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * What Copy, Save and Share write keeps the image's pixels and its colour space (#229).
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

@end
