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
    MarkupStrokeTypeHighlighter = 1
};

@interface MarkupStroke : NSObject <NSCopying>

@property (nonatomic, assign) MarkupStrokeType type;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic, assign) CGFloat lineWidth;

- (instancetype)initWithType:(MarkupStrokeType)type
                       color:(NSColor *)color
                    lineWidth:(CGFloat)lineWidth;

- (void)addPoint:(NSPoint)point;
- (NSArray<NSValue *> *)points;
- (void)drawPath;
- (BOOL)containsPoint:(NSPoint)point tolerance:(CGFloat)tolerance;
- (NSBezierPath *)path;
- (void)renderInContext:(NSGraphicsContext *)context canvasSize:(NSSize)size;
- (NSRect)bounds;
- (void)translateByOffset:(NSPoint)offset;

@end
