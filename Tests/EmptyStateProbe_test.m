/*
 * EmptyStateProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * With no image open the window shows an empty state (icon, "No Image", Open…, Take Screenshot…
 * and Paste) in the canvas's place; opening an image brings the canvas back (#55).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "STScreenshotCapture.h"
#import "TestEnvironmentHelpers.h"
#import <objc/runtime.h>

@interface AppDelegate (EmptyStateTesting)
- (void)setupWindowAndContent;
- (void)layoutContentSubviews;
- (NSScrollView *)scrollView;
- (NSView *)emptyStateView;
- (ScreenshotCanvasView *)canvasView;
- (BOOL)openImageAtURL:(NSURL *)url;
@end

@interface EmptyStateProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation EmptyStateProbeTests

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
    _appDelegate = nil;
    [super tearDown];
}

/// The button titled `title`: an NSButton, or on macOS 13 and later Open…'s NSComboButton.
- (id)buttonTitled:(NSString *)title {
    for (NSView *view in _appDelegate.emptyStateView.subviews) {
        if ([view isKindOfClass:[NSControl class]] && [view respondsToSelector:@selector(title)] &&
            [[(id)view title] isEqualToString:title]) {
            return view;
        }
    }
    return nil;
}

- (void)testEmptyStateWithoutAnImage {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_appDelegate layoutContentSubviews];
    XCTAssertFalse([_appDelegate.canvasView hasImage]);
    XCTAssertFalse(_appDelegate.emptyStateView.isHidden, @"the empty state shows");
    XCTAssertTrue(_appDelegate.scrollView.isHidden, @"no blank canvas or empty scroller behind it");
    XCTAssertTrue(NSEqualRects(_appDelegate.emptyStateView.frame, _appDelegate.scrollView.frame), @"in the canvas's place");

    NSControl *open = [self buttonTitled:@"Open…"];
    NSButton *capture = [self buttonTitled:@"Take Screenshot…"];
    NSButton *paste = [self buttonTitled:@"Paste"];
    XCTAssertTrue(sel_isEqual(open.action, @selector(openDocument:)));
    XCTAssertTrue(sel_isEqual(capture.action, @selector(takeScreenshot:)));
    XCTAssertTrue(sel_isEqual(paste.action, @selector(pasteAsNewImage:)));
    XCTAssertEqual(open.target, _appDelegate);
    XCTAssertEqual(capture.target, _appDelegate);
    XCTAssertEqual(capture.isHidden, ![STScreenshotCapture isAvailable], @"only where the system can capture");
    XCTAssertTrue(NSContainsRect(_appDelegate.emptyStateView.bounds, open.frame), @"the buttons are inside the view");
    XCTAssertTrue(NSContainsRect(_appDelegate.emptyStateView.bounds, capture.frame));
    XCTAssertTrue(NSContainsRect(_appDelegate.emptyStateView.bounds, paste.frame));
    if (!capture.isHidden) {
        XCTAssertLessThan(NSMaxX(open.frame), NSMinX(capture.frame), @"Open…, Take Screenshot…, Paste");
        XCTAssertLessThan(NSMaxX(capture.frame), NSMinX(paste.frame));
        XCTAssertEqualWithAccuracy(NSMidY(open.frame), NSMidY(capture.frame), 1.0, @"in one row");
    }
}

#if !defined(GNUSTEP)
/// macOS's Open… is AppKit's split button: its arrow lists recent files, and Return still opens.
- (void)testOpenListsRecentFilesOnMacOS {
    XCTSkipIf(_shouldSkip, @"No window server");
    if (@available(macOS 13.0, *)) {
        [_appDelegate layoutContentSubviews];
        NSComboButton *open = [self buttonTitled:@"Open…"];
        XCTAssertTrue([open isKindOfClass:[NSComboButton class]]);
        XCTAssertEqual(open.style, NSComboButtonStyleSplit);
        // AppKit doesn't open an empty menu (nor ask its delegate to fill it), so it's filled up front.
        XCTAssertGreaterThan(open.menu.numberOfItems, 0, @"recent files, or a placeholder when there are none");
        XCTAssertEqual(open.menu.delegate, (id)_appDelegate, @"and refreshed as it opens");

        NSEvent *returnKey = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                             timestamp:0 windowNumber:0 context:nil characters:@"\r"
                           charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
        NSEvent *commandReturn = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                                             modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:0
                                                   context:nil characters:@"\r" charactersIgnoringModifiers:@"\r"
                                                 isARepeat:NO keyCode:36];
        // Return is taken (it opens the panel, which isn't run here: the action goes to a stand-in).
        id target = open.target;
        open.target = nil;
        open.action = @selector(description);
        XCTAssertTrue([open performKeyEquivalent:returnKey], @"Return opens, as the default button did");
        XCTAssertFalse([open performKeyEquivalent:commandReturn], @"not with a modifier");
        open.target = target;
        open.action = @selector(openDocument:);
    }
}
#endif

- (void)testOpeningAnImageShowsTheCanvas {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:30
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"empty-state-%@.png", [[NSUUID UUID] UUIDString]]];
    [[rep representationUsingType:NSPNGFileType properties:@{}] writeToFile:path atomically:YES];
    XCTAssertTrue([_appDelegate openImageAtURL:[NSURL fileURLWithPath:path]]);
    XCTAssertTrue(_appDelegate.emptyStateView.isHidden);
    XCTAssertFalse(_appDelegate.scrollView.isHidden);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

@end
