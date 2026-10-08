#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A button with an attached menu, as libadwaita's AdwSplitButton (and AppKit's NSComboButton in
/// its split style, which GNUstep lacks): a click on the title sends the action, a click on the
/// arrow at the right opens the menu below the button. The theme draws the bezel and title as for
/// any button, so with Return as its key equivalent it is the window's suggested (blue) button;
/// the button adds the arrow and the line between the two parts, in the title's colour.
@interface STSplitButton : NSButton

/// Asked for the menu each time the arrow is pressed, so it can be built fresh.
@property (nonatomic, copy, nullable) NSMenu * _Nullable (^menuProvider)(void);

/// The arrow part, in the button's bounds.
- (NSRect)arrowRect;

@end

NS_ASSUME_NONNULL_END
