#import <AppKit/AppKit.h>
#import "STPrintLayout.h"
#import "STPrintOptions.h"

@class ScreenshotCanvasView;

NS_ASSUME_NONNULL_BEGIN

#if defined(_WIN32)
/// Windows's own printer that writes PDF files.
extern NSString * const STWindowsPDFPrinterName;

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

/// The most source rows one StretchDIBits call sends. Microsoft Print to PDF drops a row from any source
/// of 3584 rows or more; 3583 or fewer keep every row, so a taller page goes in bands, kept apart so the
/// driver doesn't join them back into one image.
FOUNDATION_EXPORT const NSUInteger STWindowsPrintMaxBandRows;

/// How many bands a page of `sourceRows` rows goes in, each at most `maxRows`.
FOUNDATION_EXPORT NSUInteger STWindowsPrintBandCount(NSUInteger sourceRows, NSUInteger maxRows);

/// Band `band` of `count` of a page from STWindowsPrintPageRects: even bands of whole source rows, and
/// their place on the sheet, rounded edge by edge from one mapping, so the bands neither gap nor overlap
/// and together cover exactly `source` and `target`.
FOUNDATION_EXPORT void STWindowsPrintBandRects(NSRect source, NSRect target, NSUInteger band, NSUInteger count,
                                               NSRect *bandSource, NSRect *bandTarget);

/// Prints every page of `layout` on `dc`, one sheet per page (#355). `image` is what's printed, already
/// flattened with its annotations: its pixels go straight to the printer, at their place on the sheet,
/// and only the pixels on each page. `devMode` (a DEVMODE, or NULL) is turned to the layout's orientation
/// and applied, so the sheet has the layout's shape. `outputPath`, if given, is where a printer that
/// writes files puts this one, with no dialog. Returns NO with `failure` set if it didn't finish, and
/// nothing is left in the queue.
FOUNDATION_EXPORT BOOL STWindowsPrintPages(void *dc, void * _Nullable devMode, STPrintLayout *layout, NSImage *image,
                                           NSString *documentName, NSString * _Nullable outputPath,
                                           NSString * _Nullable * _Nullable failure);

/// `canvas`'s image as Windows prints it, for these options: flattened at the size it's printed, up to
/// 300 dpi, with its redactions and annotations, and only the selection when that's what's printed.
FOUNDATION_EXPORT BOOL STWindowsPrintCanvas(ScreenshotCanvasView *canvas, STPrintOptions *options, void *dc, void * _Nullable devMode,
                                            NSString *documentName, NSString * _Nullable outputPath,
                                            NSString * _Nullable * _Nullable failure);

typedef NS_ENUM(NSInteger, STWindowsPrintDialogOutcome) {
    STWindowsPrintDialogPrint = 0,
    STWindowsPrintDialogCancelled,
    STWindowsPrintDialogNoPrinter,
    STWindowsPrintDialogFailed,
};

typedef struct {
    STWindowsPrintDialogOutcome outcome;
    void * _Nullable dc;
    void * _Nullable devMode;
    /// For the log: what PrintDlgEx returned, its action and any extended error.
    long hresult;
    unsigned long action;
    unsigned long extendedError;
} STWindowsPrintDialogResult;

/// Windows's print dialog, for the printer, paper and copies, starting on the printer and paper last
/// printed on and turned to `orientation`, which is what will print. The choice is remembered in
/// `defaults`. With STWindowsPrintDialogPrint, free the result with STWindowsFreePrintDialogResult.
FOUNDATION_EXPORT STWindowsPrintDialogResult STWindowsRunPrintDialog(NSInteger windowNumber, STPrintOrientation orientation,
                                                                     NSUserDefaults *defaults);
FOUNDATION_EXPORT void STWindowsFreePrintDialogResult(STWindowsPrintDialogResult result);
FOUNDATION_EXPORT void STWindowsDeleteDC(void *dc);
#endif

NS_ASSUME_NONNULL_END
