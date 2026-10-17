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

@end
