/*
 * PrintPageProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Drawing printed pages (#355): STDrawPrintPage puts each page's part of the image in its place on
 * the sheet, so 2 × 2 tiled pages cover the image exactly, in a bitmap context (bottom-left origin,
 * as a PDF page) and in a flipped view (as macOS's print view). No printer is involved.
 *
 * The rendering tests run on macOS only: on GNUstep, drawing into a bitmap context stalled in libs-gui,
 * and `flipped` is macOS-only. Linux checks the same drawing through its own PDF page probe.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "STPrintLayout.h"
#import "STPrintPage.h"

/// A flipped view that draws one page, as a print view does.
@interface STPrintPageProbeView : NSView
@property (nonatomic, strong) STPrintLayout *layout;
@property (nonatomic, strong) NSImage *image;
@property (nonatomic) NSUInteger page;
@end

@implementation STPrintPageProbeView
- (BOOL)isFlipped {
    return YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor whiteColor] setFill];
    NSRectFill(self.bounds);
    STDrawPrintPage(self.layout, self.page, self.image, YES);
}
@end

@interface PrintPageProbeTests : XCTestCase
@end

@implementation PrintPageProbeTests

/// The quadrants' colours, in page order (top left, top right, bottom left, bottom right), each with
/// its top half first: a page drawn upside down, or the wrong tile, shows the wrong colour.
static NSArray<NSColor *> *STQuadrantColors(void) {
    return @[ [NSColor colorWithCalibratedRed:1 green:0 blue:0 alpha:1],
              [NSColor colorWithCalibratedRed:0.5 green:0 blue:0 alpha:1],
              [NSColor colorWithCalibratedRed:0 green:1 blue:0 alpha:1],
              [NSColor colorWithCalibratedRed:0 green:0.5 blue:0 alpha:1],
              [NSColor colorWithCalibratedRed:0 green:0 blue:1 alpha:1],
              [NSColor colorWithCalibratedRed:0 green:0 blue:0.5 alpha:1],
              [NSColor colorWithCalibratedRed:1 green:1 blue:0 alpha:1],
              [NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0 alpha:1] ];
}

/// A 200 × 100 pixel image in four 100 × 50 quadrants, each in two halves, `pointScale` points per
/// pixel (0.5 is a Retina capture).
- (NSImage *)quadrantImageWithPointScale:(CGFloat)pointScale {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:200
                                                                    pixelsHigh:100
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    NSArray<NSColor *> *colors = STQuadrantColors();
    for (NSInteger y = 0; y < 100; y++) {
        for (NSInteger x = 0; x < 200; x++) {
            // colorAtX:y: counts rows from the top.
            NSUInteger quadrant = (y < 50 ? 0 : 2) + (x < 100 ? 0 : 1);
            [rep setColor:colors[quadrant * 2 + ((y % 50) < 25 ? 0 : 1)] atX:x y:y];
        }
    }
    rep.size = NSMakeSize(200 * pointScale, 100 * pointScale);
    NSImage *image = [[NSImage alloc] initWithSize:rep.size];
    [image addRepresentation:rep];
    return image;
}

/// 2 × 2 pages exactly: the image at 72 ppi (a point a pixel) on a 120 × 70 landscape sheet. The
/// margins differ on every side, so a page drawn mirrored lands in the wrong place, and leave
/// 100 × 50 points, a quadrant, at (6, 4).
- (STPrintLayout *)tiledLayout {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.sourceRect = NSMakeRect(0, 0, 200, 100);
    layout.pixelsPerInch = 72.0;
    layout.fit = STPrintFitActualSize;
    layout.orientation = STPrintOrientationLandscape;
    layout.paperSize = NSMakeSize(70, 120);
    layout.margins = STPrintMarginsMake(4, 6, 16, 14);
    return layout;
}

- (NSBitmapImageRep *)sheetBitmap {
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                   pixelsWide:120
                                                   pixelsHigh:70
                                                bitsPerSample:8
                                              samplesPerPixel:4
                                                     hasAlpha:YES
                                                     isPlanar:NO
                                               colorSpaceName:NSCalibratedRGBColorSpace
                                                  bytesPerRow:0
                                                 bitsPerPixel:0];
}

/// Page `page` drawn into a sheet-sized bitmap context, unflipped.
- (NSBitmapImageRep *)bitmapOfPage:(NSUInteger)page layout:(STPrintLayout *)layout image:(NSImage *)image {
    NSBitmapImageRep *sheet = [self sheetBitmap];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:sheet]];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 120, 70));
    XCTAssertTrue(STDrawPrintPage(layout, page, image, NO));
#if !defined(GNUSTEP)
    // On GNUstep this reaches XFlush and crashes; the bitmap is complete without it.
    [[NSGraphicsContext currentContext] flushGraphics];
#endif
    [NSGraphicsContext restoreGraphicsState];
    return sheet;
}

/// Page `page` drawn by a flipped view, as the print view draws it.
- (NSBitmapImageRep *)viewBitmapOfPage:(NSUInteger)page layout:(STPrintLayout *)layout image:(NSImage *)image {
    STPrintPageProbeView *view = [[STPrintPageProbeView alloc] initWithFrame:NSMakeRect(0, 0, 120, 70)];
    view.layout = layout;
    view.image = image;
    view.page = page;
    NSBitmapImageRep *sheet = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:sheet];
    return sheet;
}

/// Whether the pixel at (x, y), counted from the sheet's top left in points, is `color`.
- (void)assertSheet:(NSBitmapImageRep *)sheet x:(NSInteger)x y:(NSInteger)y is:(NSColor *)color
            message:(NSString *)message {
    CGFloat scale = sheet.pixelsWide / 120.0;
    NSColor *pixel = [[sheet colorAtX:(NSInteger)((x + 0.5) * scale) y:(NSInteger)((y + 0.5) * scale)]
        colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    NSColor *expected = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    XCTAssertEqualWithAccuracy(pixel.redComponent, expected.redComponent, 0.05, @"%@ at %ld,%ld: red", message, (long)x, (long)y);
    XCTAssertEqualWithAccuracy(pixel.greenComponent, expected.greenComponent, 0.05, @"%@ at %ld,%ld: green", message, (long)x, (long)y);
    XCTAssertEqualWithAccuracy(pixel.blueComponent, expected.blueComponent, 0.05, @"%@ at %ld,%ld: blue", message, (long)x, (long)y);
}

/// Each page holds its quadrant the right way up, filling the printable area (6, 4, 100, 50) to its
/// edges, with blank margins.
- (void)assertTiledPages:(NSBitmapImageRep * (^)(NSUInteger page))render message:(NSString *)message {
    NSArray<NSColor *> *colors = STQuadrantColors();
    NSColor *white = [NSColor whiteColor];
    for (NSUInteger page = 0; page < 4; page++) {
        NSBitmapImageRep *sheet = render(page);
        NSString *where = [NSString stringWithFormat:@"%@, page %lu", message, (unsigned long)page];
        NSColor *top = colors[page * 2];
        NSColor *bottom = colors[page * 2 + 1];
        // The printable area's corners: its quadrant, top half above, so nothing of it is missing.
        [self assertSheet:sheet x:6 y:4 is:top message:where];
        [self assertSheet:sheet x:105 y:4 is:top message:where];
        [self assertSheet:sheet x:6 y:53 is:bottom message:where];
        [self assertSheet:sheet x:105 y:53 is:bottom message:where];
        // The margins, next to each edge: nothing spills into them.
        [self assertSheet:sheet x:4 y:30 is:white message:where];
        [self assertSheet:sheet x:107 y:30 is:white message:where];
        [self assertSheet:sheet x:50 y:2 is:white message:where];
        [self assertSheet:sheet x:50 y:55 is:white message:where];
    }
}

- (void)testTheLayoutIsTwoByTwo {
    STPrintLayout *layout = [self tiledLayout];
    XCTAssertEqual(layout.pagesAcross, (NSUInteger)2);
    XCTAssertEqual(layout.pagesDown, (NSUInteger)2);
    XCTAssertTrue(NSEqualRects([layout pageRectForPage:3], NSMakeRect(6, 4, 100, 50)));
}

#if !defined(GNUSTEP)
- (void)testTiledPagesCoverTheImageInABitmapContext {
    STPrintLayout *layout = [self tiledLayout];
    NSImage *image = [self quadrantImageWithPointScale:1.0];
    [self assertTiledPages:^NSBitmapImageRep *(NSUInteger page) {
        return [self bitmapOfPage:page layout:layout image:image];
    } message:@"bitmap"];
}

- (void)testTiledPagesCoverTheImageInAFlippedView {
    STPrintLayout *layout = [self tiledLayout];
    NSImage *image = [self quadrantImageWithPointScale:1.0];
    [self assertTiledPages:^NSBitmapImageRep *(NSUInteger page) {
        return [self viewBitmapOfPage:page layout:layout image:image];
    } message:@"flipped view"];
}

/// The layout counts pixels, not points: a Retina capture's pages are the same.
- (void)testARetinaImageTilesByItsPixels {
    STPrintLayout *layout = [self tiledLayout];
    NSImage *image = [self quadrantImageWithPointScale:0.5];
    XCTAssertTrue(NSEqualSizes(STPrintImagePixelSize(image), NSMakeSize(200, 100)));
    [self assertTiledPages:^NSBitmapImageRep *(NSUInteger page) {
        return [self bitmapOfPage:page layout:layout image:image];
    } message:@"Retina"];
}
#endif

- (void)testAPageOutOfRangeDrawsNothing {
    STPrintLayout *layout = [self tiledLayout];
    NSImage *image = [self quadrantImageWithPointScale:1.0];
    XCTAssertFalse(STDrawPrintPage(layout, 4, image, NO));
    XCTAssertFalse(STDrawPrintPage(layout, 0, [[NSImage alloc] initWithSize:NSZeroSize], NO));
}

@end
