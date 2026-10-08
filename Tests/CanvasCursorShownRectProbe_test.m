/*
 * CanvasCursorShownRectProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The canvas is a scroll view's document view, so its bounds run on past what the clip view
 * shows: above it, too, once the text bar's row has scrolled the image down. The pointer counts
 * as over the canvas only in the part on screen; otherwise the crosshair stayed over the text bar
 * and the header bar after the pointer left the canvas.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

@interface ScreenshotCanvasView (ShownRectTesting)
- (BOOL)mouseInsideCanvas;
- (void)setMouseInsideCanvas:(BOOL)inside;
- (BOOL)isPointOnShownCanvas:(NSPoint)viewPoint;
@end

@interface CanvasCursorShownRectProbeTests : XCTestCase {
    BOOL _shouldSkip;
    NSWindow *_window;
    NSScrollView *_scrollView;
    ScreenshotCanvasView *_canvas;
}
@end

@implementation CanvasCursorShownRectProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        // A 400x300 window: a 260 high scroll view at the bottom, a 40 high bar above it (as the
        // text bar's row), and a canvas much taller than the scroll view.
        _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                              styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
        _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 260)];
        _canvas = [[ScreenshotCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 400, 800)];
        [_scrollView setDocumentView:_canvas];
        [[_window contentView] addSubview:_scrollView];
        NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(0, 260, 400, 40)];
        [[_window contentView] addSubview:bar];
        // Scroll to the middle: part of the canvas is above the clip view, part below.
        [[_scrollView contentView] scrollToPoint:NSMakePoint(0, 270)];
        [_scrollView reflectScrolledClipView:[_scrollView contentView]];
        [_window orderFront:nil];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    [_window orderOut:nil];
    _window = nil;
    [super tearDown];
}

- (NSEvent *)movedTo:(NSPoint)windowPoint {
    return [NSEvent mouseEventWithType:NSEventTypeMouseMoved
                              location:windowPoint
                         modifierFlags:0
                             timestamp:0
                          windowNumber:[_window windowNumber]
                               context:nil
                           eventNumber:0
                            clickCount:0
                              pressure:0.0];
}

- (void)testOnlyThePartOnScreenCounts {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSRect shown = [_canvas visibleRect];
    XCTAssertGreaterThan(NSHeight(shown), 0.0, @"part of the canvas is on screen: %@", NSStringFromRect(shown));
    XCTAssertLessThan(NSHeight(shown), NSHeight(_canvas.bounds), @"the canvas runs on past the clip view");

    // Points in the content view (the theme may draw a title bar inside the window's frame).
    NSView *content = [_window contentView];
    NSPoint overBar = [_canvas convertPoint:[content convertPoint:NSMakePoint(200, 280) toView:nil] fromView:nil];
    NSPoint inClip = [_canvas convertPoint:[content convertPoint:NSMakePoint(200, 130) toView:nil] fromView:nil];
    XCTAssertTrue(NSMouseInRect(overBar, _canvas.bounds, _canvas.isFlipped),
                  @"over the bar is in the canvas's bounds (the case that went wrong)");
    XCTAssertFalse([_canvas isPointOnShownCanvas:overBar], @"but the pointer there isn't on the canvas");
    XCTAssertTrue([_canvas isPointOnShownCanvas:inClip], @"in the clip view, it is");
}

/// Moving over the bar from the canvas leaves it, whatever the pointer's position (the moved
/// event and the re-check after it agree, as the pointer isn't over the window in a test run).
- (void)testMovingOverTheBarLeavesTheCanvas {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSView *content = [_window contentView];
    _canvas.mouseInsideCanvas = YES;
    [_canvas mouseMoved:[self movedTo:[content convertPoint:NSMakePoint(200, 280) toView:nil]]];
    XCTAssertFalse(_canvas.mouseInsideCanvas, @"over the bar, the pointer isn't on the canvas");
}

@end
