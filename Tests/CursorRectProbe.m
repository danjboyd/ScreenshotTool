/*
 * CursorRectProbe.m
 * Exercises ScreenshotCanvasView cursor generation to ensure GNUstep builds
 * keep returning custom cursors for pen/highlighter/eraser when the mouse is
 * inside the canvas.
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import "ScreenshotCanvasView.h"

@interface ScreenshotCanvasView (CursorTesting)
- (NSCursor *)cursorForTestingWithMouseInside:(BOOL)mouseInside;
@end

@interface ScreenshotCanvasView (CursorPrivate)
+ (NSBitmapImageRep *)cursorBitmapNamed:(NSString *)name;
@end

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", message.UTF8String ?: "CursorRectProbe: failure");
    exit(EXIT_FAILURE);
}

static NSString *CursorResourceDirectory(void) {
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    if (cwd.length == 0) {
        FailAndExit(@"CursorRectProbe: cannot resolve current directory");
    }
    NSString *cursorDir = [cwd stringByAppendingPathComponent:@"Resources/Cursors"];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:cursorDir isDirectory:&isDirectory] || !isDirectory) {
        FailAndExit([NSString stringWithFormat:@"CursorRectProbe: missing cursor directory at %@", cursorDir]);
    }
    return cursorDir;
}

static NSDictionary<NSString *, NSDictionary *> *LoadCursorMetadata(void) {
    NSString *cursorDir = CursorResourceDirectory();
    NSString *metadataPath = [cursorDir stringByAppendingPathComponent:@"markup-cursors.metadata.json"];
    NSData *data = [NSData dataWithContentsOfFile:metadataPath];
    if (!data) {
        FailAndExit([NSString stringWithFormat:@"CursorRectProbe: missing metadata file %@", metadataPath]);
    }
    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (!json || ![json isKindOfClass:[NSArray class]]) {
        FailAndExit([NSString stringWithFormat:@"CursorRectProbe: invalid metadata JSON (%@)", error]);
    }
    NSMutableDictionary<NSString *, NSMutableDictionary *> *mutable = [[NSMutableDictionary alloc] init];
    for (NSDictionary *entry in (NSArray *)json) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *tool = entry[@"tool"];
        NSNumber *size = entry[@"size"];
        NSString *file = entry[@"file"];
        NSArray *hotspot = entry[@"hotspot"];
        if (![tool isKindOfClass:[NSString class]] || ![size isKindOfClass:[NSNumber class]] || ![file isKindOfClass:[NSString class]]) {
            continue;
        }
        NSMutableDictionary *toolInfo = mutable[tool];
        if (!toolInfo) {
            toolInfo = [[NSMutableDictionary alloc] init];
            mutable[tool] = toolInfo;
        }
        if ([size integerValue] <= 32 || !toolInfo[@"file1x"]) {
            toolInfo[@"file1x"] = file;
            toolInfo[@"size1x"] = size;
            if ([hotspot isKindOfClass:[NSArray class]] && hotspot.count >= 2) {
                CGFloat hx = [hotspot[0] doubleValue];
                CGFloat hy = [hotspot[1] doubleValue];
                toolInfo[@"hotspot"] = [NSValue valueWithPoint:NSMakePoint(hx, hy)];
            }
        }
    }
    return [[NSDictionary alloc] initWithDictionary:mutable copyItems:YES];
}

@interface CursorProbeCanvasView : ScreenshotCanvasView
@end

@implementation CursorProbeCanvasView

+ (NSString *)probeCursorDirectory {
    static NSString *dir = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dir = CursorResourceDirectory();
    });
    return dir;
}

+ (NSDictionary<NSString *, NSDictionary *> *)cursorMetadata {
    static NSDictionary<NSString *, NSDictionary *> *metadata = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        metadata = LoadCursorMetadata();
    });
    return metadata ?: @{};
}

+ (NSBitmapImageRep *)cursorBitmapNamed:(NSString *)name {
    if (name.length == 0) {
        return [super cursorBitmapNamed:name];
    }
    NSString *cursorDir = [self probeCursorDirectory];
    NSArray<NSString *> *extensions = @[ @"png", @"tiff", @"tif" ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *ext in extensions) {
        NSString *path = [cursorDir stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"%@.%@", name, ext]];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) {
            continue;
        }
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) {
            continue;
        }
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:data];
        if (rep) {
            return rep;
        }
        NSArray *candidates = [NSBitmapImageRep imageRepsWithData:data];
        for (NSImageRep *candidate in candidates) {
            if ([candidate isKindOfClass:[NSBitmapImageRep class]]) {
                return [(NSBitmapImageRep *)candidate copy];
            }
        }
        NSImage *image = [[NSImage alloc] initWithData:data];
        if (image) {
            NSRect rect = NSMakeRect(0.0, 0.0, image.size.width, image.size.height);
            [image lockFocus];
            NSBitmapImageRep *fallback = [[NSBitmapImageRep alloc] initWithFocusedViewRect:rect];
            [image unlockFocus];
            if (fallback) {
                return fallback;
            }
        }
    }
    return [super cursorBitmapNamed:name];
}

@end

static void AssertCustomCursor(NSCursor *cursor, NSString *message, NSCursor *disallowed) {
    if (!cursor) {
        FailAndExit([NSString stringWithFormat:@"%@ (cursor nil)", message]);
    }
    if (cursor == [NSCursor arrowCursor]) {
        FailAndExit([NSString stringWithFormat:@"%@ (unexpected arrow cursor)", message]);
    }
    if (disallowed && cursor == disallowed) {
        FailAndExit([NSString stringWithFormat:@"%@ (cursor fell back to %@)", message, NSStringFromClass([disallowed class])]);
    }
}

static void AssertArrowCursor(NSCursor *cursor, NSString *message) {
    if (cursor != [NSCursor arrowCursor]) {
        FailAndExit([NSString stringWithFormat:@"%@ (expected arrow cursor)", message]);
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
#if defined(GNUSTEP)
        @try {
            [NSApplication sharedApplication];
        } @catch (NSException *exception) {
            fprintf(stderr,
                    "CursorRectProbe: SKIP (failed to connect to window server: %s)\n",
                    exception.reason.UTF8String ?: "unknown");
            return EXIT_SUCCESS;
        }
#endif
        CursorProbeCanvasView *view = [[CursorProbeCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
        if (!view) {
            FailAndExit(@"CursorRectProbe: failed to create canvas view");
        }
        view.penColor = [NSColor colorWithCalibratedRed:0.9 green:0.2 blue:0.2 alpha:1.0];
        view.highlighterColor = [NSColor colorWithCalibratedRed:1.0 green:1.0 blue:0.3 alpha:1.0];

        view.activeTool = ScreenshotCanvasToolPen;
        AssertCustomCursor([view cursorForTestingWithMouseInside:YES],
                           @"Pen tool should use tinted cursor when inside",
                           [NSCursor crosshairCursor]);
        AssertArrowCursor([view cursorForTestingWithMouseInside:NO],
                          @"Pen tool should revert to arrow when outside");

        view.activeTool = ScreenshotCanvasToolHighlighter;
        AssertCustomCursor([view cursorForTestingWithMouseInside:YES],
                           @"Highlighter should use tinted cursor when inside",
                           [NSCursor crosshairCursor]);
        AssertArrowCursor([view cursorForTestingWithMouseInside:NO],
                          @"Highlighter should revert to arrow when outside");

        view.activeTool = ScreenshotCanvasToolEraser;
        AssertCustomCursor([view cursorForTestingWithMouseInside:YES],
                           @"Eraser should use custom cursor when inside",
                           [NSCursor pointingHandCursor]);
        AssertArrowCursor([view cursorForTestingWithMouseInside:NO],
                          @"Eraser should revert to arrow when outside");

        return EXIT_SUCCESS;
    }
}
