/*
 * PrintFlattenProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The macOS flatten for printing (#355): -[ScreenshotCanvasView flattenedImageForPrintAtScale:withinRect:]
 * enlarges the capture by whole-pixel blocks after its redactions are pixelated on its own pixels,
 * so a redaction leaves nothing of what it hides at any print size, and the print path embeds only
 * that image, at up to 300 dpi. Linux checks its own flatten in PrintRedactionProbe. macOS only.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if !defined(GNUSTEP)

#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "STPrintLayout.h"
#import "STPrintOptions.h"
#import "STPrintPage.h"
#import "STPrintView.h"

@interface AppDelegate (PrintFlattenProbe)
- (void)setupWindowAndContent;
- (ScreenshotCanvasView *)canvasView;
- (NSWindow *)window;
@property (nonatomic, assign) BOOL printOperationInProgress;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
@end

@interface PrintFlattenProbeTests : XCTestCase
@end

@implementation PrintFlattenProbeTests {
    AppDelegate *_appDelegate;
    BOOL _shouldSkip;
}

- (void)testPrintCommandIsDisabledWhileAJobIsRunning {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSMenuItem *print = [[NSMenuItem alloc] initWithTitle:@"Print…" action:@selector(printDocument:) keyEquivalent:@"p"];
    XCTAssertTrue([_appDelegate validateMenuItem:print]);
    _appDelegate.printOperationInProgress = YES;
    XCTAssertFalse([_appDelegate validateMenuItem:print]);
    _appDelegate.printOperationInProgress = NO;
    XCTAssertTrue([_appDelegate validateMenuItem:print]);
}

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
    _appDelegate = [[AppDelegate alloc] init];
    @try {
        [_appDelegate setupWindowAndContent];
    } @catch (NSException *exception) {
        _shouldSkip = YES;
        return;
    }
    [_appDelegate.canvasView loadImage:[self imageWithSecret]];
}

- (void)tearDown {
    [[_appDelegate window] orderOut:nil];
    _appDelegate = nil;
    [super tearDown];
}

/// The secret's pixels: a 2-pixel red and green checkerboard, so a mosaic over it averages to
/// neither (a solid colour would keep its colour under a mosaic).
static BOOL STIsSecretPixel(const unsigned char *p) {
    BOOL red = p[0] > 200 && p[1] < 60 && p[2] < 60;
    BOOL green = p[1] > 200 && p[0] < 60 && p[2] < 60;
    return red || green;
}

/// 400 × 200 white, with the secret's 100 × 50 at (50, 40) from the top left, and a blue 100 × 60
/// at (200, 100).
- (NSImage *)imageWithSecret {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:400 pixelsHigh:200
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                      isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:0];
    for (NSInteger y = 0; y < 200; y++) {
        unsigned char *row = rep.bitmapData + rep.bytesPerRow * y;
        for (NSInteger x = 0; x < 400; x++) {
            unsigned char *p = row + x * 4;
            p[0] = p[1] = p[2] = 255;
            p[3] = 255;
            if (x >= 50 && x < 150 && y >= 40 && y < 90) {
                BOOL red = ((x / 2) + (y / 2)) % 2 == 0;
                p[0] = red ? 255 : 0;
                p[1] = red ? 0 : 255;
                p[2] = 0;
            } else if (x >= 200 && x < 300 && y >= 100 && y < 160) {
                p[0] = 0;
                p[1] = 0;
                p[2] = 255;
            }
        }
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(400, 200)];
    [image addRepresentation:rep];
    return image;
}

/// The image's pixels as 8-bit RGBA, rows from the top.
- (NSBitmapImageRep *)RGBAOf:(NSImage *)image {
    NSSize pixels = STPrintImagePixelSize(image);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)pixels.width
                                                                    pixelsHigh:(NSInteger)pixels.height bitsPerSample:8
                                                               samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:(NSInteger)pixels.width * 4 bitsPerPixel:32];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext setCurrentContext:context];
    context.imageInterpolation = NSImageInterpolationNone;
    CGImageRef cg = [image CGImageForProposedRect:NULL context:nil hints:nil];
    CGContextDrawImage(context.CGContext, CGRectMake(0, 0, pixels.width, pixels.height), cg);
    [context flushGraphics];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

- (NSUInteger)secretPixelsIn:(NSBitmapImageRep *)rep {
    NSUInteger count = 0;
    for (NSInteger y = 0; y < rep.pixelsHigh; y++) {
        const unsigned char *row = rep.bitmapData + rep.bytesPerRow * y;
        for (NSInteger x = 0; x < rep.pixelsWide; x++) {
            count += STIsSecretPixel(row + x * 4) ? 1 : 0;
        }
    }
    return count;
}

- (void)redactTheSecret {
    [_appDelegate.canvasView addRedactionsInImageRects:@[ [NSValue valueWithRect:NSMakeRect(50, 40, 100, 50)] ]
                                             actionName:@"Redact"];
}

/// The control: unredacted, the secret is all there at print size, every pixel a 3 × 3 block.
- (void)testUnredactedTheSecretIsThere {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSImage *printed = [_appDelegate.canvasView flattenedImageForPrintAtScale:3 withinRect:NSZeroRect];
    XCTAssertTrue(NSEqualSizes(STPrintImagePixelSize(printed), NSMakeSize(1200, 600)));
    XCTAssertTrue(NSEqualSizes(printed.size, NSMakeSize(400, 200)), @"its points stay the capture's");
    XCTAssertEqual([self secretPixelsIn:[self RGBAOf:printed]], (NSUInteger)(5000 * 9));
}

/// A redaction holds at print size: it's pixelated on the capture's pixels before they're enlarged,
/// so each enlarged pixel is a whole block of one capture pixel, and none is the secret.
- (void)testARedactionHoldsAtPrintSize {
    XCTSkipIf(_shouldSkip, @"No window server");
    [self redactTheSecret];
    NSBitmapImageRep *one = [self RGBAOf:[_appDelegate.canvasView flattenedImageForPrintAtScale:1 withinRect:NSZeroRect]];
    NSBitmapImageRep *three = [self RGBAOf:[_appDelegate.canvasView flattenedImageForPrintAtScale:3 withinRect:NSZeroRect]];
    XCTAssertEqual([self secretPixelsIn:one], (NSUInteger)0);
    XCTAssertEqual([self secretPixelsIn:three], (NSUInteger)0);
    NSUInteger mismatched = 0;
    for (NSInteger y = 40 * 3; y < 90 * 3; y++) {
        const unsigned char *bigRow = three.bitmapData + three.bytesPerRow * y;
        const unsigned char *smallRow = one.bitmapData + one.bytesPerRow * (y / 3);
        for (NSInteger x = 50 * 3; x < 150 * 3; x++) {
            const unsigned char *big = bigRow + x * 4, *small = smallRow + (x / 3) * 4;
            if (abs(big[0] - small[0]) > 2 || abs(big[1] - small[1]) > 2 || abs(big[2] - small[2]) > 2) {
                mismatched++;
            }
        }
    }
    XCTAssertEqual(mismatched, (NSUInteger)0, @"the mosaic is enlarged by whole blocks, not redrawn");
}

/// A clip keeps only its part: its pixels at the scale, its points the clip's.
- (void)testAClipKeepsOnlyItsPart {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSImage *printed = [_appDelegate.canvasView flattenedImageForPrintAtScale:2 withinRect:NSMakeRect(200, 100, 100, 60)];
    XCTAssertTrue(NSEqualSizes(STPrintImagePixelSize(printed), NSMakeSize(200, 120)));
    XCTAssertTrue(NSEqualSizes(printed.size, NSMakeSize(100, 60)));
    NSBitmapImageRep *rep = [self RGBAOf:printed];
    NSUInteger notBlue = 0;
    for (NSInteger y = 0; y < rep.pixelsHigh; y++) {
        for (NSInteger x = 0; x < rep.pixelsWide; x++) {
            const unsigned char *p = rep.bitmapData + rep.bytesPerRow * y + x * 4;
            notBlue += (p[2] > 200 && p[0] < 60 && p[1] < 60) ? 0 : 1;
        }
    }
    XCTAssertEqual(notBlue, (NSUInteger)0, @"only the blue part");
}

/// The print path: the view gets the canvas's print flatten at the layout's scale, about 300 dpi,
/// and the layout counts its pixels at that resolution, so the page is the same size.
- (void)testThePrintPathFlattensAtTheLayoutsScale {
    XCTSkipIf(_shouldSkip, @"No window server");
    [self redactTheSecret];
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSImage *whole = [canvas flattenedImage];
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.paperSize = NSMakeSize(612, 792);
    layout.margins = STPrintMarginsMake(STPrintDefaultMargin, STPrintDefaultMargin, STPrintDefaultMargin, STPrintDefaultMargin);
    STPrintView *view = [[STPrintView alloc] initWithLayout:layout image:whole];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.fit = STPrintFitActualSize;
    __block NSUInteger askedScale = 0;
    STPrintViewTakeOptions(view, options, whole, NSZeroRect, ^NSImage *(NSUInteger scale, NSRect clip) {
        askedScale = scale;
        return [canvas flattenedImageForPrintAtScale:scale withinRect:clip];
    });
    // 400 px at 72 ppi on macOS is a point a pixel: 300 dpi is 4 pixels a point.
    XCTAssertEqual(askedScale, (NSUInteger)4);
    XCTAssertTrue(NSEqualSizes(STPrintImagePixelSize(view.image), NSMakeSize(1600, 800)));
    XCTAssertEqualWithAccuracy(layout.pixelsPerInch, 288.0, 0.001);
    XCTAssertTrue(NSEqualRects([layout pageRectForPage:0], NSMakeRect(NSMinX([layout printableRect]) + (NSWidth([layout printableRect]) - 400) / 2,
                                                                       NSMinY([layout printableRect]) + (NSHeight([layout printableRect]) - 200) / 2,
                                                                       400, 200)),
                  @"the same 400 × 200 points on the page: %@", NSStringFromRect([layout pageRectForPage:0]));
    XCTAssertEqual([self secretPixelsIn:[self RGBAOf:view.image]], (NSUInteger)0);
}

@end
#endif
