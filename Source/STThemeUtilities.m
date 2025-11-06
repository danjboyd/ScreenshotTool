#import "STThemeUtilities.h"

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
    NSArray<NSString *> *darkTokens = @[ @"dark", @"sombre", @"graphite", @"night" ];
    for (NSString *token in darkTokens) {
        if ([lower containsString:token]) {
            return YES;
        }
    }
    return NO;
}

static BOOL STColorIsDark(NSColor *color) {
    if (!color) {
        return NO;
    }
    NSColor *device = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color;
    CGFloat luminance = (0.2126f * device.redComponent) +
                        (0.7152f * device.greenComponent) +
                        (0.0722f * device.blueComponent);
    return luminance < 0.45f;
}

BOOL STThemeIsDark(void) {
    NSString *theme = STCurrentThemeName();
    if (STThemeNameIndicatesDark(theme)) {
        return YES;
    }

    NSColor *windowColor = [NSColor windowBackgroundColor];
    if (STColorIsDark(windowColor)) {
        return YES;
    }

    NSColor *controlBackground = [NSColor controlBackgroundColor];
    if (STColorIsDark(controlBackground)) {
        return YES;
    }
    return NO;
}

NSColor *STThemeCanvasBackgroundColor(void) {
    if (STThemeIsDark()) {
        return [NSColor colorWithCalibratedRed:0.20f green:0.21f blue:0.24f alpha:1.0f];
    }
    return [NSColor windowBackgroundColor] ?: [NSColor colorWithCalibratedWhite:0.96f alpha:1.0f];
}

NSColor *STThemeStatusBarBackgroundColor(void) {
    if (STThemeIsDark()) {
        return [NSColor colorWithCalibratedRed:0.12f green:0.13f blue:0.15f alpha:1.0f];
    }
    return [NSColor colorWithCalibratedWhite:0.95f alpha:1.0f];
}

NSColor *STThemeStatusBarBorderColor(void) {
    if (STThemeIsDark()) {
        return [NSColor colorWithCalibratedWhite:0.05f alpha:1.0f];
    }
    return [NSColor colorWithCalibratedWhite:0.80f alpha:1.0f];
}

NSColor *STThemeStatusPrimaryTextColor(void) {
    if (STThemeIsDark()) {
        return [NSColor colorWithCalibratedWhite:0.78f alpha:1.0f];
    }
    NSColor *color = [NSColor secondaryLabelColor];
    return color ?: [NSColor darkGrayColor];
}

NSColor *STThemeStatusValueTextColor(void) {
    if (STThemeIsDark()) {
        return [NSColor colorWithCalibratedWhite:0.90f alpha:1.0f];
    }
    NSColor *color = [NSColor labelColor];
    return color ?: [NSColor blackColor];
}

NSColor *STThemeStatusValueBackgroundColor(void) {
    if (STThemeIsDark()) {
        return [NSColor colorWithCalibratedWhite:0.22f alpha:1.0f];
    }
    return [NSColor colorWithCalibratedWhite:0.88f alpha:1.0f];
}

NSColor *STThemeToolbarBackgroundColor(BOOL active) {
    if (STThemeIsDark()) {
        if (active) {
            return [NSColor colorWithCalibratedRed:0.58f green:0.59f blue:0.61f alpha:1.0f];
        }
        return [NSColor colorWithCalibratedRed:0.52f green:0.53f blue:0.55f alpha:1.0f];
    }
    if (active) {
        return [NSColor colorWithCalibratedWhite:0.90f alpha:1.0f];
    }
    return [NSColor colorWithCalibratedWhite:0.97f alpha:1.0f];
}

NSColor *STThemeToolbarBorderColor(BOOL active) {
    if (STThemeIsDark()) {
        CGFloat alpha = active ? 0.6f : 0.35f;
        return [NSColor colorWithCalibratedWhite:0.15f alpha:alpha];
    }
    CGFloat alpha = active ? 0.8f : 0.5f;
    return [NSColor colorWithCalibratedWhite:0.78f alpha:alpha];
}

CGFloat STThemeToolbarIconFraction(BOOL active) {
    if (STThemeIsDark()) {
        return active ? 1.0f : 0.85f;
    }
    return 1.0f;
}

NSColor *STThemeToolbarLabelColor(void) {
    if (STThemeIsDark()) {
        return [NSColor colorWithCalibratedWhite:0.92f alpha:1.0f];
    }
    return [NSColor colorWithCalibratedWhite:0.18f alpha:1.0f];
}
