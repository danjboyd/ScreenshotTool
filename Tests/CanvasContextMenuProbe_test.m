/*
 * CanvasContextMenuProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The canvas's right-click menu: what it offers for the region selection, an annotation and the
 * image, and the commands only it adds (Redact Selection, Duplicate, Bring to Front, Send to Back).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "MarkupText.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (CanvasContextMenuTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
- (void)setupMenus;
@end

@interface ScreenshotCanvasView (CanvasContextMenuTesting)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@property (nonatomic, strong) NSMutableArray<MarkupText *> *texts;
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
- (NSArray *)selectedAnnotationObjects;
- (void)cancelActiveTextEntry;
@end

@interface CanvasContextMenuProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation CanvasContextMenuProbeTests

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

/// A 600x300 canvas at 100% with a pen stroke along y = 50 (x 50–250), then a rectangle (x 300–400,
/// y 200–260) above it, and a text label around (300, 140).
- (ScreenshotCanvasView *)canvasWithAnnotations {
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self imageOfSize:NSMakeSize(600.0, 300.0)]];
    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;

    MarkupStroke *stroke = [[MarkupStroke alloc] initWithType:MarkupStrokeTypePen color:[NSColor redColor] lineWidth:6.0];
    [stroke addPoint:NSMakePoint(50.0, 50.0)];
    [stroke addPoint:NSMakePoint(250.0, 50.0)];
    MarkupStroke *rectangle = [[MarkupStroke alloc] initWithType:MarkupStrokeTypeRectangle color:[NSColor blueColor] lineWidth:4.0];
    [rectangle setStartPoint:NSMakePoint(300.0, 200.0) endPoint:NSMakePoint(400.0, 260.0)];
    canvas.strokes = [@[stroke, rectangle] mutableCopy];

    NSFont *font = [NSFont fontWithName:@"DejaVuSans" size:24.0] ?: [NSFont systemFontOfSize:24.0];
    MarkupText *text = [[MarkupText alloc] initWithText:@"Label" font:font color:[NSColor blueColor]
                                                 origin:NSMakePoint(300.0, 140.0) boxSize:NSMakeSize(1.0, 1.0)];
    [text fitToTextWithinCanvasSize:NSMakeSize(600.0, 300.0)];
    canvas.texts = [@[text] mutableCopy];
    return canvas;
}

- (NSEvent *)mouse:(NSEventType)type at:(NSPoint)point in:(ScreenshotCanvasView *)canvas {
    return [NSEvent mouseEventWithType:type
                              location:[canvas convertPoint:point toView:nil]
                         modifierFlags:0
                             timestamp:0
                          windowNumber:[canvas.window windowNumber]
                               context:nil
                           eventNumber:0
                            clickCount:1
                              pressure:1.0];
}

- (NSMenu *)rightClick:(ScreenshotCanvasView *)canvas at:(NSPoint)point {
    NSMenu *menu = [canvas menuForEvent:[self mouse:NSRightMouseDown at:point in:canvas]];
    [menu update];
    return menu;
}

- (void)drag:(ScreenshotCanvasView *)canvas from:(NSPoint)start to:(NSPoint)end {
    [canvas mouseDown:[self mouse:NSLeftMouseDown at:start in:canvas]];
    [canvas mouseDragged:[self mouse:NSLeftMouseDragged at:end in:canvas]];
    [canvas mouseUp:[self mouse:NSLeftMouseUp at:end in:canvas]];
}

/// The titles of the menu's items; separators as "-".
- (NSArray<NSString *> *)titlesOf:(NSMenu *)menu {
    NSMutableArray<NSString *> *titles = [[NSMutableArray alloc] init];
    for (NSMenuItem *item in menu.itemArray) {
        [titles addObject:item.isSeparatorItem ? @"-" : item.title];
    }
    return titles;
}

- (NSMenuItem *)item:(NSString *)title in:(NSMenu *)menu {
    NSInteger index = [menu indexOfItemWithTitle:title];
    return index >= 0 ? [menu itemAtIndex:index] : nil;
}

- (void)selectRegion:(NSRect)rect on:(ScreenshotCanvasView *)canvas {
    canvas.activeTool = ScreenshotCanvasToolSelect;
    [self drag:canvas from:rect.origin to:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
}

#pragma mark - Which menu

- (void)testNoImageNoMenu {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    XCTAssertNil([self rightClick:canvas at:NSMakePoint(10.0, 10.0)]);
}

- (void)testInsideTheSelectionCropComesFirst {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithAnnotations];
    [self selectRegion:NSMakeRect(420.0, 20.0, 150.0, 100.0) on:canvas];
    XCTAssertTrue(canvas.hasSelectionRect);

    NSMenu *menu = [self rightClick:canvas at:NSMakePoint(480.0, 60.0)];
#if defined(GNUSTEP) && !defined(ST_HAVE_LIBS_SHARING)
    NSArray *expected = @[@"Crop to Selection", @"Copy Selection", @"Redact Selection", @"-", @"Deselect"];
#else
    // macOS has a share picker, and Linux and Windows libs-sharing's.
    NSArray *expected = @[@"Crop to Selection", @"Copy Selection", @"Redact Selection", @"Share Selection…", @"-", @"Deselect"];
#endif
    XCTAssertEqualObjects([self titlesOf:menu], expected);
    NSMenuItem *crop = [self item:@"Crop to Selection" in:menu];
    XCTAssertTrue(crop.target == _appDelegate, @"The window's command, as the Edit menu has it");
    XCTAssertEqualObjects(crop.keyEquivalent, @"k", @"Its shortcut is shown");
    XCTAssertTrue(crop.isEnabled);
    XCTAssertTrue([self item:@"Redact Selection" in:menu].target == canvas);
    XCTAssertTrue(canvas.hasSelectionRect, @"Right-clicking the selection keeps it");
}

- (void)testTheSelectionWinsOverAnAnnotationInIt {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithAnnotations];
    [self selectRegion:NSMakeRect(20.0, 20.0, 260.0, 60.0) on:canvas];

    NSMenu *menu = [self rightClick:canvas at:NSMakePoint(150.0, 51.0)];
    XCTAssertEqualObjects([self titlesOf:menu].firstObject, @"Crop to Selection",
                          @"Right-clicking the selection is about the selection, not the stroke it covers");
    XCTAssertEqual([canvas selectedAnnotationObjects].count, (NSUInteger)0);
}

- (void)testAnAnnotationIsSelectedFirstWithTheSelectTool {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithAnnotations];
    canvas.activeTool = ScreenshotCanvasToolPen;

    NSMenu *menu = [self rightClick:canvas at:NSMakePoint(150.0, 51.0)];
    NSArray *expected = @[@"Duplicate", @"Bring to Front", @"Send to Back", @"-", @"Delete"];
    XCTAssertEqualObjects([self titlesOf:menu], expected);
    XCTAssertEqual(canvas.activeTool, ScreenshotCanvasToolSelect, @"The select tool, which shows the selection");
    XCTAssertTrue([canvas selectedAnnotationObjects].firstObject == canvas.strokes.firstObject);
    XCTAssertTrue([self item:@"Delete" in:menu].isEnabled);
}

- (void)testATextLabelOffersEditTextFirst {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithAnnotations];
    MarkupText *text = canvas.texts.firstObject;
    NSPoint onText = NSMakePoint(NSMidX([text textBounds]), NSMidY([text textBounds]));

    NSMenu *menu = [self rightClick:canvas at:onText];
    XCTAssertEqualObjects([self titlesOf:menu].firstObject, @"Edit Text");
    XCTAssertTrue([self item:@"Edit Text" in:menu].isEnabled);
    [canvas editSelectedText:nil];
    XCTAssertTrue([canvas activeTextEntry] != nil, @"Edit Text opens the label for editing");
    [canvas cancelActiveTextEntry];
}

- (void)testTheImageOutsideTheSelectionClearsIt {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithAnnotations];
    [self selectRegion:NSMakeRect(420.0, 20.0, 150.0, 100.0) on:canvas];

    NSMenu *menu = [self rightClick:canvas at:NSMakePoint(100.0, 250.0)];
#if defined(GNUSTEP) && !defined(ST_HAVE_LIBS_SHARING)
    NSArray *expected = @[@"Copy Image", @"Paste as New Image", @"-", @"Fit to Window", @"Zoom to 100%", @"-", @"Save As…"];
#else
    NSArray *expected = @[@"Copy Image", @"Paste as New Image", @"-", @"Fit to Window", @"Zoom to 100%", @"-", @"Save As…",
                          @"Share…"];
#endif
    XCTAssertEqualObjects([self titlesOf:menu], expected, @"The test environment has no custom actions");
    XCTAssertFalse(canvas.hasSelectionRect, @"So Copy Image copies the whole image");
    XCTAssertTrue([self item:@"Copy Image" in:menu].isEnabled);
}

- (void)testShareIsOfferedOnlyWithAPicker {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSMenu *selection = STCanvasContextMenu(STCanvasContextKindSelection, NO, YES, canvas, _appDelegate, nil);
    XCTAssertEqualObjects([self titlesOf:selection],
                          (@[@"Crop to Selection", @"Copy Selection", @"Redact Selection", @"Share Selection…", @"-", @"Deselect"]));
    NSMenu *image = STCanvasContextMenu(STCanvasContextKindImage, NO, YES, canvas, _appDelegate, nil);
    NSMenuItem *share = [self item:@"Share…" in:image];
    XCTAssertNotNil(share, @"After Save As…");
    XCTAssertEqual(share.action, @selector(shareImage:));
    XCTAssertTrue(share.target == _appDelegate);
    XCTAssertNil([self item:@"Share…" in:STCanvasContextMenu(STCanvasContextKindImage, NO, NO, canvas, _appDelegate, nil)],
                 @"No picker, no Share");
    [canvas loadImage:[self imageOfSize:NSMakeSize(200.0, 100.0)]];
#if defined(GNUSTEP) && !defined(ST_HAVE_LIBS_SHARING)
    XCTAssertNil([self item:@"Share…" in:[self rightClick:canvas at:NSMakePoint(50.0, 50.0)]],
                 @"Not on GNUstep without libs-sharing's picker");
#else
    XCTAssertNotNil([self item:@"Share…" in:[self rightClick:canvas at:NSMakePoint(50.0, 50.0)]],
                    @"macOS's picker, and on Linux and Windows libs-sharing's");
#endif
}

#pragma mark - The menu's own commands

- (void)testRedactSelectionAddsARedactionThatUndoes {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithAnnotations];
    [self selectRegion:NSMakeRect(420.0, 20.0, 150.0, 100.0) on:canvas];
    NSUInteger before = canvas.strokes.count;

    [canvas redactSelection:nil];
    XCTAssertEqual(canvas.strokes.count, before + 1);
    MarkupStroke *redaction = canvas.strokes.lastObject;
    XCTAssertEqual(redaction.type, MarkupStrokeTypeRedact);
    NSRect rect = [redaction shapeRect];
    XCTAssertEqualWithAccuracy(NSMinX(rect), 420.0, 1.0);
    XCTAssertEqualWithAccuracy(NSMinY(rect), 20.0, 1.0);
    XCTAssertEqualWithAccuracy(NSWidth(rect), 150.0, 1.0);
    XCTAssertEqualWithAccuracy(NSHeight(rect), 100.0, 1.0, @"It covers the selection");
    XCTAssertFalse(canvas.hasSelectionRect, @"The selection goes, so the redaction shows");

    [[canvas undoManager] undo];
    XCTAssertEqual(canvas.strokes.count, before);
}

- (void)testDuplicateSelectsOffsetCopiesThatUndo {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithAnnotations];
    [self rightClick:canvas at:NSMakePoint(150.0, 51.0)];
    MarkupStroke *original = canvas.strokes.firstObject;

    [canvas duplicateAnnotations:nil];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)3);
    MarkupStroke *copy = canvas.strokes.lastObject;
    XCTAssertTrue(copy != original);
    XCTAssertTrue([canvas selectedAnnotationObjects].firstObject == copy, @"The copy is selected, ready to move");
    NSPoint first = [[[copy points] firstObject] pointValue];
    XCTAssertEqualWithAccuracy(first.x, 62.0, 0.01);
    XCTAssertEqualWithAccuracy(first.y, 62.0, 0.01, @"Offset down and right of the original");

    [[canvas undoManager] undo];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)2);
}

- (void)testBringToFrontAndSendToBackRestackWithinTheLayer {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithAnnotations];
    MarkupStroke *pen = canvas.strokes[0];
    MarkupStroke *rectangle = canvas.strokes[1];

    // Each command its own undo step, as separate clicks are; here there's no event loop to group them.
    NSUndoManager *undo = [canvas undoManager];
    [undo setGroupsByEvent:NO];
    [self rightClick:canvas at:NSMakePoint(150.0, 51.0)];
    [undo beginUndoGrouping];
    [canvas bringAnnotationsToFront:nil];
    [undo endUndoGrouping];
    XCTAssertTrue(canvas.strokes.lastObject == pen, @"The pen stroke now draws above the rectangle");
    XCTAssertTrue(canvas.strokes.firstObject == rectangle);

    [undo beginUndoGrouping];
    [canvas sendAnnotationsToBack:nil];
    [undo endUndoGrouping];
    XCTAssertTrue(canvas.strokes.firstObject == pen);

    [undo undo];
    [undo setGroupsByEvent:YES];
    // Undo restores copies, so by kind.
    XCTAssertEqual(canvas.strokes.lastObject.type, MarkupStrokeTypePen, @"Undo restacks one step at a time");
}

- (void)testDeleteAndEscape {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithAnnotations];
    [self rightClick:canvas at:NSMakePoint(150.0, 51.0)];
    [canvas deleteAnnotations:nil];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)1);

    [self selectRegion:NSMakeRect(420.0, 20.0, 150.0, 100.0) on:canvas];
    unichar escape = 0x1b;
    NSString *characters = [NSString stringWithCharacters:&escape length:1];
    [canvas keyDown:[NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                                 windowNumber:[canvas.window windowNumber] context:nil
                                   characters:characters charactersIgnoringModifiers:characters
                                    isARepeat:NO keyCode:0]];
    XCTAssertFalse(canvas.hasSelectionRect, @"Esc clears the region selection, as Deselect does");
}

#pragma mark - The Edit menu

/// The Edit menu's item with this title, from the app's menu bar.
- (NSMenuItem *)editMenuItem:(NSString *)title {
    NSMenu *edit = [[[NSApp mainMenu] itemWithTitle:@"Edit"] submenu];
    return [edit itemWithTitle:title];
}

- (void)testTheMenuOnlyCommandsAreInTheEditMenuToo {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_appDelegate setupMenus];
    ScreenshotCanvasView *canvas = [self canvasWithAnnotations];

    NSDictionary<NSString *, NSArray *> *expected = @{
        @"Redact Selection": @[@"", @NO],
        @"Duplicate": @[@"d", @NO],
        @"Bring to Front": @[@"F", @YES],
        @"Send to Back": @[@"B", @YES],
    };
    for (NSString *title in expected) {
        NSMenuItem *item = [self editMenuItem:title];
        XCTAssertNotNil(item, @"%@ is in the Edit menu", title);
        XCTAssertEqualObjects(item.keyEquivalent, expected[title][0], @"%@'s shortcut", title);
        BOOL shift = (item.keyEquivalentModifierMask & NSEventModifierFlagShift) != 0;
        XCTAssertEqual(shift, [expected[title][1] boolValue], @"%@'s shortcut", title);
        XCTAssertFalse([_appDelegate validateMenuItem:item], @"%@: nothing selected yet", title);
    }

    NSMenu *menu = [self rightClick:canvas at:NSMakePoint(150.0, 51.0)];
    XCTAssertEqualObjects([self item:@"Duplicate" in:menu].keyEquivalent, @"d",
                          @"The right-click menu shows the Edit menu's shortcut");
    NSMenuItem *duplicate = [self editMenuItem:@"Duplicate"];
    XCTAssertTrue([_appDelegate validateMenuItem:duplicate], @"Enabled with an annotation selected");
    [_appDelegate performSelector:duplicate.action withObject:duplicate];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)3, @"The Edit menu's Duplicate duplicates it");

    [self selectRegion:NSMakeRect(420.0, 20.0, 150.0, 100.0) on:canvas];
    NSMenuItem *redact = [self editMenuItem:@"Redact Selection"];
    XCTAssertTrue([_appDelegate validateMenuItem:redact]);
    [_appDelegate performSelector:redact.action withObject:redact];
    XCTAssertEqual(canvas.strokes.lastObject.type, MarkupStrokeTypeRedact);
}

@end
