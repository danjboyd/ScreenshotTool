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
NSString * const STDefaultsSaveDirectoryKey = @"ScreenshotToolSaveDirectory";
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
