/* Source-only feasibility probe for a redacted raster plus vector annotation PDF scene. */
#if !defined(GNUSTEP)
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import "MarkupStroke.h"
#import "MarkupText.h"
#import "STPrintVectorScene.h"

@interface STVectorProofView : NSView
@property (nonatomic, strong) NSImage *base;
@property (nonatomic, strong) NSArray<MarkupStroke *> *strokes;
@property (nonatomic, strong) NSArray<MarkupText *> *texts;
@end

@implementation STVectorProofView
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    STDrawPrintVectorScene(self.base, NSMakeRect(40, 20, 80, 60), NSMakeSize(200, 120),
                           NSMakeRect(20, 20, 160, 120), self.strokes, self.texts);
}
@end

typedef struct {
    NSUInteger strokes;
    NSUInteger textBegins;
    NSUInteger images;
} STPDFOperators;

static void STCountStroke(CGPDFScannerRef scanner, void *context) {
    (void)scanner;
    ((STPDFOperators *)context)->strokes++;
}
static void STCountText(CGPDFScannerRef scanner, void *context) {
    (void)scanner;
    ((STPDFOperators *)context)->textBegins++;
}
static void STCountImage(CGPDFScannerRef scanner, void *context) {
    (void)scanner;
    ((STPDFOperators *)context)->images++;
}

@interface PrintVectorFeasibilityProbeTests : XCTestCase
@end

@implementation PrintVectorFeasibilityProbeTests

/// A physical 80x60 selection crop. The black patch stands in for pixels already destroyed by the
/// canvas redaction pass; no full source capture or unredacted pixels enter the PDF scene.
- (NSImage *)redactedSelectionBase {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:80 pixelsHigh:60 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
        isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    for (NSInteger y = 0; y < 60; y++) {
        for (NSInteger x = 0; x < 80; x++) {
            [rep setColor:(x >= 10 && x < 35 && y >= 10 && y < 30)
                          ? [NSColor blackColor] : [NSColor whiteColor] atX:x y:y];
        }
    }
    rep.size = NSMakeSize(80, 60);
    NSImage *image = [[NSImage alloc] initWithSize:rep.size];
    [image addRepresentation:rep];
    return image;
}

- (void)testPDFKeepsCroppedRedactedImageAndRealVectorModels {
    MarkupStroke *rectangle = [[MarkupStroke alloc] initWithType:MarkupStrokeTypeRectangle
        color:[NSColor redColor] lineWidth:2.0];
    [rectangle setStartPoint:NSMakePoint(65, 45) endPoint:NSMakePoint(95, 65)];
    MarkupText *label = [[MarkupText alloc] initWithText:@"VECTOR"
        font:[NSFont systemFontOfSize:14] color:[NSColor blueColor]
        origin:NSMakePoint(50, 30) boxSize:NSMakeSize(70, 20)];
    MarkupText *outside = [[MarkupText alloc] initWithText:@"OUTSIDE"
        font:[NSFont systemFontOfSize:14] color:[NSColor blueColor]
        origin:NSMakePoint(150, 30) boxSize:NSMakeSize(70, 20)];
    STVectorProofView *view = [[STVectorProofView alloc] initWithFrame:NSMakeRect(0, 0, 200, 160)];
    view.base = [self redactedSelectionBase];
    view.strokes = @[ rectangle ];
    view.texts = @[ label, outside ];
    NSData *data = [view dataWithPDFInsideRect:view.bounds];
    XCTAssertGreaterThan(data.length, 0U);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    XCTAssertNotEqual(document, NULL);
    if (!document) { return; }
    XCTAssertEqual(CGPDFDocumentGetNumberOfPages(document), 1U);
    CGPDFPageRef page = CGPDFDocumentGetPage(document, 1);
    CGPDFDictionaryRef resources = NULL, xobjects = NULL, fonts = NULL;
    XCTAssertTrue(CGPDFDictionaryGetDictionary(CGPDFPageGetDictionary(page), "Resources", &resources));
    XCTAssertTrue(CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects));
    XCTAssertTrue(CGPDFDictionaryGetDictionary(resources, "Font", &fonts));
    XCTAssertGreaterThan(CGPDFDictionaryGetCount(xobjects), 0U);
    XCTAssertGreaterThan(CGPDFDictionaryGetCount(fonts), 0U);

    STPDFOperators counts = {0};
    CGPDFOperatorTableRef table = CGPDFOperatorTableCreate();
    CGPDFOperatorTableSetCallback(table, "S", STCountStroke);
    CGPDFOperatorTableSetCallback(table, "BT", STCountText);
    CGPDFOperatorTableSetCallback(table, "Do", STCountImage);
    CGPDFContentStreamRef stream = CGPDFContentStreamCreateWithPage(page);
    CGPDFScannerRef scanner = CGPDFScannerCreate(stream, table, &counts);
    XCTAssertTrue(CGPDFScannerScan(scanner));
    XCTAssertGreaterThan(counts.images, 0U);
    XCTAssertGreaterThan(counts.strokes, 0U);
    XCTAssertGreaterThan(counts.textBegins, 0U);
    CGPDFScannerRelease(scanner);
    CGPDFContentStreamRelease(stream);
    CGPDFOperatorTableRelease(table);
    CGPDFDocumentRelease(document);
}

- (void)testRefusesUncroppedBase {
    NSImage *full = [[NSImage alloc] initWithSize:NSMakeSize(200, 120)];
    XCTAssertFalse(STDrawPrintVectorScene(full, NSMakeRect(40, 20, 80, 60),
        NSMakeSize(200, 120), NSMakeRect(0, 0, 80, 60), @[], @[]));
}

- (void)testPartialTextDoesNotLeaveHiddenGlyphsInPDF {
    MarkupText *partial = [[MarkupText alloc] initWithText:@"HIDDEN-BEYOND-SELECTION"
        font:[NSFont systemFontOfSize:14] color:[NSColor blueColor]
        origin:NSMakePoint(110, 30) boxSize:NSMakeSize(90, 20)];
    STVectorProofView *view = [[STVectorProofView alloc] initWithFrame:NSMakeRect(0, 0, 200, 160)];
    view.base = [self redactedSelectionBase];
    view.strokes = @[];
    view.texts = @[ partial ];
    NSData *data = [view dataWithPDFInsideRect:view.bounds];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    XCTAssertNotEqual(document, NULL);
    if (!document) { return; }
    STPDFOperators counts = {0};
    CGPDFOperatorTableRef table = CGPDFOperatorTableCreate();
    CGPDFOperatorTableSetCallback(table, "BT", STCountText);
    CGPDFContentStreamRef stream = CGPDFContentStreamCreateWithPage(CGPDFDocumentGetPage(document, 1));
    CGPDFScannerRef scanner = CGPDFScannerCreate(stream, table, &counts);
    XCTAssertTrue(CGPDFScannerScan(scanner));
    XCTAssertEqual(counts.textBegins, 0U, @"Clipping would still embed hidden characters");
    CGPDFScannerRelease(scanner);
    CGPDFContentStreamRelease(stream);
    CGPDFOperatorTableRelease(table);
    CGPDFDocumentRelease(document);
}

@end
#endif
