/*
 * ToolbarIconThemeProbe.m
 * Regression probe for toolbar icon + label rendering on GNUstep dark themes
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
#import "STThemeUtilities.h"

#if !defined(NSCompositingOperationSourceOver)
#define NSCompositingOperationSourceOver NSCompositeSourceOver
#endif

#if defined(GNUSTEP)
@interface AppDelegate (ToolbarExposure)
@property (nonatomic, assign) BOOL usesDarkTheme;
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
    itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag;
@end

#if defined(GNUSTEP)
static NSBitmapImageRep *RasterizedBitmapForImage(NSImage *image);
#endif

#endif

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    exit(EXIT_FAILURE);
}

static void ConfigureDarkThemeDefaults(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@"Sombre" forKey:@"GSTheme"];
    [defaults synchronize];
}

static NSColor *DeviceColor(NSColor *color) {
    return [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color;
}

static NSImage *ToolbarContainerImage(NSView *view) {
    if ([view respondsToSelector:@selector(displayedImage)]) {
        return [view performSelector:@selector(displayedImage)];
    }
    if ([view respondsToSelector:@selector(image)]) {
        return [view performSelector:@selector(image)];
    }
    return nil;
}

static BOOL ToolbarBitmapHasVisiblePixels(NSBitmapImageRep *bitmap) {
    if (!bitmap) {
        return NO;
    }
    NSInteger width = bitmap.pixelsWide;
    NSInteger height = bitmap.pixelsHigh;
    if (width <= 0 || height <= 0) {
        return NO;
    }
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            NSColor *color = [bitmap colorAtX:x y:y];
            if (!color) {
                continue;
            }
            NSColor *device = DeviceColor(color);
            if ([device alphaComponent] > 0.05f) {
                return YES;
            }
        }
    }
    return NO;
}

static BOOL ToolbarIconHasVisiblePixels(NSImage *image) {
    if (!image) {
        return NO;
    }
    for (NSImageRep *representation in image.representations) {
        if (![representation isKindOfClass:[NSBitmapImageRep class]]) {
            continue;
        }
        if (ToolbarBitmapHasVisiblePixels((NSBitmapImageRep *)representation)) {
            return YES;
        }
    }
    NSBitmapImageRep *fallback = nil;
#if defined(GNUSTEP)
    fallback = RasterizedBitmapForImage(image);
#endif
    if (!fallback) {
        NSData *tiff = [image TIFFRepresentation];
        if (tiff) {
            fallback = [NSBitmapImageRep imageRepWithData:tiff];
        }
    }
    return ToolbarBitmapHasVisiblePixels(fallback);
}

static NSImage *ToolbarProbeImageForItem(NSView *container, NSToolbarItem *toolbarItem) {
    NSImage *image = ToolbarContainerImage(container);
    if (!image) {
        image = toolbarItem.image;
    }
    return image;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
#if !defined(GNUSTEP)
        fprintf(stderr, "ToolbarIconThemeProbe: SKIP (not running under GNUstep)\n");
        return EXIT_SUCCESS;
#else
        NSApplication *application = nil;
        @try {
            application = [NSApplication sharedApplication];
        } @catch (NSException *exception) {
            fprintf(stderr, "ToolbarIconThemeProbe: SKIP (failed to connect to window server: %s)\n",
                    [[exception reason] UTF8String]);
            return EXIT_SUCCESS;
        }
        if (!application) {
            fprintf(stderr, "ToolbarIconThemeProbe: SKIP (NSApplication sharedApplication returned nil)\n");
            return EXIT_SUCCESS;
        }

        ConfigureDarkThemeDefaults();

        AppDelegate *delegate = [[AppDelegate alloc] init];
        if (!delegate) {
            FailAndExit(@"ToolbarIconThemeProbe: failed to create AppDelegate");
        }
        delegate.usesDarkTheme = YES;

        NSArray<NSToolbarItemIdentifier> *identifiers = @[
            @"com.screenshottool.toolbar.select",
            @"com.screenshottool.toolbar.highlighter",
            @"com.screenshottool.toolbar.pen",
            @"com.screenshottool.toolbar.text",
            @"com.screenshottool.toolbar.eraser"
        ];

        for (NSToolbarItemIdentifier identifier in identifiers) {
            NSToolbarItem *toolbarItem = [delegate toolbar:nil
                                      itemForItemIdentifier:identifier
                                   willBeInsertedIntoToolbar:YES];
            if (!toolbarItem) {
                FailAndExit([NSString stringWithFormat:@"ToolbarIconThemeProbe: unable to build %@", identifier]);
            }
            NSView *container = (NSView *)toolbarItem.view;
            NSImage *probeImage = ToolbarProbeImageForItem(container, toolbarItem);
            if (!probeImage) {
                FailAndExit([NSString stringWithFormat:@"ToolbarIconThemeProbe: container missing image (%@)", identifier]);
            }

            NSUInteger repCount = probeImage.representations.count;
            if (repCount == 0) {
                NSLog(@"ToolbarIconThemeProbe: %@ image class=%@ reps=%lu image=%@", identifier, NSStringFromClass([probeImage class]), (unsigned long)repCount, probeImage);
                FailAndExit([NSString stringWithFormat:@"ToolbarIconThemeProbe: toolbar icon lacks bitmap data for %@", identifier]);
            }

            NSTextField *labelField = nil;
            if ([container respondsToSelector:@selector(labelField)]) {
                labelField = [container performSelector:@selector(labelField)];
            }
            if (labelField) {
                NSColor *labelColor = DeviceColor(labelField.textColor);
                if (!labelColor) {
                    FailAndExit(@"ToolbarIconThemeProbe: label text color unavailable");
                }

                NSColor *expected = DeviceColor(STThemeToolbarLabelColor());
                if (!expected) {
                    FailAndExit(@"ToolbarIconThemeProbe: expected theme color unavailable");
                }

                CGFloat tolerance = 0.25f;
                if (fabs(labelColor.redComponent - expected.redComponent) > tolerance ||
                    fabs(labelColor.greenComponent - expected.greenComponent) > tolerance ||
                    fabs(labelColor.blueComponent - expected.blueComponent) > tolerance) {
                    NSString *message = [NSString stringWithFormat:@"ToolbarIconThemeProbe: label colour mismatch for %@. Expected approx (%.3f, %.3f, %.3f) got (%.3f, %.3f, %.3f)",
                                         identifier,
                                         expected.redComponent,
                                         expected.greenComponent,
                                         expected.blueComponent,
                                         labelColor.redComponent,
                                         labelColor.greenComponent,
                                         labelColor.blueComponent];
                    FailAndExit(message);
                }
            }

            if (!ToolbarIconHasVisiblePixels(probeImage)) {
                NSUInteger imageRepCount = probeImage.representations.count;
                NSBitmapImageRep *bitmap = nil;
                if (imageRepCount > 0) {
                    for (NSImageRep *rep in probeImage.representations) {
                        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
                            bitmap = (NSBitmapImageRep *)rep;
                            break;
                        }
                    }
                }
                NSColor *sample = nil;
                if (bitmap) {
                    NSInteger sampleX = MAX(0, bitmap.pixelsWide - 3);
                    NSInteger sampleY = 2;
                    sample = [bitmap colorAtX:sampleX y:sampleY];
                }
                NSColor *deviceSample = [sample colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
                NSLog(@"ToolbarIconThemeProbe DEBUG %@ reps=%lu sample=%@", identifier, (unsigned long)imageRepCount, deviceSample);
                FailAndExit([NSString stringWithFormat:@"ToolbarIconThemeProbe: rendered icon contains no bright pixels for %@", identifier]);
            }
        }
#endif
    }
    return EXIT_SUCCESS;
}
#if defined(GNUSTEP)
static NSBitmapImageRep *RasterizedBitmapForImage(NSImage *image) {
    if (!image) {
        return nil;
    }
    NSSize size = image.size;
    NSInteger width = MAX(1, (NSInteger)ceil(size.width));
    NSInteger height = MAX(1, (NSInteger)ceil(size.height));
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:width
                                                                    pixelsHigh:height
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    if (!rep) {
        return nil;
    }
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:ctx];
    [[NSColor clearColor] setFill];
    NSRect bounds = NSMakeRect(0, 0, width, height);
    NSRectFill(bounds);
    [image drawInRect:bounds
             fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
             fraction:1.0
       respectFlipped:YES
                hints:nil];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}
#endif
