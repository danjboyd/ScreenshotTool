/*
 * CropClipsAnnotationsProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "TestEnvironmentHelpers.h"

@interface ScreenshotCanvasView (CropClipsAnnotationsProbe)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
@end

@interface CropClipsAnnotationsProbeTests : XCTestCase {
    BOOL _shouldSkip;
}
@end

@implementation CropClipsAnnotationsProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

#pragma mark - Helpers

- (NSImage *)whiteImageOfSize:(NSSize)size {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    [image unlockFocus];
    return image;
}

- (MarkupStroke *)penStrokeFrom:(NSPoint)start to:(NSPoint)end {
    MarkupStroke *stroke = [[MarkupStroke alloc] initWithType:MarkupStrokeTypePen
                                                        color:[NSColor redColor]
                                                     lineWidth:6.0f];
    [stroke addPoint:start];
    [stroke addPoint:end];
    return stroke;
}

- (NSInteger)redPixelCountInImage:(NSImage *)image rows:(NSRange)rows {
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
    XCTAssertNotNil(bitmap, @"Failed to read flattened image");
    NSInteger count = 0;
    NSInteger lastRow = MIN((NSInteger)NSMaxRange(rows), bitmap.pixelsHigh);
    for (NSInteger y = (NSInteger)rows.location; y < lastRow; y++) {
        for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
            NSColor *pixel = [[bitmap colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
            if (pixel && pixel.redComponent > 0.8f && pixel.greenComponent < 0.3f) {
                count++;
            }
        }
    }
    return count;
}

#pragma mark - Tests

- (void)testCropDropsStrokesOutsideSelection {
    XCTSkipIf(_shouldSkip, @"No window server");

    ScreenshotCanvasView *canvas = [[ScreenshotCanvasView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 200.0)];
    [canvas loadImage:[self whiteImageOfSize:NSMakeSize(200.0, 200.0)]];
    if (!canvas.strokes) {
        canvas.strokes = [[NSMutableArray alloc] init];
    }

    // Canvas coordinates are flipped: the selection covers the top half, y 0..100.
    MarkupStroke *inside = [self penStrokeFrom:NSMakePoint(20.0, 40.0) to:NSMakePoint(180.0, 40.0)];
    MarkupStroke *outside = [self penStrokeFrom:NSMakePoint(20.0, 180.0) to:NSMakePoint(180.0, 180.0)];
    MarkupStroke *crossing = [self penStrokeFrom:NSMakePoint(100.0, 60.0) to:NSMakePoint(100.0, 190.0)];
    [canvas.strokes addObjectsFromArray:@[inside, outside, crossing]];

    canvas.hasSelectionRect = YES;
    canvas.selectionRect = NSMakeRect(0.0, 0.0, 200.0, 100.0);
    XCTAssertTrue([canvas cropToActiveSelection], @"Crop should succeed");

    XCTAssertEqual(canvas.strokes.count, (NSUInteger)2, @"The stroke entirely outside the crop should be dropped");
    XCTAssertFalse([canvas.strokes containsObject:outside], @"The outside stroke should not survive the crop");

    NSPoint crossingEnd = [[[crossing points] lastObject] pointValue];
    XCTAssertEqualWithAccuracy(crossingEnd.y, 190.0, 0.01, @"A crossing stroke should be translated, not clamped to the edge");

    NSImage *flattened = [canvas flattenedImage];
    XCTAssertEqualWithAccuracy(flattened.size.height, 100.0, 0.5, @"Cropped image should be 100pt tall");

    // Bitmap rows run top-down. The outside stroke used to collapse onto the bottom edge as a
    // full-width red band; only the 6px crossing stroke may reach it now.
    NSInteger bottomRed = [self redPixelCountInImage:flattened rows:NSMakeRange(96, 4)];
    XCTAssertTrue(bottomRed < 4 * 20, @"Bottom edge should not carry a band from strokes outside the crop (found %ld red pixels)", (long)bottomRed);
    NSInteger insideRed = [self redPixelCountInImage:flattened rows:NSMakeRange(37, 6)];
    XCTAssertTrue(insideRed > 100, @"The stroke inside the crop should still render");
}

@end
