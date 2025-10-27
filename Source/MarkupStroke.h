#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, MarkupStrokeType) {
    MarkupStrokeTypePen = 0,
    MarkupStrokeTypeHighlighter = 1
};

@interface MarkupStroke : NSObject

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
- (void)translateByOffset:(NSPoint)offset clampToSize:(NSSize)size;

@end
