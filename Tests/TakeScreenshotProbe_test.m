/*
 * TakeScreenshotProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * File > Take Screenshot… asks the desktop's own screenshot tool: GNOME's through the desktop
 * portal, the Snipping Tool on Windows, screencapture on macOS (STScreenshotCapture). The tool
 * itself needs a desktop session; these check the menu item, that a capture which can't start
 * reports it, once, and that the window hides during a capture unless the user keeps it (#313).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "STScreenshotCapture.h"
#import "ScreenshotToolSettings.h"
#import "PreferencesWindowController.h"
#import "TestEnvironmentHelpers.h"
#include <stdlib.h>

@interface AppDelegate (TakeScreenshotTesting)
- (void)setupMenus;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (BOOL)hiddenForScreenshot;
- (BOOL)hidesWindowForScreenshot;
- (void)takeScreenshot:(id)sender;
- (void)finishScreenshotWithResult:(STScreenshotCaptureResult)result url:(NSURL *)url failure:(NSString *)failure;
@end

@interface PreferencesWindowController (TakeScreenshotTesting)
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, assign) NSInteger currentSection;
@property (nonatomic, strong) NSTextField *saveDirectoryField;
@property (nonatomic, strong) NSButton *restoreDefaultsButton;
@property (nonatomic, strong) NSSwitch *keepVisibleSwitch;
- (void)layoutContentView;
- (void)keepVisibleToggled:(NSSwitch *)sender;
@end

@interface TakeScreenshotProbeTests : XCTestCase
@end

@implementation TakeScreenshotProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (NSMenuItem *)takeScreenshotItemIn:(NSMenu *)menu {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == @selector(takeScreenshot:)) {
            return item;
        }
        NSMenuItem *found = item.submenu ? [self takeScreenshotItemIn:item.submenu] : nil;
        if (found) {
            return found;
        }
    }
    return nil;
}

- (void)testFileMenuHasTakeScreenshot {
    [NSApplication sharedApplication];
    AppDelegate *delegate = [[AppDelegate alloc] init];
    [delegate setupMenus];
    NSMenuItem *item = [self takeScreenshotItemIn:[NSApp mainMenu]];
    XCTAssertNotNil(item);
    XCTAssertEqualObjects(item.title, @"Take Screenshot…");
    XCTAssertEqualObjects(item.keyEquivalent, @"T", @"Ctrl+Shift+T, Command-Shift-T on macOS");
    XCTAssertEqual([delegate validateMenuItem:item], [STScreenshotCapture isAvailable]);
}

/// A delegate with its window on screen, or nil without a window server.
- (AppDelegate *)delegateWithVisibleWindow {
    AppDelegate *delegate = nil;
    @try {
        [NSApplication sharedApplication];
        delegate = [[AppDelegate alloc] init];
        [delegate setupWindowAndContent];
        [delegate.window orderFront:nil];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        return nil;
    }
    return delegate.window.isVisible ? delegate : nil;
}

/// Take Screenshot hides the window on every platform, and a cancel brings it back with no alert.
- (void)testWindowHidesDuringCaptureAndComesBackOnCancel {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsKeepWindowVisibleWhileCapturingKey];
    AppDelegate *delegate = [self delegateWithVisibleWindow];
    if (!delegate) {
        return;
    }
    [delegate takeScreenshot:nil];
    // The capture starts after a moment; it isn't wanted here.
    [NSObject cancelPreviousPerformRequestsWithTarget:delegate];
    XCTAssertTrue(delegate.hiddenForScreenshot);
    XCTAssertFalse(delegate.window.isVisible, @"out of the way of the capture");

    [delegate finishScreenshotWithResult:STScreenshotCaptureResultNone url:nil failure:nil];
    XCTAssertFalse(delegate.hiddenForScreenshot);
    XCTAssertTrue(delegate.window.isVisible, @"back after a cancel");
    [delegate.window orderOut:nil];
}

/// With "Keep this window visible while capturing" on, it stays. (Not by taking a screenshot: one
/// that isn't hidden for starts at once, and a real desktop would answer it.)
- (void)testKeepVisiblePreferenceLeavesTheWindowUp {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsKeepWindowVisibleWhileCapturingKey];
    AppDelegate *delegate = [self delegateWithVisibleWindow];
    if (!delegate) {
        return;
    }
    XCTAssertTrue([delegate hidesWindowForScreenshot], @"hidden by default");
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:STDefaultsKeepWindowVisibleWhileCapturingKey];
    XCTAssertFalse([delegate hidesWindowForScreenshot]);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsKeepWindowVisibleWhileCapturingKey];
    [delegate.window orderOut:nil];
}

/// Preferences > Workspace has the switch, below the save folder, and it sets the preference.
- (void)testKeepVisibleSwitchIsOnTheWorkspacePage {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsKeepWindowVisibleWhileCapturingKey];
    AppDelegate *delegate = [self delegateWithVisibleWindow];
    if (!delegate) {
        return;
    }
    PreferencesWindowController *preferences =
        [[PreferencesWindowController alloc] initWithDelegate:(id<PreferencesWindowControllerDelegate>)delegate];
    preferences.currentSection = 3; // Workspace
    [preferences refresh];
    [preferences layoutContentView];

    NSSwitch *keepVisible = preferences.keepVisibleSwitch;
    XCTAssertNotNil(keepVisible);
    XCTAssertFalse(keepVisible.isHidden);
    XCTAssertEqual(keepVisible.state, NSControlStateValueOff, @"off by default");
    XCTAssertLessThanOrEqual(NSMaxY(keepVisible.frame), NSMinY(preferences.saveDirectoryField.frame), @"below the folder");
    XCTAssertGreaterThanOrEqual(NSMinY(keepVisible.frame), NSMaxY(preferences.restoreDefaultsButton.frame),
                                @"above Restore Defaults");

    keepVisible.state = NSControlStateValueOn;
    [preferences keepVisibleToggled:keepVisible];
    XCTAssertTrue([[NSUserDefaults standardUserDefaults] boolForKey:STDefaultsKeepWindowVisibleWhileCapturingKey]);
    XCTAssertFalse([delegate hidesWindowForScreenshot]);

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsKeepWindowVisibleWhileCapturingKey];
    [preferences.window setDelegate:nil];
    [preferences.window orderOut:nil];
    [delegate.window orderOut:nil];
}

#if !defined(GNUSTEP)
- (void)testScreencaptureIsAvailableOnMacOS {
    XCTAssertTrue([STScreenshotCapture isAvailable], @"/usr/sbin/screencapture ships with macOS");
}
#endif

#if defined(GNUSTEP) && !defined(_WIN32)
/// With no session bus to reach the portal on, the capture reports why, once, on a later turn of
/// the run loop, and another can start after.
- (void)testCaptureWithoutAPortalReportsAFailure {
    const char *saved = getenv("DBUS_SESSION_BUS_ADDRESS");
    NSString *savedAddress = saved ? [NSString stringWithUTF8String:saved] : nil;
    setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent/screenshottool-test-bus", 1);

    __block NSInteger calls = 0;
    __block STScreenshotCaptureResult result = STScreenshotCaptureResultFile;
    __block NSString *failure = nil;
    [STScreenshotCapture captureForWindow:nil completion:^(STScreenshotCaptureResult r, NSURL *url, NSString *f) {
        (void)url;
        calls++;
        result = r;
        failure = f;
    }];
    XCTAssertEqual(calls, 0, @"never from within the call");
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while (calls == 0 && [until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    if (savedAddress) {
        setenv("DBUS_SESSION_BUS_ADDRESS", savedAddress.UTF8String, 1);
    } else {
        unsetenv("DBUS_SESSION_BUS_ADDRESS");
    }
    XCTAssertEqual(calls, 1);
    XCTAssertEqual(result, STScreenshotCaptureResultNone);
    XCTAssertGreaterThan(failure.length, (NSUInteger)0, @"says why");
    XCTAssertFalse([STScreenshotCapture isCapturing], @"another can start");
}
#endif

@end
