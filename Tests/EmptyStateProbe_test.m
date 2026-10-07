/*
 * EmptyStateProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * With no image open the window shows an empty state (icon, "No Image", Open… and Paste) in the
 * canvas's place; opening an image brings the canvas back (#55).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"
#import <objc/runtime.h>

@interface AppDelegate (EmptyStateTesting)
- (void)setupWindowAndContent;
- (void)layoutContentSubviews;
- (NSScrollView *)scrollView;
- (NSView *)emptyStateView;
- (ScreenshotCanvasView *)canvasView;
- (BOOL)openImageAtURL:(NSURL *)url;
@end

@interface EmptyStateProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation EmptyStateProbeTests

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

- (NSButton *)buttonTitled:(NSString *)title {
    for (NSView *view in _appDelegate.emptyStateView.subviews) {
        if ([view isKindOfClass:[NSButton class]] && [[(NSButton *)view title] isEqualToString:title]) {
            return (NSButton *)view;
        }
    }
    return nil;
}

- (void)testEmptyStateWithoutAnImage {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_appDelegate layoutContentSubviews];
    XCTAssertFalse([_appDelegate.canvasView hasImage]);
    XCTAssertFalse(_appDelegate.emptyStateView.isHidden, @"the empty state shows");
    XCTAssertTrue(_appDelegate.scrollView.isHidden, @"no blank canvas or empty scroller behind it");
    XCTAssertTrue(NSEqualRects(_appDelegate.emptyStateView.frame, _appDelegate.scrollView.frame), @"in the canvas's place");

    NSButton *open = [self buttonTitled:@"Open…"];
    NSButton *paste = [self buttonTitled:@"Paste"];
    XCTAssertTrue(sel_isEqual(open.action, @selector(openDocument:)));
    XCTAssertTrue(sel_isEqual(paste.action, @selector(pasteAsNewImage:)));
    XCTAssertEqual(open.target, _appDelegate);
    XCTAssertTrue(NSContainsRect(_appDelegate.emptyStateView.bounds, open.frame), @"the buttons are inside the view");
    XCTAssertTrue(NSContainsRect(_appDelegate.emptyStateView.bounds, paste.frame));
}

- (void)testOpeningAnImageShowsTheCanvas {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:30
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"empty-state-%@.png", [[NSUUID UUID] UUIDString]]];
    [[rep representationUsingType:NSPNGFileType properties:@{}] writeToFile:path atomically:YES];
    XCTAssertTrue([_appDelegate openImageAtURL:[NSURL fileURLWithPath:path]]);
    XCTAssertTrue(_appDelegate.emptyStateView.isHidden);
    XCTAssertFalse(_appDelegate.scrollView.isHidden);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

@end
