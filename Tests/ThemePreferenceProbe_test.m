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

@end
