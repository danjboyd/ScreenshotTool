#import "STThemeUtilities.h"
#import "ScreenshotToolSettings.h"
#if defined(GNUSTEP)
#import <GNUstepGUI/GSTheme.h>
#endif

// Every colour below is a system colour the active theme defines, so each theme gives the app
// its own look (#57). No blends, fixed palettes or accent of the app's own.

/// `color`, or `fallback` for a theme that doesn't define it.
static NSColor *STSystemColor(NSColor *color, NSColor *fallback) {
    return color ?: fallback;
}

NSColor *STThemeWindowBackgroundColor(void) {
    return STSystemColor([NSColor windowBackgroundColor], [NSColor lightGrayColor]);
}

NSColor *STThemeCardBackgroundColor(void) {
    return STSystemColor([NSColor controlBackgroundColor], STThemeWindowBackgroundColor());
}

NSColor *STThemeInsetBackgroundColor(void) {
    return STSystemColor([NSColor textBackgroundColor], STThemeCardBackgroundColor());
}

NSColor *STThemeHairlineColor(void) {
    return STSystemColor([NSColor controlShadowColor], [NSColor grayColor]);
}

NSColor *STThemePrimaryTextColor(void) {
    return STSystemColor([NSColor labelColor], [NSColor controlTextColor]);
}

NSColor *STThemeSecondaryTextColor(void) {
    return STSystemColor([NSColor secondaryLabelColor], [NSColor disabledControlTextColor]);
}

NSColor *STThemeAccentColor(void) {
    return STSystemColor([NSColor keyboardFocusIndicatorColor], [NSColor selectedControlColor]);
}

NSColor *STThemeLinkColor(void) {
    return STThemeAccentColor();
}

NSColor *STThemeSectionHeaderColor(void) {
    // Section titles are set apart by a bold font, as in the system's own panels.
    return STThemePrimaryTextColor();
}

NSColor *STThemeCanvasBackgroundColor(void) {
    return STThemeCardBackgroundColor();
}

NSColor *STThemeCanvasBackdropColor(void) {
    return STThemeWindowBackgroundColor();
}

NSColor *STThemeCanvasImageBorderColor(void) {
    return STThemeHairlineColor();
}

NSColor *STThemeStatusBarBackgroundColor(void) {
    return STThemeWindowBackgroundColor();
}

NSColor *STThemeStatusBarBorderColor(void) {
    return STThemeHairlineColor();
}

NSColor *STThemeStatusPrimaryTextColor(void) {
    return STThemeSecondaryTextColor();
}

NSColor *STThemeStatusValueTextColor(void) {
    return STThemePrimaryTextColor();
}

NSColor *STThemeStatusValueBackgroundColor(void) {
    return STThemeInsetBackgroundColor();
}

NSColor *STThemePopoverBackgroundColor(void) {
    return STThemeWindowBackgroundColor();
}

NSColor *STThemePopoverBorderColor(void) {
    return STThemeHairlineColor();
}

/// Transient notices ("Copied image to clipboard") use the tool tip colours, which each theme
/// styles: a dark pill with Adwaita, GNUstep's own tool tip colours otherwise.
NSColor *STThemeHUDBackgroundColor(void) {
#if defined(GNUSTEP)
    return STSystemColor([NSColor toolTipColor], STThemeCardBackgroundColor());
#else
    // AppKit has no public tool tip colours.
    return STThemeCardBackgroundColor();
#endif
}

NSColor *STThemeHUDTextColor(void) {
#if defined(GNUSTEP)
    return STSystemColor([NSColor toolTipTextColor], STThemePrimaryTextColor());
#else
    return STThemePrimaryTextColor();
#endif
}

NSColor *STThemeToolbarBackgroundColor(BOOL active) {
    return active ? STSystemColor([NSColor selectedControlColor], STThemeCardBackgroundColor())
                  : STThemeCardBackgroundColor();
}

NSColor *STThemeToolbarBorderColor(BOOL active) {
    (void)active;
    return STThemeHairlineColor();
}

CGFloat STThemeToolbarIconFraction(BOOL active) {
    (void)active;
    return 1.0f;
}

NSColor *STThemeToolbarLabelColor(void) {
    return STThemeSecondaryTextColor();
}

static BOOL STThemeDeclares(NSString *key) {
#if defined(GNUSTEP)
    id value = [[[GSTheme theme] infoDictionary] objectForKey:key];
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
#else
    (void)key;
    return NO;
#endif
}

BOOL STThemeDrawsPopoverPanels(void) {
    return STThemeDeclares(@"GSThemeDrawsPopoverPanels");
}

BOOL STThemeDrawsPopoverArrows(void) {
    return STThemeDrawsPopoverPanels() && STThemeDeclares(@"GSThemeDrawsPopoverArrows");
}
