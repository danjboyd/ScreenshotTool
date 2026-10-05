/*
 * ToolbarIconThemeProbe_test.m
 * Regression probe for toolbar icon + label rendering on GNUstep dark themes
 * Copyright (C) 2025 Daniel Boyd
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "STThemeUtilities.h"

#if !defined(NSCompositingOperationSourceOver)
#define NSCompositingOperationSourceOver NSCompositeSourceOver
#endif

#if defined(GNUSTEP)

#pragma mark - Testing Category
@interface AppDelegate (ToolbarExposure)
@property (nonatomic, assign) BOOL usesDarkTheme;
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
    itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag;
@end

#pragma mark - Test Class
@interface ToolbarIconThemeProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation ToolbarIconThemeProbeTests

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    
    // This test is GNUstep-specific
#if !defined(GNUSTEP)
    _shouldSkip = YES;
    return;
#endif

    @try {
        [NSApplication sharedApplication];
        [[NSUserDefaults standardUserDefaults] setObject:@"Sombre" forKey:@"GSTheme"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        _appDelegate = [[AppDelegate alloc] init];
        _appDelegate.usesDarkTheme = YES;
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

- (NSColor *)deviceColor:(NSColor *)color {
    return [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color;
}

- (NSImage *)imageFromToolbarView:(NSView *)view orItem:(NSToolbarItem *)item {
    if ([view respondsToSelector:@selector(displayedImage)]) {
        return [view performSelector:@selector(displayedImage)];
    }
    if ([view respondsToSelector:@selector(image)]) {
        return [view performSelector:@selector(image)];
    }
    return item.image;
}

- (NSBitmapImageRep *)rasterizedBitmapForImage:(NSImage *)image {
    if (!image) return nil;
    NSSize size = image.size;
    NSInteger width = MAX(1, (NSInteger)ceil(size.width));
    NSInteger height = MAX(1, (NSInteger)ceil(size.height));
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    if (!rep) return nil;
    
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:ctx];
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0, 0, width, height));
    [image drawInRect:NSMakeRect(0, 0, width, height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

- (BOOL)bitmapHasVisiblePixels:(NSBitmapImageRep *)bitmap {
    if (!bitmap) return NO;
    for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
        for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
            if ([[bitmap colorAtX:x y:y] alphaComponent] > 0.05f) {
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)iconHasVisiblePixels:(NSImage *)image {
    if (!image) return NO;
    for (NSImageRep *rep in image.representations) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]] && [self bitmapHasVisiblePixels:(NSBitmapImageRep *)rep]) {
            return YES;
        }
    }
    NSBitmapImageRep *fallback = [self rasterizedBitmapForImage:image];
    return [self bitmapHasVisiblePixels:fallback];
}

#pragma mark - Test

- (void)testToolbarIconsAndLabelsRenderCorrectlyOnDarkTheme {
    XCTSkipIf(_shouldSkip, @"No window server");

    NSArray<NSToolbarItemIdentifier> *identifiers = @[
        @"com.screenshottool.toolbar.select",
        @"com.screenshottool.toolbar.highlighter",
        @"com.screenshottool.toolbar.pen",
        @"com.screenshottool.toolbar.text",
        @"com.screenshottool.toolbar.eraser"
    ];

    for (NSToolbarItemIdentifier identifier in identifiers) {
        NSToolbarItem *item = [_appDelegate toolbar:nil itemForItemIdentifier:identifier willBeInsertedIntoToolbar:YES];
        XCTAssertNotNil(item, @"Failed to build toolbar item: %@", identifier);

        NSView *container = (NSView *)item.view;
        NSImage *probeImage = [self imageFromToolbarView:container orItem:item];
        XCTAssertNotNil(probeImage, @"Toolbar item container missing image: %@", identifier);
        XCTAssertTrue(probeImage.representations.count > 0, @"Toolbar icon lacks bitmap data for %@", identifier);
        // One monochrome set, named so the theme tints it like GTK's symbolic icons (#57).
        XCTAssertTrue([probeImage.name hasSuffix:@"-symbolic"], @"%@ uses a symbolic icon, not %@", identifier, probeImage.name);
        
        NSTextField *labelField = nil;
        if ([container respondsToSelector:@selector(labelField)]) {
            labelField = [container performSelector:@selector(labelField)];
        }
        if (labelField) {
            NSColor *labelColor = [self deviceColor:labelField.textColor];
            XCTAssertNotNil(labelColor, @"Label text color unavailable for %@", identifier);
            
            NSColor *expectedColor = [self deviceColor:STThemeToolbarLabelColor()];
            XCTAssertNotNil(expectedColor, @"Expected theme color unavailable");

            CGFloat tolerance = 0.25f;
            XCTAssertEqualWithAccuracy(labelColor.redComponent, expectedColor.redComponent, tolerance, @"Label red component mismatch for %@", identifier);
            XCTAssertEqualWithAccuracy(labelColor.greenComponent, expectedColor.greenComponent, tolerance, @"Label green component mismatch for %@", identifier);
            XCTAssertEqualWithAccuracy(labelColor.blueComponent, expectedColor.blueComponent, tolerance, @"Label blue component mismatch for %@", identifier);
        }

        XCTAssertTrue([self iconHasVisiblePixels:probeImage], @"Rendered icon contains no visible pixels for %@", identifier);
    }
}

@end

#endif
