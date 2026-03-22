#import "STThemeUtilities.h"
#import "ScreenshotToolSettings.h"

static NSColor *STRGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    return [NSColor colorWithDeviceRed:(red / 255.0f)
                                 green:(green / 255.0f)
                                  blue:(blue / 255.0f)
                                 alpha:alpha];
}

static NSColor *STDeviceColor(NSColor *color, NSColor *fallback) {
    NSColor *resolved = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    if (resolved) {
        return resolved;
    }
    return fallback ?: color;
}

static NSColor *STBlendColors(NSColor *fromColor, NSColor *toColor, CGFloat fraction) {
    NSColor *from = STDeviceColor(fromColor, STRGB(255.0f, 255.0f, 255.0f, 1.0f));
    NSColor *to = STDeviceColor(toColor, STRGB(0.0f, 0.0f, 0.0f, 1.0f));
    CGFloat startRed = 0.0f, startGreen = 0.0f, startBlue = 0.0f, startAlpha = 1.0f;
    CGFloat endRed = 0.0f, endGreen = 0.0f, endBlue = 0.0f, endAlpha = 1.0f;
    [from getRed:&startRed green:&startGreen blue:&startBlue alpha:&startAlpha];
    [to getRed:&endRed green:&endGreen blue:&endBlue alpha:&endAlpha];

    CGFloat clamped = MAX(0.0f, MIN(1.0f, fraction));
    return [NSColor colorWithDeviceRed:(startRed + ((endRed - startRed) * clamped))
                                 green:(startGreen + ((endGreen - startGreen) * clamped))
                                  blue:(startBlue + ((endBlue - startBlue) * clamped))
                                 alpha:(startAlpha + ((endAlpha - startAlpha) * clamped))];
}

static NSString *STCurrentThemeName(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *direct = [defaults stringForKey:@"GSTheme"];
    if (direct.length > 0) {
        return direct;
    }
    NSDictionary *global = [defaults persistentDomainForName:NSGlobalDomain];
    NSString *globalTheme = [global objectForKey:@"GSTheme"];
    return globalTheme ?: @"";
}

static BOOL STThemeNameIndicatesDark(NSString *theme) {
    NSString *lower = [theme lowercaseString];
    if (lower.length == 0) {
        return NO;
    }
    return ([lower containsString:@"dark"] ||
            [lower containsString:@"black"] ||
            [lower containsString:@"night"] ||
            [lower containsString:@"sombre"]);
}

static NSColor *STFallbackWindowBackgroundColor(BOOL darkTheme) {
    return darkTheme ? STRGB(36.0f, 36.0f, 36.0f, 1.0f)
                     : STRGB(246.0f, 245.0f, 244.0f, 1.0f);
}

static NSColor *STFallbackCardBackgroundColor(BOOL darkTheme) {
    return darkTheme ? STRGB(48.0f, 48.0f, 48.0f, 1.0f)
                     : STRGB(255.0f, 255.0f, 255.0f, 1.0f);
}

static NSColor *STFallbackInsetBackgroundColor(BOOL darkTheme) {
    return darkTheme ? STRGB(42.0f, 42.0f, 45.0f, 1.0f)
                     : STRGB(235.0f, 233.0f, 230.0f, 1.0f);
}

static NSColor *STFallbackHairlineColor(BOOL darkTheme) {
    return darkTheme ? STRGB(78.0f, 78.0f, 82.0f, 1.0f)
                     : STRGB(210.0f, 206.0f, 201.0f, 1.0f);
}

static NSColor *STFallbackPrimaryTextColor(BOOL darkTheme) {
    return darkTheme ? STRGB(249.0f, 240.0f, 248.0f, 1.0f)
                     : STRGB(36.0f, 31.0f, 49.0f, 1.0f);
}

static NSColor *STFallbackSecondaryTextColor(BOOL darkTheme) {
    return darkTheme ? STRGB(192.0f, 191.0f, 188.0f, 1.0f)
                     : STRGB(94.0f, 92.0f, 100.0f, 1.0f);
}

static NSColor *STFallbackAccentColor(BOOL darkTheme) {
    return darkTheme ? STRGB(120.0f, 174.0f, 237.0f, 1.0f)
                     : STRGB(53.0f, 132.0f, 228.0f, 1.0f);
}

static NSString *STNormalizedInterfaceThemePreference(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [[[defaults stringForKey:STDefaultsInterfaceThemeKey] lowercaseString] copy] ?: @"";
}

BOOL STDefaultInterfaceThemeIsDark(void) {
    NSString *theme = STCurrentThemeName();
    return STThemeNameIndicatesDark(theme);
}

BOOL STThemeIsDark(void) {
    NSString *preference = STNormalizedInterfaceThemePreference();
    if (preference.length == 0 || [preference isEqualToString:STInterfaceThemePreferenceAutoValue]) {
        return STDefaultInterfaceThemeIsDark();
    }
    if ([preference isEqualToString:STInterfaceThemePreferenceDarkValue]) {
        return YES;
    }
    if ([preference isEqualToString:STInterfaceThemePreferenceLightValue]) {
        return NO;
    }
    return STDefaultInterfaceThemeIsDark();
}

NSColor *STThemeWindowBackgroundColor(void) {
    return STDeviceColor([NSColor windowBackgroundColor], STFallbackWindowBackgroundColor(STThemeIsDark()));
}

NSColor *STThemeCardBackgroundColor(void) {
    BOOL darkTheme = STThemeIsDark();
    NSColor *fallback = STFallbackCardBackgroundColor(darkTheme);
    NSColor *control = STDeviceColor([NSColor controlBackgroundColor], fallback);
    if (!control) {
        return fallback;
    }
    return control;
}

NSColor *STThemeInsetBackgroundColor(void) {
    BOOL darkTheme = STThemeIsDark();
    NSColor *fallback = STFallbackInsetBackgroundColor(darkTheme);
    NSColor *textBackground = STDeviceColor([NSColor textBackgroundColor], fallback);
    if (textBackground) {
        return STBlendColors(textBackground,
                             darkTheme ? STRGB(255.0f, 255.0f, 255.0f, 1.0f) : STRGB(255.0f, 255.0f, 255.0f, 1.0f),
                             darkTheme ? 0.04f : 0.18f);
    }
    return fallback;
}

NSColor *STThemeHairlineColor(void) {
    BOOL darkTheme = STThemeIsDark();
    NSColor *fallback = STFallbackHairlineColor(darkTheme);
    NSColor *blend = STBlendColors(STThemeCardBackgroundColor(),
                                   darkTheme ? STRGB(255.0f, 255.0f, 255.0f, 1.0f) : STRGB(0.0f, 0.0f, 0.0f, 1.0f),
                                   darkTheme ? 0.18f : 0.12f);
    return blend ?: fallback;
}

NSColor *STThemePrimaryTextColor(void) {
    NSColor *label = STDeviceColor([NSColor labelColor], nil);
    return label ?: STFallbackPrimaryTextColor(STThemeIsDark());
}

NSColor *STThemeSecondaryTextColor(void) {
    NSColor *secondary = STDeviceColor([NSColor secondaryLabelColor], nil);
    return secondary ?: STFallbackSecondaryTextColor(STThemeIsDark());
}

NSColor *STThemeAccentColor(void) {
    return STFallbackAccentColor(STThemeIsDark());
}

NSColor *STThemeLinkColor(void) {
    return STBlendColors(STThemeAccentColor(),
                         STThemeIsDark() ? STRGB(255.0f, 255.0f, 255.0f, 1.0f) : STRGB(24.0f, 24.0f, 24.0f, 1.0f),
                         STThemeIsDark() ? 0.12f : 0.06f);
}

NSColor *STThemeSectionHeaderColor(void) {
    return STBlendColors(STThemeAccentColor(), STThemePrimaryTextColor(), STThemeIsDark() ? 0.24f : 0.18f);
}

NSColor *STThemeCanvasBackgroundColor(void) {
    return STBlendColors(STThemeWindowBackgroundColor(),
                         STThemeCardBackgroundColor(),
                         STThemeIsDark() ? 0.18f : 0.38f);
}

NSColor *STThemeStatusBarBackgroundColorForTheme(BOOL darkTheme) {
    NSColor *windowColor = STThemeWindowBackgroundColor();
    NSColor *cardColor = STThemeCardBackgroundColor();
    return STBlendColors(windowColor, cardColor, darkTheme ? 0.56f : 0.72f);
}

NSColor *STThemeStatusBarBackgroundColor(void) {
    return STThemeStatusBarBackgroundColorForTheme(STThemeIsDark());
}

NSColor *STThemeStatusBarBorderColorForTheme(BOOL darkTheme) {
    return STBlendColors(STThemeStatusBarBackgroundColorForTheme(darkTheme),
                         darkTheme ? STRGB(255.0f, 255.0f, 255.0f, 1.0f) : STRGB(0.0f, 0.0f, 0.0f, 1.0f),
                         darkTheme ? 0.16f : 0.10f);
}

NSColor *STThemeStatusBarBorderColor(void) {
    return STThemeStatusBarBorderColorForTheme(STThemeIsDark());
}

NSColor *STThemeStatusPrimaryTextColor(void) {
    return STThemeSecondaryTextColor();
}

NSColor *STThemeStatusValueTextColor(void) {
    return STThemePrimaryTextColor();
}

NSColor *STThemeStatusValueBackgroundColor(void) {
    return STBlendColors(STThemeCardBackgroundColor(),
                         STThemeWindowBackgroundColor(),
                         STThemeIsDark() ? 0.35f : 0.18f);
}

NSColor *STThemePopoverBackgroundColor(void) {
    return STBlendColors(STThemeCardBackgroundColor(),
                         STThemeWindowBackgroundColor(),
                         STThemeIsDark() ? 0.20f : 0.08f);
}

NSColor *STThemePopoverBorderColor(void) {
    return STBlendColors(STThemePopoverBackgroundColor(),
                         STThemeIsDark() ? STRGB(255.0f, 255.0f, 255.0f, 1.0f) : STRGB(0.0f, 0.0f, 0.0f, 1.0f),
                         STThemeIsDark() ? 0.22f : 0.12f);
}

NSColor *STThemeHUDBackgroundColor(void) {
    NSColor *base = STBlendColors(STThemeAccentColor(),
                                  STThemeIsDark() ? STRGB(24.0f, 28.0f, 34.0f, 1.0f) : STRGB(30.0f, 34.0f, 40.0f, 1.0f),
                                  STThemeIsDark() ? 0.18f : 0.12f);
    return [base colorWithAlphaComponent:(STThemeIsDark() ? 0.90f : 0.88f)];
}

NSColor *STThemeHUDTextColor(void) {
    return STThemeIsDark() ? STRGB(249.0f, 240.0f, 248.0f, 1.0f)
                           : STRGB(255.0f, 255.0f, 255.0f, 1.0f);
}

NSColor *STThemeToolbarBackgroundColor(BOOL active) {
    if (active) {
        return STBlendColors(STThemeAccentColor(),
                             STThemeCardBackgroundColor(),
                             STThemeIsDark() ? 0.30f : 0.14f);
    }
    return STBlendColors(STThemeCardBackgroundColor(),
                         STThemeWindowBackgroundColor(),
                         STThemeIsDark() ? 0.26f : 0.10f);
}

NSColor *STThemeToolbarBorderColor(BOOL active) {
    if (active) {
        return STBlendColors(STThemeToolbarBackgroundColor(YES),
                             STThemeAccentColor(),
                             STThemeIsDark() ? 0.38f : 0.50f);
    }
    return STBlendColors(STThemeToolbarBackgroundColor(NO),
                         STThemeIsDark() ? STRGB(255.0f, 255.0f, 255.0f, 1.0f) : STRGB(0.0f, 0.0f, 0.0f, 1.0f),
                         STThemeIsDark() ? 0.16f : 0.10f);
}

CGFloat STThemeToolbarIconFraction(BOOL active) {
    if (STThemeIsDark()) {
        return active ? 1.0f : 0.85f;
    }
    return 1.0f;
}

NSColor *STThemeToolbarLabelColor(void) {
    return STThemeSecondaryTextColor();
}
