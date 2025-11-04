/*
 * CropUndoWindowProbe.m
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
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"

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

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    exit(EXIT_FAILURE);
}

static NSImage *STCreateFilledImage(NSSize size) {
    if (size.width <= 0.0 || size.height <= 0.0) {
        return nil;
    }
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor colorWithCalibratedRed:0.2 green:0.4 blue:0.8 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    [image unlockFocus];
    return image;
}

static NSSize ContentSizeForWindow(NSWindow *window) {
    if (!window) {
        return NSZeroSize;
    }
    NSRect frame = window.frame;
    return [window contentRectForFrameRect:frame].size;
}

@interface AppDelegate (CropUndoTesting)
- (void)setupWindowAndContent;
- (void)resizeWindowToImageSize:(NSSize)size;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = nil;
        @try {
            application = [NSApplication sharedApplication];
        } @catch (NSException *exception) {
            fprintf(stderr, "CropUndoWindowProbe: SKIP (failed to connect to window server: %s)\n",
                    [[exception reason] UTF8String]);
            return EXIT_SUCCESS;
        }
        if (!application) {
            fprintf(stderr, "CropUndoWindowProbe: SKIP (NSApplication sharedApplication returned nil)\n");
            return EXIT_SUCCESS;
        }

        AppDelegate *delegate = [[AppDelegate alloc] init];
        [delegate setupWindowAndContent];

        ScreenshotCanvasView *canvas = delegate.canvasView;
        NSWindow *window = delegate.window;
        if (!canvas || !window) {
            FailAndExit(@"CropUndoWindowProbe: window or canvas view unavailable after setup");
        }

        NSImage *originalImage = STCreateFilledImage(NSMakeSize(640.0, 480.0));
        if (!originalImage) {
            FailAndExit(@"CropUndoWindowProbe: failed to create original image");
        }
        canvas.image = originalImage;
        [delegate resizeWindowToImageSize:originalImage.size];

        NSSize originalContent = ContentSizeForWindow(window);
        if (originalContent.width <= 0.0 || originalContent.height <= 0.0) {
            FailAndExit(@"CropUndoWindowProbe: original window size invalid");
        }

        NSImage *croppedImage = STCreateFilledImage(NSMakeSize(200.0, 150.0));
        if (!croppedImage) {
            FailAndExit(@"CropUndoWindowProbe: failed to create cropped image");
        }
        canvas.image = croppedImage;
        [delegate resizeWindowToImageSize:croppedImage.size];

        NSSize croppedContent = ContentSizeForWindow(window);
        if (!(croppedContent.width < originalContent.width &&
              croppedContent.height < originalContent.height)) {
            FailAndExit(@"CropUndoWindowProbe: window did not shrink after crop simulation");
        }

        canvas.image = originalImage;
        [[NSNotificationCenter defaultCenter] postNotificationName:ScreenshotCanvasViewDidRestoreStateNotification
                                                            object:canvas];

        NSSize restoredContent = ContentSizeForWindow(window);
        CGFloat widthDelta = fabs(restoredContent.width - originalContent.width);
        CGFloat heightDelta = fabs(restoredContent.height - originalContent.height);
        if (widthDelta > 0.51f || heightDelta > 0.51f) {
            NSString *message = [NSString stringWithFormat:
                                 @"CropUndoWindowProbe: window size mismatch after undo (expected %.2fx%.2f, got %.2fx%.2f)",
                                 originalContent.width,
                                 originalContent.height,
                                 restoredContent.width,
                                 restoredContent.height];
            FailAndExit(message);
        }
    }
    return EXIT_SUCCESS;
}
