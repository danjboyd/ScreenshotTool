/*
 * ArrowCalloutProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The arrow tool and callout pointers (#33).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "MarkupText.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (ArrowCalloutTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
@end

@interface ScreenshotCanvasView (ArrowCalloutTesting)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@property (nonatomic, strong) NSMutableArray<MarkupText *> *texts;
@property (nonatomic, strong) NSTextView *activeTextView;
- (void)beginTextEntryWithImageRect:(NSRect)imageRect existingText:(MarkupText *)existingText;
- (void)commitActiveTextIfNeeded;
- (NSRect)activePointerHandleRectInView;
@end

@interface ArrowCalloutProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation ArrowCalloutProbeTests

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

#pragma mark - Arrow tool

- (void)testArrowToolDrawsAStraightArrowWithThePensSettings {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolArrow];
    [self drag:canvas from:NSMakePoint(100.0, 100.0) to:NSMakePoint(300.0, 200.0) flags:0];

    XCTAssertEqual(canvas.strokes.count, (NSUInteger)1);
    MarkupStroke *arrow = canvas.strokes.firstObject;
    XCTAssertEqual(arrow.type, MarkupStrokeTypeArrow);
    XCTAssertEqual([arrow points].count, (NSUInteger)2, @"An arrow is a start and an end");
    NSPoint end = [[arrow points].lastObject pointValue];
    XCTAssertEqualWithAccuracy(end.x, 300.0, 0.01);
    XCTAssertEqualWithAccuracy(end.y, 200.0, 0.01);
    XCTAssertEqualWithAccuracy(arrow.lineWidth, 4.0, 0.01, @"Arrows use the pen width");
    XCTAssertEqualObjects([arrow.color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]],
                          [[NSColor blueColor] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]], @"...and the pen colour");
}

- (void)testShiftSnapsTo45DegreesAndStrayClicksAreIgnored {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolArrow];
    [self drag:canvas from:NSMakePoint(100.0, 100.0) to:NSMakePoint(300.0, 115.0) flags:NSEventModifierFlagShift];
    NSPoint end = [[canvas.strokes.firstObject points].lastObject pointValue];
    XCTAssertEqualWithAccuracy(end.y, 100.0, 0.5, @"Shift snaps a nearly flat arrow to horizontal");

    [self drag:canvas from:NSMakePoint(400.0, 100.0) to:NSMakePoint(401.0, 101.0) flags:0];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)1, @"A click without a drag doesn't leave a dot-sized arrow");
}

- (void)testArrowExportsWithItsHead {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolArrow];
    [self drag:canvas from:NSMakePoint(100.0, 150.0) to:NSMakePoint(400.0, 150.0) flags:0];
    NSBitmapImageRep *rep = [self exportOf:canvas];
    BOOL (^blue)(NSColor *) = ^BOOL(NSColor *p) { return p.blueComponent > 0.7 && p.redComponent < 0.4; };

    // The head is much taller than the 4pt shaft.
    NSInteger shaftColumn = [self countIn:rep rect:NSMakeRect(200.0, 120.0, 1.0, 60.0) matching:blue];
    NSInteger headColumn = [self countIn:rep rect:NSMakeRect(390.0, 120.0, 1.0, 60.0) matching:blue];
    XCTAssertTrue(shaftColumn >= 3 && shaftColumn <= 6, @"Shaft is about the pen width (%ld)", (long)shaftColumn);
    XCTAssertTrue(headColumn > shaftColumn + 4, @"The arrowhead is exported (%ld vs %ld)", (long)headColumn, (long)shaftColumn);
}

- (void)testArrowShortcut {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolSelect];
    NSString *a = @"a";
    [canvas keyDown:[NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                                 windowNumber:[canvas.window windowNumber] context:nil characters:a
                  charactersIgnoringModifiers:a isARepeat:NO keyCode:0]];
    XCTAssertEqual(canvas.activeTool, ScreenshotCanvasToolArrow, @"A selects the arrow tool");
}

#pragma mark - Callouts

- (MarkupText *)calloutWithStyle:(MarkupTextStyle)style {
    NSFont *font = [NSFont fontWithName:@"DejaVuSans" size:24.0] ?: [NSFont systemFontOfSize:24.0];
    MarkupText *text = [[MarkupText alloc] initWithText:@"Look" font:font color:[NSColor redColor]
                                                 origin:NSMakePoint(300.0, 60.0) boxSize:NSMakeSize(1.0, 1.0)];
    text.style = style;
    [text fitToTextWithinCanvasSize:NSMakeSize(600.0, 300.0)];
    text.hasPointer = YES;
    text.pointerTarget = NSMakePoint(150.0, 230.0);
    return text;
}

- (void)testCalloutBoundsHitTestingAndMoving {
    MarkupText *callout = [self calloutWithStyle:MarkupTextStyleBackground];
    XCTAssertTrue(NSPointInRect(NSMakePoint(150.0, 230.0), [callout decoratedBounds]), @"Bounds include the pointer's target");
    XCTAssertTrue([callout containsPoint:NSMakePoint(152.0, 228.0)], @"Clicking the pointer hits the callout");
    XCTAssertFalse([callout containsPoint:NSMakePoint(160.0, 80.0)], @"Empty space beside the pointer isn't hit");

    [callout translateByOffset:NSMakePoint(-20.0, -10.0)];
    XCTAssertEqualWithAccuracy(callout.pointerTarget.x, 170.0, 0.01, @"The pointer moves with its label");
    XCTAssertEqualWithAccuracy(callout.pointerTarget.y, 240.0, 0.01);
    MarkupText *copy = [callout copy];
    XCTAssertTrue(copy.hasPointer && NSEqualPoints(copy.pointerTarget, callout.pointerTarget), @"Undo snapshots keep the pointer");
}

- (void)testCalloutPointerIsExported {
    XCTSkipIf(_shouldSkip, @"No window server");
    for (NSNumber *style in @[@(MarkupTextStyleBackground), @(MarkupTextStylePlain)]) {
        ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolSelect];
        if (!canvas.texts) {
            canvas.texts = [[NSMutableArray alloc] init];
        }
        [canvas.texts addObject:[self calloutWithStyle:(MarkupTextStyle)style.integerValue]];
        NSBitmapImageRep *rep = [self exportOf:canvas];
        NSInteger nearTarget = [self countIn:rep rect:NSMakeRect(145.0, 215.0, 20.0, 20.0) matching:^BOOL(NSColor *p) {
            return p.redComponent > 0.7 && p.greenComponent < 0.3;
        }];
        XCTAssertTrue(nearTarget > 10, @"Style %@: the pointer reaches its target in the export (%ld)", style, (long)nearTarget);
    }
}

- (void)testPointerToggleAndDragWhileEditing {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolText];
    [canvas beginTextEntryWithImageRect:NSMakeRect(300.0, 60.0, 1.0, 1.0) existingText:nil];
    [canvas.activeTextView insertText:@"Callout"];

    XCTAssertTrue([canvas toggleActiveTextPointer]);
    MarkupText *entry = [canvas activeTextEntry];
    XCTAssertTrue(entry.hasPointer);
    XCTAssertFalse(NSPointInRect(entry.pointerTarget, [entry decoratedTextBounds]), @"A new pointer starts outside the label");

    NSRect handle = [canvas activePointerHandleRectInView];
    NSPoint start = NSMakePoint(NSMidX(handle), NSMidY(handle));
    [canvas mouseDown:[self mouse:NSLeftMouseDown at:start canvas:canvas flags:0]];
    [canvas mouseDragged:[self mouse:NSLeftMouseDragged at:NSMakePoint(80.0, 250.0) canvas:canvas flags:0]];
    [canvas mouseUp:[self mouse:NSLeftMouseUp at:NSMakePoint(80.0, 250.0) canvas:canvas flags:0]];
    XCTAssertNotNil(canvas.activeTextView, @"Aiming the pointer keeps the label open");
    XCTAssertEqualWithAccuracy(entry.pointerTarget.x, 80.0, 0.01);
    XCTAssertEqualWithAccuracy(entry.pointerTarget.y, 250.0, 0.01, @"Dragging the handle aims the pointer");

    [canvas commitActiveTextIfNeeded];
    XCTAssertTrue(canvas.texts.firstObject.hasPointer, @"The committed label keeps its pointer");
}

@end
