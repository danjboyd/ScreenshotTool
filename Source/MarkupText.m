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

- (void)translateByOffset:(NSPoint)offset clampToSize:(NSSize)size {
    NSPoint newOrigin = NSMakePoint(self.origin.x - offset.x,
                                    self.origin.y - offset.y);
    newOrigin.x = MAX(0.0, MIN(size.width - MAX(1.0f, self.boxSize.width), newOrigin.x));
    newOrigin.y = MAX(0.0, MIN(size.height - MAX(1.0f, self.boxSize.height), newOrigin.y));
    self.origin = newOrigin;
    self.boxSize = NSMakeSize(MAX(1.0f, MIN(self.boxSize.width, size.width)),
                              MAX(1.0f, MIN(self.boxSize.height, size.height)));
    [self updateMeasuredSize];
}

@end
