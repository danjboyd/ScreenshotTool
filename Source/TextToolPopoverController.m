#import "TextToolPopoverController.h"
#import "STHyperlinkButton.h"
#import "ScreenshotToolSettings.h"
#include <math.h>

@interface TextToolPopoverController () <NSPopoverDelegate>
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSTextField *previewLabel;
@property (nonatomic, strong) NSColorWell *colorWell;
@property (nonatomic, strong) NSPopUpButton *fontPopUp;
@property (nonatomic, strong) NSSlider *fontSizeSlider;
@property (nonatomic, strong) NSTextField *fontSizeValueLabel;
@property (nonatomic, strong) STHyperlinkButton *resetButton;
@property (nonatomic, strong) STHyperlinkButton *defaultButton;
@end

@implementation TextToolPopoverController

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge {
    if (!self.popover) {
        [self buildPopover];
    }
    [self refresh];
    if (!self.popover.isShown) {
        [self.popover showRelativeToRect:rect ofView:view preferredEdge:edge];
    }
}

- (void)close {
    [self.popover close];
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
    [self updateFontControlsWithFont:font];
    [self updatePreviewWithFont:font color:color];

    BOOL canResetColor = ![self colorsEqual:color other:defaultColor];
    BOOL canResetFont = ![self fontsEqual:font other:defaultFont];
    BOOL enableActions = (canResetColor || canResetFont);
    [self.resetButton setEnabled:enableActions];
    [self.defaultButton setEnabled:enableActions];
}

#pragma mark - Private

- (void)buildPopover {
    self.contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 240)];

    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = YES;
    popover.contentSize = self.contentView.frame.size;
    popover.contentViewController = [[NSViewController alloc] init];
    popover.contentViewController.view = self.contentView;
    popover.delegate = self;
    self.popover = popover;

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
    [self populateFontFamilies];
    [self.contentView addSubview:self.fontPopUp];

    y -= 34.0f;
    NSTextField *sizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 60.0f, 18.0f)];
    [self configureLabel:sizeLabel font:[NSFont systemFontOfSize:12.0f]];
    [sizeLabel setStringValue:@"Size"];
    [self.contentView addSubview:sizeLabel];

    self.fontSizeSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(padding + 64.0f,
                                                                     y - 4.0f,
                                                                     contentWidth - 120.0f,
                                                                     24.0f)];
    [self.fontSizeSlider setMinValue:8.0];
    [self.fontSizeSlider setMaxValue:72.0];
    [self.fontSizeSlider setNumberOfTickMarks:0];
    [self.fontSizeSlider setContinuous:YES];
    [self.fontSizeSlider setTarget:self];
    [self.fontSizeSlider setAction:@selector(fontSizeSliderChanged:)];
    [self.contentView addSubview:self.fontSizeSlider];

    self.fontSizeValueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(NSMaxX(self.fontSizeSlider.frame) + 8.0f,
                                                                           y - 2.0f,
                                                                           44.0f,
                                                                           20.0f)];
    [self configureLabel:self.fontSizeValueLabel font:[NSFont systemFontOfSize:12.0f]];
    [self.fontSizeValueLabel setAlignment:NSTextAlignmentRight];
    [self.fontSizeValueLabel setStringValue:@"0 pt"];
    [self.contentView addSubview:self.fontSizeValueLabel];

    y -= 38.0f;
    NSTextField *colorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 60.0f, 18.0f)];
    [self configureLabel:colorLabel font:[NSFont systemFontOfSize:12.0f]];
    [colorLabel setStringValue:@"Color"];
    [self.contentView addSubview:colorLabel];

    self.colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(padding + 64.0f,
                                                                   y - 6.0f,
                                                                   52.0f,
                                                                   30.0f)];
    [self.colorWell setTarget:self];
    [self.colorWell setAction:@selector(colorChanged:)];
    [self.contentView addSubview:self.colorWell];

    y -= 64.0f;
    self.previewLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding,
                                                                      y,
                                                                      contentWidth,
                                                                      44.0f)];
    [self.previewLabel setEditable:NO];
    [self.previewLabel setBezeled:NO];
    [self.previewLabel setBordered:NO];
    [self.previewLabel setDrawsBackground:NO];
    [self.previewLabel setAlignment:NSTextAlignmentLeft];
    [self.previewLabel setStringValue:@"Sample Text"];
    [self.contentView addSubview:self.previewLabel];

    CGFloat buttonY = padding;
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

    CGFloat size = MAX(8.0f, MIN(72.0f, font.pointSize));
    [self.fontSizeSlider setDoubleValue:size];
    [self.fontSizeValueLabel setStringValue:[NSString stringWithFormat:@"%.0f pt", roundf(size)]];
}

- (void)updatePreviewWithFont:(NSFont *)font color:(NSColor *)color {
    NSColor *displayColor = color ?: [NSColor blackColor];
    NSDictionary *attributes = @{ NSFontAttributeName : font ?: STDefaultTextFont(),
                                  NSForegroundColorAttributeName : displayColor };
    NSAttributedString *example = [[NSAttributedString alloc] initWithString:@"Sample Text"
                                                                  attributes:attributes];
    [self.previewLabel setAttributedStringValue:example];
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
    CGFloat lr = 0, lg = 0, lb = 0, la = 0;
    CGFloat rr = 0, rg = 0, rb = 0, ra = 0;
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

- (NSFont *)fontFromCurrentControls {
    NSString *family = [[self.fontPopUp selectedItem] title] ?: STDefaultTextFont().familyName;
    CGFloat size = MAX(8.0f, MIN(72.0f, self.fontSizeSlider.doubleValue));
    NSFont *font = [NSFont fontWithName:family size:size];
    if (!font) {
        font = [NSFont fontWithName:STDefaultTextFont().fontName size:size];
    }
    return font ?: STDefaultTextFont();
}

#pragma mark - Actions

- (void)colorChanged:(NSColorWell *)sender {
    NSColor *color = sender.color ?: STDefaultTextColor();
    [self.delegate textToolPopover:self didChangeColor:color];
    [self refresh];
}

- (void)fontFamilyChanged:(id)sender {
    (void)sender;
    NSFont *font = [self fontFromCurrentControls];
    [self.delegate textToolPopover:self didChangeFont:font];
    [self refresh];
}

- (void)fontSizeSliderChanged:(NSSlider *)sender {
    CGFloat size = MAX(8.0f, MIN(72.0f, sender.doubleValue));
    [self.fontSizeSlider setDoubleValue:size];
    [self.fontSizeValueLabel setStringValue:[NSString stringWithFormat:@"%.0f pt", roundf(size)]];
    NSFont *font = [self fontFromCurrentControls];
    [self.delegate textToolPopover:self didChangeFont:font];
    [self refresh];
}

- (void)resetPressed:(id)sender {
    (void)sender;
    [self.delegate textToolPopoverDidRequestReset:self];
    [self refresh];
}

- (void)defaultPressed:(id)sender {
    (void)sender;
    [self.delegate textToolPopoverDidRequestSetDefault:self];
    [self refresh];
}

#pragma mark - NSPopoverDelegate

- (void)popoverDidClose:(NSNotification *)notification {
    (void)notification;
}

@end
