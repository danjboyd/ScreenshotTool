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
#import "ScreenshotToolSettings.h"
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

- (NSRect)decoratedTextBounds {
    CGFloat outset = [self decorationOutset];
    return NSInsetRect([self textBounds], -outset, -outset);
}

- (NSRect)decoratedBounds {
    NSRect bounds = [self decoratedTextBounds];
    if (!self.hasPointer) {
        return bounds;
    }
    CGFloat reach = [self pointerHeadLength] + [self pointerLineWidth];
    NSRect target = NSMakeRect(self.pointerTarget.x - reach, self.pointerTarget.y - reach, reach * 2.0, reach * 2.0);
    return NSUnionRect(bounds, target);
}

- (CGFloat)pointerLineWidth {
    return MAX(2.0, round([self stylePointSize] * 0.08));
}

- (CGFloat)pointerHeadLength {
    return MAX(10.0, [self pointerLineWidth] * 4.0);
}

- (NSPoint)pointerAnchor {
    NSRect box = [self decoratedTextBounds];
    NSPoint target = self.pointerTarget;
    NSPoint anchor = NSMakePoint(MAX(NSMinX(box), MIN(target.x, NSMaxX(box))),
                                 MAX(NSMinY(box), MIN(target.y, NSMaxY(box))));
    if (NSPointInRect(target, box)) {
        return target;
    }
    // From inside the box, step to the edge facing the target.
    CGFloat toLeft = fabs(anchor.x - NSMinX(box)), toRight = fabs(NSMaxX(box) - anchor.x);
    CGFloat toTop = fabs(anchor.y - NSMinY(box)), toBottom = fabs(NSMaxY(box) - anchor.y);
    if (target.y > NSMaxY(box) || target.y < NSMinY(box)) {
        anchor.y = (target.y > NSMaxY(box)) ? NSMaxY(box) : NSMinY(box);
    } else if (MIN(toLeft, toRight) <= MIN(toTop, toBottom)) {
        anchor.x = (target.x > NSMaxX(box)) ? NSMaxX(box) : NSMinX(box);
    }
    return anchor;
}

/// The callout pointer, drawn under the label so the box covers the tail's base.
- (void)drawPointerAtScale:(CGFloat)scale map:(NSPoint (^)(NSPoint))mapPoint {
    NSPoint target = self.pointerTarget;
    NSRect box = [self decoratedTextBounds];
    if (NSPointInRect(target, box)) {
        return;
    }
    NSPoint anchor = [self pointerAnchor];
    NSColor *color = self.color ?: [NSColor whiteColor];
    NSPoint (^scaled)(NSPoint) = ^NSPoint(NSPoint p) {
        return mapPoint(NSMakePoint(p.x * scale, p.y * scale));
    };
    CGFloat dx = target.x - anchor.x;
    CGFloat dy = target.y - anchor.y;
    CGFloat length = hypot(dx, dy);
    if (length < 1.0) {
        return;
    }
    CGFloat ux = dx / length, uy = dy / length;

    if (self.style == MarkupTextStyleBackground) {
        // A tail: wide where it meets the box, pointed at the target.
        CGFloat halfBase = MIN([self backgroundPadding] * 1.2, MIN(NSWidth(box), NSHeight(box)) * 0.3);
        NSPoint base = NSMakePoint(anchor.x - ux * halfBase, anchor.y - uy * halfBase);
        NSBezierPath *tail = [NSBezierPath bezierPath];
        [tail moveToPoint:scaled(target)];
        [tail lineToPoint:scaled(NSMakePoint(base.x - uy * halfBase, base.y + ux * halfBase))];
        [tail lineToPoint:scaled(NSMakePoint(base.x + uy * halfBase, base.y - ux * halfBase))];
        [tail closePath];
        [color setFill];
        [tail fill];
        return;
    }

    // Elsewhere: a line ending in an arrowhead.
    CGFloat lineWidth = [self pointerLineWidth];
    CGFloat head = MIN([self pointerHeadLength], length);
    NSPoint headBase = NSMakePoint(target.x - ux * head, target.y - uy * head);
    NSPoint shaftEnd = NSMakePoint(target.x - ux * head * 0.6, target.y - uy * head * 0.6);
    [color setStroke];
    [color setFill];
    NSBezierPath *line = [NSBezierPath bezierPath];
    [line setLineWidth:lineWidth * scale];
    [line setLineCapStyle:NSRoundLineCapStyle];
    [line moveToPoint:scaled(anchor)];
    [line lineToPoint:scaled(shaftEnd)];
    [line stroke];
    CGFloat halfWidth = head * 0.5;
    NSBezierPath *tip = [NSBezierPath bezierPath];
    [tip moveToPoint:scaled(target)];
    [tip lineToPoint:scaled(NSMakePoint(headBase.x - uy * halfWidth, headBase.y + ux * halfWidth))];
    [tip lineToPoint:scaled(NSMakePoint(headBase.x + uy * halfWidth, headBase.y - ux * halfWidth))];
    [tip closePath];
    [tip fill];
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

    if (self.hasPointer) {
        [self drawPointerAtScale:scale map:^NSPoint(NSPoint p) {
            return unflippedHeight > 0.0 ? NSMakePoint(p.x, unflippedHeight - p.y) : p;
        }];
    }

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
    if (NSPointInRect(point, NSInsetRect([self decoratedTextBounds], -4.0, -4.0))) {
        return YES;
    }
    if (!self.hasPointer) {
        return NO;
    }
    // ...or the pointer, but not the empty space between the label and its target.
    NSPoint a = [self pointerAnchor];
    NSPoint b = self.pointerTarget;
    CGFloat vx = b.x - a.x, vy = b.y - a.y;
    CGFloat lengthSquared = vx * vx + vy * vy;
    CGFloat t = lengthSquared > 0.0 ? ((point.x - a.x) * vx + (point.y - a.y) * vy) / lengthSquared : 0.0;
    t = MAX(0.0, MIN(1.0, t));
    CGFloat px = a.x + t * vx - point.x, py = a.y + t * vy - point.y;
    CGFloat reach = MAX(6.0, [self pointerHeadLength] * 0.5);
    return (px * px + py * py) <= reach * reach;
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
    copy.hasPointer = self.hasPointer;
    copy.pointerTarget = self.pointerTarget;
    return copy;
}

- (void)translateByOffset:(NSPoint)offset {
    self.origin = NSMakePoint(self.origin.x - offset.x, self.origin.y - offset.y);
    // The pointer moves with its label.
    self.pointerTarget = NSMakePoint(self.pointerTarget.x - offset.x, self.pointerTarget.y - offset.y);
}

- (NSDictionary *)projectRepresentation {
    NSFont *font = self.font ?: [NSFont systemFontOfSize:18.0];
    return @{ @"text": self.text ?: @"",
              @"fontName": font.fontName ?: @"",
              @"fontSize": @(font.pointSize),
              @"color": STEncodeColor(self.color ?: [NSColor whiteColor]),
              @"origin": @[@(self.origin.x), @(self.origin.y)],
              @"boxSize": @[@(self.boxSize.width), @(self.boxSize.height)],
              @"widthIsFixed": @(self.widthIsFixed),
              @"style": @(self.style),
              @"alignment": @(STTextAlignmentCode(self.alignment)),
              @"hasPointer": @(self.hasPointer),
              @"pointerTarget": @[@(self.pointerTarget.x), @(self.pointerTarget.y)] };
}

static NSPoint STProjectPoint(id value, NSPoint fallback) {
    if (![value isKindOfClass:[NSArray class]] || [(NSArray *)value count] < 2) {
        return fallback;
    }
    return NSMakePoint([((NSArray *)value)[0] doubleValue], [((NSArray *)value)[1] doubleValue]);
}

+ (instancetype)textWithProjectRepresentation:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]] || ![dictionary[@"text"] isKindOfClass:[NSString class]]) {
        return nil;
    }
    CGFloat size = MAX(1.0, [dictionary[@"fontSize"] doubleValue]);
    NSString *fontName = [dictionary[@"fontName"] isKindOfClass:[NSString class]] ? dictionary[@"fontName"] : @"";
    NSFont *font = (fontName.length > 0 ? [NSFont fontWithName:fontName size:size] : nil) ?: [NSFont systemFontOfSize:size];
    NSPoint boxSize = STProjectPoint(dictionary[@"boxSize"], NSMakePoint(1.0, 1.0));
    MarkupText *text = [[self alloc] initWithText:dictionary[@"text"]
                                             font:font
                                            color:STDecodeColor(dictionary[@"color"], [NSColor whiteColor])
                                           origin:STProjectPoint(dictionary[@"origin"], NSZeroPoint)
                                           boxSize:NSMakeSize(boxSize.x, boxSize.y)];
    text.widthIsFixed = [dictionary[@"widthIsFixed"] boolValue];
    NSInteger style = [dictionary[@"style"] integerValue];
    text.style = (style >= MarkupTextStylePlain && style <= MarkupTextStyleBackground) ? (MarkupTextStyle)style : MarkupTextStylePlain;
    text.alignment = STTextAlignmentFromCode([dictionary[@"alignment"] integerValue]);
    text.hasPointer = [dictionary[@"hasPointer"] boolValue];
    text.pointerTarget = STProjectPoint(dictionary[@"pointerTarget"], NSZeroPoint);
    [text updateMeasuredSize];
    return text;
}

@end
