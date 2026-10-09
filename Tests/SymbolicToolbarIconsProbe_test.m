/*
 * SymbolicToolbarIconsProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Every image the toolbar shows is named `…-symbolic`, which is how a theme that tints template
 * images (Adwaita) knows to tint it: GNUstep 0.32 has no -[NSImage setTemplate:]. GNUstep's
 * -[NSImage copy] has no name, so the toolbar's copies were left untinted, dark grey on Adwaita's
 * dark header bar.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (SymbolicToolbarIconsTesting)
- (void)setupWindowAndContent;
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag;
- (NSImage *)toolbarImageForIdentifier:(NSToolbarItemIdentifier)identifier active:(BOOL)active;
- (NSImage *)toolbarSegmentImageForTool:(ScreenshotCanvasTool)tool selected:(BOOL)selected;
@end

@interface SymbolicToolbarIconsProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation SymbolicToolbarIconsProbeTests

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

#if defined(GNUSTEP)
- (void)testToolbarButtonImagesAreNamedSymbolic {
    XCTSkipIf(_shouldSkip, @"No window server");
    for (NSString *identifier in @[@"com.screenshottool.toolbar.undo", @"com.screenshottool.toolbar.redo"]) {
        // The item's first image, then the one each refresh puts in its place.
        NSToolbarItem *item = [_appDelegate toolbar:nil itemForItemIdentifier:identifier willBeInsertedIntoToolbar:YES];
        XCTAssertTrue([[item.image name] hasSuffix:@"-symbolic"], @"%@ starts tinted: %@", identifier, [item.image name]);
        NSImage *refreshed = [_appDelegate toolbarImageForIdentifier:identifier active:NO];
        XCTAssertNotNil(refreshed);
        XCTAssertTrue([[refreshed name] hasSuffix:@"-symbolic"], @"%@ stays tinted: %@", identifier, [refreshed name]);
        XCTAssertEqual([_appDelegate toolbarImageForIdentifier:identifier active:NO], refreshed,
                       @"named once and handed out again: a registered name can't be given twice");
    }
}

- (void)testToolSwitcherImagesAreNamedSymbolic {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasTool tools[] = {ScreenshotCanvasToolSelect, ScreenshotCanvasToolHighlighter, ScreenshotCanvasToolPen,
                                    ScreenshotCanvasToolArrow, ScreenshotCanvasToolText, ScreenshotCanvasToolEraser};
    for (size_t index = 0; index < sizeof(tools) / sizeof(tools[0]); index++) {
        NSImage *image = [_appDelegate toolbarSegmentImageForTool:tools[index] selected:NO];
        XCTAssertNotNil(image);
        XCTAssertTrue([[image name] hasSuffix:@"-symbolic"], @"tool %ld: %@", (long)tools[index], [image name]);
        XCTAssertEqual([_appDelegate toolbarSegmentImageForTool:tools[index] selected:NO], image);
    }
}
/// Each icon has a bitmap rendered at each size the toolbar draws it at, and the one drawn at a size
/// is that size's, pixel for pixel: icons resampled to fit looked soft.
- (void)testIconsHaveARepresentationAtEachDrawnSize {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSMutableArray<NSImage *> *images = [NSMutableArray array];
    for (NSString *identifier in @[@"com.screenshottool.toolbar.undo", @"com.screenshottool.toolbar.redo",
                                   @"com.screenshottool.toolbar.copy"]) {
        // The item first, as the toolbar makes it: it names the first image.
        [_appDelegate toolbar:nil itemForItemIdentifier:identifier willBeInsertedIntoToolbar:YES];
        NSImage *image = [_appDelegate toolbarImageForIdentifier:identifier active:NO];
        XCTAssertNotNil(image, @"%@", identifier);
        if (image) {
            [images addObject:image];
        }
    }
    ScreenshotCanvasTool tools[] = {ScreenshotCanvasToolSelect, ScreenshotCanvasToolHighlighter, ScreenshotCanvasToolPen,
                                    ScreenshotCanvasToolArrow, ScreenshotCanvasToolText, ScreenshotCanvasToolEraser};
    for (size_t index = 0; index < sizeof(tools) / sizeof(tools[0]); index++) {
        NSImage *image = [_appDelegate toolbarSegmentImageForTool:tools[index] selected:NO];
        XCTAssertNotNil(image);
        if (image) {
            [images addObject:image];
        }
    }
    for (NSImage *image in images) {
        for (NSNumber *points in @[@16, @22, @24, @32]) {
            CGFloat size = points.doubleValue;
            NSImageRep *rep = [image bestRepresentationForRect:NSMakeRect(0.0, 0.0, size, size) context:nil hints:nil];
            XCTAssertTrue([rep isKindOfClass:[NSBitmapImageRep class]], @"%@ at %@", [image name], points);
            XCTAssertEqual(rep.pixelsWide, (NSInteger)size, @"%@ is drawn at %@ from a bitmap that size", [image name], points);
            XCTAssertEqualWithAccuracy(rep.size.width, size, 0.001, @"%@ at %@", [image name], points);
        }
    }
}
#endif

@end
