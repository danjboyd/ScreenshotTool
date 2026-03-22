#import "STHyperlinkButton.h"
#import "STThemeUtilities.h"

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

- (void)commonInit {
    [self setBordered:NO];
    [self setButtonType:NSMomentaryChangeButton];
#if defined(NSBezelStyleInline)
    [self setBezelStyle:NSBezelStyleInline];
#endif
    [self setFont:[NSFont systemFontOfSize:12.0]];
    [self setFocusRingType:NSFocusRingTypeNone];
    [self updateAttributedTitle];
}

- (void)setTitle:(NSString *)title {
    [super setTitle:title];
    [self updateAttributedTitle];
}

- (void)setEnabled:(BOOL)flag {
    [super setEnabled:flag];
    [self updateAttributedTitle];
}

- (void)updateAttributedTitle {
    NSString *title = self.title ?: @"";
    NSColor *enabledColor = STThemeLinkColor();
    NSColor *disabledColor = [NSColor disabledControlTextColor] ?: [NSColor lightGrayColor];
    NSColor *color = self.isEnabled ? enabledColor : disabledColor;
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:title];
    NSRange range = NSMakeRange(0, attr.length);
    [attr addAttribute:NSForegroundColorAttributeName value:color range:range];
    [attr addAttribute:NSUnderlineStyleAttributeName
                value:@(NSUnderlineStyleSingle)
                range:range];
    [self setAttributedTitle:attr];
    [self sizeToFit];
}

- (void)resetCursorRects {
    [self discardCursorRects];
    if (self.isEnabled) {
        [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
    } else {
        [self addCursorRect:self.bounds cursor:[NSCursor arrowCursor]];
    }
}

@end
