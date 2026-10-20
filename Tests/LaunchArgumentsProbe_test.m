/*
 * LaunchArgumentsProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * GNUstep's `-Key value` command-line options aren't files to open (#68), and a launch keeps
 * the exports another instance may still be using (#294).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (LaunchArgumentsTesting)
- (NSArray<NSString *> *)imagePathsFromLaunchArguments:(NSArray<NSString *> *)arguments;
- (BOOL)launchArgumentsRequestCapture:(NSArray<NSString *> *)arguments;
@end

@interface LaunchArgumentsProbeTests : XCTestCase
@end

@implementation LaunchArgumentsProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (NSArray<NSString *> *)paths:(NSArray<NSString *> *)arguments {
    return [[[AppDelegate alloc] init] imagePathsFromLaunchArguments:[@[@"ScreenshotTool"] arrayByAddingObjectsFromArray:arguments]];
}

- (void)testOptionsAndTheirValuesAreSkipped {
    XCTAssertEqualObjects([self paths:(@[@"-GSBackend", @"libgnustep-backcsd", @"shot.png"])], (@[@"shot.png"]));
    XCTAssertEqualObjects([self paths:(@[@"shot.png", @"-GSTheme", @"Adwaita"])], (@[@"shot.png"]));
    XCTAssertEqualObjects([self paths:(@[@"-NSDebug", @"YES", @"-GSTheme", @"Adwaita", @"a.png", @"b.png"])], (@[@"a.png", @"b.png"]));
}

- (void)testPlainPathsAndEdgeCases {
    XCTAssertEqualObjects([self paths:(@[@"shot.png"])], (@[@"shot.png"]));
    XCTAssertEqualObjects([self paths:(@[])], (@[]));
    XCTAssertEqualObjects([self paths:(@[@"-GSTheme"])], (@[]), @"an option with no value");
    XCTAssertEqualObjects([self paths:(@[@"-a", @"-b", @"x.png"])], (@[]), @"x.png is -b's value");
    XCTAssertEqualObjects([self paths:(@[@"--", @"-odd-name.png"])], (@[@"-odd-name.png"]), @"after --, everything is a path");
}

/// `ScreenshotTool --capture` takes a screenshot (a keyboard shortcut of the desktop's runs it).
- (void)testCaptureFlag {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    XCTAssertTrue([delegate launchArgumentsRequestCapture:(@[@"ScreenshotTool", @"--capture"])]);
    XCTAssertTrue([delegate launchArgumentsRequestCapture:(@[@"ScreenshotTool", @"-GSTheme", @"Adwaita", @"--capture"])]);
    XCTAssertFalse([delegate launchArgumentsRequestCapture:(@[@"ScreenshotTool", @"shot.png"])]);
    XCTAssertFalse([delegate launchArgumentsRequestCapture:(@[@"ScreenshotTool", @"--", @"--capture"])],
                   @"after --, a file named --capture");
    // It takes no value: a path after it is still a path.
    XCTAssertEqualObjects([self paths:(@[@"--capture", @"shot.png"])], (@[@"shot.png"]));
}

/// Open With ▸ ScreenshotTool launches a new instance on a fresh export; clearing every export at
/// launch removed it before it opened (#294). Only old exports go.
- (void)testALaunchKeepsRecentExports {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *exports = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *recent = [exports stringByAppendingPathComponent:@"recent"];
    NSString *old = [exports stringByAppendingPathComponent:@"old"];
    for (NSString *folder in @[recent, old]) {
        XCTAssertTrue([fileManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL]);
        XCTAssertTrue([[NSData data] writeToFile:[folder stringByAppendingPathComponent:@"shot.png"] atomically:NO]);
    }
    NSDate *twoDaysAgo = [NSDate dateWithTimeIntervalSinceNow:-2 * 24 * 60 * 60];
    XCTAssertTrue([fileManager setAttributes:@{NSFileModificationDate: twoDaysAgo} ofItemAtPath:old error:NULL]);

    STRemoveExportsChangedBefore([NSURL fileURLWithPath:exports isDirectory:YES],
                                 [NSDate dateWithTimeIntervalSinceNow:-24 * 60 * 60]);

    XCTAssertTrue([fileManager fileExistsAtPath:[recent stringByAppendingPathComponent:@"shot.png"]]);
    XCTAssertFalse([fileManager fileExistsAtPath:old]);
    [fileManager removeItemAtPath:exports error:NULL];
    // No exports folder yet is fine.
    STRemoveExportsChangedBefore([NSURL fileURLWithPath:exports isDirectory:YES], [NSDate date]);
}

@end
