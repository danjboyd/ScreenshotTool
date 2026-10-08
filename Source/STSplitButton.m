#import "STSplitButton.h"

/// libadwaita's arrow part: a 16px pan-down glyph and its padding.
static const CGFloat STSplitButtonArrowWidth = 28.0;

@interface STSplitButtonCell : NSButtonCell
@property (nonatomic, assign) BOOL arrowPressed;
@end

@implementation STSplitButtonCell

/// The window's suggested button, as the theme decides it: the one Return presses.
- (BOOL)isSuggested:(NSView *)controlView {
    NSString *key = [self keyEquivalent];
    if ([key isEqualToString:@"\r"] || [key isEqualToString:@"\n"]) {
        return YES;
    }
    return controlView.window != nil && [controlView.window defaultButtonCell] == self;
}

- (NSColor *)arrowColorInView:(NSView *)controlView {
    if (![self isEnabled]) {
        return [NSColor disabledControlTextColor];
    }
    return [self isSuggested:controlView] ? [NSColor selectedControlTextColor] : [NSColor controlTextColor];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    NSRect arrowRect = [controlView isKindOfClass:[STSplitButton class]]
        ? [(STSplitButton *)controlView arrowRect]
        : NSZeroRect;
    if (NSIsEmptyRect(arrowRect)) {
        [super drawInteriorWithFrame:cellFrame inView:controlView];
        return;
    }
    // The title centres in what the arrow leaves.
    NSRect titleFrame = cellFrame;
    titleFrame.size.width = MAX(0.0, NSMinX(arrowRect) - NSMinX(cellFrame));
    [super drawInteriorWithFrame:titleFrame inView:controlView];

    BOOL suggested = [self isSuggested:controlView];
    NSRect bezel = NSInsetRect(controlView.bounds, 0.5, 0.5);
    if (self.arrowPressed) {
        // Pressed, as the theme darkens a pressed button: only the arrow part.
        CGFloat radius = MIN(10.0, floor(NSHeight(bezel) / 2.0));
        [NSGraphicsContext saveGraphicsState];
        [[NSBezierPath bezierPathWithRoundedRect:bezel xRadius:radius yRadius:radius] addClip];
        [[NSColor colorWithCalibratedWhite:0.0 alpha:(suggested ? 0.18 : 0.12)] set];
        NSRectFillUsingOperation(arrowRect, NSCompositeSourceOver);
        [NSGraphicsContext restoreGraphicsState];
    }

    NSColor *color = [self arrowColorInView:controlView];
    // The line between the parts: the title's colour at 30%, the full height.
    [[color colorWithAlphaComponent:0.3] set];
    NSRectFillUsingOperation(NSMakeRect(NSMinX(arrowRect), NSMinY(bezel), 1.0, NSHeight(bezel)),
                             NSCompositeSourceOver);

    // pan-down-symbolic: a chevron, 2px wide with round ends, in a 16px square.
    NSPoint centre = NSMakePoint(NSMidX(arrowRect) + 0.5, floor(NSMidY(arrowRect)));
    CGFloat tipOffset = [controlView isFlipped] ? 2.0 : -2.0;
    NSBezierPath *chevron = [NSBezierPath bezierPath];
    [chevron moveToPoint:NSMakePoint(centre.x - 4.0, centre.y - tipOffset)];
    [chevron lineToPoint:NSMakePoint(centre.x, centre.y + tipOffset)];
    [chevron lineToPoint:NSMakePoint(centre.x + 4.0, centre.y - tipOffset)];
    [chevron setLineWidth:2.0];
    [chevron setLineCapStyle:NSRoundLineCapStyle];
    [chevron setLineJoinStyle:NSRoundLineJoinStyle];
    [color set];
    [chevron stroke];
}

@end

@implementation STSplitButton

+ (Class)cellClass {
    return [STSplitButtonCell class];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self && ![[self cell] isKindOfClass:[STSplitButtonCell class]]) {
        STSplitButtonCell *cell = [[STSplitButtonCell alloc] initTextCell:@""];
        [self setCell:cell];
    }
    return self;
}

- (NSRect)arrowRect {
    NSRect bounds = self.bounds;
    if (NSWidth(bounds) <= STSplitButtonArrowWidth * 2.0) {
        return NSZeroRect;
    }
    return NSMakeRect(NSMaxX(bounds) - STSplitButtonArrowWidth, NSMinY(bounds),
                      STSplitButtonArrowWidth, NSHeight(bounds));
}

- (void)setArrowPressed:(BOOL)pressed {
    STSplitButtonCell *cell = (STSplitButtonCell *)[self cell];
    if (cell.arrowPressed != pressed) {
        cell.arrowPressed = pressed;
        [self setNeedsDisplay:YES];
        [self displayIfNeeded];
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
    if (![self isEnabled] || !self.menuProvider || !NSPointInRect(location, [self arrowRect])) {
        [super mouseDown:event];
        return;
    }
    [self showMenuForEvent:event];
}

/// Opens the menu from the press on the arrow and tracks it as a context menu is: released over
/// an item chooses it; released elsewhere, the menu stays open for a click.
- (void)showMenuForEvent:(NSEvent *)event {
    NSMenu *menu = self.menuProvider ? self.menuProvider() : nil;
    if (!menu) {
        return;
    }
    [self setArrowPressed:YES];
#if defined(GNUSTEP)
    // GNUstep's -popUpMenuPositioningItem:atLocation:inView: never put a menu of its own on
    // screen, and a context menu opens at a point, so it would flip up over the button when there's
    // no room below. Shown as the theme shows a context menu, at a place of our own: below the
    // button, its left edges lined up, or above it when it doesn't fit below.
    NSRect buttonOnScreen = [self.window convertRectToScreen:[self convertRect:self.bounds toView:nil]];
    NSMenuView *menuView = [menu menuRepresentation];
    [menu displayTransient];
    NSWindow *menuWindow = [menuView window];
    NSSize size = menuWindow.frame.size;
    NSRect visible = [(self.window.screen ?: [NSScreen mainScreen]) visibleFrame];
    NSPoint origin = NSMakePoint(NSMinX(buttonOnScreen), NSMinY(buttonOnScreen) - 4.0 - size.height);
    if (origin.y < NSMinY(visible)) {
        origin.y = MIN(NSMaxY(buttonOnScreen) + 4.0, NSMaxY(visible) - size.height);
    }
    origin.x = MAX(NSMinX(visible), MIN(origin.x, NSMaxX(visible) - size.width));
    [menuWindow setFrameOrigin:origin];
    [menuView mouseDown:event];
    [menu closeTransient];
#else
    (void)event;
    [menu popUpMenuPositioningItem:nil
                        atLocation:NSMakePoint(0.0, [self isFlipped] ? NSMaxY(self.bounds) + 4.0 : NSMinY(self.bounds) - 4.0)
                            inView:self];
#endif
    [self setArrowPressed:NO];
}

@end
