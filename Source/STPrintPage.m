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

NSRect STPrintPixelRectForPointRect(NSImage *image, NSRect rect) {
    NSSize points = image.size;
    NSSize pixels = STPrintImagePixelSize(image);
    if (!(points.width > 0.0) || !(points.height > 0.0) || !(pixels.width > 0.0) || !(pixels.height > 0.0) ||
        NSIsEmptyRect(rect)) return NSZeroRect;
    NSRect clipped = NSIntersectionRect(rect, NSMakeRect(0, 0, points.width, points.height));
    if (NSIsEmptyRect(clipped)) return NSZeroRect;
    CGFloat sx = pixels.width / points.width;
    CGFloat sy = pixels.height / points.height;
    NSRect scaled = NSMakeRect(NSMinX(clipped) * sx, NSMinY(clipped) * sy,
                               NSWidth(clipped) * sx, NSHeight(clipped) * sy);
    return NSIntersectionRect(NSIntegralRect(scaled), NSMakeRect(0, 0, pixels.width, pixels.height));
}

NSRect STPrintPointRectForPixelRect(NSImage *image, NSRect rect) {
    NSSize points = image.size;
    NSSize pixels = STPrintImagePixelSize(image);
    if (!(points.width > 0.0) || !(points.height > 0.0) || !(pixels.width > 0.0) || !(pixels.height > 0.0) ||
        NSIsEmptyRect(rect)) return NSZeroRect;
    return NSMakeRect(NSMinX(rect) * points.width / pixels.width, NSMinY(rect) * points.height / pixels.height,
                      NSWidth(rect) * points.width / pixels.width, NSHeight(rect) * points.height / pixels.height);
}

const CGFloat STPrintDefaultMargin = 36.0;

void STConfigurePrintLayout(STPrintLayout *layout, STPrintOptions *options, NSImage *image, NSRect selection) {
    NSSize pixels = STPrintImagePixelSize(image);
    NSRect whole = NSMakeRect(0.0, 0.0, pixels.width, pixels.height);
    NSRect source = options.selectionOnly ? STPrintPixelRectForPointRect(image, selection) : whole;
    // Selection-only intent must never become a whole-image print if the selection disappears.
    // Empty and out-of-bounds selections leave an empty layout, with no printable pages.
    layout.sourceRect = source;
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
