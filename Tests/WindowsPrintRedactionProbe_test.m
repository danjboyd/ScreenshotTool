/*
 * WindowsPrintRedactionProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * On Windows too, printing never bypasses a redaction, and a selection's print holds only the selection
 * (#355). The whole path as the Print command takes it, on "Microsoft Print to PDF"; the PDF's pages are
 * rendered with pdftoppm and its embedded images read with pdfimages. Each check is shown to see the
 * secret when it's there. Skips, saying so, without that printer or poppler.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if defined(_WIN32)

#import "AppDelegate.h"
#import "MarkupStroke.h"
#import "ScreenshotCanvasView.h"
#import "STPrintLayout.h"
#import "STPrintOptions.h"
#import "STWindowsPrint.h"
#import "TestEnvironmentHelpers.h"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>

@interface AppDelegate (WindowsPrintRedactionProbe)
- (void)setupWindowAndContent;
- (ScreenshotCanvasView *)canvasView;
- (void)setupMenus;
- (void)printDocument:(id)sender;
- (void)printSelection:(id)sender;
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
@end

@interface ScreenshotCanvasView (WindowsPrintRedactionProbe)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
@end

/// As PrintRedactionProbe's: a checkerboard of a colour that's nowhere else in the image. A redaction
/// is a mosaic of cell averages, so a checkerboard's colour survives only if the original pixels do.
/// Its squares are 6 pixels, not PrintRedactionProbe's 1: Microsoft Print to PDF stores images as JPEG,
/// whose coarser colour would blend single pixels to grey and hide the secret from these checks.
static const unsigned char STSecret[3] = { 255, 0, 255 };
static const unsigned char STSecretOther[3] = { 0, 255, 0 };

@interface WindowsPrintRedactionProbeTests : XCTestCase
@end

@implementation WindowsPrintRedactionProbeTests {
    AppDelegate *_appDelegate;
    BOOL _shouldSkip;
    NSString *_directory;
    NSString *_popplerFolder;
}

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
    _appDelegate = [[AppDelegate alloc] init];
    @try {
        [_appDelegate setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
        return;
    }
    _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:NULL];
    [_appDelegate.canvasView loadImage:[self imageWithSecret]];
    NSMutableArray<NSString *> *folders = [[[[NSProcessInfo processInfo] environment][@"PATH"] componentsSeparatedByString:@";"] mutableCopy];
    [folders addObject:@"C:/msys64/ucrt64/bin"];
    [folders addObject:@"C:/msys64/mingw64/bin"];
    for (NSString *folder in folders) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:[folder stringByAppendingPathComponent:@"pdfimages.exe"]]) {
            _popplerFolder = folder;
            break;
        }
    }
}

- (void)tearDown {
    if (_directory) {
        [[NSFileManager defaultManager] removeItemAtPath:_directory error:NULL];
    }
    [super tearDown];
}

- (BOOL)canPrint {
    if (_shouldSkip) {
        return NO;
    }
    if (!STWindowsPrinterExists(STWindowsPDFPrinterName)) {
        NSLog(@"WindowsPrintRedactionProbe: SKIPPED: no \"%@\" printer here", STWindowsPDFPrinterName);
        return NO;
    }
    if (!_popplerFolder) {
        NSLog(@"WindowsPrintRedactionProbe: SKIPPED: no poppler here to read the PDF with");
        return NO;
    }
    return YES;
}

/// 400 × 200, white but for the secret's 100 × 50 at (50, 40) from the top left, and a solid blue
/// 100 × 60 at (200, 100) to select.
- (NSImage *)imageWithSecret {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:400 pixelsHigh:200 bitsPerSample:8
                                                               samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    unsigned char *data = rep.bitmapData;
    static const unsigned char white[3] = { 255, 255, 255 };
    static const unsigned char blue[3] = { 0, 0, 255 };
    for (NSInteger y = 0; y < 200; y++) {
        for (NSInteger x = 0; x < 400; x++) {
            const unsigned char *color = white;
            if (x >= 50 && x < 150 && y >= 40 && y < 90) {
                color = ((x / 6) + (y / 6)) % 2 == 0 ? STSecret : STSecretOther;
            } else if (x >= 200 && x < 300 && y >= 100 && y < 160) {
                color = blue;
            }
            unsigned char *p = data + y * rep.bytesPerRow + x * 4;
            p[0] = color[0];
            p[1] = color[1];
            p[2] = color[2];
            p[3] = 255;
        }
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(400, 200)];
    [image addRepresentation:rep];
    return image;
}

/// The Print command's path, to a file.
- (NSString *)printWithOptions:(STPrintOptions *)options {
    NSString *pdf = [_directory stringByAppendingPathComponent:@"print.pdf"];
    void *devMode = NULL;
    void *dc = STWindowsCreatePrinterDC(STWindowsPDFPrinterName, &devMode);
    XCTAssertTrue(dc != NULL);
    NSString *failure = nil;
    XCTAssertTrue(STWindowsPrintCanvas(_appDelegate.canvasView, options, dc, devMode, @"WindowsPrintRedactionProbe", pdf, &failure), @"%@", failure);
    STWindowsDeleteDC(dc);
    free(devMode);
    unsigned long long last = 0;
    for (int i = 0; i < 150; i++) {
        unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:pdf error:NULL] fileSize];
        if (size > 0 && size == last) {
            return pdf;
        }
        last = size;
        Sleep(200);
    }
    XCTFail(@"No PDF");
    return pdf;
}

- (void)run:(NSString *)tool arguments:(NSArray<NSString *> *)arguments {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = [_popplerFolder stringByAppendingPathComponent:[tool stringByAppendingPathExtension:@"exe"]];
    task.arguments = arguments;
    [task launch];
    [task waitUntilExit];
    XCTAssertEqual(task.terminationStatus, 0, @"%@", tool);
}

/// Counts pixels by colour in the PPMs named `prefix`-*.
- (NSUInteger)countInFilesWithPrefix:(NSString *)prefix blue:(NSUInteger *)blue other:(NSUInteger *)other files:(NSUInteger *)fileCount {
    NSUInteger secret = 0, blues = 0, others = 0, files = 0;
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_directory error:NULL]) {
        if (![name hasPrefix:prefix] || ![name.pathExtension isEqualToString:@"ppm"]) {
            continue;
        }
        files++;
        NSData *ppm = [NSData dataWithContentsOfFile:[_directory stringByAppendingPathComponent:name]];
        int width = 0, height = 0, maximum = 0, length = 0;
        NSString *header = [[NSString alloc] initWithData:[ppm subdataWithRange:NSMakeRange(0, MIN(ppm.length, (NSUInteger)64))]
                                                 encoding:NSISOLatin1StringEncoding];
        XCTAssertEqual(sscanf(header.UTF8String, "P6 %d %d %d%n", &width, &height, &maximum, &length), 3, @"%@", name);
        const unsigned char *pixels = (const unsigned char *)ppm.bytes + length + 1;
        for (NSInteger i = 0; i < (NSInteger)width * height; i++) {
            const unsigned char *p = pixels + i * 3;
            if (p[0] > 200 && p[1] < 80 && p[2] > 200) {
                secret++;
            } else if (p[0] < 40 && p[1] < 40 && p[2] > 200) {
                blues++;
            } else if (!(p[0] > 240 && p[1] > 240 && p[2] > 240)) {
                others++;
            }
        }
    }
    if (blue) {
        *blue = blues;
    }
    if (other) {
        *other = others;
    }
    if (fileCount) {
        *fileCount = files;
    }
    return secret;
}

- (void)renderPDF:(NSString *)pdf {
    [self run:@"pdftoppm" arguments:@[ @"-r", @"288", pdf, [_directory stringByAppendingPathComponent:@"page"] ]];
    [self run:@"pdfimages" arguments:@[ pdf, [_directory stringByAppendingPathComponent:@"image"] ]];
}

- (STPrintOptions *)actualSize {
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.fit = STPrintFitActualSize;
    options.orientation = STPrintOrientationPortrait;
    return options;
}

/// Shows the checks see the secret, so that the others' zeroes mean something.
- (void)testWithoutARedactionTheSecretIsFound {
    if (![self canPrint]) {
        return;
    }
    [self renderPDF:[self printWithOptions:[self actualSize]]];
    NSUInteger images = 0;
    XCTAssertGreaterThan([self countInFilesWithPrefix:@"page" blue:NULL other:NULL files:NULL], (NSUInteger)100, @"on the page");
    NSUInteger embedded = [self countInFilesWithPrefix:@"image" blue:NULL other:NULL files:&images];
    NSLog(@"WindowsPrintRedactionProbe: unredacted: %lu embedded image files, %lu secret pixels in them", (unsigned long)images, (unsigned long)embedded);
    XCTAssertGreaterThan(images, (NSUInteger)0, @"The driver's images must be readable, or the redacted test proves nothing about the file");
    XCTAssertGreaterThan(embedded, (NSUInteger)100, @"in the file");
}

- (void)testARedactedImagePrintsWithoutWhatItHides {
    if (![self canPrint]) {
        return;
    }
    NSArray *rects = @[ [NSValue valueWithRect:NSMakeRect(50, 40, 100, 50)] ];
    XCTAssertEqual([_appDelegate.canvasView addRedactionsInImageRects:rects actionName:@"Redact"], (NSUInteger)1);
    [self renderPDF:[self printWithOptions:[self actualSize]]];
    XCTAssertEqual([self countInFilesWithPrefix:@"page" blue:NULL other:NULL files:NULL], (NSUInteger)0, @"on the page");
    NSUInteger images = 0;
    XCTAssertEqual([self countInFilesWithPrefix:@"image" blue:NULL other:NULL files:&images], (NSUInteger)0, @"anywhere in the file");
    XCTAssertGreaterThan(images, (NSUInteger)0);
}

/// Print Selection, by the real path: the selection's solid blue, and nothing from outside it, on the
/// page or in the file.
- (void)testAPrintedSelectionHoldsOnlyTheSelection {
    if (![self canPrint]) {
        return;
    }
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    canvas.hasSelectionRect = YES;
    canvas.selectionRect = NSMakeRect(200, 100, 100, 60);
    STPrintOptions *options = [self actualSize];
    options.selectionOnly = YES;
    [self renderPDF:[self printWithOptions:options]];
    NSUInteger blue = 0, other = 0, images = 0;
    XCTAssertEqual([self countInFilesWithPrefix:@"page" blue:&blue other:&other files:NULL], (NSUInteger)0);
    // 100 × 60 pixels at 96 per inch, 288 dpi: 300 × 180.
    XCTAssertEqualWithAccuracy((double)blue, 300.0 * 180.0, 3000.0, @"The selection, at its real size");
    XCTAssertLessThan(other, (NSUInteger)3000, @"Only edge pixels are anything but blue or white");
    XCTAssertEqual([self countInFilesWithPrefix:@"image" blue:NULL other:NULL files:&images], (NSUInteger)0);
    XCTAssertGreaterThan(images, (NSUInteger)0);
}

/// Print needs an image, and Print Selection a selection.
- (void)testThePrintCommandsFollowTheImageAndSelection {
    if (_shouldSkip) {
        return;
    }
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSMenuItem *print = [[NSMenuItem alloc] initWithTitle:@"Print\u2026" action:@selector(printDocument:) keyEquivalent:@"p"];
    NSMenuItem *selection = [[NSMenuItem alloc] initWithTitle:@"Print Selection\u2026" action:@selector(printSelection:) keyEquivalent:@""];
    XCTAssertTrue([_appDelegate validateMenuItem:print]);
    XCTAssertFalse([_appDelegate validateMenuItem:selection]);
    canvas.hasSelectionRect = YES;
    canvas.selectionRect = NSMakeRect(10, 10, 50, 50);
    XCTAssertTrue([_appDelegate validateMenuItem:selection]);
    canvas.hasSelectionRect = NO;
    [canvas loadImage:nil];
    XCTAssertFalse([_appDelegate validateMenuItem:print]);
}

/// The main menu has Print with its shortcut, so Ctrl+P reaches it.
- (void)testTheFileMenuHasPrint {
    if (_shouldSkip) {
        return;
    }
    [_appDelegate setupMenus];
    NSMenuItem *found = nil;
    for (NSMenuItem *top in [NSApp mainMenu].itemArray) {
        for (NSMenuItem *item in top.submenu.itemArray) {
            if (item.action == @selector(printDocument:)) {
                found = item;
            }
        }
    }
    XCTAssertNotNil(found);
    XCTAssertEqualObjects(found.keyEquivalent, @"p");
}

@end

#endif
