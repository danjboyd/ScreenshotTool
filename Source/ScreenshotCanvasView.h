#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class MarkupStroke;
@class MarkupText;

typedef NS_ENUM(NSInteger, ScreenshotCanvasTool) {
    ScreenshotCanvasToolHighlighter = 0,
    ScreenshotCanvasToolPen = 1,
    ScreenshotCanvasToolEraser = 2,
    ScreenshotCanvasToolText = 3,
    ScreenshotCanvasToolSelect = 4
};

@interface ScreenshotCanvasView : NSView

@property (nonatomic, strong, nullable) NSImage *image;
@property (nonatomic, assign) ScreenshotCanvasTool activeTool;
@property (nonatomic, strong) NSColor *penColor;
@property (nonatomic, strong) NSColor *highlighterColor;
@property (nonatomic, strong) NSColor *textColor;
@property (nonatomic, assign) CGFloat penLineWidth;
@property (nonatomic, assign) CGFloat highlighterLineWidth;
@property (nonatomic, strong) NSFont *textFont;
@property (nonatomic, assign) CGFloat zoomScale;
@property (nonatomic, assign, getter=isFitToWindow) BOOL fitToWindow;
@property (nonatomic, weak, nullable) NSScrollView *hostScrollView;

- (void)loadImage:(nullable NSImage *)image;
- (void)updateForEnclosingBoundsChange;
- (nullable NSImage *)flattenedImage;
- (nullable NSImage *)flattenedImageForSelection;
- (BOOL)hasImage;
- (BOOL)hasSelection;
- (void)clearMarkup;
- (void)clearSelection;
- (BOOL)cropToActiveSelection;

@end

NS_ASSUME_NONNULL_END
