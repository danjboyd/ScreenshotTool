/*
 * TextFontFacePopupProbe_test.m
 * Verifies that the text typeface popup brackets menu tracking as a transient interaction.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "TextToolPopoverController.h"

@interface STPopoverInteractionSpy : NSObject
@property (nonatomic, assign) NSInteger beginCount;
@property (nonatomic, assign) NSInteger endCount;
@end

@implementation STPopoverInteractionSpy
- (void)beginTransientInteraction {
    self.beginCount += 1;
}
- (void)endTransientInteraction {
    self.endCount += 1;
}
@end

@interface TextToolPopoverController (FontFacePopupTesting)
@property (nonatomic, strong) NSPopUpButton *fontFacePopUp;
@property (nonatomic, strong) id popover;
- (void)buildPopoverForView:(NSView *)view;
@end

@interface TextFontFacePopupProbeTests : XCTestCase
@end

@implementation TextFontFacePopupProbeTests

- (void)setUp {
    [super setUp];
    if (![NSApplication sharedApplication]) {
        [NSApplication sharedApplication];
    }
}

- (void)testFontFacePopupTrackingBracketsTransientInteraction {
    TextToolPopoverController *controller = [[TextToolPopoverController alloc] init];
    NSView *hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 340, 320)];
    STPopoverInteractionSpy *spy = [[STPopoverInteractionSpy alloc] init];

    [controller buildPopoverForView:hostView];
    controller.popover = (id)spy;

    XCTAssertNotNil(controller.fontFacePopUp);
    XCTAssertNotNil(controller.fontFacePopUp.menu);

    [[NSNotificationCenter defaultCenter] postNotificationName:NSPopUpButtonWillPopUpNotification
                                                        object:controller.fontFacePopUp];
    XCTAssertEqual(spy.beginCount, 1);
    XCTAssertEqual(spy.endCount, 0);

    [[NSNotificationCenter defaultCenter] postNotificationName:NSPopUpButtonCellWillPopUpNotification
                                                        object:controller.fontFacePopUp.cell];
    XCTAssertEqual(spy.beginCount, 2);
    XCTAssertEqual(spy.endCount, 0);

    [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidEndTrackingNotification
                                                        object:[[NSMenu alloc] initWithTitle:@"Unrelated"]];
    XCTAssertEqual(spy.beginCount, 2);
    XCTAssertEqual(spy.endCount, 0);

    [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidEndTrackingNotification
                                                        object:controller.fontFacePopUp.menu];
    XCTAssertEqual(spy.beginCount, 2);
    XCTAssertEqual(spy.endCount, 1);
}

@end
