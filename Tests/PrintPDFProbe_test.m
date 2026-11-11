/*
 * PrintPDFProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Linux's printed PDF (#355): STWritePrintPDF's pages, read back by rendering them with pdftoppm. Each
 * has the right sheet size and holds its part of the image, the right way up, inside the margins. This
 * also guards the two libs-gui internals that the PDF depends on: see STPrintPDF.h. No printer involved.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if defined(__linux__)

#import "STPrintLayout.h"
#import "STPrintPDF.h"
#import "STPrintPage.h"

typedef struct {
    unsigned char r, g, b;
} STProbeRGB;

/// The quadrants' colours, in page order (top left, top right, bottom left, bottom right), each with
/// its top half first: a page drawn upside down, or the wrong tile, shows the wrong colour.
static const STProbeRGB STQuadrants[8] = {
    { 255, 0, 0 }, { 128, 0, 0 }, { 0, 255, 0 }, { 0, 128, 0 },
    { 0, 0, 255 }, { 0, 0, 128 }, { 255, 255, 0 }, { 128, 128, 0 },
};
static const STProbeRGB STWhite = { 255, 255, 255 };
static const CGFloat STRenderDPI = 144.0;

/// A rendered sheet, from pdftoppm's PPM.
@interface STProbeSheet : NSObject
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@property (nonatomic, strong) NSData *pixels;
@end

@implementation STProbeSheet

+ (nullable instancetype)sheetWithPPM:(NSData *)ppm {
    int width = 0, height = 0, maximum = 0, headerLength = 0;
    NSData *head = [ppm subdataWithRange:NSMakeRange(0, MIN(ppm.length, (NSUInteger)64))];
    NSString *header = [[NSString alloc] initWithData:head encoding:NSISOLatin1StringEncoding];
    if (sscanf(header.UTF8String, "P6 %d %d %d%n", &width, &height, &maximum, &headerLength) != 3 || maximum != 255) {
        return nil;
    }
    NSUInteger start = (NSUInteger)headerLength + 1;
    NSUInteger size = (NSUInteger)width * (NSUInteger)height * 3;
    if (ppm.length < start + size) {
        return nil;
    }
    STProbeSheet *sheet = [[STProbeSheet alloc] init];
    sheet.width = width;
    sheet.height = height;
    sheet.pixels = [ppm subdataWithRange:NSMakeRange(start, size)];
    return sheet;
}

/// The colour at (x, y) in points from the sheet's top left, at `dpi`.
- (STProbeRGB)colorAtX:(CGFloat)x y:(CGFloat)y dpi:(CGFloat)dpi {
    NSInteger px = (NSInteger)(x * dpi / 72.0);
    NSInteger py = (NSInteger)(y * dpi / 72.0);
    const unsigned char *p = (const unsigned char *)self.pixels.bytes + (py * self.width + px) * 3;
    STProbeRGB color = { p[0], p[1], p[2] };
    return color;
}

@end

@interface PrintPDFProbeTests : XCTestCase
@end

@implementation PrintPDFProbeTests {
    NSString *_directory;
}

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
    _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:_directory error:NULL];
    [super tearDown];
}

/// A 400 × 200 pixel image in four 200 × 100 quadrants, each in two halves, `pointScale` points per
/// pixel (0.5 is a Retina capture).
- (NSImage *)quadrantImageWithPointScale:(CGFloat)pointScale {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:400
                                                                    pixelsHigh:200
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    unsigned char *data = rep.bitmapData;
    for (NSInteger y = 0; y < 200; y++) {
        for (NSInteger x = 0; x < 400; x++) {
            NSInteger quadrant = (y < 100 ? 0 : 2) + (x < 200 ? 0 : 1);
            STProbeRGB color = STQuadrants[quadrant * 2 + ((y % 100) < 50 ? 0 : 1)];
            unsigned char *p = data + y * rep.bytesPerRow + x * 4;
            p[0] = color.r;
            p[1] = color.g;
            p[2] = color.b;
            p[3] = 255;
        }
    }
    rep.size = NSMakeSize(400 * pointScale, 200 * pointScale);
    NSImage *image = [[NSImage alloc] initWithSize:rep.size];
    [image addRepresentation:rep];
    return image;
}

/// 2 × 2 pages exactly: the image at 72 ppi on a 240 × 140 landscape sheet. The margins differ on
/// every side, so a mirrored page lands in the wrong place, and leave 200 × 100 points, a quadrant,
/// at (12, 8).
- (STPrintLayout *)tiledLayout {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.sourceRect = NSMakeRect(0, 0, 400, 200);
    layout.pixelsPerInch = 72.0;
    layout.fit = STPrintFitActualSize;
    layout.orientation = STPrintOrientationLandscape;
    layout.paperSize = NSMakeSize(140, 240);
    layout.margins = STPrintMarginsMake(8, 12, 32, 28);
    return layout;
}

/// The PDF's pages rendered at `dpi`, in order; nil, with a failure, if anything didn't work.
- (nullable NSArray<STProbeSheet *> *)sheetsOfLayout:(STPrintLayout *)layout image:(NSImage *)image dpi:(CGFloat)dpi {
    NSString *pdf = [_directory stringByAppendingPathComponent:@"print.pdf"];
    XCTAssertTrue(STWritePrintPDF(layout, image, pdf));
    NSString *prefix = [_directory stringByAppendingPathComponent:@"sheet"];
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/env";
    task.arguments = @[ @"pdftoppm", @"-r", [NSString stringWithFormat:@"%g", dpi], pdf, prefix ];
    [task launch];
    [task waitUntilExit];
    // Missing is a failure, not a skip, so that a machine without poppler-utils can't pass for green.
    XCTAssertEqual(task.terminationStatus, 0, @"pdftoppm failed; is poppler-utils installed?");
    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableArray<STProbeSheet *> *sheets = [NSMutableArray array];
    NSArray<NSString *> *names = [[files contentsOfDirectoryAtPath:_directory error:NULL]
        sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        if ([name.pathExtension isEqualToString:@"ppm"]) {
            NSString *path = [_directory stringByAppendingPathComponent:name];
            STProbeSheet *sheet = [STProbeSheet sheetWithPPM:[NSData dataWithContentsOfFile:path]];
            XCTAssertNotNil(sheet, @"%@ isn't a PPM", name);
            if (sheet) {
                [sheets addObject:sheet];
            }
        }
    }
    return sheets;
}

- (void)assertSheet:(STProbeSheet *)sheet x:(CGFloat)x y:(CGFloat)y is:(STProbeRGB)color message:(NSString *)message {
    STProbeRGB pixel = [sheet colorAtX:x y:y dpi:STRenderDPI];
    XCTAssertEqualWithAccuracy((double)pixel.r, (double)color.r, 12.0, @"%@ at %g,%g: red", message, x, y);
    XCTAssertEqualWithAccuracy((double)pixel.g, (double)color.g, 12.0, @"%@ at %g,%g: green", message, x, y);
    XCTAssertEqualWithAccuracy((double)pixel.b, (double)color.b, 12.0, @"%@ at %g,%g: blue", message, x, y);
}

/// Four 240 × 140 sheets, each with its quadrant the right way up, filling (12, 8, 200, 100) to its
/// edges, with blank margins.
- (void)assertTiledSheets:(NSArray<STProbeSheet *> *)sheets message:(NSString *)message {
    XCTAssertEqual(sheets.count, (NSUInteger)4, @"%@", message);
    for (NSUInteger page = 0; page < sheets.count && page < 4; page++) {
        STProbeSheet *sheet = sheets[page];
        NSString *where = [NSString stringWithFormat:@"%@, page %lu", message, (unsigned long)page];
        XCTAssertEqual(sheet.width, (NSInteger)480, @"%@", where);
        XCTAssertEqual(sheet.height, (NSInteger)280, @"%@", where);
        STProbeRGB top = STQuadrants[page * 2];
        STProbeRGB bottom = STQuadrants[page * 2 + 1];
        [self assertSheet:sheet x:13 y:9 is:top message:where];
        [self assertSheet:sheet x:210 y:9 is:top message:where];
        [self assertSheet:sheet x:13 y:106 is:bottom message:where];
        [self assertSheet:sheet x:210 y:106 is:bottom message:where];
        // The margins, next to each edge: nothing spills into them.
        [self assertSheet:sheet x:10 y:50 is:STWhite message:where];
        [self assertSheet:sheet x:214 y:50 is:STWhite message:where];
        [self assertSheet:sheet x:100 y:6 is:STWhite message:where];
        [self assertSheet:sheet x:100 y:110 is:STWhite message:where];
    }
}

- (void)testTiledPagesCoverTheImageOnLandscapeSheets {
    [self assertTiledSheets:[self sheetsOfLayout:[self tiledLayout]
                                           image:[self quadrantImageWithPointScale:1.0]
                                             dpi:STRenderDPI]
                    message:@"tiled"];
}

/// The layout counts pixels, not points: a Retina capture's pages are the same.
- (void)testARetinaImageTilesByItsPixels {
    NSImage *image = [self quadrantImageWithPointScale:0.5];
    XCTAssertTrue(NSEqualSizes(STPrintImagePixelSize(image), NSMakeSize(400, 200)));
    [self assertTiledSheets:[self sheetsOfLayout:[self tiledLayout] image:image dpi:STRenderDPI] message:@"Retina"];
}

/// A portrait sheet stays portrait, with the image shrunk to fit and centred.
- (void)testFitToPageOnAPortraitSheet {
    STPrintLayout *layout = [self tiledLayout];
    layout.fit = STPrintFitToPage;
    layout.orientation = STPrintOrientationPortrait;
    layout.margins = STPrintMarginsMake(20, 20, 20, 20);
    // 100 points wide on a 140 × 240 sheet, so 100 × 50, centred at (20, 95).
    NSArray<STProbeSheet *> *sheets = [self sheetsOfLayout:layout
                                                     image:[self quadrantImageWithPointScale:1.0]
                                                       dpi:STRenderDPI];
    XCTAssertEqual(sheets.count, (NSUInteger)1);
    STProbeSheet *sheet = sheets.firstObject;
    XCTAssertEqual(sheet.width, (NSInteger)280);
    XCTAssertEqual(sheet.height, (NSInteger)480);
    [self assertSheet:sheet x:22 y:97 is:STQuadrants[0] message:@"top left"];
    [self assertSheet:sheet x:117 y:97 is:STQuadrants[2] message:@"top right"];
    [self assertSheet:sheet x:22 y:143 is:STQuadrants[5] message:@"bottom left"];
    [self assertSheet:sheet x:117 y:143 is:STQuadrants[7] message:@"bottom right"];
    [self assertSheet:sheet x:70 y:90 is:STWhite message:@"above"];
    [self assertSheet:sheet x:70 y:149 is:STWhite message:@"below"];
}

/// Printing a selection: only that part of the image, from its own place in it.
- (void)testASourceRectPrintsOnlyThatPart {
    STPrintLayout *layout = [self tiledLayout];
    layout.sourceRect = NSMakeRect(200, 100, 200, 100);
    NSArray<STProbeSheet *> *sheets = [self sheetsOfLayout:layout
                                                     image:[self quadrantImageWithPointScale:1.0]
                                                       dpi:STRenderDPI];
    XCTAssertEqual(sheets.count, (NSUInteger)1);
    STProbeSheet *sheet = sheets.firstObject;
    [self assertSheet:sheet x:13 y:9 is:STQuadrants[6] message:@"top"];
    [self assertSheet:sheet x:210 y:106 is:STQuadrants[7] message:@"bottom"];
}

/// Real paper isn't whole points: A4, turned to landscape by the image's shape.
- (void)testA4KeepsItsSize {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.sourceRect = NSMakeRect(0, 0, 400, 200);
    layout.paperSize = NSMakeSize(595.28, 841.89);
    layout.margins = STPrintMarginsMake(36, 36, 36, 36);
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationLandscape);
    NSArray<STProbeSheet *> *sheets = [self sheetsOfLayout:layout
                                                     image:[self quadrantImageWithPointScale:1.0]
                                                       dpi:72.0];
    XCTAssertEqual(sheets.count, (NSUInteger)1);
    XCTAssertEqualWithAccuracy((double)sheets.firstObject.width, 842.0, 1.0);
    XCTAssertEqualWithAccuracy((double)sheets.firstObject.height, 595.0, 1.0);
}

- (void)testNoPagesWritesNoFile {
    STPrintLayout *layout = [self tiledLayout];
    layout.sourceRect = NSZeroRect;
    NSString *pdf = [_directory stringByAppendingPathComponent:@"none.pdf"];
    XCTAssertFalse(STWritePrintPDF(layout, [self quadrantImageWithPointScale:1.0], pdf));
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:pdf]);
}

- (void)testAnImageWithNoSizeWritesNoFile {
    NSString *pdf = [_directory stringByAppendingPathComponent:@"none.pdf"];
    XCTAssertFalse(STWritePrintPDF([self tiledLayout], [[NSImage alloc] initWithSize:NSZeroSize], pdf));
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:pdf]);
}

@end

#endif
