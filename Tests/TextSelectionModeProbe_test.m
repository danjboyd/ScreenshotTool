/*
 * TextSelectionModeProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Select Text (#330), the canvas side: the mode reads the image once, outlines the words, selects
 * them by dragging in reading order, copies them, and ends with Esc or a tool change. The reader is
 * replaced by canned lines, so this runs the same with every engine.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "MarkupStroke.h"
#import "ScreenshotCanvasView.h"
#import "STTextRecognizer.h"
#import "STTextSelection.h"
#import "STThemeUtilities.h"
#import "TestEnvironmentHelpers.h"

@interface ScreenshotCanvasView (TextSelectionModeTesting)
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
@property (nonatomic, assign) CGFloat zoomScale;
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
- (void)cancelOperation:(id)sender;
@end

@interface AppDelegate (TextSelectionModeTesting)
- (void)setupWindowAndContent;
- (ScreenshotCanvasView *)canvasView;
- (BOOL)openImageAtURL:(NSURL *)url;
- (void)selectText:(id)sender;
- (void)redactSelectedText:(id)sender;
- (void)copy:(id)sender;
- (void)readTextInImageRect:(NSRect)rect completion:(void (^)(NSArray<STRecognizedLine *> *lines))completion;
- (void)showCommandResultMessage:(NSString *)message duration:(NSTimeInterval)duration;
- (void)copyCustomActionText:(NSString *)text;
- (void)updateDocumentEditedState;
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
- (void)setupMenus;
@end

@interface TextSelectionModeProbeAppDelegate : AppDelegate
@property (nonatomic, copy) NSArray<STRecognizedLine *> *cannedLines;
@property (nonatomic, assign) NSUInteger reads;
@property (nonatomic, strong) NSMutableArray<NSString *> *messages;
@property (nonatomic, copy) NSString *copiedText;
@property (nonatomic, assign) NSUInteger editedStateUpdates;
@end

@implementation TextSelectionModeProbeAppDelegate
- (void)readTextInImageRect:(NSRect)rect completion:(void (^)(NSArray<STRecognizedLine *> *lines))completion {
    (void)rect;
    self.reads++;
    completion(self.cannedLines ?: @[]);
}
- (void)showCommandResultMessage:(NSString *)message duration:(NSTimeInterval)duration {
    (void)duration;
    if (!self.messages) {
        self.messages = [NSMutableArray array];
    }
    [self.messages addObject:message];
}
- (void)copyCustomActionText:(NSString *)text {
    self.copiedText = text;
}
- (void)updateDocumentEditedState {
    self.editedStateUpdates++;
    [super updateDocumentEditedState];
}
@end

@interface TextSelectionModeProbeTests : XCTestCase {
    BOOL _shouldSkip;
    TextSelectionModeProbeAppDelegate *_app;
}
@end

@implementation TextSelectionModeProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        _app = [[TextSelectionModeProbeAppDelegate alloc] init];
        [_app setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
        return;
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(400.0, 200.0)];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 400.0, 200.0));
    [image unlockFocus];
    [_app.canvasView loadImage:image];
    // Two lines: "Hello there world" at y 20, "second line" at y 60 (image pixels, top-left origin).
    _app.cannedLines = @[ [self lineAtY:20.0 words:@[ @"Hello", @"there", @"world" ]],
                          [self lineAtY:60.0 words:@[ @"second", @"line" ]] ];
}

- (void)tearDown {
    _app = nil;
    [super tearDown];
}

- (STRecognizedLine *)lineAtY:(CGFloat)y words:(NSArray<NSString *> *)texts {
    NSMutableArray<STRecognizedWord *> *words = [NSMutableArray array];
    CGFloat x = 10.0;
    for (NSString *text in texts) {
        [words addObject:[[STRecognizedWord alloc] initWithText:text bounds:NSMakeRect(x, y, 50.0, 16.0)]];
        x += 60.0;
    }
    return [[STRecognizedLine alloc] initWithWords:words];
}

/// A mouse event at an image point (top-left pixels), through the canvas's zoom.
- (NSEvent *)event:(NSEventType)type atImagePoint:(NSPoint)point clicks:(NSInteger)clicks flags:(NSEventModifierFlags)flags {
    ScreenshotCanvasView *canvas = _app.canvasView;
    NSPoint viewPoint = NSMakePoint(point.x * canvas.zoomScale, point.y * canvas.zoomScale);
    NSPoint windowPoint = [canvas convertPoint:viewPoint toView:nil];
    return [NSEvent mouseEventWithType:type location:windowPoint modifierFlags:flags timestamp:0
                          windowNumber:canvas.window.windowNumber context:nil eventNumber:0
                            clickCount:clicks pressure:1.0];
}

- (void)dragFrom:(NSPoint)start to:(NSPoint)end {
    ScreenshotCanvasView *canvas = _app.canvasView;
    [canvas mouseDown:[self event:NSEventTypeLeftMouseDown atImagePoint:start clicks:1 flags:0]];
    [canvas mouseDragged:[self event:NSEventTypeLeftMouseDragged atImagePoint:end clicks:1 flags:0]];
    [canvas mouseUp:[self event:NSEventTypeLeftMouseUp atImagePoint:end clicks:1 flags:0]];
}

- (void)testEnteringReadsOnceAndOutlinesTheWords {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_app selectText:nil];
    XCTAssertTrue([_app.canvasView isSelectingText]);
    XCTAssertEqual(_app.canvasView.textSelection.wordCount, (NSUInteger)5);
    XCTAssertEqual(_app.reads, (NSUInteger)1);

    // Off and on again with nothing changed: no second read.
    [_app selectText:nil];
    XCTAssertFalse([_app.canvasView isSelectingText], @"Select Text again turns it off");
    [_app selectText:nil];
    XCTAssertTrue([_app.canvasView isSelectingText]);
    XCTAssertEqual(_app.reads, (NSUInteger)1, @"The last read is reused while nothing changed");
}

- (void)testNoTextDoesntEnterTheMode {
    XCTSkipIf(_shouldSkip, @"No window server");
    _app.cannedLines = @[];
    [_app selectText:nil];
    XCTAssertFalse([_app.canvasView isSelectingText]);
    XCTAssertEqualObjects(_app.messages.lastObject, @"No text found in the image");
}

- (void)testADragAcrossALineBreakSelectsInReadingOrderAndCopies {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_app selectText:nil];
    // From "there" to "second", leftwards and down: everything between, in reading order.
    [self dragFrom:NSMakePoint(95.0, 28.0) to:NSMakePoint(20.0, 68.0)];
    XCTAssertEqualObjects(_app.canvasView.textSelection.selectedText, @"there world\nsecond");
    XCTAssertEqual(_app.canvasView.textSelection.selectedRects.count, (NSUInteger)2, @"A highlight per line");

    [_app copy:nil];
    XCTAssertEqualObjects(_app.copiedText, @"there world\nsecond", @"Copy copies the words, not the image");
}

- (void)testRedactSelectedTextCoversEachLineGrownAndUndoesTogether {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = _app.canvasView;
    [_app selectText:nil];
    NSUInteger reads = _app.reads;
    [self dragFrom:NSMakePoint(95.0, 28.0) to:NSMakePoint(20.0, 68.0)]; // "there world", "second"
    NSUndoManager *undo = [canvas undoManager];
    [undo setGroupsByEvent:NO];
    [undo beginUndoGrouping];
    [_app redactSelectedText:nil];
    [undo endUndoGrouping];

    // A redaction per line: the words' union, padded (3 pixels here), as Redact Emails and Phone Numbers does.
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)2);
    XCTAssertTrue(NSEqualRects(canvas.strokes[0].bounds, NSMakeRect(67.0, 17.0, 116.0, 22.0)), @"%@",
                  NSStringFromRect(canvas.strokes[0].bounds));
    XCTAssertTrue(NSEqualRects(canvas.strokes[1].bounds, NSMakeRect(7.0, 57.0, 56.0, 22.0)), @"%@",
                  NSStringFromRect(canvas.strokes[1].bounds));
    XCTAssertEqualObjects(_app.messages.lastObject, @"Redacted 2 items");

    // Still selecting, with nothing selected, and read again: Copy can't give back what's redacted.
    XCTAssertTrue([canvas isSelectingText]);
    XCTAssertEqual(canvas.textSelection.selectedRange.length, (NSUInteger)0);
    XCTAssertEqual(_app.reads, reads + 1);

    [undo undo];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)0, @"One undo takes both");
}

- (void)testRedactSelectedTextMarksTheImageEditedAtOnce {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_app selectText:nil];
    [self dragFrom:NSMakePoint(15.0, 28.0) to:NSMakePoint(55.0, 28.0)];
    NSUInteger updates = _app.editedStateUpdates;
    [_app redactSelectedText:nil];
    XCTAssertGreaterThan(_app.editedStateUpdates, updates, @"The status bar says \"unsaved\" now, not on the undo notice");
}

- (void)testRedactSelectedTextOverARedactionSaysAlreadyRedacted {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = _app.canvasView;
    [_app selectText:nil];
    [self dragFrom:NSMakePoint(15.0, 28.0) to:NSMakePoint(55.0, 28.0)];
    [_app redactSelectedText:nil];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)1);
    XCTAssertEqualObjects(_app.messages.lastObject, @"Redacted 1 item");

    // The canned reader still sees the word, as an engine can through a light redaction.
    [self dragFrom:NSMakePoint(15.0, 28.0) to:NSMakePoint(55.0, 28.0)];
    [_app redactSelectedText:nil];
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)1, @"Nothing added over it");
    XCTAssertEqualObjects(_app.messages.lastObject, @"Already redacted");
}

- (void)testRedactSelectedTextPadsWithTheTextHeight {
    XCTSkipIf(_shouldSkip, @"No window server");
    STRecognizedWord *word = [[STRecognizedWord alloc] initWithText:@"tall" bounds:NSMakeRect(50.0, 50.0, 100.0, 40.0)];
    _app.cannedLines = @[ [[STRecognizedLine alloc] initWithWords:@[ word ]] ];
    [_app selectText:nil];
    [self dragFrom:NSMakePoint(60.0, 70.0) to:NSMakePoint(140.0, 70.0)];
    [_app redactSelectedText:nil];
    XCTAssertEqual(_app.canvasView.strokes.count, (NSUInteger)1);
    // 15% of 40 is 6, as STSensitiveTextRects pads.
    XCTAssertTrue(NSEqualRects(_app.canvasView.strokes[0].bounds, NSMakeRect(44.0, 44.0, 112.0, 52.0)), @"%@",
                  NSStringFromRect(_app.canvasView.strokes[0].bounds));
}

- (void)testRedactSelectedTextWithNothingSelectedDoesNothing {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_app selectText:nil];
    NSUInteger messages = _app.messages.count;
    [_app redactSelectedText:nil];
    XCTAssertEqual(_app.canvasView.strokes.count, (NSUInteger)0);
    XCTAssertEqual(_app.messages.count, messages);
}

- (void)testDoubleAndTripleClickSelectAWordAndALine {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_app selectText:nil];
    ScreenshotCanvasView *canvas = _app.canvasView;
    [canvas mouseDown:[self event:NSEventTypeLeftMouseDown atImagePoint:NSMakePoint(150.0, 28.0) clicks:2 flags:0]];
    XCTAssertEqualObjects(canvas.textSelection.selectedText, @"world");
    [canvas mouseDown:[self event:NSEventTypeLeftMouseDown atImagePoint:NSMakePoint(80.0, 68.0) clicks:3 flags:0]];
    XCTAssertEqualObjects(canvas.textSelection.selectedText, @"second line");
}

- (void)testARegionSelectionPreselectsItsWords {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = _app.canvasView;
    canvas.hasSelectionRect = YES;
    canvas.selectionRect = NSMakeRect(0.0, 50.0, 200.0, 40.0);
    [_app selectText:nil];
    XCTAssertEqualObjects(canvas.textSelection.selectedText, @"second line");
    XCTAssertFalse(canvas.hasSelectionRect, @"The region becomes the word selection");
}

- (void)testEscAndAToolChangeLeaveTheMode {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_app selectText:nil];
    [_app.canvasView cancelOperation:nil];
    XCTAssertFalse([_app.canvasView isSelectingText], @"Esc leaves it");

    [_app selectText:nil];
    _app.canvasView.activeTool = ScreenshotCanvasToolPen;
    XCTAssertFalse([_app.canvasView isSelectingText], @"Choosing a tool leaves it");

    [_app selectText:nil];
    _app.canvasView.activeTool = ScreenshotCanvasToolPen;
    XCTAssertFalse([_app.canvasView isSelectingText], @"Choosing the tool already on leaves it too");
}

/// A key press as the window delivers it to the canvas.
- (void)sendKey:(unichar)key flags:(NSEventModifierFlags)flags {
    ScreenshotCanvasView *canvas = _app.canvasView;
    NSString *characters = [NSString stringWithCharacters:&key length:1];
    [canvas keyDown:[NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                                 windowNumber:[canvas.window windowNumber] context:nil
                                   characters:characters charactersIgnoringModifiers:characters
                                    isARepeat:NO keyCode:0]];
}

- (void)testEscAsAKeyPressLeavesTheMode {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_app selectText:nil];
    XCTAssertTrue([_app.canvasView isSelectingText]);
    [self sendKey:0x1b flags:0];
    XCTAssertFalse([_app.canvasView isSelectingText], @"Esc reaches keyDown: on GNUstep, not cancelOperation:");
}

#if defined(GNUSTEP)
- (void)testControlASelectsAllInTheModeOnly {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_app selectText:nil];
    [self sendKey:'a' flags:NSEventModifierFlagControl];
    XCTAssertEqual(_app.canvasView.textSelection.selectedRange.length, (NSUInteger)5, @"All five words");

    [_app.canvasView endTextSelection:nil];
    [self sendKey:'a' flags:NSEventModifierFlagControl];
    XCTAssertFalse([_app.canvasView isSelectingText], @"Out of the mode, it isn't taken and starts nothing");
}

- (void)testAPlainAInTheModeDoesntSelectAll {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_app selectText:nil];
    [self sendKey:'a' flags:0];
    XCTAssertEqual(_app.canvasView.textSelection.selectedRange.length, (NSUInteger)0, @"Only with Control");
}
#endif

- (void)testThemeColorsKeepAnAlpha {
    XCTSkipIf(_shouldSkip, @"No window server");
    XCTAssertEqualWithAccuracy(STThemeColorWithAlpha([NSColor selectedControlColor], 0.28).alphaComponent, 0.28, 0.001,
                               @"A system colour, as a theme's accent can be, keeps it, or the highlight hides the words");
    XCTAssertEqualWithAccuracy(STThemeColorWithAlpha(STThemeAccentColor(), 0.45).alphaComponent, 0.45, 0.001);
}

- (void)testCopyWithNothingSelectedStillCopiesTheImage {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_app selectText:nil];
    [_app copy:nil];
    XCTAssertNil(_app.copiedText, @"No words selected: Copy is the image's, as before");
}

/// The Retina check: an image whose size in points is half its pixels opens 1:1 in pixels, so the
/// reader's pixel boxes land on the words at any zoom.
- (void)testPixelBoxesLandOnTheWordsForAHighDensityImage {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:800 pixelsHigh:400
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                      isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:0];
    memset(rep.bitmapData, 255, (size_t)(rep.bytesPerRow * rep.pixelsHigh));
    rep.size = NSMakeSize(400.0, 200.0); // 144 dpi, as a Retina capture
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                 [NSString stringWithFormat:@"retina-%@.png", [NSUUID UUID].UUIDString]];
    XCTAssertTrue([[rep representationUsingType:NSPNGFileType properties:@{}] writeToFile:path atomically:YES]);
    XCTAssertTrue([_app openImageAtURL:[NSURL fileURLWithPath:path]]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    XCTAssertEqualWithAccuracy(_app.canvasView.image.size.width, 800.0, 0.5, @"Opened at one point per pixel");

    // A word at pixels (600, 300): past the 400 × 200 the image's points would give.
    STRecognizedWord *word = [[STRecognizedWord alloc] initWithText:@"far" bounds:NSMakeRect(600.0, 300.0, 60.0, 20.0)];
    _app.cannedLines = @[ [[STRecognizedLine alloc] initWithWords:@[ word ]] ];
    [_app selectText:nil];
    [_app.canvasView mouseDown:[self event:NSEventTypeLeftMouseDown atImagePoint:NSMakePoint(630.0, 310.0) clicks:2 flags:0]];
    XCTAssertEqualObjects(_app.canvasView.textSelection.selectedText, @"far");
}

- (void)testEditMenuRedactSelectedTextNeedsSelectedWords {
    XCTSkipIf(_shouldSkip, @"No window server");
    if (![STTextRecognizer isAvailable]) {
        return; // No engine, no text commands.
    }
    [_app setupMenus];
    NSMenuItem *item = nil;
    for (NSMenuItem *top in [[NSApp mainMenu] itemArray]) {
        NSInteger index = [top.submenu indexOfItemWithTitle:@"Redact Selected Text"];
        if (index >= 0) {
            item = [top.submenu itemAtIndex:index];
            break;
        }
    }
    XCTAssertNotNil(item, @"Edit has Redact Selected Text");
    XCTAssertEqual(item.action, @selector(redactSelectedText:));
    XCTAssertEqual(item.keyEquivalent.length, (NSUInteger)0, @"No shortcut of its own");

    XCTAssertFalse([_app validateMenuItem:item], @"Off outside Select Text");
    [_app selectText:nil];
    XCTAssertFalse([_app validateMenuItem:item], @"Off with nothing selected");
    [self dragFrom:NSMakePoint(15.0, 28.0) to:NSMakePoint(55.0, 28.0)];
    XCTAssertTrue([_app validateMenuItem:item], @"On with words selected");
    [_app.canvasView endTextSelection:nil];
    XCTAssertFalse([_app validateMenuItem:item], @"Off again when the mode ends");
}

/// ⇧⌘E, declared as Copy Text's is: GNUstep sends the Ctrl key as Command, so the menu shows
/// Shift+Ctrl+E there, and a Control mask would be unreachable (see PasteAsNewImageProbe).
- (void)testTheShortcutIsShiftCommandE {
    XCTSkipIf(_shouldSkip, @"No window server");
    if (![STTextRecognizer isAvailable]) {
        return; // No engine, no text commands.
    }
    [_app setupMenus];
    NSMenuItem *item = nil;
    for (NSMenuItem *top in [[NSApp mainMenu] itemArray]) {
        NSInteger index = [top.submenu indexOfItemWithTitle:@"Select Text"];
        if (index >= 0) {
            item = [top.submenu itemAtIndex:index];
            break;
        }
    }
    XCTAssertNotNil(item, @"Edit has Select Text");
    XCTAssertEqualObjects(item.keyEquivalent.lowercaseString, @"e");
    NSUInteger mask = item.keyEquivalentModifierMask;
    XCTAssertTrue((mask & NSEventModifierFlagCommand) != 0);
    XCTAssertTrue((mask & NSEventModifierFlagShift) != 0);
    XCTAssertTrue((mask & NSEventModifierFlagControl) == 0);
}

@end
