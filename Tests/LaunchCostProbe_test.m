#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "TestEnvironmentHelpers.h"

/// Work launch used to do that nothing on screen needed: reading the clipboard with an image open
/// (it starts GNUstep's pasteboard server and waits for it), and sizing the hidden status bar's
/// "⋯" button (a font fallback search).

@interface AppDelegate (LaunchCostTesting)
- (void)setupWindowAndContent;
- (NSView *)emptyStateView;
- (NSView *)statusControlsContainer;
- (NSButton *)toolWidthOptionsButton;
- (BOOL)openImageAtURL:(NSURL *)url;
- (void)refreshPasteAvailability;
- (void)preferencesController:(id)controller didToggleStatusBar:(BOOL)show;
@end

@interface LaunchCostTestDelegate : AppDelegate
@property (nonatomic, strong) NSPasteboard *testPasteboard;
@property (nonatomic) NSUInteger clipboardReads;
@end

@implementation LaunchCostTestDelegate
- (NSPasteboard *)clipboardPasteboard {
    self.clipboardReads++;
    return self.testPasteboard;
}
@end

@interface LaunchCostProbeTests : XCTestCase {
    BOOL _shouldSkip;
    LaunchCostTestDelegate *_appDelegate;
    NSString *_imagePath;
}
@end

@implementation LaunchCostProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        _appDelegate = [[LaunchCostTestDelegate alloc] init];
        _appDelegate.testPasteboard = [NSPasteboard pasteboardWithUniqueName];
        [_appDelegate setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    [_appDelegate.testPasteboard releaseGlobally];
    _appDelegate = nil;
    if (_imagePath) {
        [[NSFileManager defaultManager] removeItemAtPath:_imagePath error:NULL];
        _imagePath = nil;
    }
    [super tearDown];
}

- (BOOL)openAnImage {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:30
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    _imagePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"launch-cost-%@.png", [[NSUUID UUID] UUIDString]]];
    [[rep representationUsingType:NSPNGFileType properties:@{}] writeToFile:_imagePath atomically:YES];
    return [_appDelegate openImageAtURL:[NSURL fileURLWithPath:_imagePath]];
}

- (void)testPasteCheckLeavesTheClipboardAloneWhileAnImageIsOpen {
    XCTSkipIf(_shouldSkip, @"No window server");
    XCTAssertTrue([self openAnImage]);
    XCTAssertTrue(_appDelegate.emptyStateView.isHidden);
    _appDelegate.clipboardReads = 0;
    [_appDelegate refreshPasteAvailability];
    XCTAssertEqual(_appDelegate.clipboardReads, (NSUInteger)0, @"no clipboard read when no Paste button shows");
}

- (void)testPasteCheckReadsTheClipboardForTheEmptyState {
    XCTSkipIf(_shouldSkip, @"No window server");
    XCTAssertFalse(_appDelegate.emptyStateView.isHidden);
    _appDelegate.clipboardReads = 0;
    [_appDelegate refreshPasteAvailability];
    XCTAssertGreaterThan(_appDelegate.clipboardReads, (NSUInteger)0, @"the empty state's Paste button needs the clipboard");
}

- (void)testHiddenStatusBarControlsAreNotSized {
    XCTSkipIf(_shouldSkip, @"No window server");
    XCTAssertTrue(_appDelegate.statusControlsContainer.isHidden, @"the status bar is off by default");
    XCTAssertEqual(NSWidth(_appDelegate.toolWidthOptionsButton.frame), 0.0, @"the hidden \"⋯\" button isn't sized");

    [_appDelegate preferencesController:nil didToggleStatusBar:YES];
    XCTAssertFalse(_appDelegate.statusControlsContainer.isHidden, @"showing the status bar shows its controls");
    XCTAssertGreaterThan(NSWidth(_appDelegate.toolWidthOptionsButton.frame), 0.0, @"and lays them out");
    [_appDelegate preferencesController:nil didToggleStatusBar:NO];
}

- (void)testEmptyStateUsesTheLoadedApplicationIcon {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSImageView *icon = [_appDelegate.emptyStateView viewWithTag:1];
    XCTAssertNotNil(icon.image);
    if ([NSApp applicationIconImage] != nil) {
        XCTAssertEqual(icon.image, [NSApp applicationIconImage], @"no second, full-size copy of the icon");
    }
}

/// GNUstep takes the application icon from NSIcon (or CFBundleIconFile), not ApplicationIcon: without
/// it, the empty state and the windows showed GNUstep's own icon.
- (void)testInfoPlistNamesTheApplicationIconForGNUstep {
    // `make tests` runs from the repository root; the app ships this file as its Info-gnustep.plist.
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:@"Resources/Info-gnustep.plist"];
    NSString *iconName = info[@"NSIcon"];
    XCTAssertEqualObjects(iconName, @"ScreenshotToolIcon.tiff");
    NSString *path = [@"Resources" stringByAppendingPathComponent:iconName ?: @""];
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithContentsOfFile:path];
    XCTAssertNotNil(rep, @"%@ loads", path);
    XCTAssertLessThanOrEqual(rep.pixelsWide, 256, @"small: it goes to the X server with every window");
    XCTAssertTrue(rep.hasAlpha, @"transparent around the rounded square, not a grey tile");
    XCTAssertEqualWithAccuracy([[rep colorAtX:0 y:0] alphaComponent], 0.0, 0.01, @"a transparent corner");
}

@end
