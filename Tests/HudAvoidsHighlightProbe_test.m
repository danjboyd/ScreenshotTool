/*
 * HudAvoidsHighlightProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The result notice stays off what the redaction highlight is showing. At low zoom a centred
 * notice can hide all of it.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (HudAvoidsHighlightTesting)
- (void)setupWindowAndContent;
- (void)layoutContentSubviews;
- (NSWindow *)window;
- (NSView *)hudView;
- (ScreenshotCanvasView *)canvasView;
- (void)showCommandResultMessage:(NSString *)message duration:(NSTimeInterval)duration;
- (void)hideHUDMessage;
@end

@interface ScreenshotCanvasView (HudAvoidsHighlightTesting)
- (void)showRedactionHighlightInImageRects:(NSArray<NSValue *> *)rects;
- (NSRect)viewRectForImageRect:(NSRect)imageRect;
@end

extern NSRect STHUDFrameAvoidingRects(NSRect centerIn, NSRect area, NSSize size, NSArray<NSValue *> *avoid);

@interface HudAvoidsHighlightProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation HudAvoidsHighlightProbeTests

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
        [_appDelegate.window makeKeyAndOrderFront:nil];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    [_appDelegate hideHUDMessage];
    _appDelegate = nil;
    [super tearDown];
}

- (void)testThePlacesInOrder {
    NSRect window = NSMakeRect(0.0, 0.0, 800.0, 600.0);
    NSRect area = NSMakeRect(0.0, 30.0, 800.0, 500.0);
    NSSize size = NSMakeSize(200.0, 40.0);
    NSRect center = NSMakeRect(300.0, 280.0, 200.0, 40.0);
    NSRect bottom = NSMakeRect(300.0, 46.0, 200.0, 40.0);
    NSRect top = NSMakeRect(300.0, 474.0, 200.0, 40.0);
    NSValue *middle = [NSValue valueWithRect:NSMakeRect(350.0, 290.0, 40.0, 10.0)];
    NSValue *low = [NSValue valueWithRect:NSMakeRect(350.0, 60.0, 40.0, 10.0)];
    NSValue *high = [NSValue valueWithRect:NSMakeRect(350.0, 490.0, 40.0, 10.0)];
    NSValue *aside = [NSValue valueWithRect:NSMakeRect(10.0, 290.0, 40.0, 10.0)];

    XCTAssertTrue(NSEqualRects(STHUDFrameAvoidingRects(window, area, size, @[]), center));
    XCTAssertTrue(NSEqualRects(STHUDFrameAvoidingRects(window, area, size, @[ aside ]), center));
    XCTAssertTrue(NSEqualRects(STHUDFrameAvoidingRects(window, area, size, @[ middle ]), bottom));
    XCTAssertTrue(NSEqualRects(STHUDFrameAvoidingRects(window, area, size, @[ middle, low ]), top));
    XCTAssertTrue(NSEqualRects(STHUDFrameAvoidingRects(window, area, size, @[ middle, low, high ]), center));
}

- (NSImage *)whiteImageOfSize:(NSSize)size {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    [image unlockFocus];
    return image;
}

/// A 4000x3000 capture at 5%, so all of it would sit behind a centred notice.
- (void)testTheNoticeClearsTheHighlightAtLowZoom {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self whiteImageOfSize:NSMakeSize(4000.0, 3000.0)]];
    [_appDelegate layoutContentSubviews];
    canvas.fitToWindow = NO;
    canvas.zoomScale = 0.05;
    [_appDelegate.window displayIfNeeded];
    NSRect item = NSMakeRect(1800.0, 1400.0, 400.0, 200.0);
    [canvas showRedactionHighlightInImageRects:@[ [NSValue valueWithRect:item] ]];

    [_appDelegate showCommandResultMessage:@"Redacted 1 item" duration:1.0];

    NSView *hud = _appDelegate.hudView;
    XCTAssertFalse(canvas.isHiddenOrHasHiddenAncestor, @"The highlighted canvas must be visible");
    XCTAssertTrue(hud.window.isVisible, @"The HUD must be visible for the overlap check");
    NSRect hudRect = [hud.superview convertRect:hud.frame toView:nil];
    NSRect itemRect = [canvas convertRect:[canvas viewRectForImageRect:item] toView:nil];
#if !defined(GNUSTEP)
    // The Cocoa HUD is a child window, so compare both rectangles in screen coordinates.
    hudRect = [hud.window convertRectToScreen:hudRect];
    itemRect = [canvas.window convertRectToScreen:itemRect];
#endif
    XCTAssertFalse(NSIntersectsRect(hudRect, itemRect), @"notice %@ item %@", NSStringFromRect(hudRect), NSStringFromRect(itemRect));
}

/// Nothing highlighted, the notice stays in the middle of the window.
- (void)testTheNoticeStaysCentredWithNoHighlight {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_appDelegate showCommandResultMessage:@"Copied image to clipboard" duration:1.0];
    NSView *hud = _appDelegate.hudView;
    XCTAssertEqualWithAccuracy(NSMidX(hud.frame), NSMidX(hud.superview.bounds), 1.0);
    XCTAssertEqualWithAccuracy(NSMidY(hud.frame), NSMidY(hud.superview.bounds), 1.0);
}

@end
