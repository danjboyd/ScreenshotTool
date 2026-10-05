/*
 * ProjectFileProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Editable project files and the unsaved-changes prompt (#32).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "MarkupText.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (ProjectFileTesting)
- (void)setupWindowAndContent;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
- (BOOL)openImageAtURL:(NSURL *)url;
- (BOOL)writeProjectToURL:(NSURL *)url;
- (BOOL)hasUnsavedChanges;
- (BOOL)confirmProceedingWithUnsavedChanges;
- (BOOL)windowShouldClose:(id)sender;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)saveProject:(id)sender;
@end

@interface ScreenshotCanvasView (ProjectFileTesting)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@property (nonatomic, strong) NSMutableArray<MarkupText *> *texts;
@end

/// Answers the unsaved-changes alert without running it, and counts how often it was asked.
@interface STPromptStubAppDelegate : AppDelegate
@property (nonatomic, assign) NSInteger stubbedChoice;
@property (nonatomic, assign) NSInteger promptCount;
@end

@implementation STPromptStubAppDelegate
- (NSInteger)askAboutUnsavedChanges {
    self.promptCount += 1;
    return self.stubbedChoice;
}
@end

@interface ProjectFileProbeTests : XCTestCase {
    BOOL _shouldSkip;
    STPromptStubAppDelegate *_appDelegate;
    NSString *_directory;
}
@end

@implementation ProjectFileProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"st-project-%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:NULL];
    @try {
        [NSApplication sharedApplication];
        _appDelegate = [[STPromptStubAppDelegate alloc] init];
        [_appDelegate setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    _appDelegate = nil;
    [[NSFileManager defaultManager] removeItemAtPath:_directory error:NULL];
    [super tearDown];
}

#pragma mark - Helpers

- (NSURL *)writeImageNamed:(NSString *)name color:(NSColor *)color {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:200
                                                                    pixelsHigh:120
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    for (NSInteger y = 0; y < 120; y++) {
        for (NSInteger x = 0; x < 200; x++) {
            [rep setColor:(x < 100 ? color : [NSColor whiteColor]) atX:x y:y];
        }
    }
    NSData *png = [rep representationUsingType:NSPNGFileType properties:@{}];
    NSURL *url = [NSURL fileURLWithPath:[_directory stringByAppendingPathComponent:name]];
    [png writeToURL:url atomically:YES];
    return url;
}

- (void)annotate {
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    MarkupStroke *pen = [[MarkupStroke alloc] initWithType:MarkupStrokeTypePen color:[NSColor redColor] lineWidth:3.0];
    [pen addPoint:NSMakePoint(10, 10)];
    [pen addPoint:NSMakePoint(40, 30)];
    MarkupStroke *arrow = [[MarkupStroke alloc] initWithType:MarkupStrokeTypeArrow color:[NSColor blueColor] lineWidth:4.0];
    [arrow addPoint:NSMakePoint(150, 20)];
    [arrow setEndPoint:NSMakePoint(110, 90)];
    MarkupText *label = [[MarkupText alloc] initWithText:@"Look here"
                                                    font:[NSFont fontWithName:@"DejaVuSans" size:16.0] ?: [NSFont systemFontOfSize:16.0]
                                                   color:[NSColor yellowColor]
                                                  origin:NSMakePoint(20, 60)
                                                 boxSize:NSMakeSize(100, 24)];
    label.style = MarkupTextStyleBackground;
    label.alignment = NSTextAlignmentCenter;
    label.hasPointer = YES;
    label.pointerTarget = NSMakePoint(160, 100);
    canvas.strokes = [@[pen, arrow] mutableCopy];
    canvas.texts = [@[label] mutableCopy];
}

#pragma mark - Tests

- (void)testProjectRoundTripKeepsImageAndEditableAnnotations {
    XCTSkipIf(_shouldSkip, @"No window server");
    XCTAssertTrue([_appDelegate openImageAtURL:[self writeImageNamed:@"shot.png" color:[NSColor greenColor]]]);
    [self annotate];
    NSURL *projectURL = [NSURL fileURLWithPath:[_directory stringByAppendingPathComponent:@"shot.screenshottool"]];
    XCTAssertTrue([_appDelegate writeProjectToURL:projectURL]);
    XCTAssertFalse([_appDelegate hasUnsavedChanges]);

    STPromptStubAppDelegate *reopened = [[STPromptStubAppDelegate alloc] init];
    [reopened setupWindowAndContent];
    XCTAssertTrue([reopened openImageAtURL:projectURL]);
    ScreenshotCanvasView *canvas = reopened.canvasView;
    XCTAssertEqualWithAccuracy(canvas.image.size.width, 200.0, 0.5);
    XCTAssertEqualWithAccuracy(canvas.image.size.height, 120.0, 0.5);
    XCTAssertEqual(canvas.strokes.count, (NSUInteger)2);
    XCTAssertEqual(canvas.strokes[1].type, MarkupStrokeTypeArrow);
    XCTAssertEqual(canvas.strokes[1].points.count, (NSUInteger)2);
    XCTAssertEqualWithAccuracy([canvas.strokes[1].points[1] pointValue].x, 110.0, 0.01);
    XCTAssertEqualWithAccuracy(canvas.strokes[0].lineWidth, 3.0, 0.01);
    XCTAssertEqual(canvas.texts.count, (NSUInteger)1);
    MarkupText *label = canvas.texts[0];
    XCTAssertEqualObjects(label.text, @"Look here");
    XCTAssertEqual(label.style, MarkupTextStyleBackground);
    XCTAssertEqual(label.alignment, NSTextAlignmentCenter);
    XCTAssertTrue(label.hasPointer);
    XCTAssertEqualWithAccuracy(label.pointerTarget.x, 160.0, 0.01);
    XCTAssertEqualWithAccuracy(label.font.pointSize, 16.0, 0.01);
    XCTAssertFalse([reopened hasUnsavedChanges], @"a freshly opened project is clean");

    // The stored image is the original, not one with the annotations burnt in.
    NSBitmapImageRep *rep = nil;
    for (NSImageRep *candidate in canvas.image.representations) {
        if ([candidate isKindOfClass:[NSBitmapImageRep class]]) { rep = (NSBitmapImageRep *)candidate; }
    }
    XCTAssertNotNil(rep);
    NSColor *pixel = [[rep colorAtX:12 y:120 - 12] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    XCTAssertLessThan(pixel.redComponent, 0.1, @"no red pen stroke in the stored image");
    XCTAssertGreaterThan(pixel.greenComponent, 0.9);
}

- (void)testDamagedOrForeignProjectsAreRejected {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSError *error = nil;
    XCTAssertFalse([canvas loadProjectData:[@"not json" dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    XCTAssertNotNil(error);

    NSData *foreign = [NSJSONSerialization dataWithJSONObject:@{ @"format": @"something-else", @"version": @1 } options:0 error:NULL];
    error = nil;
    XCTAssertFalse([canvas loadProjectData:foreign error:&error]);
    XCTAssertNotNil(error);

    NSData *newer = [NSJSONSerialization dataWithJSONObject:@{ @"format": @"screenshottool-project", @"version": @99 } options:0 error:NULL];
    error = nil;
    XCTAssertFalse([canvas loadProjectData:newer error:&error]);
    XCTAssertTrue([error.localizedDescription rangeOfString:@"newer"].location != NSNotFound, @"%@", error.localizedDescription);
    XCTAssertFalse([canvas hasImage], @"nothing is half-loaded");
}

- (void)testEditsMarkTheDocumentDirtyAndUndoCleansIt {
    XCTSkipIf(_shouldSkip, @"No window server");
    XCTAssertTrue([_appDelegate openImageAtURL:[self writeImageNamed:@"a.png" color:[NSColor greenColor]]]);
    XCTAssertFalse([_appDelegate hasUnsavedChanges]);
    [self annotate];
    XCTAssertTrue([_appDelegate hasUnsavedChanges]);
    _appDelegate.canvasView.strokes = [NSMutableArray array];
    _appDelegate.canvasView.texts = [NSMutableArray array];
    XCTAssertFalse([_appDelegate hasUnsavedChanges], @"back to how it was opened");
}

- (void)testPromptDecidesWhetherToProceed {
    XCTSkipIf(_shouldSkip, @"No window server");
    XCTAssertTrue([_appDelegate openImageAtURL:[self writeImageNamed:@"b.png" color:[NSColor greenColor]]]);
    XCTAssertTrue([_appDelegate confirmProceedingWithUnsavedChanges]);
    XCTAssertEqual(_appDelegate.promptCount, 0, @"no prompt without changes");

    [self annotate];
    _appDelegate.stubbedChoice = 2; // Cancel
    XCTAssertFalse([_appDelegate windowShouldClose:_appDelegate.window]);
    XCTAssertEqual(_appDelegate.promptCount, 1);

    _appDelegate.stubbedChoice = 1; // Don't Save
    XCTAssertTrue([_appDelegate confirmProceedingWithUnsavedChanges]);

    // Save goes straight to the open project, with no panel.
    NSURL *projectURL = [NSURL fileURLWithPath:[_directory stringByAppendingPathComponent:@"b.screenshottool"]];
    XCTAssertTrue([_appDelegate writeProjectToURL:projectURL]);
    [_appDelegate.canvasView.strokes removeLastObject];
    XCTAssertTrue([_appDelegate hasUnsavedChanges]);
    _appDelegate.stubbedChoice = 0; // Save
    XCTAssertTrue([_appDelegate confirmProceedingWithUnsavedChanges]);
    XCTAssertFalse([_appDelegate hasUnsavedChanges]);
    NSData *saved = [NSData dataWithContentsOfURL:projectURL];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:saved options:0 error:NULL];
    XCTAssertEqual([json[@"strokes"] count], (NSUInteger)1);
}

- (void)testSaveProjectMenuItemNeedsAnImage {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Save Project…" action:@selector(saveProject:) keyEquivalent:@""];
    [_appDelegate.canvasView loadImage:nil];
    XCTAssertFalse([_appDelegate validateMenuItem:item]);
    XCTAssertTrue([_appDelegate openImageAtURL:[self writeImageNamed:@"c.png" color:[NSColor greenColor]]]);
    XCTAssertTrue([_appDelegate validateMenuItem:item]);
}

@end
