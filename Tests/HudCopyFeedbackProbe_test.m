/*
 * HudCopyFeedbackProbe_test.m
 * Ensures command results show in the HUD, whether the status bar is hidden or shown.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "PreferencesWindowController.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (HudCopyFeedbackTesting)
- (void)setupWindowAndContent;
- (void)preferencesController:(PreferencesWindowController *)controller didToggleStatusBar:(BOOL)show;
- (void)showCommandResultMessage:(NSString *)message duration:(NSTimeInterval)duration;
- (void)hideHUDMessage;
- (NSWindow *)window;
- (NSView *)hudView;
- (NSTextField *)statusTextField;
- (void)showTransientFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration;
@end

@interface HudCopyFeedbackProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation HudCopyFeedbackProbeTests

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
    XCTSkipIf(_shouldSkip, @"No window server");

    [_appDelegate preferencesController:nil didToggleStatusBar:NO];
    [_appDelegate showCommandResultMessage:@"Copied image to clipboard" duration:0.25];

    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];

    NSView *hudView = _appDelegate.hudView;
    XCTAssertNotNil(hudView, @"HUD view should be created when showing copy feedback");
    XCTAssertFalse(hudView.isHidden, @"HUD view should be visible after showing copy feedback");
    XCTAssertNotNil(hudView.superview, @"HUD view should be attached to a superview");

    [_appDelegate hideHUDMessage];
    // The fade takes 0.2s; a loaded CI runner can take longer to run it out, so wait up to 2s.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while ([deadline timeIntervalSinceNow] > 0) {
#if defined(GNUSTEP)
        BOOL hidden = hudView.isHidden;
#else
        BOOL hidden = !hudView.window.isVisible;
#endif
        if (hidden) {
            break;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
#if defined(GNUSTEP)
    XCTAssertTrue(hudView.isHidden, @"HUD view should hide after dismissing");
#else
    // On macOS the notice is a child window, ordered out when it hides.
    XCTAssertFalse(hudView.window.isVisible, @"HUD window should hide after dismissing");
#endif
}

- (BOOL)hudIsShowing {
#if defined(GNUSTEP)
    return _appDelegate.hudView && !_appDelegate.hudView.isHidden && _appDelegate.hudView.superview;
#else
    return _appDelegate.hudView.window.isVisible;
#endif
}

/// A command's result goes to the HUD even with the status bar on, where it used to be small grey
/// text for a moment (#333).
- (void)testCommandResultsUseTheHudWithTheStatusBarShown {
    XCTSkipIf(_shouldSkip, @"No window server");

    [_appDelegate preferencesController:nil didToggleStatusBar:YES];
    NSString *before = _appDelegate.statusTextField.stringValue ?: @"";
    [_appDelegate showCommandResultMessage:@"No email addresses or phone numbers found" duration:2.5];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];

    XCTAssertTrue([self hudIsShowing], @"A command result should show in the HUD with the status bar on");
    XCTAssertEqualObjects(_appDelegate.statusTextField.stringValue ?: @"", before,
                          @"The status bar should keep its passive text");
    [_appDelegate hideHUDMessage];
}

/// Passive status still goes to the status bar when it's shown.
- (void)testPassiveStatusStaysInTheStatusBar {
    XCTSkipIf(_shouldSkip, @"No window server");

    [_appDelegate preferencesController:nil didToggleStatusBar:YES];
    [_appDelegate showTransientFeedbackMessage:@"Echo…" duration:5.0];
    XCTAssertEqualObjects(_appDelegate.statusTextField.stringValue, @"Echo…");
    XCTAssertFalse([self hudIsShowing], @"Passive status shouldn't take the HUD");
}

@end
