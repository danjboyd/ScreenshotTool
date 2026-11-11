#import "STPrintLayout.h"
#include <math.h>

const CGFloat STPrintDefaultPixelsPerInch = 96.0;

static const CGFloat STPointsPerInch = 72.0;
/// Rounding in the sums must not add a page: 720.0000001 points on 720 is one page.
static const CGFloat STPageTolerance = 1e-6;

/// The layout on one orientation.
typedef struct {
    NSRect printable;
    CGFloat pointsPerPixel;
    NSUInteger across;
    NSUInteger down;
} STPrintGrid;

static NSUInteger STPagesFor(CGFloat content, CGFloat page) {
    return MAX((NSUInteger)ceil(content / page - STPageTolerance), (NSUInteger)1);
}

@implementation STPrintLayout

- (instancetype)init {
    self = [super init];
    if (self) {
        _pixelsPerInch = STPrintDefaultPixelsPerInch;
        _customScale = 1.0;
    }
    return self;
}

- (CGFloat)actualPointsPerPixel {
    return STPointsPerInch / (self.pixelsPerInch > 0.0 ? self.pixelsPerInch : STPrintDefaultPixelsPerInch);
}

- (NSSize)paperSizeForOrientation:(STPrintOrientation)orientation {
    CGFloat shortSide = MIN(self.paperSize.width, self.paperSize.height);
    CGFloat longSide = MAX(self.paperSize.width, self.paperSize.height);
    return orientation == STPrintOrientationLandscape ? NSMakeSize(longSide, shortSide)
                                                      : NSMakeSize(shortSide, longSide);
}

/// Each side's larger of `margins` and `printerMargins`, the latter turned with the sheet.
- (STPrintMargins)marginsForOrientation:(STPrintOrientation)orientation {
    STPrintMargins asked = self.margins;
    STPrintMargins printer = self.printerMargins;
    if (orientation == STPrintOrientationLandscape) {
        printer = STPrintMarginsMake(printer.left, printer.bottom, printer.right, printer.top);
    }
    return STPrintMarginsMake(MAX(asked.top, printer.top), MAX(asked.left, printer.left),
                              MAX(asked.bottom, printer.bottom), MAX(asked.right, printer.right));
}

- (NSRect)printableRectForOrientation:(STPrintOrientation)orientation {
    NSSize paper = [self paperSizeForOrientation:orientation];
    STPrintMargins margins = [self marginsForOrientation:orientation];
    CGFloat width = paper.width - margins.left - margins.right;
    CGFloat height = paper.height - margins.top - margins.bottom;
    if (!(width > 0.0) || !(height > 0.0)) {
        return NSZeroRect;
    }
    return NSMakeRect(margins.left, margins.top, width, height);
}

- (STPrintGrid)gridForOrientation:(STPrintOrientation)orientation {
    STPrintGrid grid = { [self printableRectForOrientation:orientation], 0.0, 0, 0 };
    NSSize source = self.sourceRect.size;
    if (!(source.width > 0.0) || !(source.height > 0.0) || NSIsEmptyRect(grid.printable)) {
        return grid;
    }
    switch (self.fit) {
        case STPrintFitToPage:
            grid.pointsPerPixel =
                MIN(NSWidth(grid.printable) / source.width, NSHeight(grid.printable) / source.height);
            if (!self.enlargeToFill) {
                grid.pointsPerPixel = MIN(grid.pointsPerPixel, [self actualPointsPerPixel]);
            }
            grid.across = 1;
            grid.down = 1;
            return grid;
        case STPrintFitActualSize:
            grid.pointsPerPixel = [self actualPointsPerPixel];
            break;
        case STPrintFitCustomScale:
            if (!(self.customScale > 0.0)) {
                return grid;
            }
            grid.pointsPerPixel = [self actualPointsPerPixel] * self.customScale;
            break;
    }
    grid.across = STPagesFor(source.width * grid.pointsPerPixel, NSWidth(grid.printable));
    grid.down = STPagesFor(source.height * grid.pointsPerPixel, NSHeight(grid.printable));
    return grid;
}

- (STPrintOrientation)resolvedOrientation {
    if (self.orientation != STPrintOrientationAutomatic) {
        return self.orientation;
    }
    STPrintGrid portrait = [self gridForOrientation:STPrintOrientationPortrait];
    STPrintGrid landscape = [self gridForOrientation:STPrintOrientationLandscape];
    if (self.fit == STPrintFitToPage) {
        CGFloat difference = landscape.pointsPerPixel - portrait.pointsPerPixel;
        if (fabs(difference) > STPageTolerance) {
            return difference > 0.0 ? STPrintOrientationLandscape : STPrintOrientationPortrait;
        }
    } else {
        NSUInteger portraitPages = portrait.across * portrait.down;
        NSUInteger landscapePages = landscape.across * landscape.down;
        if (portraitPages != landscapePages) {
            return landscapePages < portraitPages ? STPrintOrientationLandscape : STPrintOrientationPortrait;
        }
    }
    return NSWidth(self.sourceRect) > NSHeight(self.sourceRect) ? STPrintOrientationLandscape
                                                                : STPrintOrientationPortrait;
}

- (STPrintGrid)grid {
    return [self gridForOrientation:self.resolvedOrientation];
}

- (NSSize)orientedPaperSize {
    return [self paperSizeForOrientation:self.resolvedOrientation];
}

- (NSRect)printableRect {
    return [self printableRectForOrientation:self.resolvedOrientation];
}

- (CGFloat)pointsPerPixel {
    STPrintGrid grid = [self grid];
    return grid.across > 0 ? grid.pointsPerPixel : 0.0;
}

- (CGFloat)effectiveScale {
    return self.pointsPerPixel / [self actualPointsPerPixel];
}

- (NSUInteger)pagesAcross {
    return [self grid].across;
}

- (NSUInteger)pagesDown {
    return [self grid].down;
}

- (NSUInteger)pageCount {
    STPrintGrid grid = [self grid];
    return grid.across * grid.down;
}

- (NSRect)sourceRectForPage:(NSUInteger)page {
    STPrintGrid grid = [self grid];
    if (page >= grid.across * grid.down) {
        return NSZeroRect;
    }
    NSUInteger column = page % grid.across;
    NSUInteger row = page / grid.across;
    CGFloat tileWidth = NSWidth(grid.printable) / grid.pointsPerPixel;
    CGFloat tileHeight = NSHeight(grid.printable) / grid.pointsPerPixel;
    // The last page in each direction takes what's left, so the pages end exactly at the source's
    // edge. On a single page, that's the whole source, even at a size that fits with rounding over.
    CGFloat x = column * tileWidth;
    CGFloat y = row * tileHeight;
    CGFloat width = column + 1 == grid.across ? NSWidth(self.sourceRect) - x : tileWidth;
    CGFloat height = row + 1 == grid.down ? NSHeight(self.sourceRect) - y : tileHeight;
    return NSMakeRect(NSMinX(self.sourceRect) + x, NSMinY(self.sourceRect) + y, width, height);
}

- (NSRect)pageRectForPage:(NSUInteger)page {
    NSRect source = [self sourceRectForPage:page];
    if (NSIsEmptyRect(source)) {
        return NSZeroRect;
    }
    STPrintGrid grid = [self grid];
    CGFloat width = NSWidth(source) * grid.pointsPerPixel;
    CGFloat height = NSHeight(source) * grid.pointsPerPixel;
    CGFloat x = NSMinX(grid.printable);
    CGFloat y = NSMinY(grid.printable);
    if (grid.across == 1) {
        x += (NSWidth(grid.printable) - width) / 2.0;
    }
    if (grid.down == 1) {
        y += (NSHeight(grid.printable) - height) / 2.0;
    }
    return NSMakeRect(x, y, width, height);
}

@end
