#import "STHudView.h"

/// The transient notice ("Copied image to clipboard") as a standard label in the tool tip colours,
/// which each theme defines; the view draws nothing of its own (#67).
@interface STHudView ()
@property (nonatomic, strong) NSTextField *label;
@end

@implementation STHudView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _message = @"";
        _font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
#if defined(GNUSTEP)
        _textColor = [NSColor toolTipTextColor] ?: [NSColor controlTextColor];
        _fillColor = [NSColor toolTipColor] ?: [NSColor controlBackgroundColor];
#else
        // AppKit has no public tool tip colours; these follow light and dark mode.
        _textColor = [NSColor labelColor];
        _fillColor = [NSColor windowBackgroundColor];
#endif
        _textPadding = NSMakeSize(20.0f, 12.0f);
        _cornerRadius = 0.0f;
        _hudAlpha = 1.0f;

        _label = [[NSTextField alloc] initWithFrame:self.bounds];
        [_label setEditable:NO];
        [_label setSelectable:NO];
        [_label setBezeled:NO];
        [_label setBordered:NO];
        [_label setDrawsBackground:YES];
        [_label setAlignment:NSTextAlignmentCenter];
        [_label setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
        [self addSubview:_label];
        [self updateLabel];
    }
    return self;
}

- (void)setMessage:(NSString *)message {
    _message = [message copy] ?: @"";
    [self updateLabel];
}

- (void)setFont:(NSFont *)font {
    _font = font;
    [self updateLabel];
}

- (void)setTextColor:(NSColor *)textColor {
    _textColor = textColor;
    [self updateLabel];
}

- (void)setFillColor:(NSColor *)fillColor {
    _fillColor = fillColor;
    [self updateLabel];
}

- (void)setTextPadding:(NSSize)textPadding {
    _textPadding = textPadding;
    [self updateLabel];
}

- (void)setHudAlpha:(CGFloat)hudAlpha {
    _hudAlpha = MAX(0.0f, MIN(1.0f, hudAlpha));
    [self updateLabel];
}

/// The label fills the notice; the text is centred vertically by the label's own padding.
- (void)updateLabel {
    NSColor *text = self.textColor ?: [NSColor controlTextColor];
    NSColor *fill = self.fillColor ?: [NSColor controlBackgroundColor];
    [self.label setStringValue:self.message ?: @""];
    [self.label setFont:self.font ?: [NSFont systemFontOfSize:0.0f]];
    [self.label setTextColor:[text colorWithAlphaComponent:text.alphaComponent * self.hudAlpha]];
    [self.label setBackgroundColor:[fill colorWithAlphaComponent:fill.alphaComponent * self.hudAlpha]];
    [self.label setFrame:self.bounds];
    [self.label setNeedsDisplay:YES];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self updateLabel];
}

@end
