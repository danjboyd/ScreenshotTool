/*
 * LaunchWindowSizeProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * An image given at launch is opened before the window is first shown, so the window appears at
 * the image's size rather than being resized once shown, which loses its top 39pt (the toolbar)
 * under some window managers (#60).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (LaunchWindowSizeTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
- (void)setPendingOpenPath:(NSString *)path;
- (void)openLaunchImage;
@end

@interface LaunchWindowSizeProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation LaunchWindowSizeProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        _appDelegate = [[AppDelegate alloc] init];
        [_appDelegate setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    [_appDelegate.window orderOut:nil];
    _appDelegate = nil;
    [super tearDown];
}

- (void)testLaunchImageSizesTheWindowBeforeItIsShown {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:700 pixelsHigh:450
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"launch-size-%@.png", [[NSUUID UUID] UUIDString]]];
    [[rep representationUsingType:NSPNGFileType properties:@{}] writeToFile:path atomically:YES];

    NSWindow *window = _appDelegate.window;
    XCTAssertFalse(window.isVisible, @"setup doesn't show the window");
    NSSize before = [window contentRectForFrameRect:window.frame].size;
    [_appDelegate setPendingOpenPath:path];
    [_appDelegate openLaunchImage];
    XCTAssertTrue([_appDelegate.canvasView hasImage], @"the launch image is open");
    XCTAssertFalse(window.isVisible, @"still not shown, so its size is set before it's mapped");
    NSSize after = [window contentRectForFrameRect:window.frame].size;
    XCTAssertFalse(NSEqualSizes(before, after), @"the window is sized for the image");
    XCTAssertGreaterThanOrEqual(after.width, 700.0, @"wide enough for the image");
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

@end
