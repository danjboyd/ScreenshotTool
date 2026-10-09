/*
 * PasteAsNewImageProbe_test.m
 * Verifies clipboard images open in a new ScreenshotTool window.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotToolSettings.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (PasteAsNewImageTesting)
- (void)pasteAsNewImage:(id)sender;
- (NSData *)clipboardPNGDataForPasteAsNewImage;
- (BOOL)launchNewWindowForImageAtURL:(NSURL *)url;
- (void)showTransientFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration;
- (void)setupWindowAndContent;
- (BOOL)openImageAtURL:(NSURL *)url;
- (NSWindow *)window;
- (NSURL *)currentImageURL;
- (void)setupMenus;
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

- (void)testPastedImageOpensAsUntitledDocument {
    _appDelegate.probeClipboardPNGData = [self onePixelPNGData];
    [_appDelegate pasteAsNewImage:nil];
    NSURL *temporaryURL = _appDelegate.launchedImageURL;
    XCTAssertNotNil(temporaryURL);

    // The launched instance opens the temp file like any other path.
    AppDelegate *pastedInstance = [[AppDelegate alloc] init];
    @try {
        [pastedInstance setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        return;
    }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsRecentDocumentsKey];

    XCTAssertTrue([pastedInstance openImageAtURL:temporaryURL], @"Pasted image should open");
    XCTAssertEqualObjects(pastedInstance.window.title, @"Pasted Image", @"Window should not be titled with the temp path");
    XCTAssertNil(pastedInstance.currentImageURL, @"Pasted image should be untitled so Save As uses the save folder");
    NSArray *recents = [[NSUserDefaults standardUserDefaults] arrayForKey:STDefaultsRecentDocumentsKey];
    XCTAssertFalse([recents containsObject:temporaryURL.path], @"Temp file should not be added to Open Recent");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:temporaryURL.path], @"Temp file should be removed once loaded");
}

- (void)testAnEmptyWindowTakesThePastedImageItself {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                 [NSString stringWithFormat:@"paste-%@.png", [NSUUID UUID].UUIDString]];
    XCTAssertTrue([[self onePixelPNGData] writeToFile:path atomically:YES]);
    NSURL *url = [NSURL fileURLWithPath:path];

    AppDelegate *emptyWindow = [[AppDelegate alloc] init];
    @try {
        [emptyWindow setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        return;
    }
    // Not another instance (another process on GNUstep) beside an empty window, as Take Screenshot
    // already did.
    XCTAssertTrue([emptyWindow launchNewWindowForImageAtURL:url]);
    XCTAssertEqualObjects(emptyWindow.currentImageURL.path.stringByStandardizingPath, path.stringByStandardizingPath,
                          @"The empty window should show the image");
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (void)testPasteAsNewImageShortcutUsesCommandModifier {
    [_appDelegate setupMenus];
    NSMenuItem *pasteItem = nil;
    for (NSMenuItem *topItem in [[NSApp mainMenu] itemArray]) {
        NSInteger index = [topItem.submenu indexOfItemWithTitle:@"Paste as New Image"];
        if (index >= 0) {
            pasteItem = [topItem.submenu itemAtIndex:index];
            break;
        }
    }
    XCTAssertNotNil(pasteItem, @"Edit menu should contain Paste as New Image");

    // GNUstep sends the Ctrl key as Command, like every other shortcut in the app.
    NSUInteger mask = pasteItem.keyEquivalentModifierMask;
    XCTAssertTrue((mask & NSEventModifierFlagCommand) != 0, @"Shortcut should use the Command modifier");
    XCTAssertTrue((mask & NSEventModifierFlagShift) != 0, @"Shortcut should use Shift");
    XCTAssertTrue((mask & NSEventModifierFlagControl) == 0, @"A Control mask is unreachable from the Ctrl key on GNUstep");
    XCTAssertEqualObjects(pasteItem.keyEquivalent.lowercaseString, @"v");
}

@end
