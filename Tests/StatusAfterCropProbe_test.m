/*
 * StatusAfterCropProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * After a crop the status bar shows the canvas's new pixel size, and says the file size is
 * "unsaved" until the next save, instead of the size of the file on disk (found in #344's smoke).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

@interface ScreenshotCanvasView (StatusAfterCropTesting)
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
@end

@interface AppDelegate (StatusAfterCropTesting)
- (void)setupWindowAndContent;
- (BOOL)openImageAtURL:(NSURL *)url;
- (void)cropImage:(id)sender;
- (void)markAnnotationsSaved;
- (ScreenshotCanvasView *)canvasView;
- (NSTextField *)statusTextField;
@end

@interface StatusAfterCropProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
    NSString *_path;
}
@end

@implementation StatusAfterCropProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        _appDelegate = [[AppDelegate alloc] init];
        [_appDelegate setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
        return;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:300
                                                                    pixelsHigh:200
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    memset(rep.bitmapData, 200, (size_t)(rep.bytesPerRow * rep.pixelsHigh));
    _path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                        [NSString stringWithFormat:@"crop-status-%@.png", [NSUUID UUID].UUIDString]];
    XCTAssertTrue([[rep representationUsingType:NSPNGFileType properties:@{}] writeToFile:_path atomically:YES]);
}

- (void)tearDown {
    if (_path) {
        [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
    }
    _appDelegate = nil;
    [super tearDown];
}

- (void)testACropShowsItsSizeAndAnUnsavedFileSize {
    XCTSkipIf(_shouldSkip, @"No window server");
    XCTAssertTrue([_appDelegate openImageAtURL:[NSURL fileURLWithPath:_path]]);
    NSString *opened = _appDelegate.statusTextField.stringValue;
    XCTAssertTrue([opened hasPrefix:@"300 × 200 px  ·  PNG  ·  "], @"Opened: %@", opened);
    XCTAssertFalse([opened hasSuffix:@"unsaved"], @"A file just opened has its size: %@", opened);

    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    canvas.hasSelectionRect = YES;
    canvas.selectionRect = NSMakeRect(10.0, 10.0, 120.0, 80.0);
    [_appDelegate cropImage:nil];

    XCTAssertEqualObjects(_appDelegate.statusTextField.stringValue, @"120 × 80 px  ·  PNG  ·  unsaved",
                          @"The crop's size, and no stale file size");

    // Saved: the size of the file again, read afresh.
    [_appDelegate markAnnotationsSaved];
    NSString *saved = _appDelegate.statusTextField.stringValue;
    XCTAssertTrue([saved hasPrefix:@"120 × 80 px  ·  PNG  ·  "], @"Saved: %@", saved);
    XCTAssertFalse([saved hasSuffix:@"unsaved"], @"Saved: %@", saved);
}

@end
