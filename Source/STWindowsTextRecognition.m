#import "STWindowsIntegration.h"
#import "STTextRecognizer.h"

#if defined(_WIN32)

#import <AppKit/AppKit.h>
#define WIN32_LEAN_AND_MEAN
// The headers' C helpers (..._CreateFromByteArray, IAsyncInfo_get_Status) for calls through vtables.
#define COBJMACROS
#include <windows.h>
// The WinRT headers declare with the interface macro, which GNUstep's headers undefine (it would
// turn @interface into @struct): defined only around them, as libs-sharing does. initguid.h makes
// this file define the IIDs it uses.
#if !defined(interface)
#define interface struct
#define ST_UNDEF_INTERFACE
#endif
#include <initguid.h>
#include <roapi.h>
#include <winstring.h>
#include <asyncinfo.h>
#include <windows.foundation.h>
#include <windows.graphics.imaging.h>
#include <windows.security.cryptography.h>
#if defined(ST_UNDEF_INTERFACE)
#undef interface
#undef ST_UNDEF_INTERFACE
#endif

typedef __x_ABI_CWindows_CGraphics_CImaging_CISoftwareBitmap STSoftwareBitmap;
typedef __x_ABI_CWindows_CGraphics_CImaging_CISoftwareBitmapStatics STSoftwareBitmapStatics;
typedef __x_ABI_CWindows_CSecurity_CCryptography_CICryptographicBufferStatics STCryptographicBufferStatics;
typedef __x_ABI_CWindows_CStorage_CStreams_CIBuffer STBuffer;

// Windows.Media.Ocr isn't in mingw-w64's headers. Its interfaces are reached by vtable slot, as
// the system's metadata (Windows.Media.Ocr.winmd) orders them, after IInspectable's six:
//   IOcrEngineStatics: 6 MaxImageDimension, 7 AvailableRecognizerLanguages, 8 IsLanguageSupported,
//                      9 TryCreateFromLanguage, 10 TryCreateFromUserProfileLanguages
//   IOcrEngine: 6 RecognizeAsync, 7 RecognizerLanguage
//   IOcrResult: 6 Lines, 7 TextAngle, 8 Text
//   IOcrLine: 6 Words, 7 Text
//   IOcrWord: 6 BoundingRect, 7 Text
// and the generic ones they hand back: IAsyncOperation<T> 8 GetResults; IVectorView<T> 6 GetAt,
// 7 Size. Only the statics are asked for by IID; the rest come back as these pointers.
typedef struct STWinRTObject { void **lpVtbl; } STWinRTObject;
DEFINE_GUID(STIIDOcrEngineStatics, 0x5bffa85a, 0x3384, 0x3540, 0x99, 0x40, 0x69, 0x91, 0x20, 0xd4, 0x28, 0xa8);
#define ST_SLOT(object, index, type) ((type)((object)->lpVtbl[index]))
typedef HRESULT (STDMETHODCALLTYPE *STGetUInt32)(void *, UINT32 *);
typedef HRESULT (STDMETHODCALLTYPE *STGetObject)(void *, void **);
typedef HRESULT (STDMETHODCALLTYPE *STGetAt)(void *, UINT32, void **);
typedef HRESULT (STDMETHODCALLTYPE *STGetString)(void *, HSTRING *);
typedef HRESULT (STDMETHODCALLTYPE *STGetRect)(void *, __x_ABI_CWindows_CFoundation_CRect *);
typedef HRESULT (STDMETHODCALLTYPE *STRecognizeAsync)(void *, STSoftwareBitmap *, void **);

static void STRelease(void *object) {
    if (object) {
        ((IUnknown *)object)->lpVtbl->Release((IUnknown *)object);
    }
}

static HRESULT STActivationFactory(const WCHAR *name, REFIID iid, void **factory) {
    HSTRING className = NULL;
    HRESULT result = WindowsCreateString(name, (UINT32)wcslen(name), &className);
    if (SUCCEEDED(result)) {
        result = RoGetActivationFactory(className, iid, factory);
        WindowsDeleteString(className);
    }
    return result;
}

static NSString *STStringFromHString(HSTRING string) {
    UINT32 length = 0;
    const WCHAR *characters = WindowsGetStringRawBuffer(string, &length);
    NSString *text = characters ? [NSString stringWithCharacters:(const unichar *)characters length:length] : @"";
    WindowsDeleteString(string);
    return text;
}

/// A thread's WinRT, for as long as an object of this lives: a multithreaded apartment unless the
/// thread already has one, as a GCD worker may.
typedef struct { BOOL initialized; } STWinRTScope;

static STWinRTScope STWinRTBegin(void) {
    HRESULT result = RoInitialize(RO_INIT_MULTITHREADED);
    STWinRTScope scope = { SUCCEEDED(result) };
    return scope;
}

static void STWinRTEnd(STWinRTScope scope) {
    if (scope.initialized) {
        RoUninitialize();
    }
}

/// The OCR engine for the user's profile languages, or NULL when Windows has none for them.
static STWinRTObject *STCreateOcrEngine(UINT32 *maxDimension) {
    STWinRTObject *statics = NULL;
    if (FAILED(STActivationFactory(L"Windows.Media.Ocr.OcrEngine", &STIIDOcrEngineStatics, (void **)&statics))) {
        return NULL;
    }
    if (maxDimension) {
        *maxDimension = 0;
        ST_SLOT(statics, 6, STGetUInt32)(statics, maxDimension);
    }
    STWinRTObject *engine = NULL;
    ST_SLOT(statics, 10, STGetObject)(statics, (void **)&engine);
    STRelease(statics);
    return engine;
}

BOOL STWindowsTextRecognitionAvailable(void) {
    static dispatch_once_t once;
    static BOOL available = NO;
    dispatch_once(&once, ^{
        // On a thread of its own: the main thread's apartment is OLE's, single-threaded.
        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            STWinRTScope scope = STWinRTBegin();
            STWinRTObject *engine = STCreateOcrEngine(NULL);
            available = engine != NULL;
            STRelease(engine);
            STWinRTEnd(scope);
        });
    });
    return available;
}

/// `rep`'s pixels in `crop` as premultiplied BGRA, shrunk by a whole `factor` (each output pixel
/// the average of factor × factor), on white: what a SoftwareBitmap is made from.
static NSData *STBGRAPixels(NSBitmapImageRep *rep, NSRect crop, NSUInteger factor, NSUInteger *width, NSUInteger *height) {
    NSUInteger x0 = (NSUInteger)NSMinX(crop), y0 = (NSUInteger)NSMinY(crop);
    NSUInteger outWidth = MAX((NSUInteger)1, (NSUInteger)NSWidth(crop) / factor);
    NSUInteger outHeight = MAX((NSUInteger)1, (NSUInteger)NSHeight(crop) / factor);
    NSMutableData *pixels = [NSMutableData dataWithLength:outWidth * outHeight * 4];
    uint8_t *out = pixels.mutableBytes;
    NSInteger samples = rep.samplesPerPixel;
    BOOL alpha = rep.hasAlpha;
    BOOL premultiplied = (rep.bitmapFormat & NSAlphaNonpremultipliedBitmapFormat) == 0;
    BOOL alphaFirst = (rep.bitmapFormat & NSAlphaFirstBitmapFormat) != 0;
    // Bytes directly for 8-bit interleaved RGB(A) and grey, which is what PNG and screenshots
    // are; any other layout through -getPixel:atX:y:.
    BOOL direct = rep.bitsPerSample == 8 && !rep.isPlanar && rep.bitmapData != NULL;
    const uint8_t *data = rep.bitmapData;
    NSInteger bytesPerRow = rep.bytesPerRow, bytesPerPixel = rep.bitsPerPixel / 8;
    NSUInteger maxValue = (1u << rep.bitsPerSample) - 1;
    NSInteger colours = samples - (alpha ? 1 : 0);
    for (NSUInteger oy = 0; oy < outHeight; oy++) {
        for (NSUInteger ox = 0; ox < outWidth; ox++) {
            NSUInteger sum[3] = { 0, 0, 0 };
            for (NSUInteger dy = 0; dy < factor; dy++) {
                for (NSUInteger dx = 0; dx < factor; dx++) {
                    NSUInteger x = x0 + ox * factor + dx, y = y0 + oy * factor + dy;
                    NSUInteger value[5] = { 0, 0, 0, 0, 0 };
                    if (direct) {
                        const uint8_t *p = data + y * bytesPerRow + x * bytesPerPixel;
                        for (NSInteger s = 0; s < samples && s < 5; s++) {
                            value[s] = p[s];
                        }
                    } else {
                        [rep getPixel:value atX:(NSInteger)x y:(NSInteger)y];
                        for (NSInteger s = 0; s < samples && s < 5; s++) {
                            value[s] = value[s] * 255 / maxValue;
                        }
                    }
                    NSUInteger a = 255, first = 0;
                    if (alpha) {
                        a = alphaFirst ? value[0] : value[samples - 1];
                        first = alphaFirst ? 1 : 0;
                    }
                    for (NSInteger c = 0; c < 3; c++) {
                        NSUInteger v = value[first + (colours >= 3 ? c : 0)];
                        // Onto white, as on paper: OCR reads dark text on a light ground.
                        NSUInteger on = premultiplied ? v + (255 - a) : (v * a + 255 * (255 - a)) / 255;
                        sum[c] += MIN(on, (NSUInteger)255);
                    }
                }
            }
            NSUInteger n = factor * factor;
            uint8_t *q = out + (oy * outWidth + ox) * 4;
            q[0] = (uint8_t)(sum[2] / n);
            q[1] = (uint8_t)(sum[1] / n);
            q[2] = (uint8_t)(sum[0] / n);
            q[3] = 255;
        }
    }
    *width = outWidth;
    *height = outHeight;
    return pixels;
}

static STSoftwareBitmap *STCreateSoftwareBitmap(NSData *pixels, NSUInteger width, NSUInteger height) {
    STCryptographicBufferStatics *buffers = NULL;
    STSoftwareBitmapStatics *bitmaps = NULL;
    STBuffer *buffer = NULL;
    STSoftwareBitmap *bitmap = NULL;
    if (SUCCEEDED(STActivationFactory(RuntimeClass_Windows_Security_Cryptography_CryptographicBuffer,
                                      &IID___x_ABI_CWindows_CSecurity_CCryptography_CICryptographicBufferStatics,
                                      (void **)&buffers))
        && SUCCEEDED(__x_ABI_CWindows_CSecurity_CCryptography_CICryptographicBufferStatics_CreateFromByteArray(
               buffers, (UINT32)pixels.length, (BYTE *)pixels.bytes, &buffer))
        && SUCCEEDED(STActivationFactory(RuntimeClass_Windows_Graphics_Imaging_SoftwareBitmap,
                                         &IID___x_ABI_CWindows_CGraphics_CImaging_CISoftwareBitmapStatics,
                                         (void **)&bitmaps))) {
        __x_ABI_CWindows_CGraphics_CImaging_CISoftwareBitmapStatics_CreateCopyWithAlphaFromBuffer(
            bitmaps, buffer, BitmapPixelFormat_Bgra8, (INT32)width, (INT32)height, BitmapAlphaMode_Premultiplied, &bitmap);
    }
    STRelease(buffer);
    STRelease(bitmaps);
    STRelease(buffers);
    return bitmap;
}

/// The result of an IAsyncOperation, waited for (it runs on Windows' own threads).
static STWinRTObject *STAwaitOperation(STWinRTObject *operation, NSTimeInterval timeout) {
    IAsyncInfo *info = NULL;
    if (FAILED(((IUnknown *)operation)->lpVtbl->QueryInterface((IUnknown *)operation, &IID_IAsyncInfo, (void **)&info))) {
        return NULL;
    }
    AsyncStatus status = Started;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (SUCCEEDED(IAsyncInfo_get_Status(info, &status)) && status == Started && [deadline timeIntervalSinceNow] > 0) {
        Sleep(10);
    }
    if (status == Started) {
        IAsyncInfo_Cancel(info);
    }
    STRelease(info);
    STWinRTObject *result = NULL;
    if (status == Completed) {
        ST_SLOT(operation, 8, STGetObject)(operation, (void **)&result);
    }
    return result;
}

/// The words of an OcrResult as lines, their boxes mapped back into the whole image.
static NSArray<STRecognizedLine *> *STLinesFromOcrResult(STWinRTObject *result, NSPoint origin, CGFloat scale) {
    NSMutableArray<STRecognizedLine *> *lines = [NSMutableArray array];
    STWinRTObject *lineList = NULL;
    ST_SLOT(result, 6, STGetObject)(result, (void **)&lineList);
    UINT32 lineCount = 0;
    if (lineList) {
        ST_SLOT(lineList, 7, STGetUInt32)(lineList, &lineCount);
    }
    for (UINT32 i = 0; i < lineCount; i++) {
        STWinRTObject *line = NULL, *wordList = NULL;
        ST_SLOT(lineList, 6, STGetAt)(lineList, i, (void **)&line);
        if (line) {
            ST_SLOT(line, 6, STGetObject)(line, (void **)&wordList);
        }
        UINT32 wordCount = 0;
        if (wordList) {
            ST_SLOT(wordList, 7, STGetUInt32)(wordList, &wordCount);
        }
        NSMutableArray<STRecognizedWord *> *words = [NSMutableArray array];
        for (UINT32 j = 0; j < wordCount; j++) {
            STWinRTObject *word = NULL;
            ST_SLOT(wordList, 6, STGetAt)(wordList, j, (void **)&word);
            if (!word) {
                continue;
            }
            __x_ABI_CWindows_CFoundation_CRect box = { 0 };
            HSTRING text = NULL;
            ST_SLOT(word, 6, STGetRect)(word, &box);
            ST_SLOT(word, 7, STGetString)(word, &text);
            NSString *string = STStringFromHString(text);
            if (string.length > 0) {
                NSRect bounds = NSMakeRect(origin.x + box.X * scale, origin.y + box.Y * scale,
                                           box.Width * scale, box.Height * scale);
                [words addObject:[[STRecognizedWord alloc] initWithText:string bounds:bounds]];
            }
            STRelease(word);
        }
        if (words.count > 0) {
            [lines addObject:[[STRecognizedLine alloc] initWithWords:words]];
        }
        STRelease(wordList);
        STRelease(line);
    }
    STRelease(lineList);
    return lines;
}

/// The image read around a part, in pixels each side.
static const CGFloat STOcrMargin = 64.0;

NSArray<STRecognizedLine *> *STWindowsRecognizeText(NSURL *url, NSRect rect, NSString **failure) {
    NSString *problem = nil;
    NSArray<STRecognizedLine *> *lines = nil;
    STWinRTScope scope = STWinRTBegin();
    @autoreleasepool {
        NSBitmapImageRep *rep = url.isFileURL ? (NSBitmapImageRep *)[NSBitmapImageRep imageRepWithContentsOfFile:url.path] : nil;
        UINT32 maxDimension = 0;
        STWinRTObject *engine = STCreateOcrEngine(&maxDimension);
        if (![rep isKindOfClass:[NSBitmapImageRep class]] || rep.pixelsWide <= 0 || rep.pixelsHigh <= 0) {
            problem = @"The image couldn't be read.";
        } else if (!engine) {
            problem = @"Windows has no text recognition for your languages. Add one in Settings > Time & language > Language & region.";
        } else {
            NSRect whole = NSMakeRect(0.0, 0.0, rep.pixelsWide, rep.pixelsHigh);
            NSRect wanted = NSIsEmptyRect(rect) ? whole : NSIntersectionRect(NSIntegralRect(rect), whole);
            // A part is read with a margin around it, then keeps its own words: Windows reads
            // nothing in a crop as tight as one line's selection.
            NSRect crop = NSIntersectionRect(NSInsetRect(wanted, -STOcrMargin, -STOcrMargin), whole);
            if (NSIsEmptyRect(wanted)) {
                lines = @[];
            } else {
                // Windows reads images up to MaxImageDimension (10000) on a side: larger ones are
                // shrunk by a whole factor, and the boxes grown back.
                CGFloat longest = MAX(NSWidth(crop), NSHeight(crop));
                NSUInteger factor = maxDimension > 0 && longest > maxDimension ? (NSUInteger)ceil(longest / maxDimension) : 1;
                NSUInteger width = 0, height = 0;
                NSData *pixels = STBGRAPixels(rep, crop, factor, &width, &height);
                STSoftwareBitmap *bitmap = STCreateSoftwareBitmap(pixels, width, height);
                STWinRTObject *operation = NULL, *result = NULL;
                if (bitmap) {
                    ST_SLOT(engine, 6, STRecognizeAsync)(engine, bitmap, (void **)&operation);
                }
                if (operation) {
                    result = STAwaitOperation(operation, 60.0);
                }
                if (result) {
                    lines = STLinesFromOcrResult(result, crop.origin, (CGFloat)factor);
                    if (!NSEqualRects(wanted, whole)) {
                        lines = STLinesInsideRect(lines, wanted);
                    }
                } else {
                    problem = @"Windows couldn't read the text in the image.";
                }
                STRelease(result);
                STRelease(operation);
                STRelease(bitmap);
            }
        }
        STRelease(engine);
    }
    STWinRTEnd(scope);
    if (failure) {
        *failure = problem;
    }
    return problem ? nil : lines;
}

#else

BOOL STWindowsTextRecognitionAvailable(void) {
    return NO;
}

NSArray<STRecognizedLine *> *STWindowsRecognizeText(NSURL *url, NSRect rect, NSString **failure) {
    (void)url;
    (void)rect;
    if (failure) {
        *failure = @"Windows text recognition is only on Windows.";
    }
    return nil;
}

#endif
