#import "STHyperlinkButton.h"

@implementation STHyperlinkButton

+ (instancetype)hyperlinkButtonWithTitle:(NSString *)title
                                   target:(id)target
                                   action:(SEL)action {
    STHyperlinkButton *button = [[self alloc] initWithFrame:NSZeroRect];
    button.target = target;
    button.action = action;
    [button setTitle:title ?: @""];
    [button sizeToFit];
    return button;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

/// A standard small push button, drawn by the theme (#67). It was a hand-drawn underlined link in
/// a colour of the app's choosing.
- (void)commonInit {
    [self setButtonType:NSMomentaryPushInButton];
    [self setBezelStyle:NSRoundedBezelStyle];
    [[self cell] setControlSize:NSSmallControlSize];
    [self setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
}

@end
