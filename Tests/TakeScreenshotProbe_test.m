/*
 * TakeScreenshotProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * File > Take Screenshot… asks the desktop's own screenshot tool: GNOME's through the desktop
 * portal, the Snipping Tool on Windows, screencapture on macOS (STScreenshotCapture). The tool
 * itself needs a desktop session; these check the menu item and that a capture which can't start
 * reports it, once.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "STScreenshotCapture.h"
#import "TestEnvironmentHelpers.h"
#include <stdlib.h>

@interface AppDelegate (TakeScreenshotTesting)
- (void)setupMenus;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
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

#if !defined(GNUSTEP)
- (void)testScreencaptureIsAvailableOnMacOS {
    XCTAssertTrue([STScreenshotCapture isAvailable], @"/usr/sbin/screencapture ships with macOS");
}
#endif

#if defined(GNUSTEP) && !defined(_WIN32)
STScreenshotCaptureResult STPortalScreenshotResult(unsigned int response, const char *uri, NSURL **url, NSString **failure);

/// The portal's answers: a file, a cancel (1), and GNOME's 2 for a cancel of its UI, which isn't
/// an error either (#314).
- (void)testPortalAnswers {
    NSURL *url = nil;
    NSString *failure = nil;
    XCTAssertEqual(STPortalScreenshotResult(0, "file:///tmp/Screenshot.png", &url, &failure), STScreenshotCaptureResultFile);
    XCTAssertEqualObjects(url.path, @"/tmp/Screenshot.png");
    XCTAssertNil(failure);

    XCTAssertEqual(STPortalScreenshotResult(1, NULL, &url, &failure), STScreenshotCaptureResultNone);
    XCTAssertNil(url);
    XCTAssertNil(failure, @"a cancel says nothing");

    XCTAssertEqual(STPortalScreenshotResult(2, NULL, &url, &failure), STScreenshotCaptureResultNone);
    XCTAssertNil(failure, @"GNOME's cancel: no alert");

    XCTAssertEqual(STPortalScreenshotResult(0, "https://example.com/a.png", &url, &failure), STScreenshotCaptureResultNone);
    XCTAssertNil(url);
    XCTAssertGreaterThan(failure.length, (NSUInteger)0, @"not a file: says so");
}

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
