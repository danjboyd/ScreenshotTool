/*
 * ToolbarBadgeRefreshProbe.m
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
#import "AppDelegate.h"

@interface AppDelegate (ToolbarBadgeAccess)
- (NSImage *)imageByAddingColorBadgeToImage:(NSImage *)image color:(NSColor *)color;
@end

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    exit(EXIT_FAILURE);
}

static NSImage *STCreateBaseIcon(NSSize size, NSColor *fillColor) {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[fillColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: fillColor ?: [NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0f, 0.0f, size.width, size.height));
    [image unlockFocus];
    return image;
}

static NSColor *STSampleBadgeColor(NSImage *image, NSColor *expected) {
    if (!image) {
        FailAndExit(@"Toolbar badge probe: nil image supplied");
    }
    NSData *data = [image TIFFRepresentation];
    if (!data) {
        FailAndExit(@"Toolbar badge probe: unable to obtain TIFF");
    }
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:data];
    if (!bitmap) {
        FailAndExit(@"Toolbar badge probe: bitmap rep creation failed");
    }

    NSColorSpace *space = [NSColorSpace deviceRGBColorSpace];
    NSColor *expectedDevice = [expected colorUsingColorSpace:space] ?: expected;

    CGFloat bestDistance = CGFLOAT_MAX;
    NSColor *best = nil;
    NSInteger width = bitmap.pixelsWide;
    NSInteger height = bitmap.pixelsHigh;
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            NSColor *pixel = [bitmap colorAtX:x y:y];
            if (!pixel) {
                continue;
            }
            NSColor *devicePixel = [pixel colorUsingColorSpace:space] ?: pixel;
            CGFloat deltaR = devicePixel.redComponent - expectedDevice.redComponent;
            CGFloat deltaG = devicePixel.greenComponent - expectedDevice.greenComponent;
            CGFloat deltaB = devicePixel.blueComponent - expectedDevice.blueComponent;
            CGFloat distance = (deltaR * deltaR) + (deltaG * deltaG) + (deltaB * deltaB);
            if (distance < bestDistance) {
                bestDistance = distance;
                best = devicePixel;
            }
        }
    }

    if (!best) {
        FailAndExit(@"Toolbar badge probe: badge pixels not detected");
    }
    return best;
}

static void STAssertColorMatches(NSColor *actual, NSColor *expected, NSString *context) {
    if (!actual || !expected) {
        FailAndExit([NSString stringWithFormat:@"Toolbar badge probe: nil colour encountered (%@)", context]);
    }
    NSColorSpace *space = [NSColorSpace deviceRGBColorSpace];
    NSColor *actualDevice = [actual colorUsingColorSpace:space] ?: actual;
    NSColor *expectedDevice = [expected colorUsingColorSpace:space] ?: expected;

    CGFloat tolerance = 0.05f;
    CGFloat deltaR = fabs(actualDevice.redComponent - expectedDevice.redComponent);
    CGFloat deltaG = fabs(actualDevice.greenComponent - expectedDevice.greenComponent);
    CGFloat deltaB = fabs(actualDevice.blueComponent - expectedDevice.blueComponent);
    if (deltaR > tolerance || deltaG > tolerance || deltaB > tolerance) {
        NSString *message = [NSString stringWithFormat:@"Toolbar badge probe: colour mismatch (%@). Expected (%.3f, %.3f, %.3f) got (%.3f, %.3f, %.3f)",
                                                       context,
                                                       expectedDevice.redComponent,
                                                       expectedDevice.greenComponent,
                                                       expectedDevice.blueComponent,
                                                       actualDevice.redComponent,
                                                       actualDevice.greenComponent,
                                                       actualDevice.blueComponent];
        FailAndExit(message);
    }
}

static void STAssertImageRemainsNeutral(NSImage *image, NSString *context) {
    NSData *data = [image TIFFRepresentation];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:data];
    if (!bitmap) {
        FailAndExit([NSString stringWithFormat:@"Toolbar badge probe: neutral check failed (%@)", context]);
    }
    NSInteger width = bitmap.pixelsWide;
    NSInteger height = bitmap.pixelsHigh;
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            NSColor *pixel = [bitmap colorAtX:x y:y];
            if (!pixel) {
                continue;
            }
            NSColor *devicePixel = [pixel colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: pixel;
            if (devicePixel.redComponent < 0.98f || devicePixel.greenComponent < 0.98f || devicePixel.blueComponent < 0.98f) {
                FailAndExit([NSString stringWithFormat:@"Toolbar badge probe: base image mutated (%@)", context]);
            }
        }
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = nil;
        @try {
            application = [NSApplication sharedApplication];
        } @catch (NSException *exception) {
            fprintf(stderr, "ToolbarBadgeRefreshProbe: SKIP (failed to connect to window server: %s)\n",
                    [[exception reason] UTF8String]);
            return EXIT_SUCCESS;
        }
        if (!application) {
            fprintf(stderr, "ToolbarBadgeRefreshProbe: SKIP (NSApplication sharedApplication returned nil)\n");
            return EXIT_SUCCESS;
        }

        AppDelegate *delegate = [[AppDelegate alloc] init];

        NSSize iconSize = NSMakeSize(32.0f, 32.0f);
        NSImage *baseIcon = STCreateBaseIcon(iconSize, [NSColor whiteColor]);
        if (!baseIcon) {
            FailAndExit(@"Toolbar badge probe: failed to create base icon");
        }

        NSColor *firstColor = [NSColor colorWithCalibratedRed:0.92f green:0.18f blue:0.24f alpha:1.0f];
        NSColor *secondColor = [NSColor colorWithCalibratedRed:0.18f green:0.56f blue:0.85f alpha:1.0f];

        NSImage *firstBadge = [delegate imageByAddingColorBadgeToImage:[baseIcon copy]
                                                                  color:firstColor];
        if (!firstBadge) {
            FailAndExit(@"Toolbar badge probe: failed to render first badge");
        }
        STAssertColorMatches(STSampleBadgeColor(firstBadge, firstColor), firstColor, @"initial badge");

        STAssertImageRemainsNeutral(baseIcon, @"after first badge");

        NSImage *secondBadge = [delegate imageByAddingColorBadgeToImage:[baseIcon copy]
                                                                   color:secondColor];
        if (!secondBadge) {
            FailAndExit(@"Toolbar badge probe: failed to render second badge");
        }
        STAssertColorMatches(STSampleBadgeColor(secondBadge, secondColor), secondColor, @"refreshed badge");
        STAssertColorMatches(STSampleBadgeColor(firstBadge, firstColor), firstColor, @"first badge preserved");
        STAssertImageRemainsNeutral(baseIcon, @"after second badge");
    }
    return EXIT_SUCCESS;
}
