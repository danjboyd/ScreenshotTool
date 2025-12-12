/*
 * CropUndoWindowProbe_test.m
 * Copyright (C) 2025 Daniel Boyd
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"

#pragma mark - Testing Categories

@interface AppDelegate (CropUndoWindowTesting)
- (void)setupWindowAndContent;
- (void)resizeWindowToImageSize:(NSSize)size;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
@end

#pragma mark - Test Class

@interface CropUndoWindowProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation CropUndoWindowProbeTests

+ (void)load {
    char templatePath[] = "/tmp/ScreenshotToolDefaultsXXXXXX";
    char *defaultsDir = mkdtemp(templatePath);
    if (defaultsDir) {
        setenv("GNUSTEP_DEFAULTS_ROOT", defaultsDir, 1);
        char defaultsFile[PATH_MAX];
        snprintf(defaultsFile, sizeof(defaultsFile), "%s/GNUstepDefaults.plist", defaultsDir);
        setenv("GNUSTEP_USER_DEFAULTS", defaultsFile, 1);
    }
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
    _appDelegate = nil;
    [super tearDown];
}

#pragma mark - Helpers

- (NSImage *)createFilledImageOfSize:(NSSize)size {
    XCTAssertTrue(size.width > 0.0 && size.height > 0.0);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor colorWithCalibratedRed:0.2 green:0.4 blue:0.8 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    [image unlockFocus];
    return image;
}

- (NSSize)contentSizeForWindow:(NSWindow *)window {
    XCTAssertNotNil(window);
    return [window contentRectForFrameRect:window.frame].size;
}

#pragma mark - Test

- (void)testWindowResizesAfterCropAndUndo {
    if (_shouldSkip) return;

    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSWindow *window = _appDelegate.window;
    XCTAssertNotNil(canvas, @"Canvas should not be nil");
    XCTAssertNotNil(window, @"Window should not be nil");

    NSImage *originalImage = [self createFilledImageOfSize:NSMakeSize(640.0, 480.0)];
    XCTAssertNotNil(originalImage, @"Failed to create original image");
    
    canvas.image = originalImage;
    [_appDelegate resizeWindowToImageSize:originalImage.size];

    NSSize originalContent = [self contentSizeForWindow:window];
    XCTAssertTrue(originalContent.width > 0.0 && originalContent.height > 0.0, @"Original window size should be valid");

    NSImage *croppedImage = [self createFilledImageOfSize:NSMakeSize(200.0, 150.0)];
    XCTAssertNotNil(croppedImage, @"Failed to create cropped image");
    
    canvas.image = croppedImage;
    [_appDelegate resizeWindowToImageSize:croppedImage.size];

    NSSize croppedContent = [self contentSizeForWindow:window];
    XCTAssertTrue(croppedContent.width < originalContent.width, @"Window width should shrink after crop");
    XCTAssertTrue(croppedContent.height < originalContent.height, @"Window height should shrink after crop");

    canvas.image = originalImage;
    [[NSNotificationCenter defaultCenter] postNotificationName:ScreenshotCanvasViewDidRestoreStateNotification
                                                        object:canvas];

    NSSize restoredContent = [self contentSizeForWindow:window];
    CGFloat tolerance = 0.51f;
    XCTAssertEqualWithAccuracy(restoredContent.width, originalContent.width, tolerance, @"Window width should be restored after undo");
    XCTAssertEqualWithAccuracy(restoredContent.height, originalContent.height, tolerance, @"Window height should be restored after undo");
}

@end
