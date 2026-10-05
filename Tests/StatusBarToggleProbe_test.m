/*
 * StatusBarToggleProbe_test.m
 * Ensures hiding the status bar collapses its reserved space so the scroll view
 * reclaiming the content height does not leave a blank strip.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "PreferencesWindowController.h"
#import "TestEnvironmentHelpers.h"

static const CGFloat kStatusBarHeight = 24.0f;

#pragma mark - Testing Category

@interface AppDelegate (StatusBarToggleTesting)
- (void)setupWindowAndContent;
- (void)resizeWindowToImageSize:(NSSize)size;
- (NSWindow *)window;
- (NSScrollView *)scrollView;
- (NSView *)statusBarView;
- (void)preferencesController:(PreferencesWindowController *)controller didToggleStatusBar:(BOOL)show;
- (void)layoutContentSubviews;
- (void)loadToolSettingsFromDefaults;
- (void)preferencesControllerRestoreDefaults:(PreferencesWindowController *)controller;
- (BOOL)statusBarVisiblePreference;
- (NSString *)toolTipForIdentifier:(NSString *)identifier;
- (void)selectTool:(ScreenshotCanvasTool)tool;
- (ScreenshotCanvasView *)canvasView;
@end

#pragma mark - Test Class

@interface StatusBarToggleProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation StatusBarToggleProbeTests

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
        [_appDelegate.window makeKeyAndOrderFront:nil];
        // The bar is off by default (#54); these tests start with it shown.
        [_appDelegate preferencesController:nil didToggleStatusBar:YES];

        // Match the normal sizing path the app uses when loading an image.
        NSSize imageSize = NSMakeSize(640.0f, 480.0f);
        [_appDelegate resizeWindowToImageSize:imageSize];
        [_appDelegate layoutContentSubviews];

    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    _appDelegate = nil;
    [super tearDown];
}

- (void)testStatusBarToggleAdjustsLayout {
    XCTSkipIf(_shouldSkip, @"No window server");

    NSView *contentView = _appDelegate.window.contentView;
    XCTAssertNotNil(contentView, @"Content view should not be nil");
    NSScrollView *scrollView = _appDelegate.scrollView;
    XCTAssertNotNil(scrollView, @"Scroll view should not be nil");
    NSView *statusBar = _appDelegate.statusBarView;
    XCTAssertNotNil(statusBar, @"Status bar view should not be nil");

    CGFloat initialContentHeight = contentView.frame.size.height;
    CGFloat initialScrollHeight = scrollView.frame.size.height;
    CGFloat initialScrollOrigin = scrollView.frame.origin.y;
    XCTAssertEqualWithAccuracy(initialScrollOrigin, kStatusBarHeight, 0.75, @"Initial scroll view origin should account for status bar height");

    // --- Test Hiding ---
    [_appDelegate preferencesController:nil didToggleStatusBar:NO];
    [_appDelegate layoutContentSubviews];

    XCTAssertLessThan(statusBar.frame.size.height, 0.5f, @"Status bar frame height should be collapsed when hidden");
    XCTAssertLessThan(scrollView.frame.origin.y, 0.5f, @"Scroll view should slide to the bottom after hiding status bar");
    XCTAssertLessThan(contentView.frame.size.height, initialContentHeight - (kStatusBarHeight - 0.5f), @"Content view should reclaim status bar height when hidden");
    XCTAssertLessThanOrEqual(scrollView.frame.size.height - initialScrollHeight, 1.0f, @"Scroll view should not grow significantly after hiding status bar");

    // --- Test Re-showing ---
    [_appDelegate preferencesController:nil didToggleStatusBar:YES];
    [_appDelegate layoutContentSubviews];

    XCTAssertEqualWithAccuracy(contentView.frame.size.height, initialContentHeight, 1.0, @"Content view height should be restored after re-showing status bar");
    XCTAssertEqualWithAccuracy(scrollView.frame.origin.y, kStatusBarHeight, 0.75, @"Scroll view origin should be restored after re-showing status bar");
}

- (void)testStatusBarIsOffUnlessChosen {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"ScreenshotToolShowStatusBar"];
    [_appDelegate loadToolSettingsFromDefaults];
    XCTAssertFalse([_appDelegate statusBarVisiblePreference], @"off by default (#54)");
    XCTAssertNil([defaults objectForKey:@"ScreenshotToolShowStatusBar"], @"nothing is saved until the user chooses");
    XCTAssertEqualWithAccuracy(_appDelegate.scrollView.frame.origin.y, 0.0, 0.75, @"the canvas reaches the bottom");

    [defaults setBool:YES forKey:@"ScreenshotToolShowStatusBar"];
    [_appDelegate loadToolSettingsFromDefaults];
    XCTAssertTrue([_appDelegate statusBarVisiblePreference], @"a saved choice to show it is kept");

    [_appDelegate preferencesControllerRestoreDefaults:nil];
    XCTAssertFalse([_appDelegate statusBarVisiblePreference]);
    XCTAssertNil([defaults objectForKey:@"ScreenshotToolShowStatusBar"]);
}

- (void)testColorControlIsTheStyleControl {
    XCTSkipIf(_shouldSkip, @"No window server");
    // With the bar hidden, the toolbar's colour control is where colour and width are set (#54).
    struct { ScreenshotCanvasTool tool; NSString *name; } cases[] = {
        { ScreenshotCanvasToolPen, @"Pen" },
        { ScreenshotCanvasToolHighlighter, @"Highlighter" },
        { ScreenshotCanvasToolArrow, @"Arrow" },
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        [_appDelegate selectTool:cases[i].tool];
        NSString *tip = [_appDelegate toolTipForIdentifier:@"com.screenshottool.toolbar.color"];
        XCTAssertTrue([tip hasPrefix:cases[i].name], @"%@", tip);
        XCTAssertTrue([tip containsString:@"width"] && [tip containsString:@" px"], @"%@ mentions the width: %@", cases[i].name, tip);
    }
}

@end
