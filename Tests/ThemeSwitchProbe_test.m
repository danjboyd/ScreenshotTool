/*
 * ThemeSwitchProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Switching GNUstep themes live with the main window up (#82): to a theme that doesn't exist,
 * which falls back to GNUstep's own, and away from and back to the theme the suite runs under.
 * A user can do this in Preferences; on CI a switch away from Adwaita once crashed the process.
 * The test restores the theme it started with, so later tests run under the requested theme.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#if defined(GNUSTEP)
#import <GNUstepGUI/GSTheme.h>
#endif
#import "AppDelegate.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (ThemeSwitchTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
@end

@interface ThemeSwitchProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
    NSString *_startTheme;
}
@end

@implementation ThemeSwitchProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        _startTheme = [[NSUserDefaults standardUserDefaults] stringForKey:@"GSTheme"];
        _appDelegate = [[AppDelegate alloc] init];
        [_appDelegate setupWindowAndContent];
        [_appDelegate.window orderFront:nil];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    [self switchToTheme:_startTheme];
    [_appDelegate.window orderOut:nil];
    _appDelegate = nil;
    [super tearDown];
}

/// Sets GSTheme (nil removes it), which GNUstep applies at once, and lets the window redraw.
- (void)switchToTheme:(NSString *)name {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (name.length > 0) {
        [defaults setObject:name forKey:@"GSTheme"];
    } else {
        [defaults removeObjectForKey:@"GSTheme"];
    }
    [_appDelegate.window display];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
}

#if defined(GNUSTEP)
- (void)testUnknownThemeFallsBackWithoutException {
    if (_shouldSkip) {
        return;
    }
    XCTAssertNoThrow([self switchToTheme:@"NoSuchTheme"]);
    XCTAssertEqualObjects([[GSTheme theme] name], @"GNUstep");
}

- (void)testSwitchingAwayAndBackKeepsTheWindowWorking {
    if (_shouldSkip) {
        return;
    }
    NSString *original = [[GSTheme theme] name];
    XCTAssertNoThrow([self switchToTheme:@"Sombre"]);
    XCTAssertNoThrow([self switchToTheme:_startTheme]);
    XCTAssertEqualObjects([[GSTheme theme] name], original);
    XCTAssertTrue(_appDelegate.window.isVisible);
}
#endif

@end
