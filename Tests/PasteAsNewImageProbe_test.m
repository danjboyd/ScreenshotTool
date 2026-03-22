/*
 * PasteAsNewImageProbe_test.m
 * Verifies clipboard images open in a new ScreenshotTool window.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (PasteAsNewImageTesting)
- (void)pasteAsNewImage:(id)sender;
- (NSData *)clipboardPNGDataForPasteAsNewImage;
- (BOOL)launchNewWindowForImageAtURL:(NSURL *)url;
- (void)showTransientFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration;
@end

@interface PasteAsNewImageProbeAppDelegate : AppDelegate
@property (nonatomic, strong) NSData *probeClipboardPNGData;
@property (nonatomic, strong) NSURL *launchedImageURL;
@property (nonatomic, copy) NSString *lastTransientFeedbackMessage;
@end

@implementation PasteAsNewImageProbeAppDelegate

- (NSData *)clipboardPNGDataForPasteAsNewImage {
    return self.probeClipboardPNGData;
}

- (BOOL)launchNewWindowForImageAtURL:(NSURL *)url {
    self.launchedImageURL = url;
    return YES;
}

- (void)showTransientFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration {
    (void)duration;
    self.lastTransientFeedbackMessage = [message copy];
}

@end

@interface PasteAsNewImageProbeTests : XCTestCase {
    PasteAsNewImageProbeAppDelegate *_appDelegate;
}
@end

@implementation PasteAsNewImageProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
    _appDelegate = [[PasteAsNewImageProbeAppDelegate alloc] init];
}

- (void)tearDown {
    if (_appDelegate.launchedImageURL.path.length > 0) {
        [[NSFileManager defaultManager] removeItemAtURL:_appDelegate.launchedImageURL error:NULL];
    }
    _appDelegate = nil;
    [super tearDown];
}

- (NSData *)onePixelPNGData {
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
    data[0] = 12;
    data[1] = 34;
    data[2] = 56;
    data[3] = 255;

    NSData *pngData = [bitmap representationUsingType:NSPNGFileType properties:@{}];
    XCTAssertNotNil(pngData);
    return pngData;
}

- (void)testPasteAsNewImageWritesTemporaryPNGAndLaunchesNewWindow {
    NSData *pngData = [self onePixelPNGData];
    _appDelegate.probeClipboardPNGData = pngData;

    [_appDelegate pasteAsNewImage:nil];

    XCTAssertNotNil(_appDelegate.launchedImageURL, @"Paste as New Image should launch a new window");
    XCTAssertEqualObjects(_appDelegate.launchedImageURL.pathExtension.lowercaseString, @"png");
    NSData *writtenData = [NSData dataWithContentsOfURL:_appDelegate.launchedImageURL];
    XCTAssertEqualObjects(writtenData, pngData, @"Temporary clipboard image should preserve PNG payload");
    XCTAssertNil(_appDelegate.lastTransientFeedbackMessage, @"Success path should not emit an error message");
}

- (void)testPasteAsNewImageReportsMissingClipboardImage {
    _appDelegate.probeClipboardPNGData = nil;

    [_appDelegate pasteAsNewImage:nil];

    XCTAssertNil(_appDelegate.launchedImageURL, @"Missing clipboard image should not launch a new window");
    XCTAssertEqualObjects(_appDelegate.lastTransientFeedbackMessage, @"Clipboard does not contain an image");
}

@end
