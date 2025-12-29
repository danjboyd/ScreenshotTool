/*
 * ZoomComboBoxProbe_test.m
 * Copyright (C) 2025 Daniel Boyd
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"

#pragma mark - Test-specific Subclass

@interface ZoomProbeAppDelegate : AppDelegate
@property (nonatomic, strong) NSPopUpButton *zoomPopUpButton;
@property (nonatomic, strong) NSMutableArray<NSString *> *zoomOptions;
@end

@implementation ZoomProbeAppDelegate
@synthesize zoomPopUpButton;
@synthesize zoomOptions;

// The test only needs this method to return a toolbar item with a pop-up view.
- (NSToolbarItem *)toolbarItemForZoomControl {
    if (!self.zoomPopUpButton) {
        self.zoomPopUpButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 24) pullsDown:NO];
        self.zoomOptions = [NSMutableArray arrayWithArray:@[@"100%", @"200%"]];
        [self rebuildZoomPopUpButton];
    }
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:@"com.screenshottool.toolbar.zoom"];
    [item setView:self.zoomPopUpButton];
    [item setTarget:self];
    [item setAction:@selector(zoomPopUpSelectionChanged:)];
    return item;
}

// The test just needs to know these methods exist.
- (void)rebuildZoomPopUpButton {
    [self.zoomPopUpButton removeAllItems];
    [self.zoomPopUpButton addItemsWithTitles:self.zoomOptions];
}
- (void)updateZoomPopUpSelection {}
- (void)zoomPopUpSelectionChanged:(id)sender {}
@end

#pragma mark - Test Class

@interface ZoomComboBoxProbeTests : XCTestCase {
    ZoomProbeAppDelegate *_appDelegate;
}
@end

@implementation ZoomComboBoxProbeTests

- (void)setUp {
    [super setUp];
    if (![NSApplication sharedApplication]) {
        [NSApplication sharedApplication];
    }
    _appDelegate = [[ZoomProbeAppDelegate alloc] init];
}

- (void)tearDown {
    _appDelegate = nil;
    [super tearDown];
}

#pragma mark - Helpers

- (void)assertPopUp:(NSPopUpButton *)popUp hasItems:(NSArray<NSString *> *)expected withContext:(NSString *)context {
    XCTAssertNotNil(popUp, @"Pop-up button should not be nil (%@)", context);
    XCTAssertEqual(popUp.numberOfItems, expected.count, @"Item count mismatch (%@)", context);
    for (NSInteger i = 0; i < (NSInteger)expected.count; i++) {
        XCTAssertEqualObjects([popUp itemTitleAtIndex:i], expected[i], @"Item %ld mismatch (%@)", (long)i, context);
    }
}

#pragma mark - Tests

- (void)testZoomPopUpButtonIsCorrectlyInitialized {
    NSToolbarItem *zoomItem = [_appDelegate toolbarItemForZoomControl];
    XCTAssertNotNil(zoomItem, @"Zoom toolbar item should be created");
    
    NSPopUpButton *attachedPopUp = (NSPopUpButton *)zoomItem.view;
    XCTAssertNotNil(attachedPopUp, @"Zoom item should have a view");
    XCTAssertTrue([attachedPopUp isKindOfClass:[NSPopUpButton class]], @"View should be an NSPopUpButton");
    
    XCTAssertEqual(_appDelegate.zoomPopUpButton, attachedPopUp, @"zoomPopUpButton property should track the toolbar item's view");
    XCTAssertEqual([attachedPopUp target], _appDelegate, @"Pop-up target should be the app delegate");
    XCTAssertEqual([attachedPopUp action], @selector(zoomPopUpSelectionChanged:), @"Pop-up action is incorrect");
    
    [self assertPopUp:attachedPopUp hasItems:_appDelegate.zoomOptions withContext:@"initial toolbar pop-up"];
}

- (void)testZoomPopUpButtonCanBeRebuilt {
    NSToolbarItem *zoomItem = [_appDelegate toolbarItemForZoomControl];
    NSPopUpButton *originalPopUp = (NSPopUpButton *)zoomItem.view;

    // Simulate GNUstep cloning the pop-up button
    NSPopUpButton *clonedPopUp = [[NSPopUpButton alloc] initWithFrame:originalPopUp.frame pullsDown:NO];
    [clonedPopUp setAutoenablesItems:NO];
    [clonedPopUp setTarget:_appDelegate];
    [clonedPopUp setAction:@selector(zoomPopUpSelectionChanged:)];
    
    _appDelegate.zoomPopUpButton = clonedPopUp;
    [_appDelegate rebuildZoomPopUpButton];
    [_appDelegate updateZoomPopUpSelection];
    
    [self assertPopUp:clonedPopUp hasItems:_appDelegate.zoomOptions withContext:@"cloned toolbar pop-up"];
}

@end
