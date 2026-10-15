/*
 * StepToolProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The numbered step tool (v0.2.0, #221).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "MarkupText.h"
#import "STThemeUtilities.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (StepTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
- (void)textOptionsBarDidTogglePointer:(id)bar;
- (void)copy:(id)sender;
- (ScreenshotCanvasTool)toolbarToolForSegmentIndex:(NSInteger)index;
- (NSInteger)toolbarSegmentIndexForTool:(ScreenshotCanvasTool)tool;
@end

@interface ScreenshotCanvasView (StepTesting)
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

@interface StepToolProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation StepToolProbeTests

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

#pragma mark - Step tool

- (MarkupStroke *)placeStepIn:(ScreenshotCanvasView *)canvas at:(NSPoint)point {
    [self drag:canvas from:point to:point flags:0];
    return canvas.strokes.lastObject;
}

- (NSArray<NSNumber *> *)stepNumbersIn:(ScreenshotCanvasView *)canvas {
    NSMutableArray<NSNumber *> *numbers = [[NSMutableArray alloc] init];
    for (MarkupStroke *stroke in canvas.strokes) {
        if (stroke.type == MarkupStrokeTypeStep) {
            [numbers addObject:@(stroke.number)];
        }
    }
    return numbers;
}

- (void)testClicksPlaceNumberedSteps {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolStep];
    MarkupStroke *first = [self placeStepIn:canvas at:NSMakePoint(100.0, 100.0)];
    [self placeStepIn:canvas at:NSMakePoint(200.0, 100.0)];
    [self placeStepIn:canvas at:NSMakePoint(300.0, 100.0)];
    XCTAssertEqualObjects([self stepNumbersIn:canvas], (@[@1, @2, @3]), @"Each click the next number");
    XCTAssertEqual(first.type, MarkupStrokeTypeStep);
    XCTAssertEqualObjects([first.color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]],
                          [[NSColor blueColor] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]], @"In the pen's colour");
    XCTAssertEqualWithAccuracy([first stepDiameter], 30.0, 0.01, @"Sized by the pen's width (4 here)");

    // After deleting one, the next is one past the highest left.
    [canvas.strokes removeObjectAtIndex:1];
    [self placeStepIn:canvas at:NSMakePoint(400.0, 100.0)];
    XCTAssertEqualObjects([self stepNumbersIn:canvas], (@[@1, @3, @4]));
}

- (void)testStepExportsItsDiscRingAndNumber {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolStep];
    NSImage *black = [[NSImage alloc] initWithSize:NSMakeSize(600.0, 300.0)];
    [black lockFocus];
    [[NSColor blackColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 600.0, 300.0));
    [black unlockFocus];
    [canvas loadImage:black];
    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;
    [self placeStepIn:canvas at:NSMakePoint(200.0, 150.0)];
    NSBitmapImageRep *rep = [self exportOf:canvas];
    BOOL (^blue)(NSColor *) = ^BOOL(NSColor *p) { return p.blueComponent > 0.7 && p.redComponent < 0.4 && p.greenComponent < 0.4; };
    BOOL (^white)(NSColor *) = ^BOOL(NSColor *p) { return p.redComponent > 0.85 && p.greenComponent > 0.85 && p.blueComponent > 0.85; };
    XCTAssertGreaterThan([self countIn:rep rect:NSMakeRect(187.0, 137.0, 26.0, 26.0) matching:blue], 150, @"The disc in the pen's colour");
    XCTAssertGreaterThan([self countIn:rep rect:NSMakeRect(194.0, 142.0, 12.0, 16.0) matching:white], 4, @"...with its number in white");
    XCTAssertGreaterThan([self countIn:rep rect:NSMakeRect(184.0, 149.0, 3.0, 2.0) matching:white], 0, @"...and a white ring round it");
}

- (void)testStepShortcutPlaceAndProjectFile {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolSelect];
    NSString *n = @"n";
    [canvas keyDown:[NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                                 windowNumber:[canvas.window windowNumber] context:nil characters:n
                  charactersIgnoringModifiers:n isARepeat:NO keyCode:0]];
    XCTAssertEqual(canvas.activeTool, ScreenshotCanvasToolStep, @"N selects the step tool");
    // Select, Highlighter, Pen, Arrow, Rectangle, Text, Step, … (#221).
    XCTAssertEqual([_appDelegate toolbarSegmentIndexForTool:ScreenshotCanvasToolStep], 6);
    XCTAssertEqual([_appDelegate toolbarToolForSegmentIndex:6], ScreenshotCanvasToolStep);

    MarkupStroke *step = [[MarkupStroke alloc] initWithType:MarkupStrokeTypeStep color:[NSColor redColor] lineWidth:3.0];
    [step addPoint:NSMakePoint(42.0, 24.0)];
    step.number = 7;
    MarkupStroke *copy = [MarkupStroke strokeWithProjectRepresentation:[step projectRepresentation]];
    XCTAssertEqual(copy.type, MarkupStrokeTypeStep);
    XCTAssertEqual(copy.number, 7, @"The number survives a project file");
    XCTAssertEqual([copy points].count, (NSUInteger)1);
    XCTAssertEqual([[step copy] number], 7, @"...and a copy (undo snapshots)");
}

- (void)testStepIsHitAndErasedOnItsDisc {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolStep];
    MarkupStroke *step = [self placeStepIn:canvas at:NSMakePoint(200.0, 150.0)];
    XCTAssertTrue([step containsPoint:NSMakePoint(208.0, 150.0) tolerance:1.0], @"On the disc");
    XCTAssertFalse([step containsPoint:NSMakePoint(240.0, 150.0) tolerance:1.0], @"Not beside it");
    canvas.activeTool = ScreenshotCanvasToolEraser;
    [self drag:canvas from:NSMakePoint(205.0, 152.0) to:NSMakePoint(206.0, 152.0) flags:0];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)0, @"The eraser removes it");
}

@end
