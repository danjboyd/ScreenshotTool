/*
 * MarkupStroke.m
 * Copyright (C) 2025 Daniel Boyd
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA.
 */

#import "MarkupStroke.h"

static inline CGFloat sqr(CGFloat value) {
    return value * value;
}

static CGFloat distanceSquaredToSegment(NSPoint p, NSPoint v, NSPoint w) {
    CGFloat l2 = sqr(w.x - v.x) + sqr(w.y - v.y);
    if (l2 == 0.0) {
        return sqr(p.x - v.x) + sqr(p.y - v.y);
    }
    CGFloat t = ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2;
    t = MAX(0.0, MIN(1.0, t));
    CGFloat projX = v.x + t * (w.x - v.x);
    CGFloat projY = v.y + t * (w.y - v.y);
    return sqr(p.x - projX) + sqr(p.y - projY);
}

@interface MarkupStroke ()
@property (nonatomic, strong) NSMutableArray<NSValue *> *mutablePoints;
@property (nonatomic, strong) NSBezierPath *mutablePath;
@end

@implementation MarkupStroke

- (instancetype)initWithType:(MarkupStrokeType)type
                       color:(NSColor *)color
                    lineWidth:(CGFloat)lineWidth {
    self = [super init];
    if (self) {
        _type = type;
        _color = [color copy];
        _lineWidth = lineWidth;
        _mutablePoints = [[NSMutableArray alloc] init];
        _mutablePath = [NSBezierPath bezierPath];
        [_mutablePath setLineJoinStyle:NSRoundLineJoinStyle];
        [_mutablePath setLineCapStyle:NSRoundLineCapStyle];
    }
    return self;
}

- (NSArray<NSValue *> *)points {
    return [self.mutablePoints copy];
}

- (NSBezierPath *)path {
    return self.mutablePath;
}

- (void)addPoint:(NSPoint)point {
    if (self.mutablePoints.count == 0) {
        [self.mutablePoints addObject:[NSValue valueWithPoint:point]];
        [self.mutablePath moveToPoint:point];
        return;
    }

    NSPoint lastPoint = [[self.mutablePoints lastObject] pointValue];
    if (sqr(lastPoint.x - point.x) + sqr(lastPoint.y - point.y) < 0.25) {
        return;
    }

    [self.mutablePoints addObject:[NSValue valueWithPoint:point]];
    [self.mutablePath lineToPoint:point];
}

- (void)drawPath {
    if (self.mutablePoints.count == 0) {
        return;
    }

    NSColor *strokeColor = self.color;
    if (self.type == MarkupStrokeTypeHighlighter) {
        NSColor *calibrated = [strokeColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        if (!calibrated) {
            calibrated = strokeColor;
        }
        strokeColor = [calibrated colorWithAlphaComponent:0.35];
    }

    [strokeColor setStroke];
    [self.mutablePath setLineWidth:self.lineWidth];
    [self.mutablePath stroke];
}

- (BOOL)containsPoint:(NSPoint)point tolerance:(CGFloat)tolerance {
    if (self.mutablePoints.count == 0) {
        return NO;
    }

    CGFloat tol2 = sqr(MAX(tolerance, self.lineWidth * 0.5));

    if (self.mutablePoints.count == 1) {
        NSPoint onlyPoint = [[self.mutablePoints firstObject] pointValue];
        return sqr(point.x - onlyPoint.x) + sqr(point.y - onlyPoint.y) <= tol2;
    }

    for (NSUInteger idx = 0; idx + 1 < self.mutablePoints.count; ++idx) {
        NSPoint a = [self.mutablePoints[idx] pointValue];
        NSPoint b = [self.mutablePoints[idx + 1] pointValue];
        if (distanceSquaredToSegment(point, a, b) <= tol2) {
            return YES;
        }
    }
    return NO;
}

- (void)renderInContext:(NSGraphicsContext *)context canvasSize:(NSSize)size {
    if (self.mutablePoints.count == 0) {
        return;
    }

    // Caller is expected to make `context` current before invocation; flattening does this when it
    // binds the bitmap context. macOS lock-focus keeps this implicit, but GNUstep currently requires
    // us to manage it manually as part of the workaround.
    // GNUstep renders into an unflipped bitmap when we replay strokes off-screen, so we map
    // the view's flipped coordinates back to the origin-at-bottom convention that macOS would
    // normally handle for us when using -lockFocus on NSImage.
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineJoinStyle:NSRoundLineJoinStyle];
    [path setLineCapStyle:NSRoundLineCapStyle];
    [path setLineWidth:self.lineWidth];

    BOOL firstPoint = YES;
    for (NSValue *value in self.mutablePoints) {
        NSPoint point = value.pointValue;
        NSPoint mapped = NSMakePoint(point.x, size.height - point.y);
        if (firstPoint) {
            [path moveToPoint:mapped];
            firstPoint = NO;
        } else {
            [path lineToPoint:mapped];
        }
    }

    NSColor *strokeColor = self.color;
    if (self.type == MarkupStrokeTypeHighlighter) {
        NSColor *calibrated = [strokeColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        if (!calibrated) {
            calibrated = strokeColor;
        }
        strokeColor = [calibrated colorWithAlphaComponent:0.35];
    }
    // GNUstep drops strokes unless we force the color into the device RGB space. macOS promotes
    // colors automatically when drawing into an NSImage focus context, so we normalize here to
    // restore parity until the GNUstep color management bug is fixed.
    NSColor *deviceColor = [strokeColor colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    [(deviceColor ?: strokeColor) setStroke];

    if (self.mutablePoints.count == 1) {
        NSPoint p = NSMakePoint(self.mutablePoints.firstObject.pointValue.x,
                                size.height - self.mutablePoints.firstObject.pointValue.y);
        CGFloat radius = MAX(self.lineWidth, 1.0f);
        NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(p.x - radius * 0.5f,
                                                                             p.y - radius * 0.5f,
                                                                             radius,
                                                                             radius)];
        [(deviceColor ?: strokeColor) setFill];
        [dot fill];
    } else {
        [path stroke];
    }
}

- (id)copyWithZone:(NSZone *)zone {
    MarkupStroke *copy = [[[self class] allocWithZone:zone] initWithType:self.type
                                                                  color:[self.color copy]
                                                               lineWidth:self.lineWidth];
    copy.mutablePoints = [[NSMutableArray alloc] initWithArray:self.mutablePoints];
    copy.mutablePath = [self.mutablePath copy];
    return copy;
}

- (void)translateByOffset:(NSPoint)offset clampToSize:(NSSize)size {
    if (self.mutablePoints.count == 0) {
        return;
    }
    NSBezierPath *newPath = [NSBezierPath bezierPath];
    [newPath setLineJoinStyle:NSRoundLineJoinStyle];
    [newPath setLineCapStyle:NSRoundLineCapStyle];
    [newPath setLineWidth:self.lineWidth];

    NSMutableArray<NSValue *> *updatedPoints = [[NSMutableArray alloc] initWithCapacity:self.mutablePoints.count];
    BOOL first = YES;
    for (NSValue *value in self.mutablePoints) {
        NSPoint p = value.pointValue;
        p.x = MAX(0.0, MIN(size.width, p.x - offset.x));
        p.y = MAX(0.0, MIN(size.height, p.y - offset.y));
        if (first) {
            [newPath moveToPoint:p];
            first = NO;
        } else {
            [newPath lineToPoint:p];
        }
        [updatedPoints addObject:[NSValue valueWithPoint:p]];
    }

    self.mutablePoints = updatedPoints;
    self.mutablePath = newPath;
}

@end
