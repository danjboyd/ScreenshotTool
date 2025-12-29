#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

BOOL STThemeIsDark(void);
BOOL STDefaultInterfaceThemeIsDark(void);

NSColor *STThemeCanvasBackgroundColor(void);
NSColor *STThemeStatusBarBackgroundColor(void);
NSColor *STThemeStatusBarBorderColor(void);
NSColor *STThemeStatusBarBackgroundColorForTheme(BOOL darkTheme);
NSColor *STThemeStatusBarBorderColorForTheme(BOOL darkTheme);
NSColor *STThemeStatusPrimaryTextColor(void);
NSColor *STThemeStatusValueTextColor(void);
NSColor *STThemeStatusValueBackgroundColor(void);
NSColor *STThemeToolbarBackgroundColor(BOOL active);
NSColor *STThemeToolbarBorderColor(BOOL active);
CGFloat STThemeToolbarIconFraction(BOOL active);
NSColor *STThemeToolbarLabelColor(void);

NS_ASSUME_NONNULL_END
