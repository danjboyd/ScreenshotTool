#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MarkupText : NSObject

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
- (void)translateByOffset:(NSPoint)offset clampToSize:(NSSize)size;

@end

NS_ASSUME_NONNULL_END
