/* Offscreen Cocoa PDF probe for the redaction-first, whole-image vector print slice. */
#if !defined(GNUSTEP)
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <string.h>
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "MarkupText.h"
#import "STPrintVectorScene.h"
#import "STPrintView.h"
#import "STPrintPage.h"

extern BOOL STPixelatePrintRedactions(NSBitmapImageRep *base, NSArray<MarkupStroke *> *redactions);

@interface STNoBitmapBytesRep : NSBitmapImageRep
@property (nonatomic) BOOL denyBytes;
@end
@implementation STNoBitmapBytesRep
- (unsigned char *)bitmapData { return self.denyBytes ? NULL : [super bitmapData]; }
@end

@interface STFailingSelectionCropCanvas : ScreenshotCanvasView
@end
@implementation STFailingSelectionCropCanvas
- (NSBitmapImageRep *)cropFlattenedBitmap:(NSBitmapImageRep *)bitmap
                               withinRect:(NSRect)rect canvasSize:(NSSize)size {
    (void)bitmap; (void)rect; (void)size;
    return nil;
}
@end

typedef struct { NSUInteger image, path, text; } STVectorOperators;
typedef struct {
    NSUInteger count, matchingCount;
    NSInteger width, height, expectedWidth, expectedHeight;
} STVectorImages;
typedef struct { STVectorImages *images; NSUInteger depth; } STVectorImageWalk;
static void STCollectVectorImages(CGPDFDictionaryRef resources, STVectorImages *images, NSUInteger depth);
static void STVectorImage(CGPDFScannerRef scanner, void *info) { (void)scanner; ((STVectorOperators *)info)->image++; }
static void STVectorPath(CGPDFScannerRef scanner, void *info) { (void)scanner; ((STVectorOperators *)info)->path++; }
static void STVectorText(CGPDFScannerRef scanner, void *info) { (void)scanner; ((STVectorOperators *)info)->text++; }
static void STVectorXObject(const char *name, CGPDFObjectRef object, void *info) {
    (void)name;
    CGPDFStreamRef stream = NULL;
    if (!CGPDFObjectGetValue(object, kCGPDFObjectTypeStream, &stream)) return;
    CGPDFDictionaryRef dictionary = CGPDFStreamGetDictionary(stream);
    const char *subtype = NULL;
    if (!CGPDFDictionaryGetName(dictionary, "Subtype", &subtype)) return;
    STVectorImageWalk *walk = info;
    if (strcmp(subtype, "Form") == 0 && walk->depth < 8) {
        CGPDFDictionaryRef resources = NULL;
        if (CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources))
            STCollectVectorImages(resources, walk->images, walk->depth + 1);
    } else if (strcmp(subtype, "Image") == 0) {
        CGPDFInteger width = 0, height = 0;
        CGPDFDictionaryGetInteger(dictionary, "Width", &width);
        CGPDFDictionaryGetInteger(dictionary, "Height", &height);
        walk->images->count++;
        walk->images->width = (NSInteger)width;
        walk->images->height = (NSInteger)height;
        if ((NSInteger)width == walk->images->expectedWidth &&
            (NSInteger)height == walk->images->expectedHeight) walk->images->matchingCount++;
    }
}
static void STCollectVectorImages(CGPDFDictionaryRef resources, STVectorImages *images, NSUInteger depth) {
    CGPDFDictionaryRef xobjects = NULL;
    if (!CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects)) return;
    STVectorImageWalk walk = { images, depth };
    CGPDFDictionaryApplyFunction(xobjects, STVectorXObject, &walk);
}

@interface PrintVectorIntegrationProbeTests : XCTestCase
@end

@implementation PrintVectorIntegrationProbeTests

- (NSImage *)checkerboardWithPixelScale:(NSInteger)pixelScale {
    NSInteger width = 200 * pixelScale, height = 120 * pixelScale;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
        isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:width * 4 bitsPerPixel:32];
    for (NSInteger y = 0; y < height; y++) {
        unsigned char *row = rep.bitmapData + rep.bytesPerRow * y;
        for (NSInteger x = 0; x < width; x++) {
            unsigned char *p = row + x * 4;
            p[0] = p[1] = p[2] = p[3] = 255;
            if (x >= 20 * pixelScale && x < 60 * pixelScale &&
                y >= 20 * pixelScale && y < 40 * pixelScale) {
                BOOL red = ((x / (2 * pixelScale)) + (y / (2 * pixelScale))) % 2 == 0;
                p[0] = red ? 255 : 0;
                p[1] = red ? 0 : 255;
                p[2] = 0;
            }
        }
    }
    rep.size = NSMakeSize(200, 120);
    NSImage *image = [[NSImage alloc] initWithSize:rep.size];
    [image addRepresentation:rep];
    return image;
}

- (ScreenshotCanvasView *)canvasWithPixelScale:(NSInteger)scale {
    [NSApplication sharedApplication];
    ScreenshotCanvasView *canvas = [[ScreenshotCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 220, 140)];
    [canvas loadImage:[self checkerboardWithPixelScale:scale]];
    return canvas;
}

- (void)testGrayscaleRedactionIsDestroyedBeforeVectorEmbedding {
    NSBitmapImageRep *gray = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:200 pixelsHigh:120 bitsPerSample:8 samplesPerPixel:1 hasAlpha:NO
        isPlanar:NO colorSpaceName:NSDeviceWhiteColorSpace bytesPerRow:200 bitsPerPixel:8];
    XCTAssertNotNil(gray);
    for (NSInteger y = 0; y < 120; y++) {
        for (NSInteger x = 0; x < 200; x++) {
            gray.bitmapData[y * gray.bytesPerRow + x] = ((x / 2 + y / 2) % 2) ? 0 : 255;
        }
    }
    gray.size = NSMakeSize(200, 120);
    NSImage *image = [[NSImage alloc] initWithSize:gray.size];
    [image addRepresentation:gray];
    ScreenshotCanvasView *canvas = [[ScreenshotCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 220, 140)];
    [canvas loadImage:image];
    [canvas addRedactionsInImageRects:@[[NSValue valueWithRect:NSMakeRect(20, 20, 40, 20)]]
                              actionName:@"Redact"];
    STPrintVectorScene *scene = [canvas vectorSceneForPrint];
    XCTAssertNotNil(scene);
    if (!scene) return;
    NSBitmapImageRep *base = (NSBitmapImageRep *)scene.redactedBase.representations.firstObject;
    XCTAssertEqual(base.samplesPerPixel, 4);
    for (NSInteger y = 20; y < 40; y++) {
        for (NSInteger x = 20; x < 60; x++) {
            unsigned char *pixel = base.bitmapData + y * base.bytesPerRow + x * 4;
            XCTAssertGreaterThan(pixel[0], 60);
            XCTAssertLessThan(pixel[0], 200);
        }
    }
}

- (void)testUnavailableBitmapBytesRefuseRedactionAndPrintScene {
    STNoBitmapBytesRep *rep = [[STNoBitmapBytesRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:200 pixelsHigh:120 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
        isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:800 bitsPerPixel:32];
    XCTAssertNotNil(rep);
    MarkupStroke *redaction = [[MarkupStroke alloc] initWithType:MarkupStrokeTypeRedact
        color:NSColor.blackColor lineWidth:1];
    [redaction setStartPoint:NSMakePoint(20, 20) endPoint:NSMakePoint(60, 40)];
    rep.denyBytes = YES;
    XCTAssertFalse(STPixelatePrintRedactions(rep, @[redaction]), @"unavailable bytes cannot be covered by a PDF overlay");

    rep.size = NSMakeSize(200, 120);
    NSImage *image = [[NSImage alloc] initWithSize:rep.size];
    [image addRepresentation:rep];
    ScreenshotCanvasView *canvas = [[ScreenshotCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 220, 140)];
    [canvas loadImage:image];
    [[canvas valueForKey:@"strokes"] addObject:redaction];
    XCTAssertNil([canvas vectorSceneForPrint], @"a crop without bytes cannot produce an embedded print base");
}

- (void)testFailedSelectionCropNeverReturnsWholeImage {
    STFailingSelectionCropCanvas *canvas = [[STFailingSelectionCropCanvas alloc]
        initWithFrame:NSMakeRect(0, 0, 220, 140)];
    [canvas loadImage:[self checkerboardWithPixelScale:1]];
    NSImage *whole = [canvas flattenedImage];
    XCTAssertNotNil(whole);
    XCTAssertTrue(NSEqualSizes(whole.size, NSMakeSize(200, 120)), @"no-selection path stays intact");
    [canvas setValue:@YES forKey:@"hasSelectionRect"];
    [canvas setValue:[NSValue valueWithRect:NSMakeRect(20, 20, 40, 20)] forKey:@"selectionRect"];
    XCTAssertNil([canvas flattenedImageForSelection], @"failed crop must not expose the full image");
    [canvas setValue:[NSValue valueWithRect:NSMakeRect(250, 20, 40, 20)] forKey:@"selectionRect"];
    XCTAssertNil([canvas flattenedImageForSelection], @"out-of-bounds selection must also fail closed");
}

- (void)testOutOfBoundsPrintSelectionCannotReturnWholeImage {
    ScreenshotCanvasView *canvas = [self canvasWithPixelScale:1];
    NSRect outside = NSMakeRect(250, 20, 40, 20);
    XCTAssertNil([canvas flattenedImageForPrintAtScale:1 withinRect:outside]);
    XCTAssertNil([canvas flattenedImageForPrintAtScale:2 withinRect:outside]);

    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.paperSize = NSMakeSize(612, 792);
    STPrintView *view = [[STPrintView alloc] initWithLayout:layout image:[canvas flattenedImage]];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.selectionOnly = YES;
    STPrintViewTakeOptions(view, options, [canvas flattenedImage], outside,
        ^NSImage *(NSUInteger scale, NSRect clip) {
            return [canvas flattenedImageForPrintAtScale:scale withinRect:clip];
        });
    XCTAssertTrue(NSIsEmptyRect(layout.sourceRect), @"invalid selection must make no printable pages");
    XCTAssertEqual(layout.pageCount, 0U);
}

- (NSData *)savedPDFOfView:(STPrintView *)view {
    NSPrintInfo *info = [[NSPrintInfo alloc] initWithDictionary:@{}];
    info.paperSize = view.layout.paperSize;
    STPreparePrintInfo(info, view.layout);
    [view setFrameSize:view.layout.orientedPaperSize];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"PrintVectorIntegration-%@.pdf", [NSUUID UUID].UUIDString]]];
    info.jobDisposition = NSPrintSaveJob;
    info.dictionary[NSPrintJobSavingURL] = url;
    NSPrintOperation *operation = [NSPrintOperation printOperationWithView:view printInfo:info];
    operation.showsPrintPanel = NO;
    operation.showsProgressPanel = NO;
    XCTAssertTrue([operation runOperation]);
    NSData *data = [NSData dataWithContentsOfURL:url] ?: [NSData data];
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    return data;
}

- (void)testRealRedactionBaseAndVectorPDF {
    ScreenshotCanvasView *canvas = [self canvasWithPixelScale:1];
    [canvas addRedactionsInImageRects:@[[NSValue valueWithRect:NSMakeRect(20, 20, 40, 20)]]
                              actionName:@"Redact"];
    MarkupStroke *rectangle = [[MarkupStroke alloc] initWithType:MarkupStrokeTypeRectangle
        color:NSColor.blueColor lineWidth:2];
    [rectangle setStartPoint:NSMakePoint(80, 30) endPoint:NSMakePoint(120, 65)];
    [[canvas valueForKey:@"strokes"] addObject:rectangle];
    MarkupText *label = [[MarkupText alloc] initWithText:@"VECTOR" font:[NSFont systemFontOfSize:14]
        color:NSColor.blackColor origin:NSMakePoint(100, 70) boxSize:NSMakeSize(70, 25)];
    [[canvas valueForKey:@"texts"] addObject:label];

    STPrintVectorScene *scene = [canvas vectorSceneForPrint];
    XCTAssertNotNil(scene);
    if (!scene) return;
    XCTAssertEqual(scene.strokes.count, 1U);
    XCTAssertEqual(scene.texts.count, 1U);
    NSBitmapImageRep *base = (NSBitmapImageRep *)scene.redactedBase.representations.firstObject;
    XCTAssertEqual(base.pixelsWide, 200);
    XCTAssertEqual(base.pixelsHigh, 120);
    NSUInteger secretPixels = 0;
    for (NSInteger y = 20; y < 40; y++) {
        for (NSInteger x = 20; x < 60; x++) {
            unsigned char *p = base.bitmapData + base.bytesPerRow * y + x * 4;
            if ((p[0] > 200 && p[1] < 60 && p[2] < 60) ||
                (p[1] > 200 && p[0] < 60 && p[2] < 60)) secretPixels++;
        }
    }
    XCTAssertEqual(secretPixels, 0U, @"redaction must destroy the checkerboard before PDF drawing");

    NSImage *whole = [canvas flattenedImage];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.paperSize = NSMakeSize(612, 792);
    layout.margins = STPrintMarginsMake(36, 36, 36, 36);
    STPrintView *view = [[STPrintView alloc] initWithLayout:layout image:whole];
    STPrintViewTakeOptions(view, options, whole, NSZeroRect,
        ^NSImage *(NSUInteger scale, NSRect clip) { return [canvas flattenedImageForPrintAtScale:scale withinRect:clip]; });
    XCTAssertEqual(layout.pageCount, 1U);
    view.vectorScene = scene;
    NSData *pdf = [self savedPDFOfView:view];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pdf);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    XCTAssertNotEqual(document, NULL);
    if (!document) return;
    XCTAssertEqual(CGPDFDocumentGetNumberOfPages(document), 1U);
    CGPDFPageRef page = CGPDFDocumentGetPage(document, 1);
    CGPDFDictionaryRef resources = NULL;
    XCTAssertTrue(CGPDFDictionaryGetDictionary(CGPDFPageGetDictionary(page), "Resources", &resources));
    STVectorImages images = {0};
    if (resources) STCollectVectorImages(resources, &images, 0);
    XCTAssertEqual(images.count, 1U, @"PDF should embed only the copied, redacted base");
    XCTAssertEqual(images.width, 200);
    XCTAssertEqual(images.height, 120);
    STVectorOperators operators = {0};
    CGPDFOperatorTableRef table = CGPDFOperatorTableCreate();
    CGPDFOperatorTableSetCallback(table, "Do", STVectorImage);
    CGPDFOperatorTableSetCallback(table, "S", STVectorPath);
    CGPDFOperatorTableSetCallback(table, "BT", STVectorText);
    CGPDFContentStreamRef stream = CGPDFContentStreamCreateWithPage(page);
    CGPDFScannerRef scanner = CGPDFScannerCreate(stream, table, &operators);
    XCTAssertTrue(CGPDFScannerScan(scanner));
    XCTAssertGreaterThan(operators.image, 0U);
    XCTAssertGreaterThan(operators.path, 0U);
    XCTAssertGreaterThan(operators.text, 0U);
    CGPDFScannerRelease(scanner);
    CGPDFContentStreamRelease(stream);
    CGPDFOperatorTableRelease(table);
    CGPDFDocumentRelease(document);
}

- (void)testRetinaSceneIsRefusedAndSelectionClearsVectorMode {
    ScreenshotCanvasView *retina = [self canvasWithPixelScale:2];
    XCTAssertNil([retina vectorSceneForPrint], @"Retina stays on the current raster route");
    NSImage *retinaWhole = [retina flattenedImage];
    STPrintLayout *retinaLayout = [[STPrintLayout alloc] init];
    retinaLayout.paperSize = NSMakeSize(612, 792);
    retinaLayout.margins = STPrintMarginsMake(36, 36, 36, 36);
    STPrintView *retinaView = [[STPrintView alloc] initWithLayout:retinaLayout image:retinaWhole];
    STPrintViewTakeOptions(retinaView, [[STPrintOptions alloc] init], retinaWhole, NSZeroRect,
        ^NSImage *(NSUInteger scale, NSRect clip) {
            return [retina flattenedImageForPrintAtScale:scale withinRect:clip];
        });
    XCTAssertNil(retinaView.vectorScene);
    XCTAssertGreaterThan([self savedPDFOfView:retinaView].length, 0U);

    ScreenshotCanvasView *canvas = [self canvasWithPixelScale:1];
    STPrintVectorScene *scene = [canvas vectorSceneForPrint];
    XCTAssertNotNil(scene);
    NSImage *whole = [canvas flattenedImage];
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.paperSize = NSMakeSize(612, 792);
    layout.margins = STPrintMarginsMake(36, 36, 36, 36);
    STPrintView *view = [[STPrintView alloc] initWithLayout:layout image:whole];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    STPrintFlattener flatten = ^NSImage *(NSUInteger scale, NSRect clip) {
        return [canvas flattenedImageForPrintAtScale:scale withinRect:clip];
    };
    STPrintViewTakeOptions(view, options, whole, NSZeroRect, flatten);
    view.vectorScene = scene;
    options.selectionOnly = YES;
    STPrintViewTakeOptions(view, options, whole, NSMakeRect(20, 20, 40, 20), flatten);
    XCTAssertNil(view.vectorScene);
    XCTAssertTrue(NSEqualSizes(view.image.size, NSMakeSize(40, 20)));
}

- (void)testPartiallyClippedMarkupFallsBackToRaster {
    ScreenshotCanvasView *canvas = [self canvasWithPixelScale:1];
    MarkupText *partial = [[MarkupText alloc] initWithText:@"PARTIAL" font:[NSFont systemFontOfSize:16]
        color:NSColor.blackColor origin:NSMakePoint(185, 90) boxSize:NSMakeSize(60, 25)];
    [[canvas valueForKey:@"texts"] addObject:partial];
    XCTAssertNil([canvas vectorSceneForPrint], @"hidden glyphs cannot enter a clipped vector PDF");
    XCTAssertNotNil([canvas flattenedImageForPrintAtScale:1 withinRect:NSZeroRect]);
}

- (void)testPartiallyClippedStrokeFallsBackToRaster {
    ScreenshotCanvasView *canvas = [self canvasWithPixelScale:1];
    MarkupStroke *rectangle = [[MarkupStroke alloc] initWithType:MarkupStrokeTypeRectangle
        color:NSColor.blueColor lineWidth:4];
    [rectangle setStartPoint:NSMakePoint(185, 30) endPoint:NSMakePoint(205, 60)];
    [[canvas valueForKey:@"strokes"] addObject:rectangle];
    XCTAssertNil([canvas vectorSceneForPrint], @"clipped vector strokes stay on the raster route");
    XCTAssertNotNil([canvas flattenedImageForPrintAtScale:1 withinRect:NSZeroRect]);
}

- (void)testMultiPagePDFUsesCroppedRasterTiles {
    ScreenshotCanvasView *canvas = [self canvasWithPixelScale:1];
    [canvas addRedactionsInImageRects:@[[NSValue valueWithRect:NSMakeRect(20, 20, 40, 20)]]
                              actionName:@"Redact"];
    STPrintVectorScene *scene = [canvas vectorSceneForPrint];
    XCTAssertNotNil(scene);
    NSImage *whole = [canvas flattenedImage];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.fit = STPrintFitActualSize;
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.paperSize = NSMakeSize(100, 100);
    layout.margins = STPrintMarginsMake(10, 10, 10, 10);
    STPrintView *view = [[STPrintView alloc] initWithLayout:layout image:whole];
    STPrintViewTakeOptions(view, options, whole, NSZeroRect,
        ^NSImage *(NSUInteger scale, NSRect clip) { return [canvas flattenedImageForPrintAtScale:scale withinRect:clip]; });
    XCTAssertGreaterThan(layout.pageCount, 1U);
    view.vectorScene = scene; // Exercise drawRect's page-count guard even if a caller attaches it.
    NSData *pdf = [self savedPDFOfView:view];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pdf);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    XCTAssertNotEqual(document, NULL);
    if (!document) return;
    XCTAssertEqual(CGPDFDocumentGetNumberOfPages(document), layout.pageCount);
    for (NSUInteger pageNumber = 1; pageNumber <= CGPDFDocumentGetNumberOfPages(document); pageNumber++) {
        CGPDFPageRef page = CGPDFDocumentGetPage(document, pageNumber);
        CGPDFDictionaryRef resources = NULL;
        XCTAssertTrue(CGPDFDictionaryGetDictionary(CGPDFPageGetDictionary(page), "Resources", &resources));
        STVectorImages images = {.expectedWidth = 200, .expectedHeight = 120};
        if (resources) STCollectVectorImages(resources, &images, 0);
        XCTAssertGreaterThan(images.count, 0U);
        XCTAssertEqual(images.matchingCount, 0U,
            @"page %lu must use a physical raster tile, not the full vector base", (unsigned long)pageNumber);
    }
    CGPDFDocumentRelease(document);
}

@end
#endif
