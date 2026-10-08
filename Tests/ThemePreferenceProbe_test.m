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
