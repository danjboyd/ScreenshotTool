/*
 * WaylandClipboardTimeoutProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The Paste check asks wl-paste which types the Wayland clipboard offers, on the main thread
 * while menus validate. On GNOME wl-paste can wait for keyboard focus indefinitely; the app
 * must give up quickly instead of freezing (#90).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (WaylandClipboardTimeoutTesting)
- (BOOL)waylandClipboardHasImage;
@end

@interface WaylandClipboardTimeoutProbeTests : XCTestCase {
    AppDelegate *_appDelegate;
    NSString *_tempRoot;
    NSString *_originalPATH;
    NSString *_originalWaylandDisplay;
    NSString *_originalSessionType;
}
@end

@implementation WaylandClipboardTimeoutProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    _originalPATH = [env[@"PATH"] copy];
    _originalWaylandDisplay = [env[@"WAYLAND_DISPLAY"] copy];
    _originalSessionType = [env[@"XDG_SESSION_TYPE"] copy];
    _tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:[_tempRoot stringByAppendingPathComponent:@"bin"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    _appDelegate = [[AppDelegate alloc] init];
}

- (void)tearDown {
    if (_originalPATH) {
        STSetEnvVar("PATH", _originalPATH.UTF8String);
    }
    if (_originalWaylandDisplay) {
        STSetEnvVar("WAYLAND_DISPLAY", _originalWaylandDisplay.UTF8String);
    } else {
        STUnsetEnvVar("WAYLAND_DISPLAY");
    }
    if (_originalSessionType) {
        STSetEnvVar("XDG_SESSION_TYPE", _originalSessionType.UTF8String);
    } else {
        STUnsetEnvVar("XDG_SESSION_TYPE");
    }
    if (_tempRoot.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:_tempRoot error:NULL];
    }
    _appDelegate = nil;
    [super tearDown];
}

/// A fake wl-paste first on PATH, in a Wayland session, that runs `body` for --list-types.
- (void)installFakeWlPasteListingTypesWith:(NSString *)body {
    NSString *binDirectory = [_tempRoot stringByAppendingPathComponent:@"bin"];
    NSString *scriptPath = [binDirectory stringByAppendingPathComponent:@"wl-paste"];
    NSString *script = [NSString stringWithFormat:@"#!/bin/sh\n[ \"$1\" = --list-types ] || exit 1\n%@\n", body];
    NSError *error = nil;
    XCTAssertTrue([script writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:&error],
                  @"Failed to write fake wl-paste: %@", error);
    XCTAssertTrue([[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0755 }
                                                   ofItemAtPath:scriptPath
                                                          error:&error],
                  @"Failed to chmod fake wl-paste: %@", error);
    NSString *path = _originalPATH.length > 0 ? [NSString stringWithFormat:@"%@:%@", binDirectory, _originalPATH] : binDirectory;
    STSetEnvVar("PATH", path.UTF8String);
    STSetEnvVar("WAYLAND_DISPLAY", "wayland-test");
    STSetEnvVar("XDG_SESSION_TYPE", "wayland");
}

- (void)testListedImageTypeCounts {
    [self installFakeWlPasteListingTypesWith:@"printf 'text/plain\\nimage/png\\n'"];
    XCTAssertTrue([_appDelegate waylandClipboardHasImage]);
}

- (void)testUnansweredTypeListingGivesUpQuickly {
    // As wl-paste does on GNOME when it can't get keyboard focus.
    [self installFakeWlPasteListingTypesWith:@"exec sleep 30"];
    NSDate *start = [NSDate date];
    BOOL hasImage = [_appDelegate waylandClipboardHasImage];
    NSTimeInterval elapsed = -[start timeIntervalSinceNow];
    XCTAssertFalse(hasImage, @"No answer means no image to paste");
    XCTAssertLessThan(elapsed, 3.0, @"The Paste check waited %.1fs for wl-paste", elapsed);
}

@end
