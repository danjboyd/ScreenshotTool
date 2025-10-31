#import "TextToolPopoverController.h"
#import "STHyperlinkButton.h"
#import "ScreenshotToolSettings.h"
#import "AppDelegate.h"
#import "STFloatingResizablePopover.h"
#include <math.h>

#define STTextPopoverMinFontSize 8.0f
#define STTextPopoverMaxFontSize 128.0f

@class TextToolPopoverController;

@interface STTextPopoverContentView : NSView
@property (nonatomic, weak) TextToolPopoverController *owner;
@end

@implementation STTextPopoverContentView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)changeFont:(id)sender {
    if (self.owner && [self.owner respondsToSelector:@selector(fontPanelDidChange:)]) {
        [self.owner performSelector:@selector(fontPanelDidChange:) withObject:sender];
    }
}

@end

@interface TextToolPopoverController () <NSTextFieldDelegate, NSTextViewDelegate>
@property (nonatomic, strong) STFloatingResizablePopover *popover;
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSTextView *previewTextView;
@property (nonatomic, strong) NSColorWell *colorWell;
@property (nonatomic, strong) NSPopUpButton *fontPopUp;
@property (nonatomic, strong) NSTextField *fontSizeField;
@property (nonatomic, strong) NSStepper *fontSizeStepper;
@property (nonatomic, strong) NSButton *fontPanelButton;
@property (nonatomic, strong) STHyperlinkButton *resetButton;
@property (nonatomic, strong) STHyperlinkButton *defaultButton;
@property (nonatomic, strong) NSArray<NSButton *> *colorSwatchButtons;
@property (nonatomic, copy) NSArray<NSColor *> *colorSwatches;
@property (nonatomic, copy) NSString *previewSampleText;
@property (nonatomic, assign) CGFloat colorSwatchSize;
- (void)fontPanelDidChange:(NSFontManager *)manager;
@end

@implementation TextToolPopoverController

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge {
    if (!self.popover) {
        [self buildPopover];
    }
    [self refresh];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"TextToolPopoverController showRelativeToRect entry (popover=%@ isShown=%@)",
                             self.popover ? @"YES" : @"NO",
                             self.popover.isShown ? @"YES" : @"NO"]);
    if (self.popover.isShown) {
        ScreenshotToolAppendLog(@"TextToolPopoverController showRelativeToRect skipped because popover already shown");
        return;
    }
    ScreenshotToolAppendLog([NSString stringWithFormat:@"TextToolPopoverController showRelativeToRect requested (view=%@ rect=%@ edge=%ld)",
                             NSStringFromClass([view class]),
                             NSStringFromRect(rect),
                             (long)edge]);
    [self.popover showRelativeToRect:rect ofView:view preferredEdge:edge];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"TextToolPopoverController showRelativeToRect invoked (isShown=%@)",
                             self.popover.isShown ? @"YES" : @"NO"]);
}

- (void)close {
    if (!self.popover) {
        return;
    }
    if (!self.popover.isShown) {
        ScreenshotToolAppendLog(@"TextToolPopoverController close skipped (popover not shown)");
        return;
    }
    [self.popover close];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"TextToolPopoverController close invoked (wasShown=YES nowShown=%@)",
                             self.popover.isShown ? @"YES" : @"NO"]);
}

- (BOOL)isShown {
    return self.popover.isShown;
}

- (void)refresh {
    if (!self.popover) {
        return;
    }
    id<TextToolPopoverControllerDelegate> delegate = self.delegate;
    if (!delegate) {
        return;
    }

    NSColor *color = [delegate textToolPopoverCurrentColor:self] ?: STDefaultTextColor();
    NSColor *defaultColor = [delegate textToolPopoverDefaultColor:self] ?: STDefaultTextColor();
    NSFont *font = [delegate textToolPopoverCurrentFont:self] ?: STDefaultTextFont();
    NSFont *defaultFont = [delegate textToolPopoverDefaultFont:self] ?: STDefaultTextFont();

    [self.colorWell setColor:color];
    [self updateSwatchSelectionForColor:color];
    [self updateFontControlsWithFont:font];

    if (!self.previewSampleText) {
        self.previewSampleText = @"Sample Text";
    }
    [self.previewTextView setString:self.previewSampleText];
    [self updatePreviewWithFont:font color:color];

    BOOL canResetColor = ![self colorsEqual:color other:defaultColor];
    BOOL canResetFont = ![self fontsEqual:font other:defaultFont];
    BOOL enableActions = (canResetColor || canResetFont);
    [self.resetButton setEnabled:enableActions];
    [self.defaultButton setEnabled:enableActions];
}

#pragma mark - Private helpers

- (void)buildPopover {
    ScreenshotToolAppendLog(@"TextToolPopoverController buildPopover begin");
    CGFloat popoverWidth = 320.0f;
    CGFloat popoverHeight = 270.0f;

    STTextPopoverContentView *content = [[STTextPopoverContentView alloc] initWithFrame:NSMakeRect(0, 0, popoverWidth, popoverHeight)];
    content.owner = self;
    self.contentView = content;
    self.popover = [[STFloatingResizablePopover alloc] initWithContentView:self.contentView];
    self.popover.contentSize = self.contentView.bounds.size;
    ScreenshotToolAppendLog(@"TextToolPopoverController floating popover created");

    CGFloat padding = 14.0f;
    CGFloat contentWidth = self.contentView.bounds.size.width - (padding * 2.0f);
    CGFloat y = self.contentView.bounds.size.height - padding - 22.0f;

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, contentWidth, 22.0f)];
    [self configureLabel:title font:[NSFont boldSystemFontOfSize:13.0f]];
    [title setStringValue:@"Text Settings"];
    [self.contentView addSubview:title];

    y -= 30.0f;
    NSTextField *fontLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 60.0f, 18.0f)];
    [self configureLabel:fontLabel font:[NSFont systemFontOfSize:12.0f]];
    [fontLabel setStringValue:@"Font"];
    [self.contentView addSubview:fontLabel];

    self.fontPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(padding + 64.0f,
                                                                     y - 2.0f,
                                                                     contentWidth - 64.0f,
                                                                     26.0f) pullsDown:NO];
    [self.fontPopUp setTarget:self];
    [self.fontPopUp setAction:@selector(fontFamilyChanged:)];
    [self.fontPopUp setAutoresizingMask:NSViewWidthSizable];
    [self populateFontFamilies];
    [self.contentView addSubview:self.fontPopUp];
    [fontLabel setAutoresizingMask:(NSViewMaxYMargin | NSViewWidthSizable)];

    y -= 36.0f;
    NSTextField *sizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 60.0f, 18.0f)];
    [self configureLabel:sizeLabel font:[NSFont systemFontOfSize:12.0f]];
    [sizeLabel setStringValue:@"Size"];
    [self.contentView addSubview:sizeLabel];

    CGFloat sizeFieldWidth = 64.0f;
    self.fontSizeField = [[NSTextField alloc] initWithFrame:NSMakeRect(padding + 64.0f,
                                                                       y - 2.0f,
                                                                       sizeFieldWidth,
                                                                       24.0f)];
    [self.fontSizeField setFont:[NSFont systemFontOfSize:12.0f]];
    [self.fontSizeField setAlignment:NSTextAlignmentRight];
    [self.fontSizeField setDelegate:self];
    [self.fontSizeField setAutoresizingMask:NSViewMaxYMargin];
    [self.fontSizeField setTarget:self];
    [self.fontSizeField setAction:@selector(fontSizeFieldChanged:)];
    [self.fontSizeField setStringValue:@"14"];
    [self.contentView addSubview:self.fontSizeField];

    self.fontSizeStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(NSMaxX(self.fontSizeField.frame) + 6.0f,
                                                                       y - 2.0f,
                                                                       18.0f,
                                                                       24.0f)];
    [self.fontSizeStepper setMinValue:STTextPopoverMinFontSize];
    [self.fontSizeStepper setMaxValue:STTextPopoverMaxFontSize];
    [self.fontSizeStepper setIncrement:1.0];
    [self.fontSizeStepper setTarget:self];
    [self.fontSizeStepper setAction:@selector(fontSizeStepperChanged:)];
    [self.fontSizeStepper setAutoresizingMask:NSViewMaxYMargin];
    [self.contentView addSubview:self.fontSizeStepper];

    y -= 44.0f;
    NSTextField *colorTitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 60.0f, 18.0f)];
    [self configureLabel:colorTitleLabel font:[NSFont systemFontOfSize:12.0f]];
    [colorTitleLabel setStringValue:@"Color"];
    [self.contentView addSubview:colorTitleLabel];

    CGFloat colorWellWidth = 44.0f;
    self.colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(padding + 64.0f,
                                                                   y - 4.0f,
                                                                   colorWellWidth,
                                                                   28.0f)];
    [self.colorWell setTarget:self];
    [self.colorWell setAction:@selector(colorChanged:)];
    [self.colorWell setAutoresizingMask:NSViewMaxYMargin];
    [self.contentView addSubview:self.colorWell];

    NSArray<NSColor *> *swatches = [NSArray arrayWithObjects:
        [NSColor blackColor],
        [NSColor darkGrayColor],
        [NSColor whiteColor],
        [NSColor colorWithCalibratedRed:0.22 green:0.56 blue:0.95 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.99 green:0.75 blue:0.20 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.91 green:0.30 blue:0.24 alpha:1.0],
        nil];
    self.colorSwatches = swatches;
    CGFloat swatchSize = 22.0f;
    self.colorSwatchSize = swatchSize;
    CGFloat swatchX = NSMaxX(self.colorWell.frame) + 12.0f;
    NSMutableArray<NSButton *> *swatchButtons = [[NSMutableArray alloc] initWithCapacity:swatches.count];
    for (NSUInteger idx = 0; idx < swatches.count; idx++) {
        NSButton *swatch = [[NSButton alloc] initWithFrame:NSMakeRect(swatchX + (swatchSize + 8.0f) * idx,
                                                                      y - 3.0f,
                                                                      swatchSize,
                                                                      swatchSize)];
        [swatch setButtonType:NSMomentaryChangeButton];
        [swatch setBordered:NO];
        [swatch setBezelStyle:NSShadowlessSquareBezelStyle];
        [swatch setImage:[self swatchImageWithColor:swatches[idx] highlighted:NO size:swatchSize]];
        [swatch setAutoresizingMask:NSViewMinYMargin];
        swatch.target = self;
        swatch.action = @selector(colorSwatchPressed:);
        swatch.tag = (NSInteger)idx;
        [self.contentView addSubview:swatch];
        [swatchButtons addObject:swatch];
    }
    self.colorSwatchButtons = swatchButtons;
    [self updateSwatchSelectionForColor:self.colorWell.color];

    CGFloat previewBottom = padding + 28.0f + 8.0f; // button row + margin
    CGFloat previewTop = y - 10.0f;
    CGFloat previewHeight = MAX(80.0f, previewTop - previewBottom);
    NSScrollView *previewScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(padding,
                                                                                 previewBottom,
                                                                                 contentWidth,
                                                                                 previewHeight)];
    [previewScroll setBorderType:NSBezelBorder];
    [previewScroll setHasVerticalScroller:YES];
    [previewScroll setHasHorizontalScroller:NO];
    [previewScroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

    NSTextView *preview = [[NSTextView alloc] initWithFrame:previewScroll.contentView.bounds];
    [preview setRichText:NO];
    [preview setAllowsUndo:YES];
    [preview setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [preview setFont:STDefaultTextFont()];
    [preview setTextColor:STDefaultTextColor()];
    [preview setDelegate:self];
    [preview setString:@"Sample Text"];
    previewScroll.documentView = preview;
    [self.contentView addSubview:previewScroll];
    self.previewTextView = preview;
    self.previewSampleText = @"Sample Text";

    CGFloat buttonY = padding;

    self.fontPanelButton = [STHyperlinkButton hyperlinkButtonWithTitle:@"Font Panel…"
                                                               target:self
                                                               action:@selector(showFontPanel:)];
    [self.fontPanelButton sizeToFit];
    self.fontPanelButton.frame = NSMakeRect(padding,
                                            buttonY,
                                            self.fontPanelButton.frame.size.width,
                                            self.fontPanelButton.frame.size.height);
    [self.fontPanelButton setAutoresizingMask:NSViewMaxYMargin];
    [self.contentView addSubview:self.fontPanelButton];

    self.resetButton = [STHyperlinkButton hyperlinkButtonWithTitle:@"Reset"
                                                          target:self
                                                          action:@selector(resetPressed:)];
    [self.contentView addSubview:self.resetButton];

    self.defaultButton = [STHyperlinkButton hyperlinkButtonWithTitle:@"Set as Default"
                                                             target:self
                                                             action:@selector(defaultPressed:)];
    [self.contentView addSubview:self.defaultButton];

    [self.resetButton sizeToFit];
    [self.defaultButton sizeToFit];
    [self.resetButton setAutoresizingMask:NSViewMaxYMargin];
    [self.defaultButton setAutoresizingMask:NSViewMaxYMargin];

    CGFloat buttonsWidth = self.resetButton.frame.size.width + 12.0f + self.defaultButton.frame.size.width;
    CGFloat originX = padding + (contentWidth - buttonsWidth);
    self.resetButton.frame = NSMakeRect(originX,
                                        buttonY,
                                        self.resetButton.frame.size.width,
                                        self.resetButton.frame.size.height);
    self.defaultButton.frame = NSMakeRect(NSMaxX(self.resetButton.frame) + 12.0f,
                                          buttonY,
                                          self.defaultButton.frame.size.width,
                                          self.defaultButton.frame.size.height);
}

- (void)configureLabel:(NSTextField *)label font:(NSFont *)font {
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setFont:font];
}

- (void)populateFontFamilies {
    NSArray<NSString *> *families = [[NSFontManager sharedFontManager] availableFontFamilies];
    NSArray<NSString *> *sorted = [families sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [self.fontPopUp removeAllItems];
    [self.fontPopUp addItemsWithTitles:sorted];
}

- (void)updateFontControlsWithFont:(NSFont *)font {
    NSString *family = font.familyName ?: STDefaultTextFont().familyName;
    NSArray<NSString *> *titles = [self.fontPopUp itemTitles];
    if (![titles containsObject:family]) {
        [self.fontPopUp addItemWithTitle:family ?: @"System"];
    }
    [self.fontPopUp selectItemWithTitle:family ?: @"System"];

    CGFloat size = MAX(STTextPopoverMinFontSize, MIN(STTextPopoverMaxFontSize, font.pointSize));
    [self.fontSizeField setStringValue:[NSString stringWithFormat:@"%.0f", roundf(size)]];
    [self.fontSizeStepper setDoubleValue:size];
}

- (void)updatePreviewWithFont:(NSFont *)font color:(NSColor *)color {
    NSColor *displayColor = color ?: [NSColor blackColor];
    NSFont *resolvedFont = font ?: STDefaultTextFont();
    NSRange range = NSMakeRange(0, self.previewTextView.string.length);
    [[self.previewTextView textStorage] setAttributes:@{ NSFontAttributeName : resolvedFont,
                                                         NSForegroundColorAttributeName : displayColor }
                                                range:range];
}

- (NSImage *)swatchImageWithColor:(NSColor *)color highlighted:(BOOL)highlighted size:(CGFloat)size {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, size, size)
                                                         xRadius:4.0f
                                                         yRadius:4.0f];
    [[color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color setFill];
    [path fill];
    NSColor *strokeColor = highlighted ? [NSColor colorWithCalibratedRed:0.18 green:0.8 blue:0.44 alpha:1.0]
                                       : [NSColor colorWithCalibratedWhite:0.0 alpha:0.25];
    CGFloat strokeWidth = highlighted ? 2.0f : 1.0f;
    [strokeColor setStroke];
    [path setLineWidth:strokeWidth];
    [path stroke];
    [image unlockFocus];
    return image;
}

- (void)updateSwatchSelectionForColor:(NSColor *)color {
    if (!self.colorSwatchButtons.count) {
        return;
    }
    NSColor *comparison = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color;
    CGFloat size = (self.colorSwatchSize > 0.0f) ? self.colorSwatchSize : 22.0f;
    for (NSUInteger idx = 0; idx < self.colorSwatchButtons.count; idx++) {
        NSButton *swatch = self.colorSwatchButtons[idx];
        NSColor *candidate = [self.colorSwatches[idx] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: self.colorSwatches[idx];
        BOOL match = NO;
        if (comparison) {
            CGFloat cr, cg, cb, ca;
            CGFloat rr, rg, rb, ra;
            [comparison getRed:&cr green:&cg blue:&cb alpha:&ca];
            [candidate getRed:&rr green:&rg blue:&rb alpha:&ra];
            match = (fabs(cr - rr) < 0.01 && fabs(cg - rg) < 0.01 && fabs(cb - rb) < 0.01 && fabs(ca - ra) < 0.01);
        }
        [swatch setImage:[self swatchImageWithColor:self.colorSwatches[idx] highlighted:match size:size]];
    }
}

- (NSFont *)fontFromCurrentControls {
    NSString *family = [[self.fontPopUp selectedItem] title] ?: STDefaultTextFont().familyName;
    CGFloat size = self.fontSizeField.doubleValue;
    if (!isfinite(size) || size <= 0.0f) {
        size = STDefaultTextFont().pointSize;
    }
    size = MAX(STTextPopoverMinFontSize, MIN(STTextPopoverMaxFontSize, size));
    NSFont *font = [NSFont fontWithName:family size:size];
    if (!font) {
        font = [NSFont fontWithName:STDefaultTextFont().fontName size:size];
    }
    return font ?: STDefaultTextFont();
}

- (BOOL)colorsEqual:(NSColor *)lhs other:(NSColor *)rhs {
    if (!lhs && !rhs) {
        return YES;
    }
    if (!lhs || !rhs) {
        return NO;
    }
    NSColor *left = [lhs colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: lhs;
    NSColor *right = [rhs colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: rhs;
    CGFloat lr, lg, lb, la;
    CGFloat rr, rg, rb, ra;
    [left getRed:&lr green:&lg blue:&lb alpha:&la];
    [right getRed:&rr green:&rg blue:&rb alpha:&ra];
    return (fabs(lr - rr) < 0.001 && fabs(lg - rg) < 0.001 && fabs(lb - rb) < 0.001 && fabs(la - ra) < 0.001);
}

- (BOOL)fontsEqual:(NSFont *)lhs other:(NSFont *)rhs {
    if (!lhs && !rhs) {
        return YES;
    }
    if (!lhs || !rhs) {
        return NO;
    }
    return ([lhs.fontName isEqualToString:rhs.fontName] && fabs(lhs.pointSize - rhs.pointSize) < 0.01f);
}

- (void)applyFontSelectionChange {
    NSFont *font = [self fontFromCurrentControls];
    [self.delegate textToolPopover:self didChangeFont:font];
    [self refresh];
}

#pragma mark - Actions

- (void)colorChanged:(NSColorWell *)sender {
    NSColor *color = sender.color ?: STDefaultTextColor();
    [self.delegate textToolPopover:self didChangeColor:color];
    [self updateSwatchSelectionForColor:color];
    [self refresh];
}

- (void)colorSwatchPressed:(NSButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || (NSUInteger)index >= self.colorSwatches.count) {
        return;
    }
    NSColor *selected = self.colorSwatches[(NSUInteger)index];
    [self.colorWell setColor:selected];
    [self.delegate textToolPopover:self didChangeColor:selected];
    [self updateSwatchSelectionForColor:selected];
    [self refresh];
}

- (void)fontFamilyChanged:(id)sender {
    (void)sender;
    [self applyFontSelectionChange];
}

- (void)fontSizeFieldChanged:(id)sender {
    (void)sender;
    CGFloat size = self.fontSizeField.doubleValue;
    if (!isfinite(size) || size <= 0.0f) {
        size = STDefaultTextFont().pointSize;
    }
    size = MAX(STTextPopoverMinFontSize, MIN(STTextPopoverMaxFontSize, size));
    [self.fontSizeField setStringValue:[NSString stringWithFormat:@"%.0f", roundf(size)]]; 
    [self.fontSizeStepper setDoubleValue:size];
    [self applyFontSelectionChange];
}

- (void)fontSizeStepperChanged:(NSStepper *)sender {
    CGFloat size = MAX(STTextPopoverMinFontSize, MIN(STTextPopoverMaxFontSize, sender.doubleValue));
    [self.fontSizeField setStringValue:[NSString stringWithFormat:@"%.0f", roundf(size)]];
    [self.fontSizeStepper setDoubleValue:size];
    [self applyFontSelectionChange];
}

- (void)showFontPanel:(id)sender {
    (void)sender;
    NSWindow *window = [self.contentView window];
    if (window) {
        NSResponder *target = self.previewTextView ?: self.contentView;
        [window makeFirstResponder:target];
    }
    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSFont *current = [self.delegate textToolPopoverCurrentFont:self] ?: STDefaultTextFont();
    [manager setSelectedFont:current isMultiple:NO];
    [manager orderFrontFontPanel:self];
}

- (void)fontPanelDidChange:(NSFontManager *)manager {
    NSFont *base = [self.delegate textToolPopoverCurrentFont:self] ?: STDefaultTextFont();
    NSFont *converted = [manager convertFont:base];
    if (!converted) {
        converted = [manager convertFont:STDefaultTextFont()];
    }
    if (!converted) {
        return;
    }
    [self.delegate textToolPopover:self didChangeFont:converted];
    [self refresh];
}

- (void)resetPressed:(id)sender {
    (void)sender;
    [self.delegate textToolPopoverDidRequestReset:self];
    self.previewSampleText = @"Sample Text";
    [self refresh];
}

- (void)defaultPressed:(id)sender {
    (void)sender;
    [self.delegate textToolPopoverDidRequestSetDefault:self];
    [self refresh];
}

#pragma mark - NSTextFieldDelegate / NSTextViewDelegate

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.fontSizeField) {
        [self fontSizeFieldChanged:self.fontSizeField];
    }
}

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object == self.previewTextView) {
        self.previewSampleText = self.previewTextView.string ?: @"";
        NSFont *font = [self.delegate textToolPopoverCurrentFont:self] ?: STDefaultTextFont();
        NSColor *color = [self.delegate textToolPopoverCurrentColor:self] ?: STDefaultTextColor();
        [self updatePreviewWithFont:font color:color];
    }
}

@end
