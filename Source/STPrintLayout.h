#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// How the image is sized on the page (#355).
typedef NS_ENUM(NSInteger, STPrintFit) {
    /// On one page, centred, keeping its proportions: shrunk to fit if it's larger than the page, and
    /// otherwise at its real size, since enlarging a screenshot blurs it. See `enlargeToFill`.
    STPrintFitToPage = 0,
    /// At its real size, from `pixelsPerInch`, over as many pages as that takes.
    STPrintFitActualSize,
    /// At `customScale` times its real size, over as many pages as that takes.
    STPrintFitCustomScale,
};

typedef NS_ENUM(NSInteger, STPrintOrientation) {
    /// Whichever suits the image; see `resolvedOrientation`.
    STPrintOrientationAutomatic = 0,
    STPrintOrientationPortrait,
    STPrintOrientationLandscape,
};

/// In points, from the sheet's edges. See `margins` and `printerMargins`.
typedef struct {
    CGFloat top;
    CGFloat left;
    CGFloat bottom;
    CGFloat right;
} STPrintMargins;

NS_INLINE STPrintMargins STPrintMarginsMake(CGFloat top, CGFloat left, CGFloat bottom, CGFloat right) {
    STPrintMargins margins = { top, left, bottom, right };
    return margins;
}

/// The pixels per inch `pixelsPerInch` starts at: a screenshot's, at normal display scale.
extern const CGFloat STPrintDefaultPixelsPerInch;

/// Where an image's pixels go on printed pages (#355). Foundation only, shared by the macOS, Linux
/// and Windows print paths, so a preview, its page count and the printout agree.
///
/// Set the inputs, then read the results, which always follow the current inputs. Image rects are
/// in the image's pixels and page rects in points on the sheet, both with a top-left origin. Tiles
/// can have fractional pixel edges, so annotations stay sharp across a page break; a platform that
/// draws bitmap pixels rounds them itself.
///
/// This class doesn't save anything: the print UI keeps its inputs (fit, scale, orientation, margins)
/// in the app's defaults.
///
/// Inputs that can't be laid out (an empty `sourceRect`, margins that leave no room, a `customScale`
/// that isn't above 0) give 0 pages.
@interface STPrintLayout : NSObject

/// The part of the image to print: all of it, or a selection.
@property (nonatomic) NSRect sourceRect;
/// The image's resolution, which sets its real size. Not above 0 means the default. Pass the
/// image's own when it has one: a Retina capture is 144, so it prints at its on-screen size, and a
/// 1× capture on macOS is 72, not the default.
@property (nonatomic) CGFloat pixelsPerInch;
/// The paper in points. Its own orientation doesn't matter: 612 × 792 and 792 × 612 are one paper.
@property (nonatomic) NSSize paperSize;
/// The margins asked for, on the sheet as printed: `top` stays the top when the sheet turns.
@property (nonatomic) STPrintMargins margins;
/// What the printer can't reach, on the portrait sheet: it's fixed to the physical sheet, so it turns
/// with it. In landscape, for a sheet turned 90° clockwise, its left is the top, top the right, right
/// the bottom and bottom the left. Each side of the sheet uses the larger of this and `margins`.
/// The caller supplies it: NSPrintInfo's imageablePageBounds on macOS and GNUstep (or its margins
/// where that's all a backend reports), and GetDeviceCaps' PHYSICALOFFSETX/Y and PHYSICALWIDTH/HEIGHT
/// on Windows.
@property (nonatomic) STPrintMargins printerMargins;
@property (nonatomic) STPrintFit fit;
/// For STPrintFitToPage: enlarge an image smaller than the page to fill it. Off by default.
@property (nonatomic) BOOL enlargeToFill;
/// For STPrintFitCustomScale: 1 is the image's real size, 0.5 half of it.
@property (nonatomic) CGFloat customScale;
@property (nonatomic) STPrintOrientation orientation;

/// Portrait or Landscape. Automatic fits the image to whichever prints it larger; at a set size,
/// whichever takes fewer pages. A tie, such as a small image that prints at its real size either
/// way, follows the image's shape, and a square image is portrait.
@property (nonatomic, readonly) STPrintOrientation resolvedOrientation;
/// `paperSize`, turned to `resolvedOrientation`.
@property (nonatomic, readonly) NSSize orientedPaperSize;
/// The part of the sheet inside the margins; NSZeroRect if they leave no room.
@property (nonatomic, readonly) NSRect printableRect;

/// Points per image pixel; 0 with no pages.
@property (nonatomic, readonly) CGFloat pointsPerPixel;
/// The size relative to the image's real size, for a "62%" label; 0 with no pages.
@property (nonatomic, readonly) CGFloat effectiveScale;

@property (nonatomic, readonly) NSUInteger pagesAcross;
@property (nonatomic, readonly) NSUInteger pagesDown;
@property (nonatomic, readonly) NSUInteger pageCount;

/// The part of the image on a page. Pages run left to right, then top to bottom, from 0: that's the
/// only order, with no option for another. Together
/// they cover `sourceRect` exactly, with no overlap. NSZeroRect out of range.
- (NSRect)sourceRectForPage:(NSUInteger)page;
/// Where that part goes on the sheet. Along a direction with one page it's centred in the printable
/// area; along one with several, it starts at the margin. NSZeroRect out of range.
- (NSRect)pageRectForPage:(NSUInteger)page;

@end

NS_ASSUME_NONNULL_END
