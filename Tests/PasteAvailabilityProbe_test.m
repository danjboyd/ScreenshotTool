/*
 * PasteAvailabilityProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Paste (the empty state's button and Edit ▸ Paste as New Image) is enabled only when the
 * clipboard holds an image: PNG or TIFF data, or an image file (#76). The tests use a private
 * pasteboard, never the user's clipboard.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (PasteAvailabilityTesting)
- (void)setupWindowAndContent;
- (NSView *)emptyStateView;
- (void)refreshPasteAvailability;
- (NSData *)clipboardPNGDataForPasteAsNewImage;
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
@end

@interface PasteAvailabilityTestDelegate : AppDelegate
@property (nonatomic, strong) NSPasteboard *testPasteboard;
@end

@implementation PasteAvailabilityTestDelegate
- (NSPasteboard *)clipboardPasteboard {
    return self.testPasteboard;
}

@end

@interface PasteAvailabilityProbeTests : XCTestCase {
    BOOL _shouldSkip;
    PasteAvailabilityTestDelegate *_appDelegate;
    NSString *_directory;
}
@end

@implementation PasteAvailabilityProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        _appDelegate = [[PasteAvailabilityTestDelegate alloc] init];
        _appDelegate.testPasteboard = [NSPasteboard pasteboardWithUniqueName];
        [_appDelegate setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
    _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"paste-%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown {
    [_appDelegate.testPasteboard releaseGlobally];
    _appDelegate = nil;
    [[NSFileManager defaultManager] removeItemAtPath:_directory error:NULL];
    [super tearDown];
}

- (NSData *)pngData {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:8 pixelsHigh:6
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    return [rep representationUsingType:NSPNGFileType properties:@{}];
}

- (NSButton *)pasteButton {
    for (NSView *view in _appDelegate.emptyStateView.subviews) {
        if ([view isKindOfClass:[NSButton class]] && [[(NSButton *)view title] isEqualToString:@"Paste"]) {
            return (NSButton *)view;
        }
    }
    return nil;
}

/// Re-checks the clipboard; YES when both the button and the menu item are enabled, checking they agree.
- (BOOL)pasteIsAvailable {
    [_appDelegate refreshPasteAvailability];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Paste as New Image" action:@selector(pasteAsNewImage:) keyEquivalent:@""];
    BOOL menuEnabled = [_appDelegate validateMenuItem:item];
    BOOL buttonEnabled = [[self pasteButton] isEnabled];
    XCTAssertEqual(menuEnabled, buttonEnabled, @"the menu item and the button agree");
    return menuEnabled && buttonEnabled;
}

- (void)testNothingToPasteDisablesPaste {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_appDelegate.testPasteboard declareTypes:@[] owner:nil];
    XCTAssertFalse([self pasteIsAvailable]);
    XCTAssertEqualObjects([[self pasteButton] toolTip], @"The clipboard has no image");
}

- (void)testTextIsNotAnImage {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSPasteboard *pasteboard = _appDelegate.testPasteboard;
    [pasteboard declareTypes:@[ NSStringPboardType ] owner:nil];
    [pasteboard setString:@"hello" forType:NSStringPboardType];
    XCTAssertFalse([self pasteIsAvailable]);
}

- (void)testPNGDataEnablesPaste {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSPasteboard *pasteboard = _appDelegate.testPasteboard;
    [pasteboard declareTypes:@[ NSPasteboardTypePNG ] owner:nil];
    [pasteboard setData:[self pngData] forType:NSPasteboardTypePNG];
    XCTAssertTrue([self pasteIsAvailable]);
    XCTAssertNil([[self pasteButton] toolTip], @"no explanation when Paste works");
}

- (void)testTIFFDataEnablesPaste {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSImage *image = [[NSImage alloc] initWithData:[self pngData]];
    NSPasteboard *pasteboard = _appDelegate.testPasteboard;
    [pasteboard declareTypes:@[ NSPasteboardTypeTIFF ] owner:nil];
    [pasteboard setData:[image TIFFRepresentation] forType:NSPasteboardTypeTIFF];
    XCTAssertTrue([self pasteIsAvailable]);
}

- (void)testCopiedImageFileEnablesPasteAndPastes {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSString *path = [_directory stringByAppendingPathComponent:@"copied.png"];
    XCTAssertTrue([[self pngData] writeToFile:path atomically:YES]);
    NSPasteboard *pasteboard = _appDelegate.testPasteboard;
    [pasteboard declareTypes:@[ NSFilenamesPboardType ] owner:nil];
    [pasteboard setPropertyList:@[ path ] forType:NSFilenamesPboardType];
    XCTAssertTrue([self pasteIsAvailable]);
    XCTAssertGreaterThan([_appDelegate clipboardPNGDataForPasteAsNewImage].length, 0u, @"the file's image is what's pasted");
}

- (void)testCopiedNonImageFileDoesNotEnablePaste {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSString *path = [_directory stringByAppendingPathComponent:@"notes.txt"];
    XCTAssertTrue([@"notes" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    NSPasteboard *pasteboard = _appDelegate.testPasteboard;
    [pasteboard declareTypes:@[ NSFilenamesPboardType ] owner:nil];
    [pasteboard setPropertyList:@[ path ] forType:NSFilenamesPboardType];
    XCTAssertFalse([self pasteIsAvailable]);
}

@end
