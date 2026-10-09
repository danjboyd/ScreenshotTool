#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Marks a panel as a popover, for themes that draw popovers themselves (a WinUI flyout, say). A
/// theme checks conformance by name, NSProtocolFromString(@"GSThemePopoverPanel"), so neither
/// links against the other, and GNUstep's NSPopover could adopt it too (#67).
@protocol GSThemePopoverPanel
@optional
/// Where the arrow goes, for a theme that draws arrows (GSThemeDrawsPopoverArrows). The window
/// keeps room for it: the panel's body is the window's frame less popoverArrowHeight on that edge.
/// The edge of the window the arrow points out of: NSMaxYEdge is the top (the popover is below
/// what it points at), NSMinYEdge the bottom, NSMinXEdge the left, NSMaxXEdge the right.
- (NSRectEdge)popoverArrowEdge;
/// The middle of the arrow's base along that edge, in the window's base coordinates: x for the
/// top and bottom edges, y for the sides. It may be nearer a corner than the theme's corner radius
/// allows; the theme moves it in.
- (CGFloat)popoverArrowPosition;
/// How far the tip stands out from the body. 0 when the popover has no arrow (a dropdown's list).
- (CGFloat)popoverArrowHeight;
/// The width of the arrow's base.
- (CGFloat)popoverArrowWidth;
@end

@class STFloatingPopoverBackgroundView;

@interface STFloatingPopoverWindow : NSPanel <GSThemePopoverPanel>

- (instancetype)initWithContentSize:(NSSize)size;

/// Run when Escape is pressed in the popover.
@property (nonatomic, copy, nullable) void (^cancelHandler)(void);

@end

NS_ASSUME_NONNULL_END
