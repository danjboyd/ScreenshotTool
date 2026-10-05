/*
 * PopoverScaleFactorProbe_test.m
 * Verifies that popover sizing honors GSScaleFactor overrides.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "STFloatingPopover.h"
#import "ToolSettingsPopoverController.h"
#import "TextToolPopoverController.h"
#import "ZoomPopoverController.h"
#import "TestEnvironmentHelpers.h"

@interface ToolSettingsPopoverController (Testing)
@property (nonatomic, strong) STFloatingPopover *popover;
- (void)buildPopoverForView:(NSView *)view;
@end

@interface TextToolPopoverController (Testing)
@property (nonatomic, strong) STFloatingPopover *popover;
- (void)buildPopoverForView:(NSView *)view;
@end

@interface ZoomPopoverController (Testing)
@property (nonatomic, strong) STFloatingPopover *popover;
@property (nonatomic, strong) NSButton *fitButton;
@property (nonatomic, strong) NSButton *resetButton;
- (void)buildPopoverForView:(NSView *)view;
@end

@interface PopoverScaleFactorProbeTests : XCTestCase {
    BOOL _shouldSkip;
    NSString *_priorGSScaleFactor;
}
@end

@implementation PopoverScaleFactorProbeTests

- (void)setUp {
    [super setUp];
    const char *existing = getenv("GSScaleFactor");
    _priorGSScaleFactor = existing ? [NSString stringWithUTF8String:existing] : nil;
    STUnsetEnvVar("GSScaleFactor");
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"GSScaleFactor"];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
    } @catch (NSException *exception) {
        NSLog(@"Skipping popover scale tests: failed to connect to window server (%@)", exception.reason);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    if (_priorGSScaleFactor) {
        STSetEnvVar("GSScaleFactor", _priorGSScaleFactor.UTF8String);
    } else {
        STUnsetEnvVar("GSScaleFactor");
    }
    [super tearDown];
}

- (void)testCurrentScaleFactorUsesEnvironmentValue {
    XCTSkipIf(_shouldSkip, @"No window server");
    STSetEnvVar("GSScaleFactor", "1.75");
    CGFloat factor = [STFloatingPopover currentScaleFactorForView:nil];
    XCTAssertEqualWithAccuracy(factor, 1.0f, 0.0f, @"Scale factor should remain logical (no double-scaling)");
}

- (void)testToolSettingsPopoverScalesContentSize {
    XCTSkipIf(_shouldSkip, @"No window server");
    STSetEnvVar("GSScaleFactor", "1.50");
    NSView *anchor = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10.0f, 10.0f)];
    ToolSettingsPopoverController *controller = [[ToolSettingsPopoverController alloc] initWithTool:ScreenshotCanvasToolPen];
    [controller buildPopoverForView:anchor];
    [controller showRelativeToRect:NSMakeRect(5.0f, 5.0f, 1.0f, 1.0f) ofView:anchor preferredEdge:NSMaxYEdge];
    XCTAssertNotNil(controller.popover, @"Popover should be constructed");
    XCTAssertEqualWithAccuracy(controller.popover.contentSize.width, 260.0f, 0.1f, @"Pen popover width should stay logical sized");
    XCTAssertEqualWithAccuracy(controller.popover.contentSize.height, 180.0f, 0.1f, @"Pen popover height should stay logical sized");
}

- (void)testTextPopoverScalesContentSize {
    XCTSkipIf(_shouldSkip, @"No window server");
    STSetEnvVar("GSScaleFactor", "1.25");
    NSView *anchor = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10.0f, 10.0f)];
    TextToolPopoverController *controller = [[TextToolPopoverController alloc] init];
    [controller buildPopoverForView:anchor];
    [controller showRelativeToRect:NSMakeRect(5.0f, 5.0f, 1.0f, 1.0f) ofView:anchor preferredEdge:NSMaxYEdge];
    XCTAssertNotNil(controller.popover, @"Popover should be constructed");
    XCTAssertEqualWithAccuracy(controller.popover.contentSize.width, 340.0f, 0.1f, @"Text popover width should stay logical sized");
    XCTAssertEqualWithAccuracy(controller.popover.contentSize.height, 392.0f, 0.1f, @"Text popover height should stay logical sized (includes the Style and Align rows)");
}

- (void)testZoomPopoverButtonsFitMeasuredCellSizes {
    XCTSkipIf(_shouldSkip, @"No window server");
    STSetEnvVar("GSScaleFactor", "2.00");
    NSView *anchor = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10.0f, 10.0f)];
    ZoomPopoverController *controller = [[ZoomPopoverController alloc] init];
    [controller buildPopoverForView:anchor];

    XCTAssertNotNil(controller.fitButton, @"Fit button should be constructed");
    XCTAssertNotNil(controller.resetButton, @"Reset button should be constructed");

    NSSize fitCellSize = [controller.fitButton.cell cellSize];
    NSSize resetCellSize = [controller.resetButton.cell cellSize];
    XCTAssertGreaterThanOrEqual(controller.fitButton.frame.size.width, ceil(fitCellSize.width),
                                @"Fit button width should accommodate its cell title");
    XCTAssertGreaterThanOrEqual(controller.resetButton.frame.size.width, ceil(resetCellSize.width),
                                @"Reset button width should accommodate its cell title");
}

@end
