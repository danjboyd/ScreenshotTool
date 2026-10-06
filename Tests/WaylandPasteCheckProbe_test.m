/*
 * WaylandPasteCheckProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Whether Paste is available is checked whenever the window becomes key. In a Wayland session
 * that check must not run wl-paste: on GNOME wl-paste takes keyboard focus to read the
 * clipboard, so the window stopped being key, became key again and checked again, and its title
 * bar flickered (#90). The pasteboard already sees an image copied in a Wayland app, through
 * XWayland's clipboard.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (WaylandPasteCheckTesting)
- (void)setupWindowAndContent;
- (void)refreshPasteAvailability;
- (BOOL)clipboardHasImage;
@end

@interface WaylandPasteCheckTestDelegate : AppDelegate
@property (nonatomic, strong) NSPasteboard *testPasteboard;
@end

@implementation WaylandPasteCheckTestDelegate
- (NSPasteboard *)clipboardPasteboard {
    return self.testPasteboard;
}
@end

@interface WaylandPasteCheckProbeTests : XCTestCase {
    BOOL _shouldSkip;
    WaylandPasteCheckTestDelegate *_appDelegate;
    NSString *_tempRoot;
    NSString *_originalPATH;
    NSString *_originalWaylandDisplay;
    NSString *_originalSessionType;
}
@end

@implementation WaylandPasteCheckProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    _originalPATH = [env[@"PATH"] copy];
    _originalWaylandDisplay = [env[@"WAYLAND_DISPLAY"] copy];
    _originalSessionType = [env[@"XDG_SESSION_TYPE"] copy];
    _tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:[_tempRoot stringByAppendingPathComponent:@"bin"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    @try {
        [NSApplication sharedApplication];
        _appDelegate = [[WaylandPasteCheckTestDelegate alloc] init];
        _appDelegate.testPasteboard = [NSPasteboard pasteboardWithUniqueName];
        [_appDelegate setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
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
    [_appDelegate.testPasteboard releaseGlobally];
    _appDelegate = nil;
    if (_tempRoot.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:_tempRoot error:NULL];
    }
    [super tearDown];
}

/// A fake wl-paste first on PATH, in a Wayland session, that notes each run and offers a PNG.
- (NSString *)installRecordingWlPaste {
    NSString *binDirectory = [_tempRoot stringByAppendingPathComponent:@"bin"];
    NSString *scriptPath = [binDirectory stringByAppendingPathComponent:@"wl-paste"];
    NSString *runsPath = [_tempRoot stringByAppendingPathComponent:@"wl-paste.runs"];
    // The path is written into the script rather than passed through the environment, which
    // NSTask may hand to the child from GNUstep's launch-time snapshot (#41).
    NSString *script = [NSString stringWithFormat:@"#!/bin/sh\necho \"$*\" >> '%@'\nprintf 'image/png\\n'\n", runsPath];
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
    return runsPath;
}

- (void)testPasteCheckDoesNotRunWlPaste {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSString *runsPath = [self installRecordingWlPaste];
    [_appDelegate.testPasteboard declareTypes:@[] owner:nil];

    [_appDelegate refreshPasteAvailability];
    BOOL hasImage = [_appDelegate clipboardHasImage];

    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:runsPath],
                   @"The Paste check ran wl-paste: %@",
                   [NSString stringWithContentsOfFile:runsPath encoding:NSUTF8StringEncoding error:NULL]);
    XCTAssertFalse(hasImage, @"An empty pasteboard has no image, whatever wl-paste would say");
}

@end
