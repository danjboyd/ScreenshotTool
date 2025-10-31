#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface STFloatingPopover : NSObject

- (instancetype)initWithContentView:(NSView *)contentView;

@property (nonatomic, assign) NSSize contentSize;

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge;
- (void)close;
- (BOOL)isShown;

@end

NS_ASSUME_NONNULL_END
