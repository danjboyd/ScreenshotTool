/*
 * SplitButtonProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The empty state's Open… is a split button, as libadwaita's AdwSplitButton: the title opens a
 * file, the arrow at its right a menu of recent files (STSplitButton).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "STSplitButton.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (SplitButtonTesting)
- (void)setupWindowAndContent;
- (NSView *)emptyStateView;
@end

@interface SplitButtonProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation SplitButtonProbeTests

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

- (void)testArrowIsAtTheRight {
    XCTSkipIf(_shouldSkip, @"No window server");
    STSplitButton *button = [[STSplitButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 148.0, 32.0)];
    XCTAssertTrue(NSEqualRects([button arrowRect], NSMakeRect(120.0, 0.0, 28.0, 32.0)));
    XCTAssertEqualObjects(NSStringFromClass([[button cell] class]), @"STSplitButtonCell",
                          @"the cell draws the arrow");

    [button setFrameSize:NSMakeSize(40.0, 32.0)];
    XCTAssertTrue(NSIsEmptyRect([button arrowRect]), @"no arrow where the title wouldn't fit");
}

#if defined(GNUSTEP)
- (void)testEmptyStateOpenIsASplitButtonWithRecentFiles {
    XCTSkipIf(_shouldSkip, @"No window server");
    STSplitButton *open = [_appDelegate.emptyStateView viewWithTag:4];
    XCTAssertTrue([open isKindOfClass:[STSplitButton class]]);
    XCTAssertEqualObjects(open.title, @"Open…");
    XCTAssertEqual(open.action, @selector(openDocument:));
    XCTAssertEqualObjects(open.keyEquivalent, @"\r", @"still the suggested button Return presses");
    XCTAssertNotNil(open.menuProvider);
    NSMenu *first = open.menuProvider();
    NSMenu *second = open.menuProvider();
    XCTAssertNotNil(first);
    XCTAssertGreaterThan(first.numberOfItems, 0, @"recent files, or a placeholder when there are none");
    XCTAssertNotEqual(first, second, @"built afresh each time, so it's never stale");
}
#endif

@end
