/*
 * TitleBarToolbarProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The "Show toolbar in the title bar" preference, offered with the Adwaita theme (it writes the
 * theme's GnomeThemeHeaderBarToolbar default), and toolbar buttons that keep their clicks when
 * the toolbar sits in the theme's header bar.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "PreferencesWindowController.h"
#import "TestEnvironmentHelpers.h"

static NSString * const STHeaderBarToolbarKey = @"GnomeThemeHeaderBarToolbar";

@interface AppDelegate (TitleBarToolbarTesting)
- (void)setupWindowAndContent;
- (void)setupToolbar;
- (NSWindow *)window;
- (void)preferencesControllerRestoreDefaults:(PreferencesWindowController *)controller;
- (BOOL)preferencesControllerShowsToolbarInTitleBar:(PreferencesWindowController *)controller;
@end

@interface PreferencesWindowController (TitleBarToolbarTesting)
@property (nonatomic, strong) NSButton *titleBarToolbarCheckbox;
@property (nonatomic, strong) NSTextField *titleBarToolbarNoteLabel;
@property (nonatomic, strong) NSWindow *window;
- (void)layoutContentView;
@end

/// Stands in for the theme: whether Adwaita is active and draws the title bar.
@interface STThemeStubAppDelegate : AppDelegate
@property (nonatomic, assign) BOOL stubAdwaita;
@property (nonatomic, assign) BOOL stubHeaderBar;
@end

@implementation STThemeStubAppDelegate
- (BOOL)preferencesControllerOffersToolbarInTitleBar:(PreferencesWindowController *)controller {
    (void)controller;
    return self.stubAdwaita;
}
- (BOOL)preferencesControllerCanShowToolbarInTitleBar:(PreferencesWindowController *)controller {
    (void)controller;
    return self.stubAdwaita && self.stubHeaderBar;
}
@end

/// Records presses that reach it through the responder chain, as the header bar would take them.
@interface STPressRecordingView : NSView
@property (nonatomic, assign) NSInteger pressCount;
@end

@implementation STPressRecordingView
- (void)mouseDown:(NSEvent *)event {
    (void)event;
    self.pressCount += 1;
}
@end

@interface TitleBarToolbarProbeTests : XCTestCase {
    BOOL _shouldSkip;
    STThemeStubAppDelegate *_appDelegate;
    PreferencesWindowController *_preferences;
}
@end

@implementation TitleBarToolbarProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STHeaderBarToolbarKey];
    @try {
        [NSApplication sharedApplication];
        _appDelegate = [[STThemeStubAppDelegate alloc] init];
        [_appDelegate setupWindowAndContent];
        [_appDelegate setupToolbar];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    // The app keeps its Preferences controller for the session; let go of this one's window first.
    [_preferences.window setDelegate:nil];
    [_preferences.window orderOut:nil];
    _preferences = nil;
    // The window outlives this app delegate; its toolbar must not call back into it.
    NSToolbar *toolbar = _appDelegate.window.toolbar;
    [toolbar setDelegate:nil];
    [_appDelegate.window setToolbar:nil];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STHeaderBarToolbarKey];
    _appDelegate = nil;
    [super tearDown];
}

- (PreferencesWindowController *)preferences {
    _preferences = [[PreferencesWindowController alloc] initWithDelegate:_appDelegate];
    [_preferences refresh];
    [_preferences layoutContentView];
    return _preferences;
}

#pragma mark - Preference

- (void)testNotOfferedWithoutAdwaita {
    if (_shouldSkip) { return; }
    _appDelegate.stubAdwaita = NO;
    PreferencesWindowController *controller = [self preferences];
    XCTAssertTrue(controller.titleBarToolbarCheckbox.isHidden);
    XCTAssertTrue(controller.titleBarToolbarNoteLabel.isHidden);
}

- (void)testOfferedAndEnabledWithTheHeaderBar {
    if (_shouldSkip) { return; }
    _appDelegate.stubAdwaita = YES;
    _appDelegate.stubHeaderBar = YES;
    PreferencesWindowController *controller = [self preferences];
    XCTAssertFalse(controller.titleBarToolbarCheckbox.isHidden);
    XCTAssertTrue(controller.titleBarToolbarCheckbox.isEnabled);
    XCTAssertEqual(controller.titleBarToolbarCheckbox.state, NSControlStateValueOff, @"off unless chosen");
    XCTAssertTrue([controller.titleBarToolbarNoteLabel.stringValue hasPrefix:@"Puts the tools"]);
    XCTAssertGreaterThan(NSWidth(controller.titleBarToolbarCheckbox.frame), 100.0);
}

- (void)testDisabledWithExplanationWithoutTheHeaderBar {
    if (_shouldSkip) { return; }
    _appDelegate.stubAdwaita = YES;
    _appDelegate.stubHeaderBar = NO;
    PreferencesWindowController *controller = [self preferences];
    XCTAssertFalse(controller.titleBarToolbarCheckbox.isHidden);
    XCTAssertFalse(controller.titleBarToolbarCheckbox.isEnabled);
    XCTAssertTrue([controller.titleBarToolbarNoteLabel.stringValue containsString:@"GSX11HandlesWindowDecorations"]);
}

- (void)testToggleWritesTheThemeDefaultAndKeepsTheWindowFrame {
    if (_shouldSkip) { return; }
    _appDelegate.stubAdwaita = YES;
    _appDelegate.stubHeaderBar = YES;
    PreferencesWindowController *controller = [self preferences];
    NSToolbar *toolbar = _appDelegate.window.toolbar;
    XCTAssertNotNil(toolbar);
    NSRect frame = _appDelegate.window.frame;

    [controller.titleBarToolbarCheckbox performClick:nil];
    XCTAssertTrue([[NSUserDefaults standardUserDefaults] boolForKey:STHeaderBarToolbarKey]);
    XCTAssertTrue([_appDelegate preferencesControllerShowsToolbarInTitleBar:controller]);
    XCTAssertEqual(_appDelegate.window.toolbar, toolbar, @"the same toolbar is attached again");
    NSRect after = _appDelegate.window.frame;
    // Within a point: the backend puts the window on whole pixels.
    XCTAssertEqualWithAccuracy(NSMinX(after), NSMinX(frame), 1.0, @"the window keeps its frame");
    XCTAssertEqualWithAccuracy(NSMinY(after), NSMinY(frame), 1.0, @"the window keeps its frame");
    XCTAssertEqualWithAccuracy(NSWidth(after), NSWidth(frame), 1.0, @"the window keeps its frame");
    XCTAssertEqualWithAccuracy(NSHeight(after), NSHeight(frame), 1.0, @"the window keeps its frame");

    [controller.titleBarToolbarCheckbox performClick:nil];
    XCTAssertNotNil([[NSUserDefaults standardUserDefaults] objectForKey:STHeaderBarToolbarKey]);
    XCTAssertFalse([[NSUserDefaults standardUserDefaults] boolForKey:STHeaderBarToolbarKey],
                   @"off is written, so it overrides a global YES");
}

- (void)testRestoreDefaultsClearsTheChoice {
    if (_shouldSkip) { return; }
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:STHeaderBarToolbarKey];
    [_appDelegate preferencesControllerRestoreDefaults:nil];
    XCTAssertNil([[NSUserDefaults standardUserDefaults] objectForKey:STHeaderBarToolbarKey]);
}

#pragma mark - Clicks in the header bar

- (void)testToolbarButtonsKeepTheirPress {
    if (_shouldSkip) { return; }
    NSEvent *press = [NSEvent mouseEventWithType:NSLeftMouseDown
                                        location:NSMakePoint(5.0, 5.0)
                                   modifierFlags:0
                                       timestamp:0
                                    windowNumber:_appDelegate.window.windowNumber
                                         context:nil
                                     eventNumber:0
                                      clickCount:1
                                        pressure:1.0];
    for (NSString *className in @[@"STToolbarGlyphView", @"STToolbarColorWellView",
                                  @"STToolbarZoomButtonView", @"STToolbarUtilityButtonView"]) {
        Class viewClass = NSClassFromString(className);
        XCTAssertNotNil(viewClass, @"%@", className);
        STPressRecordingView *bar = [[STPressRecordingView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 46.0)];
        NSView *button = [[viewClass alloc] initWithFrame:NSMakeRect(10.0, 10.0, 32.0, 24.0)];
        [bar addSubview:button];
        [button mouseDown:press];
        XCTAssertEqual(bar.pressCount, 0, @"%@ passed its press on, where a header bar would start a drag", className);
    }
}

@end
