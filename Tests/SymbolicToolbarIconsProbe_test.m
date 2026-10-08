/*
 * SymbolicToolbarIconsProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Every image the toolbar shows is named `…-symbolic`, which is how a theme that tints template
 * images (Adwaita) knows to tint it: GNUstep 0.32 has no -[NSImage setTemplate:]. GNUstep's
 * -[NSImage copy] has no name, so the toolbar's copies were left untinted, dark grey on Adwaita's
 * dark header bar.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (SymbolicToolbarIconsTesting)
- (void)setupWindowAndContent;
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag;
- (NSImage *)toolbarImageForIdentifier:(NSToolbarItemIdentifier)identifier active:(BOOL)active;
- (NSImage *)toolbarSegmentImageForTool:(ScreenshotCanvasTool)tool selected:(BOOL)selected;
@end

@interface SymbolicToolbarIconsProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation SymbolicToolbarIconsProbeTests

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

#if defined(GNUSTEP)
- (void)testToolbarButtonImagesAreNamedSymbolic {
    XCTSkipIf(_shouldSkip, @"No window server");
    for (NSString *identifier in @[@"com.screenshottool.toolbar.undo", @"com.screenshottool.toolbar.redo"]) {
        // The item's first image, then the one each refresh puts in its place.
        NSToolbarItem *item = [_appDelegate toolbar:nil itemForItemIdentifier:identifier willBeInsertedIntoToolbar:YES];
        XCTAssertTrue([[item.image name] hasSuffix:@"-symbolic"], @"%@ starts tinted: %@", identifier, [item.image name]);
        NSImage *refreshed = [_appDelegate toolbarImageForIdentifier:identifier active:NO];
        XCTAssertNotNil(refreshed);
        XCTAssertTrue([[refreshed name] hasSuffix:@"-symbolic"], @"%@ stays tinted: %@", identifier, [refreshed name]);
        XCTAssertEqual([_appDelegate toolbarImageForIdentifier:identifier active:NO], refreshed,
                       @"named once and handed out again: a registered name can't be given twice");
    }
}

- (void)testToolSwitcherImagesAreNamedSymbolic {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasTool tools[] = {ScreenshotCanvasToolSelect, ScreenshotCanvasToolHighlighter, ScreenshotCanvasToolPen,
                                    ScreenshotCanvasToolArrow, ScreenshotCanvasToolText, ScreenshotCanvasToolEraser};
    for (size_t index = 0; index < sizeof(tools) / sizeof(tools[0]); index++) {
        NSImage *image = [_appDelegate toolbarSegmentImageForTool:tools[index] selected:NO];
        XCTAssertNotNil(image);
        XCTAssertTrue([[image name] hasSuffix:@"-symbolic"], @"tool %ld: %@", (long)tools[index], [image name]);
        XCTAssertEqual([_appDelegate toolbarSegmentImageForTool:tools[index] selected:NO], image);
    }
}
#endif

@end
