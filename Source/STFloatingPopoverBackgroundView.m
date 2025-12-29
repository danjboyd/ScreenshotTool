#import "STFloatingPopoverBackgroundView.h"
#import "STThemeUtilities.h"

static inline CGFloat STFPClamp(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    return MIN(MAX(value, minValue), maxValue);
}

@implementation STFloatingPopoverBackgroundView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _arrowEdge = NSMaxYEdge;
        _arrowOffset = 0.0;
        _arrowBase = 20.0;
        _arrowHeight = 12.0;
        _cornerRadius = 8.0;
    }
    return self;
}

- (BOOL)isFlipped {
    return NO;
}

- (BOOL)isOpaque {
    return NO;
}

- (void)setArrowEdge:(NSRectEdge)arrowEdge {
    if (_arrowEdge != arrowEdge) {
        _arrowEdge = arrowEdge;
        [self setNeedsDisplay:YES];
    }
}

- (void)setArrowOffset:(CGFloat)arrowOffset {
    if (fabs(_arrowOffset - arrowOffset) > 0.1) {
        _arrowOffset = arrowOffset;
        [self setNeedsDisplay:YES];
    }
}

- (void)setArrowBase:(CGFloat)arrowBase {
    if (fabs(_arrowBase - arrowBase) > 0.1) {
        _arrowBase = arrowBase;
        [self setNeedsDisplay:YES];
    }
}

- (void)setArrowHeight:(CGFloat)arrowHeight {
    if (fabs(_arrowHeight - arrowHeight) > 0.1) {
        _arrowHeight = arrowHeight;
        [self setNeedsDisplay:YES];
    }
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    if (fabs(_cornerRadius - cornerRadius) > 0.1) {
        _cornerRadius = cornerRadius;
        [self setNeedsDisplay:YES];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = self.bounds;
    if (bounds.size.width <= 1.0f || bounds.size.height <= 1.0f) {
        return;
    }

    CGFloat arrowHeight = MAX(self.arrowHeight, 0.0f);
    CGFloat arrowBase = MAX(self.arrowBase, 0.0f);
    CGFloat radius = MAX(self.cornerRadius, 2.0f);
    CGFloat inset = 0.5f;
    NSRect bodyRect = NSInsetRect(bounds, inset, inset);

    switch (self.arrowEdge) {
        case NSMinYEdge:
            bodyRect.origin.y += arrowHeight;
            bodyRect.size.height -= arrowHeight;
            break;
        case NSMaxYEdge:
            bodyRect.size.height -= arrowHeight;
            break;
        case NSMinXEdge:
            bodyRect.origin.x += arrowHeight;
            bodyRect.size.width -= arrowHeight;
            break;
        case NSMaxXEdge:
            bodyRect.size.width -= arrowHeight;
            break;
        default:
            break;
    }

    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bodyRect xRadius:radius yRadius:radius];

    CGFloat arrowHalf = arrowBase * 0.5f;
    CGFloat minimumOffset = radius + arrowHalf + 2.0f;

    switch (self.arrowEdge) {
        case NSMinYEdge: {
            CGFloat baseY = NSMinY(bodyRect);
            CGFloat tipY = baseY - arrowHeight;
            CGFloat centerX = STFPClamp(self.arrowOffset, bodyRect.origin.x + minimumOffset, NSMaxX(bodyRect) - minimumOffset);
            NSBezierPath *arrow = [NSBezierPath bezierPath];
            [arrow moveToPoint:NSMakePoint(centerX, tipY)];
            [arrow lineToPoint:NSMakePoint(centerX + arrowHalf, baseY)];
            [arrow lineToPoint:NSMakePoint(centerX - arrowHalf, baseY)];
            [arrow closePath];
            [path appendBezierPath:arrow];
            break;
        }
        case NSMaxYEdge: {
            CGFloat baseY = NSMaxY(bodyRect);
            CGFloat tipY = baseY + arrowHeight;
            CGFloat centerX = STFPClamp(self.arrowOffset, bodyRect.origin.x + minimumOffset, NSMaxX(bodyRect) - minimumOffset);
            NSBezierPath *arrow = [NSBezierPath bezierPath];
            [arrow moveToPoint:NSMakePoint(centerX, tipY)];
            [arrow lineToPoint:NSMakePoint(centerX - arrowHalf, baseY)];
            [arrow lineToPoint:NSMakePoint(centerX + arrowHalf, baseY)];
            [arrow closePath];
            [path appendBezierPath:arrow];
            break;
        }
        case NSMinXEdge: {
            CGFloat baseX = NSMinX(bodyRect);
            CGFloat tipX = baseX - arrowHeight;
            CGFloat centerY = STFPClamp(self.arrowOffset, bodyRect.origin.y + minimumOffset, NSMaxY(bodyRect) - minimumOffset);
            NSBezierPath *arrow = [NSBezierPath bezierPath];
            [arrow moveToPoint:NSMakePoint(tipX, centerY)];
            [arrow lineToPoint:NSMakePoint(baseX, centerY + arrowHalf)];
            [arrow lineToPoint:NSMakePoint(baseX, centerY - arrowHalf)];
            [arrow closePath];
            [path appendBezierPath:arrow];
            break;
        }
        case NSMaxXEdge: {
            CGFloat baseX = NSMaxX(bodyRect);
            CGFloat tipX = baseX + arrowHeight;
            CGFloat centerY = STFPClamp(self.arrowOffset, bodyRect.origin.y + minimumOffset, NSMaxY(bodyRect) - minimumOffset);
            NSBezierPath *arrow = [NSBezierPath bezierPath];
            [arrow moveToPoint:NSMakePoint(tipX, centerY)];
            [arrow lineToPoint:NSMakePoint(baseX, centerY - arrowHalf)];
            [arrow lineToPoint:NSMakePoint(baseX, centerY + arrowHalf)];
            [arrow closePath];
            [path appendBezierPath:arrow];
            break;
        }
        default:
            break;
    }

    [[NSColor windowBackgroundColor] setFill];
    [path fill];

    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.18] setStroke];
    [path setLineWidth:1.0];
    [path stroke];
}

@end
