#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// How the image is sized on the page (#355).
typedef NS_ENUM(NSInteger, STPrintFit) {
    /// As large as fits on one page, keeping its proportions, centred. Scales small images up too.
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

/// In points, on the sheet as it's printed: `top` stays the top when the sheet turns.
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
/// Inputs that can't be laid out (an empty `sourceRect`, margins that leave no room, a `customScale`
/// that isn't above 0) give 0 pages.
@interface STPrintLayout : NSObject

/// The part of the image to print: all of it, or a selection.
@property (nonatomic) NSRect sourceRect;
/// The image's resolution, which sets its real size. Not above 0 means the default.
@property (nonatomic) CGFloat pixelsPerInch;
/// The paper in points. Its own orientation doesn't matter: 612 × 792 and 792 × 612 are one paper.
@property (nonatomic) NSSize paperSize;
@property (nonatomic) STPrintMargins margins;
@property (nonatomic) STPrintFit fit;
/// For STPrintFitCustomScale: 1 is the image's real size, 0.5 half of it.
@property (nonatomic) CGFloat customScale;
@property (nonatomic) STPrintOrientation orientation;

/// Portrait or Landscape. Automatic fits the image to whichever prints it larger; at a set size,
/// whichever takes fewer pages. A tie follows the image's shape, and a square image is portrait.
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

/// The part of the image on a page. Pages run left to right, then top to bottom, from 0. Together
/// they cover `sourceRect` exactly, with no overlap. NSZeroRect out of range.
- (NSRect)sourceRectForPage:(NSUInteger)page;
/// Where that part goes on the sheet. Along a direction with one page it's centred in the printable
/// area; along one with several, it starts at the margin. NSZeroRect out of range.
- (NSRect)pageRectForPage:(NSUInteger)page;

@end

NS_ASSUME_NONNULL_END
