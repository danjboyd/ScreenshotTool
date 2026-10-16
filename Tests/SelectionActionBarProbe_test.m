/*
 * SelectionActionBarProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The bar of Crop, Copy and Redact next to a finished region selection: where it goes, when it
 * shows, that its buttons work, and its preference.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "STSelectionActionBar.h"
#import "ScreenshotToolSettings.h"
#import "PreferencesWindowController.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (SelectionActionBarTesting) <PreferencesWindowControllerDelegate>
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
- (STSelectionActionBar *)selectionActionBar;
- (void)loadToolSettingsFromDefaults;
@end

@interface ScreenshotCanvasView (SelectionActionBarTesting)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
- (BOOL)isPointOnShownCanvas:(NSPoint)viewPoint;
@end

/// A superview that counts down from the top, as the canvas does.
@interface STFlippedTestView : NSView
@end
@implementation STFlippedTestView
- (BOOL)isFlipped {
    return YES;
}
@end

@interface SelectionActionBarProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation SelectionActionBarProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsShowSelectionBarKey];
        _appDelegate = [[AppDelegate alloc] init];
        [_appDelegate setupWindowAndContent];
        [_appDelegate loadToolSettingsFromDefaults];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsShowSelectionBarKey];
    _appDelegate = nil;
    [super tearDown];
}

#pragma mark - Helpers

- (ScreenshotCanvasView *)canvasWithImage {
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600.0, 300.0)];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 600.0, 300.0));
    [image unlockFocus];
    [canvas loadImage:image];
    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;
    canvas.activeTool = ScreenshotCanvasToolSelect;
    return canvas;
}

- (NSEvent *)mouse:(NSEventType)type at:(NSPoint)point in:(ScreenshotCanvasView *)canvas {
    return [NSEvent mouseEventWithType:type location:[canvas convertPoint:point toView:nil] modifierFlags:0
                             timestamp:0 windowNumber:[canvas.window windowNumber] context:nil
                           eventNumber:0 clickCount:1 pressure:1.0];
}

- (void)select:(NSRect)rect on:(ScreenshotCanvasView *)canvas {
    [canvas mouseDown:[self mouse:NSLeftMouseDown at:rect.origin in:canvas]];
    [canvas mouseDragged:[self mouse:NSLeftMouseDragged at:NSMakePoint(NSMaxX(rect), NSMaxY(rect)) in:canvas]];
    [canvas mouseUp:[self mouse:NSLeftMouseUp at:NSMakePoint(NSMaxX(rect), NSMaxY(rect)) in:canvas]];
}

- (NSButton *)button:(NSString *)title {
    for (NSButton *button in _appDelegate.selectionActionBar.buttons) {
        if ([button.title isEqualToString:title]) {
            return button;
        }
    }
    return nil;
}

#pragma mark - Placement

- (void)testItGoesBelowThenAboveThenInside {
    STSelectionActionBar *bar = [[STSelectionActionBar alloc] initWithTarget:self];
    NSSize size = bar.frame.size;
    XCTAssertTrue(size.width > 150.0 && size.height > 20.0, @"Three buttons and some padding");

    // Counting down from the top, as on the canvas.
    STFlippedTestView *host = [[STFlippedTestView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
    [host addSubview:bar];
    NSRect visible = host.bounds;

    NSRect below = [bar frameForSelection:NSMakeRect(200, 50, 200, 100) visible:visible];
    XCTAssertEqualWithAccuracy(NSMinY(below), 158.0, 0.5, @"8 pt below the selection");
    XCTAssertEqualWithAccuracy(NSMidX(below), 300.0, 1.0, @"Centred on it");

    NSRect above = [bar frameForSelection:NSMakeRect(200, 300, 200, 90) visible:visible];
    XCTAssertEqualWithAccuracy(NSMaxY(above), 292.0, 0.5, @"No room below: 8 pt above it");

    NSRect inside = [bar frameForSelection:NSMakeRect(100, 5, 400, 390) visible:visible];
    XCTAssertTrue(NSContainsRect(NSMakeRect(100, 5, 400, 390), inside), @"No room either side: inside its bottom edge");

    NSRect clamped = [bar frameForSelection:NSMakeRect(560, 50, 30, 30) visible:visible];
    XCTAssertTrue(NSMaxX(clamped) <= 592.0, @"Kept 8 pt inside the visible area");

    // And counting up, as in a plain view.
    NSView *plain = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
    [plain addSubview:bar];
    NSRect plainBelow = [bar frameForSelection:NSMakeRect(200, 250, 200, 100) visible:plain.bounds];
    XCTAssertEqualWithAccuracy(NSMaxY(plainBelow), 242.0, 0.5, @"Below on screen whichever way the view counts");
}

#pragma mark - Showing it

- (void)testItShowsForAFinishedSelectionOnly {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithImage];
    STSelectionActionBar *bar = _appDelegate.selectionActionBar;
    XCTAssertTrue(bar == nil || bar.isHidden, @"No selection, no bar");

    [canvas mouseDown:[self mouse:NSLeftMouseDown at:NSMakePoint(100, 50) in:canvas]];
    [canvas mouseDragged:[self mouse:NSLeftMouseDragged at:NSMakePoint(300, 150) in:canvas]];
    XCTAssertTrue(_appDelegate.selectionActionBar.isHidden, @"Hidden while the selection is drawn");
    [canvas mouseUp:[self mouse:NSLeftMouseUp at:NSMakePoint(300, 150) in:canvas]];

    bar = _appDelegate.selectionActionBar;
    XCTAssertFalse(bar.isHidden, @"Shown once it's finished");
    XCTAssertTrue(bar.superview == canvas, @"On the canvas, drawn after it");
    NSArray *titles = [bar.buttons valueForKey:@"title"];
    XCTAssertEqualObjects(titles, (@[@"Crop", @"Copy", @"Redact"]));
    XCTAssertTrue([self button:@"Crop"].target == _appDelegate);
    XCTAssertFalse(NSIntersectsRect(bar.frame, [canvas selectionRectInView]), @"Next to the selection, not over it");
    XCTAssertTrue(NSContainsRect(canvas.bounds, bar.frame), @"On the image");
    NSPoint onBar = NSMakePoint(NSMidX(bar.frame), NSMidY(bar.frame));
    XCTAssertFalse([canvas isPointOnShownCanvas:onBar], @"The pointer over the bar gets the bar's cursor, not the tool's");

    unichar escape = 0x1b;
    NSString *characters = [NSString stringWithCharacters:&escape length:1];
    [canvas keyDown:[NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                                 windowNumber:[canvas.window windowNumber] context:nil
                                   characters:characters charactersIgnoringModifiers:characters
                                    isARepeat:NO keyCode:0]];
    XCTAssertTrue(bar.isHidden, @"Esc clears the selection, and the bar goes with it");
}

- (void)testItsButtonsCropAndRedact {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = [self canvasWithImage];
    [self select:NSMakeRect(100, 50, 200, 100) on:canvas];
    [[self button:@"Redact"] performClick:nil];
    XCTAssertEqual(canvas.strokes.lastObject.type, MarkupStrokeTypeRedact, @"Redact pixelates the selection");
    XCTAssertTrue(_appDelegate.selectionActionBar.isHidden, @"The selection is done with");

    // Away from the redaction, which a press on would pick instead.
    [self select:NSMakeRect(350, 160, 200, 100) on:canvas];
    [[self button:@"Crop"] performClick:nil];
    XCTAssertEqualWithAccuracy(canvas.image.size.width, 200.0, 1.0);
    XCTAssertEqualWithAccuracy(canvas.image.size.height, 100.0, 1.0, @"Crop crops to the selection");
    XCTAssertTrue(_appDelegate.selectionActionBar.isHidden);
}

- (void)testThePreferenceTurnsItOff {
    XCTSkipIf(_shouldSkip, @"No window server");
    XCTAssertTrue([_appDelegate preferencesControllerShouldShowSelectionBar:nil], @"On by default");
    ScreenshotCanvasView *canvas = [self canvasWithImage];
    [self select:NSMakeRect(100, 50, 200, 100) on:canvas];
    XCTAssertFalse(_appDelegate.selectionActionBar.isHidden);

    [_appDelegate preferencesController:nil didToggleSelectionBar:NO];
    XCTAssertTrue(_appDelegate.selectionActionBar.isHidden, @"Off hides it at once");
    XCTAssertFalse([[NSUserDefaults standardUserDefaults] boolForKey:STDefaultsShowSelectionBarKey], @"And is remembered");
    [self select:NSMakeRect(120, 60, 200, 100) on:canvas];
    XCTAssertTrue(_appDelegate.selectionActionBar.isHidden, @"And stays off for new selections");

    [_appDelegate preferencesController:nil didToggleSelectionBar:YES];
    XCTAssertFalse(_appDelegate.selectionActionBar.isHidden);
}

@end
