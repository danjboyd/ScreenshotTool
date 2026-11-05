/*
 * PrintPanelProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Linux's Print panel (#355): its controls change the options, the page count and what's printed, and
 * only Print saves them. Driven through the controls, without running the panel modally.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if defined(__linux__)

#import "STPrintPanelController.h"

@interface PrintPanelProbeTests : XCTestCase
@end

@implementation PrintPanelProbeTests

- (void)clearDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[ STDefaultsPrintFitKey, STDefaultsPrintCustomScaleKey, STDefaultsPrintEnlargeToFillKey,
                             STDefaultsPrintOrientationKey,
                             @"ScreenshotToolPrintPaperWidth", @"ScreenshotToolPrintPaperHeight" ]) {
        [defaults removeObjectForKey:key];
    }
}

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
    [self clearDefaults];
    STPrintSavePaperSize([NSUserDefaults standardUserDefaults], NSMakeSize(612, 792));
}

- (void)tearDown {
    [self clearDefaults];
    [super tearDown];
}

- (NSImage *)imageWithWidth:(NSInteger)width height:(NSInteger)height {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:width
                                                                    pixelsHigh:height
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [image addRepresentation:rep];
    return image;
}

- (STPrintPanelController *)panelWithSelection:(NSRect)selection selectionOnly:(BOOL)selectionOnly {
    return [[STPrintPanelController alloc] initWithFlattenedImage:[self imageWithWidth:3000 height:2000]
                                                        selection:selection
                                                    selectionOnly:selectionOnly
                                                         defaults:[NSUserDefaults standardUserDefaults]];
}

- (void)choose:(NSInteger)index in:(NSPopUpButton *)popUp {
    [popUp selectItemAtIndex:index];
    [popUp sendAction:popUp.action to:popUp.target];
}

- (void)testItStartsFittingTheWholeImageOnOnePage {
    STPrintPanelController *panel = [self panelWithSelection:NSZeroRect selectionOnly:NO];
    XCTAssertEqual([panel currentLayout].pageCount, (NSUInteger)1);
    XCTAssertEqual(panel.fitPopUp.indexOfSelectedItem, (NSInteger)0);
    XCTAssertTrue(panel.scaleField.isHidden);
    XCTAssertFalse(panel.enlargeCheckbox.isHidden);
    XCTAssertTrue(panel.nextPageButton.isHidden);
    XCTAssertTrue(panel.printButton.isEnabled);
    XCTAssertTrue([panel.summaryLabel.stringValue hasPrefix:@"1 page"], @"%@", panel.summaryLabel.stringValue);
}

/// Each row has its own place, inside the panel, apart from the two that share one and show in turn.
- (void)testTheControlsDoNotOverlap {
    STPrintPanelController *panel = [self panelWithSelection:NSZeroRect selectionOnly:NO];
    NSArray<NSView *> *rows = @[ panel.contentPopUp, panel.fitPopUp, panel.enlargeCheckbox, panel.orientationPopUp ];
    NSRect content = panel.panel.contentView.bounds;
    for (NSUInteger i = 0; i < rows.count; i++) {
        XCTAssertTrue(NSContainsRect(content, rows[i].frame), @"row %lu is outside", (unsigned long)i);
        for (NSUInteger j = i + 1; j < rows.count; j++) {
            XCTAssertFalse(NSIntersectsRect(rows[i].frame, rows[j].frame), @"rows %lu and %lu", (unsigned long)i, (unsigned long)j);
        }
    }
    XCTAssertFalse(NSIntersectsRect(panel.scaleField.frame, panel.fitPopUp.frame));
    XCTAssertFalse(NSIntersectsRect(panel.scaleField.frame, panel.orientationPopUp.frame));
}

- (void)testSelectionNeedsASelection {
    STPrintPanelController *none = [self panelWithSelection:NSZeroRect selectionOnly:YES];
    XCTAssertFalse(none.contentPopUp.isEnabled);
    XCTAssertFalse(none.options.selectionOnly);

    NSRect selection = NSMakeRect(100, 50, 300, 200);
    STPrintPanelController *some = [self panelWithSelection:selection selectionOnly:YES];
    XCTAssertTrue(some.contentPopUp.isEnabled);
    XCTAssertEqual(some.contentPopUp.indexOfSelectedItem, (NSInteger)1);
    XCTAssertTrue(NSEqualRects([some currentLayout].sourceRect, selection));
    [self choose:0 in:some.contentPopUp];
    XCTAssertTrue(NSEqualRects([some currentLayout].sourceRect, NSMakeRect(0, 0, 3000, 2000)));
}

- (void)testActualSizeTilesAndThePagerWalksThePages {
    STPrintPanelController *panel = [self panelWithSelection:NSZeroRect selectionOnly:NO];
    [self choose:1 in:panel.fitPopUp];
    NSUInteger pages = [panel currentLayout].pageCount;
    XCTAssertGreaterThan(pages, (NSUInteger)1);
    XCTAssertTrue(panel.enlargeCheckbox.isHidden);
    XCTAssertFalse(panel.nextPageButton.isHidden);
    XCTAssertFalse(panel.previousPageButton.isEnabled);
    XCTAssertTrue(panel.nextPageButton.isEnabled);
    NSString *first = [NSString stringWithFormat:@"Page 1 of %lu", (unsigned long)pages];
    XCTAssertTrue([panel.summaryLabel.stringValue hasPrefix:first], @"%@", panel.summaryLabel.stringValue);

    for (NSUInteger i = 1; i < pages; i++) {
        [panel.nextPageButton performClick:nil];
    }
    XCTAssertEqual(panel.previewPage, pages - 1);
    XCTAssertFalse(panel.nextPageButton.isEnabled);
    XCTAssertTrue(panel.previousPageButton.isEnabled);

    // Back to one page: the preview doesn't stay on a page that's gone.
    [self choose:0 in:panel.fitPopUp];
    XCTAssertEqual(panel.previewPage, (NSUInteger)0);
    XCTAssertTrue(panel.nextPageButton.isHidden);
}

- (void)testCustomScaleUsesTheField {
    STPrintPanelController *panel = [self panelWithSelection:NSZeroRect selectionOnly:NO];
    [self choose:2 in:panel.fitPopUp];
    XCTAssertFalse(panel.scaleField.isHidden);
    panel.scaleField.stringValue = @"50";
    [panel.scaleField sendAction:panel.scaleField.action to:panel.scaleField.target];
    XCTAssertEqualWithAccuracy(panel.options.customScale, 0.5, 1e-9);
    XCTAssertEqualWithAccuracy([panel currentLayout].effectiveScale, 0.5, 1e-9);

    // Halfway through typing, it keeps the last scale it could read.
    panel.scaleField.stringValue = @"";
    [panel.scaleField sendAction:panel.scaleField.action to:panel.scaleField.target];
    XCTAssertEqualWithAccuracy(panel.options.customScale, 0.5, 1e-9);
}

- (void)testOrientationAndPaperChangeTheLayout {
    STPrintPanelController *panel = [self panelWithSelection:NSZeroRect selectionOnly:NO];
    XCTAssertEqual([panel currentLayout].resolvedOrientation, STPrintOrientationLandscape, @"a wide image");
    [self choose:1 in:panel.orientationPopUp];
    XCTAssertEqual([panel currentLayout].resolvedOrientation, STPrintOrientationPortrait);
    panel.paperSize = NSMakeSize(595.28, 841.89);
    XCTAssertEqualWithAccuracy([panel currentLayout].orientedPaperSize.height, 841.89, 0.01);
}

- (void)testOnlyPrintSavesTheOptions {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    STPrintPanelController *panel = [self panelWithSelection:NSZeroRect selectionOnly:NO];
    [self choose:1 in:panel.fitPopUp];
    XCTAssertEqual([STPrintOptions optionsFromDefaults:defaults].fit, STPrintFitToPage, @"not saved yet");
    [panel confirm:nil];
    XCTAssertEqual([STPrintOptions optionsFromDefaults:defaults].fit, STPrintFitActualSize);
    STPrintPanelController *next = [self panelWithSelection:NSZeroRect selectionOnly:NO];
    XCTAssertEqual(next.fitPopUp.indexOfSelectedItem, (NSInteger)1);
}

- (void)testAPaperIsRemembered {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    STPrintSavePaperSize(defaults, NSMakeSize(595.28, 841.89));
    XCTAssertEqualWithAccuracy(STPrintLastPaperSize(defaults).width, 595.28, 0.01);
    XCTAssertEqualWithAccuracy([self panelWithSelection:NSZeroRect selectionOnly:NO].paperSize.height, 841.89, 0.01);
}

/// A capture whose size differs from its pixels has its own resolution: at actual size, a Retina
/// capture prints at its on-screen size.
- (void)testTheImagesOwnResolutionSetsItsRealSize {
    NSImage *retina = [self imageWithWidth:400 height:200];
    retina.size = NSMakeSize(200, 100);
    [retina.representations.firstObject setSize:NSMakeSize(200, 100)];
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    STConfigurePrintLayout(layout, [[STPrintOptions alloc] init], retina, NSZeroRect);
    XCTAssertEqualWithAccuracy(layout.pixelsPerInch, 144.0, 1e-6);
    XCTAssertTrue(NSEqualRects(layout.sourceRect, NSMakeRect(0, 0, 400, 200)));

    NSImage *plain = [self imageWithWidth:400 height:200];
    STConfigurePrintLayout(layout, [[STPrintOptions alloc] init], plain, NSZeroRect);
    XCTAssertEqualWithAccuracy(layout.pixelsPerInch, STPrintDefaultPixelsPerInch, 1e-6);
}

@end

#endif
