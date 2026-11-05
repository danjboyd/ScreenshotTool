#import <AppKit/AppKit.h>
#import "STPrintLayout.h"
#import "STPrintOptions.h"

NS_ASSUME_NONNULL_BEGIN

/// The size of `image` in pixels: its largest bitmap's, or its size in points if it has none. A
/// Retina capture is twice its point size. STPrintLayout's rects are in these pixels.
FOUNDATION_EXPORT NSSize STPrintImagePixelSize(NSImage *image);

/// Draws one printed page (#355) in the current graphics context: the part of `image` on page `page`
/// of `layout` (`sourceRectForPage:`, in its pixels) into that page's rect on the sheet
/// (`pageRectForPage:`, in points), clipped to it. Nothing else on the sheet is drawn.
///
/// `image` is what's printed, already flattened with its annotations. The context's coordinates are
/// the sheet's in points: with a top-left origin when `flipped` (a flipped view, such as macOS's print
/// view), otherwise with a bottom-left origin (a bitmap or PDF context, or an unflipped view). Shared
/// by every platform's print path, so they draw a page the same way.
///
/// `flipped` is for macOS only, for now: GNUstep's NSImage drawing already follows a flipped view, so
/// there the page came out upside down. Draw into an unflipped view or context on GNUstep, with NO.
///
/// Returns NO, drawing nothing, for a page out of range or an image with no size.
FOUNDATION_EXPORT BOOL STDrawPrintPage(STPrintLayout *layout, NSUInteger page, NSImage *image, BOOL flipped);

/// The print margins we ask for, on every side, in points.
extern const CGFloat STPrintDefaultMargin;

/// Sets a layout's content for an image: `options`' source (all of it or `selection`, in pixels from the
/// image's top left), the image's resolution, and the fit options. Paper and margins are the caller's.
/// The resolution comes from its pixels against its size: on macOS a point is 1/72 inch, so a Retina
/// capture is 144; on GNUstep a size equal to its pixels means the file gave none, so it's the default.
FOUNDATION_EXPORT void STConfigurePrintLayout(STPrintLayout *layout, STPrintOptions *options, NSImage *image, NSRect selection);

NS_ASSUME_NONNULL_END
