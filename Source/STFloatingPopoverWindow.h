#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface STFloatingPopoverWindow : NSPanel

- (instancetype)initWithContentSize:(NSSize)size;

/// Run when Escape is pressed in the popover.
@property (nonatomic, copy, nullable) void (^cancelHandler)(void);

@end

NS_ASSUME_NONNULL_END
