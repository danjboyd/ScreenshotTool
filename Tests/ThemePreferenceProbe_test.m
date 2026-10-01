/*
 * ThemePreferenceProbe_test.m
 * Verifies interface theme auto-follow and explicit overrides.
 */

#import <XCTest/XCTest.h>
#import "STThemeUtilities.h"
#import "ScreenshotToolSettings.h"
#import "TestEnvironmentHelpers.h"

@interface ThemePreferenceProbeTests : XCTestCase
@end

@implementation ThemePreferenceProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:STDefaultsInterfaceThemeKey];
    [defaults removeObjectForKey:@"GSTheme"];
}

- (void)tearDown {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:STDefaultsInterfaceThemeKey];
    [defaults removeObjectForKey:@"GSTheme"];
    [super tearDown];
}

- (void)testAdwaitaDarkThemeIsDetectedAsDarkInAutoMode {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@"Adwaita-dark" forKey:@"GSTheme"];

    XCTAssertTrue(STDefaultInterfaceThemeIsDark(), @"Adwaita-dark should be treated as a dark GNUstep theme");
    XCTAssertTrue(STThemeIsDark(), @"Auto mode should follow Adwaita-dark");
}

- (void)testExplicitLightPreferenceOverridesDarkTheme {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@"Adwaita-dark" forKey:@"GSTheme"];
    [defaults setObject:STInterfaceThemePreferenceLightValue forKey:STDefaultsInterfaceThemeKey];

    XCTAssertFalse(STThemeIsDark(), @"Explicit light preference should override dark GNUstep themes");
}

- (void)testExplicitDarkPreferenceOverridesLightTheme {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@"Adwaita" forKey:@"GSTheme"];
    [defaults setObject:STInterfaceThemePreferenceDarkValue forKey:STDefaultsInterfaceThemeKey];

    XCTAssertTrue(STThemeIsDark(), @"Explicit dark preference should override light GNUstep themes");
}

- (void)testAutoPreferenceFollowsCurrentTheme {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@"Adwaita" forKey:@"GSTheme"];
    [defaults setObject:STInterfaceThemePreferenceAutoValue forKey:STDefaultsInterfaceThemeKey];

    XCTAssertFalse(STThemeIsDark(), @"Auto preference should follow a light GNUstep theme");
}

- (void)testDarkPaletteIsDetectedFromWindowBackground {
    // Adwaita keeps its name in both colour schemes, so Auto must also read the palette.
    XCTAssertTrue(STThemeBackgroundColorIsDark([NSColor colorWithDeviceRed:0.14 green:0.14 blue:0.14 alpha:1.0]),
                  @"Adwaita's dark window background should count as dark");
    XCTAssertFalse(STThemeBackgroundColorIsDark([NSColor colorWithDeviceRed:0.98 green:0.98 blue:0.98 alpha:1.0]),
                   @"Adwaita's light window background should count as light");
    XCTAssertFalse(STThemeBackgroundColorIsDark([NSColor colorWithDeviceWhite:0.83 alpha:1.0]),
                   @"GNUstep's default grey should count as light");
}

@end
