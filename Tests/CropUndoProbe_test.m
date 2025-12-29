/*
 * CropUndoProbe_test.m
 * Copyright (C) 2025 Daniel Boyd
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "TestEnvironmentHelpers.h"

#pragma mark - Testing Categories

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

#pragma mark - Test Class

@interface CropUndoProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation CropUndoProbeTests

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
        [_appDelegate.window makeKeyAndOrderFront:nil];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    _appDelegate = nil;
    [super tearDown];
}

#pragma mark - Helpers

- (NSImage *)createTestImageWithSize:(NSSize)size {
    XCTAssertTrue(size.width > 0.0 && size.height > 0.0);
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

- (NSRect)createSelectionForImage:(NSImage *)image {
    CGFloat width = image.size.width;
    CGFloat height = image.size.height;
    return NSMakeRect(floor(width * 0.2f),
                      floor(height * 0.2f),
                      floor(width * 0.5f),
                      floor(height * 0.45f));
}

#pragma mark - Test

- (void)testCropAndUndoRestoresState {
    if (_shouldSkip) return;

    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    XCTAssertNotNil(canvas, @"Canvas view should be available from app delegate");

    NSImage *originalImage = [self createTestImageWithSize:NSMakeSize(640.0f, 480.0f)];
    XCTAssertNotNil(originalImage, @"Failed to create test image");
    
    canvas.image = originalImage;
    [_appDelegate resizeWindowToImageSize:originalImage.size];

    NSRect selection = [self createSelectionForImage:originalImage];
    canvas.hasSelectionRect = YES;
    canvas.selectionRect = selection;

    NSUndoManager *undo = [canvas undoManager];
    XCTAssertNotNil(undo, @"Undo manager should be available");
    undo.levelsOfUndo = 10;

    BOOL cropped = [canvas cropToActiveSelection];
    XCTAssertTrue(cropped, @"cropToActiveSelection should return YES");

    XCTAssertTrue([undo canUndo], @"Undo manager should register the crop action");

    NSSize originalSize = originalImage.size;
    NSSize croppedSize = canvas.image.size;
    XCTAssertTrue(croppedSize.width < originalSize.width, @"Canvas image width should be smaller after crop");
    XCTAssertTrue(croppedSize.height < originalSize.height, @"Canvas image height should be smaller after crop");

    [undo undo];

    XCTAssertEqual(canvas.image.size.width, originalSize.width, @"Undo should restore original image width");
    XCTAssertEqual(canvas.image.size.height, originalSize.height, @"Undo should restore original image height");

    XCTAssertTrue([canvas hasSelection], @"Selection should be restored after undo");

    NSRect restoredSelection = canvas.selectionRect;
    CGFloat tolerance = 0.51f;
    XCTAssertEqualWithAccuracy(restoredSelection.origin.x, selection.origin.x, tolerance);
    XCTAssertEqualWithAccuracy(restoredSelection.origin.y, selection.origin.y, tolerance);
    XCTAssertEqualWithAccuracy(restoredSelection.size.width, selection.size.width, tolerance);
    XCTAssertEqualWithAccuracy(restoredSelection.size.height, selection.size.height, tolerance);
}

@end
