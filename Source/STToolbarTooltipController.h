#import <AppKit/AppKit.h>

#if defined(GNUSTEP)

NS_ASSUME_NONNULL_BEGIN

@interface STToolbarTooltipController : NSResponder

- (instancetype)init;
- (void)registerView:(NSView *)view withTooltip:(NSString *)tooltip;
- (void)updateTooltip:(NSString *)tooltip forView:(NSView *)view;
- (void)unregisterView:(NSView *)view;
- (void)unregisterAll;
- (NSDictionary<NSValue *, NSString *> *)registeredTooltipsSnapshot;
- (NSDictionary<NSValue *, NSNumber *> *)registeredTrackingSnapshot;

@end

NS_ASSUME_NONNULL_END

#endif
