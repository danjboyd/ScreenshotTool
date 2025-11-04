/*
 * CropUndoProbe.m
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

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    exit(EXIT_FAILURE);
}

static NSImage *STCreateTestImage(NSSize size) {
    if (size.width <= 0.0 || size.height <= 0.0) {
        return nil;
    }
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor colorWithCalibratedRed:0.75f green:0.11f blue:0.28f alpha:1.0f] setFill];
    NSRectFill(NSMakeRect(0.0f, 0.0f, size.width, size.height));
    [[NSColor whiteColor] setFill];
    NSRectFillUsingOperation(NSMakeRect(size.width * 0.25f,
                                        size.height * 0.25f,
                                        size.width * 0.5f,
                                        size.height * 0.5f),
                             NSCompositeSourceOver);
    [image unlockFocus];
    return image;
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

@interface ScreenshotCanvasView (CropUndoTesting)
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
- (NSDictionary *)snapshotCanvasState;
@end

@interface AppDelegate (CropUndoTesting)
- (void)setupWindowAndContent;
- (void)resizeWindowToImageSize:(NSSize)size;
- (NSWindow *)window;
- (ScreenshotCanvasView *)canvasView;
@end

static void EnsureUndoManagerAvailable(NSUndoManager *undo) {
    if (!undo) {
        FailAndExit(@"CropUndoProbe: undo manager unavailable");
    }
    undo.levelsOfUndo = 10;
}

static NSRect CreateSelection(NSImage *image) {
    CGFloat width = image.size.width;
    CGFloat height = image.size.height;
    return NSMakeRect(floor(width * 0.2f),
                      floor(height * 0.2f),
                      floor(width * 0.5f),
                      floor(height * 0.45f));
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = nil;
        @try {
            application = [NSApplication sharedApplication];
        } @catch (NSException *exception) {
            fprintf(stderr, "CropUndoProbe: SKIP (failed to connect to window server: %s)\n",
                    [[exception reason] UTF8String]);
            return EXIT_SUCCESS;
        }
        if (!application) {
            fprintf(stderr, "CropUndoProbe: SKIP (NSApplication sharedApplication returned nil)\n");
            return EXIT_SUCCESS;
        }

        AppDelegate *delegate = [[AppDelegate alloc] init];
        [delegate setupWindowAndContent];
        [delegate.window makeKeyAndOrderFront:nil];

        ScreenshotCanvasView *canvas = delegate.canvasView;
        if (!canvas) {
            FailAndExit(@"CropUndoProbe: canvas view unavailable");
        }

        NSImage *originalImage = STCreateTestImage(NSMakeSize(640.0f, 480.0f));
        if (!originalImage) {
            FailAndExit(@"CropUndoProbe: failed to create test image");
        }
        canvas.image = originalImage;
        [delegate resizeWindowToImageSize:originalImage.size];

        NSRect selection = CreateSelection(originalImage);
        canvas.hasSelectionRect = YES;
        canvas.selectionRect = selection;

        NSUndoManager *undo = [canvas undoManager];
        EnsureUndoManagerAvailable(undo);

        BOOL cropped = [canvas cropToActiveSelection];
        if (!cropped) {
            FailAndExit(@"CropUndoProbe: cropToActiveSelection returned NO");
        }

        if (![undo canUndo]) {
            FailAndExit(@"CropUndoProbe: undo manager did not register crop action");
        }

        NSSize croppedSize = canvas.image.size;
        if (!(croppedSize.width < originalImage.size.width &&
              croppedSize.height < originalImage.size.height)) {
            FailAndExit(@"CropUndoProbe: canvas image was not reduced after crop");
        }

        [undo undo];

        if (canvas.image.size.width != originalImage.size.width ||
            canvas.image.size.height != originalImage.size.height) {
            FailAndExit(@"CropUndoProbe: undo did not restore original image size");
        }

        if (![canvas hasSelection]) {
            FailAndExit(@"CropUndoProbe: selection not restored after undo");
        }

        NSRect restoredSelection = canvas.selectionRect;
        CGFloat delta = fabs(restoredSelection.origin.x - selection.origin.x) +
                        fabs(restoredSelection.origin.y - selection.origin.y) +
                        fabs(restoredSelection.size.width - selection.size.width) +
                        fabs(restoredSelection.size.height - selection.size.height);
        if (delta > 0.51f) {
            FailAndExit(@"CropUndoProbe: selection rect mismatch after undo");
        }
    }
    return EXIT_SUCCESS;
}
