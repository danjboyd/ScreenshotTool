#import "STFloatingPopover.h"
#import "STFloatingPopoverWindow.h"
#import "STFloatingPopoverBackgroundView.h"

static const CGFloat kSTPopoverArrowHeight = 12.0f;
static const CGFloat kSTPopoverArrowBase = 20.0f;
static const CGFloat kSTPopoverCornerRadius = 8.0f;
static const CGFloat kSTPopoverArrowMargin = 4.0f;
static const CGFloat kSTPopoverWindowGap = 7.0f;

static CGFloat STReadGSScaleFactor(void) {
    const char *rawValue = getenv("GSScaleFactor");
    if (rawValue) {
        CGFloat parsed = (CGFloat)atof(rawValue);
        if (parsed > 0.0f) {
            return parsed;
        }
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGFloat userDefault = [defaults doubleForKey:@"GSScaleFactor"];
    if (userDefault > 0.0f) {
        return userDefault;
    }
    return 0.0f;
}

@interface STFloatingPopover ()
@property (nonatomic, strong) STFloatingPopoverWindow *window;
@property (nonatomic, strong) STFloatingPopoverBackgroundView *backgroundView;
@property (nonatomic, strong) NSView *contentHolder;
@property (nonatomic, strong) NSView *hostedView;
@property (nonatomic, assign) NSRectEdge currentArrowEdge;
@property (nonatomic, assign) NSPoint anchorCenterInScreen;
@end

@implementation STFloatingPopover

- (instancetype)initWithContentView:(NSView *)contentView {
    NSParameterAssert(contentView);
    self = [super init];
    if (self) {
        _hostedView = contentView;
        _contentSize = contentView.bounds.size;
        _currentArrowEdge = NSMaxYEdge;
        _effectiveScaleFactor = [[self class] currentScaleFactorForView:contentView];
    }
    return self;
}

+ (CGFloat)currentScaleFactorForView:(NSView *)view {
    (void)view;
    // Layout and positioning already occur in logical coordinates; avoid double-scaling.
    return 1.0f;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setContentSize:(NSSize)contentSize {
    _contentSize = contentSize;
    if (self.window) {
        [self updateWindowForCurrentEdge];
    }
}

- (void)ensureWindow {
    if (self.window) {
        return;
    }

    STFloatingPopoverWindow *window = [[STFloatingPopoverWindow alloc] initWithContentSize:self.contentSize];
    STFloatingPopoverBackgroundView *background = [[STFloatingPopoverBackgroundView alloc] initWithFrame:NSMakeRect(0, 0, self.contentSize.width, self.contentSize.height)];
    background.arrowHeight = kSTPopoverArrowHeight;
    background.arrowBase = kSTPopoverArrowBase;
    background.cornerRadius = kSTPopoverCornerRadius;

    window.contentView = background;
    self.window = window;
    self.backgroundView = background;

    NSView *holder = [[NSView alloc] initWithFrame:background.bounds];
    holder.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    [background addSubview:holder];
    self.contentHolder = holder;

    if (self.hostedView.superview != holder) {
        [self.hostedView removeFromSuperviewWithoutNeedingDisplay];
        [holder addSubview:self.hostedView];
    }
    self.hostedView.frame = holder.bounds;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidResignKey:)
                                                 name:NSWindowDidResignKeyNotification
                                               object:window];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidResize:)
                                                 name:NSWindowDidResizeNotification
                                               object:window];
}

- (void)windowDidResignKey:(NSNotification *)notification {
    (void)notification;
    [self close];
}

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    if (!self.window) {
        return;
    }
    NSRect frame = self.window.frame;
    NSSize windowSize = frame.size;
    NSSize contentSize = windowSize;
    if (self.currentArrowEdge == NSMinYEdge || self.currentArrowEdge == NSMaxYEdge) {
        contentSize.height = MAX(windowSize.height - kSTPopoverArrowHeight * self.effectiveScaleFactor, 40.0f);
    } else {
        contentSize.width = MAX(windowSize.width - kSTPopoverArrowHeight * self.effectiveScaleFactor, 80.0f);
    }
    _contentSize = contentSize;

    CGFloat desiredOffset;
    if (self.currentArrowEdge == NSMinYEdge || self.currentArrowEdge == NSMaxYEdge) {
        desiredOffset = self.anchorCenterInScreen.x - frame.origin.x;
    } else {
        desiredOffset = self.anchorCenterInScreen.y - frame.origin.y;
    }
    CGFloat arrowOffset = [self clampedArrowOffsetForEdge:self.currentArrowEdge windowSize:windowSize desired:desiredOffset];

    self.backgroundView.frame = NSMakeRect(0, 0, windowSize.width, windowSize.height);
    self.backgroundView.arrowEdge = self.currentArrowEdge;
    self.backgroundView.arrowOffset = arrowOffset;
    self.backgroundView.arrowBase = kSTPopoverArrowBase * self.effectiveScaleFactor;
    self.backgroundView.arrowHeight = kSTPopoverArrowHeight * self.effectiveScaleFactor;
    self.backgroundView.cornerRadius = kSTPopoverCornerRadius * self.effectiveScaleFactor;

    [self applyContentFramesForEdge:self.currentArrowEdge];
}

- (void)applyContentFramesForEdge:(NSRectEdge)edge {
    NSRect bounds = self.backgroundView.bounds;
    NSRect holderFrame = bounds;

    switch (edge) {
        case NSMinYEdge: // arrow on bottom
            holderFrame.origin.y += kSTPopoverArrowHeight * self.effectiveScaleFactor;
            holderFrame.size.height -= kSTPopoverArrowHeight * self.effectiveScaleFactor;
            break;
        case NSMaxYEdge: // arrow on top
            holderFrame.size.height -= kSTPopoverArrowHeight * self.effectiveScaleFactor;
            break;
        case NSMinXEdge: // arrow on left
            holderFrame.origin.x += kSTPopoverArrowHeight * self.effectiveScaleFactor;
            holderFrame.size.width -= kSTPopoverArrowHeight * self.effectiveScaleFactor;
            break;
        case NSMaxXEdge: // arrow on right
            holderFrame.size.width -= kSTPopoverArrowHeight * self.effectiveScaleFactor;
            break;
        default:
            break;
    }

    holderFrame = NSIntegralRect(holderFrame);
    self.contentHolder.frame = holderFrame;
    self.hostedView.frame = NSMakeRect(0, 0, holderFrame.size.width, holderFrame.size.height);
}

- (void)updateWindowForCurrentEdge {
    if (!self.window) {
        return;
    }

    NSSize windowSize = self.contentSize;
    if (self.currentArrowEdge == NSMinYEdge || self.currentArrowEdge == NSMaxYEdge) {
        windowSize.height += kSTPopoverArrowHeight * self.effectiveScaleFactor;
    } else if (self.currentArrowEdge == NSMinXEdge || self.currentArrowEdge == NSMaxXEdge) {
        windowSize.width += kSTPopoverArrowHeight * self.effectiveScaleFactor;
    }

    [self.window setContentSize:windowSize];
    self.backgroundView.frame = NSMakeRect(0, 0, windowSize.width, windowSize.height);
    CGFloat desiredOffset;
    NSRect frame = self.window.frame;
    if (self.currentArrowEdge == NSMinYEdge || self.currentArrowEdge == NSMaxYEdge) {
        desiredOffset = self.anchorCenterInScreen.x - frame.origin.x;
    } else {
        desiredOffset = self.anchorCenterInScreen.y - frame.origin.y;
    }
    CGFloat arrowOffset = [self clampedArrowOffsetForEdge:self.currentArrowEdge windowSize:windowSize desired:desiredOffset];
    self.backgroundView.arrowEdge = self.currentArrowEdge;
    self.backgroundView.arrowOffset = arrowOffset;
    self.backgroundView.arrowBase = kSTPopoverArrowBase * self.effectiveScaleFactor;
    self.backgroundView.arrowHeight = kSTPopoverArrowHeight * self.effectiveScaleFactor;
    self.backgroundView.cornerRadius = kSTPopoverCornerRadius * self.effectiveScaleFactor;
    [self applyContentFramesForEdge:self.currentArrowEdge];
}

- (NSRectEdge)arrowEdgeForPreferredEdge:(NSRectEdge)edge {
    switch (edge) {
        case NSMinYEdge:
            return NSMinYEdge;
        case NSMaxYEdge:
            return NSMaxYEdge;
        case NSMinXEdge:
            return NSMaxXEdge;
        case NSMaxXEdge:
            return NSMinXEdge;
        default:
            return NSMaxYEdge;
    }
}

- (CGFloat)clampedArrowOffsetForEdge:(NSRectEdge)edge windowSize:(NSSize)windowSize desired:(CGFloat)desired {
    CGFloat minOffset = (kSTPopoverCornerRadius + (kSTPopoverArrowBase * 0.5f) + kSTPopoverArrowMargin) * self.effectiveScaleFactor;
    CGFloat maxOffset;
    if (edge == NSMinYEdge || edge == NSMaxYEdge) {
        maxOffset = windowSize.width - minOffset;
    } else {
        maxOffset = windowSize.height - minOffset;
    }
    if (maxOffset < minOffset) {
        maxOffset = minOffset;
    }
    return MIN(MAX(desired, minOffset), maxOffset);
}

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge {
    if (!view.window) {
        return;
    }

    [self ensureWindow];
    self.effectiveScaleFactor = [[self class] currentScaleFactorForView:view];

    NSRectEdge arrowEdge = [self arrowEdgeForPreferredEdge:edge];
    NSSize contentSize = self.contentSize;
    if (contentSize.width <= 0.0f || contentSize.height <= 0.0f) {
        contentSize = NSMakeSize(240.0f, 160.0f);
    }

    NSSize windowSize = contentSize;
    if (arrowEdge == NSMinYEdge || arrowEdge == NSMaxYEdge) {
        windowSize.height += kSTPopoverArrowHeight * self.effectiveScaleFactor;
    } else if (arrowEdge == NSMinXEdge || arrowEdge == NSMaxXEdge) {
        windowSize.width += kSTPopoverArrowHeight * self.effectiveScaleFactor;
    }

    NSRect screenRect = [view.window convertRectToScreen:rect];
    NSPoint anchorCenter = NSMakePoint(NSMidX(screenRect), NSMidY(screenRect));
    self.anchorCenterInScreen = anchorCenter;

    NSRect frame = NSMakeRect(0, 0, windowSize.width, windowSize.height);
    switch (edge) {
        case NSMinYEdge:
            frame.origin.x = anchorCenter.x - (windowSize.width * 0.5f);
            frame.origin.y = NSMaxY(screenRect) + kSTPopoverWindowGap * self.effectiveScaleFactor;
            break;
        case NSMaxYEdge:
            frame.origin.x = anchorCenter.x - (windowSize.width * 0.5f);
            frame.origin.y = NSMinY(screenRect) - kSTPopoverWindowGap * self.effectiveScaleFactor - windowSize.height;
            break;
        case NSMinXEdge:
            frame.origin.x = NSMinX(screenRect) - kSTPopoverWindowGap * self.effectiveScaleFactor - windowSize.width;
            frame.origin.y = anchorCenter.y - (windowSize.height * 0.5f);
            break;
        case NSMaxXEdge:
            frame.origin.x = NSMaxX(screenRect) + kSTPopoverWindowGap * self.effectiveScaleFactor;
            frame.origin.y = anchorCenter.y - (windowSize.height * 0.5f);
            break;
        default:
            frame.origin.x = anchorCenter.x - (windowSize.width * 0.5f);
            frame.origin.y = NSMinY(screenRect) - kSTPopoverWindowGap * self.effectiveScaleFactor - windowSize.height;
            arrowEdge = NSMaxYEdge;
            break;
    }

    NSScreen *targetScreen = view.window.screen ?: [NSScreen mainScreen];
    if (targetScreen) {
        NSRect visibleFrame = targetScreen.visibleFrame;
        if (NSWidth(visibleFrame) >= windowSize.width) {
            frame.origin.x = MAX(NSMinX(visibleFrame), MIN(frame.origin.x, NSMaxX(visibleFrame) - windowSize.width));
        }
        if (NSHeight(visibleFrame) >= windowSize.height) {
            frame.origin.y = MAX(NSMinY(visibleFrame), MIN(frame.origin.y, NSMaxY(visibleFrame) - windowSize.height));
        }
    }

    CGFloat desiredOffset;
    if (arrowEdge == NSMinYEdge || arrowEdge == NSMaxYEdge) {
        desiredOffset = anchorCenter.x - frame.origin.x;
    } else {
        desiredOffset = anchorCenter.y - frame.origin.y;
    }

    CGFloat arrowOffset = [self clampedArrowOffsetForEdge:arrowEdge windowSize:windowSize desired:desiredOffset];

    self.currentArrowEdge = arrowEdge;
    [self.window setContentSize:windowSize];
    self.backgroundView.frame = NSMakeRect(0, 0, windowSize.width, windowSize.height);
    self.backgroundView.arrowEdge = arrowEdge;
    self.backgroundView.arrowOffset = arrowOffset;
    self.backgroundView.arrowBase = kSTPopoverArrowBase * self.effectiveScaleFactor;
    self.backgroundView.arrowHeight = kSTPopoverArrowHeight * self.effectiveScaleFactor;
    self.backgroundView.cornerRadius = kSTPopoverCornerRadius * self.effectiveScaleFactor;

    if (self.hostedView.superview != self.contentHolder) {
        [self.hostedView removeFromSuperviewWithoutNeedingDisplay];
        [self.contentHolder addSubview:self.hostedView];
    }
    [self applyContentFramesForEdge:arrowEdge];

    [self.window setFrame:NSIntegralRect(frame) display:NO];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)close {
    if (!self.window) {
        return;
    }
    [self.window orderOut:nil];
}

- (BOOL)isShown {
    return self.window && self.window.isVisible;
}

@end
