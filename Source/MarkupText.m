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
    NSMutableDictionary<NSAttributedStringKey, id> *attributes = [[NSMutableDictionary alloc] init];
    attributes[NSFontAttributeName] = self.font ?: [NSFont systemFontOfSize:18.0];
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

- (void)drawInCanvas {
    if (self.text.length == 0) {
        return;
    }
    NSAttributedString *attr = [self attributedString];
    NSRect rect = [self textRectForCanvas];
    [attr drawInRect:rect];
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
    return NSPointInRect(point, [self bounds]);
}

- (id)copyWithZone:(NSZone *)zone {
    MarkupText *copy = [[[self class] allocWithZone:zone] initWithText:self.text
                                                                  font:self.font
                                                                 color:self.color
                                                                origin:self.origin
                                                                boxSize:self.boxSize];
    return copy;
}

- (void)translateByOffset:(NSPoint)offset {
    self.origin = NSMakePoint(self.origin.x - offset.x, self.origin.y - offset.y);
}

@end
