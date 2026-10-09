/*
 * WindowsIntegrationProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * On Windows the app copies and pastes images through the Windows clipboard itself, which
 * GNUstep's pasteboard server bridges only text to, and starts another instance of itself shown
 * rather than through NSTask, which starts it hidden (STWindowsIntegration). These check the
 * conversions to and from a clipboard bitmap and the command line quoting, without touching the
 * clipboard the person running the tests is using.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "STWindowsIntegration.h"
#import "TestEnvironmentHelpers.h"
#include <string.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#endif

@interface WindowsIntegrationProbeTests : XCTestCase
@end

@implementation WindowsIntegrationProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

#if defined(_WIN32)

/// PNG data of a `width` by `height` image with `samples` 8-bit samples a pixel (3 or 4), rows top
/// down.
static NSData *STPNGData(NSInteger width, NSInteger height, NSInteger samples, const unsigned char *pixels) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                     pixelsWide:width
                                                                     pixelsHigh:height
                                                                  bitsPerSample:8
                                                                samplesPerPixel:samples
                                                                       hasAlpha:samples == 4
                                                                       isPlanar:NO
                                                                 colorSpaceName:NSDeviceRGBColorSpace
                                                                   bitmapFormat:NSAlphaNonpremultipliedBitmapFormat
                                                                    bytesPerRow:width * samples
                                                                   bitsPerPixel:samples * 8];
    memcpy(rep.bitmapData, pixels, (size_t)(width * height * samples));
    return [rep representationUsingType:NSPNGFileType properties:@{}];
}

/// The red, green, blue and alpha bytes of the pixel at `x`, `y` (from the top) of a PNG.
static void STPixel(NSData *pngData, NSInteger x, NSInteger y, unsigned char rgba[4]) {
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:pngData];
    NSUInteger samples[5] = {0, 0, 0, 255, 0};
    [rep getPixel:samples atX:x y:y];
    if (!rep.hasAlpha) {
        samples[3] = 255;
    }
    for (int i = 0; i < 4; i++) {
        rgba[i] = (unsigned char)samples[i];
    }
}

- (void)testAnImageCopiedOutIsABottomUpBitmapWithItsAlpha {
    // Top row: red, half-transparent green. Bottom row: blue, white.
    const unsigned char pixels[] = {
        255, 0, 0, 255,   0, 255, 0, 128,
        0, 0, 255, 255,   255, 255, 255, 255,
    };
    NSData *dib = STWindowsDIBDataForPNGData(STPNGData(2, 2, 4, pixels));
    XCTAssertEqual(dib.length, sizeof(BITMAPINFOHEADER) + 2 * 2 * 4);

    const BITMAPINFOHEADER *header = dib.bytes;
    XCTAssertEqual(header->biSize, sizeof(BITMAPINFOHEADER));
    XCTAssertEqual(header->biWidth, 2);
    XCTAssertEqual(header->biHeight, 2, @"bottom-up, as most apps read a bitmap");
    XCTAssertEqual(header->biBitCount, 32);
    XCTAssertEqual(header->biCompression, (DWORD)BI_RGB);

    const unsigned char *bgra = (const unsigned char *)dib.bytes + sizeof(BITMAPINFOHEADER);
    const unsigned char expected[] = {
        255, 0, 0, 255,   255, 255, 255, 255,
        0, 0, 255, 255,   0, 255, 0, 128,
    };
    XCTAssertEqual(memcmp(bgra, expected, sizeof(expected)), 0);
}

- (void)testAnImageWithoutAlphaIsCopiedOutOpaque {
    const unsigned char pixels[] = { 10, 20, 30,   40, 50, 60 };
    NSData *dib = STWindowsDIBDataForPNGData(STPNGData(2, 1, 3, pixels));
    XCTAssertEqual(dib.length, sizeof(BITMAPINFOHEADER) + 2 * 4);
    const unsigned char *bgra = (const unsigned char *)dib.bytes + sizeof(BITMAPINFOHEADER);
    const unsigned char expected[] = { 30, 20, 10, 255,   60, 50, 40, 255 };
    XCTAssertEqual(memcmp(bgra, expected, sizeof(expected)), 0);
}

- (void)testABitmapCopiedOutPastesBackAsTheSameImage {
    const unsigned char pixels[] = {
        255, 0, 0, 255,   0, 255, 0, 255,   0, 0, 255, 255,
        1, 2, 3, 255,     100, 150, 200, 255,   255, 255, 0, 255,
    };
    NSData *png = STWindowsPNGDataForDIBData(STWindowsDIBDataForPNGData(STPNGData(3, 2, 4, pixels)));
    XCTAssertNotNil(png);
    for (NSInteger y = 0; y < 2; y++) {
        for (NSInteger x = 0; x < 3; x++) {
            unsigned char rgba[4];
            STPixel(png, x, y, rgba);
            XCTAssertEqual(memcmp(rgba, pixels + (y * 3 + x) * 4, 4), 0, @"pixel %ld,%ld", (long)x, (long)y);
        }
    }
}

/// A packed DIB: `header`, then `extra` (masks or a color table), then `bits`.
static NSData *STDIB(BITMAPINFOHEADER header, const void *extra, size_t extraLength, const void *bits,
                     size_t bitsLength) {
    NSMutableData *dib = [NSMutableData dataWithBytes:&header length:sizeof(header)];
    if (extraLength > 0) {
        [dib appendBytes:extra length:extraLength];
    }
    [dib appendBytes:bits length:bitsLength];
    return dib;
}

static BITMAPINFOHEADER STHeader(LONG width, LONG height, WORD bitCount, DWORD compression) {
    BITMAPINFOHEADER header;
    memset(&header, 0, sizeof(header));
    header.biSize = sizeof(header);
    header.biWidth = width;
    header.biHeight = height;
    header.biPlanes = 1;
    header.biBitCount = bitCount;
    header.biCompression = compression;
    return header;
}

- (void)testA24BitBitmapPastesInWithItsRowsInOrder {
    // Bottom-up, each row padded to four bytes: the bottom row first.
    const unsigned char bits[] = {
        255, 0, 0,   0, 255, 0,   0, 0,   // bottom: blue, green
        0, 0, 255,   255, 255, 255,   0, 0,   // top: red, white
    };
    NSData *png = STWindowsPNGDataForDIBData(STDIB(STHeader(2, 2, 24, BI_RGB), NULL, 0, bits, sizeof(bits)));
    XCTAssertNotNil(png);
    unsigned char rgba[4];
    STPixel(png, 0, 0, rgba);
    XCTAssertEqual(memcmp(rgba, (unsigned char[]){255, 0, 0, 255}, 4), 0, @"top left is red");
    STPixel(png, 1, 0, rgba);
    XCTAssertEqual(memcmp(rgba, (unsigned char[]){255, 255, 255, 255}, 4), 0, @"top right is white");
    STPixel(png, 0, 1, rgba);
    XCTAssertEqual(memcmp(rgba, (unsigned char[]){0, 0, 255, 255}, 4), 0, @"bottom left is blue");
    STPixel(png, 1, 1, rgba);
    XCTAssertEqual(memcmp(rgba, (unsigned char[]){0, 255, 0, 255}, 4), 0, @"bottom right is green");
}

- (void)testATopDownBitfieldsBitmapPastesInPastItsMasks {
    // A negative height is top-down; BI_BITFIELDS puts three masks after the header.
    const DWORD masks[] = { 0x00FF0000, 0x0000FF00, 0x000000FF };
    const unsigned char bits[] = {
        0, 0, 255, 0,   0, 255, 0, 0,   // top: red, green
    };
    NSData *png = STWindowsPNGDataForDIBData(STDIB(STHeader(2, -1, 32, BI_BITFIELDS), masks, sizeof(masks),
                                                   bits, sizeof(bits)));
    XCTAssertNotNil(png);
    unsigned char rgba[4];
    STPixel(png, 0, 0, rgba);
    XCTAssertEqual(memcmp(rgba, (unsigned char[]){255, 0, 0, 255}, 4), 0, @"red, and opaque");
    STPixel(png, 1, 0, rgba);
    XCTAssertEqual(memcmp(rgba, (unsigned char[]){0, 255, 0, 255}, 4), 0, @"green, and opaque");
}

- (void)testAPaletteBitmapPastesInThroughItsColorTable {
    BITMAPINFOHEADER header = STHeader(2, 1, 8, BI_RGB);
    header.biClrUsed = 2;
    const RGBQUAD palette[] = { {0, 128, 255, 0}, {255, 0, 128, 0} };
    const unsigned char bits[] = { 1, 0, 0, 0 };
    NSData *png = STWindowsPNGDataForDIBData(STDIB(header, palette, sizeof(palette), bits, sizeof(bits)));
    XCTAssertNotNil(png);
    unsigned char rgba[4];
    STPixel(png, 0, 0, rgba);
    XCTAssertEqual(memcmp(rgba, (unsigned char[]){128, 0, 255, 255}, 4), 0);
    STPixel(png, 1, 0, rgba);
    XCTAssertEqual(memcmp(rgba, (unsigned char[]){255, 128, 0, 255}, 4), 0);
}

- (void)testATruncatedBitmapIsRefused {
    BITMAPINFOHEADER header = STHeader(2, 2, 24, BI_RGB);
    XCTAssertNil(STWindowsPNGDataForDIBData([NSData dataWithBytes:&header length:sizeof(header) - 4]));
    XCTAssertNil(STWindowsPNGDataForDIBData([NSData dataWithBytes:&header length:sizeof(header)]));
}

- (void)testArgumentsAreQuotedOnlyWhenTheyNeedIt {
    XCTAssertEqualObjects(STWindowsQuotedCommandLineArgument(@"C:\\Temp\\clip.png"), @"C:\\Temp\\clip.png");
    XCTAssertEqualObjects(STWindowsQuotedCommandLineArgument(@"C:\\My Pictures\\clip.png"),
                          @"\"C:\\My Pictures\\clip.png\"");
    XCTAssertEqualObjects(STWindowsQuotedCommandLineArgument(@""), @"\"\"");
    // Backslashes are doubled only before a quote, the closing one included.
    XCTAssertEqualObjects(STWindowsQuotedCommandLineArgument(@"C:\\My Pictures\\"), @"\"C:\\My Pictures\\\\\"");
    XCTAssertEqualObjects(STWindowsQuotedCommandLineArgument(@"say \"hi\""), @"\"say \\\"hi\\\"\"");
}

- (void)testQuotedArgumentsReadBackAsWritten {
    NSArray<NSString *> *arguments = @[ @"C:\\My Pictures\\a b.png", @"plain", @"trailing\\ ", @"q\"uote\\\"d",
                                        @"C:\\dir with space\\" ];
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:@"app.exe"];
    for (NSString *argument in arguments) {
        [parts addObject:STWindowsQuotedCommandLineArgument(argument)];
    }
    NSString *commandLine = [parts componentsJoinedByString:@" "];
    NSMutableData *buffer = [NSMutableData dataWithLength:(commandLine.length + 1) * sizeof(WCHAR)];
    [commandLine getCharacters:buffer.mutableBytes range:NSMakeRange(0, commandLine.length)];

    int count = 0;
    LPWSTR *argv = CommandLineToArgvW(buffer.mutableBytes, &count);
    XCTAssertTrue(argv != NULL);
    XCTAssertEqual(count, (int)arguments.count + 1);
    for (int i = 1; i < count && i <= (int)arguments.count; i++) {
        NSString *read = [NSString stringWithCharacters:argv[i] length:wcslen(argv[i])];
        XCTAssertEqualObjects(read, arguments[i - 1]);
    }
    LocalFree(argv);
}

#else

- (void)testTheWindowsClipboardIsUsedOnlyOnWindows {
    XCTAssertFalse(STWindowsClipboardIsNative());
    XCTAssertNil(STWindowsClipboardPNGData());
}

#endif

@end
