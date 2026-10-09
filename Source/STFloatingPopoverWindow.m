#import "STFloatingPopoverWindow.h"
#import "STFloatingPopoverBackgroundView.h"

@implementation STFloatingPopoverWindow

- (instancetype)initWithContentSize:(NSSize)size {
    NSRect contentRect = NSMakeRect(0, 0, size.width, size.height);
    self = [super initWithContentRect:contentRect
                            styleMask:NSWindowStyleMaskBorderless
                              backing:NSBackingStoreBuffered
                                defer:YES];
    if (self) {
        [self setOpaque:NO];
        [self setHasShadow:YES];
        [self setBackgroundColor:[NSColor clearColor]];
        [self setLevel:NSPopUpMenuWindowLevel];
        [self setHidesOnDeactivate:NO];
        [self setReleasedWhenClosed:NO];
        [self setCollectionBehavior:NSWindowCollectionBehaviorTransient];
    }
    return self;
}

#pragma mark - GSThemePopoverPanel

/// The arrow as the app lays it out: its background view, the content view, holds it.
- (nullable STFloatingPopoverBackgroundView *)arrowView {
    id view = self.contentView;
    return [view isKindOfClass:[STFloatingPopoverBackgroundView class]] ? view : nil;
}

- (NSRectEdge)popoverArrowEdge {
    STFloatingPopoverBackgroundView *view = [self arrowView];
    return view ? view.arrowEdge : NSMaxYEdge;
}

- (CGFloat)popoverArrowPosition {
    return [self arrowView].arrowOffset;
}

- (CGFloat)popoverArrowHeight {
    return MAX([self arrowView].arrowHeight, 0.0);
}

- (CGFloat)popoverArrowWidth {
    return MAX([self arrowView].arrowBase, 0.0);
}

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return NO;
}

- (void)cancelOperation:(id)sender {
    (void)sender;
    if (self.cancelHandler) {
        self.cancelHandler();
    }
}

- (void)keyDown:(NSEvent *)event {
    // Escape closes the popover, wherever the keyboard is inside it.
    if ([event.charactersIgnoringModifiers isEqualToString:@"\033"] && self.cancelHandler) {
        self.cancelHandler();
        return;
    }
    [super keyDown:event];
}

- (void)resetCursorRects {
    [self.contentView discardCursorRects];
    NSView *contentView = self.contentView;
    if (!contentView) {
        return;
    }
    NSCursor *cursor = [NSCursor arrowCursor];
    NSRect bounds = contentView.bounds;
    [contentView addCursorRect:bounds cursor:cursor];
    [cursor set];
}

@end
