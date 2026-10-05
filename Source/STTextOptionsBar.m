/*
 * STTextOptionsBar.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import "STTextOptionsBar.h"
#import "STThemeUtilities.h"

static const CGFloat STTextOptionsBarHeight = 40.0;
static const CGFloat STTextOptionsBarPadding = 10.0;
static const CGFloat STTextOptionsBarGroupGap = 10.0;
static const CGFloat STTextOptionsBarControlHeight = 26.0;

/// A round colour swatch with a ring when it's the current colour.
@interface STTextOptionsSwatch : NSButton
@property (nonatomic, strong) NSColor *swatchColor;
@property (nonatomic, assign) BOOL current;
@end

@implementation STTextOptionsSwatch

- (BOOL)acceptsFirstResponder {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect dot = NSInsetRect(self.bounds, 4.0, 4.0);
    if (self.current) {
        [STThemeAccentColor() setStroke];
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(self.bounds, 1.0, 1.0)];
        [ring setLineWidth:2.0];
        [ring stroke];
    }
    [(self.swatchColor ?: [NSColor blackColor]) setFill];
    [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
    [STThemeHairlineColor() setStroke];
    [[NSBezierPath bezierPathWithOvalInRect:dot] stroke];
}

@end

@interface STTextOptionsBar ()
@property (nonatomic, strong) NSArray<STTextOptionsSwatch *> *swatches;
@property (nonatomic, strong) NSSegmentedControl *sizePresets;
@property (nonatomic, strong) NSButton *smallerButton;
@property (nonatomic, strong) NSButton *biggerButton;
@property (nonatomic, strong) NSPopUpButton *stylePopUp;
@property (nonatomic, strong) NSButton *pointerButton;
@property (nonatomic, strong) NSPopUpButton *fontPopUp;
@property (nonatomic, strong) NSButton *boldButton;
@property (nonatomic, strong) NSButton *italicButton;
@property (nonatomic, strong) NSSegmentedControl *alignmentControl;
/// Control groups in priority order; trailing groups are hidden when the bar is too narrow.
@property (nonatomic, strong) NSArray<NSArray<NSView *> *> *groups;
@end

@implementation STTextOptionsBar

+ (CGFloat)preferredHeight {
    return STTextOptionsBarHeight;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self buildControls];
        [self layoutControls];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return NO;
}

#pragma mark - Building

- (void)prepareControl:(NSControl *)control toolTip:(NSString *)toolTip {
    // Clicking must not take focus from the text box being edited.
    [control setRefusesFirstResponder:YES];
    [control setToolTip:toolTip];
    [control setTarget:self];
    [self addSubview:control];
}

- (NSButton *)smallButtonWithTitle:(NSString *)title action:(SEL)action toolTip:(NSString *)toolTip {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 28.0, STTextOptionsBarControlHeight)];
    [button setTitle:title];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setFont:[NSFont systemFontOfSize:12.0]];
    [button setAction:action];
    [self prepareControl:button toolTip:toolTip];
    return button;
}

- (void)buildControls {
    NSArray<NSColor *> *colors = @[
        [NSColor colorWithDeviceRed:0.90 green:0.11 blue:0.14 alpha:1.0],
        [NSColor colorWithDeviceRed:0.96 green:0.83 blue:0.18 alpha:1.0],
        [NSColor colorWithDeviceRed:0.21 green:0.52 blue:0.89 alpha:1.0],
        [NSColor colorWithDeviceRed:0.18 green:0.76 blue:0.49 alpha:1.0],
        [NSColor blackColor],
        [NSColor whiteColor],
    ];
    NSMutableArray<STTextOptionsSwatch *> *swatches = [[NSMutableArray alloc] init];
    for (NSUInteger idx = 0; idx < colors.count; idx++) {
        STTextOptionsSwatch *swatch = [[STTextOptionsSwatch alloc] initWithFrame:NSMakeRect(0.0, 0.0, 22.0, 24.0)];
        [swatch setBordered:NO];
        swatch.swatchColor = colors[idx];
        swatch.tag = (NSInteger)idx;
        [swatch setAction:@selector(swatchPressed:)];
        [self prepareControl:swatch toolTip:@"Text colour"];
        [swatches addObject:swatch];
    }
    self.swatches = swatches;

    self.sizePresets = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0.0, 0.0, 112.0, STTextOptionsBarControlHeight)];
    NSArray<NSString *> *presetTitles = @[@"S", @"M", @"L", @"XL"];
    [self.sizePresets setSegmentCount:(NSInteger)presetTitles.count];
    [self.sizePresets setFont:[NSFont systemFontOfSize:11.0]];
    for (NSUInteger idx = 0; idx < presetTitles.count; idx++) {
        [self.sizePresets setLabel:presetTitles[idx] forSegment:(NSInteger)idx];
        [self.sizePresets setWidth:28.0 forSegment:(NSInteger)idx];
    }
    [self.sizePresets setAction:@selector(sizePresetChanged:)];
    [self prepareControl:self.sizePresets toolTip:@"Size relative to the image"];
    self.smallerButton = [self smallButtonWithTitle:@"A-" action:@selector(smallerPressed:) toolTip:@"Smaller (Ctrl+Shift+<)"];
    self.biggerButton = [self smallButtonWithTitle:@"A+" action:@selector(biggerPressed:) toolTip:@"Bigger (Ctrl+Shift+>)"];

    self.stylePopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 88.0, STTextOptionsBarControlHeight) pullsDown:NO];
    [self.stylePopUp addItemsWithTitles:@[@"Plain", @"Outline", @"Shadow", @"Box"]];
    [self.stylePopUp setFont:[NSFont systemFontOfSize:12.0]];
    [self.stylePopUp setAction:@selector(styleChanged:)];
    [self prepareControl:self.stylePopUp toolTip:@"Text style"];

    self.pointerButton = [self smallButtonWithTitle:@"Pointer" action:@selector(pointerPressed:) toolTip:@"Callout pointer — drag its handle to aim it"];
    [self.pointerButton setFrameSize:NSMakeSize(60.0, STTextOptionsBarControlHeight)];
    [self.pointerButton setFont:[NSFont systemFontOfSize:11.0]];
    [self.pointerButton setButtonType:NSPushOnPushOffButton];

    self.fontPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 110.0, STTextOptionsBarControlHeight) pullsDown:NO];
    NSArray<NSString *> *families = [[[NSFontManager sharedFontManager] availableFontFamilies]
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [self.fontPopUp addItemsWithTitles:families ?: @[]];
    [self.fontPopUp setFont:[NSFont systemFontOfSize:12.0]];
    [self.fontPopUp setAction:@selector(fontChanged:)];
    [self prepareControl:self.fontPopUp toolTip:@"Font"];

    self.boldButton = [self smallButtonWithTitle:@"B" action:@selector(boldPressed:) toolTip:@"Bold (Ctrl+B)"];
    [self.boldButton setFont:[NSFont boldSystemFontOfSize:12.0]];
    [self.boldButton setButtonType:NSPushOnPushOffButton];
    self.italicButton = [self smallButtonWithTitle:@"I" action:@selector(italicPressed:) toolTip:@"Italic (Ctrl+I)"];
    [self.italicButton setButtonType:NSPushOnPushOffButton];

    self.alignmentControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0.0, 0.0, 126.0, STTextOptionsBarControlHeight)];
    NSArray<NSString *> *alignTitles = @[@"Left", @"Centre", @"Right"];
    [self.alignmentControl setSegmentCount:(NSInteger)alignTitles.count];
    [self.alignmentControl setFont:[NSFont systemFontOfSize:11.0]];
    for (NSUInteger idx = 0; idx < alignTitles.count; idx++) {
        [self.alignmentControl setLabel:alignTitles[idx] forSegment:(NSInteger)idx];
        [self.alignmentControl setWidth:42.0 forSegment:(NSInteger)idx];
    }
    [self.alignmentControl setAction:@selector(alignmentChanged:)];
    [self prepareControl:self.alignmentControl toolTip:@"Alignment"];

    self.groups = @[
        self.swatches,
        @[self.sizePresets, self.smallerButton, self.biggerButton],
        @[self.stylePopUp, self.pointerButton],
        @[self.fontPopUp],
        @[self.boldButton, self.italicButton],
        @[self.alignmentControl],
    ];
}

#pragma mark - Layout

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self layoutControls];
}

- (CGFloat)widthOfGroup:(NSArray<NSView *> *)group {
    CGFloat width = 0.0;
    for (NSView *view in group) {
        width += NSWidth(view.frame) + 4.0;
    }
    return width - 4.0;
}

- (void)layoutControls {
    CGFloat x = STTextOptionsBarPadding;
    CGFloat limit = NSWidth(self.bounds) - STTextOptionsBarPadding;
    BOOL fits = YES;
    for (NSArray<NSView *> *group in self.groups) {
        CGFloat width = [self widthOfGroup:group];
        // Groups go in priority order; once one doesn't fit, it and the rest are hidden.
        fits = fits && (x + width <= limit);
        for (NSView *view in group) {
            [view setHidden:!fits];
            if (fits) {
                CGFloat y = floor((STTextOptionsBarHeight - NSHeight(view.frame)) * 0.5);
                [view setFrameOrigin:NSMakePoint(x, y)];
                x += NSWidth(view.frame) + 4.0;
            }
        }
        if (fits) {
            x += STTextOptionsBarGroupGap - 4.0;
        }
    }
    [self setNeedsDisplay:YES];
}

- (NSArray<NSView *> *)visibleControls {
    NSMutableArray<NSView *> *visible = [[NSMutableArray alloc] init];
    for (NSArray<NSView *> *group in self.groups) {
        for (NSView *view in group) {
            if (!view.isHidden) {
                [visible addObject:view];
            }
        }
    }
    return visible;
}

// No background or separator lines of its own: the bar sits on the window, drawn by the theme (#67).
#pragma mark - State

static BOOL STTextOptionsColorsMatch(NSColor *a, NSColor *b) {
    NSColor *ca = [a colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    NSColor *cb = [b colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    if (!ca || !cb) {
        return NO;
    }
    return fabs(ca.redComponent - cb.redComponent) < 0.02 &&
           fabs(ca.greenComponent - cb.greenComponent) < 0.02 &&
           fabs(ca.blueComponent - cb.blueComponent) < 0.02;
}

- (void)updateWithFont:(NSFont *)font
                 color:(NSColor *)color
                 style:(MarkupTextStyle)style
            sizePreset:(STTextSizePreset)sizePreset
             alignment:(NSTextAlignment)alignment
         boldAvailable:(BOOL)boldAvailable
       italicAvailable:(BOOL)italicAvailable {
    for (STTextOptionsSwatch *swatch in self.swatches) {
        swatch.current = STTextOptionsColorsMatch(swatch.swatchColor, color);
        [swatch setNeedsDisplay:YES];
    }

    if (sizePreset == STTextSizePresetExact) {
        for (NSInteger segment = 0; segment < self.sizePresets.segmentCount; segment++) {
            [self.sizePresets setSelected:NO forSegment:segment];
        }
    } else {
        [self.sizePresets setSelectedSegment:(NSInteger)sizePreset - 1];
    }
    [self.sizePresets setToolTip:[NSString stringWithFormat:@"Size relative to the image (now %.0f pt)", font.pointSize]];

    [self.stylePopUp selectItemAtIndex:MAX(0, MIN((NSInteger)style, self.stylePopUp.numberOfItems - 1))];

    NSString *family = font.familyName;
    if (family.length > 0) {
        if ([self.fontPopUp indexOfItemWithTitle:family] < 0) {
            [self.fontPopUp addItemWithTitle:family];
        }
        [self.fontPopUp selectItemWithTitle:family];
    }

    NSFontTraitMask traits = [[NSFontManager sharedFontManager] traitsOfFont:font];
    [self.boldButton setState:((traits & NSBoldFontMask) ? NSOnState : NSOffState)];
    [self.italicButton setState:((traits & NSItalicFontMask) ? NSOnState : NSOffState)];
    [self.boldButton setEnabled:boldAvailable || (traits & NSBoldFontMask)];
    [self.italicButton setEnabled:italicAvailable || (traits & NSItalicFontMask)];

    [self.alignmentControl setSelectedSegment:STTextAlignmentCode(alignment)];
}

#pragma mark - Actions

- (void)swatchPressed:(STTextOptionsSwatch *)sender {
    [self.delegate textOptionsBar:self didPickColor:sender.swatchColor];
}

- (void)sizePresetChanged:(NSSegmentedControl *)sender {
    NSInteger selected = [sender selectedSegment];
    if (selected >= 0) {
        [self.delegate textOptionsBar:self didPickSizePreset:(STTextSizePreset)(selected + 1)];
    }
}

- (void)smallerPressed:(id)sender {
    (void)sender;
    [self.delegate textOptionsBar:self didStepSizeBy:-2.0];
}

- (void)biggerPressed:(id)sender {
    (void)sender;
    [self.delegate textOptionsBar:self didStepSizeBy:2.0];
}

- (void)styleChanged:(NSPopUpButton *)sender {
    [self.delegate textOptionsBar:self didPickStyle:(MarkupTextStyle)[sender indexOfSelectedItem]];
}

- (void)setPointerOn:(BOOL)on available:(BOOL)available {
    [self.pointerButton setState:on ? NSOnState : NSOffState];
    [self.pointerButton setEnabled:available];
}

- (void)pointerPressed:(id)sender {
    (void)sender;
    [self.delegate textOptionsBarDidTogglePointer:self];
}

- (void)fontChanged:(NSPopUpButton *)sender {
    NSString *family = [sender titleOfSelectedItem];
    if (family.length > 0) {
        [self.delegate textOptionsBar:self didPickFontFamily:family];
    }
}

- (void)boldPressed:(id)sender {
    (void)sender;
    [self.delegate textOptionsBarDidToggleBold:self];
}

- (void)italicPressed:(id)sender {
    (void)sender;
    [self.delegate textOptionsBarDidToggleItalic:self];
}

- (void)alignmentChanged:(NSSegmentedControl *)sender {
    NSInteger selected = [sender selectedSegment];
    if (selected >= 0) {
        [self.delegate textOptionsBar:self didPickAlignment:STTextAlignmentFromCode(selected)];
    }
}

@end
