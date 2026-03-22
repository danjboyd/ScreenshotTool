#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface STFloatingPopover : NSObject

- (instancetype)initWithContentView:(NSView *)contentView;

// Resolves the current scale factor, honoring GSScaleFactor overrides when present.
+ (CGFloat)currentScaleFactorForView:(nullable NSView *)view;

@property (nonatomic, assign) NSSize contentSize;
@property (nonatomic, assign) CGFloat effectiveScaleFactor;

- (void)beginTransientInteraction;
- (void)endTransientInteraction;
- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge;
- (void)close;
- (BOOL)isShown;

@end

NS_ASSUME_NONNULL_END
