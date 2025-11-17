#import "STToolbarTooltipController.h"

#if defined(GNUSTEP)

extern void ScreenshotToolAppendLog(NSString *message);

static BOOL STTooltipDebugLoggingEnabled(void) {
    return YES;
}

static NSString *STTooltipDescribeView(NSView *view) {
    if (!view) {
        return @"<nil>";
    }
    return [NSString stringWithFormat:@"%@:%p", NSStringFromClass([view class]), view];
}

static void STTooltipDebugLog(NSString *message) {
    if (!STTooltipDebugLoggingEnabled() || message.length == 0) {
        return;
    }
    ScreenshotToolAppendLog(message);
}

@interface STTooltipBackgroundView : NSView
@end

@implementation STTooltipBackgroundView

- (BOOL)isOpaque {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithCalibratedWhite:0.0f alpha:0.85f] setFill];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6.0f yRadius:6.0f];
    [path fill];
}

@end

@interface STToolbarTooltipController ()

@property (nonatomic, strong) NSPanel *tooltipWindow;
@property (nonatomic, strong) NSTextField *tooltipLabel;
@property (nonatomic, strong) NSTimer *hideTimer;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSNumber *> *trackingTags;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSString *> *tooltips;

@end

@implementation STToolbarTooltipController

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    _trackingTags = [[NSMutableDictionary alloc] init];
    _tooltips = [[NSMutableDictionary alloc] init];

    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 200, 32)
                                                styleMask:NSBorderlessWindowMask
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.opaque = NO;
    panel.hasShadow = YES;
    panel.backgroundColor = [NSColor clearColor];
    panel.level = NSPopUpMenuWindowLevel;
    panel.hidesOnDeactivate = YES;
    panel.releasedWhenClosed = NO;

    STTooltipBackgroundView *contentView = [[STTooltipBackgroundView alloc] initWithFrame:NSMakeRect(0, 0, 200, 32)];

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(8.0f, 6.0f, 184.0f, 20.0f)];
    label.editable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = [NSFont systemFontOfSize:12.0f];
    label.textColor = [NSColor whiteColor];
    label.alignment = NSTextAlignmentCenter;
    [[label cell] setWraps:YES];
    [[label cell] setScrollable:NO];

    [contentView addSubview:label];
    panel.contentView = contentView;

    _tooltipWindow = panel;
    _tooltipLabel = label;

    return self;
}

- (void)dealloc {
    [self unregisterAll];
}

- (void)registerView:(NSView *)view withTooltip:(NSString *)tooltip {
    if (!view) {
        return;
    }

    [self unregisterView:view];

    view.toolTip = nil;
    if ([view respondsToSelector:@selector(removeAllToolTips)]) {
        [view removeAllToolTips];
    }
    NSValue *key = [NSValue valueWithNonretainedObject:view];

    NSTrackingRectTag tag = [view addTrackingRect:view.bounds
                                            owner:self
                                         userData:(__bridge void *)view
                                     assumeInside:NO];
    self.trackingTags[key] = @(tag);
    self.tooltips[key] = tooltip ?: @"";
    STTooltipDebugLog([NSString stringWithFormat:@"tooltip-register %@ tag=%@ text=\"%@\"",
                       STTooltipDescribeView(view),
                       @(tag),
                       tooltip ?: @""]);
}

- (void)updateTooltip:(NSString *)tooltip forView:(NSView *)view {
    if (!view) {
        return;
    }
    NSValue *key = [NSValue valueWithNonretainedObject:view];
    NSNumber *tagNumber = self.trackingTags[key];
    if (!tagNumber) {
        [self registerView:view withTooltip:tooltip];
        return;
    }
    view.toolTip = nil;
    if ([view respondsToSelector:@selector(removeAllToolTips)]) {
        [view removeAllToolTips];
    }
    self.tooltips[key] = tooltip ?: @"";
    STTooltipDebugLog([NSString stringWithFormat:@"tooltip-update %@ tag=%@ text=\"%@\"",
                       STTooltipDescribeView(view),
                       tagNumber ?: @"<nil>",
                       tooltip ?: @""]);
}

- (void)unregisterView:(NSView *)view {
    if (!view) {
        return;
    }
    NSValue *key = [NSValue valueWithNonretainedObject:view];
    NSNumber *tagNumber = self.trackingTags[key];
    if (tagNumber) {
        [view removeTrackingRect:(NSTrackingRectTag)tagNumber.integerValue];
        [self.trackingTags removeObjectForKey:key];
    }
    [self.tooltips removeObjectForKey:key];
    STTooltipDebugLog([NSString stringWithFormat:@"tooltip-unregister %@ tag=%@",
                       STTooltipDescribeView(view),
                       tagNumber ?: @"<nil>"]);
}

- (void)unregisterAll {
    NSArray<NSValue *> *keys = [self.trackingTags allKeys];
    for (NSValue *key in keys) {
        NSNumber *tagNumber = self.trackingTags[key];
        NSView *view = [key nonretainedObjectValue];
        if (view && tagNumber) {
            [view removeTrackingRect:(NSTrackingRectTag)tagNumber.integerValue];
            if ([view respondsToSelector:@selector(removeAllToolTips)]) {
                [view removeAllToolTips];
            }
        }
    }
    [self.trackingTags removeAllObjects];
    [self.tooltips removeAllObjects];
}

- (BOOL)acceptsFirstResponder {
    return NO;
}

- (void)mouseEntered:(NSEvent *)event {
    NSView *view = (__bridge NSView *)event.userData;
    if (!view) {
        return;
    }
    STTooltipDebugLog([NSString stringWithFormat:@"tooltip-mouseEntered %@",
                       STTooltipDescribeView(view)]);
    NSString *tooltip = self.tooltips[[NSValue valueWithNonretainedObject:view]];
    if (tooltip.length == 0) {
        STTooltipDebugLog([NSString stringWithFormat:@"tooltip-mouseEntered %@ skipped (empty text)",
                           STTooltipDescribeView(view)]);
        return;
    }
    [self showTooltip:tooltip relativeToView:view];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    STTooltipDebugLog(@"tooltip-mouseExited (schedule hide)");
    [self hideTooltip];
}

- (void)showTooltip:(NSString *)text relativeToView:(NSView *)view {
    if (!view.window) {
        return;
    }
    [self.hideTimer invalidate];
    self.hideTimer = nil;

    NSRect bounds = view.bounds;
    NSRect windowRect = [view convertRect:bounds toView:nil];
    NSRect screenRect = [view.window convertRectToScreen:windowRect];

    CGFloat maxWidth = 240.0f;
    NSDictionary *attributes = @{ NSFontAttributeName : self.tooltipLabel.font };
    NSSize measured = [text boundingRectWithSize:NSMakeSize(maxWidth - 16.0f, CGFLOAT_MAX)
                                         options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
                                      attributes:attributes].size;
    CGFloat width = MIN(maxWidth, ceil(measured.width) + 16.0f);
    CGFloat height = MAX(24.0f, ceil(measured.height) + 12.0f);

    NSRect tooltipFrame = NSMakeRect(screenRect.origin.x + (screenRect.size.width - width) * 0.5f,
                                     screenRect.origin.y + screenRect.size.height + 8.0f,
                                     width,
                                     height);

    self.tooltipLabel.frame = NSMakeRect(8.0f, 6.0f, width - 16.0f, height - 12.0f);
    self.tooltipLabel.stringValue = text ?: @"";

    NSView *contentView = self.tooltipWindow.contentView;
    contentView.frame = NSMakeRect(0, 0, width, height);
    [self.tooltipWindow setFrame:tooltipFrame display:NO];
    [self.tooltipWindow orderFront:nil];

    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                      target:self
                                                    selector:@selector(hideTooltip)
                                                    userInfo:nil
                                                     repeats:NO];
    STTooltipDebugLog([NSString stringWithFormat:@"tooltip-show text=\"%@\" view=%@ frame=%@",
                       text ?: @"",
                       STTooltipDescribeView(view),
                       NSStringFromRect(tooltipFrame)]);
}

- (void)hideTooltip {
    [self.tooltipWindow orderOut:nil];
    [self.hideTimer invalidate];
    self.hideTimer = nil;
    STTooltipDebugLog(@"tooltip-hide");
}

- (NSDictionary<NSValue *, NSString *> *)registeredTooltipsSnapshot {
    return [self.tooltips copy];
}

- (NSDictionary<NSValue *, NSNumber *> *)registeredTrackingSnapshot {
    return [self.trackingTags copy];
}

@end

#endif
