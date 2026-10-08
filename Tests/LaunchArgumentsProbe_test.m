/*
 * LaunchArgumentsProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * GNUstep's `-Key value` command-line options aren't files to open (#68).
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

@end
