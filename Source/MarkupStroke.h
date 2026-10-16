/*
 * MarkupStroke.h
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

#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, MarkupStrokeType) {
    MarkupStrokeTypePen = 0,
    MarkupStrokeTypeHighlighter = 1,
    /// A straight arrow from the first point to the last, with a filled head (#33).
    MarkupStrokeTypeArrow = 2,
    /// A rectangle's outline, its corners the first point and the last (v0.2.0, #221).
    MarkupStrokeTypeRectangle = 3,
    /// A numbered step: a disc at its one point with its number in it (v0.2.0, #221).
    MarkupStrokeTypeStep = 4,
    /// A redaction: the image pixelated between its two corners (v0.2.0, #221). The canvas draws
    /// it, from the image; the stroke only holds the rect.
    MarkupStrokeTypeRedact = 5
};

NS_ASSUME_NONNULL_BEGIN

@interface MarkupStroke : NSObject <NSCopying>

@property (nonatomic, assign) MarkupStrokeType type;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic, assign) CGFloat lineWidth;
/// A step's number.
@property (nonatomic, assign) NSInteger number;

- (instancetype)initWithType:(MarkupStrokeType)type
                       color:(NSColor *)color
                    lineWidth:(CGFloat)lineWidth;

- (void)addPoint:(NSPoint)point;
/// For arrows and rectangles: keeps the start point and moves the end to this point.
- (void)setEndPoint:(NSPoint)point;
/// For rectangles: corners at these two points.
- (void)setStartPoint:(NSPoint)start endPoint:(NSPoint)end;
/// Arrows, rectangles and steps: drawn as shapes, with a white outline, not as a path of points.
- (BOOL)isShape;
/// A step's disc, across.
- (CGFloat)stepDiameter;
/// A rectangle's rect, from its two corners.
- (NSRect)shapeRect;
/// Length of an arrow's head, from its tip back to its base.
- (CGFloat)arrowHeadLength;
/// Draws an arrow in canvas coordinates; a positive unflippedHeight maps them into an unflipped
/// context of that height (export), zero draws straight into a flipped view.
- (void)drawArrowWithUnflippedHeight:(CGFloat)unflippedHeight;
/// Draws an arrow or a rectangle, as -drawArrowWithUnflippedHeight: does.
- (void)drawShapeWithUnflippedHeight:(CGFloat)unflippedHeight;
- (NSArray<NSValue *> *)points;
- (void)drawPath;
- (BOOL)containsPoint:(NSPoint)point tolerance:(CGFloat)tolerance;
- (NSBezierPath *)path;
- (void)renderInContext:(NSGraphicsContext *)context canvasSize:(NSSize)size;
- (NSRect)bounds;
- (void)translateByOffset:(NSPoint)offset;

/// A property-list form for project files (#32), and back. Returns nil for malformed input.
- (NSDictionary *)projectRepresentation;
+ (nullable instancetype)strokeWithProjectRepresentation:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
