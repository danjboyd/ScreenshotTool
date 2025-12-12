/*
 * ToolbarBadgeRefreshProbe_test.m
 * Copyright (C) 2025 Daniel Boyd
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"

#pragma mark - Testing Category

@interface AppDelegate (ToolbarBadgeAccess)
- (NSImage *)imageByAddingColorBadgeToImage:(NSImage *)image color:(NSColor *)color;
@end

#pragma mark - Test Class

@interface ToolbarBadgeRefreshProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation ToolbarBadgeRefreshProbeTests

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        _appDelegate = [[AppDelegate alloc] init];
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

- (NSImage *)createBaseIconOfSize:(NSSize)size fillColor:(NSColor *)fillColor {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[fillColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: fillColor ?: [NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0f, 0.0f, size.width, size.height));
    [image unlockFocus];
    return image;
}

- (NSColor *)sampleBadgeColorFromImage:(NSImage *)image expectedColor:(NSColor *)expected {
    XCTAssertNotNil(image, @"Image should not be nil");
    NSData *data = [image TIFFRepresentation];
    XCTAssertNotNil(data, @"Failed to get TIFF representation");
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:data];
    XCTAssertNotNil(bitmap, @"Failed to create bitmap from data");

    NSColorSpace *space = [NSColorSpace deviceRGBColorSpace];
    NSColor *expectedDevice = [expected colorUsingColorSpace:space] ?: expected;

    CGFloat bestDistance = CGFLOAT_MAX;
    NSColor *best = nil;
    for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
        for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
            NSColor *pixel = [bitmap colorAtX:x y:y];
            if (!pixel) continue;
            
            NSColor *devicePixel = [pixel colorUsingColorSpace:space] ?: pixel;
            CGFloat dR = devicePixel.redComponent - expectedDevice.redComponent;
            CGFloat dG = devicePixel.greenComponent - expectedDevice.greenComponent;
            CGFloat dB = devicePixel.blueComponent - expectedDevice.blueComponent;
            CGFloat distance = (dR * dR) + (dG * dG) + (dB * dB);
            if (distance < bestDistance) {
                bestDistance = distance;
                best = devicePixel;
            }
        }
    }
    XCTAssertNotNil(best, @"Badge pixels were not detected in the image");
    return best;
}

- (void)assertColor:(NSColor *)actual matchesExpected:(NSColor *)expected withContext:(NSString *)context {
    XCTAssertNotNil(actual, @"Actual color is nil in context: %@", context);
    XCTAssertNotNil(expected, @"Expected color is nil in context: %@", context);
    
    NSColorSpace *space = [NSColorSpace deviceRGBColorSpace];
    NSColor *actualDevice = [actual colorUsingColorSpace:space] ?: actual;
    NSColor *expectedDevice = [expected colorUsingColorSpace:space] ?: expected;

    CGFloat tolerance = 0.05f;
    XCTAssertEqualWithAccuracy(actualDevice.redComponent, expectedDevice.redComponent, tolerance, @"Red mismatch in %@", context);
    XCTAssertEqualWithAccuracy(actualDevice.greenComponent, expectedDevice.greenComponent, tolerance, @"Green mismatch in %@", context);
    XCTAssertEqualWithAccuracy(actualDevice.blueComponent, expectedDevice.blueComponent, tolerance, @"Blue mismatch in %@", context);
}

- (void)assertImageIsNeutral:(NSImage *)image withContext:(NSString *)context {
    NSData *data = [image TIFFRepresentation];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:data];
    XCTAssertNotNil(bitmap, @"Bitmap could not be created for context: %@", context);
    
    for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
        for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
            NSColor *pixel = [bitmap colorAtX:x y:y];
            if (!pixel) continue;
            
            NSColor *devicePixel = [pixel colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: pixel;
            XCTAssertGreaterThanOrEqual(devicePixel.redComponent, 0.98f, @"Base image was mutated (red): %@", context);
            XCTAssertGreaterThanOrEqual(devicePixel.greenComponent, 0.98f, @"Base image was mutated (green): %@", context);
            XCTAssertGreaterThanOrEqual(devicePixel.blueComponent, 0.98f, @"Base image was mutated (blue): %@", context);
        }
    }
}

#pragma mark - Test

- (void)testBadgeCreationIsNonDestructive {
    if (_shouldSkip) return;

    NSSize iconSize = NSMakeSize(32.0f, 32.0f);
    NSImage *baseIcon = [self createBaseIconOfSize:iconSize fillColor:[NSColor whiteColor]];
    XCTAssertNotNil(baseIcon, @"Failed to create base icon");

    NSColor *firstColor = [NSColor colorWithCalibratedRed:0.92f green:0.18f blue:0.24f alpha:1.0f];
    NSColor *secondColor = [NSColor colorWithCalibratedRed:0.18f green:0.56f blue:0.85f alpha:1.0f];

    NSImage *firstBadge = [_appDelegate imageByAddingColorBadgeToImage:[baseIcon copy] color:firstColor];
    XCTAssertNotNil(firstBadge, @"Failed to render first badge");
    NSColor *sampledFirst = [self sampleBadgeColorFromImage:firstBadge expectedColor:firstColor];
    [self assertColor:sampledFirst matchesExpected:firstColor withContext:@"initial badge"];
    [self assertImageIsNeutral:baseIcon withContext:@"after first badge"];

    NSImage *secondBadge = [_appDelegate imageByAddingColorBadgeToImage:[baseIcon copy] color:secondColor];
    XCTAssertNotNil(secondBadge, @"Failed to render second badge");
    NSColor *sampledSecond = [self sampleBadgeColorFromImage:secondBadge expectedColor:secondColor];
    [self assertColor:sampledSecond matchesExpected:secondColor withContext:@"refreshed badge"];
    
    // Verify original images were not mutated
    NSColor *resampledFirst = [self sampleBadgeColorFromImage:firstBadge expectedColor:firstColor];
    [self assertColor:resampledFirst matchesExpected:firstColor withContext:@"first badge preserved"];
    [self assertImageIsNeutral:baseIcon withContext:@"after second badge"];
}

@end
