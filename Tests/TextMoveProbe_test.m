/*
 * TextMoveProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Moving a label with the Text tool, and the text bar taking its row from the viewport
 * without moving the image or resizing the window.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupText.h"
#import "STTextOptionsBar.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (TextMoveTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (NSScrollView *)scrollView;
- (ScreenshotCanvasView *)canvasView;
- (void)showTextOptionsBar;
- (void)hideTextOptionsBar;
@end

@interface ScreenshotCanvasView (TextMoveTesting)
@property (nonatomic, strong) NSMutableArray<MarkupText *> *texts;
@property (nonatomic, strong) NSTextView *activeTextView;
- (void)beginTextEntryWithImageRect:(NSRect)imageRect existingText:(MarkupText *)existingText;
- (void)commitActiveTextIfNeeded;
- (NSRect)viewRectForImageRect:(NSRect)imageRect;
- (BOOL)isPointOnActiveTextBorder:(NSPoint)viewPoint;
@end

@interface TextMoveProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation TextMoveProbeTests

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

#pragma mark - Helpers

- (NSImage *)whiteImageOfSize:(NSSize)size {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    [image unlockFocus];
    return image;
}

- (ScreenshotCanvasView *)textCanvas {
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self whiteImageOfSize:NSMakeSize(600.0, 300.0)]];
    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;
    canvas.textFont = [NSFont fontWithName:@"DejaVuSans" size:24.0] ?: [NSFont systemFontOfSize:24.0];
    canvas.textSizePreset = STTextSizePresetExact;
    canvas.textStyle = MarkupTextStylePlain;
    canvas.activeTool = ScreenshotCanvasToolText;
    return canvas;
}

/// A committed label reading "Move me" at (100, 80).
- (MarkupText *)labelOn:(ScreenshotCanvasView *)canvas {
    [canvas beginTextEntryWithImageRect:NSMakeRect(100.0, 80.0, 1.0, 1.0) existingText:nil];
    [canvas.activeTextView insertText:@"Move me"];
    [canvas commitActiveTextIfNeeded];
    // Without a run loop every undo lands in one group: start the tests' steps from a clean stack.
    [[canvas undoManager] removeAllActions];
    return canvas.texts.lastObject;
}

- (NSEvent *)mouse:(NSEventType)type at:(NSPoint)point canvas:(ScreenshotCanvasView *)canvas {
    return [NSEvent mouseEventWithType:type location:[canvas convertPoint:point toView:nil] modifierFlags:0
                             timestamp:0 windowNumber:[canvas.window windowNumber] context:nil
                           eventNumber:0 clickCount:1 pressure:1.0];
}

/// Presses at a, drags to b in a few steps, and releases there.
- (void)drag:(ScreenshotCanvasView *)canvas from:(NSPoint)a to:(NSPoint)b {
    [canvas mouseDown:[self mouse:NSLeftMouseDown at:a canvas:canvas]];
    for (NSInteger step = 1; step <= 4; step++) {
        CGFloat t = step / 4.0;
        NSPoint p = NSMakePoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
        [canvas mouseDragged:[self mouse:NSLeftMouseDragged at:p canvas:canvas]];
    }
    [canvas mouseUp:[self mouse:NSLeftMouseUp at:b canvas:canvas]];
}

- (NSPoint)centreOf:(MarkupText *)label on:(ScreenshotCanvasView *)canvas {
    NSRect rect = [canvas viewRectForImageRect:label.bounds];
    return NSMakePoint(NSMidX(rect), NSMidY(rect));
}

#pragma mark - Moving labels

- (void)testDraggingALabelWithTheTextToolMovesIt {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self textCanvas];
    MarkupText *label = [self labelOn:canvas];
    XCTAssertNotNil(label);
    NSPoint origin = label.origin;
    NSPoint start = [self centreOf:label on:canvas];

    [self drag:canvas from:start to:NSMakePoint(start.x + 40.0, start.y + 30.0)];

    MarkupText *moved = canvas.texts.lastObject;
    XCTAssertEqualWithAccuracy(moved.origin.x, origin.x + 40.0, 0.01, @"The label follows the drag");
    XCTAssertEqualWithAccuracy(moved.origin.y, origin.y + 30.0, 0.01);
    XCTAssertNil(canvas.activeTextView, @"Dragging moves the label instead of editing it");

    [[canvas undoManager] undo];
    MarkupText *restored = canvas.texts.lastObject;
    XCTAssertEqualWithAccuracy(restored.origin.x, origin.x, 0.01, @"Undo puts the label back");
    XCTAssertEqualWithAccuracy(restored.origin.y, origin.y, 0.01);
}

- (void)testClickingALabelStillEditsIt {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self textCanvas];
    MarkupText *label = [self labelOn:canvas];
    NSPoint origin = label.origin;
    NSPoint point = [self centreOf:label on:canvas];

    [canvas mouseDown:[self mouse:NSLeftMouseDown at:point canvas:canvas]];
    // A little jitter under the threshold is still a click.
    [canvas mouseDragged:[self mouse:NSLeftMouseDragged at:NSMakePoint(point.x + 1.0, point.y + 1.0) canvas:canvas]];
    [canvas mouseUp:[self mouse:NSLeftMouseUp at:NSMakePoint(point.x + 1.0, point.y + 1.0) canvas:canvas]];

    XCTAssertNotNil(canvas.activeTextView, @"A click edits the label");
    XCTAssertEqual([canvas activeTextEntry], label);
    XCTAssertTrue(NSEqualPoints(label.origin, origin), @"A click doesn't move it");
}

- (void)testDraggingTheEditedLabelsBorderMovesIt {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self textCanvas];
    MarkupText *label = [self labelOn:canvas];
    [canvas beginTextEntryWithImageRect:label.bounds existingText:label];
    MarkupText *entry = [canvas activeTextEntry];
    XCTAssertNotNil(entry);
    NSPoint origin = entry.origin;
    NSRect textRect = [canvas viewRectForImageRect:entry.bounds];
    NSPoint border = NSMakePoint(NSMinX(textRect) - 2.0, NSMidY(textRect));
    XCTAssertTrue([canvas isPointOnActiveTextBorder:border], @"Just outside the text is the border");
    NSRect textViewFrame = canvas.activeTextView.frame;

    [self drag:canvas from:border to:NSMakePoint(border.x + 50.0, border.y + 20.0)];

    XCTAssertNotNil(canvas.activeTextView, @"Moving the label keeps it open for editing");
    XCTAssertEqualWithAccuracy(entry.origin.x, origin.x + 50.0, 0.01, @"The border drags the label");
    XCTAssertEqualWithAccuracy(entry.origin.y, origin.y + 20.0, 0.01);
    XCTAssertEqualWithAccuracy(NSMinX(canvas.activeTextView.frame), NSMinX(textViewFrame) + 50.0, 0.5, @"The text view moves with it");
}

- (void)testPressingInsideTheEditedTextDoesNotMoveIt {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self textCanvas];
    MarkupText *label = [self labelOn:canvas];
    [canvas beginTextEntryWithImageRect:label.bounds existingText:label];
    MarkupText *entry = [canvas activeTextEntry];
    NSPoint origin = entry.origin;
    NSPoint inside = [self centreOf:entry on:canvas];
    XCTAssertFalse([canvas isPointOnActiveTextBorder:inside], @"Inside the text is for the caret");

    [self drag:canvas from:inside to:NSMakePoint(inside.x + 30.0, inside.y)];

    XCTAssertTrue(NSEqualPoints(entry.origin, origin), @"Dragging in the text selects; it doesn't move the label");
}

#pragma mark - The text bar

- (void)testTextBarKeepsTheImageStillAndTheWindowItsSize {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self whiteImageOfSize:NSMakeSize(500.0, 2000.0)]];
    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;
    NSClipView *clip = _appDelegate.scrollView.contentView;
    [clip scrollToPoint:NSMakePoint(0.0, 300.0)];
    NSRect windowFrame = _appDelegate.window.frame;
    NSRect scrollFrame = _appDelegate.scrollView.frame;
    CGFloat barHeight = [STTextOptionsBar preferredHeight];
    // Where an image point sits in the window, before and after.
    NSPoint imagePoint = NSMakePoint(10.0, 400.0);
    NSPoint before = [canvas convertPoint:imagePoint toView:nil];

    [_appDelegate showTextOptionsBar];

    XCTAssertTrue(NSEqualRects(_appDelegate.window.frame, windowFrame), @"The window keeps its size");
    XCTAssertEqualWithAccuracy(NSHeight(_appDelegate.scrollView.frame), NSHeight(scrollFrame) - barHeight, 0.5, @"The viewport gives up the row");
    NSPoint during = [canvas convertPoint:imagePoint toView:nil];
    XCTAssertEqualWithAccuracy(during.y, before.y, 0.5, @"The image doesn't move on screen");

    [_appDelegate hideTextOptionsBar];

    XCTAssertTrue(NSEqualRects(_appDelegate.window.frame, windowFrame), @"Still the same window");
    XCTAssertEqualWithAccuracy(NSHeight(_appDelegate.scrollView.frame), NSHeight(scrollFrame), 0.5);
    NSPoint after = [canvas convertPoint:imagePoint toView:nil];
    XCTAssertEqualWithAccuracy(after.y, before.y, 0.5, @"Nor when the row goes");
}

@end
