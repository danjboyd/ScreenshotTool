#import "ToolSettingsPopoverController.h"
#import "AppDelegate.h"
#import "STFloatingPopover.h"
#import "STHyperlinkButton.h"
#import "ScreenshotToolSettings.h"
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
        [self buildPopover];
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

- (void)buildPopover {
    ScreenshotToolAppendLog([NSString stringWithFormat:@"ToolSettingsPopoverController(%@) buildPopover begin", [self titleText]]);
    self.contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 260, 180)];
    self.popover = [[STFloatingPopover alloc] initWithContentView:self.contentView];
    self.popover.contentSize = self.contentView.bounds.size;
    ScreenshotToolAppendLog([NSString stringWithFormat:@"ToolSettingsPopoverController(%@) floating popover created",
                             [self titleText]]);

    CGFloat padding = 12.0f;
    CGFloat contentWidth = self.contentView.bounds.size.width - (padding * 2.0f);
    CGFloat y = self.contentView.bounds.size.height - padding - 20.0f;

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, contentWidth, 20.0f)];
    [title setEditable:NO];
    [title setBezeled:NO];
    [title setBordered:NO];
    [title setDrawsBackground:NO];
    [title setFont:[NSFont boldSystemFontOfSize:13.0f]];
    [title setStringValue:[self titleText]];
    self.titleLabel = title;
    [self.contentView addSubview:title];

    y -= 28.0f;
    NSTextField *widthLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 80.0f, 18.0f)];
    [widthLabel setEditable:NO];
    [widthLabel setBezeled:NO];
    [widthLabel setBordered:NO];
    [widthLabel setDrawsBackground:NO];
    [widthLabel setFont:[NSFont systemFontOfSize:12.0f]];
    [widthLabel setStringValue:@"Width"];
    self.widthLabel = widthLabel;
    [self.contentView addSubview:widthLabel];

    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(padding, y - 24.0f, contentWidth - 60.0f, 20.0f)];
    [slider setMinValue:STToolWidthMin];
    [slider setMaxValue:STToolWidthMax];
    [slider setNumberOfTickMarks:0];
    [slider setContinuous:YES];
    slider.target = self;
    slider.action = @selector(widthSliderChanged:);
    self.widthSlider = slider;
    [self.contentView addSubview:slider];

    NSTextField *valueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(NSMaxX(slider.frame) + 6.0f,
                                                                           slider.frame.origin.y,
                                                                           50.0f,
                                                                           20.0f)];
    [valueLabel setEditable:NO];
    [valueLabel setBezeled:NO];
    [valueLabel setBordered:NO];
    [valueLabel setDrawsBackground:NO];
    [valueLabel setAlignment:NSTextAlignmentRight];
    [valueLabel setFont:[NSFont systemFontOfSize:12.0f]];
    [valueLabel setStringValue:@"0 px"];
    self.widthValueLabel = valueLabel;
    [self.contentView addSubview:valueLabel];

    y = slider.frame.origin.y - 36.0f;
    NSTextField *colorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 80.0f, 18.0f)];
    [colorLabel setEditable:NO];
    [colorLabel setBezeled:NO];
    [colorLabel setBordered:NO];
    [colorLabel setDrawsBackground:NO];
    [colorLabel setFont:[NSFont systemFontOfSize:12.0f]];
    [colorLabel setStringValue:@"Color"];
    [self.contentView addSubview:colorLabel];

    NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSMakeRect(padding,
                                                                      y - 28.0f,
                                                                      44.0f,
                                                                      28.0f)];
    well.target = self;
    well.action = @selector(colorWellChanged:);
    self.colorWell = well;
    [self.contentView addSubview:well];

    CGFloat buttonY = padding;
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

    CGFloat buttonsWidth = reset.frame.size.width + 12.0f + setDefault.frame.size.width;
    CGFloat buttonsOriginX = padding + (contentWidth - buttonsWidth);
    reset.frame = NSMakeRect(buttonsOriginX,
                             buttonY,
                             reset.frame.size.width,
                             reset.frame.size.height);
    setDefault.frame = NSMakeRect(NSMaxX(reset.frame) + 12.0f,
                                  buttonY,
                                  setDefault.frame.size.width,
                                  setDefault.frame.size.height);
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
