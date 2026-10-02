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
#import "ScreenshotToolSettings.h"

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

- (void)setEndPoint:(NSPoint)point {
    if (self.mutablePoints.count == 0) {
        [self addPoint:point];
        return;
    }
    NSValue *start = self.mutablePoints.firstObject;
    self.mutablePoints = [[NSMutableArray alloc] initWithObjects:start, [NSValue valueWithPoint:point], nil];
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineJoinStyle:NSRoundLineJoinStyle];
    [path setLineCapStyle:NSRoundLineCapStyle];
    [path moveToPoint:start.pointValue];
    [path lineToPoint:point];
    self.mutablePath = path;
}

- (CGFloat)arrowHeadLength {
    return MAX(10.0, self.lineWidth * 4.0);
}

- (void)drawArrowWithUnflippedHeight:(CGFloat)unflippedHeight {
    if (self.mutablePoints.count < 2) {
        return;
    }
    NSPoint start = [self.mutablePoints.firstObject pointValue];
    NSPoint end = [self.mutablePoints.lastObject pointValue];
    NSPoint (^map)(NSPoint) = ^NSPoint(NSPoint p) {
        return unflippedHeight > 0.0 ? NSMakePoint(p.x, unflippedHeight - p.y) : p;
    };
    CGFloat dx = end.x - start.x;
    CGFloat dy = end.y - start.y;
    CGFloat length = hypot(dx, dy);
    if (length < 0.5) {
        return;
    }
    CGFloat ux = dx / length;
    CGFloat uy = dy / length;
    CGFloat head = MIN([self arrowHeadLength], length);
    CGFloat halfWidth = head * 0.5;
    // The shaft stops inside the head so its round cap doesn't poke through the tip.
    NSPoint base = NSMakePoint(end.x - ux * head, end.y - uy * head);
    NSPoint shaftEnd = NSMakePoint(end.x - ux * head * 0.6, end.y - uy * head * 0.6);

    [self.color setStroke];
    [self.color setFill];
    NSBezierPath *shaft = [NSBezierPath bezierPath];
    [shaft setLineWidth:self.lineWidth];
    [shaft setLineCapStyle:NSRoundLineCapStyle];
    [shaft moveToPoint:map(start)];
    [shaft lineToPoint:map(shaftEnd)];
    [shaft stroke];

    NSBezierPath *tip = [NSBezierPath bezierPath];
    [tip setLineJoinStyle:NSRoundLineJoinStyle];
    [tip setLineWidth:MAX(1.0, self.lineWidth * 0.5)];
    [tip moveToPoint:map(end)];
    [tip lineToPoint:map(NSMakePoint(base.x - uy * halfWidth, base.y + ux * halfWidth))];
    [tip lineToPoint:map(NSMakePoint(base.x + uy * halfWidth, base.y - ux * halfWidth))];
    [tip closePath];
    [tip fill];
    [tip stroke];
}

- (void)drawPath {
    if (self.mutablePoints.count == 0) {
        return;
    }
    if (self.type == MarkupStrokeTypeArrow) {
        [self drawArrowWithUnflippedHeight:0.0];
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
    if (self.type == MarkupStrokeTypeArrow) {
        // The head is wider than the shaft.
        NSPoint end = [self.mutablePoints.lastObject pointValue];
        CGFloat reach = [self arrowHeadLength] * 0.6 + tolerance;
        return sqr(point.x - end.x) + sqr(point.y - end.y) <= sqr(reach);
    }
    return NO;
}

- (void)renderInContext:(NSGraphicsContext *)context canvasSize:(NSSize)size {
    if (self.mutablePoints.count == 0) {
        return;
    }

    if (self.type == MarkupStrokeTypeArrow) {
        [self drawArrowWithUnflippedHeight:size.height];
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

- (NSRect)bounds {
    if (self.mutablePoints.count == 0) {
        return NSZeroRect;
    }
    NSPoint first = [[self.mutablePoints firstObject] pointValue];
    CGFloat minX = first.x, maxX = first.x, minY = first.y, maxY = first.y;
    for (NSValue *value in self.mutablePoints) {
        NSPoint p = value.pointValue;
        minX = MIN(minX, p.x);
        maxX = MAX(maxX, p.x);
        minY = MIN(minY, p.y);
        maxY = MAX(maxY, p.y);
    }
    CGFloat inset = MAX(self.lineWidth, 1.0f) * 0.5f;
    if (self.type == MarkupStrokeTypeArrow) {
        inset = MAX(inset, [self arrowHeadLength] * 0.5f + 1.0f); // the head's wings reach past the shaft
    }
    return NSMakeRect(minX - inset, minY - inset, (maxX - minX) + inset * 2.0f, (maxY - minY) + inset * 2.0f);
}

- (void)translateByOffset:(NSPoint)offset {
    if (self.mutablePoints.count == 0) {
        return;
    }
    NSBezierPath *newPath = [NSBezierPath bezierPath];
    [newPath setLineJoinStyle:NSRoundLineJoinStyle];
    [newPath setLineCapStyle:NSRoundLineCapStyle];
    [newPath setLineWidth:self.lineWidth];

    // Points are not clamped: anything past the new edges is clipped when drawn, so strokes keep
    // their shape instead of collapsing onto the border.
    NSMutableArray<NSValue *> *updatedPoints = [[NSMutableArray alloc] initWithCapacity:self.mutablePoints.count];
    BOOL first = YES;
    for (NSValue *value in self.mutablePoints) {
        NSPoint p = value.pointValue;
        p.x -= offset.x;
        p.y -= offset.y;
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

- (NSDictionary *)projectRepresentation {
    NSMutableArray<NSArray<NSNumber *> *> *points = [[NSMutableArray alloc] initWithCapacity:self.mutablePoints.count];
    for (NSValue *value in self.mutablePoints) {
        NSPoint p = value.pointValue;
        [points addObject:@[@(p.x), @(p.y)]];
    }
    return @{ @"type": @(self.type),
              @"color": STEncodeColor(self.color ?: [NSColor blackColor]),
              @"lineWidth": @(self.lineWidth),
              @"points": points };
}

+ (instancetype)strokeWithProjectRepresentation:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSInteger type = [dictionary[@"type"] integerValue];
    NSArray *points = dictionary[@"points"];
    if (type < MarkupStrokeTypePen || type > MarkupStrokeTypeArrow || ![points isKindOfClass:[NSArray class]] || points.count == 0) {
        return nil;
    }
    MarkupStroke *stroke = [[self alloc] initWithType:(MarkupStrokeType)type
                                                color:STDecodeColor(dictionary[@"color"], [NSColor blackColor])
                                             lineWidth:MAX(0.5, [dictionary[@"lineWidth"] doubleValue])];
    for (NSArray *pair in points) {
        if (![pair isKindOfClass:[NSArray class]] || pair.count < 2) {
            return nil;
        }
        NSPoint p = NSMakePoint([pair[0] doubleValue], [pair[1] doubleValue]);
        if (type == MarkupStrokeTypeArrow && [stroke points].count >= 1) {
            [stroke setEndPoint:p];
        } else {
            [stroke addPoint:p];
        }
    }
    return stroke;
}

@end
