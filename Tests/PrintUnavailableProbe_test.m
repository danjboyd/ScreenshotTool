/* Linux's no-portal print fallback: offer a PDF, preserve the options, and let either
 * dialog cancel. Use a private bus without activation directories, for example:
 * xvfb-run -a dbus-run-session --config-file=Tests/Fixtures/print-noportal-dbus.conf \
 *   -- Tools/run_tests.sh PrintUnavailableProbeTests PrintPortalProbeTests
 */
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if defined(__linux__)
#import <objc/runtime.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "STPrintOptions.h"
#import "STPrintPanelController.h"
#import "STPrintPortal.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (PrintUnavailableProbe)
- (void)setupWindowAndContent;
- (ScreenshotCanvasView *)canvasView;
- (void)printDocument:(id)sender;
- (void)printSelection:(id)sender;
- (void)savePrintAsPDFWithOptions:(STPrintOptions *)options;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
@end

@interface ScreenshotCanvasView (PrintUnavailableProbe)
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
@end

@interface STUnavailablePrintApp : AppDelegate
@property (nonatomic) NSUInteger fallbackCount;
@property (nonatomic, strong) STPrintOptions *fallbackOptions;
@end
@implementation STUnavailablePrintApp
- (void)savePrintAsPDFWithOptions:(STPrintOptions *)options {
    self.fallbackCount++;
    self.fallbackOptions = [options copy];
    [super savePrintAsPDFWithOptions:options];
}
@end

// Replace only modal interaction; the application's actual PDF writer still runs.
@interface STUnavailableSavePanel : NSObject
@property (nonatomic, copy) NSArray<NSString *> *allowedFileTypes;
@property (nonatomic, copy) NSString *nameFieldStringValue;
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic) NSInteger response;
- (NSInteger)runModal;
@end
@implementation STUnavailableSavePanel
- (NSInteger)runModal { return self.response; }
@end

static NSAlert *STUnavailableAlert;
static NSInteger STUnavailableAlertResponse;
static STUnavailableSavePanel *STUnavailablePanel;
static void (^STPrintProbeScenario)(STPrintPortalWriter, STPrintPortalCompletion);
static NSUInteger STPrintProbeFlattenCount;
static IMP STPrintProbeRealFlatten;
static NSImage *STPrintProbeCountFlatten(id canvas, SEL command) {
    STPrintProbeFlattenCount++;
    return ((NSImage *(*)(id, SEL))STPrintProbeRealFlatten)(canvas, command);
}
static BOOL STPrintProbeBusy(id cls, SEL command) {
    (void)cls; (void)command;
    return YES;
}
static void STPrintProbeRequest(id cls, SEL command, NSWindow *window, NSString *title,
                                NSDictionary *pageSetup, STPrintPortalWriter writer,
                                STPrintPortalCompletion completion) {
    (void)cls; (void)command; (void)window; (void)title; (void)pageSetup;
    STPrintProbeScenario(writer, completion);
}
static NSInteger STUnavailableRunAlert(id alert, SEL command) {
    (void)command;
    STUnavailableAlert = alert;
    return STUnavailableAlertResponse;
}
static BOOL STUnavailableConfirmPrint(id panel, SEL command) {
    (void)panel;
    (void)command;
    return YES;
}
static id STUnavailableSavePanelInstance(id cls, SEL command) {
    (void)cls;
    (void)command;
    return STUnavailablePanel;
}

@interface PrintUnavailableProbeTests : XCTestCase
@end
@implementation PrintUnavailableProbeTests {
    STUnavailablePrintApp *_app;
    NSString *_directory;
    IMP _alertRun;
    IMP _printRun;
    IMP _savePanel;
    IMP _portalRequest;
    IMP _portalBusy;
}

+ (void)load { STConfigureTestDefaults(); }

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[STDefaultsPrintFitKey, STDefaultsPrintCustomScaleKey,
                            STDefaultsPrintEnlargeToFillKey, STDefaultsPrintOrientationKey]) {
        [defaults removeObjectForKey:key];
    }
    // Keep this test independent of any configured system printer.
    STPrintSavePaperSize(defaults, NSMakeSize(612, 792));
    _app = [[STUnavailablePrintApp alloc] init];
    [_app setupWindowAndContent];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(200, 100)];
    [image lockFocus];
    [[NSColor blueColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 200, 100));
    [image unlockFocus];
    [_app.canvasView loadImage:image];
    [_app setValue:[NSURL fileURLWithPath:@"/tmp/print-probe/report.png"] forKey:@"currentImageURL"];
    _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:NULL];
    STUnavailablePanel = [[STUnavailableSavePanel alloc] init];
    STUnavailablePanel.URL = [NSURL fileURLWithPath:[_directory stringByAppendingPathComponent:@"report.pdf"]];
    STUnavailablePanel.response = NSModalResponseOK;
    STUnavailableAlertResponse = NSAlertFirstButtonReturn;
    STUnavailableAlert = nil;
    _alertRun = method_setImplementation(class_getInstanceMethod([NSAlert class], @selector(runModal)), (IMP)STUnavailableRunAlert);
    _printRun = method_setImplementation(class_getInstanceMethod([STPrintPanelController class], @selector(runModal)), (IMP)STUnavailableConfirmPrint);
    _savePanel = method_setImplementation(class_getClassMethod([NSSavePanel class], @selector(savePanel)), (IMP)STUnavailableSavePanelInstance);
}

- (void)tearDown {
    if (_portalRequest) {
        method_setImplementation(class_getClassMethod([STPrintPortal class], @selector(printForWindow:title:pageSetup:writer:completion:)), _portalRequest);
    }
    if (_portalBusy) {
        method_setImplementation(class_getClassMethod([STPrintPortal class], @selector(isPrinting)), _portalBusy);
    }
    if (STPrintProbeRealFlatten) {
        method_setImplementation(class_getInstanceMethod([ScreenshotCanvasView class], @selector(flattenedImage)), STPrintProbeRealFlatten);
        STPrintProbeRealFlatten = NULL;
    }
    STPrintProbeScenario = nil;
    method_setImplementation(class_getInstanceMethod([NSAlert class], @selector(runModal)), _alertRun);
    method_setImplementation(class_getInstanceMethod([STPrintPanelController class], @selector(runModal)), _printRun);
    method_setImplementation(class_getClassMethod([NSSavePanel class], @selector(savePanel)), _savePanel);
    [[NSFileManager defaultManager] removeItemAtPath:_directory error:NULL];
    STUnavailableAlert = nil;
    STUnavailablePanel = nil;
    _app = nil;
    [super tearDown];
}

- (void)assertNoPortalOffer {
    XCTAssertNotNil(STUnavailableAlert);
    XCTAssertEqualObjects(STUnavailableAlert.messageText, @"Unable to Print");
    XCTAssertTrue([STUnavailableAlert.informativeText containsString:@"No print service"]);
    XCTAssertEqual(STUnavailableAlert.buttons.count, (NSUInteger)2);
    XCTAssertEqualObjects([STUnavailableAlert.buttons[0] title], @"Save as PDF…");
    XCTAssertEqualObjects([STUnavailableAlert.buttons[1] title], @"Cancel");
    XCTAssertFalse([STPrintPortal isPrinting]);
}

- (void)testNoPortalOffersAndWritesAPDFNamedAfterTheImage {
    [_app printDocument:nil];
    [self assertNoPortalOffer];
    XCTAssertEqual(_app.fallbackCount, (NSUInteger)1);
    XCTAssertFalse(_app.fallbackOptions.selectionOnly);
    XCTAssertEqualObjects(STUnavailablePanel.nameFieldStringValue, @"report.pdf");
    XCTAssertEqualObjects(STUnavailablePanel.allowedFileTypes, (@[@"pdf"]));
    NSData *pdf = [NSData dataWithContentsOfURL:STUnavailablePanel.URL];
    XCTAssertGreaterThan(pdf.length, (NSUInteger)5);
    if (pdf.length >= 5) {
        XCTAssertEqualObjects([[NSString alloc] initWithData:[pdf subdataWithRange:NSMakeRange(0, 5)] encoding:NSASCIIStringEncoding], @"%PDF-");
    }
}

- (void)testCancellingTheNoPortalOfferDoesNotOpenTheSavePanel {
    STUnavailableAlertResponse = NSAlertSecondButtonReturn;
    [_app printDocument:nil];
    [self assertNoPortalOffer];
    XCTAssertEqual(_app.fallbackCount, (NSUInteger)0);
    XCTAssertNil(STUnavailablePanel.nameFieldStringValue);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:STUnavailablePanel.URL.path]);
}

- (void)testCancellingTheSavePanelWritesNothing {
    STUnavailablePanel.response = NSModalResponseCancel;
    [_app printDocument:nil];
    [self assertNoPortalOffer];
    XCTAssertEqual(_app.fallbackCount, (NSUInteger)1);
    XCTAssertEqualObjects(STUnavailablePanel.nameFieldStringValue, @"report.pdf");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:STUnavailablePanel.URL.path]);
}

- (void)testNoPortalPreservesTheSelectionAndUsesTheProjectName {
    [_app setValue:[NSURL fileURLWithPath:@"/tmp/print-probe/annotated.screenshottool"] forKey:@"currentProjectURL"];
    _app.canvasView.hasSelectionRect = YES;
    _app.canvasView.selectionRect = NSMakeRect(20, 10, 60, 40);
    [_app printSelection:nil];
    [self assertNoPortalOffer];
    XCTAssertEqual(_app.fallbackCount, (NSUInteger)1);
    XCTAssertTrue(_app.fallbackOptions.selectionOnly);
    XCTAssertEqualObjects(STUnavailablePanel.nameFieldStringValue, @"annotated.pdf");
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:STUnavailablePanel.URL.path]);
}

- (void)usePortalScenario:(void (^)(STPrintPortalWriter, STPrintPortalCompletion))scenario {
    STPrintProbeScenario = [scenario copy];
    _portalRequest = method_setImplementation(class_getClassMethod([STPrintPortal class], @selector(printForWindow:title:pageSetup:writer:completion:)), (IMP)STPrintProbeRequest);
}

- (NSDictionary *)chosenPageSetup {
    return @{ @"PPDName": @"A4", @"DisplayName": @"A4", @"Width": @210.0, @"Height": @297.0,
              @"MarginTop": @0.0, @"MarginBottom": @0.0, @"MarginLeft": @0.0, @"MarginRight": @0.0 };
}

- (STPrintPortalPageSetup)chosenPaper {
    STPrintPortalPageSetup setup;
    setup.paper = NSMakeSize(595.28, 841.89);
    setup.printerMargins = STPrintMarginsMake(0, 0, 0, 0);
    setup.valid = YES;
    return setup;
}

- (void)rememberOriginalPageSetup {
    STPrintSavePageSetup([NSUserDefaults standardUserDefaults], @{ @"PPDName": @"original" });
}

- (void)assertOriginalPageSetup {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    XCTAssertTrue(NSEqualSizes(STPrintLastPaperSize(defaults), NSMakeSize(612, 792)));
    XCTAssertEqualObjects(STPrintLastPageSetup(defaults), (@{ @"PPDName": @"original" }));
}

- (void)testBusyPrintingDisablesBothCommandsAndSkipsFlattening {
    _portalBusy = method_setImplementation(class_getClassMethod([STPrintPortal class], @selector(isPrinting)), (IMP)STPrintProbeBusy);
    _app.canvasView.hasSelectionRect = YES;
    _app.canvasView.selectionRect = NSMakeRect(20, 10, 60, 40);
    NSMenuItem *document = [[NSMenuItem alloc] initWithTitle:@"Print" action:@selector(printDocument:) keyEquivalent:@""];
    NSMenuItem *selection = [[NSMenuItem alloc] initWithTitle:@"Print Selection" action:@selector(printSelection:) keyEquivalent:@""];
    for (NSMenuItem *item in @[document, selection]) {
        XCTAssertFalse([_app validateMenuItem:item], @"%@ must be disabled during another print", item.title);
    }
    STPrintProbeFlattenCount = 0;
    STPrintProbeRealFlatten = method_setImplementation(class_getInstanceMethod([ScreenshotCanvasView class], @selector(flattenedImage)), (IMP)STPrintProbeCountFlatten);
    [_app printDocument:nil];
    [_app printSelection:nil];
    XCTAssertEqual(STPrintProbeFlattenCount, (NSUInteger)0);
}

- (void)testPDFWriteFailureDoesNotReplaceTheLastPrintedPaper {
    [self rememberOriginalPageSetup];
    [self usePortalScenario:^(STPrintPortalWriter writer, STPrintPortalCompletion completion) {
        // The image is no longer available when the portal asks for the pages.
        [_app.canvasView loadImage:nil];
        XCTAssertFalse(writer([self chosenPaper], [self chosenPageSetup], STUnavailablePanel.URL.path));
        [self assertOriginalPageSetup];
        completion(NO, NO, @"Expected PDF write failure");
    }];
    [_app printDocument:nil];
    [self assertOriginalPageSetup];
}

- (void)testPortalFailureAfterWritingDoesNotReplaceTheLastPrintedPaper {
    [self rememberOriginalPageSetup];
    [self usePortalScenario:^(STPrintPortalWriter writer, STPrintPortalCompletion completion) {
        XCTAssertTrue(writer([self chosenPaper], [self chosenPageSetup], STUnavailablePanel.URL.path));
        [self assertOriginalPageSetup];
        completion(NO, NO, @"Expected printer submission failure");
    }];
    [_app printDocument:nil];
    [self assertOriginalPageSetup];
}

- (void)testCancellingThePortalDoesNotReplaceTheLastPrintedPaper {
    [self rememberOriginalPageSetup];
    [self usePortalScenario:^(STPrintPortalWriter writer, STPrintPortalCompletion completion) {
        (void)writer;
        completion(NO, NO, nil);
    }];
    [_app printDocument:nil];
    [self assertOriginalPageSetup];
}

- (void)testSuccessfulSubmissionRemembersThePaperOnlyAfterCompletion {
    [self rememberOriginalPageSetup];
    [self usePortalScenario:^(STPrintPortalWriter writer, STPrintPortalCompletion completion) {
        XCTAssertTrue(writer([self chosenPaper], [self chosenPageSetup], STUnavailablePanel.URL.path));
        [self assertOriginalPageSetup];
        completion(YES, NO, nil);
    }];
    [_app printDocument:nil];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    XCTAssertTrue(NSEqualSizes(STPrintLastPaperSize(defaults), [self chosenPaper].paper));
    XCTAssertEqualObjects(STPrintLastPageSetup(defaults), [self chosenPageSetup]);
}
@end
#endif
