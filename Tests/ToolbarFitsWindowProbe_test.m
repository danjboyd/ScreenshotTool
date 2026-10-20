/*
 * ToolbarFitsWindowProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * On macOS the toolbar shares its row with the window's title, so a window opened at the smallest
 * canvas width showed only Undo and Redo. A small image's window now opens wide enough for the
 * whole toolbar. When the window is narrower, Undo and Redo overflow first and Save and Share last,
 * and the window can't be made so narrow that the tools, colour or Copy overflow: on GNUstep only
 * where the theme honours visibility priority.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "TestEnvironmentHelpers.h"
#if defined(GNUSTEP)
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>
#endif

@interface AppDelegate (ToolbarFitsWindowTesting)
- (void)setupWindowAndContent;
- (void)setupToolbar;
- (BOOL)openImageAtURL:(NSURL *)url;
- (NSWindow *)window;
#if defined(GNUSTEP)
- (CGFloat)contentWidthShowingAllToolbarItems;
- (CGFloat)contentWidthShowingToolbarItems:(BOOL)keptOnly;
- (void)resizeWindowToImageSize:(NSSize)imageSize;
#endif
@end

#if defined(GNUSTEP)
/// What the theme answers to -toolbarHonoursVisibilityPriority in these tests, as WinUITheme and
/// Adwaita will once they send the lowest priority into ">>" first.
static BOOL STTestThemeHonoursVisibilityPriority = NO;

static BOOL STTestToolbarHonoursVisibilityPriority(id self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    return STTestThemeHonoursVisibilityPriority;
}
#endif

@interface ToolbarFitsWindowProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation ToolbarFitsWindowProbeTests

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
        [_appDelegate setupToolbar];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    [_appDelegate.window close];
    _appDelegate = nil;
    [super tearDown];
}

#if defined(GNUSTEP)
/// GNUstep moves the row's last items, Save and Copy, into ">>" when the row is too narrow. At
/// 125% and 150% an 860px screenshot's window was (#221): the window now opens at least as wide as
/// the items at their minimum widths need. Sized directly, not by shrinking a live window (#242).
- (void)testWindowForASmallImageIsWideEnoughForTheWholeToolbar {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSWindow *window = _appDelegate.window;
    [window orderFront:nil];
    [window display];
    CGFloat needed = [_appDelegate contentWidthShowingAllToolbarItems];
    XCTSkipIf(needed <= 0.0, @"The toolbar wasn't laid out, so there's nothing to measure");

    // An image narrower than the row: the window's width comes from the toolbar, not the image.
    [_appDelegate resizeWindowToImageSize:NSMakeSize(40.0, 30.0)];
    CGFloat limit = floor(NSWidth((window.screen ?: [NSScreen mainScreen]).visibleFrame) * 0.95);
    CGFloat width = NSWidth([window.contentView frame]);
    if (needed + 8.0 <= limit) {
        XCTAssertGreaterThanOrEqual(width, needed, @"the content is as wide as the toolbar needs");
        XCTAssertLessThanOrEqual(width, MAX(needed + 9.0, 641.0), @"and no wider than that or the smallest canvas");
        [window display];
        XCTAssertEqual(window.toolbar.visibleItems.count, window.toolbar.items.count,
                       @"every toolbar item shows at %.0fpt: %@", width,
                       [window.toolbar.visibleItems valueForKey:@"itemIdentifier"]);
    } else {
        XCTAssertLessThanOrEqual(width, limit + 1.0, @"capped at the screen");
    }
}
#endif

/// The order items go into the overflow menu in: Undo and Redo first, Save and Share last, and
/// never the tools, colour or Copy. AppKit honours it; on GNUstep the theme does.
- (void)testItemsOverflowInOrderOfUse {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSDictionary<NSString *, NSNumber *> *expected = @{
        @"com.screenshottool.toolbar.tools": @(NSToolbarItemVisibilityPriorityUser),
        @"com.screenshottool.toolbar.color": @(NSToolbarItemVisibilityPriorityUser),
        @"com.screenshottool.toolbar.copy": @(NSToolbarItemVisibilityPriorityUser),
        @"com.screenshottool.toolbar.save": @(NSToolbarItemVisibilityPriorityHigh),
        @"com.screenshottool.toolbar.share": @(NSToolbarItemVisibilityPriorityHigh),
        @"com.screenshottool.toolbar.undo": @(NSToolbarItemVisibilityPriorityLow),
        @"com.screenshottool.toolbar.redo": @(NSToolbarItemVisibilityPriorityLow),
    };
    NSUInteger checked = 0;
    for (NSToolbarItem *item in _appDelegate.window.toolbar.items) {
        NSNumber *priority = expected[item.itemIdentifier];
        if (priority) {
            XCTAssertEqual(item.visibilityPriority, priority.integerValue, @"%@", item.itemIdentifier);
            checked += 1;
        }
    }
    XCTAssertGreaterThanOrEqual(checked, (NSUInteger)6, @"the default toolbar's items were checked");
}

/// Each tool stays a touch target of at least 40pt: 46 here, 40 on Windows, where the window's
/// minimum has to fit on half of a 1920px screen at 150%.
- (void)testToolSegmentsAreTouchTargets {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSSegmentedControl *tools = nil;
    for (NSToolbarItem *item in _appDelegate.window.toolbar.items) {
        if ([item.itemIdentifier isEqualToString:@"com.screenshottool.toolbar.tools"]) {
            tools = (NSSegmentedControl *)item.view;
        }
    }
    XCTAssertTrue([tools isKindOfClass:[NSSegmentedControl class]], @"the tools are a segmented control");
#if defined(_WIN32)
    CGFloat expected = 40.0;
#else
    CGFloat expected = 46.0;
#endif
    for (NSInteger segment = 0; segment < tools.segmentCount; segment++) {
        XCTAssertGreaterThanOrEqual([tools widthForSegment:segment], 40.0, @"segment %ld", (long)segment);
        XCTAssertEqualWithAccuracy([tools widthForSegment:segment], expected, 0.5, @"segment %ld", (long)segment);
    }
}

/// Opens a 40 x 30 image, smaller than any window: the window's minimum comes from the toolbar.
- (void)openSmallImage {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:30
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"toolbar-narrow-%@.png", [[NSUUID UUID] UUIDString]]];
    [[rep representationUsingType:NSPNGFileType properties:@{}] writeToFile:path atomically:YES];
    XCTAssertTrue([_appDelegate openImageAtURL:[NSURL fileURLWithPath:path]]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

#if defined(GNUSTEP)
/// Makes the current theme answer -toolbarHonoursVisibilityPriority with `honours`.
- (void)setThemeHonoursVisibilityPriority:(BOOL)honours {
    STTestThemeHonoursVisibilityPriority = honours;
    Class themeClass = [[GSTheme theme] class];
    SEL selector = @selector(toolbarHonoursVisibilityPriority);
    if (!class_getInstanceMethod(themeClass, selector)) {
        class_addMethod(themeClass, selector, (IMP)STTestToolbarHonoursVisibilityPriority, "c@:");
    }
}

/// A theme that keeps the row's first items, as libs-gui does: keeping Copy would keep the whole
/// row before it (over 1100pt under Adwaita), so the window keeps the canvas minimum and Copy may
/// go into ">>".
- (void)testWithoutPriorityTheMinimumIsTheCanvasMinimum {
    XCTSkipIf(_shouldSkip, @"No window server");
    Method answer = class_getInstanceMethod([[GSTheme theme] class], @selector(toolbarHonoursVisibilityPriority));
    XCTSkipIf(answer && method_getImplementation(answer) != (IMP)STTestToolbarHonoursVisibilityPriority,
              @"The theme itself answers -toolbarHonoursVisibilityPriority");
    [self setThemeHonoursVisibilityPriority:NO];
    NSWindow *window = _appDelegate.window;
    [window orderFront:nil];
    [window display];
    [self openSmallImage];
    CGFloat kept = [_appDelegate contentWidthShowingToolbarItems:YES];
    XCTSkipIf(kept <= 0.0, @"The toolbar wasn't laid out, so there's nothing to measure");
    XCTAssertLessThanOrEqual(window.contentMinSize.width, 641.0, @"the canvas minimum, not the toolbar's %.0fpt", kept);
}

/// A theme that sends the lowest priority into ">>" first: the window can't be made narrower than
/// the tools, colour, Copy, the flexible spaces and the ">>" button need, which is less than the
/// whole row.
- (void)testWithPriorityTheMinimumKeepsTheToolsColourAndCopy {
    XCTSkipIf(_shouldSkip, @"No window server");
    [self setThemeHonoursVisibilityPriority:YES];
    NSWindow *window = _appDelegate.window;
    [window orderFront:nil];
    [window display];
    [self openSmallImage];
    CGFloat kept = [_appDelegate contentWidthShowingToolbarItems:YES];
    CGFloat all = [_appDelegate contentWidthShowingAllToolbarItems];
    [self setThemeHonoursVisibilityPriority:NO];
    XCTSkipIf(kept <= 0.0, @"The toolbar wasn't laid out, so there's nothing to measure");
    CGFloat limit = floor(NSWidth((window.screen ?: [NSScreen mainScreen]).visibleFrame) * 0.95);
    XCTSkipIf(kept >= limit, @"The screen is too narrow for the items the window keeps");

    XCTAssertLessThan(kept, all, @"the kept items need less than the whole row");
    XCTAssertEqualWithAccuracy(window.contentMinSize.width, MAX(kept, 640.0), 1.0,
                               @"the minimum keeps the tools, colour and Copy (%.0fpt)", kept);
}
#else
/// As narrow as the window may be made, the tools, colour and Copy still show: macOS measures the
/// width at which the items it must keep show.
- (void)testTheNarrowestWindowStillShowsTheToolsColourAndCopy {
    XCTSkipIf(_shouldSkip, @"No window server");
    [self openSmallImage];
    NSWindow *window = _appDelegate.window;
    CGFloat limit = floor(NSWidth((window.screen ?: [NSScreen mainScreen]).visibleFrame) * 0.95);
    XCTSkipIf(window.contentMinSize.width >= limit, @"The screen is too narrow for the items the window keeps");
    [window setContentSize:NSMakeSize(window.contentMinSize.width, NSHeight(window.contentView.frame))];
    [window layoutIfNeeded];
    NSArray *visible = [window.toolbar.visibleItems valueForKey:@"itemIdentifier"];
    for (NSString *identifier in @[@"com.screenshottool.toolbar.tools", @"com.screenshottool.toolbar.color",
                                   @"com.screenshottool.toolbar.copy"]) {
        XCTAssertTrue([visible containsObject:identifier], @"%@ shows at %.0fpt: %@", identifier,
                      NSWidth(window.contentView.frame), visible);
    }
}
#endif

#if !defined(GNUSTEP)
- (void)testSmallImageOpensWithTheWholeToolbar {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:30
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"toolbar-fits-%@.png", [[NSUUID UUID] UUIDString]]];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    XCTAssertTrue([_appDelegate openImageAtURL:[NSURL fileURLWithPath:path]]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

    NSWindow *window = _appDelegate.window;
    // The whole toolbar where the screen has room for it: the window opens at most 95% of the
    // screen's width, so one narrower than that was sized to show everything. On a narrower screen
    // (CI's is 1024pt) the window opens at that limit and only low-priority items may overflow.
    [window layoutIfNeeded];
    CGFloat limit = floor(NSWidth((window.screen ?: [NSScreen mainScreen]).visibleFrame) * 0.95);
    NSArray *visible = [window.toolbar.visibleItems valueForKey:@"itemIdentifier"];
    if (NSWidth(window.frame) < limit - 1.0) {
        XCTAssertEqual(window.toolbar.visibleItems.count, window.toolbar.items.count,
                       @"every toolbar item shows at %.0fpt (limit %.0f): %@", NSWidth(window.frame), limit, visible);
    } else {
        for (NSToolbarItem *item in window.toolbar.items) {
            if (item.visibilityPriority > NSToolbarItemVisibilityPriorityLow) {
                XCTAssertTrue([visible containsObject:item.itemIdentifier], @"%@ shows at %.0fpt", item.itemIdentifier, NSWidth(window.frame));
            }
        }
    }
    XCTAssertLessThan(NSWidth(window.contentView.frame), 1000.0, @"no wider than the toolbar needs");
}

/// Undo, Redo and Copy were drawn in a fixed dark grey, nearly invisible on a dark toolbar. As
/// template images, AppKit tints them for light and dark mode.
- (void)testUndoRedoAndCopyIconsFollowTheAppearance {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:30
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"toolbar-template-%@.png", [[NSUUID UUID] UUIDString]]];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    XCTAssertTrue([_appDelegate openImageAtURL:[NSURL fileURLWithPath:path]]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

    NSSet<NSString *> *identifiers = [NSSet setWithObjects:@"com.screenshottool.toolbar.undo",
                                      @"com.screenshottool.toolbar.redo", @"com.screenshottool.toolbar.copy", nil];
    NSUInteger checked = 0;
    for (NSToolbarItem *item in _appDelegate.window.toolbar.items) {
        if (![identifiers containsObject:item.itemIdentifier]) {
            continue;
        }
        NSImage *image = item.image;
        if ([item.view isKindOfClass:[NSButton class]]) {
            image = ((NSButton *)item.view).image;
        }
        XCTAssertNotNil(image, @"%@", item.itemIdentifier);
        XCTAssertTrue(image.isTemplate, @"%@ is a template image", item.itemIdentifier);
        checked += 1;
    }
    XCTAssertEqual(checked, identifiers.count);
}
#endif

@end
