/*
 * ToolbarFitsWindowProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * On macOS the toolbar shares its row with the window's title, so a window opened at the smallest
 * canvas width showed only Undo and Redo. A small image's window now opens wide enough for the
 * whole toolbar, and when the window is narrower, Undo, Redo and Share overflow before the tools.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (ToolbarFitsWindowTesting)
- (void)setupWindowAndContent;
- (void)setupToolbar;
- (BOOL)openImageAtURL:(NSURL *)url;
- (NSWindow *)window;
@end

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
    [window layoutIfNeeded];
    XCTAssertEqual(window.toolbar.visibleItems.count, window.toolbar.items.count,
                   @"every toolbar item shows at %.0fpt", NSWidth(window.frame));
    XCTAssertLessThan(NSWidth(window.contentView.frame), 1000.0, @"no wider than the toolbar needs");
}

- (void)testUndoRedoAndShareOverflowBeforeTheTools {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSDictionary<NSString *, NSNumber *> *expected = @{
        @"com.screenshottool.toolbar.tools": @(NSToolbarItemVisibilityPriorityHigh),
        @"com.screenshottool.toolbar.color": @(NSToolbarItemVisibilityPriorityHigh),
        @"com.screenshottool.toolbar.undo": @(NSToolbarItemVisibilityPriorityLow),
        @"com.screenshottool.toolbar.redo": @(NSToolbarItemVisibilityPriorityLow),
        @"com.screenshottool.toolbar.share": @(NSToolbarItemVisibilityPriorityLow),
    };
    for (NSToolbarItem *item in _appDelegate.window.toolbar.items) {
        NSNumber *priority = expected[item.itemIdentifier];
        if (priority) {
            XCTAssertEqual(item.visibilityPriority, priority.integerValue, @"%@", item.itemIdentifier);
        }
    }

}

- (void)testTheNarrowestWindowStillShowsTheTools {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:30
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"toolbar-narrow-%@.png", [[NSUUID UUID] UUIDString]]];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    XCTAssertTrue([_appDelegate openImageAtURL:[NSURL fileURLWithPath:path]]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

    // As narrow as the window may be made.
    NSWindow *window = _appDelegate.window;
    [window setContentSize:NSMakeSize(window.contentMinSize.width, NSHeight(window.contentView.frame))];
    [window layoutIfNeeded];
    NSArray *visible = [window.toolbar.visibleItems valueForKey:@"itemIdentifier"];
    XCTAssertTrue([visible containsObject:@"com.screenshottool.toolbar.tools"], @"visible: %@", visible);
    XCTAssertTrue([visible containsObject:@"com.screenshottool.toolbar.color"], @"visible: %@", visible);
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
