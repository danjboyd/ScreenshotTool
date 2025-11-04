/*
 * ToolbarBadgeProbe.m
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
#import <math.h>
#import "AppDelegate.h"

#import <float.h>

@interface AppDelegate (ToolbarBadgeTesting)
- (NSImage *)imageByAddingColorBadgeToImage:(NSImage *)image color:(NSColor *)color;
@end

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    exit(EXIT_FAILURE);
}

static NSColor *FindClosestBadgeColor(NSBitmapImageRep *bitmap, NSColor *expected, CGFloat *outDistance) {
    if (!bitmap || !expected) {
        return nil;
    }

    NSColor *expectedDevice = [expected colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: expected;
    double bestDistance = DBL_MAX;
    NSColor *bestColor = nil;

    NSInteger width = bitmap.pixelsWide;
    NSInteger height = bitmap.pixelsHigh;
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            NSColor *pixel = [bitmap colorAtX:x y:y];
            if (!pixel) {
                continue;
            }
            NSColor *pixelDevice = [pixel colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: pixel;
            double deltaR = pixelDevice.redComponent - expectedDevice.redComponent;
            double deltaG = pixelDevice.greenComponent - expectedDevice.greenComponent;
            double deltaB = pixelDevice.blueComponent - expectedDevice.blueComponent;
            double deltaA = pixelDevice.alphaComponent - expectedDevice.alphaComponent;
            double distance = (deltaR * deltaR) + (deltaG * deltaG) + (deltaB * deltaB) + (deltaA * deltaA);
            if (distance < bestDistance) {
                bestDistance = distance;
                bestColor = pixelDevice;
            }
        }
    }

    if (outDistance) {
        *outDistance = (CGFloat)sqrt(bestDistance);
    }
    return bestColor;
}

static NSColor *SampleBadgeColor(NSImage *image, NSColor *expected) {
    if (!image) {
        FailAndExit(@"SampleBadgeColor invoked with nil image");
    }
    NSData *tiff = [image TIFFRepresentation];
    if (!tiff) {
        FailAndExit(@"Unable to generate TIFF representation for toolbar image");
    }
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiff];
    if (!bitmap) {
        FailAndExit(@"Failed to create NSBitmapImageRep from toolbar image");
    }

    NSInteger width = bitmap.pixelsWide;
    NSInteger height = bitmap.pixelsHigh;
    if (width <= 0 || height <= 0) {
        FailAndExit([NSString stringWithFormat:@"Bitmap dimensions invalid (%ld x %ld)", (long)width, (long)height]);
    }

    CGFloat distance = 0.0f;
    NSColor *color = FindClosestBadgeColor(bitmap, expected, &distance);
    if (!color) {
        FailAndExit(@"Failed to locate badge pixel in bitmap");
    }
    if (distance > 0.20f) {
        NSString *message = [NSString stringWithFormat:@"Closest badge pixel distance too large: %.3f", distance];
        FailAndExit(message);
    }
    return color;
}

static void AssertColorMatches(NSColor *actual, NSColor *expected, NSString *context) {
    if (!actual || !expected) {
        FailAndExit([NSString stringWithFormat:@"Nil color encountered while validating toolbar badge (%@)", context]);
    }

    NSColor *actualDevice = [actual colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: actual;
    NSColor *expectedDevice = [expected colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: expected;

    CGFloat tolerance = 0.02f;
    CGFloat deltaR = fabs(actualDevice.redComponent - expectedDevice.redComponent);
    CGFloat deltaG = fabs(actualDevice.greenComponent - expectedDevice.greenComponent);
    CGFloat deltaB = fabs(actualDevice.blueComponent - expectedDevice.blueComponent);
    CGFloat deltaA = fabs(actualDevice.alphaComponent - expectedDevice.alphaComponent);

    if (deltaR > tolerance || deltaG > tolerance || deltaB > tolerance || deltaA > tolerance) {
        NSString *message = [NSString stringWithFormat:@"Toolbar badge color mismatch (%@): "
                                                       "expected (%.3f, %.3f, %.3f, %.3f) got (%.3f, %.3f, %.3f, %.3f)",
                                                       context,
                                                       expectedDevice.redComponent,
                                                       expectedDevice.greenComponent,
                                                       expectedDevice.blueComponent,
                                                       expectedDevice.alphaComponent,
                                                       actualDevice.redComponent,
                                                       actualDevice.greenComponent,
                                                       actualDevice.blueComponent,
                                                       actualDevice.alphaComponent];
        FailAndExit(message);
    }
}

static NSImage *CreateBaseIcon(NSSize size, NSColor *fillColor) {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    NSColor *fill = fillColor ?: [NSColor whiteColor];
    [fill setFill];
    NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    [image unlockFocus];
    return image;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = nil;
        @try {
            application = [NSApplication sharedApplication];
        } @catch (NSException *exception) {
            fprintf(stderr, "ToolbarBadgeProbe: SKIP (failed to connect to window server: %s)\n",
                    [[exception reason] UTF8String]);
            return EXIT_SUCCESS;
        }
        if (!application) {
            fprintf(stderr, "ToolbarBadgeProbe: SKIP (NSApplication sharedApplication returned nil)\n");
            return EXIT_SUCCESS;
        }

        AppDelegate *delegate = [[AppDelegate alloc] init];

        NSSize iconSize = NSMakeSize(32.0f, 32.0f);
        NSImage *baseIcon = CreateBaseIcon(iconSize, [NSColor colorWithCalibratedWhite:0.95 alpha:1.0]);
        if (!baseIcon) {
            FailAndExit(@"Failed to construct base toolbar icon");
        }

        NSArray<NSColor *> *testColors = @[
            [NSColor colorWithCalibratedRed:0.95f green:0.13f blue:0.21f alpha:1.0f],
            [NSColor colorWithCalibratedRed:0.04f green:0.47f blue:0.91f alpha:1.0f],
            [NSColor colorWithCalibratedRed:0.11f green:0.76f blue:0.47f alpha:1.0f],
            [NSColor colorWithCalibratedRed:0.87f green:0.63f blue:0.17f alpha:1.0f]
        ];

        NSUInteger index = 0;
        for (NSColor *testColor in testColors) {
            NSImage *badged = [delegate imageByAddingColorBadgeToImage:baseIcon color:testColor];
            if (!badged) {
                FailAndExit([NSString stringWithFormat:@"imageByAddingColorBadgeToImage returned nil for sample %lu",
                                                        (unsigned long)index]);
            }
            NSColor *sampled = SampleBadgeColor(badged, testColor);
            NSString *context = [NSString stringWithFormat:@"sample %lu", (unsigned long)index];
            AssertColorMatches(sampled, testColor, context);
            index++;
        }
    }
    return EXIT_SUCCESS;
}
