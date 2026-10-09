#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Light or dark is the theme's choice (and the desktop's), and the app never guesses it: every
// colour here is a system colour the active theme defines (#56, #57).

NSColor *STThemeCanvasBackgroundColor(void);
NSColor *STThemeCanvasBackdropColor(void);
NSColor *STThemeCanvasImageBorderColor(void);
NSColor *STThemeWindowBackgroundColor(void);
NSColor *STThemeCardBackgroundColor(void);
NSColor *STThemeInsetBackgroundColor(void);
NSColor *STThemeHairlineColor(void);
NSColor *STThemePrimaryTextColor(void);
NSColor *STThemeSecondaryTextColor(void);
NSColor *STThemeSectionHeaderColor(void);
NSColor *STThemeAccentColor(void);
NSColor *STThemeLinkColor(void);
NSColor *STThemeStatusBarBackgroundColor(void);
NSColor *STThemeStatusBarBorderColor(void);
NSColor *STThemeStatusPrimaryTextColor(void);
NSColor *STThemeStatusValueTextColor(void);
NSColor *STThemeStatusValueBackgroundColor(void);
NSColor *STThemePopoverBackgroundColor(void);
NSColor *STThemePopoverBorderColor(void);
NSColor *STThemeHUDBackgroundColor(void);
NSColor *STThemeHUDTextColor(void);
NSColor *STThemeToolbarBackgroundColor(BOOL active);
NSColor *STThemeToolbarBorderColor(BOOL active);
CGFloat STThemeToolbarIconFraction(BOOL active);
NSColor *STThemeToolbarLabelColor(void);

/// Whether the theme draws the panels of popovers marked GSThemePopoverPanel itself, which it
/// declares with GSThemeDrawsPopoverPanels = YES in its Info-gnustep.plist. Always NO on macOS.
BOOL STThemeDrawsPopoverPanels(void);
/// Whether a theme that draws popover panels also draws their arrows, which it declares with
/// GSThemeDrawsPopoverArrows = YES. The popover then keeps room for its arrow, and its panel
/// tells the theme where the arrow goes (GSThemePopoverPanel's methods). Always NO on macOS.
BOOL STThemeDrawsPopoverArrows(void);

NS_ASSUME_NONNULL_END
