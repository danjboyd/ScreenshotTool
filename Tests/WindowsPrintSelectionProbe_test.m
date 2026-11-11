/*
 * WindowsPrintSelectionProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Windows Print Selection fails closed (#355): a selection with nothing of the image in it prints
 * nothing, rather than the whole image. STWindowsPrintFlattened with a sheet given by value and
 * recording blocks in place of the canvas and the printer, so no canvas, window, device context or
 * print job is made: the "pages" block stands for STWindowsPrintPages, which is what calls StartDoc.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if defined(_WIN32)

#import "STPrintLayout.h"
#import "STPrintOptions.h"
#import "STWindowsPrint.h"

@interface WindowsPrintSelectionProbeTests : XCTestCase
@property (nonatomic, strong) NSImage *image;
@property (nonatomic) NSUInteger flattenCalls;
@property (nonatomic) NSUInteger selectionImageCalls;
@property (nonatomic) NSUInteger printPagesCalls;
@property (nonatomic) NSRect lastClip;
@property (nonatomic) NSRect printedSource;
@end

@implementation WindowsPrintSelectionProbeTests

/// A 200x100 image in memory only: a bitmap representation, never drawn.
- (void)setUp {
    [super setUp];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:200
                                                                    pixelsHigh:100
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:200 * 4
                                                                  bitsPerPixel:32];
    memset(rep.bitmapData, 0x80, 200 * 4 * 100);
    self.image = [[NSImage alloc] initWithSize:NSMakeSize(200, 100)];
    [self.image addRepresentation:rep];
    self.flattenCalls = 0;
    self.selectionImageCalls = 0;
    self.printPagesCalls = 0;
    self.lastClip = NSZeroRect;
    self.printedSource = NSZeroRect;
}

/// A sheet as Microsoft Print to PDF reports Letter: 612x792 pt, 600 dpi, no unprintable edge.
- (STWindowsPrinterSheet)sheet {
    STWindowsPrinterSheet sheet;
    sheet.paper = NSMakeSize(612, 792);
    sheet.printerMargins = STPrintMarginsMake(0, 0, 0, 0);
    sheet.valid = YES;
    sheet.dotsPerInch = 600;
    return sheet;
}

/// Print with recording blocks; the flatten block answers with an image of the clip's size (the
/// whole image for an empty clip, as the canvas does).
- (BOOL)printSelection:(NSRect)selection selectionOnly:(BOOL)selectionOnly failure:(NSString **)failure {
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.selectionOnly = selectionOnly;
    __weak WindowsPrintSelectionProbeTests *weakSelf = self;
    NSImage *image = self.image;
    return STWindowsPrintFlattened(image, selection, options, [self sheet],
        ^NSImage *(NSUInteger scale, NSRect clip) {
            weakSelf.flattenCalls += 1;
            weakSelf.lastClip = clip;
            NSSize size = NSIsEmptyRect(clip) ? image.size : clip.size;
            NSImage *out = [[NSImage alloc] initWithSize:NSMakeSize(size.width * scale, size.height * scale)];
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                            pixelsWide:(NSInteger)(size.width * scale)
                                                                            pixelsHigh:(NSInteger)(size.height * scale)
                                                                         bitsPerSample:8
                                                                       samplesPerPixel:4
                                                                              hasAlpha:YES
                                                                              isPlanar:NO
                                                                        colorSpaceName:NSDeviceRGBColorSpace
                                                                           bytesPerRow:0
                                                                          bitsPerPixel:32];
            [out addRepresentation:rep];
            return out;
        },
        ^NSImage *(void) {
            weakSelf.selectionImageCalls += 1;
            return nil;
        },
        ^BOOL(STPrintLayout *layout, NSImage *printed) {
            weakSelf.printPagesCalls += 1;
            weakSelf.printedSource = layout.sourceRect;
            return YES;
        },
        failure);
}

/// The leak this closes: a selection wholly outside the image used to leave an empty source, which
/// the flatten read as "no clip" and printed the whole image. Now nothing reaches the printer.
- (void)testSelectionOutsideTheImagePrintsNothing {
    NSString *failure = nil;
    BOOL printed = [self printSelection:NSMakeRect(250, 20, 40, 20) selectionOnly:YES failure:&failure];
    XCTAssertFalse(printed);
    XCTAssertEqualObjects(failure, @"There's nothing to print.");
    XCTAssertEqual(self.flattenCalls, 0U, @"nothing is flattened for an empty selection");
    XCTAssertEqual(self.selectionImageCalls, 0U);
    XCTAssertEqual(self.printPagesCalls, 0U, @"no pages, so no StartDoc and no print job");
}

/// Below and left of the image, touching no pixel of it: the same.
- (void)testSelectionBesideTheImagePrintsNothing {
    NSString *failure = nil;
    BOOL printed = [self printSelection:NSMakeRect(-60, -40, 50, 30) selectionOnly:YES failure:&failure];
    XCTAssertFalse(printed);
    XCTAssertEqualObjects(failure, @"There's nothing to print.");
    XCTAssertEqual(self.flattenCalls, 0U);
    XCTAssertEqual(self.printPagesCalls, 0U);
}

/// A selection partly over the image prints only its part inside the image.
- (void)testSelectionPartlyInsidePrintsOnlyThatPart {
    NSString *failure = nil;
    BOOL printed = [self printSelection:NSMakeRect(150, 50, 100, 100) selectionOnly:YES failure:&failure];
    XCTAssertTrue(printed, @"%@", failure);
    XCTAssertEqual(self.flattenCalls, 1U);
    XCTAssertTrue(NSEqualRects(self.lastClip, NSMakeRect(150, 50, 50, 50)), @"clip %@", NSStringFromRect(self.lastClip));
    XCTAssertEqual(self.printPagesCalls, 1U);
    XCTAssertFalse(NSIsEmptyRect(self.printedSource));
}

/// Print (not Print Selection) still prints the whole image, with no clip.
- (void)testWholeImagePrintIsUnchanged {
    NSString *failure = nil;
    BOOL printed = [self printSelection:NSMakeRect(250, 20, 40, 20) selectionOnly:NO failure:&failure];
    XCTAssertTrue(printed, @"%@", failure);
    XCTAssertEqual(self.flattenCalls, 1U);
    XCTAssertTrue(NSIsEmptyRect(self.lastClip), @"no clip for the whole image");
    XCTAssertEqual(self.printPagesCalls, 1U);
}

@end

#endif
