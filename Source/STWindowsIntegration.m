#import "STWindowsIntegration.h"

#if defined(_WIN32)

#import <AppKit/AppKit.h>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <math.h>
#include <string.h>

/// The registered "PNG" format browsers, Office and the Snipping Tool use.
static UINT STPNGClipboardFormat(void) {
    static UINT format = 0;
    if (format == 0) {
        format = RegisterClipboardFormatW(L"PNG");
    }
    return format;
}

/// A message-only window to own the clipboard: opened without an owner, EmptyClipboard leaves it
/// with none, and SetClipboardData then fails.
static HWND STClipboardOwnerWindow(void) {
    static HWND window = NULL;
    if (window == NULL) {
        window = CreateWindowExW(0, L"STATIC", L"ScreenshotToolClipboard", 0, 0, 0, 0, 0,
                                 HWND_MESSAGE, NULL, GetModuleHandleW(NULL), NULL);
    }
    return window;
}

/// Opens the clipboard, retrying briefly: another app may have it open for a moment.
static BOOL STOpenClipboard(HWND owner) {
    for (int attempt = 0; attempt < 10; attempt++) {
        if (OpenClipboard(owner)) {
            return YES;
        }
        Sleep(20);
    }
    return NO;
}

static HGLOBAL STGlobalWithBytes(const void *bytes, size_t length) {
    HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE, length);
    if (handle == NULL) {
        return NULL;
    }
    void *destination = GlobalLock(handle);
    if (destination == NULL) {
        GlobalFree(handle);
        return NULL;
    }
    memcpy(destination, bytes, length);
    GlobalUnlock(handle);
    return handle;
}

/// Writes `rep`'s pixels to `out` as bottom-up rows of blue, green, red and alpha bytes.
static BOOL STCopyBGRAPixels(NSBitmapImageRep *rep, unsigned char *out) {
    NSInteger width = rep.pixelsWide;
    NSInteger height = rep.pixelsHigh;
    NSInteger samples = rep.samplesPerPixel;
    NSInteger colorSamples = samples - (rep.hasAlpha ? 1 : 0);
    NSString *space = rep.colorSpaceName;
    BOOL rgb = colorSamples == 3
        && ([space isEqualToString:NSDeviceRGBColorSpace] || [space isEqualToString:NSCalibratedRGBColorSpace]);
    BOOL white = colorSamples == 1
        && ([space isEqualToString:NSDeviceWhiteColorSpace] || [space isEqualToString:NSCalibratedWhiteColorSpace]);
    const unsigned char *data = rep.bitmapData;
    if (rep.bitsPerSample == 8 && !rep.isPlanar && rep.bitsPerPixel == samples * 8 && (rgb || white) && data) {
        BOOL alphaFirst = (rep.bitmapFormat & NSAlphaFirstBitmapFormat) != 0;
        NSInteger rowBytes = rep.bytesPerRow;
        for (NSInteger y = 0; y < height; y++) {
            const unsigned char *in = data + y * rowBytes;
            unsigned char *o = out + (height - 1 - y) * width * 4;
            for (NSInteger x = 0; x < width; x++, in += samples, o += 4) {
                const unsigned char *color = in;
                unsigned char alpha = 255;
                if (rep.hasAlpha) {
                    if (alphaFirst) {
                        alpha = in[0];
                        color = in + 1;
                    } else {
                        alpha = in[samples - 1];
                    }
                }
                if (white) {
                    o[0] = o[1] = o[2] = color[0];
                } else {
                    o[0] = color[2];
                    o[1] = color[1];
                    o[2] = color[0];
                }
                o[3] = alpha;
            }
        }
        return YES;
    }
    // Anything else, a pixel at a time.
    for (NSInteger y = 0; y < height; y++) {
        unsigned char *o = out + (height - 1 - y) * width * 4;
        for (NSInteger x = 0; x < width; x++, o += 4) {
            NSColor *color = [[rep colorAtX:x y:y] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
            if (color == nil) {
                return NO;
            }
            o[0] = (unsigned char)lround(color.blueComponent * 255.0);
            o[1] = (unsigned char)lround(color.greenComponent * 255.0);
            o[2] = (unsigned char)lround(color.redComponent * 255.0);
            o[3] = (unsigned char)lround(color.alphaComponent * 255.0);
        }
    }
    return YES;
}

NSData *STWindowsDIBDataForPNGData(NSData *pngData) {
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:pngData];
    NSInteger width = rep.pixelsWide;
    NSInteger height = rep.pixelsHigh;
    if (rep == nil || width <= 0 || height <= 0) {
        return nil;
    }
    BITMAPINFOHEADER header;
    memset(&header, 0, sizeof(header));
    header.biSize = sizeof(header);
    header.biWidth = (LONG)width;
    header.biHeight = (LONG)height;
    header.biPlanes = 1;
    header.biBitCount = 32;
    header.biCompression = BI_RGB;
    header.biSizeImage = (DWORD)(width * height * 4);

    NSMutableData *dib = [NSMutableData dataWithLength:sizeof(header) + header.biSizeImage];
    memcpy(dib.mutableBytes, &header, sizeof(header));
    if (!STCopyBGRAPixels(rep, (unsigned char *)dib.mutableBytes + sizeof(header))) {
        return nil;
    }
    return dib;
}

/// Bitmaps carry no dependable alpha, so the image is opaque; apps that keep transparency offer
/// PNG too. GDI draws the bitmap, so any depth or compression it knows is read.
NSData *STWindowsPNGDataForDIBData(NSData *dibData) {
    const void *dib = dibData.bytes;
    size_t length = dibData.length;
    if (length < sizeof(BITMAPINFOHEADER)) {
        return nil;
    }
    const BITMAPINFOHEADER *header = (const BITMAPINFOHEADER *)dib;
    if (header->biSize < sizeof(BITMAPINFOHEADER) || header->biSize > length
        || header->biCompression == BI_JPEG || header->biCompression == BI_PNG) {
        return nil;
    }
    LONG width = header->biWidth;
    LONG height = header->biHeight < 0 ? -header->biHeight : header->biHeight;
    if (width <= 0 || height <= 0 || width > 32768 || height > 32768) {
        return nil;
    }
    size_t masks = 0;
    if (header->biSize == sizeof(BITMAPINFOHEADER)) {
        if (header->biCompression == BI_BITFIELDS) {
            masks = 3 * sizeof(DWORD);
        } else if (header->biCompression == 6) { // BI_ALPHABITFIELDS
            masks = 4 * sizeof(DWORD);
        }
    }
    size_t colors = header->biClrUsed;
    if (colors == 0 && header->biBitCount <= 8) {
        colors = (size_t)1 << header->biBitCount;
    }
    size_t offset = header->biSize + masks + colors * sizeof(RGBQUAD);
    if (offset >= length) {
        return nil;
    }
    const void *bits = (const unsigned char *)dib + offset;

    BITMAPINFO target;
    memset(&target, 0, sizeof(target));
    target.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    target.bmiHeader.biWidth = width;
    target.bmiHeader.biHeight = -height;
    target.bmiHeader.biPlanes = 1;
    target.bmiHeader.biBitCount = 32;
    target.bmiHeader.biCompression = BI_RGB;
    void *targetBits = NULL;
    HBITMAP section = CreateDIBSection(NULL, &target, DIB_RGB_COLORS, &targetBits, NULL, 0);
    if (section == NULL || targetBits == NULL) {
        return nil;
    }
    HDC dc = CreateCompatibleDC(NULL);
    HGDIOBJ previous = SelectObject(dc, section);
    int lines = SetDIBitsToDevice(dc, 0, 0, (DWORD)width, (DWORD)height, 0, 0, 0, (UINT)height,
                                  bits, (const BITMAPINFO *)dib, DIB_RGB_COLORS);
    GdiFlush();

    NSData *pngData = nil;
    if (lines > 0) {
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                        pixelsWide:width
                                                                        pixelsHigh:height
                                                                     bitsPerSample:8
                                                                   samplesPerPixel:4
                                                                          hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:width * 4
                                                                      bitsPerPixel:32];
        const unsigned char *in = targetBits;
        unsigned char *out = rep.bitmapData;
        for (size_t i = 0; i < (size_t)width * (size_t)height; i++, in += 4, out += 4) {
            out[0] = in[2];
            out[1] = in[1];
            out[2] = in[0];
            out[3] = 255;
        }
        pngData = [rep representationUsingType:NSPNGFileType properties:@{}];
    }
    SelectObject(dc, previous);
    DeleteDC(dc);
    DeleteObject(section);
    return pngData;
}

/// The bytes of clipboard format `format`; the clipboard must be open.
static NSData *STOpenClipboardData(UINT format) {
    HANDLE handle = GetClipboardData(format);
    if (handle == NULL) {
        return nil;
    }
    const void *bytes = GlobalLock(handle);
    if (bytes == NULL) {
        return nil;
    }
    NSData *data = [NSData dataWithBytes:bytes length:GlobalSize(handle)];
    GlobalUnlock(handle);
    return data;
}

BOOL STWindowsClipboardIsNative(void) {
    return YES;
}

BOOL STWindowsClipboardHasImage(void) {
    UINT png = STPNGClipboardFormat();
    return IsClipboardFormatAvailable(CF_DIB) || IsClipboardFormatAvailable(CF_DIBV5)
        || IsClipboardFormatAvailable(CF_BITMAP) || (png != 0 && IsClipboardFormatAvailable(png));
}

BOOL STWindowsClipboardWritePNGData(NSData *pngData) {
    if (pngData.length == 0) {
        return NO;
    }
    NSData *dib = STWindowsDIBDataForPNGData(pngData);
    HWND owner = STClipboardOwnerWindow();
    if (owner == NULL || !STOpenClipboard(owner)) {
        return NO;
    }
    BOOL wrote = NO;
    if (EmptyClipboard()) {
        UINT png = STPNGClipboardFormat();
        HGLOBAL pngHandle = png != 0 ? STGlobalWithBytes(pngData.bytes, pngData.length) : NULL;
        if (pngHandle != NULL) {
            if (SetClipboardData(png, pngHandle) != NULL) {
                wrote = YES;
            } else {
                GlobalFree(pngHandle);
            }
        }
        HGLOBAL dibHandle = dib.length > 0 ? STGlobalWithBytes(dib.bytes, dib.length) : NULL;
        if (dibHandle != NULL) {
            if (SetClipboardData(CF_DIB, dibHandle) != NULL) {
                wrote = YES;
            } else {
                GlobalFree(dibHandle);
            }
        }
    }
    CloseClipboard();
    return wrote;
}

NSData *STWindowsClipboardPNGData(void) {
    if (!STWindowsClipboardHasImage() || !STOpenClipboard(NULL)) {
        return nil;
    }
    NSData *pngData = nil;
    UINT png = STPNGClipboardFormat();
    if (png != 0 && IsClipboardFormatAvailable(png)) {
        pngData = STOpenClipboardData(png);
        if (pngData.length > 0 && [NSBitmapImageRep imageRepWithData:pngData] == nil) {
            pngData = nil;
        }
    }
    if (pngData.length == 0 && IsClipboardFormatAvailable(CF_DIB)) {
        // Windows makes a CF_DIB of a CF_BITMAP or CF_DIBV5 when it's asked for one.
        NSData *dib = STOpenClipboardData(CF_DIB);
        pngData = STWindowsPNGDataForDIBData(dib);
    }
    CloseClipboard();
    return pngData.length > 0 ? pngData : nil;
}

NSArray<NSString *> *STWindowsClipboardFilePaths(void) {
    if (!IsClipboardFormatAvailable(CF_HDROP) || !STOpenClipboard(NULL)) {
        return nil;
    }
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    HDROP drop = (HDROP)GetClipboardData(CF_HDROP);
    if (drop != NULL) {
        UINT count = DragQueryFileW(drop, 0xFFFFFFFF, NULL, 0);
        for (UINT i = 0; i < count; i++) {
            UINT length = DragQueryFileW(drop, i, NULL, 0);
            if (length == 0) {
                continue;
            }
            NSMutableData *buffer = [NSMutableData dataWithLength:(length + 1) * sizeof(WCHAR)];
            if (DragQueryFileW(drop, i, buffer.mutableBytes, length + 1) == length) {
                [paths addObject:[NSString stringWithCharacters:buffer.bytes length:length]];
            }
        }
    }
    CloseClipboard();
    return paths.count > 0 ? paths : nil;
}

NSString *STWindowsQuotedCommandLineArgument(NSString *argument) {
    NSCharacterSet *special = [NSCharacterSet characterSetWithCharactersInString:@" \t\""];
    if (argument.length > 0 && [argument rangeOfCharacterFromSet:special].location == NSNotFound) {
        return argument;
    }
    NSMutableString *quoted = [NSMutableString stringWithString:@"\""];
    NSUInteger backslashes = 0;
    for (NSUInteger i = 0; i < argument.length; i++) {
        unichar c = [argument characterAtIndex:i];
        if (c == '\\') {
            backslashes++;
            continue;
        }
        // Backslashes before a quote are doubled, and the quote escaped.
        NSUInteger count = c == '"' ? backslashes * 2 + 1 : backslashes;
        for (NSUInteger j = 0; j < count; j++) {
            [quoted appendString:@"\\"];
        }
        backslashes = 0;
        [quoted appendFormat:@"%C", c];
    }
    // Backslashes before the closing quote are doubled.
    for (NSUInteger j = 0; j < backslashes * 2; j++) {
        [quoted appendString:@"\\"];
    }
    [quoted appendString:@"\""];
    return quoted;
}

BOOL STWindowsLaunchProcess(NSString *executablePath, NSArray<NSString *> *arguments) {
    if (executablePath.length == 0) {
        return NO;
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:STWindowsQuotedCommandLineArgument(executablePath)];
    for (NSString *argument in arguments) {
        [parts addObject:STWindowsQuotedCommandLineArgument(argument)];
    }
    NSString *commandLine = [parts componentsJoinedByString:@" "];
    NSUInteger length = commandLine.length;
    NSMutableData *commandBuffer = [NSMutableData dataWithLength:(length + 1) * sizeof(WCHAR)];
    [commandLine getCharacters:commandBuffer.mutableBytes range:NSMakeRange(0, length)];
    NSString *path = executablePath;
    NSMutableData *pathBuffer = [NSMutableData dataWithLength:(path.length + 1) * sizeof(WCHAR)];
    [path getCharacters:pathBuffer.mutableBytes range:NSMakeRange(0, path.length)];

    STARTUPINFOW startup;
    memset(&startup, 0, sizeof(startup));
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process;
    memset(&process, 0, sizeof(process));
    if (!CreateProcessW(pathBuffer.mutableBytes, commandBuffer.mutableBytes, NULL, NULL, FALSE, 0, NULL, NULL,
                        &startup, &process)) {
        return NO;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return YES;
}

#else

BOOL STWindowsClipboardIsNative(void) {
    return NO;
}

BOOL STWindowsClipboardHasImage(void) {
    return NO;
}

BOOL STWindowsClipboardWritePNGData(NSData *pngData) {
    (void)pngData;
    return NO;
}

NSData *STWindowsClipboardPNGData(void) {
    return nil;
}

NSArray<NSString *> *STWindowsClipboardFilePaths(void) {
    return nil;
}

BOOL STWindowsLaunchProcess(NSString *executablePath, NSArray<NSString *> *arguments) {
    (void)executablePath;
    (void)arguments;
    return NO;
}

NSData *STWindowsDIBDataForPNGData(NSData *pngData) {
    (void)pngData;
    return nil;
}

NSData *STWindowsPNGDataForDIBData(NSData *dibData) {
    (void)dibData;
    return nil;
}

NSString *STWindowsQuotedCommandLineArgument(NSString *argument) {
    return argument;
}

#endif
