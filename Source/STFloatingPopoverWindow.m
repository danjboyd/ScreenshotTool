#import "STFloatingPopoverWindow.h"

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

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return NO;
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
