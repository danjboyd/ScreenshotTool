/*
 * PrintViewProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The macOS print view (#355): STPrintView, run through a real NSPrintOperation into a PDF, gives
 * one sheet a page, each holding its part of the image the right way up, so a printout and its
 * preview match STPrintLayout. No printer is involved. macOS only: GNUstep and Windows have their
 * own print paths.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if !defined(GNUSTEP)
#import "STPrintLayout.h"
#import "STPrintOptions.h"
#import "STPrintPage.h"
#import "STPrintView.h"

@interface PrintViewProbeTests : XCTestCase
@end

@implementation PrintViewProbeTests

/// Each quadrant's colour, top half first, in page order: a page upside down, mirrored or of the
/// wrong tile shows the wrong one.
static NSArray<NSColor *> *STPrintViewQuadrantColors(void) {
    return @[ [NSColor colorWithCalibratedRed:1 green:0 blue:0 alpha:1],
              [NSColor colorWithCalibratedRed:0.5 green:0 blue:0 alpha:1],
              [NSColor colorWithCalibratedRed:0 green:1 blue:0 alpha:1],
              [NSColor colorWithCalibratedRed:0 green:0.5 blue:0 alpha:1],
              [NSColor colorWithCalibratedRed:0 green:0 blue:1 alpha:1],
              [NSColor colorWithCalibratedRed:0 green:0 blue:0.5 alpha:1],
              [NSColor colorWithCalibratedRed:1 green:1 blue:0 alpha:1],
              [NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0 alpha:1] ];
}

/// 200 × 100 pixels in four quadrants, each in two halves; `pointScale` 0.5 is a Retina capture.
- (NSImage *)quadrantImageWithPointScale:(CGFloat)pointScale {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:200 pixelsHigh:100
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                      isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:0];
    NSArray<NSColor *> *colors = STPrintViewQuadrantColors();
    for (NSInteger y = 0; y < 100; y++) {
        for (NSInteger x = 0; x < 200; x++) {
            NSUInteger quadrant = (y < 50 ? 0 : 2) + (x < 100 ? 0 : 1);
            [rep setColor:colors[quadrant * 2 + ((y % 50) < 25 ? 0 : 1)] atX:x y:y];
        }
    }
    rep.size = NSMakeSize(200 * pointScale, 100 * pointScale);
    NSImage *image = [[NSImage alloc] initWithSize:rep.size];
    [image addRepresentation:rep];
    return image;
}

/// A 40×20-point Retina image whose 80×40 pixels have distinct 20×10 colour tiles.
- (NSImage *)retinaSelectionTiles {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:80 pixelsHigh:40
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                      isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:0];
    for (NSInteger y = 0; y < 40; y++) {
        for (NSInteger x = 0; x < 80; x++) {
            NSInteger tileX = x / 20, tileY = y / 10;
            NSColor *color = [NSColor colorWithCalibratedRed:(CGFloat)tileX / 3.0
                                                       green:(CGFloat)tileY / 3.0
                                                        blue:(CGFloat)(tileX * 4 + tileY) / 15.0 alpha:1];
            [rep setColor:color atX:x y:y];
        }
    }
    rep.size = NSMakeSize(40, 20);
    NSImage *image = [[NSImage alloc] initWithSize:rep.size];
    [image addRepresentation:rep];
    return image;
}

/// 2 × 2 pages: the image at 72 ppi on a 70 × 120 sheet turned landscape, with uneven margins that
/// leave a quadrant's 100 × 50 points at (6, 4).
- (STPrintLayout *)tiledLayout {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.sourceRect = NSMakeRect(0, 0, 200, 100);
    layout.pixelsPerInch = 72.0;
    layout.fit = STPrintFitActualSize;
    layout.orientation = STPrintOrientationLandscape;
    layout.paperSize = NSMakeSize(70, 120);
    layout.margins = STPrintMarginsMake(4, 6, 16, 14);
    return layout;
}

/// The PDF a print operation saves of the view, readied as the app readies it: the same path as
/// printing, with the job saved to a file instead of sent to a printer.
- (NSData *)PDFOfLayout:(STPrintLayout *)layout image:(NSImage *)image {
    NSPrintInfo *info = [[NSPrintInfo alloc] initWithDictionary:@{}];
    info.paperSize = layout.paperSize;
    STPreparePrintInfo(info, layout);
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                            [NSString stringWithFormat:@"PrintViewProbe-%@.pdf", [NSUUID UUID].UUIDString]]];
    info.jobDisposition = NSPrintSaveJob;
    info.dictionary[NSPrintJobSavingURL] = url;
    STPrintView *view = [[STPrintView alloc] initWithLayout:layout image:image];
    NSPrintOperation *operation = [NSPrintOperation printOperationWithView:view printInfo:info];
    operation.showsPrintPanel = NO;
    operation.showsProgressPanel = NO;
    XCTAssertTrue([operation runOperation]);
    NSData *data = [NSData dataWithContentsOfURL:url];
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    return data ?: [NSData data];
}

/// A PDF page drawn into a bitmap two pixels a point, on white.
- (NSBitmapImageRep *)bitmapOfPDFPage:(CGPDFPageRef)page {
    CGRect box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
    NSInteger width = (NSInteger)lround(box.size.width * 2), height = (NSInteger)lround(box.size.height * 2);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                      isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    CGContextRef cg = context.CGContext;
    CGContextSetRGBFillColor(cg, 1, 1, 1, 1);
    CGContextFillRect(cg, CGRectMake(0, 0, width, height));
    CGContextScaleCTM(cg, 2, 2);
    CGContextTranslateCTM(cg, -box.origin.x, -box.origin.y);
    CGContextDrawPDFPage(cg, page);
    CGContextFlush(cg);
    return rep;
}

/// The nearest of the quadrant colours and white to `pixel`. A PDF's colours go through colour
/// management on the way to a bitmap, so the probe asks which colour a pixel is, not its exact value.
static NSColor *STNearestProbeColor(NSColor *pixel) {
    NSMutableArray<NSColor *> *candidates = [STPrintViewQuadrantColors() mutableCopy];
    [candidates addObject:[NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:1]];
    NSColor *rgb = [pixel colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    NSColor *nearest = nil;
    CGFloat best = CGFLOAT_MAX;
    for (NSColor *candidate in candidates) {
        NSColor *c = [candidate colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        CGFloat dr = c.redComponent - rgb.redComponent, dg = c.greenComponent - rgb.greenComponent,
                db = c.blueComponent - rgb.blueComponent;
        CGFloat distance = dr * dr + dg * dg + db * db;
        if (distance < best) {
            best = distance;
            nearest = candidate;
        }
    }
    return nearest;
}

/// Whether the sheet at (x, y), in points from its top left, is `color`.
- (void)assertSheet:(NSBitmapImageRep *)sheet x:(NSInteger)x y:(NSInteger)y is:(NSColor *)color message:(NSString *)message {
    NSColor *pixel = [sheet colorAtX:(NSInteger)((x + 0.5) * 2) y:(NSInteger)((y + 0.5) * 2)];
    NSColor *nearest = STNearestProbeColor(pixel);
    XCTAssertTrue([[nearest colorUsingColorSpaceName:NSCalibratedRGBColorSpace]
                      isEqual:[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace]],
                  @"%@ at %ld,%ld: %@ is nearest %@, not %@", message, (long)x, (long)y, pixel, nearest, color);
}

- (void)assertTiledPDF:(NSData *)data message:(NSString *)message {
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    XCTAssertTrue(document != NULL, @"%@: not a PDF", message);
    if (!document) {
        return;
    }
    XCTAssertEqual(CGPDFDocumentGetNumberOfPages(document), (size_t)4, @"%@: pages", message);
    NSArray<NSColor *> *colors = STPrintViewQuadrantColors();
    NSColor *white = [NSColor whiteColor];
    for (NSUInteger page = 0; page < MIN((size_t)4, CGPDFDocumentGetNumberOfPages(document)); page++) {
        CGPDFPageRef pdfPage = CGPDFDocumentGetPage(document, page + 1);
        CGRect box = CGPDFPageGetBoxRect(pdfPage, kCGPDFMediaBox);
        NSString *where = [NSString stringWithFormat:@"%@, page %lu", message, (unsigned long)page];
        XCTAssertEqualWithAccuracy(box.size.width, 120.0, 0.5, @"%@: a landscape sheet", where);
        XCTAssertEqualWithAccuracy(box.size.height, 70.0, 0.5, @"%@: a landscape sheet", where);
        NSBitmapImageRep *sheet = [self bitmapOfPDFPage:pdfPage];
        NSColor *top = colors[page * 2];
        NSColor *bottom = colors[page * 2 + 1];
        [self assertSheet:sheet x:6 y:4 is:top message:where];
        [self assertSheet:sheet x:105 y:4 is:top message:where];
        [self assertSheet:sheet x:6 y:53 is:bottom message:where];
        [self assertSheet:sheet x:105 y:53 is:bottom message:where];
        [self assertSheet:sheet x:4 y:30 is:white message:where];
        [self assertSheet:sheet x:107 y:30 is:white message:where];
        [self assertSheet:sheet x:50 y:2 is:white message:where];
        [self assertSheet:sheet x:50 y:55 is:white message:where];
    }
    CGPDFDocumentRelease(document);
}

- (void)testAPrintOperationGivesASheetAPage {
    [self assertTiledPDF:[self PDFOfLayout:[self tiledLayout] image:[self quadrantImageWithPointScale:1.0]]
                 message:@"1x"];
}

- (void)testARetinaImagePrintsTheSamePages {
    [self assertTiledPDF:[self PDFOfLayout:[self tiledLayout] image:[self quadrantImageWithPointScale:0.5]]
                 message:@"Retina"];
}

/// The print info follows the layout: its orientation, and none of its own margins or scaling.
- (void)testThePrintInfoIsReadiedForTheLayout {
    STPrintLayout *layout = [self tiledLayout];
    NSPrintInfo *info = [[NSPrintInfo alloc] initWithDictionary:@{}];
    info.paperSize = layout.paperSize;
    info.topMargin = 36;
    info.leftMargin = 36;
    info.horizontallyCentered = YES;
    STPreparePrintInfo(info, layout);
    XCTAssertEqual(info.orientation, NSPaperOrientationLandscape);
    XCTAssertEqual(info.topMargin, 0.0);
    XCTAssertEqual(info.leftMargin, 0.0);
    XCTAssertFalse(info.horizontallyCentered);
    XCTAssertEqual(info.horizontalPagination, NSPrintingPaginationModeClip);
    XCTAssertEqual(info.scalingFactor, 1.0);

    layout.orientation = STPrintOrientationPortrait;
    STPreparePrintInfo(info, layout);
    XCTAssertEqual(info.orientation, NSPaperOrientationPortrait);
}

/// A layout with no pages prints none, rather than a blank sheet.
- (void)testNoPagesGivesAnEmptyRange {
    STPrintLayout *layout = [self tiledLayout];
    layout.sourceRect = NSZeroRect;
    STPrintView *view = [[STPrintView alloc] initWithLayout:layout image:[self quadrantImageWithPointScale:1.0]];
    NSRange range = NSMakeRange(NSNotFound, 0);
    XCTAssertTrue([view knowsPageRange:&range]);
    XCTAssertEqual(range.length, (NSUInteger)0);
}

/// Printer margins come out on the portrait sheet whatever the print info's orientation.
- (void)testPrinterMarginsAreReadPortrait {
    NSPrintInfo *info = [[NSPrintInfo alloc] initWithDictionary:@{}];
    info.paperSize = NSMakeSize(612, 792);
    STPrintMargins portrait = STPrinterMarginsForPrintInfo(info);
    info.orientation = NSPaperOrientationLandscape;
    STPrintMargins landscape = STPrinterMarginsForPrintInfo(info);
    XCTAssertEqual(portrait.top, landscape.top);
    XCTAssertEqual(portrait.left, landscape.left);
    XCTAssertEqual(portrait.bottom, landscape.bottom);
    XCTAssertEqual(portrait.right, landscape.right);
    XCTAssertGreaterThanOrEqual(portrait.top, 0.0);
    XCTAssertEqual(info.orientation, NSPaperOrientationLandscape, @"the print info is left as it was");
}


#pragma mark - Only what's printed is in the file

/// Every image a PDF embeds, as its pixel size, including those inside form XObjects.
static void STCollectPDFImages(CGPDFDictionaryRef resources, NSMutableArray<NSValue *> *sizes, NSUInteger depth);

static void STCollectXObject(const char *key, CGPDFObjectRef object, void *info) {
    (void)key;
    NSMutableDictionary *context = (__bridge NSMutableDictionary *)info;
    NSMutableArray<NSValue *> *sizes = context[@"sizes"];
    NSUInteger depth = [context[@"depth"] unsignedIntegerValue];
    CGPDFStreamRef stream = NULL;
    if (!CGPDFObjectGetValue(object, kCGPDFObjectTypeStream, &stream)) {
        return;
    }
    CGPDFDictionaryRef dictionary = CGPDFStreamGetDictionary(stream);
    const char *subtype = NULL;
    if (!CGPDFDictionaryGetName(dictionary, "Subtype", &subtype)) {
        return;
    }
    if (strcmp(subtype, "Image") == 0) {
        CGPDFInteger width = 0, height = 0;
        CGPDFDictionaryGetInteger(dictionary, "Width", &width);
        CGPDFDictionaryGetInteger(dictionary, "Height", &height);
        [sizes addObject:[NSValue valueWithSize:NSMakeSize(width, height)]];
    } else if (strcmp(subtype, "Form") == 0 && depth < 8) {
        CGPDFDictionaryRef resources = NULL;
        if (CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)) {
            STCollectPDFImages(resources, sizes, depth + 1);
        }
    }
}

static void STCollectPDFImages(CGPDFDictionaryRef resources, NSMutableArray<NSValue *> *sizes, NSUInteger depth) {
    CGPDFDictionaryRef xobjects = NULL;
    if (!CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects)) {
        return;
    }
    NSMutableDictionary *context = [@{ @"sizes": sizes, @"depth": @(depth) } mutableCopy];
    CGPDFDictionaryApplyFunction(xobjects, STCollectXObject, (__bridge void *)context);
}

- (NSArray<NSValue *> *)imageSizesInPDF:(NSData *)data {
    NSMutableArray<NSValue *> *sizes = [NSMutableArray array];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    for (size_t page = 1; document && page <= CGPDFDocumentGetNumberOfPages(document); page++) {
        CGPDFDictionaryRef resources = NULL;
        if (CGPDFDictionaryGetDictionary(CGPDFPageGetDictionary(CGPDFDocumentGetPage(document, page)), "Resources", &resources)) {
            STCollectPDFImages(resources, sizes, 0);
        }
    }
    CGPDFDocumentRelease(document);
    return sizes;
}

/// A page of several embeds only its own part of the image, not all of it clipped (perf, 0.4.0).
- (void)testEachPageEmbedsOnlyItsTile {
    NSArray<NSValue *> *sizes = [self imageSizesInPDF:[self PDFOfLayout:[self tiledLayout] image:[self quadrantImageWithPointScale:1.0]]];
    XCTAssertEqual(sizes.count, (NSUInteger)4, @"%@", sizes);
    for (NSValue *size in sizes) {
        XCTAssertTrue(NSEqualSizes(size.sizeValue, NSMakeSize(100, 50)), @"a quadrant, not the whole image: %@", sizes);
    }
}

/// A 400 × 200 checkerboard (a redaction's mosaic keeps a solid colour, so the probe doesn't use one).
- (NSImage *)checkerboardImageWithSize:(NSSize)size {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)size.width
                                                                    pixelsHigh:(NSInteger)size.height bitsPerSample:8
                                                               samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    for (NSInteger y = 0; y < (NSInteger)size.height; y++) {
        for (NSInteger x = 0; x < (NSInteger)size.width; x++) {
            BOOL dark = ((x / 10) + (y / 10)) % 2 == 0;
            [rep setColor:[NSColor colorWithCalibratedWhite:dark ? 0.1 : 0.9 alpha:1] atX:x y:y];
        }
    }
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image addRepresentation:rep];
    return image;
}

- (NSData *)PDFOfView:(STPrintView *)view {
    NSPrintInfo *info = [[NSPrintInfo alloc] initWithDictionary:@{}];
    info.paperSize = NSMakeSize(612, 792);
    view.layout.paperSize = info.paperSize;
    STPreparePrintInfo(info, view.layout);
    [view setFrameSize:view.layout.orientedPaperSize];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                            [NSString stringWithFormat:@"PrintViewProbe-%@.pdf", [NSUUID UUID].UUIDString]]];
    info.jobDisposition = NSPrintSaveJob;
    info.dictionary[NSPrintJobSavingURL] = url;
    NSPrintOperation *operation = [NSPrintOperation printOperationWithView:view printInfo:info];
    operation.showsPrintPanel = NO;
    operation.showsProgressPanel = NO;
    XCTAssertTrue([operation runOperation]);
    NSData *data = [NSData dataWithContentsOfURL:url];
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    return data ?: [NSData data];
}

/// Printing the selection embeds only the selection's pixels, not the whole image clipped.
- (void)testASelectionsPDFHoldsOnlyTheSelection {
    NSImage *whole = [self checkerboardImageWithSize:NSMakeSize(400, 200)];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.selectionOnly = YES;
    STPrintView *view = [[STPrintView alloc] initWithLayout:[[STPrintLayout alloc] init] image:whole];
    // No flattener: the on-screen flatten, cropped to the selection.
    STPrintViewTakeOptions(view, options, whole, NSMakeRect(50, 40, 100, 80), nil);
    XCTAssertTrue(NSEqualSizes(STPrintImagePixelSize(view.image), NSMakeSize(100, 80)));
    NSArray<NSValue *> *sizes = [self imageSizesInPDF:[self PDFOfView:view]];
    XCTAssertGreaterThan(sizes.count, (NSUInteger)0, @"the PDF has the image");
    for (NSValue *size in sizes) {
        XCTAssertLessThanOrEqual(size.sizeValue.width, 100.0, @"an embedded image wider than the selection: %@", size);
        XCTAssertLessThanOrEqual(size.sizeValue.height, 80.0, @"an embedded image taller than the selection: %@", size);
    }
}

/// The probe sees the leak it guards against: the whole image clipped to a selection is all in the file.
- (void)testTheProbeSeesAClippedWholeImage {
    NSImage *whole = [self checkerboardImageWithSize:NSMakeSize(400, 200)];
    STPrintView *view = [[STPrintView alloc] initWithLayout:[[STPrintLayout alloc] init] image:whole];
    STPrintViewTakeOptions(view, [[STPrintOptions alloc] init], whole, NSZeroRect, nil);
    view.layout.sourceRect = NSMakeRect(50, 50, 100, 80);
    NSArray<NSValue *> *sizes = [self imageSizesInPDF:[self PDFOfView:view]];
    BOOL sawWhole = NO;
    for (NSValue *size in sizes) {
        sawWhole = sawWhole || size.sizeValue.width >= 400.0;
    }
    XCTAssertTrue(sawWhole, @"embedded: %@", sizes);
}

/// A selection-only request whose selection disappeared must have no printable pages.
- (void)testNoSelectionPrintsNothing {
    NSImage *whole = [self checkerboardImageWithSize:NSMakeSize(400, 200)];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.selectionOnly = YES;
    STPrintView *view = [[STPrintView alloc] initWithLayout:[[STPrintLayout alloc] init] image:whole];
    STPrintViewTakeOptions(view, options, whole, NSZeroRect, nil);
    XCTAssertTrue(NSIsEmptyRect(view.layout.sourceRect));
    XCTAssertEqual(view.layout.pageCount, (NSUInteger)0);
}

/// Canvas selection coordinates are points; a Retina bitmap's printable source is in pixels.
- (void)testRetinaSelectionConfiguresTheMatchingPixelRect {
    NSImage *whole = [self retinaSelectionTiles];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.selectionOnly = YES;
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    STConfigurePrintLayout(layout, options, whole, NSMakeRect(10, 5, 10, 5));
    XCTAssertTrue(NSEqualRects(layout.sourceRect, NSMakeRect(20, 10, 20, 10)), @"source=%@", NSStringFromRect(layout.sourceRect));
}

/// A failed print flattener must crop the selected pixels, never the neighboring tile.
- (void)testRetinaSelectionFlattenerFallbackKeepsTheSelectedPixels {
    NSImage *whole = [self retinaSelectionTiles];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.selectionOnly = YES;
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    STPrintView *view = [[STPrintView alloc] initWithLayout:layout image:whole];
    __block NSRect sourceDuringFlatten = NSZeroRect, clipAsked = NSZeroRect;
    STPrintViewTakeOptions(view, options, whole, NSMakeRect(10, 5, 10, 5), ^NSImage *(NSUInteger scale, NSRect clip) {
        (void)scale;
        sourceDuringFlatten = layout.sourceRect;
        clipAsked = clip;
        return nil;
    });
    XCTAssertTrue(NSEqualRects(sourceDuringFlatten, NSMakeRect(20, 10, 20, 10)), @"source=%@", NSStringFromRect(sourceDuringFlatten));
    XCTAssertTrue(NSEqualRects(clipAsked, NSMakeRect(10, 5, 10, 5)), @"clip=%@", NSStringFromRect(clipAsked));
    XCTAssertTrue(NSEqualSizes(STPrintImagePixelSize(view.image), NSMakeSize(20, 10)), @"pixels=%@", NSStringFromSize(STPrintImagePixelSize(view.image)));
    NSBitmapImageRep *cropped = (NSBitmapImageRep *)view.image.representations.firstObject;
    NSColor *sample = [[cropped colorAtX:5 y:5] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    NSColor *expected = [[NSColor colorWithCalibratedRed:1.0 / 3.0 green:1.0 / 3.0 blue:1.0 / 3.0 alpha:1]
                         colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    XCTAssertEqualWithAccuracy(sample.redComponent, expected.redComponent, 0.03);
    XCTAssertEqualWithAccuracy(sample.greenComponent, expected.greenComponent, 0.03);
    XCTAssertEqualWithAccuracy(sample.blueComponent, expected.blueComponent, 0.03);
}

- (void)testOneXSelectionKeepsItsPixelRect {
    NSImage *whole = [self checkerboardImageWithSize:NSMakeSize(40, 20)];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.selectionOnly = YES;
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    STConfigurePrintLayout(layout, options, whole, NSMakeRect(10, 5, 10, 5));
    XCTAssertTrue(NSEqualRects(layout.sourceRect, NSMakeRect(10, 5, 10, 5)));
}

- (void)testRetinaSelectionRoundsOutwardAndClipsToImage {
    NSImage *whole = [self retinaSelectionTiles];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.selectionOnly = YES;
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    STConfigurePrintLayout(layout, options, whole, NSMakeRect(38.25, 18.25, 10, 10));
    XCTAssertTrue(NSEqualRects(layout.sourceRect, NSMakeRect(76, 36, 4, 4)), @"source=%@", NSStringFromRect(layout.sourceRect));
}

- (void)testRetinaFlattenerReceivesPointClipAndKeepsPrintedResolution {
    NSImage *whole = [self retinaSelectionTiles];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.selectionOnly = YES;
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    STPrintView *view = [[STPrintView alloc] initWithLayout:layout image:whole];
    __block NSRect clipAsked = NSZeroRect;
    STPrintViewTakeOptions(view, options, whole, NSMakeRect(10, 5, 10, 5), ^NSImage *(NSUInteger scale, NSRect clip) {
        (void)scale;
        clipAsked = clip;
        return STPrintImageCrop(whole, NSMakeRect(20, 10, 20, 10));
    });
    XCTAssertTrue(NSEqualRects(clipAsked, NSMakeRect(10, 5, 10, 5)));
    XCTAssertTrue(NSEqualSizes(STPrintImagePixelSize(view.image), NSMakeSize(20, 10)));
    XCTAssertEqualWithAccuracy(layout.pixelsPerInch, 144.0, 0.001);
}

/// The flattener is asked for the layout's scale and the selection's rect, and the layout counts the
/// printed image's pixels at that resolution; one that fails leaves the cropped on-screen image.
- (void)testTheFlattenerSetsTheResolution {
    NSImage *whole = [self checkerboardImageWithSize:NSMakeSize(400, 200)];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.fit = STPrintFitActualSize;
    options.selectionOnly = YES;
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.paperSize = NSMakeSize(612, 792);
    STPrintView *view = [[STPrintView alloc] initWithLayout:layout image:whole];
    __block NSUInteger askedScale = 0;
    __block NSRect askedClip = NSZeroRect;
    STPrintViewTakeOptions(view, options, whole, NSMakeRect(50, 40, 100, 80), ^NSImage *(NSUInteger scale, NSRect clip) {
        askedScale = scale;
        askedClip = clip;
        NSImage *image = [self checkerboardImageWithSize:NSMakeSize(clip.size.width * scale, clip.size.height * scale)];
        image.size = clip.size;
        return image;
    });
    XCTAssertEqual(askedScale, (NSUInteger)4, @"300 dpi of a 72 ppi image");
    XCTAssertTrue(NSEqualRects(askedClip, NSMakeRect(50, 40, 100, 80)));
    XCTAssertTrue(NSEqualRects(layout.sourceRect, NSMakeRect(0, 0, 400, 320)));
    XCTAssertEqualWithAccuracy(layout.pixelsPerInch, 288.0, 0.001);

    STPrintViewTakeOptions(view, options, whole, NSMakeRect(50, 40, 100, 80), ^NSImage *(NSUInteger scale, NSRect clip) {
        (void)scale;
        (void)clip;
        return nil;
    });
    XCTAssertTrue(NSEqualRects(layout.sourceRect, NSMakeRect(0, 0, 100, 80)));
    XCTAssertEqualWithAccuracy(layout.pixelsPerInch, 72.0, 0.001);
}

@end
#endif
