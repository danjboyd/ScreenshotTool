/*
 * MarkupText.m
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

#import "MarkupText.h"
#include <float.h>

static inline CGFloat STTextLineHeight(NSFont *font) {
    if (!font) {
        return 14.0f;
    }
    return ceil([font ascender] - [font descender] + [font leading]);
}

@interface MarkupText ()
@property (nonatomic, assign, readwrite) NSSize measuredSize;
@end

@implementation MarkupText

- (instancetype)initWithText:(NSString *)text
                        font:(NSFont *)font
                       color:(NSColor *)color
                      origin:(NSPoint)origin
                      boxSize:(NSSize)boxSize {
    self = [super init];
    if (self) {
        _text = [text copy] ?: @"";
        _font = font ?: [NSFont systemFontOfSize:18.0];
        _color = color ?: [NSColor whiteColor];
        _origin = origin;
        _boxSize = NSMakeSize(MAX(1.0f, boxSize.width), MAX(1.0f, boxSize.height));
        [self updateMeasuredSize];
    }
    return self;
}

- (void)setText:(NSString *)text {
    _text = [text copy] ?: @"";
    [self updateMeasuredSize];
}

- (void)setFont:(NSFont *)font {
    _font = font ?: [NSFont systemFontOfSize:18.0];
    [self updateMeasuredSize];
}

- (void)setColor:(NSColor *)color {
    _color = color ?: [NSColor whiteColor];
}

- (NSAttributedString *)attributedString {
    return [self attributedStringWithFont:self.font ?: [NSFont systemFontOfSize:18.0]];
}

- (NSAttributedString *)attributedStringWithFont:(NSFont *)font {
    NSMutableDictionary<NSAttributedStringKey, id> *attributes = [[NSMutableDictionary alloc] init];
    attributes[NSFontAttributeName] = font;
    attributes[NSForegroundColorAttributeName] = self.color ?: [NSColor whiteColor];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByWordWrapping;
    style.alignment = NSTextAlignmentLeft;
    attributes[NSParagraphStyleAttributeName] = style;
    return [[NSAttributedString alloc] initWithString:self.text ?: @"" attributes:attributes];
}

- (void)setBoxSize:(NSSize)boxSize {
    _boxSize = NSMakeSize(MAX(1.0f, boxSize.width), MAX(1.0f, boxSize.height));
}

- (void)updateMeasuredSize {
    NSAttributedString *attr = [self attributedString];
    if (attr.length == 0) {
        CGFloat lineHeight = STTextLineHeight(self.font);
        self.measuredSize = NSMakeSize(MAX(1.0f, lineHeight * 0.8f), lineHeight);
        return;
    }

    NSSize constraint = NSMakeSize(MAX(1.0f, self.boxSize.width), FLT_MAX);
    NSRect bounding = [attr boundingRectWithSize:constraint
                                         options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)];
    NSSize size = NSMakeSize(ceil(MAX(bounding.size.width, 1.0)),
                             ceil(MAX(bounding.size.height, STTextLineHeight(self.font))));
    size.width = ceil(MAX(size.width, 1.0));
    self.measuredSize = size;
}

- (NSRect)textRectForCanvas {
    return NSMakeRect(self.origin.x,
                      self.origin.y,
                      MAX(1.0f, self.boxSize.width),
                      MAX(1.0f, self.boxSize.height));
}

- (NSRect)bounds {
    return [self textRectForCanvas];
}

- (NSRect)textBounds {
    return NSMakeRect(self.origin.x, self.origin.y, self.measuredSize.width, self.measuredSize.height);
}

- (CGFloat)lineHeight {
    return STTextLineHeight(self.font);
}

- (NSSize)measuredSizeForWrapWidth:(CGFloat)wrapWidth {
    NSAttributedString *attr = [self attributedString];
    CGFloat lineHeight = STTextLineHeight(self.font);
    if (attr.length == 0) {
        return NSMakeSize(MAX(1.0f, lineHeight * 0.8f), lineHeight);
    }
    NSRect bounding = [attr boundingRectWithSize:NSMakeSize(MAX(1.0f, wrapWidth), FLT_MAX)
                                         options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)];
    return NSMakeSize(ceil(MAX(bounding.size.width, 1.0)), ceil(MAX(bounding.size.height, lineHeight)));
}

- (BOOL)fitToTextWithinCanvasSize:(NSSize)canvasSize {
    CGFloat lineHeight = STTextLineHeight(self.font);
    CGFloat pointSize = self.font.pointSize > 0.0 ? self.font.pointSize : 18.0;
    NSPoint origin = self.origin;

    // Keep a few characters of room at the right edge rather than wrapping every glyph.
    CGFloat minWrapWidth = MIN(MAX(canvasSize.width, 1.0), MAX(lineHeight * 2.0, pointSize * 3.0));
    origin.x = MAX(0.0, MIN(origin.x, canvasSize.width - minWrapWidth));
    origin.y = MAX(0.0, MIN(origin.y, canvasSize.height - lineHeight));
    CGFloat availableWidth = MAX(minWrapWidth, canvasSize.width - origin.x);

    CGFloat wrapWidth = self.widthIsFixed ? MIN(MAX(self.boxSize.width, minWrapWidth), availableWidth) : availableWidth;
    NSSize measured = [self measuredSizeForWrapWidth:wrapWidth];

    CGFloat width = wrapWidth;
    if (!self.widthIsFixed) {
        // Slack keeps zoom-scaled fonts, whose hinted advances run slightly wider, from re-wrapping.
        CGFloat slack = ceil(pointSize * 0.25) + 2.0;
        width = MIN(availableWidth, MAX(lineHeight, measured.width + slack));
    }
    CGFloat height = MAX(measured.height, lineHeight);
    if (origin.y + height > canvasSize.height) {
        origin.y = MAX(0.0, canvasSize.height - height);
    }

    _origin = origin;
    _boxSize = NSMakeSize(ceil(width), ceil(height));
    self.measuredSize = measured;
    return height <= canvasSize.height + 0.5;
}

- (void)drawInCanvasAtScale:(CGFloat)scale {
    if (self.text.length == 0 || scale <= 0.0) {
        return;
    }
    // Lay out with a font scaled to the zoom, as the editing text view does, rather than scaling
    // 1x glyph advances through a transform: hinted advances don't scale evenly and spacing breaks.
    NSFont *baseFont = self.font ?: [NSFont systemFontOfSize:18.0];
    NSFont *font = baseFont;
    if (fabs(scale - 1.0) > 0.0001) {
        font = [NSFont fontWithName:baseFont.fontName size:MAX(1.0, baseFont.pointSize * scale)] ?: baseFont;
    }
    NSRect rect = [self textRectForCanvas];
    rect = NSMakeRect(rect.origin.x * scale, rect.origin.y * scale, rect.size.width * scale, rect.size.height * scale);
    [[self attributedStringWithFont:font] drawInRect:rect];
}

- (void)renderInContext:(NSGraphicsContext *)context canvasSize:(NSSize)canvasSize {
    if (self.text.length == 0 || self.boxSize.width <= 0.0 || self.boxSize.height <= 0.0) {
        return;
    }
    NSAttributedString *attr = [self attributedString];
    NSRect rect = [self textRectForCanvas];
    rect.origin.y = canvasSize.height - rect.origin.y - rect.size.height;
    [attr drawInRect:rect];
}

- (BOOL)containsPoint:(NSPoint)point {
    // Hit the text itself (with a little tolerance), not empty space in a wide box.
    return NSPointInRect(point, NSInsetRect([self textBounds], -4.0, -4.0));
}

- (id)copyWithZone:(NSZone *)zone {
    MarkupText *copy = [[[self class] allocWithZone:zone] initWithText:self.text
                                                                  font:self.font
                                                                 color:self.color
                                                                origin:self.origin
                                                                boxSize:self.boxSize];
    copy.widthIsFixed = self.widthIsFixed;
    return copy;
}

- (void)translateByOffset:(NSPoint)offset {
    self.origin = NSMakePoint(self.origin.x - offset.x, self.origin.y - offset.y);
}

@end
