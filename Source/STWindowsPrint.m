#import "STWindowsPrint.h"

#if defined(_WIN32)

#import "STPrintPage.h"
#import "ScreenshotCanvasView.h"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winspool.h>
#if !defined(interface)
#define interface struct
#define ST_UNDEF_INTERFACE
#endif
#include <commdlg.h>
#include <cderr.h>
#if defined(ST_UNDEF_INTERFACE)
#undef interface
#undef ST_UNDEF_INTERFACE
#endif
#include <math.h>
#include <stdlib.h>

NSString * const STWindowsPDFPrinterName = @"Microsoft Print to PDF";
static NSString * const STDefaultsPrintWindowsDevModeKey = @"PrintWindowsDevMode";
static NSString * const STDefaultsPrintWindowsDevNamesKey = @"PrintWindowsDevNames";

STWindowsPrinterSheet STWindowsPrinterSheetFromDC(void *dcHandle) {
    HDC dc = (HDC)dcHandle;
    STWindowsPrinterSheet sheet = { NSZeroSize, STPrintMarginsMake(0.0, 0.0, 0.0, 0.0), NO, 0.0 };
    int dpiX = GetDeviceCaps(dc, LOGPIXELSX), dpiY = GetDeviceCaps(dc, LOGPIXELSY);
    int width = GetDeviceCaps(dc, PHYSICALWIDTH), height = GetDeviceCaps(dc, PHYSICALHEIGHT);
    if (dpiX <= 0 || dpiY <= 0 || width <= 0 || height <= 0) {
        return sheet;
    }
    CGFloat toX = 72.0 / dpiX, toY = 72.0 / dpiY;
    int left = GetDeviceCaps(dc, PHYSICALOFFSETX), top = GetDeviceCaps(dc, PHYSICALOFFSETY);
    int right = width - left - GetDeviceCaps(dc, HORZRES), bottom = height - top - GetDeviceCaps(dc, VERTRES);
    STPrintMargins margins = STPrintMarginsMake(MAX(top, 0) * toY, MAX(left, 0) * toX, MAX(bottom, 0) * toY, MAX(right, 0) * toX);
    NSSize paper = NSMakeSize(width * toX, height * toY);
    if (paper.width > paper.height) {
        // A landscape sheet is a portrait one turned 90 degrees anticlockwise: its top was the right.
        paper = NSMakeSize(paper.height, paper.width);
        margins = STPrintMarginsMake(margins.left, margins.bottom, margins.right, margins.top);
    }
    sheet.paper = paper;
    sheet.printerMargins = margins;
    sheet.valid = YES;
    sheet.dotsPerInch = MAX(dpiX, dpiY);
    return sheet;
}

static NSData *STWideString(NSString *string) {
    NSMutableData *data = [[string dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
    const unichar terminator = 0;
    [data appendBytes:&terminator length:sizeof(terminator)];
    return data;
}

void *STWindowsCreatePrinterDC(NSString *printerName, void **devMode) {
    NSData *name = STWideString(printerName);
    const WCHAR *wideName = (const WCHAR *)name.bytes;
    HANDLE printer = NULL;
    DEVMODEW *mode = NULL;
    if (OpenPrinterW((LPWSTR)wideName, &printer, NULL)) {
        LONG size = DocumentPropertiesW(NULL, printer, (LPWSTR)wideName, NULL, NULL, 0);
        if (size > 0) {
            mode = (DEVMODEW *)calloc(1, (size_t)size);
            if (mode && DocumentPropertiesW(NULL, printer, (LPWSTR)wideName, mode, NULL, DM_OUT_BUFFER) != IDOK) {
                free(mode);
                mode = NULL;
            }
        }
        ClosePrinter(printer);
    }
    HDC dc = CreateDCW(L"WINSPOOL", wideName, NULL, mode);
    if (devMode && dc) {
        *devMode = mode;
    } else {
        free(mode);
    }
    return dc;
}

BOOL STWindowsPrinterExists(NSString *printerName) {
    HANDLE printer = NULL;
    NSData *name = STWideString(printerName);
    if (!OpenPrinterW((LPWSTR)name.bytes, &printer, NULL)) {
        return NO;
    }
    ClosePrinter(printer);
    return YES;
}

void STWindowsPrintPageRects(STPrintLayout *layout, NSUInteger page, NSSize imagePixels, NSSize dpi, NSPoint offset,
                             NSRect *source, NSRect *target) {
    NSRect from = [layout sourceRectForPage:page];
    NSRect to = [layout pageRectForPage:page];
    // Rounded edge by edge, not origin and size: two pages' shared edge is the same number, so it rounds
    // to the same place.
    CGFloat left = MAX(round(NSMinX(from)), 0.0), right = MIN(round(NSMaxX(from)), imagePixels.width);
    CGFloat top = MAX(round(NSMinY(from)), 0.0), bottom = MIN(round(NSMaxY(from)), imagePixels.height);
    *source = NSMakeRect(left, top, MAX(right - left, 0.0), MAX(bottom - top, 0.0));
    CGFloat x0 = round(NSMinX(to) * dpi.width / 72.0) - offset.x, x1 = round(NSMaxX(to) * dpi.width / 72.0) - offset.x;
    CGFloat y0 = round(NSMinY(to) * dpi.height / 72.0) - offset.y, y1 = round(NSMaxY(to) * dpi.height / 72.0) - offset.y;
    *target = NSMakeRect(x0, y0, x1 - x0, y1 - y0);
}

const NSUInteger STWindowsPrintMaxPieceSide = 3583;

NSUInteger STWindowsPrintPieceCount(NSUInteger pixels, NSUInteger maxSide) {
    if (pixels == 0) {
        return 0;
    }
    maxSide = MAX(maxSide, (NSUInteger)1);
    return (pixels + maxSide - 1) / maxSide;
}

/// Piece `index` of `count` along one side: even pieces of whole pixels, `length` long from `origin`, and
/// its span on the sheet, from `targetOrigin` over `targetLength`, rounded from the same pixels, so a shared
/// edge lands on the same device pixel.
static void STWindowsPrintSplit(CGFloat origin, NSUInteger length, CGFloat targetOrigin, CGFloat targetLength,
                                NSUInteger index, NSUInteger count, CGFloat *from, CGFloat *fromLength,
                                CGFloat *to, CGFloat *toLength) {
    count = MAX(count, (NSUInteger)1);
    index = MIN(index, count - 1);
    // Piece i covers i*length/count up to (i+1)*length/count, so no two differ by more than a pixel.
    NSUInteger p0 = index * length / count, p1 = (index + 1) * length / count;
    CGFloat scale = length > 0 ? targetLength / (CGFloat)length : 0.0;
    CGFloat t0 = targetOrigin + round(p0 * scale);
    CGFloat t1 = index == count - 1 ? targetOrigin + targetLength : targetOrigin + round(p1 * scale);
    *from = origin + p0;
    *fromLength = (CGFloat)(p1 - p0);
    *to = t0;
    *toLength = t1 - t0;
}

void STWindowsPrintPieceRects(NSRect source, NSRect target, NSUInteger column, NSUInteger columns, NSUInteger row,
                              NSUInteger rows, NSRect *pieceSource, NSRect *pieceTarget) {
    CGFloat x, w, tx, tw, y, h, ty, th;
    STWindowsPrintSplit(NSMinX(source), (NSUInteger)NSWidth(source), NSMinX(target), NSWidth(target), column, columns,
                        &x, &w, &tx, &tw);
    STWindowsPrintSplit(NSMinY(source), (NSUInteger)NSHeight(source), NSMinY(target), NSHeight(target), row, rows,
                        &y, &h, &ty, &th);
    *pieceSource = NSMakeRect(x, y, w, h);
    *pieceTarget = NSMakeRect(tx, ty, tw, th);
}

/// `source`'s pixels as a top-down 32-bit DIB's, on white: all a page needs of the image.
static NSData *STPrintDIBPixels(NSBitmapImageRep *rep, NSRect source) {
    NSInteger x0 = (NSInteger)NSMinX(source), y0 = (NSInteger)NSMinY(source);
    NSInteger width = (NSInteger)NSWidth(source), height = (NSInteger)NSHeight(source);
    NSMutableData *pixels = [NSMutableData dataWithLength:(NSUInteger)width * (NSUInteger)height * 4];
    uint8_t *out = pixels.mutableBytes;
    NSInteger samples = rep.samplesPerPixel;
    BOOL alpha = rep.hasAlpha;
    BOOL premultiplied = (rep.bitmapFormat & NSAlphaNonpremultipliedBitmapFormat) == 0;
    BOOL alphaFirst = (rep.bitmapFormat & NSAlphaFirstBitmapFormat) != 0;
    BOOL direct = rep.bitsPerSample == 8 && !rep.isPlanar && rep.bitmapData != NULL;
    const uint8_t *data = rep.bitmapData;
    NSInteger bytesPerRow = rep.bytesPerRow, bytesPerPixel = rep.bitsPerPixel / 8;
    NSUInteger maxValue = (1u << rep.bitsPerSample) - 1;
    NSInteger colours = samples - (alpha ? 1 : 0);
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            NSUInteger value[5] = { 0, 0, 0, 0, 0 };
            if (direct) {
                const uint8_t *p = data + (y0 + y) * bytesPerRow + (x0 + x) * bytesPerPixel;
                for (NSInteger s = 0; s < samples && s < 5; s++) {
                    value[s] = p[s];
                }
            } else {
                [rep getPixel:value atX:x0 + x y:y0 + y];
                for (NSInteger s = 0; s < samples && s < 5; s++) {
                    value[s] = value[s] * 255 / maxValue;
                }
            }
            NSUInteger a = 255, first = 0;
            if (alpha) {
                a = alphaFirst ? value[0] : value[samples - 1];
                first = alphaFirst ? 1 : 0;
            }
            uint8_t *q = out + (y * width + x) * 4;
            for (NSInteger c = 0; c < 3; c++) {
                NSUInteger v = value[first + (colours >= 3 ? c : 0)];
                NSUInteger on = premultiplied ? v + (255 - a) : (v * a + 255 * (255 - a)) / 255;
                q[2 - c] = (uint8_t)MIN(on, (NSUInteger)255);
            }
            q[3] = 255;
        }
    }
    return pixels;
}

static NSBitmapImageRep *STLargestBitmap(NSImage *image) {
    NSBitmapImageRep *best = nil;
    for (NSImageRep *rep in image.representations) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]] &&
            (!best || rep.pixelsWide * rep.pixelsHigh > best.pixelsWide * best.pixelsHigh)) {
            best = (NSBitmapImageRep *)rep;
        }
    }
    return best;
}

BOOL STWindowsPrintPages(void *dcHandle, void *devModeHandle, STPrintLayout *layout, NSImage *image, NSString *documentName,
                         NSString *outputPath, NSString **failure) {
    HDC dc = (HDC)dcHandle;
    DEVMODEW *mode = (DEVMODEW *)devModeHandle;
    NSString *problem = nil;
    NSBitmapImageRep *rep = STLargestBitmap(image);
    NSUInteger pages = layout.pageCount;
    BOOL landscape = layout.resolvedOrientation == STPrintOrientationLandscape;
    if (!rep || pages == 0) {
        problem = @"There's nothing to print.";
    } else if (!(GetDeviceCaps(dc, RASTERCAPS) & RC_STRETCHDIB)) {
        problem = @"This printer can't print images.";
    }
    if (!problem && mode) {
        mode->dmFields |= DM_ORIENTATION;
        mode->dmOrientation = landscape ? DMORIENT_LANDSCAPE : DMORIENT_PORTRAIT;
        if (!ResetDCW(dc, mode)) {
            problem = @"The printer couldn't be set up for this page.";
        }
    }
    if (!problem) {
        // A printer that kept its own orientation would cut the pages off.
        BOOL sheetLandscape = GetDeviceCaps(dc, PHYSICALWIDTH) > GetDeviceCaps(dc, PHYSICALHEIGHT);
        if (sheetLandscape != landscape) {
            problem = @"The printer wouldn't turn the page.";
        }
    }
    if (problem) {
        if (failure) {
            *failure = problem;
        }
        return NO;
    }

    NSData *name = STWideString(documentName);
    NSData *output = outputPath ? STWideString(outputPath) : nil;
    DOCINFOW info = { .cbSize = sizeof(DOCINFOW), .lpszDocName = (LPCWSTR)name.bytes, .lpszOutput = (LPCWSTR)output.bytes };
    if (StartDocW(dc, &info) <= 0) {
        if (failure) {
            *failure = @"The print job couldn't be started.";
        }
        return NO;
    }
    NSSize imagePixels = NSMakeSize(rep.pixelsWide, rep.pixelsHigh);
    NSSize dpi = NSMakeSize(GetDeviceCaps(dc, LOGPIXELSX), GetDeviceCaps(dc, LOGPIXELSY));
    NSPoint offset = NSMakePoint(GetDeviceCaps(dc, PHYSICALOFFSETX), GetDeviceCaps(dc, PHYSICALOFFSETY));
    for (NSUInteger page = 0; page < pages && !problem; page++) {
        @autoreleasepool {
            if (StartPage(dc) <= 0) {
                problem = @"The printer stopped.";
                break;
            }
            NSRect source, target;
            STWindowsPrintPageRects(layout, page, imagePixels, dpi, offset, &source, &target);
            if (NSWidth(source) > 0.0 && NSHeight(source) > 0.0 && NSWidth(target) > 0.0 && NSHeight(target) > 0.0) {
                SetStretchBltMode(dc, HALFTONE);
                SetBrushOrgEx(dc, 0, 0, NULL);
                // In pieces at most STWindowsPrintMaxPieceSide pixels on a side: Microsoft Print to PDF drops a
                // row or column from a larger source.
                NSUInteger columns = STWindowsPrintPieceCount((NSUInteger)NSWidth(source), STWindowsPrintMaxPieceSide);
                NSUInteger rows = STWindowsPrintPieceCount((NSUInteger)NSHeight(source), STWindowsPrintMaxPieceSide);
                for (NSUInteger piece = 0; piece < columns * rows && !problem; piece++) {
                    @autoreleasepool {
                        NSRect from, to;
                        STWindowsPrintPieceRects(source, target, piece % columns, columns, piece / columns, rows, &from, &to);
                        if (NSWidth(from) <= 0.0 || NSHeight(from) <= 0.0 || NSWidth(to) <= 0.0 || NSHeight(to) <= 0.0) {
                            continue;
                        }
                        if (piece > 0) {
                            // Microsoft Print to PDF joins images that meet into one, and drops the row again;
                            // any GDI call between them keeps them apart. This one changes nothing: the
                            // raster op is D, the destination as it is.
                            PatBlt(dc, (int)NSMinX(to), (int)NSMinY(to), 1, 1, 0x00AA0029);
                        }
                        NSData *pixels = STPrintDIBPixels(rep, from);
                        BITMAPINFOHEADER header = { .biSize = sizeof(BITMAPINFOHEADER), .biWidth = (LONG)NSWidth(from),
                                                    .biHeight = -(LONG)NSHeight(from), .biPlanes = 1, .biBitCount = 32,
                                                    .biCompression = BI_RGB };
                        int drawn = StretchDIBits(dc, (int)NSMinX(to), (int)NSMinY(to), (int)NSWidth(to), (int)NSHeight(to),
                                                  0, 0, (int)NSWidth(from), (int)NSHeight(from), pixels.bytes,
                                                  (const BITMAPINFO *)&header, DIB_RGB_COLORS, SRCCOPY);
                        if (drawn == 0 || drawn == GDI_ERROR) {
                            problem = @"The page couldn't be drawn.";
                        }
                    }
                }
            }
            if (EndPage(dc) <= 0 && !problem) {
                problem = @"The printer stopped.";
            }
        }
    }
    if (problem) {
        AbortDoc(dc);
        if (failure) {
            *failure = problem;
        }
        return NO;
    }
    if (EndDoc(dc) <= 0) {
        if (failure) {
            *failure = @"The print job couldn't be finished.";
        }
        return NO;
    }
    return YES;
}

BOOL STWindowsPrintFlattened(NSImage *flattened, NSRect selection, STPrintOptions *options, STWindowsPrinterSheet sheet,
                             NSImage *(^flatten)(NSUInteger scale, NSRect clip), NSImage *(^selectionImage)(void),
                             BOOL (^printPages)(STPrintLayout *layout, NSImage *image), NSString **failure) {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.paperSize = sheet.paper;
    layout.printerMargins = sheet.printerMargins;
    layout.margins = STPrintMarginsMake(STPrintDefaultMargin, STPrintDefaultMargin, STPrintDefaultMargin, STPrintDefaultMargin);
    STConfigurePrintLayout(layout, options, flattened, selection);
    // A selection with nothing of the image in it leaves no source. An empty clip below would mean
    // the whole image, so it stops here and nothing outside the selection is printed (#355).
    if (options.selectionOnly && NSIsEmptyRect(layout.sourceRect)) {
        if (failure) {
            *failure = @"There's nothing to print.";
        }
        return NO;
    }

    // As Linux's: the scale comes from this layout; only the bitmap and its pixel counts change after it.
    // Its resolution is the printer's own (#355), so annotations print as fine as it does, within bounds.
    NSUInteger scale = [layout flattenScaleForImagePixelSize:STPrintImagePixelSize(flattened) dotsPerInch:sheet.dotsPerInch];
    NSRect keep = options.selectionOnly ? layout.sourceRect : NSZeroRect;
    NSImage *printed = flatten(scale, STPrintPointRectForPixelRect(flattened, keep));
    if (!printed) {
        scale = 1;
        printed = options.selectionOnly ? selectionImage() : flattened;
    }
    if (!printed) {
        if (failure) {
            *failure = @"The image couldn't be prepared for printing.";
        }
        return NO;
    }
    NSSize pixels = STPrintImagePixelSize(printed);
    layout.sourceRect = NSMakeRect(0.0, 0.0, pixels.width, pixels.height);
    layout.pixelsPerInch = layout.pixelsPerInch * scale;
    return printPages(layout, printed);
}

BOOL STWindowsPrintCanvas(ScreenshotCanvasView *canvas, STPrintOptions *options, void *dc, void *devMode, NSString *documentName,
                          NSString *outputPath, NSString **failure) {
    NSImage *flattened = [canvas flattenedImage];
    STWindowsPrinterSheet sheet = STWindowsPrinterSheetFromDC(dc);
    if (!flattened || !sheet.valid) {
        if (failure) {
            *failure = flattened ? @"The printer didn't say what paper it has." : @"There's nothing to print.";
        }
        return NO;
    }
    return STWindowsPrintFlattened(flattened, [canvas selectionImageRect], options, sheet,
        ^NSImage *(NSUInteger scale, NSRect clip) {
            return [canvas flattenedImageForPrintAtScale:scale withinRect:clip];
        },
        ^NSImage *(void) {
            return [canvas flattenedImageForSelection];
        },
        ^BOOL(STPrintLayout *layout, NSImage *image) {
            return STWindowsPrintPages(dc, devMode, layout, image, documentName, outputPath, failure);
        },
        failure);
}

static HGLOBAL STGlobalWithData(NSData *data) {
    if (data.length == 0) {
        return NULL;
    }
    HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE, data.length);
    void *bytes = handle ? GlobalLock(handle) : NULL;
    if (bytes) {
        memcpy(bytes, data.bytes, data.length);
        GlobalUnlock(handle);
    }
    return handle;
}

static NSData *STDataFromGlobal(HGLOBAL handle) {
    void *bytes = handle ? GlobalLock(handle) : NULL;
    NSData *data = bytes ? [NSData dataWithBytes:bytes length:GlobalSize(handle)] : nil;
    if (bytes) {
        GlobalUnlock(handle);
    }
    return data;
}

static void STTurnDevMode(HGLOBAL handle, STPrintOrientation orientation) {
    DEVMODEW *mode = handle ? (DEVMODEW *)GlobalLock(handle) : NULL;
    if (mode) {
        mode->dmFields |= DM_ORIENTATION;
        mode->dmOrientation = orientation == STPrintOrientationLandscape ? DMORIENT_LANDSCAPE : DMORIENT_PORTRAIT;
        GlobalUnlock(handle);
    }
}

STWindowsPrintDialogResult STWindowsRunPrintDialog(NSInteger windowNumber, STPrintOrientation orientation, NSUserDefaults *defaults) {
    STWindowsPrintDialogResult result = { STWindowsPrintDialogFailed, NULL, NULL, 0, 0, 0 };
    PRINTDLGEXW dialog;
    memset(&dialog, 0, sizeof(dialog));
    dialog.lStructSize = sizeof(dialog);
    dialog.hwndOwner = (HWND)(intptr_t)windowNumber;
    dialog.nMaxPageRanges = 0;
    dialog.nStartPage = START_PAGE_GENERAL;
    dialog.nCopies = 1;
    // Page ranges and the selection are our panel's; copies are the driver's.
    dialog.Flags = PD_RETURNDC | PD_NOPAGENUMS | PD_NOSELECTION | PD_NOCURRENTPAGE | PD_USEDEVMODECOPIESANDCOLLATE;
    NSData *savedMode = [defaults dataForKey:STDefaultsPrintWindowsDevModeKey];
    NSData *savedNames = [defaults dataForKey:STDefaultsPrintWindowsDevNamesKey];
    dialog.hDevMode = STGlobalWithData(savedMode);
    dialog.hDevNames = STGlobalWithData(savedNames);
    if (!dialog.hDevMode) {
        // The default printer's settings, so the dialog can start turned.
        PRINTDLGEXW defaultsOnly = dialog;
        defaultsOnly.hDC = NULL;
        defaultsOnly.Flags = PD_RETURNDEFAULT | PD_NOPAGENUMS | PD_NOSELECTION | PD_NOCURRENTPAGE;
        HRESULT got = PrintDlgExW(&defaultsOnly);
        if (SUCCEEDED(got)) {
            dialog.hDevMode = defaultsOnly.hDevMode;
            dialog.hDevNames = defaultsOnly.hDevNames;
        } else if (CommDlgExtendedError() == PDERR_NODEFAULTPRN) {
            result.outcome = STWindowsPrintDialogNoPrinter;
            return result;
        }
    }
    STTurnDevMode(dialog.hDevMode, orientation);
    HRESULT answer = PrintDlgExW(&dialog);
    if (FAILED(answer) && dialog.hDevMode && savedMode) {
        // The printer saved last time may be gone: ask afresh.
        GlobalFree(dialog.hDevMode);
        if (dialog.hDevNames) {
            GlobalFree(dialog.hDevNames);
        }
        dialog.hDevMode = NULL;
        dialog.hDevNames = NULL;
        [defaults removeObjectForKey:STDefaultsPrintWindowsDevModeKey];
        [defaults removeObjectForKey:STDefaultsPrintWindowsDevNamesKey];
        answer = PrintDlgExW(&dialog);
    }
    result.hresult = answer;
    result.action = dialog.dwResultAction;
    result.extendedError = CommDlgExtendedError();
    if (FAILED(answer)) {
        result.outcome = result.extendedError == PDERR_NODEFAULTPRN ? STWindowsPrintDialogNoPrinter : STWindowsPrintDialogFailed;
    } else if (dialog.dwResultAction == PD_RESULT_PRINT && dialog.hDC) {
        result.outcome = STWindowsPrintDialogPrint;
        result.dc = dialog.hDC;
        NSData *mode = STDataFromGlobal(dialog.hDevMode);
        NSData *names = STDataFromGlobal(dialog.hDevNames);
        if (mode.length > 0 && names.length > 0) {
            [defaults setObject:mode forKey:STDefaultsPrintWindowsDevModeKey];
            [defaults setObject:names forKey:STDefaultsPrintWindowsDevNamesKey];
            result.devMode = malloc(mode.length);
            if (result.devMode) {
                memcpy(result.devMode, mode.bytes, mode.length);
            }
        }
    } else {
        result.outcome = STWindowsPrintDialogCancelled;
        if (dialog.hDC) {
            DeleteDC(dialog.hDC);
        }
    }
    if (dialog.hDevMode) {
        GlobalFree(dialog.hDevMode);
    }
    if (dialog.hDevNames) {
        GlobalFree(dialog.hDevNames);
    }
    return result;
}

void STWindowsFreePrintDialogResult(STWindowsPrintDialogResult result) {
    if (result.dc) {
        DeleteDC((HDC)result.dc);
    }
    free(result.devMode);
}

void STWindowsDeleteDC(void *dc) {
    DeleteDC((HDC)dc);
}

NSString *STWindowsPrintSelectionProblem(NSSize imagePixels, NSRect selection, BOOL selectionOnly) {
    if (!selectionOnly) {
        return nil;
    }
    NSRect inImage = NSIntersectionRect(selection, NSMakeRect(0, 0, imagePixels.width, imagePixels.height));
    return NSIsEmptyRect(inImage) ? @"Nothing selected to print" : nil;
}

#endif
