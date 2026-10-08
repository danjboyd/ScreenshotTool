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
#import "STFontFamilyList.h"
#import "STThemeUtilities.h"
#import "STSegmentToolTips.h"
#import <objc/runtime.h>

/// "Bold (Ctrl+B)" on GNUstep, "Bold (⌘B)" on macOS.
static NSString *STShortcutToolTip(NSString *title, NSString *gnustepShortcut, NSString *macShortcut) {
#if defined(GNUSTEP)
    (void)macShortcut;
    return [NSString stringWithFormat:@"%@ (%@)", title, gnustepShortcut];
#else
    (void)gnustepShortcut;
    return [NSString stringWithFormat:@"%@ (%@)", title, macShortcut];
#endif
}

static const CGFloat STTextOptionsBarPadding = 10.0;
static const CGFloat STTextOptionsBarGroupGap = 10.0;
/// Space above and below the controls.
static const CGFloat STTextOptionsBarMargin = 7.0;
/// The smallest control height, and the smallest a small button is wide.
static const CGFloat STTextOptionsBarMinControlHeight = 26.0;

/// The theme's control height: what a push button asks for in the theme's font.
static CGFloat STTextOptionsBarControlHeight(void) {
    NSButton *probe = [[NSButton alloc] initWithFrame:NSZeroRect];
    [probe setBezelStyle:NSRoundedBezelStyle];
    [probe setTitle:@"A"];
    return MAX(STTextOptionsBarMinControlHeight, ceil([[probe cell] cellSize].height));
}

/// Sizes each segment of a text-labelled segmented control to its label in the control's font, and
/// the control to its segments.
static void STTextOptionsBarSizeSegments(NSSegmentedControl *control, CGFloat minimumWidth, CGFloat height) {
    NSDictionary *attributes = @{NSFontAttributeName: [control font] ?: [NSFont systemFontOfSize:0.0]};
    CGFloat total = 0.0;
    for (NSInteger segment = 0; segment < [control segmentCount]; segment++) {
        NSString *label = [control labelForSegment:segment] ?: @"";
        CGFloat width = MAX(minimumWidth, ceil([label sizeWithAttributes:attributes].width) + 12.0);
        [control setWidth:width forSegment:segment];
        total += width;
    }
    [control setFrameSize:NSMakeSize(total, height)];
}

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

@interface STTextOptionsBar () <NSComboBoxDataSource, NSComboBoxDelegate>
@property (nonatomic, strong) NSArray<STTextOptionsSwatch *> *swatches;
@property (nonatomic, strong) NSSegmentedControl *sizePresets;
@property (nonatomic, strong) NSButton *smallerButton;
@property (nonatomic, strong) NSButton *biggerButton;
@property (nonatomic, strong) NSSegmentedControl *styleControl;
@property (nonatomic, strong) NSButton *pointerButton;
@property (nonatomic, strong) NSComboBox *fontField;
@property (nonatomic, strong) STFontFamilyList *fontFamilies;
@property (nonatomic, copy) NSString *shownFontFamily;
@property (nonatomic, assign) BOOL takingTextFocus;
@property (nonatomic, strong) NSButton *boldButton;
@property (nonatomic, strong) NSButton *italicButton;
@property (nonatomic, strong) NSSegmentedControl *alignmentControl;
/// Control groups in priority order; trailing groups are hidden when the bar is too narrow.
@property (nonatomic, strong) NSArray<NSArray<NSView *> *> *groups;
@end

/// The dark grey of GNOME's symbolic icons, which the app's other symbolic icons use.
static NSColor *STSymbolicIconColor(void) {
    return [NSColor colorWithDeviceRed:61.0 / 255.0 green:56.0 / 255.0 blue:70.0 / 255.0 alpha:1.0];
}

/// An "A" drawn in a text style, as a symbolic icon for the style control: plain, outlined, with
/// a shadow, or cut out of a box. Named -symbolic so themes that tint icons tint it (#51, #57).
static NSImage *STTextStyleSampleImage(MarkupTextStyle style) {
    // Made once per style: an image name can belong to only one image.
    static NSImage *samples[4];
    NSInteger index = MAX(0, MIN((NSInteger)style, 3));
    if (samples[index]) {
        return samples[index];
    }
    NSString *names[] = {@"Plain", @"Outline", @"Shadow", @"Box"};
    NSSize size = NSMakeSize(18.0, 16.0);
    NSRect bounds = NSMakeRect(0.0, 0.0, size.width, size.height);
    NSColor *ink = STSymbolicIconColor();

    // The letter on its own, composited below: GNUstep has no glyph outlines to stroke here.
    NSImage *letter = [[NSImage alloc] initWithSize:size];
    NSDictionary *attributes = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:13.0],
                                 NSForegroundColorAttributeName: ink};
    NSSize letterSize = [@"A" sizeWithAttributes:attributes];
    [letter lockFocus];
    [@"A" drawAtPoint:NSMakePoint(floor((size.width - letterSize.width) * 0.5), floor((size.height - letterSize.height) * 0.5))
       withAttributes:attributes];
    [letter unlockFocus];

    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    switch (style) {
        case MarkupTextStyleOutline:
            // The letter spread by a pixel each way, its middle cut out.
            for (NSInteger dx = -1; dx <= 1; dx++) {
                for (NSInteger dy = -1; dy <= 1; dy++) {
                    if (dx != 0 || dy != 0) {
                        [letter drawInRect:NSOffsetRect(bounds, dx, dy) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
                    }
                }
            }
            [letter drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationOut fraction:1.0];
            break;
        case MarkupTextStyleShadow:
            [letter drawInRect:NSOffsetRect(bounds, 1.5, -1.5) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:0.45];
            [letter drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
            break;
        case MarkupTextStyleBackground:
            [ink setFill];
            [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:3.0 yRadius:3.0] fill];
            [letter drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeDestinationOut fraction:1.0];
            break;
        case MarkupTextStylePlain:
        default:
            [letter drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
            break;
    }
    [image unlockFocus];
    [image setName:[NSString stringWithFormat:@"ScreenshotToolTextStyle%@-symbolic", names[index]]];
    samples[index] = image;
    return image;
}

#if defined(GNUSTEP)
/// Lines of text set left, centred or right, as a symbolic icon for the alignment control: words
/// don't fit a narrow bar in larger theme fonts. Named -symbolic so themes that tint icons tint it.
static NSImage *STTextAlignmentImage(NSInteger index) {
    // Made once per alignment: an image name can belong to only one image.
    static NSImage *images[3];
    index = MAX(0, MIN(index, 2));
    if (images[index]) {
        return images[index];
    }
    NSString *names[] = {@"Left", @"Centre", @"Right"};
    CGFloat lengths[] = {14.0, 9.0, 12.0, 7.0};
    NSSize size = NSMakeSize(16.0, 14.0);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [STSymbolicIconColor() setFill];
    for (NSInteger line = 0; line < 4; line++) {
        CGFloat length = lengths[line];
        CGFloat x = 1.0;
        if (index == 1) {
            x = floor((size.width - length) * 0.5);
        } else if (index == 2) {
            x = size.width - 1.0 - length;
        }
        NSRectFill(NSMakeRect(x, size.height - 2.0 - (3.5 * line) - 2.0, length, 2.0));
    }
    [image unlockFocus];
    [image setName:[NSString stringWithFormat:@"ScreenshotToolTextAlign%@-symbolic", names[index]]];
    images[index] = image;
    return image;
}
#endif

/// The font field: an editable combo box that, unlike the bar's other controls, takes the keyboard.
/// It says so as AppKit asks, which is before the text box gives the keyboard up.
@interface STFontComboBox : NSComboBox
@property (nonatomic, copy, nullable) void (^willTakeFocus)(void);
@end

@implementation STFontComboBox
- (BOOL)acceptsFirstResponder {
    BOOL accepts = [super acceptsFirstResponder];
    if (accepts && self.willTakeFocus && ![self currentEditor]) {
        self.willTakeFocus();
    }
    return accepts;
}
@end

@implementation STTextOptionsBar

+ (CGFloat)preferredHeight {
    return STTextOptionsBarControlHeight() + (2.0 * STTextOptionsBarMargin);
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

/// As wide as its title needs in its font, and at least 28pt: measured from the text rather than the
/// cell, whose bezel padding (macOS's and WinUI's are wide) would push the bar past a typical window.
- (void)sizeButtonToTitle:(NSButton *)button {
    NSDictionary *attributes = @{NSFontAttributeName: [button font] ?: [NSFont systemFontOfSize:0.0]};
    CGFloat width = ceil([[button title] sizeWithAttributes:attributes].width) + 14.0;
    [button setFrameSize:NSMakeSize(MAX(28.0, width), NSHeight([button frame]))];
}

- (NSButton *)smallButtonWithTitle:(NSString *)title action:(SEL)action toolTip:(NSString *)toolTip {
    CGFloat height = STTextOptionsBarControlHeight();
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 28.0, height)];
    [button setTitle:title];
    [button setBezelStyle:NSRoundedBezelStyle];
    [self sizeButtonToTitle:button];
    [button setAction:action];
    [self prepareControl:button toolTip:toolTip];
    return button;
}

- (void)buildControls {
    CGFloat controlHeight = STTextOptionsBarControlHeight();
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

    self.sizePresets = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0.0, 0.0, 112.0, controlHeight)];
    NSArray<NSString *> *presetTitles = @[@"S", @"M", @"L", @"XL"];
    [self.sizePresets setSegmentCount:(NSInteger)presetTitles.count];
    for (NSUInteger idx = 0; idx < presetTitles.count; idx++) {
        [self.sizePresets setLabel:presetTitles[idx] forSegment:(NSInteger)idx];
    }
    STTextOptionsBarSizeSegments(self.sizePresets, 28.0, controlHeight);
    [self.sizePresets setAction:@selector(sizePresetChanged:)];
    [self prepareControl:self.sizePresets toolTip:@"Size relative to the image"];
    self.smallerButton = [self smallButtonWithTitle:@"A-" action:@selector(smallerPressed:) toolTip:STShortcutToolTip(@"Smaller", @"Ctrl+Shift+<", @"⇧⌘<")];
    self.biggerButton = [self smallButtonWithTitle:@"A+" action:@selector(biggerPressed:) toolTip:STShortcutToolTip(@"Bigger", @"Ctrl+Shift+>", @"⇧⌘>")];

    // Segments rather than a pop-up: one click to choose, and no menu, which flickered while a
    // text box was being edited (#102). Each segment shows its style on an "A"; tool tips name them.
    NSArray<NSString *> *styleNames = @[@"Plain", @"Outline", @"Shadow", @"Box"];
    self.styleControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0.0, 0.0, 4.0 * 22.0 + 4.0, controlHeight)];
    [self.styleControl setSegmentCount:(NSInteger)styleNames.count];
    for (NSUInteger idx = 0; idx < styleNames.count; idx++) {
        [self.styleControl setImage:STTextStyleSampleImage((MarkupTextStyle)idx) forSegment:(NSInteger)idx];
        [self.styleControl setLabel:@"" forSegment:(NSInteger)idx];
        [self.styleControl setWidth:22.0 forSegment:(NSInteger)idx];
        [[self.styleControl cell] setToolTip:styleNames[idx] forSegment:(NSInteger)idx];
    }
    [self.styleControl setAction:@selector(styleChanged:)];
    [self prepareControl:self.styleControl toolTip:nil];
    STInstallSegmentToolTips(self.styleControl);

    self.pointerButton = [self smallButtonWithTitle:@"Pointer" action:@selector(pointerPressed:) toolTip:@"Callout pointer — drag its handle to aim it"];
    [self.pointerButton setButtonType:NSPushOnPushOffButton];

    // An editable combo box: type part of a name to complete it (any installed family), or pick
    // from a scrolling list of recent fonts and those for the user's language (#103). The list is
    // its data source, so thousands of families cost nothing until it opens.
    self.fontFamilies = [[STFontFamilyList alloc] init];
    STFontComboBox *fontField = [[STFontComboBox alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, controlHeight)];
    [fontField setUsesDataSource:YES];
    [fontField setDataSource:self];
    [fontField setDelegate:self];
    [fontField setCompletes:YES];
    [fontField setNumberOfVisibleItems:12];
    [fontField setAction:@selector(fontEntered:)];
    __weak STTextOptionsBar *weakSelf = self;
    fontField.willTakeFocus = ^{
        [weakSelf noteTakingTextFocus];
    };
    self.fontField = fontField;
    [self prepareControl:self.fontField toolTip:@"Font: type a name, or pick from recent fonts and fonts for your language"];
    [self.fontField setRefusesFirstResponder:NO];

    self.boldButton = [self smallButtonWithTitle:@"B" action:@selector(boldPressed:) toolTip:STShortcutToolTip(@"Bold", @"Ctrl+B", @"⌘B")];
    // An explicit size: macOS draws a button's boldSystemFontOfSize:0 in regular weight.
    [self.boldButton setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
    [self sizeButtonToTitle:self.boldButton];
    [self.boldButton setButtonType:NSPushOnPushOffButton];
    self.italicButton = [self smallButtonWithTitle:@"I" action:@selector(italicPressed:) toolTip:STShortcutToolTip(@"Italic", @"Ctrl+I", @"⌘I")];
    [self.italicButton setButtonType:NSPushOnPushOffButton];

    self.alignmentControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0.0, 0.0, 126.0, controlHeight)];
    NSArray<NSString *> *alignTitles = @[@"Left", @"Centre", @"Right"];
    [self.alignmentControl setSegmentCount:(NSInteger)alignTitles.count];
    for (NSUInteger idx = 0; idx < alignTitles.count; idx++) {
#if defined(GNUSTEP)
        [self.alignmentControl setImage:STTextAlignmentImage((NSInteger)idx) forSegment:(NSInteger)idx];
        [self.alignmentControl setLabel:@"" forSegment:(NSInteger)idx];
        [self.alignmentControl setWidth:28.0 forSegment:(NSInteger)idx];
        [[self.alignmentControl cell] setToolTip:[NSString stringWithFormat:@"Align %@", alignTitles[idx]] forSegment:(NSInteger)idx];
#else
        // The system's alignment symbols, as in macOS's own text bars; the words don't fit 42pt
        // in macOS's system font.
        NSArray<NSString *> *symbols = @[@"text.alignleft", @"text.aligncenter", @"text.alignright"];
        NSImage *image = [NSImage imageWithSystemSymbolName:symbols[idx] accessibilityDescription:alignTitles[idx]];
        if (image) {
            [self.alignmentControl setImage:image forSegment:(NSInteger)idx];
            [self.alignmentControl setWidth:32.0 forSegment:(NSInteger)idx];
        } else {
            [self.alignmentControl setLabel:alignTitles[idx] forSegment:(NSInteger)idx];
            [self.alignmentControl setWidth:42.0 forSegment:(NSInteger)idx];
        }
        [self.alignmentControl setToolTip:[NSString stringWithFormat:@"Align %@", alignTitles[idx]] forSegment:(NSInteger)idx];
#endif
    }
#if defined(GNUSTEP)
    [self.alignmentControl setFrameSize:NSMakeSize(3.0 * 28.0, controlHeight)];
#else
    [self.alignmentControl sizeToFit];
#endif
    [self.alignmentControl setAction:@selector(alignmentChanged:)];
    [self prepareControl:self.alignmentControl toolTip:@"Alignment"];
#if defined(GNUSTEP)
    STInstallSegmentToolTips(self.alignmentControl);
#endif

    self.groups = @[
        self.swatches,
        @[self.sizePresets, self.smallerButton, self.biggerButton],
        @[self.styleControl, self.pointerButton],
        @[self.fontField],
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
                CGFloat y = floor((NSHeight(self.bounds) - NSHeight(view.frame)) * 0.5);
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

    [self.styleControl setSelectedSegment:MAX(0, MIN((NSInteger)style, self.styleControl.segmentCount - 1))];

    NSString *family = font.familyName;
    if (family.length > 0) {
        self.shownFontFamily = family;
        // Not while a name is being typed there.
        if (![self.fontField currentEditor]) {
            [self.fontField setStringValue:[STFontFamilyList displayNameForFamily:family]];
        }
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

- (void)styleChanged:(NSSegmentedControl *)sender {
    [self.delegate textOptionsBar:self didPickStyle:(MarkupTextStyle)[sender selectedSegment]];
}

- (void)setPointerOn:(BOOL)on available:(BOOL)available {
    [self.pointerButton setState:on ? NSOnState : NSOffState];
    [self.pointerButton setEnabled:available];
}

- (void)pointerPressed:(id)sender {
    (void)sender;
    [self.delegate textOptionsBarDidTogglePointer:self];
}

#pragma mark - Font field

- (void)noteTakingTextFocus {
    // Until the next turn of the run loop: long enough for the text box to give the keyboard up.
    self.takingTextFocus = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearTakingTextFocus) object:nil];
    [self performSelector:@selector(clearTakingTextFocus) withObject:nil afterDelay:0.0];
}

- (void)clearTakingTextFocus {
    self.takingTextFocus = NO;
}

- (BOOL)isTakingTextFocus {
    return self.takingTextFocus;
}

/// Uses `family` for the text, remembers it as recent, and gives the keyboard back.
- (void)chooseFontFamily:(NSString *)family {
    NSString *installed = [self.fontFamilies familyNamed:family];
    if (installed) {
        [self.fontFamilies noteUsedFamily:installed];
        [self.fontField reloadData];
        self.shownFontFamily = installed;
        [self.delegate textOptionsBar:self didPickFontFamily:installed];
    }
    [self finishFontEntry];
}

/// Gives the keyboard back to the text box, then shows the text's font: set while the field is
/// still being edited, the value would lose to the typed text.
- (void)finishFontEntry {
    if ([self.delegate respondsToSelector:@selector(textOptionsBarDidFinishFontEntry:)]) {
        [self.delegate textOptionsBarDidFinishFontEntry:self];
    }
    if ([self.fontField currentEditor]) {
        [[self.fontField window] endEditingFor:self.fontField];
    }
    [self.fontField setStringValue:[STFontFamilyList displayNameForFamily:self.shownFontFamily ?: @""]];
}

/// Return in the field: the typed name, or the family it completes to.
- (void)fontEntered:(id)sender {
    (void)sender;
    NSString *typed = self.fontField.stringValue ?: @"";
    NSString *family = [self.fontFamilies familyNamed:typed] ?: [self.fontFamilies completionForPrefix:typed];
    [self chooseFontFamily:family ?: @""];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    (void)textView;
    if (control != self.fontField) {
        return NO;
    }
    // Escape (GNUstep binds it to complete:; Cocoa sends cancelOperation:): keep the font.
    if (sel_isEqual(commandSelector, @selector(cancelOperation:)) || sel_isEqual(commandSelector, @selector(complete:))) {
        [self finishFontEntry];
        return YES;
    }
    return NO;
}

/// The list closed, perhaps without a choice (Escape there is the list's): show the text's font and
/// give the keyboard back. A choice has already done both.
- (void)comboBoxWillDismiss:(NSNotification *)notification {
    if (notification.object != self.fontField) {
        return;
    }
    [self performSelector:@selector(finishFontEntry) withObject:nil afterDelay:0.0];
}

- (void)comboBoxSelectionDidChange:(NSNotification *)notification {
    if (notification.object != self.fontField) {
        return;
    }
    // By index: in data-source mode GNUstep's -objectValueOfSelectedItem isn't available.
    NSInteger index = self.fontField.indexOfSelectedItem;
    NSArray<NSString *> *listed = self.fontFamilies.listedFamilies;
    if (index >= 0 && (NSUInteger)index < listed.count) {
        [self chooseFontFamily:listed[(NSUInteger)index]];
    }
}

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)comboBox {
    return comboBox == self.fontField ? (NSInteger)self.fontFamilies.listedFamilies.count : 0;
}

- (id)comboBox:(NSComboBox *)comboBox objectValueForItemAtIndex:(NSInteger)index {
    NSArray<NSString *> *listed = self.fontFamilies.listedFamilies;
    if (comboBox != self.fontField || index < 0 || (NSUInteger)index >= listed.count) {
        return nil;
    }
    return listed[(NSUInteger)index];
}

- (NSUInteger)comboBox:(NSComboBox *)comboBox indexOfItemWithStringValue:(NSString *)string {
    if (comboBox != self.fontField) {
        return NSNotFound;
    }
    NSString *family = [self.fontFamilies familyNamed:string];
    return family ? [self.fontFamilies.listedFamilies indexOfObject:family] : NSNotFound;
}

- (NSString *)comboBox:(NSComboBox *)comboBox completedString:(NSString *)string {
    return comboBox == self.fontField ? [self.fontFamilies completionForPrefix:string] : nil;
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
