/*
 * TextToolProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Text box sizing, hit-testing and the editing interactions of the text tool.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupText.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (TextToolTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
@end

@interface ScreenshotCanvasView (TextToolTesting)
@property (nonatomic, strong) NSTextView *activeTextView;
@property (nonatomic, strong) MarkupText *currentTextEntry;
@property (nonatomic, strong) NSMutableArray<MarkupText *> *texts;
@property (nonatomic, assign) BOOL isCreatingTextBox;
- (NSRect)activeTextHandleRectInView;
- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector;
@end

@interface TextToolProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation TextToolProbeTests

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

- (NSFont *)fontOfSize:(CGFloat)size {
    return [NSFont fontWithName:@"DejaVuSans" size:size] ?: [NSFont systemFontOfSize:size];
}

- (MarkupText *)textWithString:(NSString *)string size:(CGFloat)size origin:(NSPoint)origin {
    return [[MarkupText alloc] initWithText:string
                                       font:[self fontOfSize:size]
                                      color:[NSColor redColor]
                                     origin:origin
                                     boxSize:NSMakeSize(1.0, 1.0)];
}

- (ScreenshotCanvasView *)canvasWithTextTool {
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(800.0, 400.0)];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 800.0, 400.0));
    [image unlockFocus];
    [canvas loadImage:image];
    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;
    canvas.textFont = [self fontOfSize:24.0];
    canvas.activeTool = ScreenshotCanvasToolText;
    return canvas;
}

- (NSEvent *)mouseEvent:(NSEventType)type atViewPoint:(NSPoint)viewPoint in:(ScreenshotCanvasView *)canvas {
    NSPoint windowPoint = [canvas convertPoint:viewPoint toView:nil];
    return [NSEvent mouseEventWithType:type
                              location:windowPoint
                         modifierFlags:0
                             timestamp:0
                          windowNumber:[canvas.window windowNumber]
                               context:nil
                           eventNumber:0
                            clickCount:1
                              pressure:1.0];
}

- (void)clickCanvas:(ScreenshotCanvasView *)canvas atViewPoint:(NSPoint)point {
    [canvas mouseDown:[self mouseEvent:NSLeftMouseDown atViewPoint:point in:canvas]];
    [canvas mouseUp:[self mouseEvent:NSLeftMouseUp atViewPoint:point in:canvas]];
}

#pragma mark - Box sizing (#15, #18, #19)

- (void)testClickedBoxHugsTextOnOneLine {
    MarkupText *text = [self textWithString:@"Fix this label" size:64.0 origin:NSMakePoint(100.0, 100.0)];
    XCTAssertTrue([text fitToTextWithinCanvasSize:NSMakeSize(800.0, 400.0)]);
    XCTAssertEqualWithAccuracy(text.boxSize.height, [text lineHeight], 1.0, @"A short label should stay on one line");
    XCTAssertTrue(text.boxSize.width < 700.0, @"An unfixed box should be about as wide as its text, not the space available");
    XCTAssertTrue(text.boxSize.width >= text.measuredSize.width, @"The box must hold the measured text");
}

- (void)testBoxShrinksWhenLinesAreDeleted {
    MarkupText *text = [self textWithString:@"Hi\n\n\n\nx" size:24.0 origin:NSMakePoint(50.0, 50.0)];
    [text fitToTextWithinCanvasSize:NSMakeSize(800.0, 400.0)];
    CGFloat tallHeight = text.boxSize.height;
    text.text = @"Hi";
    [text fitToTextWithinCanvasSize:NSMakeSize(800.0, 400.0)];
    XCTAssertTrue(text.boxSize.height < tallHeight, @"Deleting lines should shrink the box");
    XCTAssertEqualWithAccuracy(text.boxSize.height, [text lineHeight], 1.0);
}

- (void)testFixedWidthWrapsAndKeepsWidth {
    MarkupText *text = [self textWithString:@"one two three four five six" size:24.0 origin:NSMakePoint(50.0, 50.0)];
    text.widthIsFixed = YES;
    text.boxSize = NSMakeSize(150.0, 10.0);
    [text fitToTextWithinCanvasSize:NSMakeSize(800.0, 400.0)];
    XCTAssertEqualWithAccuracy(text.boxSize.width, 150.0, 0.5, @"A dragged width is kept");
    XCTAssertTrue(text.boxSize.height > [text lineHeight] * 1.5, @"Text wraps within a fixed width and the box grows to fit");
}

- (void)testClickNearRightEdgeKeepsItsOrigin {
    MarkupText *text = [self textWithString:@"Edge" size:12.0 origin:NSMakePoint(600.0, 100.0)];
    [text fitToTextWithinCanvasSize:NSMakeSize(800.0, 400.0)];
    XCTAssertEqualWithAccuracy(text.origin.x, 600.0, 0.01, @"Text should start where the user clicked");
    XCTAssertTrue(NSMaxX([text bounds]) <= 800.0, @"The box should stay inside the image");
}

- (void)testTextAtBottomGrowsUpwardInsteadOfClipping {
    MarkupText *text = [self textWithString:@"one\ntwo\nthree\nfour" size:24.0 origin:NSMakePoint(50.0, 380.0)];
    XCTAssertTrue([text fitToTextWithinCanvasSize:NSMakeSize(800.0, 400.0)]);
    XCTAssertTrue(NSMaxY([text bounds]) <= 400.0 + 0.5, @"Wrapped lines must stay inside the image");
}

- (void)testTextTallerThanImageReportsOverflow {
    MarkupText *text = [self textWithString:@"1\n2\n3\n4\n5\n6" size:24.0 origin:NSMakePoint(10.0, 0.0)];
    XCTAssertFalse([text fitToTextWithinCanvasSize:NSMakeSize(800.0, 60.0)], @"Text that can't fit should be reported");
}

#pragma mark - Hit-testing (#16)

- (void)testHitTestingUsesTheTextNotTheBox {
    MarkupText *text = [self textWithString:@"Hi" size:24.0 origin:NSMakePoint(100.0, 100.0)];
    text.widthIsFixed = YES;
    text.boxSize = NSMakeSize(400.0, 10.0);
    [text fitToTextWithinCanvasSize:NSMakeSize(800.0, 400.0)];
    XCTAssertTrue([text containsPoint:NSMakePoint(105.0, 110.0)], @"A point on the text hits it");
    XCTAssertFalse([text containsPoint:NSMakePoint(400.0, 110.0)], @"Empty space in a wide box should not hit the text");
}

#pragma mark - Canvas interactions (#17, #20, #21)

- (void)testClickingAwayOnlyCommits {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTextTool];

    [self clickCanvas:canvas atViewPoint:NSMakePoint(100.0, 100.0)];
    XCTAssertNotNil(canvas.activeTextView, @"A click with the text tool opens an editor");
    [canvas.activeTextView insertText:@"Hi"];

    [self clickCanvas:canvas atViewPoint:NSMakePoint(600.0, 300.0)];
    XCTAssertNil(canvas.activeTextView, @"Clicking away should only finish the text, not open another box");
    XCTAssertFalse(canvas.isCreatingTextBox);
    XCTAssertEqual(canvas.texts.count, (NSUInteger)1, @"The typed text should be committed");

    [self clickCanvas:canvas atViewPoint:NSMakePoint(600.0, 300.0)];
    XCTAssertNotNil(canvas.activeTextView, @"The next click starts a new box");
}

- (void)testEscapeKeepsNewText {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTextTool];

    [self clickCanvas:canvas atViewPoint:NSMakePoint(100.0, 100.0)];
    [canvas.activeTextView insertText:@"Keep me"];
    [canvas textView:canvas.activeTextView doCommandBySelector:@selector(cancelOperation:)];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];

    XCTAssertNil(canvas.activeTextView, @"Escape ends editing");
    XCTAssertEqual(canvas.texts.count, (NSUInteger)1, @"Escape should keep the new text, which Undo can remove");
    XCTAssertEqualObjects(canvas.texts.firstObject.text, @"Keep me");
}

- (void)testEscapeKeyEventEndsEditing {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTextTool];

    // Send a real Escape key down so it goes through the key bindings (GNUstep maps Escape to
    // complete:) and the text view's own command dispatch, as it does in the app.
    [self clickCanvas:canvas atViewPoint:NSMakePoint(100.0, 100.0)];
    [canvas.activeTextView insertText:@"Escape me"];
    NSString *escape = [NSString stringWithFormat:@"%C", (unichar)0x1b];
    NSEvent *event = [NSEvent keyEventWithType:NSKeyDown
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:[canvas.window windowNumber]
                                       context:nil
                                    characters:escape
                   charactersIgnoringModifiers:escape
                                     isARepeat:NO
                                       keyCode:9];
    [canvas.activeTextView keyDown:event];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];

    XCTAssertNil(canvas.activeTextView, @"Escape should end editing");
    XCTAssertEqual(canvas.texts.count, (NSUInteger)1, @"Escape keeps the text");
}

- (void)testResizeHandleResizesInsteadOfCommitting {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTextTool];

    [self clickCanvas:canvas atViewPoint:NSMakePoint(100.0, 100.0)];
    [canvas.activeTextView insertText:@"Resize me please"];
    XCTAssertFalse([canvas acceptsFirstResponder],
                   @"While editing, the canvas must not take first responder: GNUstep would end editing before -mouseDown:");

    NSRect handle = [canvas activeTextHandleRectInView];
    NSPoint start = NSMakePoint(NSMidX(handle), NSMidY(handle));
    CGFloat startWidth = canvas.currentTextEntry.boxSize.width;
    [canvas mouseDown:[self mouseEvent:NSLeftMouseDown atViewPoint:start in:canvas]];
    NSPoint end = NSMakePoint(start.x - 60.0, start.y + 40.0);
    [canvas mouseDragged:[self mouseEvent:NSLeftMouseDragged atViewPoint:end in:canvas]];
    [canvas mouseUp:[self mouseEvent:NSLeftMouseUp atViewPoint:end in:canvas]];

    XCTAssertNotNil(canvas.activeTextView, @"Dragging the handle keeps the editor open");
    XCTAssertTrue(canvas.currentTextEntry.widthIsFixed, @"The handle sets a fixed wrap width");
    XCTAssertEqualWithAccuracy(canvas.currentTextEntry.boxSize.width, startWidth - 60.0, 1.0, @"The width follows the drag");
    XCTAssertEqual(canvas.texts.count, (NSUInteger)0, @"Nothing should be committed by the resize");
}

@end
