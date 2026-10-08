#import "ToolSettingsPopoverController.h"
#import "AppDelegate.h"
#import "STFloatingPopover.h"
#import "STHyperlinkButton.h"
#import "ScreenshotToolSettings.h"
#import "STThemeUtilities.h"
#include <math.h>

@interface ToolSettingsPopoverController ()
@property (nonatomic, strong) STFloatingPopover *popover;
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *widthLabel;
@property (nonatomic, strong) NSSlider *widthSlider;
@property (nonatomic, strong) NSTextField *widthValueLabel;
@property (nonatomic, strong) NSColorWell *colorWell;
@property (nonatomic, strong) STHyperlinkButton *resetButton;
@property (nonatomic, strong) STHyperlinkButton *defaultButton;
@end

@implementation ToolSettingsPopoverController

- (instancetype)initWithTool:(ScreenshotCanvasTool)tool {
    self = [super init];
    if (self) {
        _tool = tool;
    }
    return self;
}

- (void)dealloc {
    [self.popover close];
}

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge {
    if (!self.popover) {
        [self buildPopoverForView:view];
    }
    [self refresh];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"ToolSettingsPopoverController(%@) showRelativeToRect entry (popover=%@ isShown=%@)",
                             [self titleText],
                             self.popover ? @"YES" : @"NO",
                             self.popover.isShown ? @"YES" : @"NO"]);
    if (self.popover.isShown) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"ToolSettingsPopoverController(%@) showRelativeToRect skipped because popover already shown",
                                 [self titleText]]);
        return;
    }
    ScreenshotToolAppendLog([NSString stringWithFormat:@"ToolSettingsPopoverController(%@) showRelativeToRect requested (view=%@ rect=%@ edge=%ld)",
                             [self titleText],
                             NSStringFromClass([view class]),
                             NSStringFromRect(rect),
                             (long)edge]);
    [self.popover showRelativeToRect:rect ofView:view preferredEdge:edge];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"ToolSettingsPopoverController(%@) showRelativeToRect invoked (visible=%@)",
                             [self titleText],
                             self.popover.isShown ? @"YES" : @"NO"]);
}

- (void)close {
    if (!self.popover) {
        return;
    }
    BOOL wasShown = self.popover.isShown;
    if (!wasShown) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"ToolSettingsPopoverController(%@) close skipped (popover not shown)",
                                 [self titleText]]);
        return;
    }
    [self.popover close];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"ToolSettingsPopoverController(%@) close invoked (wasShown=YES nowShown=%@)",
                             [self titleText],
                             self.popover.isShown ? @"YES" : @"NO"]);
}

- (BOOL)isShown {
    return self.popover.isShown;
}

- (void)refresh {
    if (!self.popover) {
        return;
    }
    id<ToolSettingsPopoverControllerDelegate> delegate = self.delegate;
    if (!delegate) {
        return;
    }

    CGFloat width = [delegate toolSettingsPopover:self currentWidthForTool:self.tool];
    CGFloat defaultWidth = [delegate toolSettingsPopover:self defaultWidthForTool:self.tool];
    NSColor *color = [delegate toolSettingsPopover:self currentColorForTool:self.tool] ?: STDefaultPenColor();
    NSColor *defaultColor = [delegate toolSettingsPopover:self defaultColorForTool:self.tool] ?: STDefaultPenColor();

    [self.widthSlider setMinValue:STToolWidthMin];
    [self.widthSlider setMaxValue:STToolWidthMax];
    [self.widthSlider setDoubleValue:width];
    [self updateWidthValueLabelWithWidth:width];
    [self.colorWell setColor:color];

    BOOL canResetWidth = fabs(width - defaultWidth) > 0.01f;
    BOOL canResetColor = ![self color:color isEqualToColor:defaultColor];
    [self.resetButton setEnabled:(canResetWidth || canResetColor)];
    [self.defaultButton setEnabled:(canResetWidth || canResetColor)];
}

#pragma mark - Private

/// A non-editable label in the theme's font.
static NSTextField *STToolSettingsLabel(NSString *string, NSFont *font, NSColor *color) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setFont:font];
    [label setTextColor:color];
    [label setStringValue:string ?: @""];
    return label;
}

/// The height a control asks for in the theme's font and metrics.
static CGFloat STToolSettingsNaturalHeight(NSControl *control) {
    return ceil([[control cell] cellSize].height);
}

- (void)buildPopoverForView:(NSView *)view {
    ScreenshotToolAppendLog([NSString stringWithFormat:@"ToolSettingsPopoverController(%@) buildPopover begin", [self titleText]]);
    // Only spacing and the width are the app's; heights come from the theme's fonts and controls,
    // and the popover is as tall as its content.
    CGFloat width = 260.0f;
    CGFloat padding = 12.0f;
    CGFloat labelGap = 4.0f;
    CGFloat sectionGap = 12.0f;
    self.contentView = [[NSView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, width, 100.0f)];
    NSColor *labelColor = STThemeSecondaryTextColor() ?: [NSColor labelColor];
    NSColor *titleColor = STThemeSectionHeaderColor() ?: STThemePrimaryTextColor();
    NSColor *valueTextColor = STThemePrimaryTextColor() ?: labelColor;
    NSFont *font = [NSFont systemFontOfSize:0.0f];

    self.titleLabel = STToolSettingsLabel([self titleText], [NSFont boldSystemFontOfSize:[NSFont systemFontSize]], titleColor);
    [self.contentView addSubview:self.titleLabel];
    self.widthLabel = STToolSettingsLabel(@"Width", font, labelColor);
    [self.contentView addSubview:self.widthLabel];

    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    [slider setMinValue:STToolWidthMin];
    [slider setMaxValue:STToolWidthMax];
    [slider setNumberOfTickMarks:0];
    [slider setContinuous:YES];
    slider.target = self;
    slider.action = @selector(widthSliderChanged:);
    self.widthSlider = slider;
    [self.contentView addSubview:slider];

    NSTextField *valueLabel = STToolSettingsLabel(@"0 px", font, valueTextColor);
    [valueLabel setAlignment:NSTextAlignmentRight];
    self.widthValueLabel = valueLabel;
    [self.contentView addSubview:valueLabel];

    NSTextField *colorLabel = STToolSettingsLabel(@"Color", font, labelColor);
    [self.contentView addSubview:colorLabel];

    NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSZeroRect];
    well.target = self;
    well.action = @selector(colorWellChanged:);
    [well setBordered:YES];
    self.colorWell = well;
    [self.contentView addSubview:well];

    STHyperlinkButton *reset = [STHyperlinkButton hyperlinkButtonWithTitle:@"Reset"
                                                                    target:self
                                                                    action:@selector(resetPressed:)];
    self.resetButton = reset;
    [self.contentView addSubview:reset];
    STHyperlinkButton *setDefault = [STHyperlinkButton hyperlinkButtonWithTitle:@"Set as Default"
                                                                         target:self
                                                                         action:@selector(defaultPressed:)];
    self.defaultButton = setDefault;
    [self.contentView addSubview:setDefault];
    [reset sizeToFit];
    [setDefault sizeToFit];
    // Wide enough for the buttons in the theme's font (Adwaita's are wide).
    width = MAX(width, NSWidth(reset.frame) + 12.0f + NSWidth(setDefault.frame) + (padding * 2.0f));

    // Heights, measured; then the rows from the top down.
    CGFloat contentWidth = width - (padding * 2.0f);
    CGFloat titleHeight = STToolSettingsNaturalHeight(self.titleLabel);
    CGFloat labelHeight = STToolSettingsNaturalHeight(self.widthLabel);
    CGFloat controlHeight = MAX(NSHeight(reset.frame), STToolSettingsNaturalHeight(slider));
    NSDictionary *valueAttributes = @{NSFontAttributeName: font};
    CGFloat valueWidth = ceil([@"888 px" sizeWithAttributes:valueAttributes].width) + 4.0f;
    CGFloat wellHeight = MAX(controlHeight, 28.0f);
    CGFloat buttonsHeight = MAX(NSHeight(reset.frame), NSHeight(setDefault.frame));
    CGFloat height = padding + titleHeight + sectionGap
        + labelHeight + labelGap + controlHeight + sectionGap
        + labelHeight + labelGap + wellHeight + sectionGap
        + buttonsHeight + padding;

    [self.contentView setFrameSize:NSMakeSize(width, height)];
    self.popover = [[STFloatingPopover alloc] initWithContentView:self.contentView];
    self.popover.contentSize = NSMakeSize(width, height);
    self.popover.effectiveScaleFactor = 1.0f;
    ScreenshotToolAppendLog([NSString stringWithFormat:@"ToolSettingsPopoverController(%@) floating popover created",
                             [self titleText]]);

    CGFloat y = height - padding;
    y -= titleHeight;
    [self.titleLabel setFrame:NSMakeRect(padding, y, contentWidth, titleHeight)];
    y -= sectionGap + labelHeight;
    [self.widthLabel setFrame:NSMakeRect(padding, y, contentWidth, labelHeight)];
    y -= labelGap + controlHeight;
    [slider setFrame:NSMakeRect(padding, y, contentWidth - valueWidth - 6.0f, controlHeight)];
    [valueLabel setFrame:NSMakeRect(padding + contentWidth - valueWidth,
                                    y + floor((controlHeight - labelHeight) / 2.0f),
                                    valueWidth,
                                    labelHeight)];
    y -= sectionGap + labelHeight;
    [colorLabel setFrame:NSMakeRect(padding, y, contentWidth, labelHeight)];
    y -= labelGap + wellHeight;
    [well setFrame:NSMakeRect(padding, y, round(wellHeight * 1.6f), wellHeight)];

    CGFloat buttonsWidth = NSWidth(reset.frame) + 12.0f + NSWidth(setDefault.frame);
    CGFloat buttonsX = padding + (contentWidth - buttonsWidth);
    reset.frame = NSMakeRect(buttonsX, padding, NSWidth(reset.frame), NSHeight(reset.frame));
    setDefault.frame = NSMakeRect(NSMaxX(reset.frame) + 12.0f, padding, NSWidth(setDefault.frame), NSHeight(setDefault.frame));
}

- (NSString *)titleText {
    switch (self.tool) {
        case ScreenshotCanvasToolPen:
            return @"Pen Settings";
        case ScreenshotCanvasToolHighlighter:
            return @"Highlighter Settings";
        default:
            return @"Tool Settings";
    }
}

- (void)updateWidthValueLabelWithWidth:(CGFloat)width {
    [self.widthValueLabel setStringValue:[NSString stringWithFormat:@"%.0f px", roundf(width)]];
}

- (BOOL)color:(NSColor *)lhs isEqualToColor:(NSColor *)rhs {
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

#pragma mark - Actions

- (void)widthSliderChanged:(NSSlider *)sender {
    CGFloat value = roundf(sender.doubleValue);
    value = MAX(STToolWidthMin, MIN(STToolWidthMax, value));
    [sender setDoubleValue:value];
    [self updateWidthValueLabelWithWidth:value];
    [self.delegate toolSettingsPopover:self didChangeWidth:value forTool:self.tool];
    [self refresh];
}

- (void)colorWellChanged:(NSColorWell *)sender {
    NSColor *color = sender.color ?: STDefaultPenColor();
    [self.delegate toolSettingsPopover:self didChangeColor:color forTool:self.tool];
    [self refresh];
}

- (void)resetPressed:(id)sender {
    [self.delegate toolSettingsPopoverDidRequestReset:self forTool:self.tool];
    [self refresh];
}

- (void)defaultPressed:(id)sender {
    [self.delegate toolSettingsPopoverDidRequestSetDefault:self forTool:self.tool];
    [self refresh];
}

@end
