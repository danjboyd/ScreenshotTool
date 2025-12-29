/*
 * TextFontComboProbe_test.m
 * Validates that the TextTool font combo keeps GNUstep's data-source mode.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "TextToolPopoverController.h"

#pragma mark - Mock Objects

@interface STFakeFieldEditor : NSResponder
@end
@implementation STFakeFieldEditor
@end

@interface STProbeComboBox : NSComboBox
@property (nonatomic, assign) NSInteger testingIndex;
@property (nonatomic, copy) NSString *testingStringValue;
@property (nonatomic, assign) BOOL editing;
@property (nonatomic, strong) STFakeFieldEditor *fakeEditor;
@end
@implementation STProbeComboBox
- (instancetype)init {
    self = [super init];
    if (self) {
        _testingIndex = -1;
        _fakeEditor = [[STFakeFieldEditor alloc] init];
    }
    return self;
}
- (NSInteger)indexOfSelectedItem { return self.testingIndex; }
- (void)selectItemAtIndex:(NSInteger)index { self.testingIndex = index; }
- (void)deselectItemAtIndex:(NSInteger)index {
    if (self.testingIndex == index) self.testingIndex = -1;
}
- (NSString *)stringValue { return self.testingStringValue ?: @""; }
- (void)setStringValue:(NSString *)string { self.testingStringValue = [string copy]; }
- (void)reloadData {}
- (void)noteNumberOfItemsChanged {}
- (id)currentEditor { return self.editing ? self.fakeEditor : nil; }
- (id)objectValueOfSelectedItem {
    fprintf(stderr, "font combo attempted to call objectValueOfSelectedItem while in data-source mode\n");
    abort();
    return nil;
}
@end

@interface ProbeTextToolPopoverController : TextToolPopoverController

@property (nonatomic, assign) NSInteger finalizeInvocations;

@property (nonatomic, assign) NSInteger applyFontInvocations;

@property (nonatomic, copy) NSString *lastFinalizeInput;

@property (nonatomic, copy) NSString *currentFontComboSelection;

@end



@implementation ProbeTextToolPopoverController



- (void)finalizeFontComboSelectionWithInput:(NSString *)input {
    self.finalizeInvocations += 1;
    self.lastFinalizeInput = input ?: @"";
    self.currentFontComboSelection = input ?: @"";
}
- (void)applyFontSelectionChange {
    self.applyFontInvocations += 1;
}
@end

#pragma mark - Testing Category

@interface TextToolPopoverController (Testing)
@property (nonatomic, strong) NSComboBox *fontComboBox;
@property (nonatomic, copy) NSArray<NSString *> *filteredFontFamilies;
@property (nonatomic, copy) NSString *currentFontComboSelection;
@property (nonatomic, copy) NSString *pendingFontComboStringValue;
- (void)comboBoxSelectionDidChange:(NSNotification *)notification;
- (void)setFontComboSelectionToFamily:(NSString *)family;
- (void)flushPendingFontComboStringValueIfNeeded;
@end

#pragma mark - Test Class

@interface TextFontComboProbeTests : XCTestCase {
    ProbeTextToolPopoverController *_controller;
    STProbeComboBox *_combo;
}
@end

@implementation TextFontComboProbeTests

- (void)setUp {
    [super setUp];
    // This test requires NSApplication but not a full window server connection
    if (![NSApplication sharedApplication]) {
        [NSApplication sharedApplication];
    }
    _controller = [[ProbeTextToolPopoverController alloc] init];
    _combo = [[STProbeComboBox alloc] init];
    _controller.fontComboBox = _combo;
    _controller.filteredFontFamilies = @[ @"Arial", @"Courier", @"Fira Code" ];
}

- (void)tearDown {
    _controller = nil;
    _combo = nil;
    [super tearDown];
}

- (void)testFontComboBoxScenarios {
    // --- Scenario 1: Selecting an existing item ---
    _combo.testingIndex = 1;
    _combo.testingStringValue = @"Courier";
    NSNotification *note1 = [NSNotification notificationWithName:NSComboBoxSelectionDidChangeNotification object:_combo userInfo:nil];
    [_controller comboBoxSelectionDidChange:note1];
    XCTAssertEqualObjects(_controller.lastFinalizeInput, @"Courier", @"Scenario 1 failed");

    // --- Scenario 2: Typing a new item ---
    _combo.testingIndex = -1;
    _combo.testingStringValue = @"Papyrus";
    NSNotification *note2 = [NSNotification notificationWithName:NSComboBoxSelectionDidChangeNotification object:_combo userInfo:nil];
    [_controller comboBoxSelectionDidChange:note2];
    XCTAssertEqualObjects(_controller.lastFinalizeInput, @"Papyrus", @"Scenario 2 failed");

    // --- Scenario 3: Deferring update while editing ---
    _combo.testingStringValue = @"Initial";
    _controller.pendingFontComboStringValue = nil;
    _combo.editing = YES;
    
    [_controller setFontComboSelectionToFamily:@"Fira Code"];
    XCTAssertEqualObjects(_controller.pendingFontComboStringValue, @"Fira Code", @"Expected pending string to capture new value");
    XCTAssertEqualObjects(_combo.stringValue, @"Initial", @"Combo string should not change while editing");
    
    _combo.editing = NO;
    [_controller flushPendingFontComboStringValueIfNeeded];
    XCTAssertEqualObjects(_combo.stringValue, @"Fira Code", @"Pending combo string did not flush after editing");
    XCTAssertNil(_controller.pendingFontComboStringValue, @"Pending combo string should clear after flushing");
    
    // --- Final check: Invocation counts ---
    XCTAssertEqual(_controller.finalizeInvocations, 2, @"Expected finalize to be invoked twice");
    XCTAssertEqual(_controller.applyFontInvocations, 2, @"Expected apply to be invoked twice");
}

@end
