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
    return [self attributedStringWithFont:font color:self.color ?: [NSColor whiteColor]];
}

- (NSAttributedString *)attributedStringWithFont:(NSFont *)font color:(NSColor *)color {
    NSMutableDictionary<NSAttributedStringKey, id> *attributes = [[NSMutableDictionary alloc] init];
    attributes[NSFontAttributeName] = font;
    attributes[NSForegroundColorAttributeName] = color;
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByWordWrapping;
    style.alignment = self.alignment;
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

/// How far the widest line sits from the box's left edge, given the alignment.
- (CGFloat)alignmentOffset {
    CGFloat spare = MAX(0.0, self.boxSize.width - self.measuredSize.width);
    switch (self.alignment) {
        case NSTextAlignmentCenter:
            return floor(spare * 0.5);
        case NSTextAlignmentRight:
            return spare;
        default:
            return 0.0;
    }
}

- (NSRect)textBounds {
    return NSMakeRect(self.origin.x + [self alignmentOffset], self.origin.y, self.measuredSize.width, self.measuredSize.height);
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
    // Outlines, shadows and backgrounds draw outside the text; keep them on the image as well.
    CGFloat inset = [self decorationOutset];

    // Keep a few characters of room at the right edge rather than wrapping every glyph.
    CGFloat minWrapWidth = MIN(MAX(canvasSize.width - inset * 2.0, 1.0), MAX(lineHeight * 2.0, pointSize * 3.0));
    origin.x = MAX(inset, MIN(origin.x, canvasSize.width - inset - minWrapWidth));
    origin.y = MAX(inset, MIN(origin.y, canvasSize.height - inset - lineHeight));
    CGFloat availableWidth = MAX(minWrapWidth, canvasSize.width - inset - origin.x);

    CGFloat wrapWidth = self.widthIsFixed ? MIN(MAX(self.boxSize.width, minWrapWidth), availableWidth) : availableWidth;
    NSSize measured = [self measuredSizeForWrapWidth:wrapWidth];

    CGFloat width = wrapWidth;
    if (!self.widthIsFixed) {
        // Slack keeps zoom-scaled fonts, whose hinted advances run slightly wider, from re-wrapping.
        CGFloat slack = ceil(pointSize * 0.25) + 2.0;
        width = MIN(availableWidth, MAX(lineHeight, measured.width + slack));
    }
    CGFloat height = MAX(measured.height, lineHeight);
    if (origin.y + height > canvasSize.height - inset) {
        origin.y = MAX(0.0, canvasSize.height - inset - height);
    }

    _origin = origin;
    _boxSize = NSMakeSize(ceil(width), ceil(height));
    self.measuredSize = measured;
    return height + inset * 2.0 <= canvasSize.height + 0.5;
}

- (CGFloat)stylePointSize {
    return self.font.pointSize > 0.0 ? self.font.pointSize : 18.0;
}

- (CGFloat)outlineWidth {
    return MAX(1.0, round([self stylePointSize] * 0.07 * 2.0) / 2.0);
}

- (CGFloat)shadowOffset {
    return MAX(1.0, round([self stylePointSize] * 0.06));
}

- (CGFloat)backgroundPadding {
    return round([self stylePointSize] * 0.3) + 2.0;
}

- (CGFloat)decorationOutset {
    switch (self.style) {
        case MarkupTextStyleOutline:
            return ceil([self outlineWidth]);
        case MarkupTextStyleShadow:
            return ceil([self shadowOffset] * 1.5);
        case MarkupTextStyleBackground:
            return [self backgroundPadding];
        case MarkupTextStylePlain:
        default:
            return 0.0;
    }
}

- (NSRect)decoratedBounds {
    CGFloat outset = [self decorationOutset];
    return NSInsetRect([self textBounds], -outset, -outset);
}

/// Black or white, whichever reads better against the text colour.
- (NSColor *)contrastingColor {
    NSColor *color = [(self.color ?: [NSColor whiteColor]) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    CGFloat red = 1.0, green = 1.0, blue = 1.0, alpha = 1.0;
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    CGFloat luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue);
    return luminance > 0.55 ? [NSColor blackColor] : [NSColor whiteColor];
}

- (NSColor *)glyphColor {
    if (self.style == MarkupTextStyleBackground) {
        return [self contrastingColor];
    }
    return self.color ?: [NSColor whiteColor];
}

- (void)drawInCanvasAtScale:(CGFloat)scale {
    [self drawAtScale:scale unflippedHeight:0.0 decorationsOnly:NO];
}

- (void)drawAtScale:(CGFloat)scale unflippedHeight:(CGFloat)unflippedHeight decorationsOnly:(BOOL)decorationsOnly {
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

    NSRect box = [self textRectForCanvas];
    NSRect textRect = NSMakeRect(box.origin.x * scale, box.origin.y * scale, box.size.width * scale, box.size.height * scale);
    // Rects are worked out top-down, as on the canvas, then mapped for unflipped contexts.
    NSRect (^map)(NSRect) = ^NSRect(NSRect rect) {
        if (unflippedHeight > 0.0) {
            rect.origin.y = unflippedHeight - rect.origin.y - rect.size.height;
        }
        return rect;
    };
    void (^drawGlyphs)(NSColor *, CGFloat, CGFloat) = ^(NSColor *color, CGFloat dx, CGFloat dy) {
        NSRect rect = NSOffsetRect(textRect, dx, dy);
        [[self attributedStringWithFont:font color:color] drawInRect:map(rect)];
    };

    switch (self.style) {
        case MarkupTextStyleOutline: {
            // Copies of the text in a ring around it make an outline that works with any font.
            CGFloat width = [self outlineWidth] * scale;
            NSColor *outline = [self contrastingColor];
            for (NSInteger step = 0; step < 16; step++) {
                CGFloat angle = (M_PI * 2.0 * step) / 16.0;
                drawGlyphs(outline, cos(angle) * width, sin(angle) * width);
            }
            break;
        }
        case MarkupTextStyleShadow: {
            // A few offset passes at low opacity read as a soft shadow.
            CGFloat offset = [self shadowOffset] * scale;
            drawGlyphs([NSColor colorWithDeviceWhite:0.0 alpha:0.18], offset * 1.5, offset * 1.5);
            drawGlyphs([NSColor colorWithDeviceWhite:0.0 alpha:0.30], offset, offset);
            drawGlyphs([NSColor colorWithDeviceWhite:0.0 alpha:0.30], offset * 0.5, offset * 0.5);
            break;
        }
        case MarkupTextStyleBackground: {
            CGFloat padding = [self backgroundPadding] * scale;
            NSRect used = NSMakeRect((box.origin.x + [self alignmentOffset]) * scale, box.origin.y * scale,
                                     self.measuredSize.width * scale, self.measuredSize.height * scale);
            NSRect pill = NSInsetRect(used, -padding, -padding);
            CGFloat radius = MIN(padding * 1.2, pill.size.height * 0.5);
            [(self.color ?: [NSColor whiteColor]) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:map(pill) xRadius:radius yRadius:radius] fill];
            break;
        }
        case MarkupTextStylePlain:
        default:
            break;
    }

    if (!decorationsOnly) {
        drawGlyphs([self glyphColor], 0.0, 0.0);
    }
}

- (void)renderInContext:(NSGraphicsContext *)context canvasSize:(NSSize)canvasSize {
    (void)context;
    if (self.boxSize.width <= 0.0 || self.boxSize.height <= 0.0) {
        return;
    }
    [self drawAtScale:1.0 unflippedHeight:canvasSize.height decorationsOnly:NO];
}

- (BOOL)containsPoint:(NSPoint)point {
    // Hit the text itself (with a little tolerance), not empty space in a wide box.
    return NSPointInRect(point, NSInsetRect([self decoratedBounds], -4.0, -4.0));
}

- (id)copyWithZone:(NSZone *)zone {
    MarkupText *copy = [[[self class] allocWithZone:zone] initWithText:self.text
                                                                  font:self.font
                                                                 color:self.color
                                                                origin:self.origin
                                                                boxSize:self.boxSize];
    copy.widthIsFixed = self.widthIsFixed;
    copy.style = self.style;
    copy.alignment = self.alignment;
    return copy;
}

- (void)translateByOffset:(NSPoint)offset {
    self.origin = NSMakePoint(self.origin.x - offset.x, self.origin.y - offset.y);
}

@end
