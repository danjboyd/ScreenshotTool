#import "STPrintPage.h"
#include <math.h>

NSSize STPrintImagePixelSize(NSImage *image) {
    NSSize pixels = NSZeroSize;
    for (NSImageRep *rep in image.representations) {
        if (rep.pixelsWide > 0 && rep.pixelsHigh > 0 && (CGFloat)rep.pixelsWide * rep.pixelsHigh > pixels.width * pixels.height) {
            pixels = NSMakeSize(rep.pixelsWide, rep.pixelsHigh);
        }
    }
    return pixels.width > 0.0 ? pixels : image.size;
}

const CGFloat STPrintDefaultMargin = 36.0;

void STConfigurePrintLayout(STPrintLayout *layout, STPrintOptions *options, NSImage *image, NSRect selection) {
    NSSize pixels = STPrintImagePixelSize(image);
    NSRect whole = NSMakeRect(0.0, 0.0, pixels.width, pixels.height);
    NSRect source = options.selectionOnly ? NSIntersectionRect(selection, whole) : whole;
    layout.sourceRect = NSIsEmptyRect(source) ? whole : source;
#if defined(GNUSTEP)
    layout.pixelsPerInch = image.size.width > 0.0 && fabs(image.size.width - pixels.width) > 0.5
                               ? 72.0 * pixels.width / image.size.width
                               : STPrintDefaultPixelsPerInch;
#else
    layout.pixelsPerInch = image.size.width > 0.0 ? 72.0 * pixels.width / image.size.width : 72.0;
#endif
    [options applyToLayout:layout];
}

BOOL STDrawPrintPage(STPrintLayout *layout, NSUInteger page, NSImage *image, BOOL flipped) {
    NSRect source = [layout sourceRectForPage:page];
    NSRect target = [layout pageRectForPage:page];
    NSSize pixels = STPrintImagePixelSize(image);
    NSSize points = image.size;
    if (NSIsEmptyRect(source) || NSIsEmptyRect(target) || !(pixels.width > 0.0) || !(pixels.height > 0.0) ||
        !(points.width > 0.0) || !(points.height > 0.0)) {
        return NO;
    }

    // The layout's pixels, top-left origin, to the image's own points, bottom-left origin.
    CGFloat xScale = points.width / pixels.width;
    CGFloat yScale = points.height / pixels.height;
    NSRect from = NSMakeRect(NSMinX(source) * xScale, (pixels.height - NSMaxY(source)) * yScale,
                             NSWidth(source) * xScale, NSHeight(source) * yScale);

    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];
    if (flipped) {
        // Drawn as on an unflipped sheet. drawInRect:fromRect:… ignores a flipped context, so a
        // flipped view would get the image upside down; turning the sheet back avoids relying on
        // respectFlipped:, which each platform reads from its context differently.
        NSAffineTransform *unflip = [NSAffineTransform transform];
        [unflip translateXBy:0.0 yBy:layout.orientedPaperSize.height];
        [unflip scaleXBy:1.0 yBy:-1.0];
        [unflip concat];
    }
    NSRect to = NSMakeRect(NSMinX(target), layout.orientedPaperSize.height - NSMaxY(target),
                           NSWidth(target), NSHeight(target));
    NSRectClip(to);
    [context setImageInterpolation:NSImageInterpolationHigh];
    [image drawInRect:to fromRect:from operation:NSCompositeSourceOver fraction:1.0];
    [context restoreGraphicsState];
    return YES;
}
