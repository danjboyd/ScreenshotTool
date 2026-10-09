/*
 * TextFontFieldProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The text bar's font field (#103): an editable combo box listing recent fonts, then those for
 * the user's language; a typed prefix completes to any installed family. It takes the keyboard
 * from the text box being edited without finishing it, and gives it back once a font is chosen.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "STFontFamilyList.h"
#import "STTextOptionsBar.h"
#import "STFontPicker.h"
#import "TestEnvironmentHelpers.h"

@interface STTextOptionsBar (TextFontFieldTesting)
@property (nonatomic, strong) NSComboBox *fontField;
@property (nonatomic, strong) STFontFamilyList *fontFamilies;
- (void)fontEntered:(id)sender;
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector;
#if defined(GNUSTEP)
- (NSPopUpButton *)fontButton;
- (void)fontPicker:(STFontPicker *)picker didChooseFamily:(NSString *)family;
- (void)fontPickerDidClose:(STFontPicker *)picker;
#endif
@end

/// Records what the font picker reports.
@interface STFontPicker (TextFontFieldTesting)
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSTableView *tableView;
@end

@interface TextFontPickerRecorder : NSObject <STFontPickerDelegate>
@property (nonatomic, copy) NSString *chosenFamily;
@property (nonatomic, assign) NSInteger closes;
@end

@implementation TextFontPickerRecorder
- (void)fontPicker:(STFontPicker *)picker didChooseFamily:(NSString *)family { self.chosenFamily = family; }
- (void)fontPickerDidClose:(STFontPicker *)picker { self.closes++; }
@end

@interface AppDelegate (TextFontFieldTesting)
- (void)setupWindowAndContent;
- (void)layoutContentSubviews;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
@end

@interface ScreenshotCanvasView (TextFontFieldTesting)
@property (nonatomic, strong) NSTextView *activeTextView;
- (void)beginTextEntryWithImageRect:(NSRect)imageRect existingText:(MarkupText *)existingText;
- (void)commitActiveTextIfNeeded;
@end

@interface TextFontFieldRecorder : NSObject <STTextOptionsBarDelegate>
@property (nonatomic, copy) NSString *pickedFamily;
@property (nonatomic, assign) NSInteger finishedEntries;
@end

@implementation TextFontFieldRecorder
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickFontFamily:(NSString *)family { self.pickedFamily = family; }
- (void)textOptionsBarDidFinishFontEntry:(STTextOptionsBar *)bar { self.finishedEntries++; }
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickStyle:(MarkupTextStyle)style {}
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickColor:(NSColor *)color {}
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickSizePreset:(STTextSizePreset)preset {}
- (void)textOptionsBar:(STTextOptionsBar *)bar didStepSizeBy:(CGFloat)delta {}
- (void)textOptionsBarDidTogglePointer:(STTextOptionsBar *)bar {}
- (void)textOptionsBarDidToggleBold:(STTextOptionsBar *)bar {}
- (void)textOptionsBarDidToggleItalic:(STTextOptionsBar *)bar {}
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickAlignment:(NSTextAlignment)alignment {}
@end

/// A companion that says focus is moving into it while `taking` is YES.
@interface TextFontFieldCompanion : NSObject <STTextEditingCompanion>
@property (nonatomic, assign) BOOL taking;
@end

@implementation TextFontFieldCompanion
- (BOOL)isTakingTextFocus { return self.taking; }
@end

@interface TextFontFieldProbeTests : XCTestCase {
    BOOL _shouldSkip;
    NSArray *_savedRecents;
}
@end

@implementation TextFontFieldProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    _savedRecents = [[NSUserDefaults standardUserDefaults] objectForKey:STRecentFontFamiliesDefaultsKey];
    @try {
        [NSApplication sharedApplication];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    if (_savedRecents) {
        [[NSUserDefaults standardUserDefaults] setObject:_savedRecents forKey:STRecentFontFamiliesDefaultsKey];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:STRecentFontFamiliesDefaultsKey];
    }
    [super tearDown];
}

#pragma mark - The family list

- (STFontFamilyList *)sampleList {
    return [[STFontFamilyList alloc] initWithFamilies:@[@"Noto Sans Bengali", @"DejaVu Sans", @"Cantarell", @"Noto Sans", @"Arial"]
                                      coveredFamilies:@[@"Noto Sans", @"cantarell", @"DejaVu Sans", @"Not Installed"]
                                               recent:@[@"Arial", @"Missing Font"]];
}

- (void)testListsRecentThenLanguageFamilies {
    STFontFamilyList *list = [self sampleList];
    // Recent (installed only) first, then the language's families, sorted, without repeats.
    XCTAssertEqualObjects(list.listedFamilies, (@[@"Arial", @"Cantarell", @"DejaVu Sans", @"Noto Sans"]));
    XCTAssertEqual(list.recentCount, 1u);
    XCTAssertFalse([list.listedFamilies containsObject:@"Noto Sans Bengali"], @"Other scripts' families aren't listed");
}

- (void)testWithoutLanguageInformationListsEveryFamily {
    STFontFamilyList *list = [[STFontFamilyList alloc] initWithFamilies:@[@"B", @"a", @"C"] coveredFamilies:nil recent:@[]];
    XCTAssertEqualObjects(list.listedFamilies, (@[@"a", @"B", @"C"]));
}

- (void)testCompletesFromListedThenAllFamilies {
    STFontFamilyList *list = [self sampleList];
    XCTAssertEqualObjects([list completionForPrefix:@"noto"], @"Noto Sans", @"Listed families come first");
    XCTAssertEqualObjects([list completionForPrefix:@"Noto Sans B"], @"Noto Sans Bengali", @"Any installed family can be typed");
    XCTAssertNil([list completionForPrefix:@"Zz"]);
    XCTAssertEqualObjects([list familyNamed:@"  dejavu sans "], @"DejaVu Sans");
    XCTAssertNil([list familyNamed:@"Missing Font"]);
}

- (void)testRemembersRecentFamilies {
    STFontFamilyList *list = [self sampleList];
    [list noteUsedFamily:@"cantarell"];
    XCTAssertEqualObjects([list.listedFamilies subarrayWithRange:NSMakeRange(0, 2)], (@[@"Cantarell", @"Arial"]));
    XCTAssertEqualObjects([[NSUserDefaults standardUserDefaults] stringArrayForKey:STRecentFontFamiliesDefaultsKey], (@[@"Cantarell", @"Arial"]));
    for (NSString *family in @[@"Noto Sans", @"DejaVu Sans", @"Noto Sans Bengali", @"Arial", @"Cantarell", @"Noto Sans"]) {
        [list noteUsedFamily:family];
    }
    XCTAssertLessThanOrEqual(list.recentCount, STRecentFontFamiliesLimit);
}

#pragma mark - The bar's field

- (STTextOptionsBar *)barWithRecorder:(TextFontFieldRecorder *)recorder {
    STTextOptionsBar *bar = [[STTextOptionsBar alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1400.0, [STTextOptionsBar preferredHeight])];
    bar.fontFamilies = [self sampleList];
    [bar.fontField reloadData];
    bar.delegate = recorder;
    [bar updateWithFont:[NSFont systemFontOfSize:20.0]
                  color:[NSColor redColor]
                  style:MarkupTextStylePlain
             sizePreset:STTextSizePresetExact
              alignment:NSTextAlignmentLeft
          boldAvailable:YES
        italicAvailable:YES];
    return bar;
}

#if defined(GNUSTEP)
- (void)testFontIsADropdownButtonShowingTheFamily {
    XCTSkipIf(_shouldSkip, @"No window server");
    STTextOptionsBar *bar = [self barWithRecorder:[[TextFontFieldRecorder alloc] init]];
    XCTAssertTrue([bar.fontButton isKindOfClass:[NSPopUpButton class]], @"drawn by the theme as a dropdown");
    XCTAssertNil(bar.fontField, @"no combo box on GNUstep");
    XCTAssertEqualObjects(bar.fontButton.titleOfSelectedItem,
                          [STFontFamilyList displayNameForFamily:[NSFont systemFontOfSize:20.0].familyName]);
    XCTAssertTrue([bar.visibleControls containsObject:bar.fontButton]);
}

- (void)testPickerListsRecentThenLanguageFamiliesUnderHeadings {
    XCTSkipIf(_shouldSkip, @"No window server");
    STFontPicker *picker = [[STFontPicker alloc] initWithFamilies:[self sampleList]];
    NSArray<NSString *> *titles = [picker shownRowTitles];
    XCTAssertEqual(titles.count, (NSUInteger)6, @"%@", titles);
    XCTAssertEqualObjects(titles[0], @"# Recent");
    XCTAssertEqualObjects(titles[1], @"Arial");
    XCTAssertTrue([titles[2] hasPrefix:@"# "], @"the language's heading: %@", titles[2]);
    XCTAssertEqualObjects([titles subarrayWithRange:NSMakeRange(3, 3)], (@[@"Cantarell", @"DejaVu Sans", @"Noto Sans"]));
}

- (void)testSearchListsEveryInstalledMatchStartingWithItFirst {
    XCTSkipIf(_shouldSkip, @"No window server");
    STFontPicker *picker = [[STFontPicker alloc] initWithFamilies:[self sampleList]];
    [picker setSearchString:@"sans"];
    XCTAssertEqualObjects([picker shownRowTitles], (@[@"DejaVu Sans", @"Noto Sans", @"Noto Sans Bengali"]),
                          @"any installed family, not only the listed ones, with no headings");
    [picker setSearchString:@"noto"];
    XCTAssertEqualObjects([picker shownRowTitles], (@[@"Noto Sans", @"Noto Sans Bengali"]));
    [picker setSearchString:@"Ben"];
    XCTAssertEqualObjects([picker shownRowTitles], (@[@"Noto Sans Bengali"]));
    [picker setSearchString:@"zzz"];
    XCTAssertEqualObjects([picker shownRowTitles], (@[]));
}

- (void)testTypingInTheSearchFieldListsWhatHasBeenTyped {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setReleasedWhenClosed:NO];
    [window orderFront:nil];
    NSView *anchor = [[NSView alloc] initWithFrame:NSMakeRect(20, 200, 120, 30)];
    [window.contentView addSubview:anchor];
    STFontPicker *picker = [[STFontPicker alloc] initWithFamilies:[self sampleList]];
    [picker showBelowView:anchor];
    NSText *editor = [picker.searchField currentEditor];
    XCTAssertNotNil(editor, @"the search field has the keyboard");
    // One key at a time, as typed: each change lists the matches for the whole text so far.
    for (NSString *key in @[@"n", @"o", @"t", @"o", @" ", @"s", @"a", @"n", @"s", @" ", @"b"]) {
        [(NSTextView *)editor insertText:key];
    }
    XCTAssertEqualObjects([picker shownRowTitles], (@[@"Noto Sans Bengali"]));
    [(NSTextView *)editor deleteBackward:nil];
    XCTAssertEqualObjects([picker shownRowTitles], (@[@"Noto Sans", @"Noto Sans Bengali"]));
    [picker close];
    [window orderOut:nil];
}

/// The list's visible part, after showing the picker with this family current.
- (NSRect)visibleListShowingFamily:(NSString *)family ofFamilies:(NSArray<NSString *> *)families picker:(STFontPicker **)pickerOut {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setReleasedWhenClosed:NO];
    [window orderFront:nil];
    NSView *anchor = [[NSView alloc] initWithFrame:NSMakeRect(20, 200, 120, 30)];
    [window.contentView addSubview:anchor];
    STFontPicker *picker = [[STFontPicker alloc] initWithFamilies:[[STFontFamilyList alloc] initWithFamilies:families coveredFamilies:nil recent:@[]]];
    picker.currentFamily = family;
    [picker showBelowView:anchor];
    *pickerOut = picker;
    NSRect visible = picker.tableView.visibleRect;
    [picker close];
    [window orderOut:nil];
    return visible;
}

- (void)testOpensWithTheCurrentFamilyAmongTheRowsAroundIt {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSMutableArray<NSString *> *families = [[NSMutableArray alloc] init];
    for (NSInteger i = 0; i < 60; i++) {
        [families addObject:[NSString stringWithFormat:@"Family %02ld", (long)i]];
    }
    STFontPicker *picker = nil;
    NSRect visible = [self visibleListShowingFamily:@"Family 02" ofFamilies:families picker:&picker];
    XCTAssertEqualWithAccuracy(NSMinY(visible), 0.0, 0.5, @"in the first screenful: the list stays at the top, heading and all");

    visible = [self visibleListShowingFamily:@"Family 40" ofFamilies:families picker:&picker];
    NSRect row = [picker.tableView rectOfRow:[[picker shownRowTitles] indexOfObject:@"Family 40"]];
    XCTAssertEqualWithAccuracy(NSMidY(row), NSMidY(visible), 1.0, @"further down: in the middle of the list");

    visible = [self visibleListShowingFamily:@"Family 59" ofFamilies:families picker:&picker];
    XCTAssertEqualWithAccuracy(NSMaxY(visible), NSHeight(picker.tableView.frame), 0.5, @"the last one: the list ends at the bottom");
}

- (void)testUpDownSkipHeadingsAndReturnChooses {
    XCTSkipIf(_shouldSkip, @"No window server");
    STFontPicker *picker = [[STFontPicker alloc] initWithFamilies:[self sampleList]];
    TextFontPickerRecorder *recorder = [[TextFontPickerRecorder alloc] init];
    picker.delegate = recorder;
    XCTAssertEqual([picker selectedRow], -1, @"nothing selected: Return takes the first family");
    [picker moveSelectionBy:1];
    XCTAssertEqual([picker selectedRow], 1, @"over the Recent heading");
    [picker moveSelectionBy:1];
    XCTAssertEqual([picker selectedRow], 3, @"over the language's heading");
    [picker chooseSelectedOrFirst];
    XCTAssertEqualObjects(recorder.chosenFamily, @"Cantarell");

    [picker setSearchString:@"dej"];
    [picker chooseSelectedOrFirst];
    XCTAssertEqualObjects(recorder.chosenFamily, @"DejaVu Sans", @"Return on a search takes the first match");
    XCTAssertEqualObjects(picker.currentFamily, @"DejaVu Sans", @"and checks it");
}

- (void)testChoosingPicksTheFamilyAndClosingGivesTheKeyboardBackOnce {
    XCTSkipIf(_shouldSkip, @"No window server");
    TextFontFieldRecorder *recorder = [[TextFontFieldRecorder alloc] init];
    STTextOptionsBar *bar = [self barWithRecorder:recorder];
    [bar fontPicker:nil didChooseFamily:@"cantarell"];
    [bar fontPickerDidClose:nil];
    XCTAssertEqualObjects(recorder.pickedFamily, @"Cantarell");
    XCTAssertEqualObjects(bar.fontButton.titleOfSelectedItem, @"Cantarell");
    XCTAssertEqual(recorder.finishedEntries, 1, @"the keyboard goes back to the text box, once");
    XCTAssertEqualObjects(bar.fontFamilies.listedFamilies.firstObject, @"Cantarell", @"It's now the most recent");

    // Closed without a choice (Escape, a click elsewhere): the font stays.
    recorder.pickedFamily = nil;
    [bar fontPickerDidClose:nil];
    XCTAssertNil(recorder.pickedFamily);
    XCTAssertEqualObjects(bar.fontButton.titleOfSelectedItem, @"Cantarell");
    XCTAssertEqual(recorder.finishedEntries, 2);
}

#else
- (void)testFieldIsAnEditableComboBoxOfTheListedFamilies {
    XCTSkipIf(_shouldSkip, @"No window server");
    STTextOptionsBar *bar = [self barWithRecorder:[[TextFontFieldRecorder alloc] init]];
    XCTAssertTrue([bar.fontField isKindOfClass:[NSComboBox class]]);
    XCTAssertTrue(bar.fontField.usesDataSource);
    XCTAssertTrue(bar.fontField.isEditable);
    XCTAssertTrue(bar.fontField.completes);
    XCTAssertFalse(bar.fontField.refusesFirstResponder, @"The field takes the keyboard for typing");
    // From its data source (GNUstep's -numberOfItems doesn't ask it).
    XCTAssertEqual([bar.fontField.dataSource numberOfItemsInComboBox:bar.fontField], 4);
    XCTAssertEqualObjects([bar.fontField.dataSource comboBox:bar.fontField objectValueForItemAtIndex:0], @"Arial");
    XCTAssertTrue([bar.visibleControls containsObject:bar.fontField]);
}

- (void)testTypingAPrefixChoosesTheCompletedFamily {
    XCTSkipIf(_shouldSkip, @"No window server");
    TextFontFieldRecorder *recorder = [[TextFontFieldRecorder alloc] init];
    STTextOptionsBar *bar = [self barWithRecorder:recorder];
    [bar.fontField setStringValue:@"dejav"];
    [bar fontEntered:bar.fontField];
    XCTAssertEqualObjects(recorder.pickedFamily, @"DejaVu Sans");
    XCTAssertEqualObjects(bar.fontField.stringValue, @"DejaVu Sans");
    XCTAssertEqual(recorder.finishedEntries, 1, @"The keyboard goes back to the text box");
    XCTAssertEqualObjects(bar.fontFamilies.listedFamilies.firstObject, @"DejaVu Sans", @"It's now the most recent");
}

- (void)testUnknownNameOrEscapeKeepsTheFont {
    XCTSkipIf(_shouldSkip, @"No window server");
    TextFontFieldRecorder *recorder = [[TextFontFieldRecorder alloc] init];
    STTextOptionsBar *bar = [self barWithRecorder:recorder];
    NSString *shown = bar.fontField.stringValue;
    [bar.fontField setStringValue:@"No Such Font"];
    [bar fontEntered:bar.fontField];
    XCTAssertNil(recorder.pickedFamily);
    XCTAssertEqualObjects(bar.fontField.stringValue, shown);

    [bar.fontField setStringValue:@"Cant"];
    XCTAssertTrue([bar control:bar.fontField textView:nil doCommandBySelector:@selector(cancelOperation:)]);
    XCTAssertNil(recorder.pickedFamily);
    XCTAssertEqualObjects(bar.fontField.stringValue, shown);
    XCTAssertEqual(recorder.finishedEntries, 2);
}

#endif

#pragma mark - The canvas keeps editing

- (ScreenshotCanvasView *)canvasEditingTextIn:(AppDelegate *)appDelegate {
    ScreenshotCanvasView *canvas = appDelegate.canvasView;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600.0, 300.0)];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 600.0, 300.0));
    [image unlockFocus];
    [canvas loadImage:image];
    [appDelegate.window setContentSize:NSMakeSize(600.0, 300.0)];
    [appDelegate layoutContentSubviews];
    canvas.activeTool = ScreenshotCanvasToolText;
    [canvas beginTextEntryWithImageRect:NSMakeRect(100.0, 150.0, 1.0, 1.0) existingText:nil];
    return canvas;
}

- (void)testTextBoxStaysOpenWhileTheCompanionTakesTheKeyboard {
    XCTSkipIf(_shouldSkip, @"No window server");
    AppDelegate *appDelegate = [[AppDelegate alloc] init];
    [appDelegate setupWindowAndContent];
    ScreenshotCanvasView *canvas = [self canvasEditingTextIn:appDelegate];
    XCTAssertNotNil([canvas activeTextEntry]);
    TextFontFieldCompanion *companion = [[TextFontFieldCompanion alloc] init];
    canvas.textEditingCompanion = companion;

    companion.taking = YES;
    [appDelegate.window makeFirstResponder:nil];
    XCTAssertNotNil([canvas activeTextEntry], @"Focus moving into the companion leaves the box open");
    XCTAssertTrue([canvas focusActiveTextView], @"and the box can have the keyboard back");
    XCTAssertEqual(appDelegate.window.firstResponder, canvas.activeTextView);

    companion.taking = NO;
    [appDelegate.window makeFirstResponder:nil];
    XCTAssertNil([canvas activeTextEntry], @"Focus going anywhere else finishes the box");
    XCTAssertFalse([canvas focusActiveTextView]);
}

@end
