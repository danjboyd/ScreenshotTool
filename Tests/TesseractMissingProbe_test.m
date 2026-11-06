/*
 * TesseractMissingProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * On Linux and the BSDs the text commands stay in the menus without tesseract, say how to install
 * it instead of running, and work once it's there, with no restart. "tesseract isn't installed" is
 * the lookup replaced, so this doesn't depend on what the machine has.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "STCanvasContextMenu.h"
#import "STTextRecognizer.h"
#import "TestEnvironmentHelpers.h"

#if defined(GNUSTEP) && !defined(_WIN32)

@interface AppDelegate (TesseractMissingTesting)
- (void)setupWindowAndContent;
- (void)setupMenus;
- (ScreenshotCanvasView *)canvasView;
- (BOOL)readingText;
- (void)copyText:(id)sender;
- (void)selectText:(id)sender;
- (void)redactDetectedText:(id)sender;
- (void)showTesseractMissingAlert;
- (nullable NSMenu *)canvasContextMenuForKind:(STCanvasContextKind)kind;
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
@end

@interface STTextRecognizer (TesseractMissingTesting)
+ (nullable NSString *)tesseractPath;
@end

extern NSString *STTesseractMissingAlertText(void);

/// Counts the alert, which would otherwise wait for a click.
@interface TesseractMissingProbeAppDelegate : AppDelegate
@property (nonatomic, assign) NSUInteger alerts;
@end

@implementation TesseractMissingProbeAppDelegate
- (void)showTesseractMissingAlert {
    self.alerts++;
}
@end

static id STNoTesseractPath(id self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    return nil;
}

@interface TesseractMissingProbeTests : XCTestCase {
    BOOL _shouldSkip;
    TesseractMissingProbeAppDelegate *_app;
    IMP _realLookup;
}
@end

@implementation TesseractMissingProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        _app = [[TesseractMissingProbeAppDelegate alloc] init];
        [_app setupWindowAndContent];
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(200.0, 100.0)];
        [image lockFocus];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0.0, 0.0, 200.0, 100.0));
        [image unlockFocus];
        [_app.canvasView loadImage:image];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
    _realLookup = NULL;
}

- (void)tearDown {
    [self restoreTesseract];
    _app = nil;
    [super tearDown];
}

- (void)removeTesseract {
    Method lookup = class_getClassMethod([STTextRecognizer class], @selector(tesseractPath));
    _realLookup = method_setImplementation(lookup, (IMP)STNoTesseractPath);
}

- (void)restoreTesseract {
    if (_realLookup) {
        method_setImplementation(class_getClassMethod([STTextRecognizer class], @selector(tesseractPath)), _realLookup);
        _realLookup = NULL;
    }
}

- (NSMenuItem *)itemWithAction:(SEL)action inMenu:(NSMenu *)menu {
    NSInteger index = [menu indexOfItemWithTarget:_app andAction:action];
    return index >= 0 ? [menu itemAtIndex:index] : nil;
}

- (void)testTheCommandsAreInTheMenusAndEnabledWithoutTesseract {
    XCTSkipIf(_shouldSkip, @"No window server");
    [self removeTesseract];
    XCTAssertFalse([STTextRecognizer isAvailable]);
    XCTAssertTrue([STTextRecognizer isOffered]);
    XCTAssertTrue([STTextRecognizer needsInstalling]);

    [_app setupMenus];
    NSMenu *edit = [[[NSApp mainMenu] itemWithTitle:@"Edit"] submenu];
    for (NSString *selector in @[ @"copyText:", @"selectText:", @"redactDetectedText:" ]) {
        NSMenuItem *item = [self itemWithAction:NSSelectorFromString(selector) inMenu:edit];
        XCTAssertNotNil(item, @"%@ should be in the Edit menu", selector);
        XCTAssertTrue([_app validateMenuItem:item], @"%@ should be enabled with an image open", selector);
    }
    XCTAssertNotNil([self itemWithAction:@selector(redactSelectedText:) inMenu:edit]);

    NSMenu *context = [_app canvasContextMenuForKind:STCanvasContextKindImage];
    XCTAssertNotNil([self itemWithAction:@selector(copyText:) inMenu:context]);
    XCTAssertNotNil([self itemWithAction:@selector(selectText:) inMenu:context]);
}

- (void)testPickingOneExplainsAndRunsNothing {
    XCTSkipIf(_shouldSkip, @"No window server");
    [self removeTesseract];
    [_app copyText:nil];
    XCTAssertEqual(_app.alerts, (NSUInteger)1);
    XCTAssertFalse(_app.readingText, @"Nothing should be reading");
    [_app selectText:nil];
    XCTAssertEqual(_app.alerts, (NSUInteger)2);
    XCTAssertFalse(_app.canvasView.isSelectingText);
    [_app redactDetectedText:nil];
    XCTAssertEqual(_app.alerts, (NSUInteger)3);
    XCTAssertFalse(_app.readingText);
}

- (void)testTheAlertSaysHow {
    NSString *text = STTesseractMissingAlertText();
    for (NSString *command in @[ @"apt install tesseract-ocr", @"dnf install tesseract", @"pacman -S tesseract tesseract-data-eng",
                                 @"zypper install tesseract-ocr" ]) {
        XCTAssertTrue([text rangeOfString:command].location != NSNotFound, @"%@", command);
    }
}

/// Installing it works at once: the lookup isn't kept from one use to the next.
- (void)testItWorksOnceInstalledWithNoRestart {
    XCTSkipIf(_shouldSkip, @"No window server");
    [self removeTesseract];
    [_app copyText:nil];
    XCTAssertEqual(_app.alerts, (NSUInteger)1);
    [self restoreTesseract];
    if ([STTextRecognizer needsInstalling]) {
        NSLog(@"tesseract isn't installed: reading isn't tried");
        return;
    }
    [_app copyText:nil];
    XCTAssertEqual(_app.alerts, (NSUInteger)1, @"With tesseract there, no alert");
    XCTAssertTrue(_app.readingText, @"With tesseract there, it reads");
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30.0];
    while (_app.readingText && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    XCTAssertFalse(_app.readingText);
}

@end

#endif
