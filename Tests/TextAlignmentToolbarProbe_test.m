/*
 * TextAlignmentToolbarProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Text alignment (#31) and the in-place text toolbar shown while editing (#34).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupText.h"
#import "STTextOptionsBar.h"
#import "ScreenshotToolSettings.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (TextAlignmentToolbarTesting) <STTextOptionsBarDelegate>
- (void)setupWindowAndContent;
- (void)layoutContentSubviews;
- (NSWindow *)window;
- (NSScrollView *)scrollView;
- (ScreenshotCanvasView *)canvasView;
- (STTextOptionsBar *)textOptionsBar;
@end

@interface ScreenshotCanvasView (TextAlignmentToolbarTesting)
@property (nonatomic, strong) NSTextView *activeTextView;
@property (nonatomic, strong) NSMutableArray<MarkupText *> *texts;
- (void)beginTextEntryWithImageRect:(NSRect)imageRect existingText:(MarkupText *)existingText;
- (void)commitActiveTextIfNeeded;
@end

@interface TextAlignmentToolbarProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation TextAlignmentToolbarProbeTests

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
    }
}

- (void)tearDown {
    _appDelegate = nil;
    [super tearDown];
}

#pragma mark - Helpers

- (NSImage *)whiteImageOfSize:(NSSize)size {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    [image unlockFocus];
    return image;
}

- (ScreenshotCanvasView *)editingCanvas {
    ScreenshotCanvasView *canvas = _appDelegate.canvasView;
    [canvas loadImage:[self whiteImageOfSize:NSMakeSize(800.0, 400.0)]];
    [_appDelegate.window setContentSize:NSMakeSize(800.0, 400.0)];
    [_appDelegate layoutContentSubviews];
    canvas.fitToWindow = NO;
    canvas.zoomScale = 1.0;
    canvas.textFont = [NSFont fontWithName:@"DejaVuSans" size:24.0] ?: [NSFont systemFontOfSize:24.0];
    canvas.textSizePreset = STTextSizePresetExact;
    canvas.textStyle = MarkupTextStylePlain;
    canvas.textAlignment = NSTextAlignmentLeft;
    canvas.activeTool = ScreenshotCanvasToolText;
    return canvas;
}

/// Column range of non-white pixels in an image's rows [top, top+height).
- (NSRange)inkColumnsIn:(NSImage *)image top:(NSInteger)top height:(NSInteger)height {
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
    NSInteger minX = NSIntegerMax, maxX = -1;
    for (NSInteger y = top; y < MIN(top + height, rep.pixelsHigh); y++) {
        for (NSInteger x = 0; x < rep.pixelsWide; x++) {
            NSColor *p = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
            if (p && (p.redComponent < 0.8 || p.greenComponent < 0.8 || p.blueComponent < 0.8)) {
                minX = MIN(minX, x);
                maxX = MAX(maxX, x);
            }
        }
    }
    return maxX < 0 ? NSMakeRange(NSNotFound, 0) : NSMakeRange((NSUInteger)minX, (NSUInteger)(maxX - minX + 1));
}

- (MarkupText *)fixedLabel:(NSString *)string alignment:(NSTextAlignment)alignment {
    NSFont *font = [NSFont fontWithName:@"DejaVuSans" size:24.0] ?: [NSFont systemFontOfSize:24.0];
    MarkupText *text = [[MarkupText alloc] initWithText:string font:font color:[NSColor blackColor]
                                                 origin:NSMakePoint(100.0, 100.0) boxSize:NSMakeSize(400.0, 10.0)];
    text.widthIsFixed = YES;
    text.alignment = alignment;
    [text fitToTextWithinCanvasSize:NSMakeSize(800.0, 400.0)];
    return text;
}

- (NSImage *)exportOfText:(MarkupText *)text {
    ScreenshotCanvasView *canvas = [[ScreenshotCanvasView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 800.0, 400.0)];
    [canvas loadImage:[self whiteImageOfSize:NSMakeSize(800.0, 400.0)]];
    if (!canvas.texts) {
        canvas.texts = [[NSMutableArray alloc] init];
    }
    [canvas.texts addObject:text];
    return [canvas flattenedImage];
}

#pragma mark - #31 alignment

- (void)testAlignmentPlacesTextWithinAFixedBox {
    if (_shouldSkip) return;
    MarkupText *left = [self fixedLabel:@"Hi" alignment:NSTextAlignmentLeft];
    MarkupText *centre = [self fixedLabel:@"Hi" alignment:NSTextAlignmentCenter];
    MarkupText *right = [self fixedLabel:@"Hi" alignment:NSTextAlignmentRight];

    NSRange leftInk = [self inkColumnsIn:[self exportOfText:left] top:100 height:40];
    NSRange centreInk = [self inkColumnsIn:[self exportOfText:centre] top:100 height:40];
    NSRange rightInk = [self inkColumnsIn:[self exportOfText:right] top:100 height:40];
    XCTAssertTrue(leftInk.location < 110, @"Left-aligned text starts at the box's left edge");
    XCTAssertEqualWithAccuracy(NSMidX(NSMakeRect(centreInk.location, 0, centreInk.length, 1)), 300.0, 6.0,
                               @"Centred text sits in the middle of the 400pt box");
    XCTAssertTrue(NSMaxRange(rightInk) > 490 && NSMaxRange(rightInk) <= 501, @"Right-aligned text ends at the box's right edge");

    XCTAssertEqualWithAccuracy(NSMaxX([right textBounds]), 500.0, 1.0, @"textBounds follows the aligned line, for hit-testing");
    XCTAssertTrue([right containsPoint:NSMakePoint(495.0, 110.0)]);
    XCTAssertFalse([right containsPoint:NSMakePoint(110.0, 110.0)], @"Empty space at the left of right-aligned text isn't hit");
}

- (void)testAlignmentCodesRoundTripAndCopiesKeepIt {
    for (NSNumber *value in @[@(NSTextAlignmentLeft), @(NSTextAlignmentCenter), @(NSTextAlignmentRight)]) {
        NSTextAlignment alignment = (NSTextAlignment)value.integerValue;
        XCTAssertEqual(STTextAlignmentFromCode(STTextAlignmentCode(alignment)), alignment);
    }
    XCTAssertEqual(STTextAlignmentCode(NSTextAlignmentCenter), 1, @"Stored codes don't depend on the platform's raw values");
    MarkupText *right = [self fixedLabel:@"Hi" alignment:NSTextAlignmentRight];
    XCTAssertEqual(((MarkupText *)[right copy]).alignment, NSTextAlignmentRight);
}

#pragma mark - #34 text toolbar

- (void)testToolbarAppearsWhileEditingAndKeepsFocusInTheText {
    if (_shouldSkip) return;
    ScreenshotCanvasView *canvas = [self editingCanvas];
    [canvas beginTextEntryWithImageRect:NSMakeRect(100.0, 250.0, 1.0, 1.0) existingText:nil];
    [canvas.activeTextView insertText:@"Label"];

    STTextOptionsBar *bar = _appDelegate.textOptionsBar;
    XCTAssertNotNil(bar);
    XCTAssertFalse(bar.isHidden, @"The text toolbar shows while a box is being edited");
    for (NSView *control in [bar visibleControls]) {
        XCTAssertFalse([control acceptsFirstResponder], @"%@ must not take focus from the text box", control);
    }

    [_appDelegate textOptionsBar:bar didPickStyle:MarkupTextStyleBackground];
    [_appDelegate textOptionsBar:bar didPickAlignment:NSTextAlignmentCenter];
    XCTAssertNotNil(canvas.activeTextView, @"Using the toolbar keeps the box open");
    XCTAssertEqual([canvas activeTextEntry].style, MarkupTextStyleBackground, @"The toolbar restyles the box being edited");
    XCTAssertEqual([canvas activeTextEntry].alignment, NSTextAlignmentCenter);

    CGFloat before = [canvas activeTextEntry].font.pointSize;
    [_appDelegate textOptionsBar:bar didStepSizeBy:2.0];
    XCTAssertEqualWithAccuracy([canvas activeTextEntry].font.pointSize, before + 2.0, 0.01, @"A+ steps the size");
    XCTAssertEqual(canvas.textSizePreset, STTextSizePresetExact, @"Stepping picks an exact size");

    [canvas commitActiveTextIfNeeded];
    XCTAssertTrue(bar.isHidden, @"The toolbar goes away when editing ends");
}

- (void)testToolbarTakesItsOwnRowWithoutRescalingTheImage {
    if (_shouldSkip) return;
    ScreenshotCanvasView *canvas = [self editingCanvas];
    canvas.fitToWindow = YES;
    [canvas updateForEnclosingBoundsChange];
    CGFloat zoomBefore = canvas.zoomScale;
    NSRect scrollBefore = _appDelegate.scrollView.frame;

    [canvas beginTextEntryWithImageRect:NSMakeRect(100.0, 5.0, 1.0, 1.0) existingText:nil];
    [canvas.activeTextView insertText:@"Top"];
    STTextOptionsBar *bar = _appDelegate.textOptionsBar;
    XCTAssertFalse(NSIntersectsRect(bar.frame, _appDelegate.scrollView.frame),
                   @"The toolbar has its own row and never covers the canvas or the box being edited");
    XCTAssertEqualWithAccuracy(NSHeight(_appDelegate.scrollView.frame), NSHeight(scrollBefore) - [STTextOptionsBar preferredHeight], 0.5);
    XCTAssertEqualWithAccuracy(canvas.zoomScale, zoomBefore, 0.0001, @"Showing the row doesn't rescale the image");

    [canvas commitActiveTextIfNeeded];
    XCTAssertEqualWithAccuracy(NSHeight(_appDelegate.scrollView.frame), NSHeight(scrollBefore), 0.5, @"The canvas gets its space back");
}

- (void)testNarrowToolbarKeepsTheMostUsedControls {
    if (_shouldSkip) return;
    STTextOptionsBar *wide = [[STTextOptionsBar alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1200.0, 40.0)];
    STTextOptionsBar *narrow = [[STTextOptionsBar alloc] initWithFrame:NSMakeRect(0.0, 0.0, 420.0, 40.0)];
    XCTAssertTrue([narrow visibleControls].count < [wide visibleControls].count, @"A narrow bar drops lower-priority groups");
    STTextOptionsBar *typical = [[STTextOptionsBar alloc] initWithFrame:NSMakeRect(0.0, 0.0, 860.0, 40.0)];
    XCTAssertEqual([typical visibleControls].count, [wide visibleControls].count,
                   @"At a typical 860pt window every group, alignment included, fits");
    NSView *firstWide = [wide visibleControls].firstObject;
    NSView *firstNarrow = [narrow visibleControls].firstObject;
    XCTAssertEqualObjects(NSStringFromClass([firstNarrow class]), NSStringFromClass([firstWide class]),
                          @"Colour swatches, the highest priority, stay");
}

- (void)testControlBTogglesBoldWhileEditing {
    if (_shouldSkip) return;
    ScreenshotCanvasView *canvas = [self editingCanvas];
    [canvas beginTextEntryWithImageRect:NSMakeRect(100.0, 250.0, 1.0, 1.0) existingText:nil];
    [canvas.activeTextView insertText:@"Bold?"];
    NSFont *before = [canvas activeTextEntry].font;
    NSFont *boldVersion = [[NSFontManager sharedFontManager] convertFont:before toHaveTrait:NSBoldFontMask];
    if ([boldVersion.fontName isEqualToString:before.fontName]) {
        NSLog(@"Skipping bold check: %@ has no bold face here", before.familyName);
        return;
    }

    NSString *b = @"b";
    NSEvent *event = [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagControl
                                     timestamp:0 windowNumber:[canvas.window windowNumber] context:nil
                                    characters:b charactersIgnoringModifiers:b isARepeat:NO keyCode:0];
    [canvas.activeTextView keyDown:event];
    NSFontTraitMask traits = [[NSFontManager sharedFontManager] traitsOfFont:[canvas activeTextEntry].font];
    XCTAssertTrue((traits & NSBoldFontMask) != 0, @"Ctrl+B makes the box bold");
    XCTAssertEqualObjects(canvas.activeTextView.string, @"Bold?", @"Ctrl+B doesn't type a 'b'");
    [canvas commitActiveTextIfNeeded];
}

@end
