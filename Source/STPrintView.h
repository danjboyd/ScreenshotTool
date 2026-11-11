#import <AppKit/AppKit.h>
#import "STPrintLayout.h"
#import "STPrintOptions.h"

NS_ASSUME_NONNULL_BEGIN

#if !defined(GNUSTEP)
@class STPrintVectorScene;
/// What the printer can't reach on `printInfo`'s paper, on the portrait sheet, as
/// STPrintLayout's `printerMargins` wants it: from imageablePageBounds, read with the sheet portrait
/// (#355). `printInfo` is left as it was.
FOUNDATION_EXPORT STPrintMargins STPrinterMarginsForPrintInfo(NSPrintInfo *printInfo);

/// Readies `printInfo` to print an STPrintView of `layout`: the layout's resolved orientation, no
/// margins of its own (the layout's margins and printer margins are already in its page rects), and
/// one view page a sheet, unscaled and uncentred. Set the layout's paper and printer margins from
/// `printInfo` first.
FOUNDATION_EXPORT void STPreparePrintInfo(NSPrintInfo *printInfo, STPrintLayout *layout);

/// The macOS print view (#355): one sheet of `layout`'s oriented paper, which each page of the print
/// operation draws in turn with STDrawPrintPage, so a printout, its preview and a saved PDF match
/// the other platforms' pages. Use it with a print info readied by STPreparePrintInfo.
///
/// Outside a print operation (cacheDisplayInRect:, say) it draws `page`.
@interface STPrintView : NSView

- (instancetype)initWithLayout:(STPrintLayout *)layout image:(NSImage *)image;

/// The print panel and its accessory change it while the panel is open, between paginations.
@property (nonatomic, strong) STPrintLayout *layout;
/// What's printed, already flattened with its annotations, or not, as the options say.
@property (nonatomic, strong) NSImage *image;
/// Optional redaction-only bitmap and immutable markup for a whole-image, one-page vector PDF.
/// `STPrintViewTakeOptions` clears this on every option change; the caller may reattach it.
@property (nonatomic, strong, nullable) STPrintVectorScene *vectorScene;
/// The page drawn outside a print operation, from 0.
@property (nonatomic) NSUInteger page;
/// Called when the print panel's orientation turns the sheet from the layout's: the layout already
/// has it, as a set orientation. The print panel's accessory takes it as the user's choice.
@property (nonatomic, copy, nullable) void (^printInfoChoseOrientation)(STPrintOrientation orientation);

/// Takes the paper, the printer's margins and, if it differs from the layout's, the orientation from
/// `printInfo`, which the print panel changes, and resizes to the sheet. The view does this itself
/// whenever its operation paginates; it's here for probes.
- (void)takePaperFromPrintInfo:(NSPrintInfo *)printInfo;

@end

/// Flattens the image for printing at `scale` pixels per image pixel, keeping only `clip` (image
/// pixels; NSZeroRect keeps it all): the canvas's flattenedImageForPrintAtScale:withinRect:.
typedef NSImage *_Nullable (^STPrintFlattener)(NSUInteger scale, NSRect clip);

/// Gives `view` what `options` prints, and lays it out (#355). `wholeImage` is the on-screen
/// flatten, which sets the layout; `selection` is the selection in its pixels (NSZeroRect for none).
/// The image printed is then flattened again at the printed size, up to 300 dpi (STPrintLayout's
/// flattenScaleForImagePixelSize:), by `flattener`, so annotations print sharp and redactions stay
/// cells of the capture. Without a flattener, or if it fails, the on-screen flatten prints.
///
/// Only what's printed goes in the file: a selection is its own image, never the whole image clipped,
/// which would still carry all of it, invisible, in a saved PDF.
FOUNDATION_EXPORT void STPrintViewTakeOptions(STPrintView *view, STPrintOptions *options, NSImage *wholeImage,
                                              NSRect selection, STPrintFlattener _Nullable flattener);

/// `image`'s pixels in `rect` (top-left origin) as an image of their own, at its resolution.
FOUNDATION_EXPORT NSImage *_Nullable STPrintImageCrop(NSImage *image, NSRect rect);
#endif

NS_ASSUME_NONNULL_END
