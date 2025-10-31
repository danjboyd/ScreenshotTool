#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface STFloatingPopoverBackgroundView : NSView

@property (nonatomic, assign) NSRectEdge arrowEdge;
@property (nonatomic, assign) CGFloat arrowOffset;
@property (nonatomic, assign) CGFloat arrowBase;
@property (nonatomic, assign) CGFloat arrowHeight;
@property (nonatomic, assign) CGFloat cornerRadius;

@end

NS_ASSUME_NONNULL_END
