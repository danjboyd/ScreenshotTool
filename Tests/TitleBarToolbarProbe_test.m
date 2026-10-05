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
#import <objc/runtime.h>

static NSString * const STHeaderBarToolbarKey = @"GnomeThemeHeaderBarToolbar";

@interface AppDelegate (TitleBarToolbarTesting)
- (void)setupWindowAndContent;
- (void)setupToolbar;
- (NSWindow *)window;
- (void)preferencesControllerRestoreDefaults:(PreferencesWindowController *)controller;
- (void)setupMenus;
- (BOOL)preferencesControllerShowsToolbarInTitleBar:(PreferencesWindowController *)controller;
@end

@interface PreferencesWindowController (TitleBarToolbarTesting)
@property (nonatomic, strong) NSSwitch *titleBarToolbarSwitch;
@property (nonatomic, strong) NSSwitch *statusBarSwitch;
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

/// What a click on a switch does: flip it and send its action.
- (void)toggle:(NSSwitch *)control {
    [control setState:(control.state == NSControlStateValueOn) ? NSControlStateValueOff : NSControlStateValueOn];
    [NSApp sendAction:control.action to:control.target from:control];
}

- (PreferencesWindowController *)preferences {
    _preferences = [[PreferencesWindowController alloc] initWithDelegate:_appDelegate];
    [_preferences refresh];
    [_preferences layoutContentView];
    return _preferences;
}

#pragma mark - Preference

- (void)testNotOfferedWithoutAdwaita {
    XCTSkipIf(_shouldSkip, @"No window server");
    _appDelegate.stubAdwaita = NO;
    PreferencesWindowController *controller = [self preferences];
    XCTAssertTrue(controller.titleBarToolbarSwitch.isHidden);
    XCTAssertTrue(controller.titleBarToolbarNoteLabel.isHidden);
}

- (void)testOfferedAndEnabledWithTheHeaderBar {
    XCTSkipIf(_shouldSkip, @"No window server");
    _appDelegate.stubAdwaita = YES;
    _appDelegate.stubHeaderBar = YES;
    PreferencesWindowController *controller = [self preferences];
    XCTAssertFalse(controller.titleBarToolbarSwitch.isHidden);
    XCTAssertTrue(controller.titleBarToolbarSwitch.isEnabled);
    XCTAssertEqual(controller.titleBarToolbarSwitch.state, NSControlStateValueOff, @"off unless chosen");
    XCTAssertTrue([controller.titleBarToolbarNoteLabel.stringValue hasPrefix:@"Puts the tools"]);
    XCTAssertGreaterThan(NSWidth(controller.titleBarToolbarSwitch.frame), 20.0);
}

- (void)testDisabledWithExplanationWithoutTheHeaderBar {
    XCTSkipIf(_shouldSkip, @"No window server");
    _appDelegate.stubAdwaita = YES;
    _appDelegate.stubHeaderBar = NO;
    PreferencesWindowController *controller = [self preferences];
    XCTAssertFalse(controller.titleBarToolbarSwitch.isHidden);
    XCTAssertFalse(controller.titleBarToolbarSwitch.isEnabled);
    XCTAssertTrue([controller.titleBarToolbarNoteLabel.stringValue containsString:@"GSX11HandlesWindowDecorations"]);
}

- (void)testToggleWritesTheThemeDefaultAndKeepsTheWindowFrame {
    XCTSkipIf(_shouldSkip, @"No window server");
    _appDelegate.stubAdwaita = YES;
    _appDelegate.stubHeaderBar = YES;
    PreferencesWindowController *controller = [self preferences];
    NSToolbar *toolbar = _appDelegate.window.toolbar;
    XCTAssertNotNil(toolbar);
    NSRect frame = _appDelegate.window.frame;

    [self toggle:controller.titleBarToolbarSwitch];
    XCTAssertTrue([[NSUserDefaults standardUserDefaults] boolForKey:STHeaderBarToolbarKey]);
    XCTAssertTrue([_appDelegate preferencesControllerShowsToolbarInTitleBar:controller]);
    XCTAssertEqual(_appDelegate.window.toolbar, toolbar, @"the same toolbar is attached again");
    NSRect after = _appDelegate.window.frame;
    // Within a point: the backend puts the window on whole pixels.
    XCTAssertEqualWithAccuracy(NSMinX(after), NSMinX(frame), 1.0, @"the window keeps its frame");
    XCTAssertEqualWithAccuracy(NSMinY(after), NSMinY(frame), 1.0, @"the window keeps its frame");
    XCTAssertEqualWithAccuracy(NSWidth(after), NSWidth(frame), 1.0, @"the window keeps its frame");
    XCTAssertEqualWithAccuracy(NSHeight(after), NSHeight(frame), 1.0, @"the window keeps its frame");

    [self toggle:controller.titleBarToolbarSwitch];
    XCTAssertNotNil([[NSUserDefaults standardUserDefaults] objectForKey:STHeaderBarToolbarKey]);
    XCTAssertFalse([[NSUserDefaults standardUserDefaults] boolForKey:STHeaderBarToolbarKey],
                   @"off is written, so it overrides a global YES");
}

- (void)testRestoreDefaultsClearsTheChoice {
    XCTSkipIf(_shouldSkip, @"No window server");
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:STHeaderBarToolbarKey];
    [_appDelegate preferencesControllerRestoreDefaults:nil];
    XCTAssertNil([[NSUserDefaults standardUserDefaults] objectForKey:STHeaderBarToolbarKey]);
}

#pragma mark - Standard controls (#57)

- (void)testToolbarUsesStandardControls {
    XCTSkipIf(_shouldSkip, @"No window server");
    // Standard controls track their own clicks (so the theme's header bar can't take them) and are
    // drawn by the theme, under GNUstep's default theme and Adwaita alike.
    NSToolbar *toolbar = _appDelegate.window.toolbar;
    XCTAssertNotNil(toolbar);
    id<NSToolbarDelegate> delegate = (id<NSToolbarDelegate>)_appDelegate;
    for (NSString *name in @[@"copy", @"preferences"]) {
        NSString *identifier = [@"com.screenshottool.toolbar." stringByAppendingString:name];
        NSToolbarItem *item = [delegate toolbar:toolbar itemForItemIdentifier:identifier willBeInsertedIntoToolbar:YES];
        XCTAssertNotNil(item, @"%@", identifier);
        XCTAssertNil(item.view, @"%@ is a plain toolbar item the theme draws, not %@", identifier, item.view.class);
        XCTAssertNotNil(item.image, @"%@ shows its icon", identifier);
    }
    for (NSString *name in @[@"tools", @"color", @"zoom"]) {
        NSString *identifier = [@"com.screenshottool.toolbar." stringByAppendingString:name];
        NSToolbarItem *item = [delegate toolbar:toolbar itemForItemIdentifier:identifier willBeInsertedIntoToolbar:YES];
        XCTAssertNotNil(item, @"%@", identifier);
        XCTAssertTrue([item.view isKindOfClass:[NSControl class]], @"%@ is a standard control, not %@", identifier, item.view.class);
    }
}

#pragma mark - Slim toolbar (#53)

- (void)testDefaultToolbarIsToolsStyleAndCopy {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSToolbar *toolbar = _appDelegate.window.toolbar;
    id<NSToolbarDelegate> delegate = (id<NSToolbarDelegate>)_appDelegate;
    NSArray *defaults = [delegate toolbarDefaultItemIdentifiers:toolbar];
    XCTAssertEqualObjects(defaults, (@[@"com.screenshottool.toolbar.tools", @"com.screenshottool.toolbar.color",
                                       NSToolbarFlexibleSpaceItemIdentifier, @"com.screenshottool.toolbar.copy"]));
    NSArray *allowed = [delegate toolbarAllowedItemIdentifiers:toolbar];
    XCTAssertTrue([allowed containsObject:@"com.screenshottool.toolbar.zoom"], @"zoom can be added back");
    XCTAssertTrue([allowed containsObject:@"com.screenshottool.toolbar.preferences"], @"preferences can be added back");
    XCTAssertTrue(toolbar.allowsUserCustomization);
    XCTAssertTrue(toolbar.autosavesConfiguration, @"a customised toolbar is kept");
}

- (void)testZoomAndPreferencesAreInTheMenusWithShortcuts {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_appDelegate setupMenus];
    NSMenu *menu = [NSApp mainMenu];
    NSMenuItem *(^find)(NSString *) = ^NSMenuItem *(NSString *title) {
        for (NSMenuItem *top in menu.itemArray) {
            for (NSMenuItem *item in top.submenu.itemArray) {
                if ([item.title isEqualToString:title]) {
                    return item;
                }
            }
        }
        return nil;
    };
    XCTAssertEqualObjects(find(@"Fit to Window").keyEquivalent, @"0");
    XCTAssertEqualObjects(find(@"100%").keyEquivalent, @"1");
    XCTAssertEqualObjects(find(@"Zoom In").keyEquivalent, @"=");
    XCTAssertEqualObjects(find(@"Preferences…").keyEquivalent, @",");
    XCTAssertTrue(sel_isEqual(find(@"Customize Toolbar…").action, @selector(runToolbarCustomizationPalette:)));
}

#pragma mark - Declared intent (#52)

- (void)testInfoPlistDeclaresTheToolbarSuitsAHeaderBar {
    // `make tests` runs from the repository root; the app ships this file as its Info-gnustep.plist.
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:@"Resources/Info-gnustep.plist"];
    XCTAssertNotNil(info, @"the plist parses");
    XCTAssertTrue([info[@"GnomeThemeHeaderBarToolbar"] boolValue], @"the toolbar suits a header bar");
    XCTAssertNil(info[@"GnomeThemeMenuStyle"], @"menu bar or primary menu is the user's theme setting, not the app's");
}

#pragma mark - Standard Preferences (#56)

- (void)testPreferencesUseStandardControls {
    XCTSkipIf(_shouldSkip, @"No window server");
    _appDelegate.stubAdwaita = YES;
    _appDelegate.stubHeaderBar = YES;
    PreferencesWindowController *controller = [self preferences];
    XCTAssertTrue([controller.statusBarSwitch isKindOfClass:[NSSwitch class]], @"on/off settings are switches");
    XCTAssertTrue([controller.titleBarToolbarSwitch isKindOfClass:[NSSwitch class]]);
    XCTAssertFalse([controller respondsToSelector:@selector(closeButton)], @"changes apply at once: no Close button");
    XCTAssertFalse([controller respondsToSelector:@selector(interfaceThemePopUp)], @"light or dark is the theme's choice");
    // The page draws nothing of its own, so each theme draws the window its way.
    Class pageView = NSClassFromString(@"STPreferencesBackgroundView");
    XCTAssertNotNil(pageView);
    XCTAssertEqual(class_getMethodImplementation(pageView, @selector(drawRect:)),
                   class_getMethodImplementation([NSView class], @selector(drawRect:)));
}

@end
