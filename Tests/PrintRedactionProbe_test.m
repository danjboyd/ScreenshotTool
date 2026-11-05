/*
 * PrintRedactionProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Printing never bypasses a redaction (#355). What goes in the PDF is the flattened image, so the
 * pixels under a redaction aren't in the file at all, drawn or not; and a selection's PDF holds only
 * the selection, since a clip would leave the rest of the image in the file. Reads the PDF's embedded
 * images back with pdfimages, as well as rendering its pages.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if defined(__linux__)

#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "STPrintLayout.h"
#import "STPrintOptions.h"
#import "STPrintPDF.h"
#import "STPrintPanelController.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (PrintRedactionProbe)
- (void)setupWindowAndContent;
- (ScreenshotCanvasView *)canvasView;
@end

@interface ScreenshotCanvasView (PrintRedactionProbe)
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
@end

@interface PrintRedactionProbeAppDelegate : AppDelegate
@end
@implementation PrintRedactionProbeAppDelegate
@end

/// What's being hidden is a checkerboard with this colour, which is nowhere else in the image. A
/// redaction is a mosaic of cell averages, so a solid block would keep its colour; a checkerboard's
/// colour survives only if the original pixels do.
static const unsigned char STSecret[3] = { 255, 0, 255 };
static const unsigned char STSecretOther[3] = { 0, 255, 0 };

@interface PrintRedactionProbeTests : XCTestCase
@end

@implementation PrintRedactionProbeTests {
    PrintRedactionProbeAppDelegate *_appDelegate;
    BOOL _shouldSkip;
    NSString *_directory;
}

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
    _appDelegate = [[PrintRedactionProbeAppDelegate alloc] init];
    @try {
        [_appDelegate setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
        return;
    }
    _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    [_appDelegate.canvasView loadImage:[self imageWithSecret]];
}

- (void)tearDown {
    if (_directory) {
        [[NSFileManager defaultManager] removeItemAtPath:_directory error:NULL];
    }
    [super tearDown];
}

/// 400 × 200, white but for the secret's 100 × 50 at (50, 40) from the top left, and a solid blue
/// 100 × 60 at (200, 100) to select.
- (NSImage *)imageWithSecret {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:400
                                                                    pixelsHigh:200
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    unsigned char *data = rep.bitmapData;
    static const unsigned char white[3] = { 255, 255, 255 };
    static const unsigned char blue[3] = { 0, 0, 255 };
    for (NSInteger y = 0; y < 200; y++) {
        for (NSInteger x = 0; x < 400; x++) {
            const unsigned char *color = white;
            if (x >= 50 && x < 150 && y >= 40 && y < 90) {
                color = (x + y) % 2 == 0 ? STSecret : STSecretOther;
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

- (NSString *)writePDFOfImage:(NSImage *)image {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.paperSize = NSMakeSize(612, 792);
    layout.margins = STPrintMarginsMake(36, 36, 36, 36);
    STConfigurePrintLayout(layout, [[STPrintOptions alloc] init], image, NSZeroRect);
    NSString *pdf = [_directory stringByAppendingPathComponent:@"print.pdf"];
    XCTAssertTrue(STWritePrintPDF(layout, image, pdf));
    return pdf;
}

- (void)run:(NSString *)tool arguments:(NSArray<NSString *> *)arguments {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/env";
    task.arguments = [@[ tool ] arrayByAddingObjectsFromArray:arguments];
    [task launch];
    [task waitUntilExit];
    XCTAssertEqual(task.terminationStatus, 0, @"%@ failed; is poppler-utils installed?", tool);
}

/// How many pixels are the secret's colour in the PPMs named `prefix`-*, and each one's size.
- (NSUInteger)secretPixelsInFilesWithPrefix:(NSString *)prefix sizes:(NSMutableArray<NSString *> *)sizes {
    NSUInteger count = 0;
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_directory error:NULL];
    NSUInteger files = 0;
    for (NSString *name in names) {
        if (![name hasPrefix:prefix] || ![name.pathExtension isEqualToString:@"ppm"]) {
            continue;
        }
        files++;
        NSData *ppm = [NSData dataWithContentsOfFile:[_directory stringByAppendingPathComponent:name]];
        int width = 0, height = 0, maximum = 0, length = 0;
        NSData *head = [ppm subdataWithRange:NSMakeRange(0, MIN(ppm.length, (NSUInteger)64))];
        NSString *header = [[NSString alloc] initWithData:head encoding:NSISOLatin1StringEncoding];
        XCTAssertEqual(sscanf(header.UTF8String, "P6 %d %d %d%n", &width, &height, &maximum, &length), 3, @"%@", name);
        [sizes addObject:[NSString stringWithFormat:@"%dx%d", width, height]];
        const unsigned char *pixels = (const unsigned char *)ppm.bytes + length + 1;
        for (NSInteger i = 0; i < (NSInteger)width * height; i++) {
            const unsigned char *p = pixels + i * 3;
            // Close, not exact, so scaling or a colour conversion can't hide it from this check.
            if (p[0] > 200 && p[1] < 80 && p[2] > 200) {
                count++;
            }
        }
    }
    XCTAssertGreaterThan(files, (NSUInteger)0, @"no %@ files", prefix);
    return count;
}

/// The secret's pixels as printed on the pages, and as embedded in the file.
- (void)countSecretInPDF:(NSString *)pdf rendered:(NSUInteger *)rendered embedded:(NSUInteger *)embedded
           embeddedSizes:(NSMutableArray<NSString *> *)sizes {
    [self run:@"pdftoppm" arguments:@[ @"-r", @"288", pdf, [_directory stringByAppendingPathComponent:@"page"] ]];
    [self run:@"pdfimages" arguments:@[ pdf, [_directory stringByAppendingPathComponent:@"image"] ]];
    *rendered = [self secretPixelsInFilesWithPrefix:@"page" sizes:[NSMutableArray array]];
    *embedded = [self secretPixelsInFilesWithPrefix:@"image" sizes:sizes];
}

/// Shows the checks can see the secret, so that the others' zeroes mean something.
- (void)testWithoutARedactionTheSecretIsFound {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSUInteger rendered = 0, embedded = 0;
    [self countSecretInPDF:[self writePDFOfImage:[_appDelegate.canvasView flattenedImage]]
                  rendered:&rendered
                  embedded:&embedded
             embeddedSizes:[NSMutableArray array]];
    XCTAssertGreaterThan(rendered, (NSUInteger)100);
    XCTAssertEqual(embedded, (NSUInteger)2500);
}

- (void)testARedactedImagePrintsWithoutWhatItHides {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    NSArray *rects = @[ [NSValue valueWithRect:NSMakeRect(50, 40, 100, 50)] ];
    XCTAssertEqual([canvas addRedactionsInImageRects:rects actionName:@"Redact"], (NSUInteger)1);
    NSUInteger rendered = 0, embedded = 0;
    [self countSecretInPDF:[self writePDFOfImage:[canvas flattenedImage]]
                  rendered:&rendered
                  embedded:&embedded
             embeddedSizes:[NSMutableArray array]];
    XCTAssertEqual(rendered, (NSUInteger)0, @"on the page");
    XCTAssertEqual(embedded, (NSUInteger)0, @"anywhere in the file");
}

/// What Print Selection sends: the part that's outside isn't in the file.
- (void)testASelectionsPDFHoldsOnlyTheSelection {
    XCTSkipIf(_shouldSkip, @"No window server");
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    canvas.hasSelectionRect = YES;
    canvas.selectionRect = NSMakeRect(200, 100, 100, 60);
    XCTAssertTrue(canvas.hasSelection);
    NSImage *selected = [canvas flattenedImageForSelection];
    NSUInteger rendered = 0, embedded = 0;
    NSMutableArray<NSString *> *sizes = [NSMutableArray array];
    [self countSecretInPDF:[self writePDFOfImage:selected] rendered:&rendered embedded:&embedded embeddedSizes:sizes];
    XCTAssertEqual(embedded, (NSUInteger)0, @"the secret is outside the selection");
    XCTAssertEqualObjects(sizes, @[ @"100x60" ]);
}

/// Nothing can act on a saved "annotations off", from a build that had the option or by hand.
- (void)testThereIsNoOptionToLeaveAnnotationsOut {
    XCTSkipIf(_shouldSkip, @"No window server");
    STPrintOptions *options = [[STPrintOptions alloc] init];
    XCTAssertFalse([options respondsToSelector:NSSelectorFromString(@"includeAnnotations")]);
    XCTAssertFalse([options respondsToSelector:NSSelectorFromString(@"setIncludeAnnotations:")]);
}

@end

#endif
