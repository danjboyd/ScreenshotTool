#import "ZoomPopoverController.h"
#import "AppDelegate.h"
#import "STFloatingPopover.h"
#import "STThemeUtilities.h"
#include <math.h>

static const CGFloat STZoomPopoverMinScale = 0.05f;
static const CGFloat STZoomPopoverMaxScale = 8.0f;
static const CGFloat STZoomPopoverSliderMaxValue = 1000.0f;
static const CGFloat STZoomPopoverButtonHeight = 28.0f;
static const CGFloat STZoomPopoverButtonGap = 12.0f;

static CGFloat STZoomPopoverButtonWidth(NSString *title, CGFloat minimumWidth) {
    NSString *displayTitle = (title.length > 0) ? title : @"";
    NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    NSSize titleSize = [displayTitle sizeWithAttributes:@{ NSFontAttributeName: font }];
    CGFloat bezelPadding = 40.0f;
    return ceil(MAX(minimumWidth, titleSize.width + bezelPadding));
}

static CGFloat STClampZoomScale(CGFloat scale) {
    return MAX(STZoomPopoverMinScale, MIN(scale, STZoomPopoverMaxScale));
}

static CGFloat STZoomSliderValueForScale(CGFloat scale) {
    CGFloat clamped = STClampZoomScale(scale);
    CGFloat minLog = log(STZoomPopoverMinScale);
    CGFloat maxLog = log(STZoomPopoverMaxScale);
    CGFloat scaleLog = log(clamped);
    CGFloat t = (scaleLog - minLog) / (maxLog - minLog);
    return MAX(0.0f, MIN(STZoomPopoverSliderMaxValue, t * STZoomPopoverSliderMaxValue));
}

static CGFloat STZoomScaleForSliderValue(CGFloat sliderValue) {
    CGFloat clampedValue = MAX(0.0f, MIN(STZoomPopoverSliderMaxValue, sliderValue));
    CGFloat t = clampedValue / STZoomPopoverSliderMaxValue;
    CGFloat minLog = log(STZoomPopoverMinScale);
    CGFloat maxLog = log(STZoomPopoverMaxScale);
    return exp(minLog + ((maxLog - minLog) * t));
}

@interface ZoomPopoverController ()
@property (nonatomic, strong) STFloatingPopover *popover;
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *valueLabel;
@property (nonatomic, strong) NSSlider *slider;
@property (nonatomic, strong) NSButton *resetButton;
@property (nonatomic, strong) NSButton *fitButton;
@end

@implementation ZoomPopoverController

- (void)dealloc {
    [self.popover close];
}

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge {
    if (!self.popover) {
        [self buildPopoverForView:view];
    }
    [self refresh];
    if (self.popover.isShown) {
        return;
    }
    ScreenshotToolAppendLog([NSString stringWithFormat:@"ZoomPopoverController show requested (view=%@ rect=%@ edge=%ld)",
                             NSStringFromClass([view class]),
                             NSStringFromRect(rect),
                             (long)edge]);
    [self.popover showRelativeToRect:rect ofView:view preferredEdge:edge];
}

- (void)close {
    if (!self.popover || !self.popover.isShown) {
        return;
    }
    [self.popover close];
}

- (BOOL)isShown {
    return self.popover.isShown;
}

- (void)refresh {
    if (!self.contentView) {
        return;
    }

    id<ZoomPopoverControllerDelegate> delegate = self.delegate;
    BOOL hasImage = delegate ? [delegate zoomPopoverHasImage:self] : NO;
    BOOL fitToWindow = delegate ? [delegate zoomPopoverIsFitToWindow:self] : NO;
    CGFloat scale = delegate ? [delegate zoomPopoverCurrentScale:self] : 1.0f;
    scale = STClampZoomScale(scale);

    NSColor *titleColor = STThemeSectionHeaderColor() ?: STThemePrimaryTextColor();
    NSColor *textColor = STThemeSecondaryTextColor() ?: [NSColor labelColor];
    NSColor *valueColor = STThemePrimaryTextColor() ?: textColor;

    [self.titleLabel setTextColor:titleColor];
    [self.valueLabel setTextColor:valueColor];

    [self.slider setEnabled:hasImage];
    [self.slider setDoubleValue:STZoomSliderValueForScale(scale)];

    NSString *valueString = @"No image";
    if (hasImage) {
        NSInteger percent = (NSInteger)lround(scale * 100.0f);
        valueString = fitToWindow ? @"Fit" : [NSString stringWithFormat:@"%ld%%", (long)percent];
    }
    [self.valueLabel setStringValue:valueString];

    [self.fitButton setEnabled:(hasImage && !fitToWindow)];
    BOOL canReset = hasImage && (fitToWindow || fabs(scale - 1.0f) > 0.001f);
    [self.resetButton setEnabled:canReset];

    [self.contentView setNeedsDisplay:YES];
}

#pragma mark - Private

- (void)buildPopoverForView:(NSView *)view {
    (void)view;
    CGFloat scaleFactor = 1.0f;
    CGFloat padding = 12.0f * scaleFactor;
    CGFloat fitButtonWidth = STZoomPopoverButtonWidth(@"Fit to Window", 132.0f);
    CGFloat resetButtonWidth = STZoomPopoverButtonWidth(@"100%", 84.0f);
    CGFloat contentWidthTarget = fitButtonWidth + STZoomPopoverButtonGap + resetButtonWidth + (padding * 2.0f);
    NSRect contentFrame = NSMakeRect(0, 0, MAX(284.0f, contentWidthTarget), 132.0f);
    self.contentView = [[NSView alloc] initWithFrame:contentFrame];
    self.popover = [[STFloatingPopover alloc] initWithContentView:self.contentView];
    self.popover.contentSize = contentFrame.size;
    self.popover.effectiveScaleFactor = scaleFactor;

    CGFloat contentWidth = NSWidth(contentFrame) - (padding * 2.0f);
    CGFloat y = NSHeight(contentFrame) - padding - (22.0f * scaleFactor);

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 120.0f, 22.0f)];
    [title setEditable:NO];
    [title setSelectable:NO];
    [title setBezeled:NO];
    [title setBordered:NO];
    [title setDrawsBackground:NO];
    [title setFont:[NSFont boldSystemFontOfSize:13.0f]];
    [title setStringValue:@"Zoom"];
    self.titleLabel = title;
    [self.contentView addSubview:title];

    NSTextField *value = [[NSTextField alloc] initWithFrame:NSMakeRect(NSMaxX(contentFrame) - padding - 70.0f,
                                                                       y,
                                                                       70.0f,
                                                                       22.0f)];
    [value setEditable:NO];
    [value setSelectable:NO];
    [value setBezeled:NO];
    [value setBordered:NO];
    [value setDrawsBackground:NO];
    [value setAlignment:NSTextAlignmentRight];
    [value setFont:[NSFont boldSystemFontOfSize:12.0f]];
    [value setStringValue:@"100%"];
    self.valueLabel = value;
    [self.contentView addSubview:value];

    y -= 30.0f * scaleFactor;
    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(padding, y, contentWidth, 22.0f)];
    [slider setMinValue:0.0f];
    [slider setMaxValue:STZoomPopoverSliderMaxValue];
    [slider setContinuous:YES];
    slider.target = self;
    slider.action = @selector(sliderChanged:);
    self.slider = slider;
    [self.contentView addSubview:slider];

    y -= 42.0f * scaleFactor;
    NSButton *fitButton = [[NSButton alloc] initWithFrame:NSMakeRect(padding, y, fitButtonWidth, STZoomPopoverButtonHeight)];
    [fitButton setTitle:@"Fit to Window"];
    [fitButton setButtonType:NSMomentaryPushInButton];
    [fitButton setBezelStyle:NSRoundedBezelStyle];
    [fitButton setTarget:self];
    [fitButton setAction:@selector(fitButtonPressed:)];
    self.fitButton = fitButton;
    [self.contentView addSubview:fitButton];

    NSButton *resetButton = [[NSButton alloc] initWithFrame:NSMakeRect(NSMaxX(contentFrame) - padding - resetButtonWidth,
                                                                       y,
                                                                       resetButtonWidth,
                                                                       STZoomPopoverButtonHeight)];
    [resetButton setTitle:@"100%"];
    [resetButton setButtonType:NSMomentaryPushInButton];
    [resetButton setBezelStyle:NSRoundedBezelStyle];
    [resetButton setTarget:self];
    [resetButton setAction:@selector(resetButtonPressed:)];
    self.resetButton = resetButton;
    [self.contentView addSubview:resetButton];
}

- (void)sliderChanged:(id)sender {
    (void)sender;
    id<ZoomPopoverControllerDelegate> delegate = self.delegate;
    if (!delegate || ![delegate zoomPopoverHasImage:self]) {
        return;
    }
    CGFloat scale = STZoomScaleForSliderValue(self.slider.doubleValue);
    [delegate zoomPopover:self didChangeScale:scale];
    [self refresh];
}

- (void)fitButtonPressed:(id)sender {
    (void)sender;
    id<ZoomPopoverControllerDelegate> delegate = self.delegate;
    if (!delegate || ![delegate zoomPopoverHasImage:self]) {
        return;
    }
    [delegate zoomPopoverDidRequestFitToWindow:self];
    [self refresh];
}

- (void)resetButtonPressed:(id)sender {
    (void)sender;
    id<ZoomPopoverControllerDelegate> delegate = self.delegate;
    if (!delegate || ![delegate zoomPopoverHasImage:self]) {
        return;
    }
    [delegate zoomPopover:self didChangeScale:1.0f];
    [self refresh];
}

@end
