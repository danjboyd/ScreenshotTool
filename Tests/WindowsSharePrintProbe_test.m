/*
 * WindowsSharePrintProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Print in the share sheet on Windows (#355): libs-sharing's sheet lists Print… for the image and, with a
 * selection, Print Selection…, after its own services and before the custom actions; choosing one is the
 * File menu's Print or Print Selection, so the same Print panel and Windows print dialog follow, and a
 * cancel of either brings the sheet back (libs-sharing's -reportCancelled). Offscreen: the sheet's list is
 * read from libs-sharing's panel without showing it, and the print is recorded instead of opening the panel.
 * The app's main window is made (setupWindowAndContent) but never ordered front.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if defined(_WIN32) && defined(ST_HAVE_LIBS_SHARING)

#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"
#import "GSSharing.h"
#import "GSSharingPickerPanel.h"
#import "GSSharingPrivate.h"

@interface AppDelegate (WindowsSharePrintProbe) <NSSharingServicePickerDelegate>
- (void)setupWindowAndContent;
- (ScreenshotCanvasView *)canvasView;
- (NSArray *)shareItemProviders;
- (BOOL)printWithSelectionOnly:(BOOL)selectionOnly;
@end

@interface ScreenshotCanvasView (WindowsSharePrintProbe)
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
@end

/// Records the prints instead of opening the Print panel; `cancels` stands for the user cancelling it.
@interface STSharePrintRecordingAppDelegate : AppDelegate
@property (nonatomic, strong) NSMutableArray<NSString *> *prints;
@property (nonatomic) BOOL cancels;
@end

@implementation STSharePrintRecordingAppDelegate
- (BOOL)printWithSelectionOnly:(BOOL)selectionOnly {
    [self.prints addObject:selectionOnly ? @"selection" : @"document"];
    return !self.cancels;
}
@end

@interface WindowsSharePrintProbeTests : XCTestCase {
    STSharePrintRecordingAppDelegate *_app;
    NSString *_actionsDirectory;
    NSMutableArray *_observers;
}
@end

@implementation WindowsSharePrintProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _observers = [NSMutableArray array];
    // No custom actions but the test's own, so the sheet's list is known.
    _actionsDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_actionsDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    STSetEnvVar("SCREENSHOT_TOOL_ACTIONS_DIR", _actionsDirectory.UTF8String);
    @try {
        [NSApplication sharedApplication];
        _app = [[STSharePrintRecordingAppDelegate alloc] init];
        _app.prints = [NSMutableArray array];
        [_app setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _app = nil;
    }
}

- (void)tearDown {
    for (id observer in _observers) {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }
    _observers = nil;
    _app = nil;
    [[NSFileManager defaultManager] removeItemAtPath:_actionsDirectory error:NULL];
    [super tearDown];
}

- (void)loadImage {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:120
                                                                    pixelsHigh:80
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    memset(rep.bitmapData, 200, rep.bytesPerRow * rep.pixelsHigh);
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(120, 80)];
    [image addRepresentation:rep];
    [_app.canvasView loadImage:image];
}

- (void)selectPart {
    _app.canvasView.selectionRect = NSMakeRect(10, 10, 40, 30);
    _app.canvasView.hasSelectionRect = YES;
}

/// What the share sheet lists, as libs-sharing's panel asks for it when it shows: its own services
/// that take the PNG a share sends, then what the app's picker delegate makes of them.
- (NSArray<NSSharingService *> *)sheetServices {
    NSSharingServicePicker *picker = [[NSSharingServicePicker alloc] initWithItems:[_app shareItemProviders]];
    picker.delegate = (id<NSSharingServicePickerDelegate>)_app;
    GSSharingPickerPanel *panel = [[GSSharingPickerPanel alloc] initWithPicker:picker];
    return [panel services];
}

- (NSSharingService *)service:(NSString *)title in:(NSArray<NSSharingService *> *)services {
    for (NSSharingService *service in services) {
        if ([service.title isEqualToString:title]) {
            return service;
        }
    }
    return nil;
}

- (void)testNothingToPrintWithoutAnImage {
    XCTSkipIf(_app == nil, @"No window server");
    NSArray *titles = [[_app sharingServicePicker:nil sharingServicesForItems:@[] proposedSharingServices:@[]] valueForKey:@"title"];
    XCTAssertFalse([titles containsObject:@"Print…"], @"%@", titles);
    XCTAssertFalse([titles containsObject:@"Print Selection…"], @"%@", titles);
}

/// The sheet has Print… after libs-sharing's own services (Copy, Save a Copy, Email…), and no Print
/// Selection… without a selection.
- (void)testTheSheetListsPrintAfterItsOwnServices {
    XCTSkipIf(_app == nil, @"No window server");
    [self loadImage];
    NSArray *items = [_app shareItemProviders];
    XCTAssertEqual(items.count, (NSUInteger)1, @"The PNG a share sends");
    NSArray<NSString *> *own = [[NSSharingService sharingServicesForItems:items] valueForKey:@"title"];
    NSArray<NSString *> *titles = [[self sheetServices] valueForKey:@"title"];
    XCTAssertTrue(own.count > 0, @"libs-sharing's services: %@", own);
    NSUInteger print = [titles indexOfObject:@"Print…"];
    XCTAssertNotEqual(print, (NSUInteger)NSNotFound, @"%@", titles);
    for (NSString *title in own) {
        NSUInteger index = [titles indexOfObject:title];
        if (index != NSNotFound) {
            XCTAssertLessThan(index, print, @"%@ comes first: %@", title, titles);
        }
    }
    XCTAssertEqual(print, titles.count - 1, @"Nothing else after it without custom actions: %@", titles);
    XCTAssertFalse([titles containsObject:@"Print Selection…"], @"No selection: %@", titles);
}

/// With a selection the sheet has Print Selection… too, right after Print…, and the custom actions
/// still come last.
- (void)testASelectionAddsPrintSelectionBeforeTheActions {
    XCTSkipIf(_app == nil, @"No window server");
    NSString *action = @"{\"title\": \"Echo\", \"command\": [\"cmd.exe\", \"/c\", \"echo\", \"echoed\"]}";
    [action writeToFile:[_actionsDirectory stringByAppendingPathComponent:@"echo.json"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    // The actions are read once, by the app made after the file.
    _app = [[STSharePrintRecordingAppDelegate alloc] init];
    _app.prints = [NSMutableArray array];
    [_app setupWindowAndContent];
    [self loadImage];
    [self selectPart];
    NSArray<NSString *> *titles = [[self sheetServices] valueForKey:@"title"];
    NSUInteger print = [titles indexOfObject:@"Print…"];
    NSUInteger selection = [titles indexOfObject:@"Print Selection…"];
    XCTAssertNotEqual(print, (NSUInteger)NSNotFound, @"%@", titles);
    XCTAssertEqual(selection, print + 1, @"%@", titles);
    NSUInteger echo = [titles indexOfObject:@"Echo"];
    XCTAssertNotEqual(echo, (NSUInteger)NSNotFound, @"%@", titles);
    XCTAssertGreaterThan(echo, selection, @"Custom actions after Print: %@", titles);
}

/// Print says nothing of its own ("Shared with Print…"): the Print panel and the print dialog that
/// follow are what it shows. libs-sharing's own services still report back.
- (void)testPrintHasNoShareMessage {
    XCTSkipIf(_app == nil, @"No window server");
    [self loadImage];
    [self selectPart];
    NSArray<NSSharingService *> *services = [self sheetServices];
    XCTAssertNil([_app sharingServicePicker:nil delegateForSharingService:[self service:@"Print…" in:services]]);
    XCTAssertNil([_app sharingServicePicker:nil delegateForSharingService:[self service:@"Print Selection…" in:services]]);
    NSSharingService *own = [NSSharingService sharingServicesForItems:[_app shareItemProviders]].firstObject;
    XCTAssertNotNil(own);
    XCTAssertTrue([_app sharingServicePicker:nil delegateForSharingService:own] == (id)_app, @"%@ reports back", own.title);
}

/// Choosing Print… is File > Print…; Print Selection… is the context menu's Print Selection…: the
/// same panel, options and Windows print dialog (PrintDlgEx) for the whole image or the selection.
- (void)testChoosingPrintIsTheFileMenusPrint {
    XCTSkipIf(_app == nil, @"No window server");
    [self loadImage];
    [self selectPart];
    NSArray<NSSharingService *> *services = [self sheetServices];
    NSArray *items = [_app shareItemProviders];
    [[self service:@"Print…" in:services] performWithItems:items];
    XCTAssertEqualObjects(_app.prints, (@[@"document"]));
    [[self service:@"Print Selection…" in:services] performWithItems:items];
    XCTAssertEqualObjects(_app.prints, (@[@"document", @"selection"]));
}

/// The ends libs-sharing's sheet watches for (GSSharingServiceDidFinishNotification), with their errors.
- (NSMutableArray<NSError *> *)watchEndsOf:(NSSharingService *)service {
    NSMutableArray<NSError *> *ends = [NSMutableArray array];
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:GSSharingServiceDidFinishNotification
                                                                   object:service
                                                                    queue:nil
                                                               usingBlock:^(NSNotification *note) {
        [ends addObject:note.userInfo[@"error"] ?: (NSError *)[NSNull null]];
    }];
    [_observers addObject:observer];
    return ends;
}

/// Cancelling our Print panel or Windows's dialog, chosen from the sheet, reports a cancel: the sheet
/// watching for the service's end (as for Save a Copy's panel) comes back.
- (void)testACancelledPrintBringsTheSheetBack {
    XCTSkipIf(_app == nil, @"No window server");
    [self loadImage];
    [self selectPart];
    NSArray<NSSharingService *> *services = [self sheetServices];
    _app.cancels = YES;
    for (NSString *title in @[ @"Print…", @"Print Selection…" ]) {
        NSSharingService *service = [self service:title in:services];
        NSMutableArray<NSError *> *ends = [self watchEndsOf:service];
        [service performWithItems:[_app shareItemProviders]];
        XCTAssertEqual(ends.count, (NSUInteger)1, @"%@: one end", title);
        NSError *error = ends.firstObject;
        XCTAssertTrue([error isKindOfClass:[NSError class]], @"%@: %@", title, error);
        XCTAssertEqualObjects(error.domain, NSCocoaErrorDomain, @"%@", title);
        XCTAssertEqual(error.code, (NSInteger)NSUserCancelledError, @"%@", title);
    }
    XCTAssertEqualObjects(_app.prints, (@[@"document", @"selection"]));
}

/// A print that goes ahead (or fails, saying so itself) reports no end: the sheet stays closed.
- (void)testAPrintThatGoesAheadLeavesTheSheetClosed {
    XCTSkipIf(_app == nil, @"No window server");
    [self loadImage];
    NSSharingService *print = [self service:@"Print…" in:[self sheetServices]];
    NSMutableArray<NSError *> *ends = [self watchEndsOf:print];
    [print performWithItems:[_app shareItemProviders]];
    XCTAssertEqualObjects(_app.prints, (@[@"document"]));
    XCTAssertEqual(ends.count, (NSUInteger)0);
}

/// What's printed is what's there when it's chosen: a selection gone by then prints nothing, as
/// Print Selection… would be off in the menus.
- (void)testPrintSelectionWithTheSelectionGonePrintsNothing {
    XCTSkipIf(_app == nil, @"No window server");
    [self loadImage];
    [self selectPart];
    NSSharingService *selection = [self service:@"Print Selection…" in:[self sheetServices]];
    XCTAssertNotNil(selection);
    _app.canvasView.hasSelectionRect = NO;
    [selection performWithItems:@[]];
    XCTAssertEqualObjects(_app.prints, (@[]));
}

@end

#endif
