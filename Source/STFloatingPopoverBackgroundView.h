#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface STFloatingPopoverBackgroundView : NSView

@property (nonatomic, assign) NSRectEdge arrowEdge;
@property (nonatomic, assign) CGFloat arrowOffset;
@property (nonatomic, assign) CGFloat arrowBase;
@property (nonatomic, assign) CGFloat arrowHeight;
@property (nonatomic, assign) CGFloat cornerRadius;
/// NO when the theme draws the popover's panel, so this view draws nothing. Default YES.
@property (nonatomic, assign) BOOL drawsPanel;

@end

NS_ASSUME_NONNULL_END
