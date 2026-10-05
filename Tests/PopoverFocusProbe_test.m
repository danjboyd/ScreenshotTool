/*
 * PopoverFocusProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Closing a popover gives the keyboard back to the window it was shown from, and the canvas takes
 * it when that window becomes key, so tool shortcuts work straight away (#80). Key status needs an
 * active app, which a test process isn't, so the tests check the requests rather than the result.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "STFloatingPopover.h"
#import "STFloatingPopoverWindow.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (PopoverFocusTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
- (BOOL)openImageAtURL:(NSURL *)url;
- (void)windowDidBecomeKey:(NSNotification *)notification;
@end

@interface STFloatingPopover (PopoverFocusTesting)
@property (nonatomic, strong) STFloatingPopoverWindow *window;
@end

/// Counts requests to become key.
@interface STKeyRequestRecordingWindow : NSWindow
@property (nonatomic, assign) NSUInteger keyRequests;
@end

@implementation STKeyRequestRecordingWindow
- (void)makeKeyWindow {
    self.keyRequests += 1;
    [super makeKeyWindow];
}
@end

@interface PopoverFocusProbeTests : XCTestCase {
    BOOL _shouldSkip;
}
@end

@implementation PopoverFocusProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (STKeyRequestRecordingWindow *)anchorWindow {
    STKeyRequestRecordingWindow *window = [[STKeyRequestRecordingWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                                                                         styleMask:NSWindowStyleMaskTitled
                                                                                           backing:NSBackingStoreBuffered
                                                                                             defer:NO];
    [window setReleasedWhenClosed:NO];
    [window orderFront:nil];
    return window;
}

- (STFloatingPopover *)popoverShownFromWindow:(NSWindow *)window {
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 120)];
    STFloatingPopover *popover = [[STFloatingPopover alloc] initWithContentView:content];
    [popover showRelativeToRect:NSMakeRect(20, 20, 10, 10) ofView:window.contentView preferredEdge:NSMaxYEdge];
    return popover;
}

- (void)testClosingGivesTheKeyboardBackToTheWindow {
    XCTSkipIf(_shouldSkip, @"No window server");
    STKeyRequestRecordingWindow *window = [self anchorWindow];
    STFloatingPopover *popover = [self popoverShownFromWindow:window];
    XCTAssertTrue(popover.isShown);
    window.keyRequests = 0;
    [popover close];
    XCTAssertFalse(popover.isShown);
    XCTAssertEqual(window.keyRequests, 1u, @"the window it was shown from is made key again");
    [window orderOut:nil];
}

- (void)testEscapeClosesAndGivesTheKeyboardBack {
    XCTSkipIf(_shouldSkip, @"No window server");
    STKeyRequestRecordingWindow *window = [self anchorWindow];
    STFloatingPopover *popover = [self popoverShownFromWindow:window];
    window.keyRequests = 0;
    [popover.window cancelOperation:nil];
    XCTAssertFalse(popover.isShown, @"Escape closes the popover");
    XCTAssertEqual(window.keyRequests, 1u);
    [window orderOut:nil];
}

- (void)testClosingLeavesAHiddenWindowAlone {
    XCTSkipIf(_shouldSkip, @"No window server");
    STKeyRequestRecordingWindow *window = [self anchorWindow];
    STFloatingPopover *popover = [self popoverShownFromWindow:window];
    [window orderOut:nil];
    window.keyRequests = 0;
    [popover close];
    XCTAssertEqual(window.keyRequests, 0u, @"a window that has gone isn't brought back");
}

- (void)testCanvasTakesTheKeyboardWhenTheWindowBecomesKey {
    XCTSkipIf(_shouldSkip, @"No window server");
    AppDelegate *appDelegate = [[AppDelegate alloc] init];
    [appDelegate setupWindowAndContent];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:30
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"popover-focus-%@.png", [[NSUUID UUID] UUIDString]]];
    [[rep representationUsingType:NSPNGFileType properties:@{}] writeToFile:path atomically:YES];
    XCTAssertTrue([appDelegate openImageAtURL:[NSURL fileURLWithPath:path]]);

    NSWindow *window = appDelegate.window;
    [window makeFirstResponder:nil];
    [appDelegate windowDidBecomeKey:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification object:window]];
    XCTAssertEqual(window.firstResponder, (NSResponder *)appDelegate.canvasView, @"the canvas has the keyboard");

    // Text being edited keeps it.
    NSTextView *editor = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 50, 20)];
    [window.contentView addSubview:editor];
    [window makeFirstResponder:editor];
    [appDelegate windowDidBecomeKey:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification object:window]];
    XCTAssertEqual(window.firstResponder, (NSResponder *)editor, @"editing text keeps the keyboard");

    [window orderOut:nil];
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

@end
