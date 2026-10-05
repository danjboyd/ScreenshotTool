#import "ScreenshotToolSettings.h"

const CGFloat STPenWidthDefault = 3.0f;
const CGFloat STHighlighterWidthDefault = 12.0f;
const CGFloat STToolWidthMin = 1.0f;
const CGFloat STToolWidthMax = 36.0f;

NSString * const STDefaultsPenWidthKey = @"ScreenshotToolPenWidth";
NSString * const STDefaultsPenDefaultWidthKey = @"ScreenshotToolPenDefaultWidth";
NSString * const STDefaultsHighlighterWidthKey = @"ScreenshotToolHighlighterWidth";
NSString * const STDefaultsHighlighterDefaultWidthKey = @"ScreenshotToolHighlighterDefaultWidth";
NSString * const STDefaultsPenColorKey = @"ScreenshotToolPenColor";
NSString * const STDefaultsPenDefaultColorKey = @"ScreenshotToolPenDefaultColor";
NSString * const STDefaultsHighlighterColorKey = @"ScreenshotToolHighlighterColor";
NSString * const STDefaultsHighlighterDefaultColorKey = @"ScreenshotToolHighlighterDefaultColor";
NSString * const STDefaultsTextColorKey = @"ScreenshotToolTextColor";
NSString * const STDefaultsTextDefaultColorKey = @"ScreenshotToolTextDefaultColor";
NSString * const STDefaultsTextFontNameKey = @"ScreenshotToolTextFontName";
NSString * const STDefaultsTextFontSizeKey = @"ScreenshotToolTextFontSize";
NSString * const STDefaultsTextDefaultFontNameKey = @"ScreenshotToolTextDefaultFontName";
NSString * const STDefaultsTextDefaultFontSizeKey = @"ScreenshotToolTextDefaultFontSize";
NSString * const STDefaultsTextStyleKey = @"ScreenshotToolTextStyle";
NSString * const STDefaultsTextDefaultStyleKey = @"ScreenshotToolTextDefaultStyle";
NSString * const STDefaultsTextSizePresetKey = @"ScreenshotToolTextSizePreset";
NSString * const STDefaultsTextDefaultSizePresetKey = @"ScreenshotToolTextDefaultSizePreset";
NSString * const STDefaultsTextAlignmentKey = @"ScreenshotToolTextAlignment";
NSString * const STDefaultsTextDefaultAlignmentKey = @"ScreenshotToolTextDefaultAlignment";
NSString * const STDefaultsSaveDirectoryKey = @"ScreenshotToolSaveDirectory";
NSString * const STDefaultsRecentDocumentsKey = @"ScreenshotToolRecentDocuments";
NSString * const STDefaultsShowStatusBarKey = @"ScreenshotToolShowStatusBar";

NSColor *STDefaultPenColor(void) {
    return [NSColor redColor];
}

NSColor *STDefaultHighlighterColor(void) {
    return [NSColor yellowColor];
}

NSColor *STDefaultTextColor(void) {
    return STDefaultPenColor();
}

NSFont *STDefaultTextFont(void) {
    return [NSFont systemFontOfSize:24.0f];
}

NSInteger STDefaultTextStyle(void) {
    return 1; // MarkupTextStyleOutline
}

NSInteger STStoredTextStyle(NSString *key, NSInteger fallback) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (![stored respondsToSelector:@selector(integerValue)]) {
        return fallback;
    }
    NSInteger value = [stored integerValue];
    return (value >= 0 && value <= 3) ? value : fallback;
}

STTextSizePreset STDefaultTextSizePreset(void) {
    return STTextSizePresetMedium;
}

STTextSizePreset STStoredTextSizePreset(NSString *key, STTextSizePreset fallback) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (![stored respondsToSelector:@selector(integerValue)]) {
        return fallback;
    }
    NSInteger value = [stored integerValue];
    return (value >= STTextSizePresetExact && value <= STTextSizePresetExtraLarge) ? (STTextSizePreset)value : fallback;
}

NSInteger STTextAlignmentCode(NSTextAlignment alignment) {
    switch (alignment) {
        case NSTextAlignmentCenter:
            return 1;
        case NSTextAlignmentRight:
            return 2;
        default:
            return 0;
    }
}

NSTextAlignment STTextAlignmentFromCode(NSInteger code) {
    switch (code) {
        case 1:
            return NSTextAlignmentCenter;
        case 2:
            return NSTextAlignmentRight;
        default:
            return NSTextAlignmentLeft;
    }
}

NSTextAlignment STStoredTextAlignment(NSString *key, NSTextAlignment fallback) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (![stored respondsToSelector:@selector(integerValue)]) {
        return fallback;
    }
    NSInteger code = [stored integerValue];
    return (code >= 0 && code <= 2) ? STTextAlignmentFromCode(code) : fallback;
}

CGFloat STTextPointSizeForPreset(STTextSizePreset preset, NSSize imageSize) {
    CGFloat multiplier = 0.0;
    CGFloat minimum = 0.0;
    switch (preset) {
        case STTextSizePresetSmall:      multiplier = 0.7;  minimum = 11.0; break;
        case STTextSizePresetMedium:     multiplier = 1.0;  minimum = 14.0; break;
        case STTextSizePresetLarge:      multiplier = 1.45; minimum = 20.0; break;
        case STTextSizePresetExtraLarge: multiplier = 2.1;  minimum = 28.0; break;
        case STTextSizePresetExact:
        default:
            return 0.0;
    }
    CGFloat scale = sqrt(MAX(imageSize.width, 1.0) * MAX(imageSize.height, 1.0));
    CGFloat size = round(scale * 0.019 * multiplier);
    return MIN(240.0, MAX(minimum, size));
}

NSString *STEncodeColor(NSColor *color) {
    if (!color) {
        return @"";
    }
    NSColor *deviceColor = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color;
    CGFloat r = 0.0f, g = 0.0f, b = 0.0f, a = 1.0f;
    [deviceColor getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"%.6f,%.6f,%.6f,%.6f",
                                      MAX(0.0, MIN(1.0, r)),
                                      MAX(0.0, MIN(1.0, g)),
                                      MAX(0.0, MIN(1.0, b)),
                                      MAX(0.0, MIN(1.0, a))];
}

NSColor *STDecodeColor(NSString *encoded, NSColor *fallback) {
    if (encoded.length == 0) {
        return fallback ? [fallback copy] : [NSColor blackColor];
    }
    NSArray<NSString *> *components = [encoded componentsSeparatedByString:@","];
    if (components.count < 3) {
        return fallback ? [fallback copy] : [NSColor blackColor];
    }
    double r = components[0].doubleValue;
    double g = components[1].doubleValue;
    double b = components[2].doubleValue;
    double a = (components.count >= 4) ? components[3].doubleValue : 1.0;
    r = MAX(0.0, MIN(1.0, r));
    g = MAX(0.0, MIN(1.0, g));
    b = MAX(0.0, MIN(1.0, b));
    a = MAX(0.0, MIN(1.0, a));
    return [NSColor colorWithDeviceRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a];
}
