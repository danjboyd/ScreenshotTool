#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Marks a panel as a popover, for themes that draw popovers themselves (a WinUI flyout, say). It
/// has no methods: a theme checks conformance by name, NSProtocolFromString(@"GSThemePopoverPanel"),
/// so neither links against the other, and GNUstep's NSPopover could adopt it too (#67).
@protocol GSThemePopoverPanel
@end

@interface STFloatingPopoverWindow : NSPanel <GSThemePopoverPanel>

- (instancetype)initWithContentSize:(NSSize)size;

/// Run when Escape is pressed in the popover.
@property (nonatomic, copy, nullable) void (^cancelHandler)(void);

@end

NS_ASSUME_NONNULL_END
