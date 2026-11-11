/* Test-only, offscreen probe for the exact 0.4 toolbar hit geometry. */
#if !defined(GNUSTEP)
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"

static void STTrackedClick(NSSegmentedControl *control, NSEvent *down) {
    NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                                    location:down.locationInWindow
                               modifierFlags:0 timestamp:0.01
                                windowNumber:down.windowNumber context:nil
                                 eventNumber:1 clickCount:down.clickCount pressure:0];
    [NSApp postEvent:up atStart:YES];
    [control mouseDown:down];
}

@interface AppDelegate (ToolbarHitGeometryProbe)
- (NSToolbarItem *)toolbarItemForToolControl;
- (void)toolbarToolControlAction:(id)sender;
@end

@interface STToolbarProbeAppDelegate : AppDelegate
@property (nonatomic) ScreenshotCanvasTool selectedToolForProbe;
@property (nonatomic) ScreenshotCanvasTool popoverToolForProbe;
@property (nonatomic) NSRect popoverAnchorForProbe;
@property (nonatomic) NSInteger popoverCountForProbe;
@end

@implementation STToolbarProbeAppDelegate
- (void)selectTool:(ScreenshotCanvasTool)tool {
    self.selectedToolForProbe = tool;
}
- (void)showToolSettingsPopoverForTool:(ScreenshotCanvasTool)tool
                            anchorRect:(NSRect)anchor
                                ofView:(NSView *)view
                                 event:(NSEvent *)event {
    (void)event;
    self.popoverToolForProbe = tool;
    self.popoverAnchorForProbe = [view convertRect:anchor toView:nil];
    self.popoverCountForProbe++;
}
@end

@interface STToolbarHitRecorder : NSObject
@property (nonatomic) NSInteger hit;
@property (nonatomic) NSInteger calls;
@property (nonatomic) NSInteger clickCount;
- (void)clicked:(id)sender;
@end

@implementation STToolbarHitRecorder
- (void)clicked:(id)sender {
    NSInteger clicked = [[sender valueForKey:@"clickedSegment"] integerValue];
    self.hit = clicked >= 0 ? clicked : [sender selectedSegment];
    self.clickCount = [[sender valueForKey:@"lastClickCount"] integerValue];
    self.calls++;
}
@end

@interface ToolbarHitGeometryProbeTests : XCTestCase
@end

@implementation ToolbarHitGeometryProbeTests

- (void)testActualControlOffscreenHitGeometry {
    [NSApplication sharedApplication];
    STToolbarProbeAppDelegate *delegate = [[STToolbarProbeAppDelegate alloc] init];
    NSToolbarItem *item = [delegate toolbarItemForToolControl];
    NSSegmentedControl *control = (NSSegmentedControl *)item.view;
    XCTAssertNotNil(control);
    XCTAssertEqual(control.segmentCount, 9);

    // The window is never ordered front. It supplies the real view-to-window transform.
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 120)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 700, 120)];
    window.contentView = container;
    [delegate setValue:window forKey:@"window"];
    [container addSubview:control];
    STToolbarHitRecorder *recorder = [[STToolbarHitRecorder alloc] init];
    control.target = recorder;
    control.action = @selector(clicked:);
    control.enabled = YES;
    for (NSInteger segment = 0; segment < control.segmentCount; segment++) {
        [control setEnabled:YES forSegment:segment];
    }

    NSInteger axMismatchCount = 0;
    for (NSNumber *offset in @[@0.0, @31.0]) {
        control.frame = NSMakeRect(offset.doubleValue, 19, 414, 32);
        CGFloat cellX = 0;
        NSMutableArray<NSValue *> *logicalRects = [NSMutableArray array];
        for (NSInteger segment = 0; segment < control.segmentCount; segment++) {
            CGFloat width = [control widthForSegment:segment];
            XCTAssertEqualWithAccuracy(width, 46, 0.001);
            [logicalRects addObject:[NSValue valueWithRect:NSMakeRect(cellX, 0, width, control.bounds.size.height)]];
            cellX += width;
        }
        XCTAssertEqualWithAccuracy(cellX, control.bounds.size.width, 0.001);
        NSArray *segments = control.cell.accessibilityChildren;
        XCTAssertEqual(segments.count, 9);
        for (NSInteger segment = 0; segment < segments.count; segment++) {
            id child = segments[segment];
            NSRect axFrame = [child accessibilityFrame];
            NSRect handlerScreenFrame = [window convertRectToScreen:
                [control convertRect:logicalRects[segment].rectValue toView:nil]];
            NSLog(@"toolbar-ax-vs-handler offset=%.1f segment=%ld ax=%@ handlerScreen=%@",
                  offset.doubleValue, (long)segment,
                  NSStringFromRect(axFrame), NSStringFromRect(handlerScreenFrame));
            for (NSNumber *fraction in @[@0.02, @0.5, @0.98]) {
                NSPoint screenPoint = NSMakePoint(NSMinX(axFrame) + NSWidth(axFrame) * fraction.doubleValue,
                                                 NSMidY(axFrame));
                NSPoint windowPoint = [window convertPointFromScreen:screenPoint];
                NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                                   location:windowPoint modifierFlags:0 timestamp:0
                                               windowNumber:window.windowNumber context:nil
                                                eventNumber:0 clickCount:1 pressure:1];
                recorder.hit = -99;
                STTrackedClick(control, event);
                NSPoint localPoint = [control convertPoint:windowPoint fromView:nil];
                BOOL insideControl = NSPointInRect(localPoint, control.bounds);
                if (insideControl) {
                    XCTAssertEqual(recorder.hit, segment);
                    if (recorder.hit != segment) axMismatchCount++;
                } else {
                    XCTAssertEqual(recorder.hit, -99);
                }
                NSLog(@"toolbar-ax-hit offset=%.1f segment=%ld fraction=%.2f screenX=%.2f hit=%ld",
                      offset.doubleValue, (long)segment, fraction.doubleValue,
                      screenPoint.x, (long)recorder.hit);
            }
        }
        for (NSInteger segment = 0; segment < control.segmentCount; segment++) {
            NSRect rect = logicalRects[segment].rectValue;
            for (NSNumber *fraction in @[@0.05, @0.5, @0.95]) {
                NSPoint local = NSMakePoint(NSMinX(rect) + NSWidth(rect) * fraction.doubleValue,
                                           NSMidY(rect));
                NSPoint inWindow = [control convertPoint:local toView:nil];
                NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                                   location:inWindow
                                              modifierFlags:0 timestamp:0
                                               windowNumber:window.windowNumber
                                                    context:nil eventNumber:0
                                                 clickCount:1 pressure:1];
                NSInteger oldCalls = recorder.calls;
                STTrackedClick(control, event);
                NSLog(@"toolbar-nominal-hit offset=%.1f segment=%ld fraction=%.2f callsDelta=%ld hit=%ld",
                      offset.doubleValue, (long)segment, fraction.doubleValue,
                      (long)(recorder.calls - oldCalls), (long)recorder.hit);
                NSLog(@"toolbar-hit offset=%.1f segment=%ld fraction=%.2f local=%.2f window=%.2f hit=%ld",
                      offset.doubleValue, (long)segment, fraction.doubleValue,
                      local.x, inWindow.x, (long)recorder.hit);
            }
        }
        NSLog(@"toolbar-geometry os=%@ scale=%.2f frame=%@ bounds=%@ widths=%@ axChildren=%@",
              [NSProcessInfo processInfo].operatingSystemVersionString,
              window.backingScaleFactor, NSStringFromRect(control.frame),
              NSStringFromRect(control.bounds),
              [logicalRects valueForKey:@"description"], control.accessibilityChildren);
        for (NSInteger segment = 1; segment < control.segmentCount; segment++) {
            CGFloat edge = NSMinX(logicalRects[segment].rectValue);
            for (NSNumber *side in @[@-0.01, @0.01]) {
                NSPoint inWindow = [control convertPoint:NSMakePoint(edge + side.doubleValue, 16) toView:nil];
                NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                                   location:inWindow modifierFlags:0 timestamp:0
                                               windowNumber:window.windowNumber context:nil
                                                eventNumber:0 clickCount:1 pressure:1];
                STTrackedClick(control, event);
                NSLog(@"toolbar-boundary-hit offset=%.1f edge=%ld side=%.2f hit=%ld",
                      offset.doubleValue, (long)segment, side.doubleValue, (long)recorder.hit);
            }
        }
    }
    NSLog(@"toolbar-ax-hit inBoundsMismatchCount=%ld of 50", (long)axMismatchCount);
    XCTAssertEqual(axMismatchCount, 0);

    NSRect disabledAX = [control.cell.accessibilityChildren[4] accessibilityFrame];
    NSPoint disabledInWindow = [window convertPointFromScreen:
        NSMakePoint(NSMidX(disabledAX), NSMidY(disabledAX))];
    NSEvent *disabledDown = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                             location:disabledInWindow modifierFlags:0 timestamp:0
                                         windowNumber:window.windowNumber context:nil
                                          eventNumber:0 clickCount:1 pressure:1];
    [control setEnabled:NO forSegment:4];
    NSInteger callsBeforeDisabled = recorder.calls;
    NSInteger selectedBeforeDisabled = control.selectedSegment;
    STTrackedClick(control, disabledDown);
    XCTAssertEqual(recorder.calls, callsBeforeDisabled);
    XCTAssertEqual(control.selectedSegment, selectedBeforeDisabled);
    NSInteger disabledCallsDelta = recorder.calls - callsBeforeDisabled;
    [control setEnabled:YES forSegment:4];

    NSRect doubleAX = [control.cell.accessibilityChildren[2] accessibilityFrame];
    NSPoint doubleInWindow = [window convertPointFromScreen:
        NSMakePoint(NSMidX(doubleAX), NSMidY(doubleAX))];
    NSEvent *doubleDown = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                           location:doubleInWindow modifierFlags:0 timestamp:0
                                       windowNumber:window.windowNumber context:nil
                                        eventNumber:0 clickCount:2 pressure:1];
    NSInteger callsBeforeDouble = recorder.calls;
    STTrackedClick(control, doubleDown);
    XCTAssertEqual(recorder.calls, callsBeforeDouble + 1);
    XCTAssertEqual(recorder.hit, 2);
    XCTAssertEqual(recorder.clickCount, 2);
    NSLog(@"toolbar-double-click hit=%ld count=%ld disabledCallsDelta=%ld",
          (long)recorder.hit, (long)recorder.clickCount,
          (long)disabledCallsDelta);
    control.target = delegate;
    control.action = @selector(toolbarToolControlAction:);
    NSArray<NSNumber *> *expectedTools = @[
        @(ScreenshotCanvasToolSelect), @(ScreenshotCanvasToolHighlighter),
        @(ScreenshotCanvasToolPen), @(ScreenshotCanvasToolArrow),
        @(ScreenshotCanvasToolRectangle), @(ScreenshotCanvasToolText),
        @(ScreenshotCanvasToolStep), @(ScreenshotCanvasToolRedact),
        @(ScreenshotCanvasToolEraser)
    ];
    for (NSInteger segment = 0; segment < control.segmentCount; segment++) {
        NSRect ax = [control.cell.accessibilityChildren[segment] accessibilityFrame];
        NSPoint point = [window convertPointFromScreen:NSMakePoint(NSMidX(ax), NSMidY(ax))];
        NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                         location:point modifierFlags:0 timestamp:0
                                     windowNumber:window.windowNumber context:nil
                                      eventNumber:0 clickCount:1 pressure:1];
        STTrackedClick(control, down);
        XCTAssertEqual(delegate.selectedToolForProbe, expectedTools[segment].integerValue);
        XCTAssertEqual(delegate.popoverCountForProbe, 0);
    }
    STTrackedClick(control, doubleDown);
    XCTAssertEqual(delegate.selectedToolForProbe, ScreenshotCanvasToolPen);
    XCTAssertEqual(delegate.popoverToolForProbe, ScreenshotCanvasToolPen);
    XCTAssertEqual(delegate.popoverCountForProbe, 1);
    NSRect anchorOnScreen = [window convertRectToScreen:delegate.popoverAnchorForProbe];
    XCTAssertTrue(NSMidX(anchorOnScreen) >= NSMinX(doubleAX));
    XCTAssertTrue(NSMidX(anchorOnScreen) < NSMaxX(doubleAX));
    XCTAssertEqualWithAccuracy(NSMinY(anchorOnScreen), NSMaxY(doubleAX), 0.01);
    NSLog(@"toolbar-popover anchorScreen=%@ selectedTool=%ld count=%ld",
          NSStringFromRect(anchorOnScreen), (long)delegate.selectedToolForProbe,
          (long)delegate.popoverCountForProbe);
    NSLog(@"toolbar-probe assertions complete; unordered window remains local until test exit");
}
@end
#endif // !defined(GNUSTEP)
