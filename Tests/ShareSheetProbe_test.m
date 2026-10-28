/*
 * ShareSheetProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Share on Linux and Windows through libs-sharing (third_party/libs-sharing): the library is installed into
 * libs-gui's classes, the sheet is given the PNG a share sends, and the toolbar has its Share item.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"
#if defined(ST_HAVE_LIBS_SHARING)
#import "GSSharing.h"
#import "GSSharingPrivate.h"
#import "GSSharingRclone.h"
#endif

@interface AppDelegate (ShareSheetTesting) <NSToolbarDelegate>
- (void)setupWindowAndContent;
- (ScreenshotCanvasView *)canvasView;
- (NSArray *)shareItemProviders;
- (void)presentShareFromView:(NSView *)view rect:(NSRect)rect;
- (NSWindow *)window;
- (void)setupMenus;
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
@end

#if defined(GNUSTEP) && defined(ST_HAVE_LIBS_SHARING)
@interface AppDelegate (ShareSheetFeedbackTesting) <NSSharingServicePickerDelegate>
- (void)showCopyFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration;
- (void)sharingService:(NSSharingService *)sharingService didShareItems:(NSArray *)items;
- (void)sharingService:(NSSharingService *)sharingService didFailToShareItems:(NSArray *)items error:(NSError *)error;
@end

/// Keeps the messages a share's end shows, instead of showing them.
@interface STFeedbackRecordingAppDelegate : AppDelegate
@property (nonatomic, strong) NSMutableArray<NSString *> *messages;
@end

@implementation STFeedbackRecordingAppDelegate
- (void)showCopyFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration {
    (void)duration;
    if (!self.messages) {
        self.messages = [NSMutableArray array];
    }
    [self.messages addObject:message];
}
@end

/// A service whose work ends after it returns, as libs-sharing's rclone upload's does.
@interface STLaterShare : NSObject
@property (nonatomic, strong) NSSharingService *service;
@property (nonatomic, strong) NSArray *items;
@end

@implementation STLaterShare
- (void)shareItems:(NSArray *)items service:(NSSharingService *)service {
    GSSharingServiceWillFinishLater(service);
    self.service = service;
    self.items = items;
}
- (void)finish:(NSError *)error {
    GSSharingServiceFinish(self.service, self.items, error);
}
@end
#endif

#if !defined(GNUSTEP)
@interface AppDelegate (ShareInProgressTesting) <NSSharingServicePickerDelegate, NSSharingServiceDelegate>
- (nullable NSSharingService *)sharingServiceInProgress;
- (nullable NSSharingServicePicker *)openSharePicker;
- (void)shareFromMenuItem:(NSMenuItem *)sender;
@end

/// A service that only counts its shares: its window, were it AirDrop's, would still be up until
/// it reports.
@interface STCountingSharingService : NSSharingService
@property (nonatomic, assign) NSUInteger performCount;
@end

@implementation STCountingSharingService
- (void)performWithItems:(NSArray *)items {
    (void)items;
    self.performCount += 1;
}
@end
#endif

@interface ScreenshotCanvasView (ShareSheetTesting)
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
@end

@interface ShareSheetProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation ShareSheetProbeTests

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

#if defined(GNUSTEP) && defined(ST_HAVE_LIBS_SHARING)
- (void)loadImageOfSize:(NSSize)size {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:(NSInteger)size.width
                                                                    pixelsHigh:(NSInteger)size.height
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    memset(rep.bitmapData, 200, rep.bytesPerRow * rep.pixelsHigh);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image addRepresentation:rep];
    [_appDelegate.canvasView loadImage:image];
}

- (void)testTheLibraryIsInstalled {
    XCTAssertTrue(GSSharingInstall(), @"libs-sharing is compiled in and installed into libs-gui's classes");
    XCTAssertTrue([NSSharingServicePicker instancesRespondToSelector:@selector(showRelativeToRect:ofView:preferredEdge:)]);
    NSArray *titles = [[NSSharingService sharingServicesForItems:@[[NSURL fileURLWithPath:@"/tmp/Shot.png"]]]
                       valueForKey:@"title"];
    for (NSString *title in @[@"Email", @"Copy", @"Save a Copy", @"Show in Folder", @"Open With…"]) {
        XCTAssertTrue([titles containsObject:title], @"%@ is offered for a PNG", title);
    }
}

- (void)testTheSheetGetsThePNGAShareSends {
    XCTSkipIf(_shouldSkip, @"No window server");
    [self loadImageOfSize:NSMakeSize(120, 80)];
    NSArray *items = [_appDelegate shareItemProviders];
    XCTAssertEqual(items.count, (NSUInteger)1);
    NSURL *url = items.firstObject;
    XCTAssertTrue([url isKindOfClass:[NSURL class]] && url.isFileURL, @"A file, which every service takes");
    XCTAssertEqualObjects(url.pathExtension, @"png");
    NSBitmapImageRep *png = [NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfURL:url]];
    XCTAssertEqual(png.pixelsWide, 120);

    _appDelegate.canvasView.selectionRect = NSMakeRect(10, 10, 40, 30);
    _appDelegate.canvasView.hasSelectionRect = YES;
    png = [NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfURL:[_appDelegate shareItemProviders].firstObject]];
    XCTAssertEqual(png.pixelsWide, 40, @"With a selection, the selection");
    XCTAssertEqual(png.pixelsHigh, 30);
}

/// The sheet Share… and the selection bar's Share open (-presentShareFromView:rect:), which
/// keeps itself up after the call though nothing here keeps the picker.
- (void)testShareOpensTheSheet {
    XCTSkipIf(_shouldSkip, @"No window server");
    [self loadImageOfSize:NSMakeSize(120, 80)];
    [_appDelegate.window orderFront:nil];
    @autoreleasepool {
        [_appDelegate presentShareFromView:_appDelegate.canvasView rect:NSMakeRect(10, 10, 1, 1)];
    }
    NSWindow *sheet = nil;
    for (NSWindow *window in [NSApp windows]) {
        if ([window.title isEqualToString:@"Share"] && window.isVisible) {
            sheet = window;
        }
    }
    XCTAssertNotNil(sheet, @"The share sheet is up");
    [sheet performClose:nil];
    XCTAssertFalse(sheet.isVisible);
}

/// File > Share… opens the same sheet, so Share isn't only on the toolbar and the canvas.
- (void)testFileMenuSharesTheImage {
    XCTSkipIf(_shouldSkip, @"No window server");
    [_appDelegate setupMenus];
    NSMenu *fileMenu = [[NSApp mainMenu] itemWithTitle:@"File"].submenu;
    NSMenuItem *share = [fileMenu itemWithTitle:@"Share…"];
    XCTAssertNotNil(share, @"File > Share…");
    XCTAssertFalse([_appDelegate validateMenuItem:share], @"Nothing to share without an image");

    [self loadImageOfSize:NSMakeSize(120, 80)];
    XCTAssertTrue([_appDelegate validateMenuItem:share]);
    [_appDelegate.window orderFront:nil];
    @autoreleasepool {
        [NSApp sendAction:share.action to:share.target from:share];
    }
    NSWindow *sheet = nil;
    for (NSWindow *window in [NSApp windows]) {
        if ([window.title isEqualToString:@"Share"] && window.isVisible) {
            sheet = window;
        }
    }
    XCTAssertNotNil(sheet, @"The share sheet is up");
    [sheet performClose:nil];
}

- (NSArray<NSWindow *> *)visibleShareSheets {
    NSMutableArray<NSWindow *> *sheets = [NSMutableArray array];
    for (NSWindow *window in [NSApp windows]) {
        if ([window.title isEqualToString:@"Share"] && window.isVisible) {
            [sheets addObject:window];
        }
    }
    return sheets;
}

- (void)showNewPicker {
    @autoreleasepool {
        NSSharingServicePicker *picker = [[NSSharingServicePicker alloc] initWithItems:[_appDelegate shareItemProviders]];
        picker.delegate = (id<NSSharingServicePickerDelegate>)_appDelegate;
        [picker showRelativeToRect:NSMakeRect(10, 10, 1, 1) ofView:_appDelegate.canvasView preferredEdge:NSMinYEdge];
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
}

/// Each toolbar Share click makes a new picker. A second click while the sheet shows leaves one
/// sheet, not two stacked (#316), and Share opens again after the sheet closes.
- (void)testShareTwiceLeavesOneSheet {
    XCTSkipIf(_shouldSkip, @"No window server");
    [self loadImageOfSize:NSMakeSize(120, 80)];
    [_appDelegate.window orderFront:nil];
    [self showNewPicker];
    [self showNewPicker];
    XCTAssertEqual([self visibleShareSheets].count, (NSUInteger)1, @"One sheet after two Share clicks");

    [[self visibleShareSheets].firstObject performClose:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    XCTAssertEqual([self visibleShareSheets].count, (NSUInteger)0);

    [self showNewPicker];
    XCTAssertEqual([self visibleShareSheets].count, (NSUInteger)1, @"Share opens again after a close");
    [[self visibleShareSheets].firstObject performClose:nil];
}

/// An rclone upload names its remote: libs-sharing's tile says "Link on Work" and its title is a
/// sentence, neither of which reads well after "Shared with".
- (void)testAnRcloneShareNamesItsRemote {
    XCTSkipIf(_shouldSkip, @"No window server");
    STFeedbackRecordingAppDelegate *app = [[STFeedbackRecordingAppDelegate alloc] init];
    [app setupWindowAndContent];
    NSArray *items = @[[NSURL fileURLWithPath:@"/tmp/Shot.png"]];
    // As libs-sharing makes them (GSSharingRcloneService.m).
    NSSharingService *upload = [[NSSharingService alloc] initWithTitle:@"Upload a copy to Work (Google Drive) and copy a link to it"
                                                                 image:nil
                                                        alternateImage:nil
                                                               handler:^{}];
    upload.menuItemTitle = @"Link on Work";

    [app sharingService:upload didShareItems:items];
    XCTAssertEqualObjects(app.messages.lastObject, @"Uploaded to Work; link copied");
    [app sharingService:upload didFailToShareItems:items
                  error:[NSError errorWithDomain:GSSharingRcloneErrorDomain code:GSSharingRcloneErrorFailed
                                        userInfo:@{NSLocalizedDescriptionKey: @"rclone couldn't do it.",
                                                   NSLocalizedFailureReasonErrorKey: @"Failed to copy: quota exceeded"}]];
    XCTAssertEqualObjects(app.messages.lastObject, @"Couldn't share with Work: Failed to copy: quota exceeded");
}

/// A share says how it went once it has ended: "Shared with" when it's done, why it failed, and
/// nothing for Cancel or while it's still going (libs-sharing reports the end, its #5).
- (void)testAShareSaysHowItWentWhenItEnds {
    XCTSkipIf(_shouldSkip, @"No window server");
    STFeedbackRecordingAppDelegate *app = [[STFeedbackRecordingAppDelegate alloc] init];
    [app setupWindowAndContent];
    STLaterShare *work = [[STLaterShare alloc] init];
    NSArray *items = @[[NSURL fileURLWithPath:@"/tmp/Shot.png"]];

    NSSharingService *(^start)(void) = ^NSSharingService * {
        NSSharingService *service = [[NSSharingService alloc] initWithTitle:@"Work Drive"
                                                                      image:nil
                                                             alternateImage:nil
                                                                     target:work
                                                                     action:@selector(shareItems:service:)];
        // As the sheet does: the service reports to the delegate the picker's delegate names.
        service.delegate = [app sharingServicePicker:nil delegateForSharingService:service];
        [service performWithItems:items];
        return service;
    };

    start();
    XCTAssertEqual(app.messages.count, (NSUInteger)0, @"Nothing while the upload is going");
    [work finish:nil];
    XCTAssertEqualObjects(app.messages.lastObject, @"Shared with Work Drive");

    start();
    [work finish:[NSError errorWithDomain:@"rclone" code:3
                                 userInfo:@{NSLocalizedDescriptionKey: @"The sign-in to Work Drive has expired."}]];
    XCTAssertEqualObjects(app.messages.lastObject, @"Couldn't share with Work Drive: The sign-in to Work Drive has expired.");

    // rclone's own words when libs-sharing has none plainer.
    start();
    [work finish:[NSError errorWithDomain:GSSharingRcloneErrorDomain code:GSSharingRcloneErrorFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"rclone couldn't do it.",
                                            NSLocalizedFailureReasonErrorKey: @"Failed to copy: quota exceeded"}]];
    XCTAssertEqualObjects(app.messages.lastObject, @"Couldn't share with Work Drive: Failed to copy: quota exceeded");

    NSUInteger count = app.messages.count;
    start();
    [work finish:GSSharingCancelledError()];
    XCTAssertEqual(app.messages.count, count, @"Cancel says nothing");

    // Email, Show in Folder and Open With hand the image to another app, whose window says it.
    for (NSSharingServiceName name in @[NSSharingServiceNameComposeEmail, GSSharingServiceNameShowInFolder,
                                         GSSharingServiceNameOpenWith]) {
        [app sharingService:[NSSharingService sharingServiceNamed:name] didShareItems:items];
        XCTAssertEqual(app.messages.count, count, @"%@ says nothing when it hands off", name);
    }
    [app sharingService:[NSSharingService sharingServiceNamed:NSSharingServiceNameComposeEmail]
        didFailToShareItems:items
                      error:[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil]];
    XCTAssertEqual(app.messages.count, count + 1, @"but says when it fails");
    [app sharingService:[NSSharingService sharingServiceNamed:GSSharingServiceNameSaveCopy] didShareItems:items];
    XCTAssertEqualObjects(app.messages.lastObject, @"Saved a copy");

    // The sheet's Copy says what the Copy button says: under Wayland, GNUstep's pasteboard is the
    // X11 clipboard only.
    const char *wayland = getenv("WAYLAND_DISPLAY");
    const char *session = getenv("XDG_SESSION_TYPE");
    NSString *savedWayland = wayland ? @(wayland) : nil;
    NSString *savedSession = session ? @(session) : nil;
    NSSharingService *copy = [NSSharingService sharingServiceNamed:GSSharingServiceNameCopy];
    copy.delegate = [app sharingServicePicker:nil delegateForSharingService:copy];
    STUnsetEnvVar("WAYLAND_DISPLAY");
    STSetEnvVar("XDG_SESSION_TYPE", "x11");
    [copy performWithItems:items];
    XCTAssertEqualObjects(app.messages.lastObject, @"Copied image to clipboard");
    STSetEnvVar("XDG_SESSION_TYPE", "wayland");
    [copy performWithItems:items];
    XCTAssertEqualObjects(app.messages.lastObject, @"Copied image to X11 clipboard");
    if (savedWayland) {
        STSetEnvVar("WAYLAND_DISPLAY", savedWayland.UTF8String);
    }
    if (savedSession) {
        STSetEnvVar("XDG_SESSION_TYPE", savedSession.UTF8String);
    } else {
        STUnsetEnvVar("XDG_SESSION_TYPE");
    }
}

- (void)testTheToolbarHasShare {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSToolbarItem *item = [_appDelegate toolbar:nil
                          itemForItemIdentifier:@"com.screenshottool.toolbar.share"
                      willBeInsertedIntoToolbar:YES];
    XCTAssertTrue([item isKindOfClass:[NSSharingServicePickerToolbarItem class]], @"libs-sharing's item");
    XCTAssertTrue([(NSSharingServicePickerToolbarItem *)item delegate] == (id)_appDelegate);
    XCTAssertNotNil(item.image, @"With ScreenshotTool's Share icon");
    XCTAssertTrue([[_appDelegate toolbarAllowedItemIdentifiers:nil] containsObject:@"com.screenshottool.toolbar.share"]);
}
#endif

#if !defined(GNUSTEP)
- (STCountingSharingService *)countingService {
    return [[STCountingSharingService alloc] initWithTitle:@"AirDrop" image:[[NSImage alloc] init]
                                            alternateImage:nil handler:^{}];
}

/// File > Share > AirDrop while AirDrop's window from the last one is still up does nothing:
/// two would stack (#335). Once the share reports, however it went, Share works again.
- (void)testAMenuShareWaitsForTheLastOneToEnd {
    XCTSkipIf(_shouldSkip, @"No window server");
    STCountingSharingService *service = [self countingService];
    NSArray *items = @[[NSURL fileURLWithPath:@"/tmp/Shot.png"]];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:service.title action:@selector(shareFromMenuItem:) keyEquivalent:@""];
    item.representedObject = @[service, items.firstObject];

    [_appDelegate shareFromMenuItem:item];
    XCTAssertEqual(service.performCount, (NSUInteger)1);
    [_appDelegate shareFromMenuItem:item];
    XCTAssertEqual(service.performCount, (NSUInteger)1, @"Not a second share while the first is going");

    // The share reports to the delegate the menu gave it, as AirDrop does when its window closes,
    // Cancel included (#299).
    [service.delegate sharingService:service didShareItems:items];
    [_appDelegate shareFromMenuItem:item];
    XCTAssertEqual(service.performCount, (NSUInteger)2, @"Share again once it reported");

    [service.delegate sharingService:service didFailToShareItems:items
                               error:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
    [_appDelegate shareFromMenuItem:item];
    XCTAssertEqual(service.performCount, (NSUInteger)3, @"and once it failed or was cancelled");
    [service.delegate sharingService:service didShareItems:items];
}

/// A service chosen from the toolbar's or the canvas's picker counts too: Share opens no picker
/// over its window until it reports (#335).
- (void)testAPickedServiceKeepsSharePickerClosedUntilItEnds {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(120, 80)];
    [image lockFocus];
    [[NSColor grayColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 120, 80));
    [image unlockFocus];
    [_appDelegate.canvasView loadImage:image];
    [_appDelegate.window orderFront:nil];

    // The picker that offered it, as the toolbar's would have (never shown).
    NSSharingServicePicker *picker = [[NSSharingServicePicker alloc] initWithItems:@[]];
    STCountingSharingService *picked = [self countingService];
    [_appDelegate sharingServicePicker:picker didChooseSharingService:picked];
    XCTAssertEqual(_appDelegate.sharingServiceInProgress, picked);
    [_appDelegate presentShareFromView:_appDelegate.canvasView rect:NSMakeRect(10, 10, 1, 1)];
    XCTAssertNil(_appDelegate.openSharePicker, @"No picker over the chosen service's window");

    [_appDelegate sharingService:picked didFailToShareItems:@[]
                           error:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
    XCTAssertNil(_appDelegate.sharingServiceInProgress, @"Cancelled, it's over");

    // Closing the picker without a choice starts nothing.
    [_appDelegate sharingServicePicker:picker didChooseSharingService:nil];
    XCTAssertNil(_appDelegate.sharingServiceInProgress);
    [_appDelegate.window orderOut:nil];
}
#endif

@end
