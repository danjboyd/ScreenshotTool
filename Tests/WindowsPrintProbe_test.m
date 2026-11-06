/*
 * WindowsPrintProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Windows's printed pages (#355): STWindowsPrintPages on "Microsoft Print to PDF", read back by rendering
 * the PDF with pdftoppm. The page count, each sheet's size and shape, and each page's part of the image,
 * the right way up, against STPrintLayout. Skips, saying so, without that printer or pdftoppm.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if defined(_WIN32)

#import "STPrintLayout.h"
#import "STPrintPage.h"
#import "STWindowsPrint.h"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <math.h>
#include <stdlib.h>

static NSString * const STPDFPrinter = @"Microsoft Print to PDF";
static const CGFloat STRenderDPI = 72.0;

typedef struct {
    unsigned char r, g, b;
} STPrintProbeRGB;

/// The quadrants' colours, in page order, each with its top half first: a page drawn upside down, or
/// the wrong tile, shows the wrong colour.
static const STPrintProbeRGB STPrintQuadrants[8] = {
    { 255, 0, 0 }, { 128, 0, 0 }, { 0, 255, 0 }, { 0, 128, 0 },
    { 0, 0, 255 }, { 0, 0, 128 }, { 255, 255, 0 }, { 128, 128, 0 },
};

@interface STPrintProbeSheet : NSObject
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@property (nonatomic, strong) NSData *pixels;
@end

@implementation STPrintProbeSheet
+ (nullable instancetype)sheetAtPath:(NSString *)path {
    NSData *ppm = [NSData dataWithContentsOfFile:path];
    int width = 0, height = 0, maximum = 0, headerLength = 0;
    NSString *header = [[NSString alloc] initWithData:[ppm subdataWithRange:NSMakeRange(0, MIN(ppm.length, (NSUInteger)64))]
                                             encoding:NSISOLatin1StringEncoding];
    if (sscanf(header.UTF8String, "P6 %d %d %d%n", &width, &height, &maximum, &headerLength) != 3 || maximum != 255) {
        return nil;
    }
    NSUInteger start = (NSUInteger)headerLength + 1, size = (NSUInteger)width * (NSUInteger)height * 3;
    if (ppm.length < start + size) {
        return nil;
    }
    STPrintProbeSheet *sheet = [[STPrintProbeSheet alloc] init];
    sheet.width = width;
    sheet.height = height;
    sheet.pixels = [ppm subdataWithRange:NSMakeRange(start, size)];
    return sheet;
}
- (STPrintProbeRGB)colorAtX:(CGFloat)x y:(CGFloat)y {
    NSInteger px = (NSInteger)(x * STRenderDPI / 72.0), py = (NSInteger)(y * STRenderDPI / 72.0);
    const unsigned char *p = (const unsigned char *)self.pixels.bytes + (py * self.width + px) * 3;
    STPrintProbeRGB color = { p[0], p[1], p[2] };
    return color;
}
@end

@interface WindowsPrintProbeTests : XCTestCase
@end

@implementation WindowsPrintProbeTests {
    NSString *_directory;
    NSString *_pdftoppm;
}

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
    _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:NULL];
    _pdftoppm = nil;
    NSMutableArray<NSString *> *folders = [[[[NSProcessInfo processInfo] environment][@"PATH"] componentsSeparatedByString:@";"] mutableCopy];
    [folders addObject:@"C:/msys64/ucrt64/bin"];
    [folders addObject:@"C:/msys64/mingw64/bin"];
    for (NSString *folder in folders) {
        NSString *candidate = [folder stringByAppendingPathComponent:@"pdftoppm.exe"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
            _pdftoppm = candidate;
            break;
        }
    }
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:_directory error:NULL];
    [super tearDown];
}

/// Whether this machine can run these, logging why not.
- (BOOL)canPrint {
    if (!STWindowsPrinterExists(STPDFPrinter)) {
        NSLog(@"WindowsPrintProbe: SKIPPED: no \"%@\" printer here", STPDFPrinter);
        return NO;
    }
    if (!_pdftoppm) {
        NSLog(@"WindowsPrintProbe: SKIPPED: no pdftoppm here to read the PDF with");
        return NO;
    }
    return YES;
}

/// A 400 × 200 pixel image in four 200 × 100 quadrants, each in two halves.
- (NSImage *)quadrantImage {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:400 pixelsHigh:200 bitsPerSample:8
                                                               samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    unsigned char *data = rep.bitmapData;
    for (NSInteger y = 0; y < 200; y++) {
        for (NSInteger x = 0; x < 400; x++) {
            NSInteger quadrant = (y < 100 ? 0 : 2) + (x < 200 ? 0 : 1);
            STPrintProbeRGB color = STPrintQuadrants[quadrant * 2 + ((y % 100) < 50 ? 0 : 1)];
            unsigned char *p = data + y * rep.bytesPerRow + x * 4;
            p[0] = color.r;
            p[1] = color.g;
            p[2] = color.b;
            p[3] = 255;
        }
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(400, 200)];
    [image addRepresentation:rep];
    return image;
}

- (STPrintLayout *)layoutOnPrinterDC:(void *)dc pixelsPerInch:(CGFloat)ppi {
    STWindowsPrinterSheet sheet = STWindowsPrinterSheetFromDC(dc);
    XCTAssertTrue(sheet.valid);
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.sourceRect = NSMakeRect(0, 0, 400, 200);
    layout.pixelsPerInch = ppi;
    layout.paperSize = sheet.paper;
    layout.printerMargins = sheet.printerMargins;
    layout.margins = STPrintMarginsMake(STPrintDefaultMargin, STPrintDefaultMargin, STPrintDefaultMargin, STPrintDefaultMargin);
    return layout;
}

/// The PDF the spooler writes after the job ends: there and no longer growing.
- (BOOL)waitForFile:(NSString *)path {
    unsigned long long last = 0;
    for (int i = 0; i < 150; i++) {
        unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] fileSize];
        if (size > 0 && size == last) {
            return YES;
        }
        last = size;
        Sleep(200);
    }
    return NO;
}

/// Prints and renders; the sheets in page order.
- (NSArray<STPrintProbeSheet *> *)sheetsPrinting:(STPrintLayout *)layout image:(NSImage *)image dc:(void *)dc devMode:(void *)devMode {
    NSString *pdf = [_directory stringByAppendingPathComponent:@"out.pdf"];
    NSString *failure = nil;
    BOOL printed = STWindowsPrintPages(dc, devMode, layout, image, @"WindowsPrintProbe", pdf, &failure);
    XCTAssertTrue(printed, @"%@", failure);
    if (!printed || ![self waitForFile:pdf]) {
        XCTFail(@"No PDF at %@", pdf);
        return @[];
    }
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = _pdftoppm;
    task.arguments = @[ @"-r", [NSString stringWithFormat:@"%g", STRenderDPI], pdf, [_directory stringByAppendingPathComponent:@"page"] ];
    [task launch];
    [task waitUntilExit];
    XCTAssertEqual(task.terminationStatus, 0);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_directory error:NULL]) {
        if ([name hasSuffix:@".ppm"]) {
            [names addObject:name];
        }
    }
    [names sortUsingSelector:@selector(compare:)];
    NSMutableArray<STPrintProbeSheet *> *sheets = [NSMutableArray array];
    for (NSString *name in names) {
        STPrintProbeSheet *sheet = [STPrintProbeSheet sheetAtPath:[_directory stringByAppendingPathComponent:name]];
        XCTAssertNotNil(sheet, @"%@", name);
        if (sheet) {
            [sheets addObject:sheet];
        }
    }
    return sheets;
}

- (void)assertColor:(STPrintProbeRGB)color near:(STPrintProbeRGB)expected message:(NSString *)message {
    XCTAssertLessThanOrEqual(abs(color.r - expected.r) + abs(color.g - expected.g) + abs(color.b - expected.b), 40,
                             @"%@: %d,%d,%d not %d,%d,%d", message, color.r, color.g, color.b, expected.r, expected.g, expected.b);
}

/// Each tile's quadrants of `sheet`, where the layout says, and its sheet's size.
- (void)assertSheet:(STPrintProbeSheet *)sheet page:(NSUInteger)page layout:(STPrintLayout *)layout {
    NSSize oriented = layout.orientedPaperSize;
    XCTAssertEqualWithAccuracy((CGFloat)sheet.width, oriented.width, 2.0, @"page %lu", (unsigned long)page);
    XCTAssertEqualWithAccuracy((CGFloat)sheet.height, oriented.height, 2.0, @"page %lu", (unsigned long)page);
    NSRect from = [layout sourceRectForPage:page];
    NSRect to = [layout pageRectForPage:page];
    CGFloat toX = NSWidth(to) / NSWidth(from), toY = NSHeight(to) / NSHeight(from);
    // A sample in every quarter of the tile, kept off the edges of the image's colour bands.
    for (CGFloat fx = 0.125; fx < 1.0; fx += 0.25) {
        for (CGFloat fy = 0.125; fy < 1.0; fy += 0.25) {
            CGFloat ix = NSMinX(from) + NSWidth(from) * fx, iy = NSMinY(from) + NSHeight(from) * fy;
            CGFloat bandY = fmod(iy, 50.0), bandX = fmod(ix, 200.0);
            if (bandY < 6.0 || bandY > 44.0 || bandX < 6.0 || bandX > 194.0) {
                continue;
            }
            NSInteger quadrant = (iy < 100 ? 0 : 2) + (ix < 200 ? 0 : 1);
            STPrintProbeRGB expected = STPrintQuadrants[quadrant * 2 + (fmod(iy, 100.0) < 50 ? 0 : 1)];
            CGFloat sx = NSMinX(to) + (ix - NSMinX(from)) * toX, sy = NSMinY(to) + (iy - NSMinY(from)) * toY;
            [self assertColor:[sheet colorAtX:sx y:sy] near:expected
                      message:[NSString stringWithFormat:@"page %lu at image %.0f,%.0f", (unsigned long)page, ix, iy]];
        }
    }
    // Outside the page's rect the sheet stays white.
    STPrintProbeRGB white = { 255, 255, 255 };
    if (NSMinX(to) > 8.0) {
        [self assertColor:[sheet colorAtX:NSMinX(to) - 6.0 y:NSMidY(to)] near:white message:@"Left of the page's rect"];
    }
    if (NSMinY(to) > 8.0) {
        [self assertColor:[sheet colorAtX:NSMidX(to) y:NSMinY(to) - 6.0] near:white message:@"Above the page's rect"];
    }
}

- (void)printLayout:(STPrintLayout *(^)(void *dc))make expectingPages:(NSUInteger)count landscape:(BOOL)landscape {
    void *devMode = NULL;
    void *dc = STWindowsCreatePrinterDC(STPDFPrinter, &devMode);
    XCTAssertTrue(dc != NULL);
    if (!dc) {
        return;
    }
    STPrintLayout *layout = make(dc);
    XCTAssertEqual(layout.pageCount, count);
    XCTAssertEqual(layout.resolvedOrientation == STPrintOrientationLandscape, landscape);
    NSArray<STPrintProbeSheet *> *sheets = [self sheetsPrinting:layout image:[self quadrantImage] dc:dc devMode:devMode];
    DeleteDC((HDC)dc);
    free(devMode);
    XCTAssertEqual(sheets.count, count, @"One sheet per page");
    for (NSUInteger page = 0; page < MIN(sheets.count, count); page++) {
        [self assertSheet:sheets[page] page:page layout:layout];
    }
}

/// Automatic orientation: a wide image fits a landscape sheet larger, and the sheet turns.
- (void)testFitToPageTurnsTheSheetForAWideImage {
    if (![self canPrint]) {
        return;
    }
    [self printLayout:^STPrintLayout *(void *dc) {
        STPrintLayout *layout = [self layoutOnPrinterDC:dc pixelsPerInch:32.0];
        layout.fit = STPrintFitToPage;
        return layout;
    } expectingPages:1 landscape:YES];
}

/// A set orientation holds, and a small image prints at its real size, centred.
- (void)testPortraitHoldsWhenAskedFor {
    if (![self canPrint]) {
        return;
    }
    [self printLayout:^STPrintLayout *(void *dc) {
        STPrintLayout *layout = [self layoutOnPrinterDC:dc pixelsPerInch:96.0];
        layout.fit = STPrintFitToPage;
        layout.orientation = STPrintOrientationPortrait;
        return layout;
    } expectingPages:1 landscape:NO];
}

/// Larger than a sheet at its real size: tiled, left to right then down, each tile in its place.
- (void)testActualSizeTilesOverSheets {
    if (![self canPrint]) {
        return;
    }
    [self printLayout:^STPrintLayout *(void *dc) {
        STPrintLayout *layout = [self layoutOnPrinterDC:dc pixelsPerInch:32.0];
        layout.fit = STPrintFitActualSize;
        layout.orientation = STPrintOrientationPortrait;
        return layout;
    } expectingPages:[self expectedTilesPortraitAt32] landscape:NO];
}

- (NSUInteger)expectedTilesPortraitAt32 {
    void *dc = STWindowsCreatePrinterDC(STPDFPrinter, NULL);
    STPrintLayout *layout = [self layoutOnPrinterDC:dc pixelsPerInch:32.0];
    layout.fit = STPrintFitActualSize;
    layout.orientation = STPrintOrientationPortrait;
    NSUInteger count = layout.pageCount;
    DeleteDC((HDC)dc);
    XCTAssertGreaterThan(count, (NSUInteger)1, @"The test needs tiles");
    return count;
}

/// Shared edges round the same way on both sides, so tiles neither gap nor overlap.
- (void)testTileEdgesMeet {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.sourceRect = NSMakeRect(0, 0, 1001, 777);
    layout.pixelsPerInch = 37.0;
    layout.paperSize = NSMakeSize(612, 792);
    layout.margins = STPrintMarginsMake(36, 36, 36, 36);
    layout.fit = STPrintFitActualSize;
    layout.orientation = STPrintOrientationPortrait;
    XCTAssertGreaterThan(layout.pagesAcross, (NSUInteger)1);
    XCTAssertGreaterThan(layout.pagesDown, (NSUInteger)1);
    NSSize pixels = NSMakeSize(1001, 777);
    NSRect last = NSZeroRect;
    CGFloat coveredWidth = 0.0, coveredHeight = 0.0;
    for (NSUInteger page = 0; page < layout.pageCount; page++) {
        NSRect source, target;
        STWindowsPrintPageRects(layout, page, pixels, NSMakeSize(600, 600), NSZeroPoint, &source, &target);
        if (page % layout.pagesAcross == 0) {
            coveredHeight += NSHeight(source);
        } else {
            XCTAssertEqual(NSMinX(source), NSMaxX(last), @"page %lu", (unsigned long)page);
        }
        if (page < layout.pagesAcross) {
            coveredWidth += NSWidth(source);
        }
        last = source;
    }
    XCTAssertEqual(coveredWidth, 1001.0);
    XCTAssertEqual(coveredHeight, 777.0);
}

@end

#endif
