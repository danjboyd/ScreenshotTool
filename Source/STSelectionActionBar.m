#import "STSelectionActionBar.h"
#import "STThemeUtilities.h"

/// Between the bar and the selection, the window's edge, and around the buttons.
static const CGFloat STSelectionBarGap = 8.0;
static const CGFloat STSelectionBarPadding = 4.0;

@implementation STSelectionActionBar {
    NSArray<NSButton *> *_buttons;
}

- (instancetype)initWithTarget:(id)target {
    self = [super initWithFrame:NSZeroRect];
    if (!self) {
        return nil;
    }
    NSArray<NSString *> *titles = @[@"Crop", @"Copy", @"Redact"];
    SEL actions[] = { @selector(cropImage:), @selector(copy:), @selector(redactSelection:) };
    NSArray<NSString *> *toolTips = @[@"Crop to the selection", @"Copy the selection", @"Pixelate the selection"];
    NSMutableArray<NSButton *> *buttons = [[NSMutableArray alloc] init];
    CGFloat x = STSelectionBarPadding;
    CGFloat height = 0.0;
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 64.0, 24.0)];
        button.title = titles[i];
        [button setBezelStyle:NSRoundedBezelStyle];
        button.target = target;
        button.action = actions[i];
        button.toolTip = toolTips[i];
        // A click on the bar leaves the keyboard with the canvas (Esc, the tool keys).
        [button setRefusesFirstResponder:YES];
        if (i == 0 && [button respondsToSelector:@selector(setGSThemeStyle:)]) {
            [button performSelector:@selector(setGSThemeStyle:) withObject:@"accent"];
        }
        [button sizeToFit];
        NSRect frame = button.frame;
        frame.size.width = MAX(64.0, ceil(NSWidth(frame)) + 12.0);
        frame.origin = NSMakePoint(x, STSelectionBarPadding);
        button.frame = frame;
        x = NSMaxX(frame) + STSelectionBarPadding;
        height = MAX(height, NSHeight(frame));
        [self addSubview:button];
        [buttons addObject:button];
    }
    _buttons = [buttons copy];
    [self setFrameSize:NSMakeSize(x, height + STSelectionBarPadding * 2.0)];
    return self;
}

- (NSArray<NSButton *> *)buttons {
    return _buttons;
}

- (BOOL)isOpaque {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect box = NSInsetRect(self.bounds, 0.5, 0.5);
    CGFloat radius = MIN(10.0, NSHeight(box) / 2.0);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:box xRadius:radius yRadius:radius];
    [STThemePopoverBackgroundColor() setFill];
    [path fill];
    [STThemePopoverBorderColor() setStroke];
    [path setLineWidth:1.0];
    [path stroke];
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor arrowCursor]];
}

- (NSRect)frameForSelection:(NSRect)selection visible:(NSRect)visible {
    NSSize size = self.frame.size;
    BOOL flipped = self.superview.isFlipped;
    // "Below" is towards the bottom of the screen whichever way the superview counts.
    CGFloat belowY = flipped ? NSMaxY(selection) + STSelectionBarGap : NSMinY(selection) - STSelectionBarGap - size.height;
    CGFloat aboveY = flipped ? NSMinY(selection) - STSelectionBarGap - size.height : NSMaxY(selection) + STSelectionBarGap;
    CGFloat insideY = flipped ? NSMaxY(selection) - STSelectionBarGap - size.height : NSMinY(selection) + STSelectionBarGap;
    CGFloat minY = NSMinY(visible) + STSelectionBarGap;
    CGFloat maxY = NSMaxY(visible) - STSelectionBarGap - size.height;
    CGFloat y = insideY;
    if (belowY >= minY && belowY <= maxY) {
        y = belowY;
    } else if (aboveY >= minY && aboveY <= maxY) {
        y = aboveY;
    }
    y = MAX(minY, MIN(y, maxY));
    CGFloat x = NSMidX(selection) - size.width / 2.0;
    x = MAX(NSMinX(visible) + STSelectionBarGap, MIN(x, NSMaxX(visible) - STSelectionBarGap - size.width));
    return NSMakeRect(round(x), round(y), size.width, size.height);
}

@end
