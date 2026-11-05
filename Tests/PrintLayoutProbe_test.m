/*
 * PrintLayoutProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Where an image's pixels go on printed pages (#355): fit to page, actual size with tiling, custom
 * scale, automatic orientation, margins and the page count. STPrintLayout is Foundation only, so
 * this needs no window or printer.
 */

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#include <math.h>
#import "STPrintLayout.h"

@interface PrintLayoutProbeTests : XCTestCase
@end

@implementation PrintLayoutProbeTests

static const NSSize STLetter = { 612.0, 792.0 };
static const CGFloat STAccuracy = 0.000001;

/// A whole `width` × `height` image on Letter with half-inch margins, fitted to the page.
- (STPrintLayout *)layoutWithWidth:(CGFloat)width height:(CGFloat)height {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.sourceRect = NSMakeRect(0, 0, width, height);
    layout.paperSize = STLetter;
    layout.margins = STPrintMarginsMake(36, 36, 36, 36);
    return layout;
}

- (void)assertRect:(NSRect)rect equals:(NSRect)expected message:(NSString *)message {
    XCTAssertEqualWithAccuracy(NSMinX(rect), NSMinX(expected), STAccuracy, @"%@: x", message);
    XCTAssertEqualWithAccuracy(NSMinY(rect), NSMinY(expected), STAccuracy, @"%@: y", message);
    XCTAssertEqualWithAccuracy(NSWidth(rect), NSWidth(expected), STAccuracy, @"%@: width", message);
    XCTAssertEqualWithAccuracy(NSHeight(rect), NSHeight(expected), STAccuracy, @"%@: height", message);
}

- (void)assertNoPages:(STPrintLayout *)layout message:(NSString *)message {
    XCTAssertEqual(layout.pageCount, (NSUInteger)0, @"%@", message);
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.0, STAccuracy, @"%@", message);
    XCTAssertEqualWithAccuracy(layout.effectiveScale, 0.0, STAccuracy, @"%@", message);
    XCTAssertTrue(NSEqualRects([layout sourceRectForPage:0], NSZeroRect), @"%@", message);
    XCTAssertTrue(NSEqualRects([layout pageRectForPage:0], NSZeroRect), @"%@", message);
}

#pragma mark - Fit to page

- (void)testFitIsTheDefaultAndFillsOnePageCentred {
    STPrintLayout *layout = [self layoutWithWidth:1200 height:700];
    XCTAssertEqual(layout.fit, STPrintFitToPage);
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationLandscape, @"A wide image turns the sheet");
    XCTAssertEqual(layout.pageCount, (NSUInteger)1);
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.6, STAccuracy, @"720 / 1200");
    XCTAssertEqualWithAccuracy(layout.effectiveScale, 0.8, STAccuracy, @"0.6 of the real size's 0.75");
    [self assertRect:[layout sourceRectForPage:0] equals:NSMakeRect(0, 0, 1200, 700) message:@"All of it"];
    [self assertRect:[layout pageRectForPage:0] equals:NSMakeRect(36, 96, 720, 420)
             message:@"Full width, centred down the 540 points"];
}

- (void)testFitDoesntEnlargeASmallImage {
    STPrintLayout *layout = [self layoutWithWidth:100 height:100];
    XCTAssertFalse(layout.enlargeToFill, @"Off by default: enlarging a screenshot blurs it");
    XCTAssertEqual(layout.pageCount, (NSUInteger)1);
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.75, STAccuracy, @"Its real size");
    XCTAssertEqualWithAccuracy(layout.effectiveScale, 1.0, STAccuracy);
    [self assertRect:[layout pageRectForPage:0] equals:NSMakeRect(268.5, 358.5, 75, 75) message:@"Centred"];
}

- (void)testEnlargeToFillFillsThePage {
    STPrintLayout *layout = [self layoutWithWidth:100 height:100];
    layout.enlargeToFill = YES;
    XCTAssertEqual(layout.pageCount, (NSUInteger)1);
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 5.4, STAccuracy, @"540 / 100");
    XCTAssertEqualWithAccuracy(layout.effectiveScale, 7.2, STAccuracy);
    [self assertRect:[layout pageRectForPage:0] equals:NSMakeRect(36, 126, 540, 540) message:@"Centred"];
}

- (void)testEnlargeToFillDoesntChangeALargeImage {
    STPrintLayout *layout = [self layoutWithWidth:1200 height:700];
    layout.enlargeToFill = YES;
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.6, STAccuracy, @"Shrunk the same either way");
}

- (void)testEnlargeToFillOnlyAppliesToFit {
    STPrintLayout *layout = [self layoutWithWidth:100 height:100];
    layout.enlargeToFill = YES;
    layout.fit = STPrintFitActualSize;
    XCTAssertEqualWithAccuracy(layout.effectiveScale, 1.0, STAccuracy, @"Actual size ignores it");
    layout.fit = STPrintFitCustomScale;
    layout.customScale = 0.5;
    XCTAssertEqualWithAccuracy(layout.effectiveScale, 0.5, STAccuracy, @"Custom scale ignores it");
}

- (void)testFitUsesTheRealSizeFromPixelsPerInch {
    STPrintLayout *layout = [self layoutWithWidth:1000 height:500];
    layout.pixelsPerInch = 300;
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.24, STAccuracy, @"Fits at 240 × 120 points: 72 / 300");
    XCTAssertEqualWithAccuracy(layout.effectiveScale, 1.0, STAccuracy);
    layout.pixelsPerInch = 72;
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.72, STAccuracy, @"1000 points doesn't fit: 720 / 1000");
    XCTAssertEqualWithAccuracy(layout.effectiveScale, 0.72, STAccuracy);
}

- (void)testASetOrientationIsKept {
    STPrintLayout *layout = [self layoutWithWidth:1200 height:700];
    layout.orientation = STPrintOrientationPortrait;
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationPortrait);
    XCTAssertTrue(NSEqualSizes(layout.orientedPaperSize, NSMakeSize(612, 792)));
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.45, STAccuracy, @"540 / 1200");
    [self assertRect:[layout pageRectForPage:0] equals:NSMakeRect(36, 238.5, 540, 315) message:@"Centred down"];

    layout = [self layoutWithWidth:700 height:1200];
    layout.orientation = STPrintOrientationLandscape;
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationLandscape);
    XCTAssertTrue(NSEqualSizes(layout.orientedPaperSize, NSMakeSize(792, 612)));
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.45, STAccuracy, @"540 / 1200");
}

#pragma mark - Automatic orientation

- (void)testAutomaticFollowsTheImageWhenFitting {
    XCTAssertEqual([self layoutWithWidth:1200 height:700].resolvedOrientation, STPrintOrientationLandscape);
    XCTAssertEqual([self layoutWithWidth:700 height:1200].resolvedOrientation, STPrintOrientationPortrait);
    XCTAssertEqual([self layoutWithWidth:800 height:800].resolvedOrientation, STPrintOrientationPortrait,
                   @"A square prints the same either way: portrait");
    XCTAssertEqual([self layoutWithWidth:900 height:600].resolvedOrientation, STPrintOrientationLandscape,
                   @"Real size in landscape, shrunk in portrait");
}

- (void)testAutomaticFollowsASmallImageSShape {
    XCTAssertEqual([self layoutWithWidth:400 height:300].resolvedOrientation, STPrintOrientationLandscape,
                   @"Real size either way: its shape decides");
    XCTAssertEqual([self layoutWithWidth:300 height:400].resolvedOrientation, STPrintOrientationPortrait);
}

- (void)testAutomaticPrefersFewerPagesAtASetSize {
    STPrintLayout *layout = [self layoutWithWidth:400 height:300];
    layout.fit = STPrintFitCustomScale;
    layout.customScale = 3.0; // 900 × 675 points
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationPortrait,
                   @"A wide image, but portrait takes 2 pages and landscape 4");
    XCTAssertEqual(layout.pagesAcross, (NSUInteger)2);
    XCTAssertEqual(layout.pagesDown, (NSUInteger)1);
    XCTAssertEqual(layout.pageCount, (NSUInteger)2);
}

- (void)testAutomaticAtASetSizeFollowsTheImageOnATie {
    STPrintLayout *layout = [self layoutWithWidth:400 height:300];
    layout.fit = STPrintFitActualSize;
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationLandscape, @"One page either way");
    layout = [self layoutWithWidth:300 height:400];
    layout.fit = STPrintFitActualSize;
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationPortrait);
}

- (void)testThePaperSOwnOrientationDoesntMatter {
    STPrintLayout *layout = [self layoutWithWidth:700 height:1200];
    layout.paperSize = NSMakeSize(792, 612);
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationPortrait);
    XCTAssertTrue(NSEqualSizes(layout.orientedPaperSize, NSMakeSize(612, 792)));
}

#pragma mark - Actual size and tiling

- (void)testActualSizeTilesAcrossPages {
    STPrintLayout *layout = [self layoutWithWidth:1920 height:1080];
    layout.fit = STPrintFitActualSize; // 1440 × 810 points at 96 ppi
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationLandscape, @"4 pages, and portrait's 6");
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.75, STAccuracy, @"72 / 96");
    XCTAssertEqualWithAccuracy(layout.effectiveScale, 1.0, STAccuracy, @"Real size");
    XCTAssertEqual(layout.pagesAcross, (NSUInteger)2, @"Exactly 2 pages' width: no third");
    XCTAssertEqual(layout.pagesDown, (NSUInteger)2);
    XCTAssertEqual(layout.pageCount, (NSUInteger)4);
    [self assertRect:[layout sourceRectForPage:0] equals:NSMakeRect(0, 0, 960, 720) message:@"Top left"];
    [self assertRect:[layout sourceRectForPage:1] equals:NSMakeRect(960, 0, 960, 720) message:@"Top right"];
    [self assertRect:[layout sourceRectForPage:2] equals:NSMakeRect(0, 720, 960, 360) message:@"Bottom left"];
    [self assertRect:[layout sourceRectForPage:3] equals:NSMakeRect(960, 720, 960, 360) message:@"Bottom right"];
    [self assertRect:[layout pageRectForPage:0] equals:NSMakeRect(36, 36, 720, 540) message:@"A full page"];
    [self assertRect:[layout pageRectForPage:3] equals:NSMakeRect(36, 36, 720, 270)
             message:@"The rest of it starts at the margin, not centred"];
    XCTAssertTrue(NSEqualRects([layout sourceRectForPage:4], NSZeroRect), @"Out of range");
    XCTAssertTrue(NSEqualRects([layout pageRectForPage:4], NSZeroRect), @"Out of range");
}

- (void)testARowOfPagesCentresDownThePage {
    STPrintLayout *layout = [self layoutWithWidth:1920 height:300];
    layout.fit = STPrintFitActualSize; // 1440 × 225 points
    layout.orientation = STPrintOrientationLandscape;
    XCTAssertEqual(layout.pagesAcross, (NSUInteger)2);
    XCTAssertEqual(layout.pagesDown, (NSUInteger)1);
    [self assertRect:[layout pageRectForPage:1] equals:NSMakeRect(36, 193.5, 720, 225)
             message:@"Across from the margin, centred down"];
}

- (void)testAnImageSmallerThanThePageIsCentred {
    STPrintLayout *layout = [self layoutWithWidth:400 height:300];
    layout.fit = STPrintFitActualSize;
    XCTAssertEqual(layout.pageCount, (NSUInteger)1);
    [self assertRect:[layout pageRectForPage:0] equals:NSMakeRect(246, 193.5, 300, 225) message:@"300 × 225, centred"];
}

- (void)testPixelsPerInchSetsTheRealSize {
    STPrintLayout *layout = [self layoutWithWidth:3000 height:1500];
    layout.fit = STPrintFitActualSize;
    layout.pixelsPerInch = 300;
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.24, STAccuracy, @"72 / 300");
    XCTAssertEqual(layout.pageCount, (NSUInteger)1, @"720 points on 720, with rounding: no second page");
    [self assertRect:[layout sourceRectForPage:0] equals:NSMakeRect(0, 0, 3000, 1500) message:@"All of it"];

    layout.pixelsPerInch = 0;
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.75, STAccuracy, @"Not above 0: the default");
    layout.pixelsPerInch = -5;
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.75, STAccuracy, @"Not above 0: the default");
}

- (void)testARetinaCapturePrintsAtItsOnScreenSize {
    STPrintLayout *layout = [self layoutWithWidth:1440 height:900];
    layout.pixelsPerInch = 144;
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.5, STAccuracy, @"72 / 144");
    XCTAssertEqualWithAccuracy(layout.effectiveScale, 1.0, STAccuracy, @"Fit doesn't shrink it: 720 × 450 points fit");
    layout.fit = STPrintFitActualSize;
    XCTAssertEqual(layout.pageCount, (NSUInteger)1);
    [self assertRect:[layout pageRectForPage:0] equals:NSMakeRect(36, 81, 720, 450) message:@"720 × 450, centred"];
}

#pragma mark - Custom scale

- (void)testCustomScaleIsRelativeToTheRealSize {
    STPrintLayout *layout = [self layoutWithWidth:400 height:300];
    layout.fit = STPrintFitCustomScale;
    XCTAssertEqualWithAccuracy(layout.customScale, 1.0, STAccuracy, @"Starts at real size");
    layout.customScale = 0.5;
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.375, STAccuracy, @"Half of 0.75");
    XCTAssertEqualWithAccuracy(layout.effectiveScale, 0.5, STAccuracy);
    XCTAssertEqual(layout.pageCount, (NSUInteger)1);
    layout.customScale = 2.0;
    XCTAssertEqualWithAccuracy(layout.effectiveScale, 2.0, STAccuracy);
    [self assertRect:[layout pageRectForPage:0] equals:NSMakeRect(96, 81, 600, 450) message:@"600 × 450, centred"];
}

- (void)testAScaleOnlyAppliesToCustomScale {
    STPrintLayout *layout = [self layoutWithWidth:400 height:300];
    layout.customScale = 9.0;
    XCTAssertEqual(layout.pageCount, (NSUInteger)1, @"Fit ignores it");
    layout.fit = STPrintFitActualSize;
    XCTAssertEqualWithAccuracy(layout.effectiveScale, 1.0, STAccuracy, @"Actual size ignores it");
}

#pragma mark - Margins

- (void)testMarginsSetThePrintableArea {
    STPrintLayout *layout = [self layoutWithWidth:700 height:1200];
    layout.margins = STPrintMarginsMake(10, 20, 30, 40);
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationPortrait);
    [self assertRect:layout.printableRect equals:NSMakeRect(20, 10, 552, 752) message:@"Portrait"];
    layout.orientation = STPrintOrientationLandscape;
    [self assertRect:layout.printableRect equals:NSMakeRect(20, 10, 732, 572)
             message:@"Landscape: top is still the top of the sheet as printed"];
}

- (void)testPrinterMarginsTurnWithTheSheet {
    STPrintLayout *layout = [self layoutWithWidth:700 height:1200];
    layout.margins = STPrintMarginsMake(0, 0, 0, 0);
    layout.printerMargins = STPrintMarginsMake(10, 20, 30, 40);
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationPortrait);
    [self assertRect:layout.printableRect equals:NSMakeRect(20, 10, 552, 752) message:@"Portrait: as given"];
    layout.orientation = STPrintOrientationLandscape;
    [self assertRect:layout.printableRect equals:NSMakeRect(30, 20, 752, 552)
             message:@"Landscape: left is the top, top the right, right the bottom, bottom the left"];
}

- (void)testEachSideUsesTheLargerOfTheMargins {
    STPrintLayout *layout = [self layoutWithWidth:700 height:1200];
    layout.printerMargins = STPrintMarginsMake(0, 50, 0, 0);
    [self assertRect:layout.printableRect equals:NSMakeRect(50, 36, 526, 720) message:@"Portrait: the printer's left"];
    layout.orientation = STPrintOrientationLandscape;
    [self assertRect:layout.printableRect equals:NSMakeRect(36, 50, 720, 526)
             message:@"Landscape: the printer's left is now the top"];
}

- (void)testAutomaticWeighsThePrinterMargins {
    STPrintLayout *layout = [self layoutWithWidth:800 height:800];
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationPortrait, @"A tie: a square is portrait");
    layout.margins = STPrintMarginsMake(0, 0, 0, 0);
    layout.printerMargins = STPrintMarginsMake(0, 0, 0, 100); // portrait 512 wide, landscape 512 tall
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationPortrait, @"Still a tie");
    layout.printerMargins = STPrintMarginsMake(0, 0, 150, 0); // portrait's height only, so landscape's left
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationPortrait, @"612 fits either way");
    layout.printerMargins = STPrintMarginsMake(100, 0, 0, 0); // landscape's right, portrait's top
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationPortrait, @"612 is still the short side");
}

- (void)testNoMarginsUseTheWholeSheet {
    STPrintLayout *layout = [self layoutWithWidth:1224 height:1584];
    layout.margins = STPrintMarginsMake(0, 0, 0, 0);
    XCTAssertEqualWithAccuracy(layout.pointsPerPixel, 0.5, STAccuracy);
    [self assertRect:[layout pageRectForPage:0] equals:NSMakeRect(0, 0, 612, 792) message:@"The whole sheet"];
}

#pragma mark - A selection, and the pages covering it

- (void)testPagesCoverASelectionExactly {
    NSRect selection = NSMakeRect(100, 50, 1701.5, 1003.25);
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.sourceRect = selection;
    layout.paperSize = STLetter;
    layout.margins = STPrintMarginsMake(36, 36, 36, 36);
    layout.fit = STPrintFitCustomScale;
    layout.customScale = 1.3;
    XCTAssertGreaterThan(layout.pageCount, (NSUInteger)1);

    CGFloat area = 0.0;
    NSRect all = NSZeroRect;
    for (NSUInteger page = 0; page < layout.pageCount; page++) {
        NSRect source = [layout sourceRectForPage:page];
        XCTAssertFalse(NSIsEmptyRect(source), @"Page %lu", (unsigned long)page);
        NSRect onPage = [layout pageRectForPage:page];
        XCTAssertEqualWithAccuracy(NSWidth(onPage), NSWidth(source) * layout.pointsPerPixel, STAccuracy);
        XCTAssertEqualWithAccuracy(NSHeight(onPage), NSHeight(source) * layout.pointsPerPixel, STAccuracy);
        XCTAssertLessThanOrEqual(NSWidth(onPage), NSWidth(layout.printableRect) + STAccuracy);
        XCTAssertLessThanOrEqual(NSHeight(onPage), NSHeight(layout.printableRect) + STAccuracy);
        area += NSWidth(source) * NSHeight(source);
        all = page == 0 ? source : NSUnionRect(all, source);
    }
    [self assertRect:all equals:selection message:@"Their union is the selection"];
    XCTAssertEqualWithAccuracy(area, NSWidth(selection) * NSHeight(selection), 0.001,
                               @"Their areas add up to it: no overlap");
}

- (void)testPagesRunLeftToRightThenDown {
    STPrintLayout *layout = [self layoutWithWidth:3000 height:2000];
    layout.fit = STPrintFitActualSize;
    layout.orientation = STPrintOrientationLandscape;
    NSUInteger across = layout.pagesAcross;
    XCTAssertGreaterThan(across, (NSUInteger)1);
    XCTAssertGreaterThan(layout.pagesDown, (NSUInteger)1);
    XCTAssertEqual(layout.pageCount, across * layout.pagesDown);
    XCTAssertGreaterThan(NSMinX([layout sourceRectForPage:1]), NSMinX([layout sourceRectForPage:0]));
    XCTAssertEqualWithAccuracy(NSMinY([layout sourceRectForPage:1]), NSMinY([layout sourceRectForPage:0]), STAccuracy);
    XCTAssertEqualWithAccuracy(NSMinX([layout sourceRectForPage:across]), 0.0, STAccuracy, @"The next row's first");
    XCTAssertGreaterThan(NSMinY([layout sourceRectForPage:across]), NSMinY([layout sourceRectForPage:0]));
}

#pragma mark - What can't be laid out

- (void)testNothingToPrintGivesNoPages {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    [self assertNoPages:layout message:@"Nothing set"];
    layout = [self layoutWithWidth:0 height:700];
    [self assertNoPages:layout message:@"No width"];
    layout = [self layoutWithWidth:1200 height:0];
    layout.fit = STPrintFitActualSize;
    [self assertNoPages:layout message:@"No height"];
}

- (void)testMarginsThatLeaveNoRoomGiveNoPages {
    STPrintLayout *layout = [self layoutWithWidth:1200 height:700];
    layout.margins = STPrintMarginsMake(0, 400, 0, 400);
    [self assertNoPages:layout message:@"Wider than the sheet both ways"];
    XCTAssertTrue(NSEqualRects(layout.printableRect, NSZeroRect));
}

- (void)testAScaleNotAboveZeroGivesNoPages {
    STPrintLayout *layout = [self layoutWithWidth:400 height:300];
    layout.fit = STPrintFitCustomScale;
    layout.customScale = 0.0;
    [self assertNoPages:layout message:@"Zero"];
    layout.customScale = -1.0;
    [self assertNoPages:layout message:@"Negative"];
    layout.customScale = (CGFloat)NAN;
    [self assertNoPages:layout message:@"Not a number"];
}

/// Annotations print at 300 dpi: 96 ppi at real size is 0.75 points a pixel, so 3.125, rounded.
- (void)testTheFlattenScaleReachesThreeHundredDPI {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.sourceRect = NSMakeRect(0, 0, 400, 200);
    layout.paperSize = NSMakeSize(612, 792);
    layout.fit = STPrintFitActualSize;
    XCTAssertEqual([layout flattenScaleForImagePixelSize:NSMakeSize(400, 200)], (NSUInteger)3);
    layout.fit = STPrintFitCustomScale;
    layout.customScale = 4.0;
    XCTAssertEqual([layout flattenScaleForImagePixelSize:NSMakeSize(400, 200)], (NSUInteger)13);
}

/// A large image shrunk to fit is already past 300 dpi: never below its own pixels.
- (void)testTheFlattenScaleIsAtLeastOne {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.sourceRect = NSMakeRect(0, 0, 8000, 4000);
    layout.paperSize = NSMakeSize(612, 792);
    XCTAssertEqual([layout flattenScaleForImagePixelSize:NSMakeSize(8000, 4000)], (NSUInteger)1);
    layout.sourceRect = NSZeroRect;
    XCTAssertEqual([layout flattenScaleForImagePixelSize:NSMakeSize(8000, 4000)], (NSUInteger)1, @"no pages");
}

/// The whole image is what's enlarged, even when only a selection prints, so the cap follows it.
- (void)testTheFlattenScaleStaysWithinThePixelCap {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.sourceRect = NSMakeRect(0, 0, 100, 100);
    layout.paperSize = NSMakeSize(612, 792);
    layout.fit = STPrintFitCustomScale;
    layout.customScale = 4.0;
    XCTAssertEqual([layout flattenScaleForImagePixelSize:NSMakeSize(100, 100)], (NSUInteger)13);
    XCTAssertEqual([layout flattenScaleForImagePixelSize:NSMakeSize(4096, 2000)], (NSUInteger)2);
    XCTAssertEqual([layout flattenScaleForImagePixelSize:NSMakeSize(5000, 2000)], (NSUInteger)1);
}

@end
