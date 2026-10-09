#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface STFloatingPopover : NSObject

- (instancetype)initWithContentView:(NSView *)contentView;

// Resolves the current scale factor, honoring GSScaleFactor overrides when present.
+ (CGFloat)currentScaleFactorForView:(nullable NSView *)view;

@property (nonatomic, assign) NSSize contentSize;
@property (nonatomic, assign) CGFloat effectiveScaleFactor;

/// Whether the popover points at what it was shown from (YES); a dropdown's list doesn't. Set
/// before it's first shown. GNUstep only: AppKit's popovers always point.
@property (nonatomic, assign) BOOL showsArrow;
/// Called after the popover closes, however it closed.
@property (nonatomic, copy, nullable) void (^didCloseHandler)(void);
- (void)beginTransientInteraction;
- (void)endTransientInteraction;
- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge;
- (void)close;
- (BOOL)isShown;

@end

NS_ASSUME_NONNULL_END
