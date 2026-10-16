/*
 * RedactToolProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The redact tool (v0.2.0, #221).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "MarkupText.h"
#import "STThemeUtilities.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (RedactTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
- (void)textOptionsBarDidTogglePointer:(id)bar;
- (void)copy:(id)sender;
- (ScreenshotCanvasTool)toolbarToolForSegmentIndex:(NSInteger)index;
- (NSInteger)toolbarSegmentIndexForTool:(ScreenshotCanvasTool)tool;
@end

@interface ScreenshotCanvasView (RedactTesting)
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

@interface RedactToolProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation RedactToolProbeTests

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

#pragma mark - Redact tool

/// An image of 1-pixel black and white stripes: anything a redaction leaves readable shows.
- (NSImage *)stripedImage {
    NSInteger width = 600, height = 300;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height
                                                                  bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                 colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:width * 4 bitsPerPixel:32];
    unsigned char *data = [rep bitmapData];
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            unsigned char value = (x % 2 == 0) ? 0 : 255;
            unsigned char *pixel = data + (y * width * 4) + (x * 4);
            pixel[0] = pixel[1] = pixel[2] = value;
            pixel[3] = 255;
        }
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [image addRepresentation:rep];
    return image;
}

- (ScreenshotCanvasView *)stripedCanvasWithTool:(ScreenshotCanvasTool)tool {
    ScreenshotCanvasView *canvas = [self canvasWithTool:tool];
    [canvas loadImage:[self stripedImage]];
    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;
    return canvas;
}

- (CGFloat)greyAt:(NSBitmapImageRep *)rep x:(NSInteger)x y:(NSInteger)y {
    return [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]].redComponent;
}

- (void)testRedactionPixelatesTheExport {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self stripedCanvasWithTool:ScreenshotCanvasToolRedact];
    [self drag:canvas from:NSMakePoint(100.0, 100.0) to:NSMakePoint(200.0, 150.0) flags:0];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)1);
    XCTAssertEqual(canvas.strokes.firstObject.type, MarkupStrokeTypeRedact);

    NSBitmapImageRep *rep = [self exportOf:canvas];
    // Inside: each 10px cell one grey, the stripes' average.
    for (NSInteger x = 100; x < 110; x++) {
        XCTAssertEqualWithAccuracy([self greyAt:rep x:x y:105], [self greyAt:rep x:100 y:105], 0.01, @"One colour across a cell (x %ld)", (long)x);
    }
    XCTAssertEqualWithAccuracy([self greyAt:rep x:105 y:105], 0.5, 0.05, @"...the average of what's under it");
    XCTAssertEqualWithAccuracy([self greyAt:rep x:195 y:145], 0.5, 0.05, @"To the far corner");
    // Outside: the stripes, untouched.
    XCTAssertEqualWithAccuracy(fabs([self greyAt:rep x:90 y:105] - [self greyAt:rep x:91 y:105]), 1.0, 0.01, @"The image beside it is as it was");
    XCTAssertEqualWithAccuracy(fabs([self greyAt:rep x:150 y:160] - [self greyAt:rep x:151 y:160]), 1.0, 0.01, @"...and below it");
}

/// Annotations draw over a redaction: it pixelates the image, not them.
- (void)testAnnotationsStayOverARedaction {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self stripedCanvasWithTool:ScreenshotCanvasToolArrow];
    [self drag:canvas from:NSMakePoint(60.0, 130.0) to:NSMakePoint(300.0, 130.0) flags:0];
    canvas.activeTool = ScreenshotCanvasToolRedact;
    [self drag:canvas from:NSMakePoint(100.0, 100.0) to:NSMakePoint(200.0, 160.0) flags:0];
    NSBitmapImageRep *rep = [self exportOf:canvas];
    BOOL (^blue)(NSColor *) = ^BOOL(NSColor *p) { return p.blueComponent > 0.7 && p.redComponent < 0.4; };
    XCTAssertGreaterThan([self countIn:rep rect:NSMakeRect(150.0, 120.0, 1.0, 20.0) matching:blue], 2,
                         @"The arrow, drawn first, still shows over the redaction drawn after it");
}

- (void)testRedactShortcutSegmentProjectFileAndResize {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithTool:ScreenshotCanvasToolSelect];
    NSString *x = @"x";
    [canvas keyDown:[NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                                 windowNumber:[canvas.window windowNumber] context:nil characters:x
                  charactersIgnoringModifiers:x isARepeat:NO keyCode:0]];
    XCTAssertEqual(canvas.activeTool, ScreenshotCanvasToolRedact, @"X selects the redact tool");
    // Select, Highlighter, Pen, Arrow, Rectangle, Text, Step, Redact, Eraser (#221).
    XCTAssertEqual([_appDelegate toolbarSegmentIndexForTool:ScreenshotCanvasToolRedact], 7);
    XCTAssertEqual([_appDelegate toolbarToolForSegmentIndex:7], ScreenshotCanvasToolRedact);
    XCTAssertEqual([_appDelegate toolbarToolForSegmentIndex:8], ScreenshotCanvasToolEraser);

    MarkupStroke *redaction = [[MarkupStroke alloc] initWithType:MarkupStrokeTypeRedact color:[NSColor blackColor] lineWidth:1.0];
    [redaction setStartPoint:NSMakePoint(10.0, 20.0) endPoint:NSMakePoint(60.0, 40.0)];
    MarkupStroke *copy = [MarkupStroke strokeWithProjectRepresentation:[redaction projectRepresentation]];
    XCTAssertEqual(copy.type, MarkupStrokeTypeRedact);
    XCTAssertTrue(NSEqualRects([copy shapeRect], NSMakeRect(10.0, 20.0, 50.0, 20.0)), @"%@", NSStringFromRect([copy shapeRect]));
    XCTAssertTrue([copy containsPoint:NSMakePoint(35.0, 30.0) tolerance:1.0], @"Hit anywhere inside");

    canvas.activeTool = ScreenshotCanvasToolRedact;
    [self drag:canvas from:NSMakePoint(100.0, 100.0) to:NSMakePoint(200.0, 150.0) flags:0];
    MarkupStroke *drawn = canvas.strokes.firstObject;
    canvas.activeTool = ScreenshotCanvasToolSelect;
    [canvas selectAnnotation:drawn extending:NO];
    NSRect handles[4];
    [canvas getSelectionHandleRects:handles forAnnotation:drawn];
    NSPoint grab = NSMakePoint(NSMidX(handles[0]), NSMidY(handles[0])); // top left
    [self drag:canvas from:grab to:NSMakePoint(grab.x - 20.0, grab.y - 10.0) flags:0];
    XCTAssertTrue(NSEqualRects([drawn shapeRect], NSMakeRect(80.0, 90.0, 120.0, 60.0)),
                  @"It resizes by a corner handle as a rectangle does: %@", NSStringFromRect([drawn shapeRect]));
}

@end
