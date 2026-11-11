#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"

#if !defined(GNUSTEP)
@interface AppDelegate (SharePrintSelectionProbe)
- (NSSharingService *)printSharingService;
- (ScreenshotCanvasView *)canvasView;
@end

@interface STSelectionFlagCanvas : NSObject
@property (nonatomic) BOOL selected;
- (BOOL)hasSelection;
@end
@implementation STSelectionFlagCanvas
- (BOOL)hasSelection { return self.selected; }
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
@end
#endif
