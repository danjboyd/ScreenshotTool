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

NS_ASSUME_NONNULL_END
