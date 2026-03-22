/*
 * WaylandClipboardMirrorProbe_test.m
 * Verifies copy: mirrors PNG data to wl-copy when available on Wayland.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"
#include <string.h>

@interface AppDelegate (WaylandClipboardMirrorTesting)
- (void)copy:(id)sender;
@end

@interface WaylandClipboardMirrorProbeAppDelegate : AppDelegate
@property (nonatomic, copy) NSString *lastCopyFeedbackMessage;
@end

@implementation WaylandClipboardMirrorProbeAppDelegate

- (void)showCopyFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration {
    (void)duration;
    self.lastCopyFeedbackMessage = [message copy];
}

@end

@interface WaylandClipboardMirrorProbeTests : XCTestCase {
    WaylandClipboardMirrorProbeAppDelegate *_appDelegate;
    NSString *_tempRoot;
    NSString *_originalPATH;
    NSString *_originalWaylandDisplay;
    NSString *_originalSessionType;
}
@end

@implementation WaylandClipboardMirrorProbeTests

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
    NSError *error = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:_tempRoot
                                             withIntermediateDirectories:YES
                                                              attributes:nil
                                                                   error:&error];
    XCTAssertTrue(created, @"Failed to create temp root: %@", error);

    _appDelegate = [[WaylandClipboardMirrorProbeAppDelegate alloc] init];
    ScreenshotCanvasView *canvasView = [[ScreenshotCanvasView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 16.0f, 16.0f)];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16.0f, 16.0f)];
    [image lockFocus];
    [[NSColor colorWithCalibratedRed:0.2f green:0.6f blue:0.9f alpha:1.0f] setFill];
    NSRectFill(NSMakeRect(0.0f, 0.0f, 16.0f, 16.0f));
    [image unlockFocus];
    [canvasView loadImage:image];
    [_appDelegate setValue:canvasView forKey:@"canvasView"];
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
    STUnsetEnvVar("ST_WL_COPY_CAPTURE");
    STUnsetEnvVar("ST_WL_COPY_ARGS");

    if (_tempRoot.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:_tempRoot error:NULL];
    }
    _appDelegate = nil;
    [super tearDown];
}

- (void)installFakeWlCopy {
    NSString *binDirectory = [_tempRoot stringByAppendingPathComponent:@"bin"];
    NSString *capturePath = [_tempRoot stringByAppendingPathComponent:@"captured.png"];
    NSString *argsPath = [_tempRoot stringByAppendingPathComponent:@"wl-copy.args"];
    NSError *error = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:binDirectory
                                             withIntermediateDirectories:YES
                                                              attributes:nil
                                                                   error:&error];
    XCTAssertTrue(created, @"Failed to create bin directory: %@", error);

    NSString *scriptPath = [binDirectory stringByAppendingPathComponent:@"wl-copy"];
    NSString *script = @"#!/usr/bin/env bash\nprintf '%s\n' \"$@\" > \"$ST_WL_COPY_ARGS\"\ncat > \"$ST_WL_COPY_CAPTURE\"\n";
    BOOL wrote = [script writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    XCTAssertTrue(wrote, @"Failed to write fake wl-copy: %@", error);

    NSDictionary *attrs = @{ NSFilePosixPermissions: @0755 };
    BOOL chmodded = [[NSFileManager defaultManager] setAttributes:attrs ofItemAtPath:scriptPath error:&error];
    XCTAssertTrue(chmodded, @"Failed to chmod fake wl-copy: %@", error);

    NSString *pathPrefix = _originalPATH.length > 0 ? [NSString stringWithFormat:@"%@:%@", binDirectory, _originalPATH] : binDirectory;
    STSetEnvVar("PATH", pathPrefix.UTF8String);
    STSetEnvVar("WAYLAND_DISPLAY", "wayland-test");
    STSetEnvVar("XDG_SESSION_TYPE", "wayland");
    STSetEnvVar("ST_WL_COPY_CAPTURE", capturePath.UTF8String);
    STSetEnvVar("ST_WL_COPY_ARGS", argsPath.UTF8String);
}

- (void)testCopyMirrorsPNGToWaylandClipboardWhenWlCopyExists {
    [self installFakeWlCopy];

    [_appDelegate copy:nil];

    NSString *capturePath = [_tempRoot stringByAppendingPathComponent:@"captured.png"];
    NSData *captured = [NSData dataWithContentsOfFile:capturePath];
    XCTAssertTrue(captured.length > 8, @"wl-copy should receive PNG payload");

    const unsigned char *bytes = captured.bytes;
    static const unsigned char pngSignature[8] = { 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };
    XCTAssertEqual(memcmp(bytes, pngSignature, sizeof(pngSignature)), 0, @"Mirrored clipboard payload should be PNG");

    NSString *argsPath = [_tempRoot stringByAppendingPathComponent:@"wl-copy.args"];
    NSString *args = [NSString stringWithContentsOfFile:argsPath encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertTrue([args containsString:@"--type"], @"wl-copy should be invoked with a MIME type");
    XCTAssertTrue([args containsString:@"image/png"], @"wl-copy should mirror image/png");
    XCTAssertEqualObjects(_appDelegate.lastCopyFeedbackMessage, @"Copied image to clipboard");
}

@end
