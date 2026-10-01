/*
 * MarkupText.h
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

NS_ASSUME_NONNULL_BEGIN

@interface MarkupText : NSObject <NSCopying>

@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic, strong) NSFont *font;
@property (nonatomic, assign) NSPoint origin;
@property (nonatomic, assign) NSSize boxSize;
@property (nonatomic, assign, readonly) NSSize measuredSize;

- (instancetype)initWithText:(NSString *)text
                        font:(NSFont *)font
                       color:(NSColor *)color
                      origin:(NSPoint)origin
                      boxSize:(NSSize)boxSize;

- (NSAttributedString *)attributedString;
- (void)drawInCanvas;
- (void)renderInContext:(NSGraphicsContext *)context canvasSize:(NSSize)canvasSize;
- (BOOL)containsPoint:(NSPoint)point;
- (void)updateMeasuredSize;
- (NSRect)bounds;
- (void)translateByOffset:(NSPoint)offset;

@end

NS_ASSUME_NONNULL_END
