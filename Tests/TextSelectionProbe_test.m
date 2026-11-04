/*
 * TextSelectionProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Selecting recognised words (#330): hit testing with slop, drags in either direction and from the
 * margins, Shift-click extending, word/line/all and rect selections, and the text and rects a
 * selection gives. STTextSelection is Foundation only, so this needs no window.
 */

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#import "STTextRecognizer.h"
#import "STTextSelection.h"

@interface TextSelectionProbeTests : XCTestCase
@end

@implementation TextSelectionProbeTests

static STRecognizedWord *Word(NSString *text, CGFloat x, CGFloat y, CGFloat width) {
    return [[STRecognizedWord alloc] initWithText:text bounds:NSMakeRect(x, y, width, 20.0)];
}

/// "Hello world" on y 10–30, then "second line here" on y 50–70; words 0–4 in reading order.
- (NSArray<STRecognizedLine *> *)twoLines {
    return @[
        [[STRecognizedLine alloc] initWithWords:@[ Word(@"Hello", 10, 10, 50), Word(@"world", 70, 10, 60) ]],
        [[STRecognizedLine alloc] initWithWords:@[ Word(@"second", 10, 50, 70), Word(@"line", 90, 50, 40),
                                                   Word(@"here", 140, 50, 40) ]],
    ];
}

- (STTextSelection *)selection {
    return [[STTextSelection alloc] initWithLines:[self twoLines]];
}

- (void)assertRange:(NSRange)range equals:(NSRange)expected message:(NSString *)message {
    XCTAssertEqual(range.location, expected.location, @"%@", message);
    XCTAssertEqual(range.length, expected.length, @"%@", message);
}

- (void)testWordsAreIndexedInReadingOrder {
    STTextSelection *selection = [self selection];
    XCTAssertEqual(selection.wordCount, (NSUInteger)5);
    XCTAssertTrue(NSEqualRects([selection boundsOfWordAtIndex:3], NSMakeRect(90, 50, 40, 20)));
    XCTAssertTrue(NSEqualRects([selection boundsOfWordAtIndex:5], NSZeroRect), @"Out of range is NSZeroRect");
    XCTAssertEqual([selection lineIndexOfWordAtIndex:1], (NSUInteger)0);
    XCTAssertEqual([selection lineIndexOfWordAtIndex:2], (NSUInteger)1);
    XCTAssertEqual([selection lineIndexOfWordAtIndex:5], (NSUInteger)NSNotFound);
    XCTAssertEqual(selection.anchorIndex, (NSUInteger)NSNotFound, @"Nothing is selected at first");
    XCTAssertEqual(selection.selectedRange.length, (NSUInteger)0);
}

- (void)testALineWithNoWordsKeepsTheLineIndexes {
    NSArray<STRecognizedLine *> *lines = [self twoLines];
    STRecognizedLine *empty = [[STRecognizedLine alloc] initWithWords:@[]];
    STTextSelection *selection = [[STTextSelection alloc] initWithLines:@[ lines[0], empty, lines[1] ]];
    XCTAssertEqual(selection.wordCount, (NSUInteger)5);
    XCTAssertEqual([selection lineIndexOfWordAtIndex:2], (NSUInteger)2, @"Line indexes are into `lines`");
    [selection selectLineOfWordAtIndex:3];
    [self assertRange:selection.selectedRange equals:NSMakeRange(2, 3) message:@"The line after the empty one"];
    XCTAssertEqual([selection wordIndexAtImagePoint:NSMakePoint(20, 40) slop:2.0], (NSUInteger)NSNotFound,
                   @"An empty line has no band to hit");
}

- (void)testHitTestingFindsTheWordAndUsesSlop {
    STTextSelection *selection = [self selection];
    XCTAssertEqual([selection wordIndexAtImagePoint:NSMakePoint(20, 20) slop:0.0], (NSUInteger)0);
    XCTAssertEqual([selection wordIndexAtImagePoint:NSMakePoint(150, 60) slop:0.0], (NSUInteger)4);
    XCTAssertEqual([selection wordIndexAtImagePoint:NSMakePoint(20, 33) slop:0.0], (NSUInteger)NSNotFound,
                   @"Just under a line, with no slop, is no word");
    XCTAssertEqual([selection wordIndexAtImagePoint:NSMakePoint(20, 33) slop:4.0], (NSUInteger)0,
                   @"Slop grows the word's box");
    XCTAssertEqual([selection wordIndexAtImagePoint:NSMakePoint(20, 40) slop:4.0], (NSUInteger)NSNotFound,
                   @"Between lines, beyond the slop, is no word");
    XCTAssertEqual([selection wordIndexAtImagePoint:NSMakePoint(500, 500) slop:4.0], (NSUInteger)NSNotFound);
}

- (void)testAPointBetweenWordsGivesTheNearestWordOnItsLine {
    STTextSelection *selection = [self selection];
    XCTAssertEqual([selection wordIndexAtImagePoint:NSMakePoint(62, 20) slop:0.0], (NSUInteger)0,
                   @"Nearer Hello's end than world's start");
    XCTAssertEqual([selection wordIndexAtImagePoint:NSMakePoint(67, 20) slop:0.0], (NSUInteger)1,
                   @"Nearer world's start");
    XCTAssertEqual([selection wordIndexAtImagePoint:NSMakePoint(400, 60) slop:0.0], (NSUInteger)4,
                   @"Right of a line, on its band, is its last word");
}

- (void)testADragSelectsInEitherDirection {
    STTextSelection *selection = [self selection];
    [selection selectFromImagePoint:NSMakePoint(20, 20) toImagePoint:NSMakePoint(100, 60)];
    [self assertRange:selection.selectedRange equals:NSMakeRange(0, 4) message:@"Hello through line"];
    XCTAssertEqual(selection.anchorIndex, (NSUInteger)0);

    [selection selectFromImagePoint:NSMakePoint(100, 60) toImagePoint:NSMakePoint(20, 20)];
    [self assertRange:selection.selectedRange equals:NSMakeRange(0, 4) message:@"The same words, dragged back"];
    XCTAssertEqual(selection.anchorIndex, (NSUInteger)3, @"The anchor is where the drag began");

    [selection selectFromImagePoint:NSMakePoint(20, 20) toImagePoint:NSMakePoint(25, 22)];
    [self assertRange:selection.selectedRange equals:NSMakeRange(0, 1) message:@"Inside one word"];
}

- (void)testADragFromTheMarginsSnapsToTheNearestWord {
    STTextSelection *selection = [self selection];
    [selection selectFromImagePoint:NSMakePoint(0, 60) toImagePoint:NSMakePoint(300, 200)];
    [self assertRange:selection.selectedRange equals:NSMakeRange(2, 3)
              message:@"Left of the second line to below the text: the whole second line"];
    [selection selectFromImagePoint:NSMakePoint(100, 0) toImagePoint:NSMakePoint(5, 40)];
    XCTAssertGreaterThan(selection.selectedRange.length, (NSUInteger)0, @"Margins and gaps never select nothing");
}

- (void)testShiftClickExtendsFromTheAnchor {
    STTextSelection *selection = [self selection];
    [selection selectWordAtIndex:1];
    [selection extendSelectionToImagePoint:NSMakePoint(160, 60)];
    [self assertRange:selection.selectedRange equals:NSMakeRange(1, 4) message:@"world through here"];
    XCTAssertEqual(selection.anchorIndex, (NSUInteger)1, @"Extending keeps the anchor");
    [selection extendSelectionToImagePoint:NSMakePoint(20, 20)];
    [self assertRange:selection.selectedRange equals:NSMakeRange(0, 2) message:@"Back past the anchor: Hello world"];

    [selection clearSelection];
    [selection extendSelectionToImagePoint:NSMakePoint(100, 60)];
    [self assertRange:selection.selectedRange equals:NSMakeRange(3, 1) message:@"With no anchor, the word clicked"];
    XCTAssertEqual(selection.anchorIndex, (NSUInteger)3);
}

- (void)testWordLineAndAll {
    STTextSelection *selection = [self selection];
    [selection selectWordAtIndex:3];
    [self assertRange:selection.selectedRange equals:NSMakeRange(3, 1) message:@"A double click's word"];
    [selection selectLineOfWordAtIndex:3];
    [self assertRange:selection.selectedRange equals:NSMakeRange(2, 3) message:@"A triple click's line"];
    XCTAssertEqual(selection.anchorIndex, (NSUInteger)2);
    [selection selectAll];
    [self assertRange:selection.selectedRange equals:NSMakeRange(0, 5) message:@"Everything"];
    XCTAssertEqual(selection.anchorIndex, (NSUInteger)0);
    [selection selectWordAtIndex:9];
    XCTAssertEqual(selection.selectedRange.length, (NSUInteger)0, @"A word out of range clears the selection");
    XCTAssertEqual(selection.anchorIndex, (NSUInteger)NSNotFound);
}

- (void)testARectSelectsTheWordsWhoseMiddleItHolds {
    STTextSelection *selection = [self selection];
    [selection selectWordsInImageRect:NSMakeRect(60, 0, 100, 80)];
    [self assertRange:selection.selectedRange equals:NSMakeRange(1, 3)
              message:@"world and line, and second between them in reading order"];
    XCTAssertEqual(selection.anchorIndex, (NSUInteger)1);
    [selection selectWordsInImageRect:NSMakeRect(300, 300, 50, 50)];
    XCTAssertEqual(selection.selectedRange.length, (NSUInteger)0, @"A rect over no word clears the selection");
}

- (void)testSettingARangeThatDoesntFitClearsIt {
    STTextSelection *selection = [self selection];
    selection.selectedRange = NSMakeRange(1, 2);
    [self assertRange:selection.selectedRange equals:NSMakeRange(1, 2) message:@"A range that fits"];
    XCTAssertEqual(selection.anchorIndex, (NSUInteger)1);
    selection.selectedRange = NSMakeRange(4, 3);
    XCTAssertEqual(selection.selectedRange.length, (NSUInteger)0, @"Past the last word");
    XCTAssertEqual(selection.anchorIndex, (NSUInteger)NSNotFound);
}

- (void)testSelectedTextJoinsAsRecognizedTextDoes {
    NSArray<STRecognizedLine *> *lines = [self twoLines];
    STTextSelection *selection = [[STTextSelection alloc] initWithLines:lines];
    XCTAssertEqualObjects(selection.selectedText, @"", @"Nothing selected");
    [selection selectAll];
    XCTAssertEqualObjects(selection.selectedText, STRecognizedText(lines), @"All of it is what Copy Text copies");
    XCTAssertEqualObjects(selection.selectedText, @"Hello world\nsecond line here");
    selection.selectedRange = NSMakeRange(1, 3);
    XCTAssertEqualObjects(selection.selectedText, @"world\nsecond line");
}

- (void)testSelectedRectsAreOnePerLine {
    STTextSelection *selection = [self selection];
    XCTAssertEqual(selection.selectedRects.count, (NSUInteger)0);
    selection.selectedRange = NSMakeRange(1, 3);
    NSArray<NSValue *> *rects = selection.selectedRects;
    XCTAssertEqual(rects.count, (NSUInteger)2);
    XCTAssertTrue(NSEqualRects(rects[0].rectValue, NSMakeRect(70, 10, 60, 20)), @"world alone on the first line");
    XCTAssertTrue(NSEqualRects(rects[1].rectValue, NSMakeRect(10, 50, 120, 20)), @"second through line");
}

@end
