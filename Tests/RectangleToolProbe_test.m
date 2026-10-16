/*
 * RectangleToolProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The rectangle tool (v0.2.0, #221).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "MarkupText.h"
#import "STThemeUtilities.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (RectangleTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
- (void)textOptionsBarDidTogglePointer:(id)bar;
- (void)copy:(id)sender;
- (ScreenshotCanvasTool)toolbarToolForSegmentIndex:(NSInteger)index;
- (NSInteger)toolbarSegmentIndexForTool:(ScreenshotCanvasTool)tool;
@end

@interface ScreenshotCanvasView (RectangleTesting)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@property (nonatomic, strong) NSMutableArray<MarkupText *> *texts;
@property (nonatomic, strong) NSTextView *activeTextView;
- (void)beginTextEntryWithImageRect:(NSRect)imageRect existingText:(MarkupText *)existingText;
- (void)commitActiveTextIfNeeded;
- (NSRect)activePointerHandleRectInView;
- (BOOL)toggleActiveTextPointer;
- (MarkupText *)activeTextEntry;
- (void)selectAnnotation:(id)annotation extending:(BOOL)extending;
- (void)getSelectionHandleRects:(NSRect *)rects forAnnotation:(id)annotation;
- (NSArray *)selectedAnnotationObjects;
@end

@interface RectangleToolProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation RectangleToolProbeTests

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

- (NSImage *)whiteImage {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600.0, 300.0)];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 600.0, 300.0));
    [image unlockFocus];
    return image;
}

- (ScreenshotCanvasView *)canvasWithTool:(ScreenshotCanvasTool)tool {
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self whiteImage]];
    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;
    canvas.penColor = [NSColor blueColor];
    canvas.penLineWidth = 4.0;
    canvas.textFont = [NSFont fontWithName:@"DejaVuSans" size:24.0] ?: [NSFont systemFontOfSize:24.0];
    canvas.textSizePreset = STTextSizePresetExact;
    canvas.textStyle = MarkupTextStylePlain;
    canvas.activeTool = tool;
    return canvas;
}

- (NSEvent *)mouse:(NSEventType)type at:(NSPoint)point canvas:(ScreenshotCanvasView *)canvas flags:(NSUInteger)flags {
    return [NSEvent mouseEventWithType:type location:[canvas convertPoint:point toView:nil] modifierFlags:flags
                             timestamp:0 windowNumber:[canvas.window windowNumber] context:nil
                           eventNumber:0 clickCount:1 pressure:1.0];
}

- (void)drag:(ScreenshotCanvasView *)canvas from:(NSPoint)a to:(NSPoint)b flags:(NSUInteger)flags {
    [canvas mouseDown:[self mouse:NSLeftMouseDown at:a canvas:canvas flags:flags]];
    [canvas mouseDragged:[self mouse:NSLeftMouseDragged at:b canvas:canvas flags:flags]];
    [canvas mouseUp:[self mouse:NSLeftMouseUp at:b canvas:canvas flags:flags]];
}

- (NSBitmapImageRep *)exportOf:(ScreenshotCanvasView *)canvas {
    return [NSBitmapImageRep imageRepWithData:[[canvas flattenedImage] TIFFRepresentation]];
}

- (NSInteger)countIn:(NSBitmapImageRep *)rep rect:(NSRect)rect matching:(BOOL (^)(NSColor *))predicate {
    NSInteger count = 0;
    for (NSInteger y = MAX(0, (NSInteger)NSMinY(rect)); y < MIN(rep.pixelsHigh, (NSInteger)NSMaxY(rect)); y++) {
        for (NSInteger x = MAX(0, (NSInteger)NSMinX(rect)); x < MIN(rep.pixelsWide, (NSInteger)NSMaxX(rect)); x++) {
            NSColor *p = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
            if (p && predicate(p)) {
                count++;
            }
        }
    }
    return count;
}

#pragma mark - Rectangle tool

- (void)testRectangleToolDrawsWithThePensSettings {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolRectangle];
    [self drag:canvas from:NSMakePoint(300.0, 200.0) to:NSMakePoint(100.0, 100.0) flags:0];

    XCTAssertEqual(canvas.strokes.count, (NSUInteger)1);
    MarkupStroke *rectangle = canvas.strokes.firstObject;
    XCTAssertEqual(rectangle.type, MarkupStrokeTypeRectangle);
    XCTAssertTrue(NSEqualRects([rectangle shapeRect], NSMakeRect(100.0, 100.0, 200.0, 100.0)),
                  @"Corner to corner, in either direction: %@", NSStringFromRect([rectangle shapeRect]));
    XCTAssertEqualWithAccuracy(rectangle.lineWidth, 4.0, 0.01, @"Rectangles use the pen width");
    XCTAssertEqualObjects([rectangle.color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]],
                          [[NSColor blueColor] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]], @"...and the pen colour");
}

- (void)testShiftMakesASquareAndStrayClicksAreIgnored {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolRectangle];
    [self drag:canvas from:NSMakePoint(100.0, 100.0) to:NSMakePoint(250.0, 160.0) flags:NSEventModifierFlagShift];
    NSRect rect = [canvas.strokes.firstObject shapeRect];
    XCTAssertEqualWithAccuracy(NSWidth(rect), NSHeight(rect), 0.01, @"Shift makes it a square: %@", NSStringFromRect(rect));
    XCTAssertEqualWithAccuracy(NSWidth(rect), 150.0, 0.01, @"...as big as the longer side");

    [self drag:canvas from:NSMakePoint(400.0, 100.0) to:NSMakePoint(401.0, 101.0) flags:0];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)1, @"A click without a drag draws nothing");
}

- (void)testRectangleExportsItsOutlineOnly {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolRectangle];
    [self drag:canvas from:NSMakePoint(100.0, 100.0) to:NSMakePoint(300.0, 200.0) flags:0];
    NSBitmapImageRep *rep = [self exportOf:canvas];
    BOOL (^blue)(NSColor *) = ^BOOL(NSColor *p) { return p.blueComponent > 0.7 && p.redComponent < 0.4; };
    XCTAssertGreaterThan([self countIn:rep rect:NSMakeRect(150.0, 95.0, 1.0, 10.0) matching:blue], 2, @"The top edge is drawn");
    XCTAssertGreaterThan([self countIn:rep rect:NSMakeRect(95.0, 150.0, 10.0, 1.0) matching:blue], 2, @"...and the left");
    XCTAssertEqual([self countIn:rep rect:NSMakeRect(150.0, 130.0, 100.0, 40.0) matching:blue], 0, @"It's an outline: the inside stays the image");
}

- (void)testRectangleShortcutAndToolbarPlace {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolSelect];
    NSString *r = @"r";
    [canvas keyDown:[NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                                 windowNumber:[canvas.window windowNumber] context:nil characters:r
                  charactersIgnoringModifiers:r isARepeat:NO keyCode:0]];
    XCTAssertEqual(canvas.activeTool, ScreenshotCanvasToolRectangle, @"R selects the rectangle tool");
    // Select, Highlighter, Pen, Arrow, Rectangle, Text, Eraser (#221).
    XCTAssertEqual([_appDelegate toolbarSegmentIndexForTool:ScreenshotCanvasToolRectangle], 4);
    XCTAssertEqual([_appDelegate toolbarToolForSegmentIndex:4], ScreenshotCanvasToolRectangle);
    XCTAssertEqual([_appDelegate toolbarToolForSegmentIndex:5], ScreenshotCanvasToolText);
    XCTAssertEqual([_appDelegate toolbarToolForSegmentIndex:6], ScreenshotCanvasToolEraser);
}

- (void)testRectangleSurvivesAProjectFile {
    MarkupStroke *rectangle = [[MarkupStroke alloc] initWithType:MarkupStrokeTypeRectangle color:[NSColor redColor] lineWidth:6.0];
    [rectangle setStartPoint:NSMakePoint(40.0, 30.0) endPoint:NSMakePoint(10.0, 80.0)];
    MarkupStroke *copy = [MarkupStroke strokeWithProjectRepresentation:[rectangle projectRepresentation]];
    XCTAssertNotNil(copy);
    XCTAssertEqual(copy.type, MarkupStrokeTypeRectangle);
    XCTAssertTrue(NSEqualRects([copy shapeRect], NSMakeRect(10.0, 30.0, 30.0, 50.0)), @"%@", NSStringFromRect([copy shapeRect]));
    XCTAssertEqualWithAccuracy(copy.lineWidth, 6.0, 0.01);
}

- (void)testEraserAndHitTestingUseTheOutline {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolRectangle];
    [self drag:canvas from:NSMakePoint(100.0, 100.0) to:NSMakePoint(300.0, 200.0) flags:0];
    MarkupStroke *rectangle = canvas.strokes.firstObject;
    XCTAssertTrue([rectangle containsPoint:NSMakePoint(200.0, 101.0) tolerance:2.0], @"On an edge");
    XCTAssertFalse([rectangle containsPoint:NSMakePoint(200.0, 150.0) tolerance:2.0], @"Not in the middle");

    canvas.activeTool = ScreenshotCanvasToolEraser;
    [self drag:canvas from:NSMakePoint(200.0, 150.0) to:NSMakePoint(201.0, 150.0) flags:0];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)1, @"Erasing inside misses it");
    [self drag:canvas from:NSMakePoint(200.0, 100.0) to:NSMakePoint(201.0, 100.0) flags:0];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)0, @"Erasing on its edge removes it");
}

/// A selected rectangle resizes by a corner handle, the opposite corner staying put, and Undo puts
/// it back.
- (void)testResizeByACornerHandleAndUndo {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolRectangle];
    [self drag:canvas from:NSMakePoint(100.0, 100.0) to:NSMakePoint(300.0, 200.0) flags:0];
    MarkupStroke *rectangle = canvas.strokes.firstObject;
    // Each gesture its own undo group, as each is its own event in the app.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    canvas.activeTool = ScreenshotCanvasToolSelect;
    [canvas selectAnnotation:rectangle extending:NO];

    NSRect handles[4];
    [canvas getSelectionHandleRects:handles forAnnotation:rectangle];
    NSPoint grab = NSMakePoint(NSMidX(handles[3]), NSMidY(handles[3])); // bottom right
    [self drag:canvas from:grab to:NSMakePoint(grab.x + 80.0, grab.y + 40.0) flags:0];
    XCTAssertTrue(NSEqualRects([rectangle shapeRect], NSMakeRect(100.0, 100.0, 280.0, 140.0)),
                  @"The top left stays; the bottom right follows the pointer: %@", NSStringFromRect([rectangle shapeRect]));
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)1, @"Resizing draws nothing new");
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];

    [[canvas undoManager] undo];
    XCTAssertTrue(NSEqualRects([canvas.strokes.firstObject shapeRect], NSMakeRect(100.0, 100.0, 200.0, 100.0)),
                  @"Undo puts it back: %@", NSStringFromRect([canvas.strokes.firstObject shapeRect]));
}

@end
