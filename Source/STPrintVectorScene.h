#import <AppKit/AppKit.h>

@class MarkupStroke;
@class MarkupText;

NS_ASSUME_NONNULL_BEGIN

/// One immutable snapshot for a whole-image Cocoa print job. The base has already had every
/// redaction applied to copied pixels; ordinary markup is kept separate for vector drawing.
@interface STPrintVectorScene : NSObject
- (instancetype)initWithRedactedBase:(NSImage *)base canvasSize:(NSSize)canvasSize
                            strokes:(NSArray<MarkupStroke *> *)strokes texts:(NSArray<MarkupText *> *)texts;
@property (nonatomic, strong, readonly) NSImage *redactedBase;
@property (nonatomic, readonly) NSSize canvasSize;
@property (nonatomic, copy, readonly) NSArray<MarkupStroke *> *strokes;
@property (nonatomic, copy, readonly) NSArray<MarkupText *> *texts;
@end

/// Experimental PDF scene split for #355. `redactedBase` must contain only the physical crop of
/// `sourceRect` after redaction, with no other annotations. All rects use image-pixel coordinates
/// from the top left; `targetRect` uses PDF sheet points from the bottom left. A partial text box is
/// refused rather than embedding characters hidden by the selection clip.
FOUNDATION_EXPORT BOOL STDrawPrintVectorScene(NSImage *redactedBase, NSRect sourceRect,
                                              NSSize canvasSize, NSRect targetRect,
                                              NSArray<MarkupStroke *> *strokes,
                                              NSArray<MarkupText *> *texts);

NS_ASSUME_NONNULL_END
