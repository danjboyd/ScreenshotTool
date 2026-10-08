/*
 * MultiWindowProbe_test.m
 * On macOS each document gets a window of its own (AppDelegate's Windows section); GNUstep keeps
 * one window per process, so there's nothing to test there.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

#if !defined(GNUSTEP)

@interface AppDelegate (MultiWindowTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
- (NSMutableArray<AppDelegate *> *)documentWindows;
- (void)setDocumentRouter:(id)router;
- (id)documentRouter;
- (BOOL)openURLInDocumentWindow:(NSURL *)url preferring:(AppDelegate *)preferred;
- (AppDelegate *)makeDocumentWindow;
@end

@interface MultiWindowProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_application;
    NSString *_directory;
}
@end

@implementation MultiWindowProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:NULL];
    @try {
        [NSApplication sharedApplication];
        // Other classes' windows mustn't count as the front document.
        for (NSWindow *window in [NSApp windows]) {
            [window orderOut:nil];
        }
        _application = [[AppDelegate alloc] init];
        [_application setupWindowAndContent];
        [_application.window orderFront:nil];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    for (AppDelegate *document in [_application.documentWindows copy]) {
        [document.window orderOut:nil];
    }
    [_application.window orderOut:nil];
    _application = nil;
    [[NSFileManager defaultManager] removeItemAtPath:_directory error:NULL];
    [super tearDown];
}

- (NSURL *)imageNamed:(NSString *)name {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:60 pixelsHigh:40
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                      isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:0];
    NSURL *url = [NSURL fileURLWithPath:[_directory stringByAppendingPathComponent:name]];
    [[rep representationUsingType:NSPNGFileType properties:@{}] writeToURL:url atomically:YES];
    return url;
}

- (void)spinRunLoop {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

/// Runs the run loop until `done`, for up to two seconds: a window's first close can keep it busy
/// for longer than a fixed wait.
- (void)spinRunLoopUntil:(BOOL (^)(void))done {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (!done() && [deadline timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
    }
}

- (void)testOpenFillsAnEmptyWindowThenOpensNewOnes {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSURL *first = [self imageNamed:@"first.png"];
    NSURL *second = [self imageNamed:@"second.png"];

    XCTAssertTrue([_application openURLInDocumentWindow:first preferring:_application]);
    XCTAssertTrue([_application.canvasView hasImage], @"the empty window takes the first image");
    XCTAssertEqual(_application.documentWindows.count, (NSUInteger)0);

    XCTAssertTrue([_application openURLInDocumentWindow:second preferring:_application]);
    XCTAssertEqual(_application.documentWindows.count, (NSUInteger)1, @"the next image gets a window of its own");
    AppDelegate *document = _application.documentWindows.firstObject;
    XCTAssertTrue([document.canvasView hasImage]);
    XCTAssertTrue(document.window.isVisible);
    XCTAssertNotEqual(document.window, _application.window);

    XCTAssertTrue([_application openURLInDocumentWindow:first preferring:nil]);
    XCTAssertEqual(_application.documentWindows.count, (NSUInteger)1, @"an image that's open isn't opened again");
}

- (void)testRouterSendsCommandsToTheFrontWindow {
    XCTSkipIf(_shouldSkip, @"No window server");
    Class routerClass = NSClassFromString(@"STDocumentRouter");
    XCTAssertNotNil(routerClass);
    id router = [[routerClass alloc] init];
    AppDelegate *document = [_application makeDocumentWindow];
    [document.window orderFront:nil];
    [self spinRunLoop];

    XCTAssertTrue([router respondsToSelector:@selector(zoomIn:)], @"it handles what a document handles");
    XCTAssertEqual([router forwardingTargetForSelector:@selector(zoomIn:)], document, @"the front window's controller");

    [_application.window orderFront:nil];
    [self spinRunLoop];
    XCTAssertEqual([router forwardingTargetForSelector:@selector(zoomIn:)], _application);
}

- (void)testClosingADocumentWindowReleasesItsController {
    XCTSkipIf(_shouldSkip, @"No window server");
    id previousDelegate = NSApp.delegate;
    NSApp.delegate = (id<NSApplicationDelegate>)_application;
    __weak AppDelegate *weakDocument = nil;
    @autoreleasepool {
        AppDelegate *document = [_application makeDocumentWindow];
        weakDocument = document;
        [document.window orderFront:nil];
        XCTAssertEqual(_application.documentWindows.count, (NSUInteger)1);
        [document.window close];
    }
    AppDelegate *application = _application;
    [self spinRunLoopUntil:^BOOL{ return application.documentWindows.count == 0; }];
    XCTAssertEqual(_application.documentWindows.count, (NSUInteger)0, @"a closed window's controller goes");
    [self spinRunLoopUntil:^BOOL{ return weakDocument == nil; }];
    XCTAssertNil(weakDocument, @"and is released");

    [_application.window close];
    [self spinRunLoop];
    XCTAssertNotNil(_application.window, @"the application delegate's own window stays, for reuse");
    NSApp.delegate = previousDelegate;
}

@end

#endif
