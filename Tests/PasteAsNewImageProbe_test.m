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
- (void)showCommandResultMessage:(NSString *)message duration:(NSTimeInterval)duration;
- (void)setupWindowAndContent;
- (BOOL)openImageAtURL:(NSURL *)url;
- (NSWindow *)window;
- (NSURL *)currentImageURL;
- (void)setupMenus;
- (NSURL *)temporaryCaptureImageURLForPNGData:(NSData *)pngData;
- (NSString *)untitledDocumentTitle;
- (NSString *)emptyStateRecentDetailForDate:(NSDate *)date;
@end

extern NSString *STCaptureTitleForDate(NSDate *date);
extern BOOL STLaunchesNewWindowsThroughOpenapp(NSDictionary<NSString *, NSString *> *environment);

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

- (void)showCommandResultMessage:(NSString *)message duration:(NSTimeInterval)duration {
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

- (void)testCaptureOpensWithItsOwnUntitledTitle {
    // #332: a capture used to open as "Pasted Image", through the same temp-file route.
    NSURL *temporaryURL = [_appDelegate temporaryCaptureImageURLForPNGData:[self onePixelPNGData]];
    XCTAssertNotNil(temporaryURL);

    AppDelegate *captureWindow = [[AppDelegate alloc] init];
    @try {
        [captureWindow setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        [[NSFileManager defaultManager] removeItemAtURL:temporaryURL error:NULL];
        return;
    }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsRecentDocumentsKey];

    XCTAssertTrue([captureWindow openImageAtURL:temporaryURL], @"The capture should open");
    NSString *title = captureWindow.window.title;
    XCTAssertTrue([title hasPrefix:@"Screenshot "], @"A capture should be titled as one, not %@", title);
    XCTAssertNotEqualObjects(title, @"Pasted Image");
    XCTAssertEqualObjects(captureWindow.untitledDocumentTitle, title, @"The Save panels should offer the window's title");
    XCTAssertNil(captureWindow.currentImageURL, @"A capture should be untitled so Save As uses the save folder");
    NSArray *recents = [[NSUserDefaults standardUserDefaults] arrayForKey:STDefaultsRecentDocumentsKey];
    XCTAssertFalse([recents containsObject:temporaryURL.path], @"Temp file should not be added to Open Recent");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:temporaryURL.path], @"Temp file should be removed once loaded");
}

- (void)testPastedImageOffersPastedImageAsItsSaveName {
    _appDelegate.probeClipboardPNGData = [self onePixelPNGData];
    [_appDelegate pasteAsNewImage:nil];
    NSURL *temporaryURL = _appDelegate.launchedImageURL;
    XCTAssertNotNil(temporaryURL);

    AppDelegate *pastedInstance = [[AppDelegate alloc] init];
    @try {
        [pastedInstance setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        return;
    }
    XCTAssertTrue([pastedInstance openImageAtURL:temporaryURL]);
    XCTAssertEqualObjects(pastedInstance.untitledDocumentTitle, @"Pasted Image");
}

- (void)testCaptureTitleIsAValidFileNameWithTheTime {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.year = 2026;
    components.month = 11;
    components.day = 3;
    components.hour = 9;
    components.minute = 5;
    components.second = 7;
    NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:components];
    NSString *title = STCaptureTitleForDate(date);
    XCTAssertEqualObjects(title, @"Screenshot 2026-11-03 at 09.05.07");
    XCTAssertEqual([title rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@":/\\"]].location,
                   (NSUInteger)NSNotFound, @"The title is also the Save name, so no path or colon characters");
}

- (void)testCaptureTitleIsInTheLocalZoneNotUTC {
    NSDate *november = [NSDate dateWithTimeIntervalSince1970:1793736246]; // 2026-11-03 20:04:06 UTC
    NSDate *july = [NSDate dateWithTimeIntervalSince1970:1784837046];     // 2026-07-23 20:04:06 UTC
    NSTimeZone *original = [NSTimeZone defaultTimeZone];
    @try {
        [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneWithName:@"Asia/Tokyo"]];
        XCTAssertEqualObjects(STCaptureTitleForDate(november), @"Screenshot 2026-11-04 at 05.04.06");
        // Windows's name for a zone, as GNUstep reports the local one there. The formatter doesn't
        // know it and printed GMT. Only Windows has a zone by this name.
        NSTimeZone *windowsZone = [NSTimeZone timeZoneWithName:@"Central Standard Time"];
        if (windowsZone) {
            [NSTimeZone setDefaultTimeZone:windowsZone];
            XCTAssertEqualObjects(STCaptureTitleForDate(november), @"Screenshot 2026-11-03 at 14.04.06");
            XCTAssertEqualObjects(STCaptureTitleForDate(july), @"Screenshot 2026-07-23 at 15.04.06",
                                  @"Daylight time, by the date");
        }
    } @finally {
        [NSTimeZone setDefaultTimeZone:original];
    }
}

- (void)testRecentsDatesAreInTheLocalZoneNotUTC {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1595534646]; // 2020-07-23 20:04:06 UTC
    // ICU's no-break spaces before AM/PM: GNUstep's Recents text has plain ones, macOS's doesn't.
    NSString *(^plain)(NSString *) = ^NSString *(NSString *text) {
        text = [text stringByReplacingOccurrencesOfString:@" " withString:@" "];
        return [text stringByReplacingOccurrencesOfString:@" " withString:@" "];
    };
    NSString *(^expected)(NSInteger) = ^NSString *(NSInteger secondsFromGMT) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:secondsFromGMT];
#if !defined(GNUSTEP)
        formatter.doesRelativeDateFormatting = YES; // As the Recents list does.
#endif
        return plain([formatter stringFromDate:date]);
    };
    NSTimeZone *original = [NSTimeZone defaultTimeZone];
    @try {
        [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneWithName:@"Asia/Tokyo"]];
        XCTAssertEqualObjects(plain([_appDelegate emptyStateRecentDetailForDate:date]), expected(9 * 3600));
        NSTimeZone *windowsZone = [NSTimeZone timeZoneWithName:@"Central Standard Time"];
        if (windowsZone) {
            [NSTimeZone setDefaultTimeZone:windowsZone];
            XCTAssertEqualObjects(plain([_appDelegate emptyStateRecentDetailForDate:date]), expected(-5 * 3600),
                                  @"Windows's zone name, in daylight time");
        }
    } @finally {
        [NSTimeZone setDefaultTimeZone:original];
    }
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

- (void)testAnAppImageStartsItsNewWindowsWithoutOpenapp {
    // From an AppImage the host's openapp sourced the AppImage's relative GNUstep.conf and failed,
    // so Paste as New Image opened nothing on a host with GNUstep: AppRun's variables say not to.
    XCTAssertTrue(STLaunchesNewWindowsThroughOpenapp(@{}), @"A GNUstep install starts new windows through openapp");
    XCTAssertTrue(STLaunchesNewWindowsThroughOpenapp(@{ @"APPDIR" : @"" }), @"An empty APPDIR is no AppImage");
    XCTAssertFalse(STLaunchesNewWindowsThroughOpenapp(@{ @"APPDIR" : @"/tmp/.mount_ScreenXYZ" }),
                   @"Inside an AppImage the executable is started directly");
    XCTAssertFalse(STLaunchesNewWindowsThroughOpenapp(@{ @"APPIMAGE" : @"/home/user/ScreenshotTool.AppImage" }),
                   @"APPIMAGE alone also means an AppImage");
}

@end
