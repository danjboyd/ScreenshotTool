/*
 * ClipboardHighlighterOpacityProbe.m
 * Copyright (C) 2025 Daniel Boyd
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA.
 */

#import <AppKit/AppKit.h>
#import <stdlib.h>
#import <string.h>
#import <limits.h>
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    exit(EXIT_FAILURE);
}

static void STConfigureDefaultsRoot(void) __attribute__((constructor));

static void STConfigureDefaultsRoot(void) {
    char templatePath[] = "/tmp/ScreenshotToolDefaultsXXXXXX";
    char *defaultsDir = mkdtemp(templatePath);
    if (defaultsDir) {
        setenv("GNUSTEP_DEFAULTS_ROOT", defaultsDir, 1);
        char defaultsFile[PATH_MAX];
        snprintf(defaultsFile, sizeof(defaultsFile), "%s/GNUstepDefaults.plist", defaultsDir);
        setenv("GNUSTEP_USER_DEFAULTS", defaultsFile, 1);
    }
}

@interface ScreenshotCanvasView (ClipboardOpacityProbe)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@end

static NSImage *STCreateBaseImage(NSSize size, NSColor *fillColor) {
    if (size.width <= 0.0 || size.height <= 0.0) {
        return nil;
    }
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[fillColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: fillColor ?: [NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    [image unlockFocus];
    return image;
}

static MarkupStroke *STCreateHighlighterStroke(NSColor *color, CGFloat width, NSRect bounds) {
    MarkupStroke *stroke = [[MarkupStroke alloc] initWithType:MarkupStrokeTypeHighlighter
                                                        color:color
                                                     lineWidth:width];
    CGFloat y = NSMidY(bounds);
    CGFloat inset = bounds.size.width * 0.1;
    [stroke addPoint:NSMakePoint(inset, y)];
    [stroke addPoint:NSMakePoint(bounds.size.width - inset, y)];
    return stroke;
}

static NSColor *STSamplePixel(NSImage *image, NSPoint point) {
    if (!image) {
        return nil;
    }
    NSData *tiff = [image TIFFRepresentation];
    if (!tiff) {
        return nil;
    }
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiff];
    if (!bitmap) {
        return nil;
    }

    NSInteger x = (NSInteger)lrint(point.x);
    NSInteger y = (NSInteger)lrint(point.y);

    if (x < 0 || y < 0 || x >= bitmap.pixelsWide || y >= bitmap.pixelsHigh) {
        return nil;
    }
    return [bitmap colorAtX:x y:y];
}

static NSColor *STCompositeExpectedColor(NSColor *base,
                                         NSColor *overlay,
                                         CGFloat overlayAlpha,
                                         NSUInteger passCount) {
    if (!base || !overlay || passCount == 0) {
        return base;
    }

    NSColorSpace *deviceSpace = [NSColorSpace deviceRGBColorSpace];
    NSColor *baseDevice = [base colorUsingColorSpace:deviceSpace] ?: base;
    NSColor *overlayDevice = [overlay colorUsingColorSpace:deviceSpace] ?: overlay;

    double remainFactor = pow(1.0 - overlayAlpha, (double)passCount);
    double blendFactor = 1.0 - remainFactor;

    double expectedR = baseDevice.redComponent * remainFactor + overlayDevice.redComponent * blendFactor;
    double expectedG = baseDevice.greenComponent * remainFactor + overlayDevice.greenComponent * blendFactor;
    double expectedB = baseDevice.blueComponent * remainFactor + overlayDevice.blueComponent * blendFactor;

    return [NSColor colorWithDeviceRed:(CGFloat)expectedR
                                 green:(CGFloat)expectedG
                                  blue:(CGFloat)expectedB
                                 alpha:1.0f];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = nil;
        @try {
            application = [NSApplication sharedApplication];
        } @catch (NSException *exception) {
            fprintf(stderr, "ClipboardHighlighterOpacityProbe: SKIP (failed to connect to window server: %s)\n",
                    [[exception reason] UTF8String]);
            return EXIT_SUCCESS;
        }
        if (!application) {
            fprintf(stderr, "ClipboardHighlighterOpacityProbe: SKIP (NSApplication sharedApplication returned nil)\n");
            return EXIT_SUCCESS;
        }

        NSRect frame = NSMakeRect(0.0, 0.0, 640.0, 480.0);
        ScreenshotCanvasView *canvas = [[ScreenshotCanvasView alloc] initWithFrame:frame];
        if (!canvas) {
            FailAndExit(@"ClipboardHighlighterOpacityProbe: failed to allocate canvas view");
        }

        NSColor *baseColor = [NSColor colorWithCalibratedRed:0.25f
                                                      green:0.25f
                                                       blue:0.25f
                                                      alpha:1.0f];
        NSImage *baseImage = STCreateBaseImage(frame.size, baseColor);
        if (!baseImage) {
            FailAndExit(@"ClipboardHighlighterOpacityProbe: failed to construct base image");
        }
        [canvas loadImage:baseImage];

        if (!canvas.strokes) {
            canvas.strokes = [[NSMutableArray alloc] init];
        }

        NSColor *highlighter = [NSColor colorWithCalibratedRed:0.99f
                                                        green:0.94f
                                                         blue:0.30f
                                                        alpha:1.0f];

        const NSUInteger passCount = 5;
        for (NSUInteger pass = 0; pass < passCount; ++pass) {
            MarkupStroke *stroke = STCreateHighlighterStroke(highlighter, 32.0f, frame);
            if (!stroke) {
                FailAndExit(@"ClipboardHighlighterOpacityProbe: failed to construct highlighter stroke");
            }
            [canvas.strokes addObject:stroke];
        }

        NSImage *flattened = [canvas flattenedImageForSelection];
        if (!flattened) {
            FailAndExit(@"ClipboardHighlighterOpacityProbe: canvas failed to flatten image");
        }

        NSPoint samplePoint = NSMakePoint(NSMidX(frame), NSMidY(frame));
        NSColor *sampled = STSamplePixel(flattened, samplePoint);
        if (!sampled) {
            FailAndExit(@"ClipboardHighlighterOpacityProbe: failed to sample flattened output");
        }

        CGFloat overlayAlpha = 0.35f;
        NSColor *expected = STCompositeExpectedColor(baseColor, highlighter, overlayAlpha, passCount);
        if (!expected) {
            FailAndExit(@"ClipboardHighlighterOpacityProbe: failed to compute expected colour");
        }

        NSColorSpace *deviceSpace = [NSColorSpace deviceRGBColorSpace];
        NSColor *sampledDevice = [sampled colorUsingColorSpace:deviceSpace] ?: sampled;
        NSColor *expectedDevice = [expected colorUsingColorSpace:deviceSpace] ?: expected;

        CGFloat tolerance = 0.05f;
        CGFloat deltaR = fabs(sampledDevice.redComponent - expectedDevice.redComponent);
        CGFloat deltaG = fabs(sampledDevice.greenComponent - expectedDevice.greenComponent);
        CGFloat deltaB = fabs(sampledDevice.blueComponent - expectedDevice.blueComponent);

        if (deltaR > tolerance || deltaG > tolerance || deltaB > tolerance) {
            NSString *message = [NSString stringWithFormat:@"ClipboardHighlighterOpacityProbe: colour mismatch after %u passes. "
                                                           "Expected (%.3f, %.3f, %.3f) got (%.3f, %.3f, %.3f)",
                                                           (unsigned int)passCount,
                                                           expectedDevice.redComponent,
                                                           expectedDevice.greenComponent,
                                                           expectedDevice.blueComponent,
                                                           sampledDevice.redComponent,
                                                           sampledDevice.greenComponent,
                                                           sampledDevice.blueComponent];
            FailAndExit(message);
        }
    }
    return EXIT_SUCCESS;
}
