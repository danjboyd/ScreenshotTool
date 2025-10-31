#import "STFloatingResizablePopover.h"

@interface STFloatingResizablePopover ()
@property (nonatomic, strong) NSPanel *window;
@property (nonatomic, strong) NSView *hostedView;
@end

@implementation STFloatingResizablePopover

- (instancetype)initWithContentView:(NSView *)view {
    NSParameterAssert(view);
    self = [super init];
    if (self) {
        _hostedView = view;
        _contentSize = view.bounds.size;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSPanel *)ensureWindow {
    if (!self.window) {
        NSSize preferred = self.contentSize;
        NSRect frame = NSMakeRect(0, 0,
                                  MAX(preferred.width, 240.0f),
                                  MAX(preferred.height, 180.0f));
        NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                    styleMask:(NSWindowStyleMaskTitled |
                                                               NSWindowStyleMaskResizable |
                                                               NSWindowStyleMaskUtilityWindow)
                                                      backing:NSBackingStoreBuffered
                                                        defer:YES];
        [panel setReleasedWhenClosed:NO];
        [panel setFloatingPanel:YES];
        [panel setHidesOnDeactivate:NO];
        [panel setLevel:NSPopUpMenuWindowLevel];
        [panel setCollectionBehavior:(NSWindowCollectionBehaviorTransient |
                                       NSWindowCollectionBehaviorFullScreenAuxiliary)];
        [panel setShowsResizeIndicator:YES];
        [panel setTitle:@""];

        NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0,
                                                                      frame.size.width,
                                                                      frame.size.height)];
        container.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
        panel.contentView = container;

        if (self.hostedView.superview != container) {
            [self.hostedView removeFromSuperviewWithoutNeedingDisplay];
            [self.hostedView setFrame:container.bounds];
            [container addSubview:self.hostedView];
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidResign:)
                                                     name:NSWindowDidResignKeyNotification
                                                   object:panel];

        self.window = panel;
    }
    return self.window;
}

- (void)windowDidResign:(NSNotification *)note {
    (void)note;
    [self close];
}

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge {
    (void)edge;
    if (!view.window) {
        return;
    }

    NSPanel *panel = [self ensureWindow];
    NSSize desired = self.contentSize;
    NSSize panelSize = NSMakeSize(MAX(desired.width, 240.0f), MAX(desired.height, 180.0f));
    [panel setContentSize:panelSize];
    NSView *container = panel.contentView;
    [container setFrame:NSMakeRect(0, 0, panelSize.width, panelSize.height)];
    [self.hostedView setFrame:container.bounds];

    NSRect screenRect = [view.window convertRectToScreen:rect];
    CGFloat x = NSMinX(screenRect) - (panelSize.width * 0.5f) + (rect.size.width * 0.5f);
    CGFloat y = NSMinY(screenRect) - panelSize.height - 8.0f;
    NSRect frame = NSMakeRect(x, y, panelSize.width, panelSize.height);

    NSScreen *screen = view.window.screen ?: [NSScreen mainScreen];
    if (screen) {
        NSRect visible = screen.visibleFrame;
        if (NSMinX(frame) < NSMinX(visible)) {
            frame.origin.x = NSMinX(visible);
        }
        if (NSMaxX(frame) > NSMaxX(visible)) {
            frame.origin.x = NSMaxX(visible) - frame.size.width;
        }
        if (NSMinY(frame) < NSMinY(visible)) {
            frame.origin.y = NSMinY(visible);
        }
    }

    [panel setFrame:NSIntegralRect(frame) display:NO];
    [panel makeKeyAndOrderFront:nil];
}

- (void)close {
    [self.window orderOut:nil];
}

- (BOOL)isShown {
    return self.window.isVisible;
}

@end
