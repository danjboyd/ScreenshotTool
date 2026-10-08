/*
 * ToolSegmentToolTipsProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Each tool in the toolbar's tool switcher has its own tool tip, not one "Tools" for them all.
 * GNUstep never shows NSSegmentedCell's per-segment tips, so the app gives each segment a tool
 * tip area of its own (STSegmentToolTips).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "STSegmentToolTips.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (ToolSegmentToolTipsTesting)
- (void)setupWindowAndContent;
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag;
@end

@interface ToolSegmentToolTipsProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation ToolSegmentToolTipsProbeTests

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

- (void)testEachToolHasItsOwnToolTip {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSToolbarItem *item = [_appDelegate toolbar:nil
                          itemForItemIdentifier:@"com.screenshottool.toolbar.tools"
                      willBeInsertedIntoToolbar:YES];
    NSSegmentedControl *control = (NSSegmentedControl *)item.view;
    XCTAssertTrue([control isKindOfClass:[NSSegmentedControl class]]);
    XCTAssertNil(item.toolTip, @"No one tip for the whole tool switcher");
    XCTAssertEqual([control toolTip].length, (NSUInteger)0, @"No one tip for the whole tool switcher");

    NSMutableSet<NSString *> *tips = [NSMutableSet set];
    for (NSInteger segment = 0; segment < control.segmentCount; segment++) {
        NSString *tip = [[control cell] toolTipForSegment:segment];
        XCTAssertTrue([tip containsString:@"Tool"], @"segment %ld names its tool: %@", (long)segment, tip);
        [tips addObject:tip ?: @""];
    }
    XCTAssertEqual(tips.count, (NSUInteger)control.segmentCount, @"Each tool's tip is its own");

    // Only the tools with a settings popover offer one; the arrow uses the pen's settings.
    for (NSString *tip in tips) {
        BOOL offersSettings = [tip containsString:@"double-click to configure"];
        BOOL hasPopover = [tip hasPrefix:@"Pen"] || [tip hasPrefix:@"Highlighter"] || [tip hasPrefix:@"Text"];
        XCTAssertEqual(offersSettings, hasPopover, @"%@", tip);
    }
}

- (void)testSegmentAreasTileTheControl {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSSegmentedControl *control = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0)];
    [control setSegmentCount:3];
    [control setWidth:40.0 forSegment:0];
    // Segments 1 and 2 have no set width: they share what's left, as GNUstep draws them.
    XCTAssertTrue(NSEqualRects(STSegmentToolTipRect(control, 0), NSMakeRect(0.0, 0.0, 40.0, 20.0)));
    XCTAssertTrue(NSEqualRects(STSegmentToolTipRect(control, 1), NSMakeRect(40.0, 0.0, 30.0, 20.0)));
    XCTAssertTrue(NSEqualRects(STSegmentToolTipRect(control, 2), NSMakeRect(70.0, 0.0, 30.0, 20.0)));
    XCTAssertTrue(NSIsEmptyRect(STSegmentToolTipRect(control, 3)), @"No area past the last segment");

    [control setToolTip:@"Whole control"];
    STInstallSegmentToolTips(control);
#if defined(GNUSTEP)
    XCTAssertEqual([control toolTip].length, (NSUInteger)0, @"The segments' tips replace the control's");
#endif
}

@end
