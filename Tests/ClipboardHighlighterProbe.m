/*
 * ClipboardHighlighterProbe.m
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

@interface ScreenshotCanvasView (ClipboardProbe)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@end

static NSImage *STCreateBaseImage(NSSize size) {
    if (size.width <= 0.0 || size.height <= 0.0) {
        return nil;
    }
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
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

static BOOL STImageContainsHighlighterOverlay(NSImage *image) {
    if (!image) {
        return NO;
    }
    NSData *tiff = [image TIFFRepresentation];
    if (!tiff) {
        return NO;
    }
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiff];
    if (!bitmap) {
        return NO;
    }

    NSInteger width = bitmap.pixelsWide;
    NSInteger height = bitmap.pixelsHigh;
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            NSColor *pixel = [bitmap colorAtX:x y:y];
            if (!pixel) {
                continue;
            }
            NSColor *device = [pixel colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: pixel;
            // Highlighter overlay (semi-transparent yellow) significantly reduces the blue channel.
            if (device.blueComponent < 0.95f) {
                return YES;
            }
        }
    }
    return NO;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = nil;
        @try {
            application = [NSApplication sharedApplication];
        } @catch (NSException *exception) {
            fprintf(stderr, "ClipboardHighlighterProbe: SKIP (failed to connect to window server: %s)\n",
                    [[exception reason] UTF8String]);
            return EXIT_SUCCESS;
        }
        if (!application) {
            fprintf(stderr, "ClipboardHighlighterProbe: SKIP (NSApplication sharedApplication returned nil)\n");
            return EXIT_SUCCESS;
        }

        NSRect frame = NSMakeRect(0.0, 0.0, 640.0, 480.0);
        ScreenshotCanvasView *canvas = [[ScreenshotCanvasView alloc] initWithFrame:frame];
        if (!canvas) {
            FailAndExit(@"ClipboardHighlighterProbe: failed to allocate canvas view");
        }

        NSImage *baseImage = STCreateBaseImage(frame.size);
        if (!baseImage) {
            FailAndExit(@"ClipboardHighlighterProbe: failed to construct base image");
        }
        [canvas loadImage:baseImage];

        NSColor *highlighter = [NSColor colorWithCalibratedRed:0.99f
                                                        green:0.94f
                                                         blue:0.30f
                                                        alpha:1.0f];
        MarkupStroke *stroke = STCreateHighlighterStroke(highlighter, 32.0f, frame);
        if (!stroke) {
            FailAndExit(@"ClipboardHighlighterProbe: failed to construct highlighter stroke");
        }

        if (!canvas.strokes) {
            canvas.strokes = [[NSMutableArray alloc] init];
        }
        [canvas.strokes addObject:stroke];

        NSImage *flattened = [canvas flattenedImageForSelection];
        if (!flattened) {
            FailAndExit(@"ClipboardHighlighterProbe: canvas failed to flatten image");
        }

        if (!STImageContainsHighlighterOverlay(flattened)) {
            FailAndExit(@"ClipboardHighlighterProbe: highlighter overlay missing from flattened image");
        }
    }
    return EXIT_SUCCESS;
}
