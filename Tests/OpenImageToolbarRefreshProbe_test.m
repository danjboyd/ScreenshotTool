/*
 * OpenImageToolbarRefreshProbe_test.m
 * Verifies successful opens refresh toolbar button enabled state.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (OpenImageToolbarRefreshTesting)
- (BOOL)openImageAtURL:(NSURL *)url;
@end

@interface OpenImageToolbarRefreshProbeAppDelegate : AppDelegate
@property (nonatomic, assign) NSInteger refreshToolButtonIconsCallCount;
@end

@implementation OpenImageToolbarRefreshProbeAppDelegate

- (void)refreshToolButtonIcons {
    self.refreshToolButtonIconsCallCount += 1;
}

- (void)addRecentDocumentURL:(NSURL *)url {
    (void)url;
}

- (void)resizeWindowToImageSize:(NSSize)imageSize {
    (void)imageSize;
}

- (void)reflectZoomSelection {
}

@end

@interface OpenImageToolbarRefreshProbeTests : XCTestCase {
    OpenImageToolbarRefreshProbeAppDelegate *_appDelegate;
    NSString *_tempRoot;
}
@end

@implementation OpenImageToolbarRefreshProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];

    _tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSError *error = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:_tempRoot
                                             withIntermediateDirectories:YES
                                                              attributes:nil
                                                                   error:&error];
    XCTAssertTrue(created, @"Failed to create temp root: %@", error);

    _appDelegate = [[OpenImageToolbarRefreshProbeAppDelegate alloc] init];
    ScreenshotCanvasView *canvasView = [[ScreenshotCanvasView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 32.0f, 32.0f)];
    [_appDelegate setValue:canvasView forKey:@"canvasView"];
}

- (void)tearDown {
    if (_tempRoot.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:_tempRoot error:NULL];
    }
    _appDelegate = nil;
    [super tearDown];
}

- (NSString *)writeProbeImage {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                        pixelsWide:1
                                                                        pixelsHigh:1
                                                                     bitsPerSample:8
                                                                   samplesPerPixel:4
                                                                          hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:0
                                                                      bitsPerPixel:0];
    XCTAssertNotNil(bitmap);

    unsigned char *data = [bitmap bitmapData];
    XCTAssertTrue(data != NULL, @"Bitmap data should be allocated");
    data[0] = 255;
    data[1] = 0;
    data[2] = 0;
    data[3] = 255;

    NSData *pngData = [bitmap representationUsingType:NSPNGFileType properties:@{}];
    XCTAssertNotNil(pngData);

    NSString *path = [_tempRoot stringByAppendingPathComponent:@"probe.png"];
    NSError *error = nil;
    BOOL wrote = [pngData writeToFile:path options:NSDataWritingAtomic error:&error];
    XCTAssertTrue(wrote, @"Failed to write probe image: %@", error);
    return path;
}

- (void)testSuccessfulOpenRefreshesToolbarButtons {
    NSString *path = [self writeProbeImage];

    BOOL opened = [_appDelegate openImageAtURL:[NSURL fileURLWithPath:path]];

    XCTAssertTrue(opened, @"Probe image should open successfully");
    XCTAssertEqual(_appDelegate.refreshToolButtonIconsCallCount, 1, @"Successful open should refresh toolbar button state");

    ScreenshotCanvasView *canvasView = [_appDelegate valueForKey:@"canvasView"];
    XCTAssertTrue([canvasView hasImage], @"Canvas should hold the opened image");
}

@end
