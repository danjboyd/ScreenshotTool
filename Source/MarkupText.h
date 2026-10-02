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

/// How a text annotation stands out from the image behind it.
typedef NS_ENUM(NSInteger, MarkupTextStyle) {
    MarkupTextStylePlain = 0,
    /// A contrasting stroke around the glyphs.
    MarkupTextStyleOutline = 1,
    /// A soft dark shadow below and to the right of the glyphs.
    MarkupTextStyleShadow = 2,
    /// A rounded box in the text colour behind contrasting glyphs.
    MarkupTextStyleBackground = 3,
};

@interface MarkupText : NSObject <NSCopying>

@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic, strong) NSFont *font;
@property (nonatomic, assign) NSPoint origin;
@property (nonatomic, assign) NSSize boxSize;
@property (nonatomic, assign, readonly) NSSize measuredSize;
/// YES when the user set the wrap width by dragging or resizing; otherwise the box hugs the text.
@property (nonatomic, assign) BOOL widthIsFixed;
@property (nonatomic, assign) MarkupTextStyle style;

- (instancetype)initWithText:(NSString *)text
                        font:(NSFont *)font
                       color:(NSColor *)color
                      origin:(NSPoint)origin
                      boxSize:(NSSize)boxSize;

- (NSAttributedString *)attributedString;
- (void)drawInCanvasAtScale:(CGFloat)scale;
/// Draws the annotation, or only its outline/shadow/background, in canvas coordinates at the given
/// zoom. A positive unflippedHeight maps the canvas's top-down coordinates into an unflipped context
/// of that height (export bitmaps); zero draws straight into a flipped view such as the canvas.
- (void)drawAtScale:(CGFloat)scale unflippedHeight:(CGFloat)unflippedHeight decorationsOnly:(BOOL)decorationsOnly;
/// The colour the glyphs are drawn in: the text colour, or a contrasting one on a background box.
- (NSColor *)glyphColor;
/// How far the style draws outside the text, in image points.
- (CGFloat)decorationOutset;
/// The text plus its outline, shadow or background: what is visible and can be hit.
- (NSRect)decoratedBounds;
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
