#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat STPenWidthDefault;
extern const CGFloat STHighlighterWidthDefault;
extern const CGFloat STToolWidthMin;
extern const CGFloat STToolWidthMax;

extern NSString * const STDefaultsPenWidthKey;
extern NSString * const STDefaultsPenDefaultWidthKey;
extern NSString * const STDefaultsHighlighterWidthKey;
extern NSString * const STDefaultsHighlighterDefaultWidthKey;
extern NSString * const STDefaultsPenColorKey;
extern NSString * const STDefaultsPenDefaultColorKey;
extern NSString * const STDefaultsHighlighterColorKey;
extern NSString * const STDefaultsHighlighterDefaultColorKey;
extern NSString * const STDefaultsTextColorKey;
extern NSString * const STDefaultsTextDefaultColorKey;
extern NSString * const STDefaultsTextFontNameKey;
extern NSString * const STDefaultsTextFontSizeKey;
extern NSString * const STDefaultsTextDefaultFontNameKey;
extern NSString * const STDefaultsTextDefaultFontSizeKey;
extern NSString * const STDefaultsSaveDirectoryKey;
extern NSString * const STDefaultsShowStatusBarKey;
extern NSString * const STDefaultsInterfaceThemeKey;
extern NSString * const STInterfaceThemePreferenceAutoValue;
extern NSString * const STInterfaceThemePreferenceLightValue;
extern NSString * const STInterfaceThemePreferenceDarkValue;

FOUNDATION_EXPORT NSColor *STDefaultPenColor(void);
FOUNDATION_EXPORT NSColor *STDefaultHighlighterColor(void);
FOUNDATION_EXPORT NSColor *STDefaultTextColor(void);
FOUNDATION_EXPORT NSFont *STDefaultTextFont(void);
FOUNDATION_EXPORT NSString *STEncodeColor(NSColor *color);
FOUNDATION_EXPORT NSColor *STDecodeColor(NSString *encoded, NSColor *fallback);

NS_ASSUME_NONNULL_END
