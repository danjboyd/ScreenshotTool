/*
 * ThemePreferenceProbe_test.m
 * Verifies interface theme auto-follow and explicit overrides.
 */

#import <XCTest/XCTest.h>
#import "STThemeUtilities.h"
#if defined(GNUSTEP)
#import <GNUstepGUI/GSTheme.h>
#endif
#import "ScreenshotToolSettings.h"
#import "TestEnvironmentHelpers.h"

@interface ThemePreferenceProbeTests : XCTestCase
@end

@implementation ThemePreferenceProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

// These tests don't set GSTheme: GNUstep switches themes live when it changes, and switching away
// from the theme the suite runs under (TEST_THEME) crashed the test process on CI.

- (void)testDarkThemeNamesAreDetected {
    XCTAssertTrue(STThemeNameIndicatesDark(@"Adwaita-dark"), @"Adwaita-dark should be treated as a dark GNUstep theme");
    XCTAssertTrue(STThemeNameIndicatesDark(@"Sombre"));
    XCTAssertFalse(STThemeNameIndicatesDark(@"Adwaita"));
    XCTAssertFalse(STThemeNameIndicatesDark(@""));
}

- (void)testLightOrDarkFollowsTheRunningTheme {
    // Both themes the suite runs under (GNUstep's own and Adwaita's light palette) are light.
    [NSApplication sharedApplication];
    XCTAssertFalse(STThemeIsDark(), @"Light or dark follows the theme (#56); this one is light");
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

- (void)testRunsUnderTheRequestedTheme {
    // Tools/run_tests.sh sets ST_EXPECT_THEME with TEST_THEME (#74), so a run meant for a theme
    // fails if that theme didn't load rather than quietly testing GNUstep's own.
    NSString *expected = [[NSProcessInfo processInfo] environment][@"ST_EXPECT_THEME"];
    XCTSkipIf(expected.length == 0, @"No theme requested");
#if defined(GNUSTEP)
    [NSApplication sharedApplication];
    XCTAssertEqualObjects([[GSTheme theme] name], expected);
#endif
}

@end
