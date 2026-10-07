#import "STFloatingPopover.h"
#import "STFloatingPopoverWindow.h"
#import "STFloatingPopoverBackgroundView.h"
#import "AppDelegate.h"

#if !defined(GNUSTEP)

/// On macOS the popover is AppKit's own: the system material, arrow, animation, Escape and
/// focus handling. It's semitransient, so the colour panel a colour well opens doesn't close it;
/// clicking the window does.
@interface STFloatingPopover () <NSPopoverDelegate>
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) NSViewController *contentController;
/// The toolbar control the popover is shown from.
@property (nonatomic, weak) NSView *anchorView;
@end

@implementation STFloatingPopover

- (instancetype)initWithContentView:(NSView *)contentView {
    NSParameterAssert(contentView);
    self = [super init];
    if (self) {
        _contentController = [[NSViewController alloc] init];
        _contentController.view = contentView;
        _contentSize = contentView.bounds.size;
        _effectiveScaleFactor = 1.0f;
        _popover = [[NSPopover alloc] init];
        _popover.contentViewController = _contentController;
        _popover.behavior = NSPopoverBehaviorSemitransient;
        _popover.animates = YES;
        _popover.delegate = self;
    }
    return self;
}

+ (CGFloat)currentScaleFactorForView:(NSView *)view {
    (void)view;
    return 1.0f;
}

- (void)setContentSize:(NSSize)contentSize {
    _contentSize = contentSize;
    if (contentSize.width > 0.0f && contentSize.height > 0.0f) {
        self.popover.contentSize = contentSize;
    }
}

- (void)beginTransientInteraction {
    // NSPopover keeps itself open while its own menus and combo box lists are up.
}

- (void)endTransientInteraction {
}

/// Callers anchor the popover to a small rect in the window's content view, under the toolbar
/// control it belongs to. AppKit positions a popover best against the control itself, so find
/// the view at the rect's centre (the toolbar control) and anchor to its full height there, which
/// keeps the arrow on the segment the rect is under.
- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge {
    if (!view.window) {
        return;
    }
    NSView *anchorView = view;
    NSRect anchorRect = rect;
    NSRectEdge anchorEdge = edge;
    NSView *frameView = view.window.contentView.superview;
    if (frameView) {
        NSRect windowRect = [view convertRect:rect toView:nil];
        NSPoint centre = NSMakePoint(NSMidX(windowRect), NSMidY(windowRect));
        NSView *hit = [frameView hitTest:[frameView convertPoint:centre fromView:nil]];
        // A control in the toolbar, not the content view or something inside it.
        if (hit && hit != view && ![hit isDescendantOf:view.window.contentView]) {
            anchorView = hit;
            NSRect hitRect = [hit convertRect:windowRect fromView:nil];
            anchorRect = NSMakeRect(NSMinX(hitRect), NSMinY(hit.bounds), NSWidth(hitRect), NSHeight(hit.bounds));
            if (hit.isFlipped != view.isFlipped) {
                if (edge == NSMinYEdge) {
                    anchorEdge = NSMaxYEdge;
                } else if (edge == NSMaxYEdge) {
                    anchorEdge = NSMinYEdge;
                }
            }
        }
    }
    if (self.contentSize.width > 0.0f && self.contentSize.height > 0.0f) {
        self.popover.contentSize = self.contentSize;
    }
    self.anchorView = anchorView;
    [self.popover showRelativeToRect:anchorRect ofView:anchorView preferredEdge:anchorEdge];
}

/// A click on the control that opened the popover is left to that control's action, which
/// toggles it; closing here first would make the action open it again.
- (BOOL)popoverShouldClose:(NSPopover *)popover {
    (void)popover;
    NSEvent *event = [NSApp currentEvent];
    NSView *anchor = self.anchorView;
    if (anchor && event.type == NSEventTypeLeftMouseDown && event.window == anchor.window) {
        NSPoint point = [anchor convertPoint:event.locationInWindow fromView:nil];
        if (NSPointInRect(point, anchor.bounds)) {
            return NO;
        }
    }
    return YES;
}

- (void)close {
    if (self.popover.isShown) {
        [self.popover close];
    }
}

- (BOOL)isShown {
    return self.popover.isShown;
}

@end

#else

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

static CGFloat STUserSpaceScaleFactorForWindow(NSWindow *window) {
    if (!window) {
        return 0.0f;
    }
    if ([window respondsToSelector:@selector(userSpaceScaleFactor)]) {
        return window.userSpaceScaleFactor;
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
@property (nonatomic, assign) NSInteger transientInteractionCount;
/// The window the popover was shown from, which gets the keyboard back when it closes (#80).
@property (nonatomic, weak) NSWindow *anchorWindow;
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
    __weak STFloatingPopover *weakSelf = self;
    window.cancelHandler = ^{
        [weakSelf close];
    };
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
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(handleDeferredFocusLoss) object:nil];
    [self performSelector:@selector(handleDeferredFocusLoss) withObject:nil afterDelay:0.0];
}

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    if (!self.window) {
        return;
    }
    NSRect frame = self.window.frame;
    NSRect contentRect = [self.window contentRectForFrameRect:frame];
    NSSize windowSize = contentRect.size;
    NSSize contentSize = windowSize;
    if (self.currentArrowEdge == NSMinYEdge || self.currentArrowEdge == NSMaxYEdge) {
        contentSize.height = MAX(windowSize.height - kSTPopoverArrowHeight * self.effectiveScaleFactor, 40.0f);
    } else {
        contentSize.width = MAX(windowSize.width - kSTPopoverArrowHeight * self.effectiveScaleFactor, 80.0f);
    }
    _contentSize = contentSize;

    CGFloat screenScale = STUserSpaceScaleFactorForWindow(self.window);
    if (screenScale <= 0.0f) {
        screenScale = STReadGSScaleFactor();
    }
    if (screenScale <= 0.0f) {
        screenScale = 1.0f;
    }

    CGFloat desiredOffset;
    if (self.currentArrowEdge == NSMinYEdge || self.currentArrowEdge == NSMaxYEdge) {
        desiredOffset = self.anchorCenterInScreen.x - frame.origin.x;
    } else {
        desiredOffset = self.anchorCenterInScreen.y - frame.origin.y;
    }
    CGFloat arrowOffset = [self clampedArrowOffsetForEdge:self.currentArrowEdge windowSize:windowSize desired:(desiredOffset / screenScale)];

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
    CGFloat screenScale = STUserSpaceScaleFactorForWindow(self.window);
    if (screenScale <= 0.0f) {
        screenScale = STReadGSScaleFactor();
    }
    if (screenScale <= 0.0f) {
        screenScale = 1.0f;
    }

    CGFloat desiredOffset;
    NSRect frame = self.window.frame;
    if (self.currentArrowEdge == NSMinYEdge || self.currentArrowEdge == NSMaxYEdge) {
        desiredOffset = self.anchorCenterInScreen.x - frame.origin.x;
    } else {
        desiredOffset = self.anchorCenterInScreen.y - frame.origin.y;
    }
    CGFloat arrowOffset = [self clampedArrowOffsetForEdge:self.currentArrowEdge windowSize:windowSize desired:(desiredOffset / screenScale)];
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
    self.anchorWindow = view.window;
    self.effectiveScaleFactor = [[self class] currentScaleFactorForView:view];
    CGFloat gsScaleFactor = STReadGSScaleFactor();
    CGFloat anchorWindowScale = STUserSpaceScaleFactorForWindow(view.window);
    CGFloat screenScale = anchorWindowScale > 0.0f ? anchorWindowScale : (gsScaleFactor > 0.0f ? gsScaleFactor : 1.0f);

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

    NSRect windowRect = [view convertRect:rect toView:nil];
    NSRect screenRect = [view.window convertRectToScreen:windowRect];
    NSPoint anchorCenter = NSMakePoint(NSMidX(screenRect), NSMidY(screenRect));
    self.anchorCenterInScreen = anchorCenter;

    NSSize scaledWindowSize = NSMakeSize(windowSize.width * screenScale, windowSize.height * screenScale);
    CGFloat screenGap = kSTPopoverWindowGap * screenScale;
    NSRect frame = NSMakeRect(0, 0, scaledWindowSize.width, scaledWindowSize.height);
    switch (edge) {
        case NSMinYEdge:
            frame.origin.x = anchorCenter.x - (scaledWindowSize.width * 0.5f);
            frame.origin.y = NSMaxY(screenRect) + screenGap;
            break;
        case NSMaxYEdge:
            frame.origin.x = anchorCenter.x - (scaledWindowSize.width * 0.5f);
            frame.origin.y = NSMinY(screenRect) - screenGap - scaledWindowSize.height;
            break;
        case NSMinXEdge:
            frame.origin.x = NSMinX(screenRect) - screenGap - scaledWindowSize.width;
            frame.origin.y = anchorCenter.y - (scaledWindowSize.height * 0.5f);
            break;
        case NSMaxXEdge:
            frame.origin.x = NSMaxX(screenRect) + screenGap;
            frame.origin.y = anchorCenter.y - (scaledWindowSize.height * 0.5f);
            break;
        default:
            frame.origin.x = anchorCenter.x - (scaledWindowSize.width * 0.5f);
            frame.origin.y = NSMinY(screenRect) - screenGap - scaledWindowSize.height;
            arrowEdge = NSMaxYEdge;
            break;
    }

    NSScreen *targetScreen = view.window.screen ?: [NSScreen mainScreen];
    if (targetScreen) {
        NSRect visibleFrame = targetScreen.visibleFrame;
        if (NSWidth(visibleFrame) >= scaledWindowSize.width) {
            frame.origin.x = MAX(NSMinX(visibleFrame), MIN(frame.origin.x, NSMaxX(visibleFrame) - scaledWindowSize.width));
        }
        if (NSHeight(visibleFrame) >= scaledWindowSize.height) {
            frame.origin.y = MAX(NSMinY(visibleFrame), MIN(frame.origin.y, NSMaxY(visibleFrame) - scaledWindowSize.height));
        }
    }

    CGFloat desiredOffset;
    if (arrowEdge == NSMinYEdge || arrowEdge == NSMaxYEdge) {
        desiredOffset = anchorCenter.x - frame.origin.x;
    } else {
        desiredOffset = anchorCenter.y - frame.origin.y;
    }

    CGFloat arrowOffset = [self clampedArrowOffsetForEdge:arrowEdge windowSize:windowSize desired:(desiredOffset / screenScale)];

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

- (void)beginTransientInteraction {
    self.transientInteractionCount += 1;
}

- (void)endTransientInteraction {
    if (self.transientInteractionCount > 0) {
        self.transientInteractionCount -= 1;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(handleDeferredFocusLoss) object:nil];
    [self performSelector:@selector(handleDeferredFocusLoss) withObject:nil afterDelay:0.0];
}

- (BOOL)shouldRemainOpenForActiveWindow:(NSWindow *)activeWindow {
    if (!activeWindow) {
        return NO;
    }
    if (activeWindow == self.window) {
        return YES;
    }
    if (activeWindow.parentWindow == self.window) {
        return YES;
    }
    if (self.window.parentWindow == activeWindow) {
        return YES;
    }
    return NO;
}

- (void)handleDeferredFocusLoss {
    if (!self.window || !self.window.isVisible) {
        return;
    }
    if (self.transientInteractionCount > 0) {
        return;
    }
    NSWindow *activeWindow = [NSApp keyWindow] ?: [NSApp mainWindow];
    if ([self shouldRemainOpenForActiveWindow:activeWindow]) {
        return;
    }
    [self close];
}

- (void)close {
    if (!self.window) {
        return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(handleDeferredFocusLoss) object:nil];
    // Give the keyboard back if the popover had it (or nothing has it); not when the user has
    // moved on to another window, which closes the popover too.
    NSWindow *keyWindow = [NSApp keyWindow];
    BOOL hadKeyboard = self.window.isVisible && (keyWindow == nil || keyWindow == self.window);
    [self.window orderOut:nil];
    NSWindow *parent = self.anchorWindow;
    if (hadKeyboard && parent.isVisible) {
        [parent makeKeyWindow];
    }
}

- (BOOL)isShown {
    return self.window && self.window.isVisible;
}

@end

#endif
