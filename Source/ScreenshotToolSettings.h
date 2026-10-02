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
extern NSString * const STDefaultsTextStyleKey;
extern NSString * const STDefaultsTextDefaultStyleKey;
extern NSString * const STDefaultsTextSizePresetKey;
extern NSString * const STDefaultsTextDefaultSizePresetKey;
extern NSString * const STDefaultsSaveDirectoryKey;
extern NSString * const STDefaultsRecentDocumentsKey;
extern NSString * const STDefaultsShowStatusBarKey;
extern NSString * const STDefaultsInterfaceThemeKey;
extern NSString * const STInterfaceThemePreferenceAutoValue;
extern NSString * const STInterfaceThemePreferenceLightValue;
extern NSString * const STInterfaceThemePreferenceDarkValue;

FOUNDATION_EXPORT NSColor *STDefaultPenColor(void);
FOUNDATION_EXPORT NSColor *STDefaultHighlighterColor(void);
FOUNDATION_EXPORT NSColor *STDefaultTextColor(void);
FOUNDATION_EXPORT NSFont *STDefaultTextFont(void);
/// The built-in text style (a MarkupTextStyle value): outlined, so labels read on any image.
FOUNDATION_EXPORT NSInteger STDefaultTextStyle(void);
/// A stored MarkupTextStyle value, or the fallback when it is missing or out of range.
FOUNDATION_EXPORT NSInteger STStoredTextStyle(NSString *key, NSInteger fallback);

/// Text size presets. Exact means the font's own point size; the others scale with the image.
typedef NS_ENUM(NSInteger, STTextSizePreset) {
    STTextSizePresetExact = 0,
    STTextSizePresetSmall = 1,
    STTextSizePresetMedium = 2,
    STTextSizePresetLarge = 3,
    STTextSizePresetExtraLarge = 4,
};
/// The built-in preset for new text: Medium, sized from the image.
FOUNDATION_EXPORT STTextSizePreset STDefaultTextSizePreset(void);
/// A stored preset, or the fallback when it is missing or out of range.
FOUNDATION_EXPORT STTextSizePreset STStoredTextSizePreset(NSString *key, STTextSizePreset fallback);
/// The point size a preset gives on an image of this size; 0 for Exact. Sized from the image's
/// area (geometric mean of width and height), so a 1080p capture gets about 27pt at Medium, a 4K
/// capture about 55pt, and small crops a readable minimum.
FOUNDATION_EXPORT CGFloat STTextPointSizeForPreset(STTextSizePreset preset, NSSize imageSize);
FOUNDATION_EXPORT NSString *STEncodeColor(NSColor *color);
FOUNDATION_EXPORT NSColor *STDecodeColor(NSString *encoded, NSColor *fallback);

NS_ASSUME_NONNULL_END
