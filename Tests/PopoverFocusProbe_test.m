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
#import "STFloatingPopoverBackgroundView.h"
#import "STThemeUtilities.h"
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
@property (nonatomic, strong) STFloatingPopoverBackgroundView *backgroundView;
@property (nonatomic, assign) BOOL themeDrawsPanel;
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

// On Windows, hiding the popover makes Windows activate the window behind it, and the win32
// backend turns that into a makeKeyWindow of its own (from MainWndProc, during orderOut:), so
// the app's own request can't be counted apart from it.
#if defined(_WIN32)
static const BOOL STBackendRequestsKeyOnClose = YES;
#else
static const BOOL STBackendRequestsKeyOnClose = NO;
#endif

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

#if defined(GNUSTEP)
// The drawn popover's own focus handling; on macOS STFloatingPopover is AppKit's NSPopover.
- (void)testClosingGivesTheKeyboardBackToTheWindow {
    XCTSkipIf(_shouldSkip, @"No window server");
    STKeyRequestRecordingWindow *window = [self anchorWindow];
    STFloatingPopover *popover = [self popoverShownFromWindow:window];
    XCTAssertTrue(popover.isShown);
    window.keyRequests = 0;
    [popover close];
    XCTAssertFalse(popover.isShown);
    if (STBackendRequestsKeyOnClose) {
        [window orderOut:nil];
        XCTSkipIf(YES, @"The Windows backend makes the window key itself on close, so the app's request can't be counted");
    }
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
    if (STBackendRequestsKeyOnClose) {
        [window orderOut:nil];
        XCTSkipIf(YES, @"The Windows backend makes the window key itself on close, so the app's request can't be counted");
    }
    XCTAssertEqual(window.keyRequests, 1u);
    [window orderOut:nil];
}

- (void)testAPopoverWithoutAnArrowIsJustItsContent {
    XCTSkipIf(_shouldSkip, @"No window server");
    STKeyRequestRecordingWindow *window = [self anchorWindow];
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 120)];

    STFloatingPopover *pointing = [[STFloatingPopover alloc] initWithContentView:content];
    [pointing showRelativeToRect:NSMakeRect(20, 20, 10, 10) ofView:window.contentView preferredEdge:NSMaxYEdge];
    CGFloat pointingHeight = NSHeight(pointing.window.frame);
    [pointing close];
    XCTAssertGreaterThan(pointingHeight, 120.0, @"a popover is taller than its content by its arrow");

    STFloatingPopover *dropdown = [[STFloatingPopover alloc] initWithContentView:content];
    dropdown.showsArrow = NO;
    [dropdown showRelativeToRect:NSMakeRect(20, 20, 10, 10) ofView:window.contentView preferredEdge:NSMaxYEdge];
    XCTAssertEqualWithAccuracy(NSHeight(dropdown.window.frame), 120.0, 0.5, @"without an arrow, the window is the content's height");
    XCTAssertEqualWithAccuracy(NSWidth(dropdown.window.frame), 200.0, 0.5);
    XCTAssertEqualWithAccuracy(NSHeight(content.frame), 120.0, 0.5, @"the content keeps its height");
    [dropdown close];
    [window orderOut:nil];
}

- (void)testThePanelIsMarkedForThemesThatDrawPopovers {
    XCTSkipIf(_shouldSkip, @"No window server");
    STKeyRequestRecordingWindow *window = [self anchorWindow];
    STFloatingPopover *popover = [self popoverShownFromWindow:window];
    // A theme finds the mark by name (#67), so it must be registered with the runtime.
    Protocol *mark = NSProtocolFromString(@"GSThemePopoverPanel");
    XCTAssertNotNil(mark);
    XCTAssertTrue([popover.window conformsToProtocol:mark]);
    XCTAssertEqual(popover.backgroundView.drawsPanel, !STThemeDrawsPopoverPanels(), @"the app draws the panel unless the theme says it does");
    [popover close];
    [window orderOut:nil];
}

- (void)testAThemeThatDrawsThePanelGetsItWithoutAnArrow {
    XCTSkipIf(_shouldSkip, @"No window server");
    STKeyRequestRecordingWindow *window = [self anchorWindow];
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 120)];
    STFloatingPopover *popover = [[STFloatingPopover alloc] initWithContentView:content];
    popover.themeDrawsPanel = YES;
    [popover showRelativeToRect:NSMakeRect(20, 20, 10, 10) ofView:window.contentView preferredEdge:NSMaxYEdge];
    XCTAssertFalse(popover.backgroundView.drawsPanel, @"the app draws no panel of its own");
    XCTAssertEqualWithAccuracy(NSHeight(popover.window.frame), 120.0, 0.5, @"and no arrow: the window is the content's height");
    XCTAssertTrue([popover.window canBecomeKeyWindow], @"its sliders and fields still take the keyboard");
    [popover close];
    [window orderOut:nil];
}

- (void)testEscapeRunsTheCloseHandler {
    XCTSkipIf(_shouldSkip, @"No window server");
    STKeyRequestRecordingWindow *window = [self anchorWindow];
    STFloatingPopover *popover = [self popoverShownFromWindow:window];
    __block NSUInteger closes = 0;
    popover.didCloseHandler = ^{
        closes += 1;
    };
    [popover.window cancelOperation:nil];
    XCTAssertEqual(closes, 1u, @"closing with Escape runs the handler");
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
#else
- (void)testCloseHidesThePopoverAtOnce {
    XCTSkipIf(_shouldSkip, @"No window server");
    STKeyRequestRecordingWindow *window = [self anchorWindow];
    STFloatingPopover *popover = [self popoverShownFromWindow:window];
    XCTAssertTrue(popover.isShown);
    [popover close];
    XCTAssertFalse(popover.isShown, @"callers toggle on -isShown right after closing");
    [window orderOut:nil];
}
#endif

- (void)testClosingRunsTheCloseHandlerOnce {
    XCTSkipIf(_shouldSkip, @"No window server");
    STKeyRequestRecordingWindow *window = [self anchorWindow];
    STFloatingPopover *popover = [self popoverShownFromWindow:window];
    __block NSUInteger closes = 0;
    popover.didCloseHandler = ^{
        closes += 1;
    };
    [popover close];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertEqual(closes, 1u, @"the handler runs once when the popover closes");
    [popover close];
    XCTAssertEqual(closes, 1u, @"closing a closed popover doesn't run it again");
    [window orderOut:nil];
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
