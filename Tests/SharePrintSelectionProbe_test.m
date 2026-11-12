#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"

#if !defined(GNUSTEP)
@interface AppDelegate (SharePrintSelectionProbe)
- (NSSharingService *)printSharingService;
- (ScreenshotCanvasView *)canvasView;
- (void)printSelection:(id)sender;
@end

@interface STSelectionFlagCanvas : NSObject
@property (nonatomic) BOOL selected;
@property (nonatomic) NSRect selectionRect;
@property (nonatomic, strong) NSImage *image;
@property (nonatomic) NSUInteger flattenCount;
- (BOOL)hasSelection;
- (NSRect)selectionImageRect;
- (NSImage *)flattenedImage;
@end
@implementation STSelectionFlagCanvas
- (BOOL)hasSelection { return self.selected; }
- (NSRect)selectionImageRect { return self.selectionRect; }
- (NSImage *)flattenedImage { self.flattenCount++; return self.image; }
@end

@interface STSharePrintRecorder : AppDelegate
@property (nonatomic, strong) STSelectionFlagCanvas *flagCanvas;
@property (nonatomic) NSUInteger wholeRequests;
@property (nonatomic) NSUInteger selectionRequests;
@end
@implementation STSharePrintRecorder
- (ScreenshotCanvasView *)canvasView { return (ScreenshotCanvasView *)self.flagCanvas; }
- (void)printDocument:(id)sender { (void)sender; self.wholeRequests++; }
- (void)printSelection:(id)sender { (void)sender; self.selectionRequests++; }
@end

@interface STUnavailablePrintRecorder : AppDelegate
@property (nonatomic, strong) STSelectionFlagCanvas *flagCanvas;
@property (nonatomic) NSUInteger beepCount;
@property (nonatomic) NSUInteger wholeRequests;
@property (nonatomic, copy) NSString *feedback;
@property (nonatomic) NSTimeInterval feedbackDuration;
@end
@implementation STUnavailablePrintRecorder
- (ScreenshotCanvasView *)canvasView { return (ScreenshotCanvasView *)self.flagCanvas; }
- (void)beepForUnavailablePrintSelection { self.beepCount++; }
- (void)showTransientFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration {
    self.feedback = message;
    self.feedbackDuration = duration;
}
- (void)printDocument:(id)sender { (void)sender; self.wholeRequests++; }
@end

@interface SharePrintSelectionProbeTests : XCTestCase
@end
@implementation SharePrintSelectionProbeTests

- (STSharePrintRecorder *)recorder {
    STSharePrintRecorder *recorder = [[STSharePrintRecorder alloc] init];
    recorder.flagCanvas = [[STSelectionFlagCanvas alloc] init];
    return recorder;
}

- (void)perform:(NSSharingService *)service {
    [service performWithItems:@[]];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

- (void)testSelectionDisappearsBeforeSharePrintDoesNotRouteToWholeImage {
    STSharePrintRecorder *app = [self recorder];
    app.flagCanvas.selected = YES;
    NSSharingService *service = [app printSharingService];
    app.flagCanvas.selected = NO;
    [self perform:service];
    XCTAssertEqual(app.selectionRequests, (NSUInteger)1);
    XCTAssertEqual(app.wholeRequests, (NSUInteger)0);
}

- (void)testCancelledPickerReentryUsesCurrentSelectionIntent {
    STSharePrintRecorder *app = [self recorder];
    app.flagCanvas.selected = YES;
    __unused NSSharingService *cancelled = [app printSharingService];
    app.flagCanvas.selected = NO;
    NSSharingService *reopened = [app printSharingService];
    [self perform:reopened];
    XCTAssertEqual(app.selectionRequests, (NSUInteger)0);
    XCTAssertEqual(app.wholeRequests, (NSUInteger)1);
}

- (STUnavailablePrintRecorder *)unavailableRecorder {
    STUnavailablePrintRecorder *recorder = [[STUnavailablePrintRecorder alloc] init];
    recorder.flagCanvas = [[STSelectionFlagCanvas alloc] init];
    return recorder;
}

- (void)assertUnavailableFeedback:(STUnavailablePrintRecorder *)app {
    XCTAssertEqual(app.beepCount, (NSUInteger)1);
    XCTAssertEqualObjects(app.feedback, @"Nothing selected to print");
    XCTAssertEqualWithAccuracy(app.feedbackDuration, 2.0, 0.001);
    XCTAssertEqual(app.wholeRequests, (NSUInteger)0);
}

- (void)testDirectPrintSelectionWithNoSelectionShowsFeedbackBeforeFlattening {
    STUnavailablePrintRecorder *app = [self unavailableRecorder];
    [app printSelection:nil];
    [self assertUnavailableFeedback:app];
    XCTAssertEqual(app.flagCanvas.flattenCount, (NSUInteger)0);
}

- (void)testOutOfBoundsPrintSelectionShowsFeedback {
    STUnavailablePrintRecorder *app = [self unavailableRecorder];
    app.flagCanvas.selected = YES;
    app.flagCanvas.selectionRect = NSMakeRect(100, 100, 10, 10);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:20
                                                                  bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(40, 20)];
    [image addRepresentation:rep];
    app.flagCanvas.image = image;
    [app printSelection:nil];
    [self assertUnavailableFeedback:app];
    XCTAssertEqual(app.flagCanvas.flattenCount, (NSUInteger)1);
}

- (void)testSharePrintSelectionDisappearsShowsFeedbackWithoutWholePrint {
    STUnavailablePrintRecorder *app = [self unavailableRecorder];
    app.flagCanvas.selected = YES;
    NSSharingService *service = [app printSharingService];
    app.flagCanvas.selected = NO;
    [self perform:service];
    [self assertUnavailableFeedback:app];
    XCTAssertEqual(app.flagCanvas.flattenCount, (NSUInteger)0);
}
@end
#endif
