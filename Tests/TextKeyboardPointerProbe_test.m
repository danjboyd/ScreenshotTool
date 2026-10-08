/*
 * TextKeyboardPointerProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Text keyboard conventions (#28), pointer affordances (#29) and undoable emptying of a label (#30).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupText.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (TextKeyboardPointerTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
@end

@interface ScreenshotCanvasView (TextKeyboardPointerTesting)
@property (nonatomic, strong) NSTextView *activeTextView;
@property (nonatomic, strong) MarkupText *currentTextEntry;
@property (nonatomic, strong) NSMutableArray<MarkupText *> *texts;
@property (nonatomic, assign) BOOL mouseInsideCanvas;
@property (nonatomic, weak) id hoverAnnotation;
- (void)updateHoverAtViewPoint:(NSPoint)viewPoint;
- (NSCursor *)contextCursorAtViewPoint:(NSPoint)viewPoint hover:(id)hover;
- (NSRect)activeTextHandleRectInView;
- (BOOL)isAnnotationSelected:(id)annotation;
- (void)beginTextEntryWithImageRect:(NSRect)imageRect existingText:(MarkupText *)existingText;
- (void)commitActiveTextIfNeeded;
@end

@interface TextKeyboardPointerProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation TextKeyboardPointerProbeTests

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

- (ScreenshotCanvasView *)canvasWithTool:(ScreenshotCanvasTool)tool {
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600.0, 300.0)];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 600.0, 300.0));
    [image unlockFocus];
    [canvas loadImage:image];
    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;
    canvas.textFont = [NSFont fontWithName:@"DejaVuSans" size:24.0] ?: [NSFont systemFontOfSize:24.0];
    canvas.textSizePreset = STTextSizePresetExact;
    canvas.activeTool = tool;
    return canvas;
}

- (MarkupText *)addLabel:(NSString *)string to:(ScreenshotCanvasView *)canvas at:(NSPoint)origin {
    MarkupText *text = [[MarkupText alloc] initWithText:string font:canvas.textFont color:[NSColor redColor]
                                                 origin:origin boxSize:NSMakeSize(1.0, 1.0)];
    [text fitToTextWithinCanvasSize:NSMakeSize(600.0, 300.0)];
    if (!canvas.texts) {
        canvas.texts = [[NSMutableArray alloc] init];
    }
    [canvas.texts addObject:text];
    return text;
}

- (void)spinRunLoop {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

/// Finishing commits on a later turn of the run loop: waits for it, up to 2s, rather than a fixed
/// time a slow CI runner can overrun.
- (void)waitForEditingToEndIn:(ScreenshotCanvasView *)canvas {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (canvas.activeTextView && [until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}

- (NSEvent *)keyEvent:(unichar)key flags:(NSUInteger)flags canvas:(ScreenshotCanvasView *)canvas {
    NSString *characters = [NSString stringWithCharacters:&key length:1];
    return [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                        windowNumber:[canvas.window windowNumber] context:nil
                          characters:characters charactersIgnoringModifiers:characters
                           isARepeat:NO keyCode:0];
}

#pragma mark - #30

- (void)testEmptyingALabelIsAnUndoableDelete {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolText];
    MarkupText *label = [self addLabel:@"Keep" to:canvas at:NSMakePoint(50.0, 50.0)];

    [canvas beginTextEntryWithImageRect:[label bounds] existingText:label];
    XCTAssertNotNil(canvas.activeTextView);
    [canvas.activeTextView setString:@""];
    [canvas commitActiveTextIfNeeded];
    XCTAssertEqual(canvas.texts.count, (NSUInteger)0, @"Emptying a label and committing removes it");

    [[canvas undoManager] undo];
    XCTAssertEqual(canvas.texts.count, (NSUInteger)1, @"Undo brings the label back");
    XCTAssertEqualObjects(canvas.texts.firstObject.text, @"Keep");
}

#pragma mark - #28

- (void)testControlReturnFinishesAndReturnAddsALine {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolText];
    [canvas beginTextEntryWithImageRect:NSMakeRect(50.0, 50.0, 1.0, 1.0) existingText:nil];
    [canvas.activeTextView insertText:@"First"];

    [canvas.activeTextView keyDown:[self keyEvent:NSCarriageReturnCharacter flags:0 canvas:canvas]];
    [self spinRunLoop];
    XCTAssertNotNil(canvas.activeTextView, @"Plain Return keeps editing");
    XCTAssertTrue([canvas.activeTextView.string containsString:@"\n"], @"Plain Return adds a new line");

    [canvas.activeTextView insertText:@"Second"];
    [canvas.activeTextView keyDown:[self keyEvent:NSCarriageReturnCharacter flags:NSEventModifierFlagControl canvas:canvas]];
    [self waitForEditingToEndIn:canvas];
    XCTAssertNil(canvas.activeTextView, @"Ctrl+Return (Control modifier) finishes editing");
    XCTAssertEqual(canvas.texts.count, (NSUInteger)1);
    XCTAssertEqualObjects(canvas.texts.firstObject.text, @"First\nSecond", @"Ctrl+Return doesn't add a line of its own");

    // Where the Ctrl key maps to GNUstep's Command modifier (and on macOS), it finishes too.
    [canvas beginTextEntryWithImageRect:NSMakeRect(50.0, 150.0, 1.0, 1.0) existingText:nil];
    [canvas.activeTextView insertText:@"Third"];
    [canvas.activeTextView keyDown:[self keyEvent:NSCarriageReturnCharacter flags:NSEventModifierFlagCommand canvas:canvas]];
    [self waitForEditingToEndIn:canvas];
    XCTAssertNil(canvas.activeTextView, @"Cmd+Return finishes editing");
    XCTAssertEqual(canvas.texts.count, (NSUInteger)2);
}

- (void)testTypingHasItsOwnUndoHistory {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolText];
    [canvas beginTextEntryWithImageRect:NSMakeRect(50.0, 50.0, 1.0, 1.0) existingText:nil];

    NSUndoManager *editing = [canvas activeTextUndoManager];
    XCTAssertNotNil(editing, @"An open box has its own undo manager");
    XCTAssertTrue(editing != [canvas undoManager], @"...separate from the canvas's");
    XCTAssertTrue([canvas.activeTextView undoManager] == editing, @"The text view records typing there");

    [canvas commitActiveTextIfNeeded];
    XCTAssertNil([canvas activeTextUndoManager], @"No editing history is left once the box closes");
}

- (void)testToolShortcutsSwitchToolsOnlyWithoutModifiers {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolSelect];

    [canvas keyDown:[self keyEvent:'t' flags:0 canvas:canvas]];
    XCTAssertEqual(canvas.activeTool, ScreenshotCanvasToolText, @"T selects the text tool");
    [canvas keyDown:[self keyEvent:'p' flags:0 canvas:canvas]];
    XCTAssertEqual(canvas.activeTool, ScreenshotCanvasToolPen, @"P selects the pen");
    [canvas keyDown:[self keyEvent:'e' flags:NSEventModifierFlagControl canvas:canvas]];
    XCTAssertEqual(canvas.activeTool, ScreenshotCanvasToolPen, @"Ctrl+E is not a tool shortcut");
    [canvas keyDown:[self keyEvent:'s' flags:0 canvas:canvas]];
    XCTAssertEqual(canvas.activeTool, ScreenshotCanvasToolSelect, @"S selects the Select tool");
}

#pragma mark - #29

- (void)testCursorsAndHoverSayWhatAClickWillDo {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolText];
    MarkupText *label = [self addLabel:@"Hover" to:canvas at:NSMakePoint(100.0, 100.0)];
    NSPoint onLabel = NSMakePoint(NSMidX([label textBounds]), NSMidY([label textBounds]));
    NSPoint empty = NSMakePoint(450.0, 250.0);
    canvas.mouseInsideCanvas = YES;

    [canvas updateHoverAtViewPoint:onLabel];
    XCTAssertTrue(canvas.hoverAnnotation == label, @"Text under the pointer is the hover target");
    XCTAssertFalse([canvas isAnnotationSelected:label],
                   @"With nothing selected the hover target isn't treated as selected (so its outline draws)");
    XCTAssertEqual([canvas contextCursorAtViewPoint:onLabel hover:label], [NSCursor IBeamCursor], @"I-beam over text");
    XCTAssertEqual([canvas contextCursorAtViewPoint:empty hover:nil], [NSCursor crosshairCursor], @"Crosshair where a click creates a box");
    [canvas updateHoverAtViewPoint:empty];
    XCTAssertNil(canvas.hoverAnnotation);

    [canvas beginTextEntryWithImageRect:NSMakeRect(300.0, 50.0, 1.0, 1.0) existingText:nil];
    [canvas.activeTextView insertText:@"Edit"];
    NSRect handle = [canvas activeTextHandleRectInView];
    NSPoint nearHandle = NSMakePoint(NSMaxX(handle) + 2.0, NSMaxY(handle) + 2.0);
    XCTAssertEqual([canvas contextCursorAtViewPoint:nearHandle hover:nil], [NSCursor resizeLeftRightCursor],
                   @"The handle shows a resize cursor, with a little extra room around it");
    [canvas commitActiveTextIfNeeded];

    canvas.activeTool = ScreenshotCanvasToolSelect;
    XCTAssertEqual([canvas contextCursorAtViewPoint:onLabel hover:label], [NSCursor openHandCursor],
                   @"With the Select tool, annotations show a move cursor");
}

@end
