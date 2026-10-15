#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The view behind the window's empty state (#55, #221). Once it takes drops (`dragOperation` and
/// `performDrop` set), it draws a dashed outline inset from its edges, the place an image can be
/// dropped, in the theme's accent while a drop is over it. Its controls are ordinary subviews.
@interface STEmptyStateView : NSView

/// The outline's distance from the view's edges.
+ (CGFloat)outlineInset;

/// The drag's operation, or NSDragOperationNone where nothing can be dropped. Setting this and
/// `performDrop` makes the view take drops; without them it only draws the outline.
@property (nonatomic, copy, nullable) NSDragOperation (^dragOperation)(id<NSDraggingInfo> info);
@property (nonatomic, copy, nullable) BOOL (^performDrop)(id<NSDraggingInfo> info);

/// Whether a drop that can be taken is over the view.
@property (nonatomic, readonly, getter=isDropHighlighted) BOOL dropHighlighted;

@end

NS_ASSUME_NONNULL_END
