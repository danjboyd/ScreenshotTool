/*
 * EmptyStateProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * With no image open the window shows an empty state (icon, the app's name, Take Screenshot, Open… and
 * Paste, in a dashed drop outline) in the canvas's place, and the drawing tools are disabled;
 * opening an image brings the canvas and the tools back (#55, #221).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "STScreenshotCapture.h"
#import "STEmptyStateView.h"
#import "TestEnvironmentHelpers.h"
#import <objc/runtime.h>

@interface AppDelegate (EmptyStateTesting)
- (void)setupWindowAndContent;
- (void)layoutContentSubviews;
- (NSScrollView *)scrollView;
- (NSView *)emptyStateView;
- (ScreenshotCanvasView *)canvasView;
- (BOOL)openImageAtURL:(NSURL *)url;
- (NSSegmentedControl *)toolbarToolSegmentedControl;
- (NSToolbarItem *)toolbarItemForToolControl;
- (NSMutableArray<NSString *> *)recentDocumentPaths;
- (void)setRecentDocumentPaths:(NSMutableArray<NSString *> *)paths;
- (void)refreshEmptyStateRecents;
- (void)layoutEmptyStateViewInFrame:(NSRect)frame;
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

/// The control whose action is `action`.
- (id)controlWithAction:(SEL)action {
    for (NSView *view in _appDelegate.emptyStateView.subviews) {
        if ([view isKindOfClass:[NSControl class]] && sel_isEqual([(NSControl *)view action], action)) {
            return view;
        }
    }
    return nil;
}

- (NSString *)writeSampleImage {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:30
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"empty-state-%@.png", [[NSUUID UUID] UUIDString]]];
    [[rep representationUsingType:NSPNGFileType properties:@{}] writeToFile:path atomically:YES];
    return path;
}

- (void)testEmptyStateWithoutAnImage {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_appDelegate layoutContentSubviews];
    XCTAssertFalse([_appDelegate.canvasView hasImage]);
    XCTAssertFalse(_appDelegate.emptyStateView.isHidden, @"the empty state shows");
    XCTAssertTrue(_appDelegate.scrollView.isHidden, @"no blank canvas or empty scroller behind it");
    XCTAssertTrue(NSEqualRects(_appDelegate.emptyStateView.frame, _appDelegate.scrollView.frame), @"in the canvas's place");

    NSControl *open = [self buttonTitled:@"Open…"];
    NSButton *capture = [self controlWithAction:@selector(takeScreenshot:)];
    XCTAssertTrue([capture.title hasPrefix:@"Take Screenshot"], @"titled, with its shortcut after");
    XCTAssertTrue([_appDelegate.emptyStateView isKindOfClass:[STEmptyStateView class]], @"in the dashed drop outline");
    NSTextField *heading = [_appDelegate.emptyStateView viewWithTag:2];
    XCTAssertEqualObjects(heading.stringValue, @"ScreenshotTool");
    NSTextField *detail = [_appDelegate.emptyStateView viewWithTag:3];
    XCTAssertLessThanOrEqual(NSWidth(detail.frame), 480.0, @"the line under the heading wraps");
    XCTAssertTrue(NSContainsRect(_appDelegate.emptyStateView.bounds, detail.frame));
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
        XCTAssertLessThan(NSMaxX(capture.frame), NSMinX(open.frame), @"Take Screenshot, Open…, Paste");
        XCTAssertLessThan(NSMaxX(open.frame), NSMinX(paste.frame));
        XCTAssertEqualWithAccuracy(NSMidY(open.frame), NSMidY(capture.frame), 1.0, @"in one row");
        XCTAssertNotEqualObjects(capture.keyEquivalent, @"\r", @"the accent button, but Return stays with Open… (#103)");
    }
}

#if !defined(GNUSTEP)
/// Take Screenshot is white on the accent only while its window is key; otherwise AppKit draws the
/// bezel grey, so its title takes the label colours. The key hint is shown once, however often the
/// title is refreshed.
- (void)testAccentButtonTitleReadsWhenTheWindowIsntKey {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_appDelegate layoutContentSubviews];
    STAccentButton *capture = [self controlWithAction:@selector(takeScreenshot:)];
    XCTAssertTrue([capture isKindOfClass:[STAccentButton class]]);
    [capture setEnabled:NO];
    [capture setEnabled:YES];
    NSAttributedString *title = capture.attributedTitle;
    XCTAssertEqual([title.string componentsSeparatedByString:@"⇧⌘T"].count, 2u, @"the hint once: %@", title.string);
    XCTAssertTrue([title.string hasPrefix:@"Take Screenshot"]);
    if (!capture.window.isKeyWindow) {
        NSColor *colour = [title attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
        XCTAssertEqualObjects(colour, [NSColor labelColor], @"not white on the grey bezel of a window that isn't key");
    }
}

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

/// The drawing tools need an image: disabled in the empty state, enabled once one opens (#221).
- (void)testDrawingToolsFollowTheImage {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_appDelegate toolbarItemForToolControl];
    [_appDelegate layoutContentSubviews];
    XCTAssertNotNil(_appDelegate.toolbarToolSegmentedControl);
    XCTAssertFalse(_appDelegate.toolbarToolSegmentedControl.isEnabled, @"no image, no drawing");
    for (NSInteger segment = 0; segment < _appDelegate.toolbarToolSegmentedControl.segmentCount; segment++) {
        XCTAssertFalse([_appDelegate.toolbarToolSegmentedControl isEnabledForSegment:segment], @"each segment too, which GNUstep draws");
    }
    NSString *path = [self writeSampleImage];
    XCTAssertTrue([_appDelegate openImageAtURL:[NSURL fileURLWithPath:path]]);
    XCTAssertTrue(_appDelegate.toolbarToolSegmentedControl.isEnabled);
    XCTAssertTrue([_appDelegate.toolbarToolSegmentedControl isEnabledForSegment:0]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

/// Recent shows up to three of Open Recent's files that still exist, each a card that opens it (#221).
- (void)testRecentCards {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSString *first = [self writeSampleImage];
    NSString *second = [self writeSampleImage];
    NSString *missing = [NSTemporaryDirectory() stringByAppendingPathComponent:@"empty-state-missing.png"];
    _appDelegate.recentDocumentPaths = [@[first, missing, second] mutableCopy];
    [_appDelegate refreshEmptyStateRecents];
    [_appDelegate layoutEmptyStateViewInFrame:NSMakeRect(0.0, 0.0, 900.0, 760.0)];

    NSMutableArray<STRecentCard *> *cards = [NSMutableArray array];
    for (NSView *view in _appDelegate.emptyStateView.subviews) {
        if ([view isKindOfClass:[STRecentCard class]] && !view.isHidden) {
            [cards addObject:(STRecentCard *)view];
        }
    }
    XCTAssertEqual(cards.count, 2u, @"the missing file is left out");
    [cards sortUsingComparator:^NSComparisonResult(NSView *a, NSView *b) {
        return [@(NSMinX(a.frame)) compare:@(NSMinX(b.frame))];
    }];
    XCTAssertEqualObjects(cards[0].representedObject, first, @"newest first, left to right");
    XCTAssertEqualObjects(cards[1].representedObject, second);
    XCTAssertEqualObjects(cards[0].title, first.lastPathComponent);
    XCTAssertTrue(sel_isEqual(cards[0].action, @selector(openRecentDocument:)), @"opens as Open Recent's item does");
    XCTAssertEqual(cards[0].target, _appDelegate);
    XCTAssertEqualWithAccuracy(NSMinY(cards[0].frame), NSMinY(cards[1].frame), 0.5, @"in one row");
    NSView *capture = [self controlWithAction:@selector(takeScreenshot:)];
    NSView *paste = [self controlWithAction:@selector(pasteAsNewImage:)];
    XCTAssertLessThan(NSMaxY(cards[0].frame), NSMinY(capture.isHidden ? paste.frame : capture.frame), @"under the buttons");

    // A window too short for them hides them.
    [_appDelegate layoutEmptyStateViewInFrame:NSMakeRect(0.0, 0.0, 900.0, 380.0)];
    XCTAssertTrue(cards[0].isHidden);
    [[NSFileManager defaultManager] removeItemAtPath:first error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:second error:NULL];
}

- (void)testOpeningAnImageShowsTheCanvas {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSString *path = [self writeSampleImage];
    XCTAssertTrue([_appDelegate openImageAtURL:[NSURL fileURLWithPath:path]]);
    XCTAssertTrue(_appDelegate.emptyStateView.isHidden);
    XCTAssertFalse(_appDelegate.scrollView.isHidden);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

@end
