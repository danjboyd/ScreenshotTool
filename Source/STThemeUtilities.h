#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

BOOL STThemeIsDark(void);
BOOL STDefaultInterfaceThemeIsDark(void);
BOOL STThemeBackgroundColorIsDark(NSColor *color);

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
NSColor *STThemeStatusBarBackgroundColorForTheme(BOOL darkTheme);
NSColor *STThemeStatusBarBorderColorForTheme(BOOL darkTheme);
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
