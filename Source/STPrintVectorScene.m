#if !defined(GNUSTEP)
#import "STPrintVectorScene.h"
#import "MarkupStroke.h"
#import "MarkupText.h"

@implementation STPrintVectorScene
- (instancetype)initWithRedactedBase:(NSImage *)base canvasSize:(NSSize)canvasSize
                            strokes:(NSArray<MarkupStroke *> *)strokes texts:(NSArray<MarkupText *> *)texts {
    self = [super init];
    if (self) {
        _redactedBase = base;
        _canvasSize = canvasSize;
        _strokes = [strokes copy];
        _texts = [texts copy];
    }
    return self;
}
@end

BOOL STDrawPrintVectorScene(NSImage *redactedBase, NSRect sourceRect, NSSize canvasSize,
                            NSRect targetRect, NSArray<MarkupStroke *> *strokes,
                            NSArray<MarkupText *> *texts) {
    if (NSIsEmptyRect(sourceRect) || NSIsEmptyRect(targetRect) ||
        !NSEqualSizes(redactedBase.size, sourceRect.size) ||
        !NSContainsRect(NSMakeRect(0, 0, canvasSize.width, canvasSize.height), sourceRect)) {
        return NO;
    }
    // A point-size-only match could still hide a full-resolution capture in the PDF object.
    BOOL hasCroppedRaster = NO;
    for (NSImageRep *rep in redactedBase.representations) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]] &&
            rep.pixelsWide == (NSInteger)NSWidth(sourceRect) &&
            rep.pixelsHigh == (NSInteger)NSHeight(sourceRect)) {
            hasCroppedRaster = YES;
        } else {
            return NO;
        }
    }
    if (!hasCroppedRaster) { return NO; }
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    if (!context) {
        return NO;
    }
    [context saveGraphicsState];
    NSRectClip(targetRect);
    // The only embedded raster is already redacted and physically cropped to the selection.
    [redactedBase drawInRect:targetRect fromRect:NSZeroRect
                   operation:NSCompositingOperationSourceOver fraction:1.0];

    CGFloat sx = NSWidth(targetRect) / NSWidth(sourceRect);
    CGFloat sy = NSHeight(targetRect) / NSHeight(sourceRect);
    NSAffineTransform *mapping = [NSAffineTransform transform];
    [mapping translateXBy:NSMinX(targetRect) - NSMinX(sourceRect) * sx
                      yBy:NSMinY(targetRect) - (canvasSize.height - NSMaxY(sourceRect)) * sy];
    [mapping scaleXBy:sx yBy:sy];
    [mapping concat];
    for (MarkupStroke *stroke in strokes) {
        if (stroke.type != MarkupStrokeTypeRedact && NSIntersectsRect([stroke bounds], sourceRect)) {
            [stroke renderInContext:context canvasSize:canvasSize];
        }
    }
    for (MarkupText *text in texts) {
        NSRect bounds = [text decoratedBounds];
        // Clipping a partially visible string would leave its hidden glyphs in the PDF object.
        if (NSContainsRect(sourceRect, bounds)) {
            [text renderInContext:context canvasSize:canvasSize];
        }
    }
    [context restoreGraphicsState];
    return YES;
}
#endif
