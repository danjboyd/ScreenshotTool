#import "STPrintView.h"
#import "STPrintPage.h"

#if !defined(GNUSTEP)
#import "STPrintVectorScene.h"

STPrintMargins STPrinterMarginsForPrintInfo(NSPrintInfo *printInfo) {
    NSPrintInfo *portrait = [printInfo copy];
    portrait.orientation = NSPaperOrientationPortrait;
    NSSize paper = portrait.paperSize;
    NSRect bounds = portrait.imageablePageBounds;
    if (NSIsEmptyRect(bounds)) {
        return STPrintMarginsMake(0, 0, 0, 0);
    }
    // imageablePageBounds has a bottom-left origin.
    return STPrintMarginsMake(MAX(0.0, paper.height - NSMaxY(bounds)), MAX(0.0, NSMinX(bounds)),
                              MAX(0.0, NSMinY(bounds)), MAX(0.0, paper.width - NSMaxX(bounds)));
}

void STPreparePrintInfo(NSPrintInfo *printInfo, STPrintLayout *layout) {
    printInfo.orientation = layout.resolvedOrientation == STPrintOrientationLandscape
        ? NSPaperOrientationLandscape : NSPaperOrientationPortrait;
    printInfo.topMargin = 0.0;
    printInfo.leftMargin = 0.0;
    printInfo.bottomMargin = 0.0;
    printInfo.rightMargin = 0.0;
    printInfo.horizontalPagination = NSPrintingPaginationModeClip;
    printInfo.verticalPagination = NSPrintingPaginationModeClip;
    printInfo.horizontallyCentered = NO;
    printInfo.verticallyCentered = NO;
    printInfo.scalingFactor = 1.0;
}

NSImage *STPrintImageCrop(NSImage *image, NSRect rect) {
    NSSize pixels = STPrintImagePixelSize(image);
    NSRect integral = NSIntersectionRect(NSIntegralRect(rect), NSMakeRect(0, 0, pixels.width, pixels.height));
    CGImageRef whole = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (NSIsEmptyRect(integral) || !whole || CGImageGetWidth(whole) != (size_t)pixels.width) {
        return nil;
    }
    CGImageRef part = CGImageCreateWithImageInRect(whole, NSRectToCGRect(integral));
    if (!part) {
        return nil;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:part];
    CGImageRelease(part);
    CGFloat pointsPerPixel = image.size.width / pixels.width;
    NSSize points = NSMakeSize(NSWidth(integral) * pointsPerPixel, NSHeight(integral) * pointsPerPixel);
    rep.size = points;
    NSImage *cropped = [[NSImage alloc] initWithSize:points];
    [cropped addRepresentation:rep];
    return cropped;
}

void STPrintViewTakeOptions(STPrintView *view, STPrintOptions *options, NSImage *wholeImage, NSRect selection,
                            STPrintFlattener flattener) {
    view.vectorScene = nil;
    STPrintLayout *layout = view.layout;
    // The layout from the on-screen flatten: the source (all of it or the selection), the image's
    // resolution (72 ppi a point on macOS, so a Retina capture is 144) and the options.
    STConfigurePrintLayout(layout, options, wholeImage, selection);
    if (options.selectionOnly && NSIsEmptyRect(layout.sourceRect)) return;
    NSRect keep = options.selectionOnly ? layout.sourceRect : NSZeroRect;
    NSRect whole = NSMakeRect(0, 0, STPrintImagePixelSize(wholeImage).width, STPrintImagePixelSize(wholeImage).height);
    if (NSEqualRects(keep, whole)) {
        keep = NSZeroRect;
    }

    NSUInteger scale = [layout flattenScaleForImagePixelSize:STPrintImagePixelSize(wholeImage)];
    NSImage *printed = flattener ? flattener(scale, keep) : nil;
    if (!printed) {
        scale = 1;
        printed = NSIsEmptyRect(keep) ? wholeImage : STPrintImageCrop(wholeImage, keep);
    }
    if (!printed) {
        // Nothing to print that leaves the rest out: print nothing rather than the whole image.
        layout.sourceRect = NSZeroRect;
        return;
    }
    NSSize pixels = STPrintImagePixelSize(printed);
    view.image = printed;
    layout.sourceRect = NSMakeRect(0, 0, pixels.width, pixels.height);
    layout.pixelsPerInch = layout.pixelsPerInch * scale;
}

@interface STPrintView ()
@property (nonatomic, strong, nullable) NSImage *tileImage;
@property (nonatomic, weak, nullable) NSImage *tileSourceImage;
@property (nonatomic) NSRect tileSource;
@end

@implementation STPrintView

- (instancetype)initWithLayout:(STPrintLayout *)layout image:(NSImage *)image {
    NSSize paper = layout.orientedPaperSize;
    self = [super initWithFrame:NSMakeRect(0, 0, paper.width, paper.height)];
    if (self) {
        _layout = layout;
        _image = image;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

- (void)takePaperFromPrintInfo:(NSPrintInfo *)printInfo {
    STPrintLayout *layout = self.layout;
    layout.paperSize = printInfo.paperSize;
    layout.printerMargins = STPrinterMarginsForPrintInfo(printInfo);
    STPrintOrientation panel = printInfo.orientation == NSPaperOrientationLandscape
        ? STPrintOrientationLandscape : STPrintOrientationPortrait;
    BOOL turned = panel != layout.resolvedOrientation;
    if (turned) {
        layout.orientation = panel;
    }
    NSSize paper = layout.orientedPaperSize;
    [self setFrameSize:paper];
    if (turned && self.printInfoChoseOrientation) {
        self.printInfoChoseOrientation(panel);
    }
}

- (BOOL)knowsPageRange:(NSRangePointer)range {
    // The panel may have changed the paper or turned the sheet since the last pagination.
    NSPrintOperation *operation = [NSPrintOperation currentOperation];
    if (operation && operation.view == self) {
        [self takePaperFromPrintInfo:operation.printInfo];
    }
    // AppKit counts pages from 1. A layout with no pages prints nothing.
    *range = NSMakeRange(1, self.layout.pageCount);
    return YES;
}

/// Every page is the whole sheet: drawRect: picks the page's part of the image.
- (NSRect)rectForPage:(NSInteger)page {
    (void)page;
    NSSize paper = self.layout.orientedPaperSize;
    return NSMakeRect(0, 0, paper.width, paper.height);
}

- (NSUInteger)pageToDraw {
    NSPrintOperation *operation = [NSPrintOperation currentOperation];
    if (operation && operation.view == self && operation.currentPage > 0) {
        return (NSUInteger)operation.currentPage - 1;
    }
    return self.page;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSUInteger page = [self pageToDraw];
    STPrintLayout *layout = self.layout;
    STPrintVectorScene *scene = self.vectorScene;
    if (scene && page == 0 && layout.pageCount == 1) {
        NSSize pixels = STPrintImagePixelSize(self.image);
        NSRect source = [layout sourceRectForPage:0];
        NSRect target = [layout pageRectForPage:0];
        if (NSEqualRects(source, NSMakeRect(0, 0, pixels.width, pixels.height)) &&
            !NSIsEmptyRect(target)) {
            NSGraphicsContext *context = [NSGraphicsContext currentContext];
            [context saveGraphicsState];
            NSAffineTransform *unflip = [NSAffineTransform transform];
            [unflip translateXBy:0.0 yBy:layout.orientedPaperSize.height];
            [unflip scaleXBy:1.0 yBy:-1.0];
            [unflip concat];
            NSRect to = NSMakeRect(NSMinX(target), layout.orientedPaperSize.height - NSMaxY(target),
                                   NSWidth(target), NSHeight(target));
            BOOL drew = STDrawPrintVectorScene(scene.redactedBase,
                NSMakeRect(0, 0, scene.canvasSize.width, scene.canvasSize.height),
                scene.canvasSize, to, scene.strokes, scene.texts);
            [context restoreGraphicsState];
            if (drew) return;
        }
    }
    // A page of several draws only its own part of the image (perf, 0.4.0): drawn whole and clipped,
    // Quartz hashes and unpacks all of the image again for each page of a PDF or a printout.
    if (layout.pageCount > 1) {
        NSRect source = [layout sourceRectForPage:page];
        NSRect target = [layout pageRectForPage:page];
        // The last page's tile is kept for the preview, which draws the same page again and again.
        BOOL kept = self.tileImage && self.tileSourceImage == self.image && NSEqualRects(self.tileSource, source);
        NSImage *tile = kept ? self.tileImage : STPrintImageCrop(self.image, source);
        if (tile && NSEqualSizes(STPrintImagePixelSize(tile), NSIntegralRect(source).size) && NSEqualRects(NSIntegralRect(source), source)) {
            self.tileImage = tile;
            self.tileSourceImage = self.image;
            self.tileSource = source;
            NSGraphicsContext *context = [NSGraphicsContext currentContext];
            [context saveGraphicsState];
            // As STDrawPrintPage draws: on the sheet unflipped, clipped to the page's printed part.
            NSAffineTransform *unflip = [NSAffineTransform transform];
            [unflip translateXBy:0.0 yBy:layout.orientedPaperSize.height];
            [unflip scaleXBy:1.0 yBy:-1.0];
            [unflip concat];
            NSRect to = NSMakeRect(NSMinX(target), layout.orientedPaperSize.height - NSMaxY(target), NSWidth(target), NSHeight(target));
            NSRectClip(to);
            [context setImageInterpolation:NSImageInterpolationHigh];
            [tile drawInRect:to fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
            [context restoreGraphicsState];
            return;
        }
    }
    STDrawPrintPage(layout, page, self.image, YES);
}

@end

#endif
