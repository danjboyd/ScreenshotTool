#import <AppKit/AppKit.h>
#import "STPrintLayout.h"

NS_ASSUME_NONNULL_BEGIN

#if defined(_WIN32)
/// A sheet as a printer has it, in points: the paper turned to portrait, and the printer's unprintable
/// area on that portrait sheet, as STPrintLayout takes them.
typedef struct {
    NSSize paper;
    STPrintMargins printerMargins;
    BOOL valid;
} STWindowsPrinterSheet;

/// Reads a printer device context (an HDC). Not valid if it reports no size.
FOUNDATION_EXPORT STWindowsPrinterSheet STWindowsPrinterSheetFromDC(void *dc);

/// A device context for the named printer with its default settings, or NULL. `devMode`, if given, gets
/// a DEVMODE to pass to STWindowsPrintPages, to be freed with free(). Delete the context with DeleteDC.
FOUNDATION_EXPORT void * _Nullable STWindowsCreatePrinterDC(NSString *printerName, void * _Nullable * _Nullable devMode);

/// Whether a printer of this name is installed.
FOUNDATION_EXPORT BOOL STWindowsPrinterExists(NSString *printerName);

/// The rects a page's pixels go between, whole pixels and device units: a page of `layout` on a sheet at
/// `dpi`, with the sheet's printable area starting `offset` device units in. Pages that share an edge
/// round it to the same place, on the image and on the sheet, so tiles neither gap nor overlap.
FOUNDATION_EXPORT void STWindowsPrintPageRects(STPrintLayout *layout, NSUInteger page, NSSize imagePixels, NSSize dpi, NSPoint offset,
                                               NSRect *source, NSRect *target);

/// Prints every page of `layout` on `dc`, one sheet per page (#355). `image` is what's printed, already
/// flattened with its annotations: its pixels go straight to the printer, at their place on the sheet,
/// and only the pixels on each page. `devMode` (a DEVMODE, or NULL) is turned to the layout's orientation
/// and applied, so the sheet has the layout's shape. `outputPath`, if given, is where a printer that
/// writes files puts this one, with no dialog. Returns NO with `failure` set if it didn't finish, and
/// nothing is left in the queue.
FOUNDATION_EXPORT BOOL STWindowsPrintPages(void *dc, void * _Nullable devMode, STPrintLayout *layout, NSImage *image,
                                           NSString *documentName, NSString * _Nullable outputPath,
                                           NSString * _Nullable * _Nullable failure);
#endif

NS_ASSUME_NONNULL_END
