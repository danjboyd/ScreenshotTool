/*
 * HudCopyFeedbackProbe_test.m
 * Ensures copy feedback shows a HUD when the status bar is hidden.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "PreferencesWindowController.h"

@interface AppDelegate (HudCopyFeedbackTesting)
- (void)setupWindowAndContent;
- (void)preferencesController:(PreferencesWindowController *)controller didToggleStatusBar:(BOOL)show;
- (void)showCopyFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration;
- (void)hideHUDMessage;
- (NSWindow *)window;
- (NSView *)hudView;
@end

@interface HudCopyFeedbackProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation HudCopyFeedbackProbeTests

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
        [_appDelegate.window makeKeyAndOrderFront:nil];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    _appDelegate = nil;
    [super tearDown];
}

- (void)testHudAppearsWhenStatusBarHidden {
    if (_shouldSkip) return;

    [_appDelegate preferencesController:nil didToggleStatusBar:NO];
    [_appDelegate showCopyFeedbackMessage:@"Copied image to clipboard" duration:0.25];

    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];

    NSView *hudView = _appDelegate.hudView;
    XCTAssertNotNil(hudView, @"HUD view should be created when showing copy feedback");
    XCTAssertFalse(hudView.isHidden, @"HUD view should be visible after showing copy feedback");
    XCTAssertNotNil(hudView.superview, @"HUD view should be attached to a superview");

    [_appDelegate hideHUDMessage];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.30]];
    XCTAssertTrue(hudView.isHidden, @"HUD view should hide after dismissing");
}

@end
