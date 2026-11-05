#import <AppKit/AppKit.h>
#import "STPrintLayout.h"

NS_ASSUME_NONNULL_BEGIN

#if defined(__linux__)
/// Writes every page of `layout` to a PDF at `path`, one sheet per page, each the size of the layout's
/// oriented paper (#355). This is what Linux sends to the printer. `image` is what's printed, already
/// flattened with its annotations.
///
/// Returns NO, leaving no file, if the layout has no pages or the file wasn't written.
///
/// GNUstep's own PDF operation prints one page in a fixed orientation, so this depends on two of its
/// internals, both pinned with the libraries and covered by PrintPDFProbe_test.m: an override of the
/// private -[GSPDFPrintOperation _print], and a sheet that says portrait whatever its shape, since
/// CairoContext would otherwise swap a landscape sheet back. Recheck them at every libs-gui bump.
FOUNDATION_EXPORT BOOL STWritePrintPDF(STPrintLayout *layout, NSImage *image, NSString *path);
#endif

NS_ASSUME_NONNULL_END
