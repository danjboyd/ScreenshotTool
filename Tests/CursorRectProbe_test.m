/*
 * CursorRectProbe_test.m
 * Exercises ScreenshotCanvasView cursor generation to ensure GNUstep builds
 * keep returning custom cursors for pen/highlighter/eraser when the mouse is
 * inside the canvas.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "ScreenshotCanvasView.h"

#pragma mark - Private Category
@interface ScreenshotCanvasView (CursorPrivate)
+ (NSBitmapImageRep *)cursorBitmapNamed:(NSString *)name;
@end

#pragma mark - Testing Subclass

// A canvas view subclass that overrides cursor asset loading to use the local
// file system instead of the main bundle, isolating the test from app resources.
@interface CursorProbeCanvasView : ScreenshotCanvasView
@end

@implementation CursorProbeCanvasView

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    exit(EXIT_FAILURE);
}

static NSDictionary<NSString *, NSDictionary *> *LoadCursorMetadata(void) {
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    if (cwd.length == 0) {
        FailAndExit(@"CursorRectProbe: Cannot resolve current directory");
    }
    
    NSString *cursorDir = [cwd stringByAppendingPathComponent:@"Resources/Cursors"];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:cursorDir isDirectory:&isDirectory] || !isDirectory) {
        FailAndExit(@"CursorRectProbe: Missing cursor directory");
    }

    NSString *metadataPath = [cursorDir stringByAppendingPathComponent:@"markup-cursors.metadata.json"];
    NSData *data = [NSData dataWithContentsOfFile:metadataPath];
    if (!data) {
        FailAndExit([NSString stringWithFormat:@"CursorRectProbe: Missing metadata file: %@", metadataPath]);
    }
    
    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (!json) {
        FailAndExit([NSString stringWithFormat:@"CursorRectProbe: Invalid metadata JSON: %@", error]);
    }
    if (![json isKindOfClass:[NSArray class]]) {
        FailAndExit(@"CursorRectProbe: Metadata should be an array");
    }
    
    NSMutableDictionary<NSString *, NSMutableDictionary *> *mutable = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in (NSArray *)json) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        
        NSString *tool = entry[@"tool"];
        if (![tool isKindOfClass:[NSString class]]) continue;

        NSMutableDictionary *toolInfo = mutable[tool] ?: [NSMutableDictionary dictionary];
        mutable[tool] = toolInfo;
        
        toolInfo[@"file1x"] = entry[@"file"];
        toolInfo[@"size1x"] = entry[@"size"];
        if ([entry[@"hotspot"] isKindOfClass:[NSArray class]] && [entry[@"hotspot"] count] >= 2) {
            CGFloat hx = [entry[@"hotspot"][0] doubleValue];
            CGFloat hy = [entry[@"hotspot"][1] doubleValue];
            toolInfo[@"hotspot"] = [NSValue valueWithPoint:NSMakePoint(hx, hy)];
        }
    }
    return [NSDictionary dictionaryWithDictionary:mutable];
}

+ (NSDictionary<NSString *, NSDictionary *> *)cursorMetadata {
    static NSDictionary<NSString *, NSDictionary *> *metadata = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        metadata = LoadCursorMetadata();
    });
    return metadata ?: @{};
}

+ (NSString *)probeCursorDirectory {
    static NSString *dir = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
        if (cwd.length == 0) return;
        
        NSString *cursorDir = [cwd stringByAppendingPathComponent:@"Resources/Cursors"];
        BOOL isDirectory = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:cursorDir isDirectory:&isDirectory] && isDirectory) {
            dir = cursorDir;
        }
    });
    return dir;
}

+ (NSBitmapImageRep *)cursorBitmapNamed:(NSString *)name {
    if (name.length == 0) {
        return [super cursorBitmapNamed:name];
    }
    NSString *cursorDir = [self probeCursorDirectory];
    if (!cursorDir) return [super cursorBitmapNamed:name];
    
    NSArray<NSString *> *extensions = @[ @"png", @"tiff", @"tif" ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *ext in extensions) {
        NSString *path = [cursorDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", name, ext]];
        if (![fm fileExistsAtPath:path]) continue;
        
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:data];
        if (rep) return rep;
    }
    return [super cursorBitmapNamed:name];
}
@end

#pragma mark - Testing Category

@interface ScreenshotCanvasView (CursorTesting)
- (NSCursor *)cursorForTestingWithMouseInside:(BOOL)mouseInside;
@end

#pragma mark - Test Class

@interface CursorRectProbeTests : XCTestCase {
    BOOL _shouldSkip;
    CursorProbeCanvasView *_canvas;
}
@end

@implementation CursorRectProbeTests

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        _canvas = [[CursorProbeCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
        
        // Ensure cursor logic thinks an image is present; otherwise it intentionally falls back to the arrow cursor.
        _canvas.image = [[NSImage alloc] initWithSize:NSMakeSize(10.0, 10.0)];
        _canvas.penColor = [NSColor colorWithCalibratedRed:0.9 green:0.2 blue:0.2 alpha:1.0];
        _canvas.highlighterColor = [NSColor colorWithCalibratedRed:1.0 green:1.0 blue:0.3 alpha:1.0];

    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    _canvas = nil;
    [super tearDown];
}

- (void)testPenCursor {
    if (_shouldSkip) return;
    
    _canvas.activeTool = ScreenshotCanvasToolPen;
    NSCursor *insideCursor = [_canvas cursorForTestingWithMouseInside:YES];
    XCTAssertNotNil(insideCursor, @"Cursor should not be nil for pen tool inside canvas");
    XCTAssertNotEqual(insideCursor, [NSCursor arrowCursor], @"Pen tool should use custom cursor when inside");
    XCTAssertNotEqual(insideCursor, [NSCursor crosshairCursor], @"Pen tool should use tinted cursor, not crosshair fallback");

    NSCursor *outsideCursor = [_canvas cursorForTestingWithMouseInside:NO];
    XCTAssertEqual(outsideCursor, [NSCursor arrowCursor], @"Pen tool should revert to arrow cursor when outside");
}

- (void)testHighlighterCursor {
    if (_shouldSkip) return;

    _canvas.activeTool = ScreenshotCanvasToolHighlighter;
    NSCursor *insideCursor = [_canvas cursorForTestingWithMouseInside:YES];
    XCTAssertNotNil(insideCursor, @"Cursor should not be nil for highlighter tool inside canvas");
    XCTAssertNotEqual(insideCursor, [NSCursor arrowCursor], @"Highlighter should use custom cursor when inside");
    XCTAssertNotEqual(insideCursor, [NSCursor crosshairCursor], @"Highlighter should use tinted cursor, not crosshair fallback");

    NSCursor *outsideCursor = [_canvas cursorForTestingWithMouseInside:NO];
    XCTAssertEqual(outsideCursor, [NSCursor arrowCursor], @"Highlighter should revert to arrow cursor when outside");
}

- (void)testEraserCursor {
    if (_shouldSkip) return;

    _canvas.activeTool = ScreenshotCanvasToolEraser;
    NSCursor *insideCursor = [_canvas cursorForTestingWithMouseInside:YES];
    XCTAssertNotNil(insideCursor, @"Cursor should not be nil for eraser tool inside canvas");
    XCTAssertNotEqual(insideCursor, [NSCursor arrowCursor], @"Eraser should use custom cursor when inside");
    XCTAssertNotEqual(insideCursor, [NSCursor pointingHandCursor], @"Eraser should use custom cursor, not pointing hand fallback");
    
    NSCursor *outsideCursor = [_canvas cursorForTestingWithMouseInside:NO];
    XCTAssertEqual(outsideCursor, [NSCursor arrowCursor], @"Eraser should revert to arrow cursor when outside");
}

@end
