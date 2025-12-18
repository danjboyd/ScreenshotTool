#import "STHudView.h"

@implementation STHudView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _message = @"";
        _font = [NSFont boldSystemFontOfSize:13.0f];
        _textColor = [NSColor whiteColor];
        _fillColor = [NSColor colorWithCalibratedWhite:0.1f alpha:0.85f];
        _textPadding = NSMakeSize(20.0f, 12.0f);
        _cornerRadius = 10.0f;
        _hudAlpha = 1.0f;
    }
    return self;
}

- (BOOL)isOpaque {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = self.bounds;
    if (bounds.size.width <= 0.0f || bounds.size.height <= 0.0f) {
        return;
    }

    CGFloat alpha = MAX(0.0f, MIN(1.0f, self.hudAlpha));
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bounds
                                                         xRadius:self.cornerRadius
                                                         yRadius:self.cornerRadius];
    NSColor *fill = self.fillColor ?: [NSColor colorWithCalibratedWhite:0.1f alpha:0.85f];
    fill = [fill colorWithAlphaComponent:(fill.alphaComponent * alpha)];
    [fill setFill];
    [path fill];

    if (self.message.length == 0) {
        return;
    }

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    style.lineBreakMode = NSLineBreakByTruncatingTail;

    NSColor *textColor = self.textColor ?: [NSColor whiteColor];
    textColor = [textColor colorWithAlphaComponent:(textColor.alphaComponent * alpha)];
    NSDictionary *attributes = @{
        NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:13.0f],
        NSForegroundColorAttributeName: textColor,
        NSParagraphStyleAttributeName: style
    };

    NSRect textRect = NSInsetRect(bounds, self.textPadding.width, self.textPadding.height);
    [self.message drawInRect:textRect withAttributes:attributes];
}

@end
