/*
 * ClipboardHighlighterProbe_test.m
 * Copyright (C) 2025 Daniel Boyd
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "TestEnvironmentHelpers.h"

@interface ScreenshotCanvasView (ClipboardProbe)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@end

@interface ClipboardHighlighterProbeTests : XCTestCase {
    BOOL _shouldSkip;
}
@end

@implementation ClipboardHighlighterProbeTests

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

- (NSImage *)createBaseImageOfSize:(NSSize)size {
    XCTAssertTrue(size.width > 0.0 && size.height > 0.0, @"Image size must be positive");
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    [image unlockFocus];
    return image;
}

- (MarkupStroke *)createHighlighterStrokeWithColor:(NSColor *)color width:(CGFloat)width bounds:(NSRect)bounds {
    MarkupStroke *stroke = [[MarkupStroke alloc] initWithType:MarkupStrokeTypeHighlighter
                                                        color:color
                                                     lineWidth:width];
    CGFloat y = NSMidY(bounds);
    CGFloat inset = bounds.size.width * 0.1;
    [stroke addPoint:NSMakePoint(inset, y)];
    [stroke addPoint:NSMakePoint(bounds.size.width - inset, y)];
    return stroke;
}

- (BOOL)imageContainsHighlighterOverlay:(NSImage *)image {
    XCTAssertNotNil(image, @"Image cannot be nil");
    NSData *tiff = [image TIFFRepresentation];
    XCTAssertNotNil(tiff, @"Failed to get TIFF representation");
    
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiff];
    XCTAssertNotNil(bitmap, @"Failed to create bitmap from data");

    NSInteger width = bitmap.pixelsWide;
    NSInteger height = bitmap.pixelsHigh;
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            NSColor *pixel = [bitmap colorAtX:x y:y];
            if (!pixel) continue;
            
            NSColor *device = [pixel colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: pixel;
            // Highlighter overlay (semi-transparent yellow) significantly reduces the blue channel.
            if (device.blueComponent < 0.95f) {
                return YES;
            }
        }
    }
    return NO;
}

#pragma mark - Test

- (void)testHighlighterIsVisibleInFlattenedImage {
    if (_shouldSkip) return;

    NSRect frame = NSMakeRect(0.0, 0.0, 640.0, 480.0);
    ScreenshotCanvasView *canvas = [[ScreenshotCanvasView alloc] initWithFrame:frame];
    XCTAssertNotNil(canvas, @"Failed to allocate canvas view");

    NSImage *baseImage = [self createBaseImageOfSize:frame.size];
    XCTAssertNotNil(baseImage, @"Failed to construct base image");
    [canvas loadImage:baseImage];

    NSColor *highlighter = [NSColor colorWithCalibratedRed:0.99f green:0.94f blue:0.30f alpha:1.0f];
    MarkupStroke *stroke = [self createHighlighterStrokeWithColor:highlighter width:32.0f bounds:frame];
    XCTAssertNotNil(stroke, @"Failed to construct highlighter stroke");

    if (!canvas.strokes) {
        canvas.strokes = [[NSMutableArray alloc] init];
    }
    [canvas.strokes addObject:stroke];

    NSImage *flattened = [canvas flattenedImageForSelection];
    XCTAssertNotNil(flattened, @"Canvas failed to flatten image");

    XCTAssertTrue([self imageContainsHighlighterOverlay:flattened], @"Highlighter overlay missing from flattened image");
}

@end
