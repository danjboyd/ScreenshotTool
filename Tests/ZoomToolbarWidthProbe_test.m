/*
 * ZoomToolbarWidthProbe_test.m
 * Verifies the GNUstep zoom toolbar control keeps a stable width.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

#if defined(GNUSTEP)
@interface AppDelegate (ZoomToolbarWidthTesting)
- (void)setupWindowAndContent;
- (NSToolbarItem *)toolbarItemForZoomControl;
- (void)refreshZoomToolbarControl;
- (ScreenshotCanvasView *)canvasView;
- (NSView *)zoomToolbarButtonView;
@end
#endif

@interface ZoomToolbarWidthProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation ZoomToolbarWidthProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        _appDelegate = [[AppDelegate alloc] init];
#if defined(GNUSTEP)
        [_appDelegate setupWindowAndContent];
        [_appDelegate toolbarItemForZoomControl];
#endif
    } @catch (NSException *exception) {
        NSLog(@"Skipping zoom toolbar width test: failed to connect to window server (%@)", exception.reason);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    _appDelegate = nil;
    [super tearDown];
}

- (NSImage *)testImageWithSize:(NSSize)size {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor colorWithCalibratedRed:0.24f green:0.47f blue:0.82f alpha:1.0f] setFill];
    NSRectFill(NSMakeRect(0.0f, 0.0f, size.width, size.height));
    [image unlockFocus];
    return image;
}

- (void)testZoomToolbarWidthRemainsFixedAcrossDisplayedValues {
    if (_shouldSkip) return;
#if !defined(GNUSTEP)
    return;
#else
    ScreenshotCanvasView *canvasView = [_appDelegate canvasView];
    XCTAssertNotNil(canvasView, @"Canvas view should exist");

    NSImage *image = [self testImageWithSize:NSMakeSize(640.0f, 480.0f)];
    [canvasView loadImage:image];
    canvasView.fitToWindow = NO;
    canvasView.zoomScale = 1.0f;
    [_appDelegate refreshZoomToolbarControl];

    CGFloat initialWidth = [_appDelegate zoomToolbarButtonView].frame.size.width;
    XCTAssertGreaterThan(initialWidth, 0.0, @"Zoom toolbar width should be initialized");

    canvasView.zoomScale = 2.52f;
    [_appDelegate refreshZoomToolbarControl];
    CGFloat numericWidth = [_appDelegate zoomToolbarButtonView].frame.size.width;

    canvasView.fitToWindow = YES;
    [_appDelegate refreshZoomToolbarControl];
    CGFloat fitWidth = [_appDelegate zoomToolbarButtonView].frame.size.width;

    XCTAssertEqualWithAccuracy(numericWidth, initialWidth, 0.1f,
                               @"Zoom toolbar width should not expand for wider percentage titles");
    XCTAssertEqualWithAccuracy(fitWidth, initialWidth, 0.1f,
                               @"Zoom toolbar width should remain fixed in fit-to-window mode");
#endif
}

@end
