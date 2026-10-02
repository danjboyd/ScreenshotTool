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
/// YES when the user set the wrap width by dragging or resizing; otherwise the box hugs the text.
@property (nonatomic, assign) BOOL widthIsFixed;

- (instancetype)initWithText:(NSString *)text
                        font:(NSFont *)font
                       color:(NSColor *)color
                      origin:(NSPoint)origin
                      boxSize:(NSSize)boxSize;

- (NSAttributedString *)attributedString;
- (void)drawInCanvasAtScale:(CGFloat)scale;
- (void)renderInContext:(NSGraphicsContext *)context canvasSize:(NSSize)canvasSize;
- (BOOL)containsPoint:(NSPoint)point;
- (void)updateMeasuredSize;
- (NSRect)bounds;
/// The area the laid-out text covers, which can be smaller than a fixed-width box.
- (NSRect)textBounds;
- (CGFloat)lineHeight;
/// Sizes the box to the text: one line tall at least, width from the text unless fixed, kept
/// inside the canvas by wrapping at the right edge and moving up from the bottom edge.
/// Returns NO when the text is taller than the canvas and must overflow.
- (BOOL)fitToTextWithinCanvasSize:(NSSize)canvasSize;
- (void)translateByOffset:(NSPoint)offset;

@end

NS_ASSUME_NONNULL_END
