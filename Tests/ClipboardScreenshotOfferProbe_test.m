/*
 * ClipboardScreenshotOfferProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * An image another app copies (a snip, Win+Shift+S) can be offered for opening: the status bar's
 * Open New Screenshot, and the empty state's Paste under that name (#275). Off by default, and
 * only where the platform reports clipboard changes (Windows). The app's own copies are never
 * offered.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotToolSettings.h"
#import "PreferencesWindowController.h"
#import "STWindowsIntegration.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (ClipboardOfferTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (NSView *)emptyStateView;
- (NSButton *)statusOfferButton;
- (BOOL)clipboardScreenshotOffered;
- (void)setClipboardScreenshotOffered:(BOOL)offered;
- (void)updateClipboardScreenshotOffer;
@end

@interface PreferencesWindowController (ClipboardOfferTesting)
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, assign) NSInteger currentSection;
@property (nonatomic, strong) NSButton *restoreDefaultsButton;
@property (nonatomic, strong) NSSwitch *keepVisibleSwitch;
@property (nonatomic, strong) NSSwitch *offerClipboardSwitch;
- (void)layoutContentView;
- (void)offerClipboardToggled:(NSSwitch *)sender;
@end

@interface ClipboardScreenshotOfferProbeTests : XCTestCase
@end

@implementation ClipboardScreenshotOfferProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

/// A delegate with its window on screen, or nil without a window server.
- (AppDelegate *)delegateWithVisibleWindow {
    AppDelegate *delegate = nil;
    @try {
        [NSApplication sharedApplication];
        delegate = [[AppDelegate alloc] init];
        [delegate setupWindowAndContent];
        [delegate.window orderFront:nil];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        return nil;
    }
    return delegate.window.isVisible ? delegate : nil;
}

/// Preferences > Workspace has the switch where the platform can offer, below Keep this window
/// visible; elsewhere it's hidden. It's off by default and sets the preference.
- (void)testOfferSwitchShowsOnlyWhereThePlatformCanOffer {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsOfferClipboardScreenshotsKey];
    AppDelegate *delegate = [self delegateWithVisibleWindow];
    if (!delegate) {
        return;
    }
    PreferencesWindowController *preferences =
        [[PreferencesWindowController alloc] initWithDelegate:(id<PreferencesWindowControllerDelegate>)delegate];
    preferences.currentSection = 3; // Workspace
    [preferences refresh];
    [preferences layoutContentView];

    NSSwitch *offer = preferences.offerClipboardSwitch;
    XCTAssertNotNil(offer);
    BOOL supported = STWindowsClipboardIsNative();
    XCTAssertEqual(offer.isHidden, !supported, @"only where clipboard changes are reported");
    if (supported) {
        XCTAssertEqual(offer.state, NSControlStateValueOff, @"off by default");
        XCTAssertLessThanOrEqual(NSMaxY(offer.frame), NSMinY(preferences.keepVisibleSwitch.frame),
                                 @"below Keep this window visible");
        XCTAssertGreaterThanOrEqual(NSMinY(offer.frame), NSMaxY(preferences.restoreDefaultsButton.frame),
                                    @"above Restore Defaults");
        offer.state = NSControlStateValueOn;
        [preferences offerClipboardToggled:offer];
        XCTAssertTrue([[NSUserDefaults standardUserDefaults] boolForKey:STDefaultsOfferClipboardScreenshotsKey]);
    }

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsOfferClipboardScreenshotsKey];
    [preferences.window setDelegate:nil];
    [preferences.window orderOut:nil];
    [delegate.window orderOut:nil];
}

/// While offered, the status bar shows Open New Screenshot and the empty state's Paste takes that
/// name; withdrawn, both go back.
- (void)testOfferShowsInTheStatusBarAndTheEmptyState {
    AppDelegate *delegate = [self delegateWithVisibleWindow];
    if (!delegate) {
        return;
    }
    NSButton *paste = [delegate.emptyStateView viewWithTag:5];
    XCTAssertNotNil(paste);
    XCTAssertEqualObjects(paste.title, @"Paste");
    XCTAssertTrue(delegate.statusOfferButton.isHidden);

    [delegate setClipboardScreenshotOffered:YES];
    XCTAssertFalse(delegate.statusOfferButton.isHidden);
    XCTAssertEqualObjects(paste.title, @"Open New Screenshot");
    XCTAssertGreaterThanOrEqual(NSWidth(paste.frame), ceil([[paste cell] cellSize].width), @"wide enough for its title");

    [delegate setClipboardScreenshotOffered:NO];
    XCTAssertTrue(delegate.statusOfferButton.isHidden);
    XCTAssertEqualObjects(paste.title, @"Paste");
    [delegate.window orderOut:nil];
}

/// An image the app copies itself is never offered, even with the preference on; nor is anything
/// with it off.
- (void)testOwnCopiesAndThePreferenceOffAreNotOffered {
    if (!STWindowsClipboardIsNative()) {
        return;
    }
    AppDelegate *delegate = [self delegateWithVisibleWindow];
    if (!delegate) {
        return;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:4 pixelsHigh:4
                                                                bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                               colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSData *png = [rep representationUsingType:NSPNGFileType properties:@{}];
    XCTAssertTrue(STWindowsClipboardWritePNGData(png));
    XCTAssertFalse(STWindowsClipboardImageIsFromAnotherApp(NO), @"the app's own copy");

    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:STDefaultsOfferClipboardScreenshotsKey];
    [delegate updateClipboardScreenshotOffer];
    XCTAssertFalse(delegate.clipboardScreenshotOffered, @"own copies aren't offered");

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsOfferClipboardScreenshotsKey];
    [delegate setClipboardScreenshotOffered:YES];
    [delegate updateClipboardScreenshotOffer];
    XCTAssertFalse(delegate.clipboardScreenshotOffered, @"off by default");
    [delegate.window orderOut:nil];
}

@end
