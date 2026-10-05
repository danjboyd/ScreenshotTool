/*
 * ObjectSelectionProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Selecting, moving, nudging and deleting annotations (#25) and image-relative text size (#27).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "MarkupText.h"
#import "ScreenshotToolSettings.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (ObjectSelectionTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
@end

@interface ScreenshotCanvasView (ObjectSelectionTesting)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@property (nonatomic, strong) NSMutableArray<MarkupText *> *texts;
@property (nonatomic, strong) NSTextView *activeTextView;
@property (nonatomic, strong) MarkupText *currentTextEntry;
@property (nonatomic, assign) BOOL hasSelectionRect;
- (NSArray *)selectedAnnotationObjects;
@end

@interface ObjectSelectionProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation ObjectSelectionProbeTests

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

- (NSImage *)imageOfSize:(NSSize)size {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    [image unlockFocus];
    return image;
}

/// A canvas at 100% with one horizontal pen stroke (y = 50) and one text label (around y = 150).
- (ScreenshotCanvasView *)canvasWithStrokeAndText {
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self imageOfSize:NSMakeSize(600.0, 300.0)]];
    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;
    canvas.activeTool = ScreenshotCanvasToolSelect;

    MarkupStroke *stroke = [[MarkupStroke alloc] initWithType:MarkupStrokeTypePen color:[NSColor redColor] lineWidth:6.0];
    [stroke addPoint:NSMakePoint(50.0, 50.0)];
    [stroke addPoint:NSMakePoint(250.0, 50.0)];
    if (!canvas.strokes) {
        canvas.strokes = [[NSMutableArray alloc] init];
    }
    [canvas.strokes addObject:stroke];

    NSFont *font = [NSFont fontWithName:@"DejaVuSans" size:24.0] ?: [NSFont systemFontOfSize:24.0];
    MarkupText *text = [[MarkupText alloc] initWithText:@"Label" font:font color:[NSColor blueColor]
                                                 origin:NSMakePoint(300.0, 140.0) boxSize:NSMakeSize(1.0, 1.0)];
    [text fitToTextWithinCanvasSize:NSMakeSize(600.0, 300.0)];
    if (!canvas.texts) {
        canvas.texts = [[NSMutableArray alloc] init];
    }
    [canvas.texts addObject:text];
    return canvas;
}

- (NSEvent *)mouse:(NSEventType)type at:(NSPoint)point in:(ScreenshotCanvasView *)canvas clicks:(NSInteger)clicks flags:(NSUInteger)flags {
    return [NSEvent mouseEventWithType:type
                              location:[canvas convertPoint:point toView:nil]
                         modifierFlags:flags
                             timestamp:0
                          windowNumber:[canvas.window windowNumber]
                               context:nil
                           eventNumber:0
                            clickCount:clicks
                              pressure:1.0];
}

- (void)click:(ScreenshotCanvasView *)canvas at:(NSPoint)point flags:(NSUInteger)flags clicks:(NSInteger)clicks {
    [canvas mouseDown:[self mouse:NSLeftMouseDown at:point in:canvas clicks:clicks flags:flags]];
    [canvas mouseUp:[self mouse:NSLeftMouseUp at:point in:canvas clicks:clicks flags:flags]];
}

- (void)drag:(ScreenshotCanvasView *)canvas from:(NSPoint)start to:(NSPoint)end {
    [canvas mouseDown:[self mouse:NSLeftMouseDown at:start in:canvas clicks:1 flags:0]];
    [canvas mouseDragged:[self mouse:NSLeftMouseDragged at:end in:canvas clicks:1 flags:0]];
    [canvas mouseUp:[self mouse:NSLeftMouseUp at:end in:canvas clicks:1 flags:0]];
}

- (void)pressKey:(unichar)key flags:(NSUInteger)flags on:(ScreenshotCanvasView *)canvas {
    NSString *characters = [NSString stringWithCharacters:&key length:1];
    NSEvent *event = [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                                  windowNumber:[canvas.window windowNumber] context:nil
                                    characters:characters charactersIgnoringModifiers:characters
                                     isARepeat:NO keyCode:0];
    [canvas keyDown:event];
}

- (NSPoint)firstPointOf:(MarkupStroke *)stroke {
    return [[[stroke points] firstObject] pointValue];
}

#pragma mark - Size presets (#27)

- (void)testPresetSizesScaleWithTheImage {
    CGFloat medium1080 = STTextPointSizeForPreset(STTextSizePresetMedium, NSMakeSize(1920.0, 1080.0));
    CGFloat medium4K = STTextPointSizeForPreset(STTextSizePresetMedium, NSMakeSize(3840.0, 2160.0));
    XCTAssertEqualWithAccuracy(medium1080, 27.0, 1.0, @"Medium on a 1080p capture should be about 27pt");
    XCTAssertEqualWithAccuracy(medium4K, medium1080 * 2.0, 2.0, @"A 4K capture gets about twice the size");
    XCTAssertTrue(STTextPointSizeForPreset(STTextSizePresetSmall, NSMakeSize(1920.0, 1080.0)) < medium1080);
    XCTAssertTrue(STTextPointSizeForPreset(STTextSizePresetLarge, NSMakeSize(1920.0, 1080.0)) > medium1080);
    XCTAssertTrue(STTextPointSizeForPreset(STTextSizePresetExtraLarge, NSMakeSize(1920.0, 1080.0)) >
                  STTextPointSizeForPreset(STTextSizePresetLarge, NSMakeSize(1920.0, 1080.0)));
    XCTAssertEqualWithAccuracy(STTextPointSizeForPreset(STTextSizePresetMedium, NSMakeSize(200.0, 100.0)), 14.0, 0.01,
                               @"Small crops still get a readable minimum");
    XCTAssertEqual(STTextPointSizeForPreset(STTextSizePresetExact, NSMakeSize(1920.0, 1080.0)), 0.0);
}

- (void)testNewTextUsesThePresetForTheCurrentImage {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    canvas.textFont = [NSFont fontWithName:@"DejaVuSans" size:12.0] ?: [NSFont systemFontOfSize:12.0];

    [canvas loadImage:[self imageOfSize:NSMakeSize(1920.0, 1080.0)]];
    canvas.textSizePreset = STTextSizePresetLarge;
    XCTAssertEqualWithAccuracy([canvas effectiveTextFont].pointSize,
                               STTextPointSizeForPreset(STTextSizePresetLarge, NSMakeSize(1920.0, 1080.0)), 0.01);

    [canvas loadImage:[self imageOfSize:NSMakeSize(3840.0, 2160.0)]];
    XCTAssertEqualWithAccuracy([canvas effectiveTextFont].pointSize,
                               STTextPointSizeForPreset(STTextSizePresetLarge, NSMakeSize(3840.0, 2160.0)), 0.01,
                               @"The preset is remembered, not the point size");

    canvas.textSizePreset = STTextSizePresetExact;
    XCTAssertEqualWithAccuracy([canvas effectiveTextFont].pointSize, 12.0, 0.01, @"Exact uses the font's own size");
}

#pragma mark - Object selection (#25)

- (void)testClickSelectsAndDragMovesWithUndo {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithStrokeAndText];
    MarkupStroke *stroke = canvas.strokes.firstObject;

    [self click:canvas at:NSMakePoint(150.0, 51.0) flags:0 clicks:1];
    XCTAssertEqual([canvas selectedAnnotationObjects].count, (NSUInteger)1);
    XCTAssertTrue([canvas selectedAnnotationObjects].firstObject == stroke, @"Clicking a stroke selects it");
    XCTAssertFalse(canvas.hasSelectionRect, @"Picking an object doesn't start a region selection");

    [self drag:canvas from:NSMakePoint(150.0, 51.0) to:NSMakePoint(170.0, 91.0)];
    NSPoint moved = [self firstPointOf:canvas.strokes.firstObject];
    XCTAssertEqualWithAccuracy(moved.x, 70.0, 0.01);
    XCTAssertEqualWithAccuracy(moved.y, 90.0, 0.01, @"Dragging a selected stroke moves it");

    [[canvas undoManager] undo];
    NSPoint restored = [self firstPointOf:canvas.strokes.firstObject];
    XCTAssertEqualWithAccuracy(restored.x, 50.0, 0.01);
    XCTAssertEqualWithAccuracy(restored.y, 50.0, 0.01, @"Undo puts the stroke back in one step");
}

- (void)testShiftClickExtendsAndDeleteRemovesWithUndo {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithStrokeAndText];
    NSPoint onText = NSMakePoint(NSMidX([canvas.texts.firstObject textBounds]), NSMidY([canvas.texts.firstObject textBounds]));

    [self click:canvas at:NSMakePoint(150.0, 51.0) flags:0 clicks:1];
    [self click:canvas at:onText flags:NSEventModifierFlagShift clicks:1];
    XCTAssertEqual([canvas selectedAnnotationObjects].count, (NSUInteger)2, @"Shift-click adds to the selection");

    [self pressKey:NSDeleteCharacter flags:0 on:canvas];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)0);
    XCTAssertEqual(canvas.texts.count, (NSUInteger)0, @"Delete removes every selected annotation");

    [[canvas undoManager] undo];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)1);
    XCTAssertEqual(canvas.texts.count, (NSUInteger)1, @"Undo restores them");
}

- (void)testArrowKeysNudgeSelection {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithStrokeAndText];
    MarkupText *text = canvas.texts.firstObject;
    NSPoint onText = NSMakePoint(NSMidX([text textBounds]), NSMidY([text textBounds]));
    NSPoint start = text.origin;

    [self click:canvas at:onText flags:0 clicks:1];
    [self pressKey:NSRightArrowFunctionKey flags:0 on:canvas];
    [self pressKey:NSDownArrowFunctionKey flags:NSEventModifierFlagShift on:canvas];
    XCTAssertEqualWithAccuracy(canvas.texts.firstObject.origin.x, start.x + 1.0, 0.01, @"Arrow nudges 1pt");
    XCTAssertEqualWithAccuracy(canvas.texts.firstObject.origin.y, start.y + 10.0, 0.01, @"Shift-arrow nudges 10pt");
}

- (void)testDoubleClickEditsTextAndEmptyDragMakesRegionSelection {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithStrokeAndText];
    MarkupText *text = canvas.texts.firstObject;
    NSPoint onText = NSMakePoint(NSMidX([text textBounds]), NSMidY([text textBounds]));

    [self click:canvas at:onText flags:0 clicks:2];
    XCTAssertNotNil(canvas.activeTextView, @"Double-clicking text with the Select tool edits it");
    XCTAssertTrue(canvas.currentTextEntry == text);

    // Clicking away commits the edit; a drag in empty space still makes a crop/copy selection.
    [self drag:canvas from:NSMakePoint(400.0, 220.0) to:NSMakePoint(500.0, 280.0)];
    XCTAssertNil(canvas.activeTextView);
    XCTAssertTrue(canvas.hasSelectionRect, @"Dragging empty space keeps making a region selection");
    XCTAssertEqual([canvas selectedAnnotationObjects].count, (NSUInteger)0);
}

@end
