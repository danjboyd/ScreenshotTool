#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "MarkupText.h"
#include <math.h>
#include <string.h>
#include <float.h>

typedef struct {
    unsigned char *data;
    NSInteger width;
    NSInteger height;
    NSInteger bytesPerRow;
    NSInteger bytesPerPixel;
    NSInteger rIndex;
    NSInteger gIndex;
    NSInteger bIndex;
    NSInteger aIndex;
    BOOL hasAlpha;
} STBitmapBuffer;

static const CGFloat STSelectionHandleSize = 10.0f;

static inline unsigned char STRoundToByte(double value) {
    if (value <= 0.0) {
        return 0;
    }
    if (value >= 1.0) {
        return 255;
    }
    return (unsigned char)lrint(value * 255.0);
}

static BOOL STPrepareBitmapBuffer(NSBitmapImageRep *rep, STBitmapBuffer *buffer) {
    if (!rep || !buffer) {
        return NO;
    }
    if (rep.isPlanar || rep.bitsPerSample != 8) {
        return NO;
    }
    NSInteger width = rep.pixelsWide;
    NSInteger height = rep.pixelsHigh;
    NSInteger bytesPerRow = rep.bytesPerRow;
    if (width <= 0 || height <= 0 || bytesPerRow <= 0) {
        return NO;
    }
    unsigned char *data = rep.bitmapData;
    if (!data) {
        return NO;
    }

    NSInteger bytesPerPixel = bytesPerRow / width;
    if (bytesPerPixel < rep.samplesPerPixel) {
        bytesPerPixel = rep.samplesPerPixel;
    }

    BOOL hasAlpha = rep.hasAlpha;
    NSBitmapFormat format = rep.bitmapFormat;
    BOOL alphaFirst = ((format & NSAlphaFirstBitmapFormat) == NSAlphaFirstBitmapFormat);

    NSInteger aIndex = -1;
    NSInteger rIndex = 0;
    NSInteger gIndex = 1;
    NSInteger bIndex = 2;

    if (hasAlpha) {
        if (alphaFirst) {
            aIndex = 0;
            rIndex = 1;
            gIndex = 2;
            bIndex = 3;
        } else {
            aIndex = MIN(bytesPerPixel - 1, 3);
        }
    }

    buffer->data = data;
    buffer->width = width;
    buffer->height = height;
    buffer->bytesPerRow = bytesPerRow;
    buffer->bytesPerPixel = bytesPerPixel;
    buffer->rIndex = rIndex;
    buffer->gIndex = gIndex;
    buffer->bIndex = bIndex;
    buffer->aIndex = aIndex;
    buffer->hasAlpha = hasAlpha && (aIndex >= 0);
    return YES;
}

static inline void STBlendPixel(STBitmapBuffer *buffer,
                                NSInteger x,
                                NSInteger y,
                                double sr,
                                double sg,
                                double sb,
                                double sa) {
    if (!buffer || sa <= 0.0) {
        return;
    }
    if (x < 0 || x >= buffer->width || y < 0 || y >= buffer->height) {
        return;
    }

    NSInteger rowIndex = buffer->height - 1 - y;
    unsigned char *row = buffer->data + (buffer->bytesPerRow * rowIndex);
    unsigned char *pixel = row + (buffer->bytesPerPixel * x);

    double dr = pixel[buffer->rIndex] / 255.0;
    double dg = pixel[buffer->gIndex] / 255.0;
    double db = pixel[buffer->bIndex] / 255.0;

    double outR = sr * sa + dr * (1.0 - sa);
    double outG = sg * sa + dg * (1.0 - sa);
    double outB = sb * sa + db * (1.0 - sa);

    pixel[buffer->rIndex] = STRoundToByte(outR);
    pixel[buffer->gIndex] = STRoundToByte(outG);
    pixel[buffer->bIndex] = STRoundToByte(outB);

    if (buffer->hasAlpha) {
        double da = pixel[buffer->aIndex] / 255.0;
        double outA = sa + da * (1.0 - sa);
        pixel[buffer->aIndex] = STRoundToByte(outA);
    }
}

static void STBlendDisk(STBitmapBuffer *buffer,
                        double centerX,
                        double centerY,
                        double radius,
                        double sr,
                        double sg,
                        double sb,
                        double sa) {
    if (!buffer || sa <= 0.0 || radius <= 0.0) {
        return;
    }

    NSInteger minX = (NSInteger)floor(centerX - radius);
    NSInteger maxX = (NSInteger)ceil(centerX + radius);
    NSInteger minY = (NSInteger)floor(centerY - radius);
    NSInteger maxY = (NSInteger)ceil(centerY + radius);

    minX = MAX(0, minX);
    minY = MAX(0, minY);
    maxX = MIN(buffer->width - 1, maxX);
    maxY = MIN(buffer->height - 1, maxY);

    double radiusSquared = radius * radius;
    for (NSInteger y = minY; y <= maxY; ++y) {
        double dy = ((double)y + 0.5) - centerY;
        double dy2 = dy * dy;
        for (NSInteger x = minX; x <= maxX; ++x) {
            double dx = ((double)x + 0.5) - centerX;
            double distanceSquared = dx * dx + dy2;
            if (distanceSquared <= radiusSquared) {
                STBlendPixel(buffer, x, y, sr, sg, sb, sa);
            }
        }
    }
}

static void STRasterizeStrokeOntoBitmap(MarkupStroke *stroke,
                                        STBitmapBuffer *buffer,
                                        NSSize canvasSize) {
    if (!stroke || !buffer) {
        return;
    }

    NSArray<NSValue *> *points = [stroke points];
    NSUInteger count = points.count;
    if (count == 0) {
        return;
    }

    NSColor *strokeColor = stroke.color;
    if (stroke.type == MarkupStrokeTypeHighlighter) {
        NSColor *calibrated = [strokeColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        if (!calibrated) {
            calibrated = strokeColor;
        }
        strokeColor = [calibrated colorWithAlphaComponent:0.35];
    }
    NSColor *deviceColor = [strokeColor colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    if (!deviceColor) {
        deviceColor = strokeColor;
    }

    double sr = [deviceColor redComponent];
    double sg = [deviceColor greenComponent];
    double sb = [deviceColor blueComponent];
    double sa = [deviceColor alphaComponent];
    if (sa <= 0.0) {
        return;
    }

    double radius = MAX(stroke.lineWidth * 0.5, 0.5);
    double spacing = MAX(radius * 0.5, 0.75);

    NSPoint firstPoint = [points.firstObject pointValue];
    double prevX = firstPoint.x;
    double prevY = canvasSize.height - firstPoint.y;
    STBlendDisk(buffer, prevX, prevY, radius, sr, sg, sb, sa);

    for (NSUInteger idx = 1; idx < count; ++idx) {
        NSPoint current = [points[idx] pointValue];
        double currX = current.x;
        double currY = canvasSize.height - current.y;

        double dx = currX - prevX;
        double dy = currY - prevY;
        double distance = hypot(dx, dy);
        NSUInteger steps = (NSUInteger)ceil(distance / spacing);
        if (steps < 1) {
            steps = 1;
        }

        for (NSUInteger step = 1; step <= steps; ++step) {
            double t = (double)step / (double)steps;
            double sampleX = prevX + dx * t;
            double sampleY = prevY + dy * t;
            STBlendDisk(buffer, sampleX, sampleY, radius, sr, sg, sb, sa);
        }

        prevX = currX;
        prevY = currY;
    }
}

static void STRasterizeTextOntoBitmap(MarkupText *text,
                                      STBitmapBuffer *buffer,
                                      NSSize canvasSize) {
    if (!text || !buffer || !buffer->data) {
        return;
    }
    if (text.text.length == 0) {
        return;
    }

    NSInteger width = (NSInteger)ceil(MAX(1.0f, text.boxSize.width));
    NSInteger height = (NSInteger)ceil(MAX(1.0f, text.boxSize.height));
    if (width <= 0 || height <= 0) {
        return;
    }

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:width
                                                                    pixelsHigh:height
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    if (!rep) {
        return;
    }

    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    if (!context) {
        return;
    }

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, width, height));
    NSAttributedString *attr = [text attributedString];
    [attr drawInRect:NSMakeRect(0.0, 0.0, width, height)];
    [NSGraphicsContext restoreGraphicsState];

    unsigned char *data = rep.bitmapData;
    if (!data) {
        return;
    }

    NSInteger bytesPerPixel = MAX(1, rep.bitsPerPixel / 8);
    NSInteger bytesPerRow = rep.bytesPerRow;
    NSInteger rIndex = 0;
    NSInteger gIndex = 1;
    NSInteger bIndex = 2;
    NSInteger aIndex = 3;

    double destBaseX = text.origin.x;
    double destBaseY = canvasSize.height - text.origin.y - text.boxSize.height;

    for (NSInteger row = 0; row < height; row++) {
        NSInteger destY = (NSInteger)floor(destBaseY + row);
        if (destY < 0 || destY >= buffer->height) {
            continue;
        }
        unsigned char *srcRow = data + row * bytesPerRow;
        for (NSInteger col = 0; col < width; col++) {
            NSInteger destX = (NSInteger)floor(destBaseX + col);
            if (destX < 0 || destX >= buffer->width) {
                continue;
            }
            unsigned char *srcPixel = srcRow + col * bytesPerPixel;
            double alpha = srcPixel[aIndex] / 255.0;
            if (alpha <= 0.0) {
                continue;
            }
            double sr = srcPixel[rIndex] / 255.0;
            double sg = srcPixel[gIndex] / 255.0;
            double sb = srcPixel[bIndex] / 255.0;
            STBlendPixel(buffer, destX, destY, sr, sg, sb, alpha);
        }
    }
}

static NSBitmapImageRep *STBitmapImageRepCrop(NSBitmapImageRep *source, NSRect clipRect, NSSize canvasSize) {
    if (!source) {
        return nil;
    }

    NSInteger srcWidth = source.pixelsWide;
    NSInteger srcHeight = source.pixelsHigh;
    if (srcWidth <= 0 || srcHeight <= 0) {
        return nil;
    }

    CGFloat maxClipWidth = canvasSize.width > 0.0 ? canvasSize.width : (CGFloat)srcWidth;
    CGFloat maxClipHeight = canvasSize.height > 0.0 ? canvasSize.height : (CGFloat)srcHeight;

    CGFloat originXFloat = MAX(0.0, MIN(clipRect.origin.x, maxClipWidth));
    CGFloat originYTopFloat = MAX(0.0, MIN(clipRect.origin.y, maxClipHeight));
    CGFloat widthFloat = MAX(1.0, MIN(clipRect.size.width, maxClipWidth - originXFloat));
    CGFloat heightFloat = MAX(1.0, MIN(clipRect.size.height, maxClipHeight - originYTopFloat));

    NSInteger originX = (NSInteger)floor(originXFloat);
    NSInteger originYTop = (NSInteger)floor(originYTopFloat);
    NSInteger clipWidth = (NSInteger)ceil(widthFloat);
    NSInteger clipHeight = (NSInteger)ceil(heightFloat);

    if (originX >= srcWidth || originYTop >= srcHeight) {
        return nil;
    }

    if (originX + clipWidth > srcWidth) {
        clipWidth = srcWidth - originX;
    }
    if (originYTop + clipHeight > srcHeight) {
        clipHeight = srcHeight - originYTop;
    }

    if (clipWidth <= 0 || clipHeight <= 0) {
        return nil;
    }

    NSBitmapImageRep *dest = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                     pixelsWide:clipWidth
                                                                     pixelsHigh:clipHeight
                                                                  bitsPerSample:source.bitsPerSample
                                                                samplesPerPixel:source.samplesPerPixel
                                                                       hasAlpha:source.hasAlpha
                                                                       isPlanar:source.isPlanar
                                                                 colorSpaceName:source.colorSpaceName ?: NSDeviceRGBColorSpace
                                                                    bytesPerRow:0
                                                                   bitsPerPixel:source.bitsPerPixel];
    if (!dest) {
        return nil;
    }

    unsigned char *srcData = source.bitmapData;
    unsigned char *dstData = dest.bitmapData;
    if (!srcData || !dstData) {
        return dest;
    }

    NSInteger bytesPerPixel = MAX(1, source.bitsPerPixel / 8);
    NSInteger srcBytesPerRow = source.bytesPerRow;
    NSInteger dstBytesPerRow = dest.bytesPerRow;

    NSInteger bottomStartRow = srcHeight - originYTop - clipHeight;
    if (bottomStartRow < 0) {
        bottomStartRow = 0;
    }

    for (NSInteger row = 0; row < clipHeight; row++) {
        unsigned char *srcRow = srcData + ((bottomStartRow + row) * srcBytesPerRow) + originX * bytesPerPixel;
        unsigned char *dstRow = dstData + (row * dstBytesPerRow);
        memcpy(dstRow, srcRow, (size_t)clipWidth * (size_t)bytesPerPixel);
    }

    [dest setSize:NSMakeSize((CGFloat)clipWidth, (CGFloat)clipHeight)];
    return dest;
}
@interface ScreenshotCanvasView () <NSTextViewDelegate>
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@property (nonatomic, strong, nullable) MarkupStroke *currentStroke;
@property (nonatomic, strong) NSMutableArray<MarkupText *> *texts;
@property (nonatomic, strong, nullable) MarkupText *currentTextEntry;
@property (nonatomic, strong, nullable) NSTextView *activeTextView;
@property (nonatomic, assign) BOOL isCreatingTextBox;
@property (nonatomic, assign) BOOL isResizingTextBox;
@property (nonatomic, assign) NSRect pendingTextRect;
@property (nonatomic, assign) NSPoint textDragStartImagePoint;
@property (nonatomic, assign) NSPoint textResizeStartImagePoint;
@property (nonatomic, assign) NSSize textResizeStartBoxSize;
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
@property (nonatomic, assign) BOOL isCreatingSelection;
@property (nonatomic, assign) BOOL isResizingSelection;
@property (nonatomic, assign) BOOL isMovingSelection;
@property (nonatomic, assign) NSPoint selectionDragStartImagePoint;
@property (nonatomic, assign) NSRect selectionStartRect;
@property (nonatomic, strong, nullable) NSTimer *selectionDashTimer;
@property (nonatomic, assign) CGFloat selectionDashPhase;
@end

@implementation ScreenshotCanvasView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _strokes = [[NSMutableArray alloc] init];
        _texts = [[NSMutableArray alloc] init];
        _penColor = [NSColor redColor];
        _highlighterColor = [NSColor yellowColor];
        _textColor = [_penColor copy];
        _textFont = [NSFont systemFontOfSize:24.0f];
        _penLineWidth = 3.0;
        _highlighterLineWidth = 12.0;
        _zoomScale = 1.0;
        _fitToWindow = YES;
        _isCreatingTextBox = NO;
        _isResizingTextBox = NO;
        _pendingTextRect = NSZeroRect;
        _selectionDashPhase = 0.0f;
        [self setPostsFrameChangedNotifications:YES];
    }
    return self;
}

static NSBitmapImageRep *STBitmapImageRepFromImage(NSImage *image, NSSize size) {
    if (!image) {
        return nil;
    }

    NSBitmapImageRep *source = nil;
    for (NSImageRep *rep in [image representations]) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            source = (NSBitmapImageRep *)rep;
            break;
        }
    }

    if (!source) {
        NSData *tiff = [image TIFFRepresentation];
        if (tiff) {
            NSImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
            if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
                source = (NSBitmapImageRep *)rep;
            }
        }
    }

    if (!source) {
        return nil;
    }

    return STBitmapImageRepCrop(source, NSMakeRect(0.0, 0.0, size.width, size.height), size);
}

- (void)dealloc {
    if (self.hostScrollView) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSViewBoundsDidChangeNotification
                                                      object:self.hostScrollView.contentView];
    }
    if (self.activeTextView) {
        self.activeTextView.delegate = nil;
    }
    [self.selectionDashTimer invalidate];
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return YES;
}

- (void)setHostScrollView:(NSScrollView *)hostScrollView {
    if (_hostScrollView == hostScrollView) {
        return;
    }

    if (_hostScrollView) {
        NSClipView *clipView = _hostScrollView.contentView;
        [clipView setPostsBoundsChangedNotifications:NO];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSViewBoundsDidChangeNotification
                                                      object:clipView];
    }

    _hostScrollView = hostScrollView;

    if (_hostScrollView) {
        NSClipView *clipView = _hostScrollView.contentView;
        [clipView setPostsBoundsChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(clipViewBoundsDidChange:)
                                                     name:NSViewBoundsDidChangeNotification
                                                 object:clipView];
    }
}

- (void)setActiveTool:(ScreenshotCanvasTool)activeTool {
    if (_activeTool == activeTool) {
        return;
    }
    if (_activeTool == ScreenshotCanvasToolText) {
        [self commitActiveTextIfNeeded];
    }
    _activeTool = activeTool;
    if (_activeTool != ScreenshotCanvasToolText) {
        [self commitActiveTextIfNeeded];
        self.isCreatingTextBox = NO;
        self.isResizingTextBox = NO;
        self.pendingTextRect = NSZeroRect;
    }
    [self updateSelectionAnimationState];
    [self setNeedsDisplay:YES];
}

- (void)clipViewBoundsDidChange:(NSNotification *)notification {
    [self updateForEnclosingBoundsChange];
}

- (void)loadImage:(NSImage *)image {
    self.image = image;
    [self clearMarkup];
    [self clearSelection];
    _zoomScale = 1.0;
    self.fitToWindow = YES;
    [self updateForEnclosingBoundsChange];
    [self setNeedsDisplay:YES];
}

- (void)clearMarkup {
    [self cancelActiveTextEntry];
    [self.strokes removeAllObjects];
    [self.texts removeAllObjects];
    self.currentStroke = nil;
    self.pendingTextRect = NSZeroRect;
    self.isCreatingTextBox = NO;
    self.isResizingTextBox = NO;
    [self clearSelection];
    [self setNeedsDisplay:YES];
}

- (BOOL)hasImage {
    return (self.image != nil);
}

- (void)setZoomScale:(CGFloat)zoomScale {
    CGFloat clamped = MAX(0.05, MIN(zoomScale, 8.0));
    if (fabs(clamped - _zoomScale) < 0.0001) {
        return;
    }
    _zoomScale = clamped;
    [self updateFrameSize];
    [self setNeedsDisplay:YES];
    [self updateActiveTextViewFrame];
}

- (void)setFitToWindow:(BOOL)fitToWindow {
    if (_fitToWindow == fitToWindow) {
        return;
    }
    _fitToWindow = fitToWindow;
    if (fitToWindow) {
        [self updateForEnclosingBoundsChange];
    }
}

- (void)setTextColor:(NSColor *)textColor {
    NSColor *resolved = textColor ?: [NSColor whiteColor];
    if ([_textColor isEqual:resolved]) {
        return;
    }
    _textColor = [resolved copy];
    if (self.currentTextEntry) {
        self.currentTextEntry.color = _textColor;
    }
    if (self.activeTextView) {
        [self.activeTextView setTextColor:_textColor];
        [self.activeTextView setInsertionPointColor:_textColor];
    }
    [self setNeedsDisplay:YES];
}

- (void)setTextFont:(NSFont *)textFont {
    NSFont *resolved = textFont ?: [NSFont systemFontOfSize:24.0f];
    if ([_textFont isEqual:resolved]) {
        return;
    }
    _textFont = resolved;
    if (self.currentTextEntry) {
        self.currentTextEntry.font = _textFont;
    }
    [self updateActiveTextViewFrame];
    [self setNeedsDisplay:YES];
}

- (void)cancelActiveTextEntry {
    if (!self.activeTextView) {
        return;
    }
    self.activeTextView.delegate = nil;
    [self.activeTextView removeFromSuperview];
    self.activeTextView = nil;
    self.currentTextEntry = nil;
    self.isResizingTextBox = NO;
    self.pendingTextRect = NSZeroRect;
    [self updateSelectionAnimationState];
}

- (void)commitActiveTextIfNeeded {
    if (!self.activeTextView || !self.currentTextEntry) {
        return;
    }

    NSString *submitted = self.activeTextView.string ?: @"";
    NSString *trimmed = [submitted stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length > 0) {
        self.currentTextEntry.text = submitted;
        self.currentTextEntry.color = self.textColor ?: [NSColor whiteColor];
        NSRect viewFrame = self.activeTextView.frame;
        self.currentTextEntry.origin = NSMakePoint(viewFrame.origin.x / self.zoomScale,
                                                   viewFrame.origin.y / self.zoomScale);
        self.currentTextEntry.boxSize = NSMakeSize(viewFrame.size.width / self.zoomScale,
                                                   viewFrame.size.height / self.zoomScale);
        [self.currentTextEntry updateMeasuredSize];
        [self.texts addObject:self.currentTextEntry];
        [self setNeedsDisplay:YES];
    }

    [self cancelActiveTextEntry];
}

- (void)clearSelection {
    self.hasSelectionRect = NO;
    self.isCreatingSelection = NO;
    self.isMovingSelection = NO;
    self.isResizingSelection = NO;
    self.selectionRect = NSZeroRect;
    [self setNeedsDisplay:YES];
    [self updateSelectionAnimationState];
}

- (BOOL)hasSelection {
    return self.hasSelectionRect;
}

- (void)startSelectionDashAnimation {
    if (self.selectionDashTimer) {
        return;
    }
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.12
                                             target:self
                                           selector:@selector(selectionDashTimerFired:)
                                           userInfo:nil
                                            repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.selectionDashTimer = timer;
}

- (void)stopSelectionDashAnimation {
    [self.selectionDashTimer invalidate];
    self.selectionDashTimer = nil;
}

- (void)selectionDashTimerFired:(NSTimer *)timer {
    self.selectionDashPhase += 1.0f;
    if (self.selectionDashPhase >= 8.0f) {
        self.selectionDashPhase -= 8.0f;
    }
    [self setNeedsDisplay:YES];
}

- (void)updateSelectionAnimationState {
    if (self.hasSelectionRect || self.isCreatingSelection || self.isMovingSelection ||
        self.isResizingSelection || self.activeTextView || self.isCreatingTextBox || self.isResizingTextBox) {
        [self startSelectionDashAnimation];
    } else {
        [self stopSelectionDashAnimation];
        self.selectionDashPhase = 0.0f;
    }
}

- (NSPoint)viewPointForImagePoint:(NSPoint)imagePoint {
    return NSMakePoint(imagePoint.x * self.zoomScale, imagePoint.y * self.zoomScale);
}

- (NSFont *)scaledFontForEditing {
    CGFloat size = (self.textFont ?: [NSFont systemFontOfSize:24.0f]).pointSize * self.zoomScale;
    NSFont *font = self.textFont ?: [NSFont systemFontOfSize:24.0f];
    NSFont *scaled = [NSFont fontWithName:font.fontName size:MAX(1.0, size)];
    if (!scaled) {
        scaled = [NSFont systemFontOfSize:MAX(1.0, size)];
    }
    return scaled;
}

- (NSRect)viewRectForImageRect:(NSRect)imageRect {
    return NSMakeRect(imageRect.origin.x * self.zoomScale,
                      imageRect.origin.y * self.zoomScale,
                      imageRect.size.width * self.zoomScale,
                      imageRect.size.height * self.zoomScale);
}

- (NSRect)normalizedImageRectFromStart:(NSPoint)start end:(NSPoint)end {
    CGFloat minX = MIN(start.x, end.x);
    CGFloat minY = MIN(start.y, end.y);
    CGFloat width = MAX(fabs(end.x - start.x), 1.0f);
    CGFloat height = MAX(fabs(end.y - start.y), 1.0f);
    return NSMakeRect(minX, minY, width, height);
}

- (NSRect)clampedImageRect:(NSRect)rect {
    if (!self.image) {
        return rect;
    }
    NSSize imageSize = self.image.size;
    CGFloat originX = MAX(0.0f, MIN(rect.origin.x, imageSize.width));
    CGFloat originY = MAX(0.0f, MIN(rect.origin.y, imageSize.height));
    CGFloat maxWidth = MAX(0.0f, imageSize.width - originX);
    CGFloat maxHeight = MAX(0.0f, imageSize.height - originY);
    CGFloat width = MAX(0.0f, MIN(rect.size.width, maxWidth));
    CGFloat height = MAX(0.0f, MIN(rect.size.height, maxHeight));
    return NSMakeRect(originX, originY, width, height);
}

- (NSRect)integralSelectionRect {
    if (!self.image || !self.hasSelectionRect) {
        return NSZeroRect;
    }
    NSRect clamped = [self clampedImageRect:self.selectionRect];
    if (clamped.size.width <= 0.5f || clamped.size.height <= 0.5f) {
        return NSZeroRect;
    }
    CGFloat originX = floor(clamped.origin.x);
    CGFloat originY = floor(clamped.origin.y);
    CGFloat maxX = ceil(NSMaxX(clamped));
    CGFloat maxY = ceil(NSMaxY(clamped));
    maxX = MIN(maxX, self.image.size.width);
    maxY = MIN(maxY, self.image.size.height);
    return NSMakeRect(originX,
                      originY,
                      MAX(1.0f, maxX - originX),
                      MAX(1.0f, maxY - originY));
}

- (MarkupText *)textOverlayContainingImagePoint:(NSPoint)point {
    NSEnumerator<MarkupText *> *enumerator = [self.texts reverseObjectEnumerator];
    for (MarkupText *text in enumerator) {
        if ([text containsPoint:point]) {
            return text;
        }
    }
    return nil;
}

- (void)updateActiveTextViewFrame {
    if (!self.activeTextView || !self.currentTextEntry) {
        return;
    }

    NSSize boxSize = self.currentTextEntry.boxSize;
    CGFloat minWidth = MAX(40.0f, boxSize.width);
    CGFloat requiredHeight = MAX(self.currentTextEntry.measuredSize.height, boxSize.height);
    NSPoint origin = [self viewPointForImagePoint:self.currentTextEntry.origin];
    NSRect frame = NSMakeRect(origin.x,
                              origin.y,
                              minWidth * self.zoomScale,
                              requiredHeight * self.zoomScale);
    [self.activeTextView setFrame:frame];
    [self.activeTextView setMaxSize:NSMakeSize(frame.size.width, FLT_MAX)];

    NSTextContainer *container = self.activeTextView.textContainer;
    if (container) {
        NSSize containerSize = NSMakeSize(frame.size.width, FLT_MAX);
        [container setContainerSize:containerSize];
        [container setWidthTracksTextView:YES];
    }

    [self.activeTextView setFont:[self scaledFontForEditing]];
    [self.activeTextView setTextColor:self.textColor ?: [NSColor whiteColor]];
    [self.activeTextView setInsertionPointColor:self.textColor ?: [NSColor whiteColor]];

    self.currentTextEntry.boxSize = NSMakeSize(minWidth, requiredHeight);
}

- (void)beginTextEntryWithImageRect:(NSRect)imageRect existingText:(MarkupText * _Nullable)existingText {
    [self commitActiveTextIfNeeded];

    NSFont *baseFont = self.textFont ?: [NSFont systemFontOfSize:24.0f];
    NSColor *baseColor = self.textColor ?: [NSColor whiteColor];
    MarkupText *entry = existingText;
    if (!entry) {
        entry = [[MarkupText alloc] initWithText:@""
                                            font:baseFont
                                           color:baseColor
                                          origin:imageRect.origin
                                          boxSize:imageRect.size];
    } else {
        entry.origin = imageRect.origin;
        entry.boxSize = imageRect.size;
    }

    self.currentTextEntry = entry;
    [self.currentTextEntry updateMeasuredSize];
    self.pendingTextRect = NSZeroRect;

    NSRect viewRect = [self viewRectForImageRect:imageRect];
    NSTextView *textView = [[NSTextView alloc] initWithFrame:viewRect];
    [textView setDelegate:self];
    [textView setRichText:NO];
    [textView setEditable:YES];
    [textView setImportsGraphics:NO];
    [textView setDrawsBackground:YES];
    NSColor *background = [NSColor textBackgroundColor] ?: [NSColor lightGrayColor];
    if ([background respondsToSelector:@selector(colorWithAlphaComponent:)]) {
        background = [background colorWithAlphaComponent:0.15f];
    }
    [textView setBackgroundColor:background];
    [textView setTextColor:entry.color];
    [textView setFont:[self scaledFontForEditing]];
    [textView setInsertionPointColor:entry.color];
    [textView setHorizontallyResizable:NO];
    [textView setVerticallyResizable:YES];
    [textView setMaxSize:NSMakeSize(viewRect.size.width, FLT_MAX)];
    [textView setAutoresizingMask:NSViewNotSizable];
    textView.allowsUndo = YES;
    textView.string = entry.text ?: @"";

    NSTextContainer *container = textView.textContainer;
    if (container) {
        [container setWidthTracksTextView:YES];
        [container setContainerSize:NSMakeSize(viewRect.size.width, FLT_MAX)];
    }

    [self addSubview:textView];
    self.activeTextView = textView;

    NSWindow *window = self.window;
    if (window) {
        [window makeFirstResponder:textView];
    }

    [self updateActiveTextViewFrame];
    [self updateSelectionAnimationState];
}

#pragma mark - NSTextViewDelegate

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object != self.activeTextView || !self.currentTextEntry) {
        return;
    }
    self.currentTextEntry.text = self.activeTextView.string ?: @"";
    [self updateActiveTextViewFrame];
    [self setNeedsDisplay:YES];
}

- (void)textDidEndEditing:(NSNotification *)notification {
    if (notification.object != self.activeTextView) {
        return;
    }
    [self commitActiveTextIfNeeded];
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (textView != self.activeTextView) {
        return NO;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [self cancelActiveTextEntry];
        return YES;
    }
    return NO;
}

- (void)updateFrameSize {
    if (!self.image) {
        return;
    }
    NSSize imageSize = self.image.size;
    CGFloat width = round(imageSize.width * self.zoomScale);
    CGFloat height = round(imageSize.height * self.zoomScale);
    NSSize targetSize = NSMakeSize(MAX(width, 1.0f), MAX(height, 1.0f));
    [self setFrameSize:targetSize];
    [self updateScrollerVisibility];
    [self updateActiveTextViewFrame];
}

- (void)updateForEnclosingBoundsChange {
    if (!self.fitToWindow || !self.image || !self.hostScrollView) {
        return;
    }

    NSClipView *clipView = self.hostScrollView.contentView;
    NSRect clipBounds = clipView.bounds;
    NSSize imageSize = self.image.size;
    if (imageSize.width <= 0.0 || imageSize.height <= 0.0) {
        return;
    }

    CGFloat scaleX = clipBounds.size.width / imageSize.width;
    CGFloat scaleY = clipBounds.size.height / imageSize.height;
    CGFloat newScale = MIN(scaleX, scaleY);
    if (fabs(scaleX - scaleY) < 0.0005f) {
        newScale = scaleX;
    }
    newScale = MAX(0.05, MIN(newScale, 8.0));
    _zoomScale = newScale;
    [self updateFrameSize];
    [self setNeedsDisplay:YES];
    [self updateActiveTextViewFrame];
}

- (void)updateScrollerVisibility {
    if (!self.hostScrollView) {
        return;
    }
    BOOL shouldScroll = !self.fitToWindow;
    [self.hostScrollView setHasHorizontalScroller:shouldScroll];
    [self.hostScrollView setHasVerticalScroller:shouldScroll];
    if (!shouldScroll) {
        [self.hostScrollView flashScrollers];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(dirtyRect);

    if (!self.image) {
        return;
    }

    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform scaleBy:self.zoomScale];
    [transform concat];

    NSSize imageSize = self.image.size;
    NSRect imageRect = NSMakeRect(0.0, 0.0, imageSize.width, imageSize.height);
    [self.image drawInRect:imageRect
                  fromRect:NSZeroRect
                 operation:NSCompositeSourceOver
                  fraction:1.0
            respectFlipped:YES
                     hints:nil];

    for (MarkupStroke *stroke in self.strokes) {
        [stroke drawPath];
    }

    [self.currentStroke drawPath];

    for (MarkupText *text in self.texts) {
        [text drawInCanvas];
    }
    if (self.currentTextEntry && !self.activeTextView) {
        [self.currentTextEntry drawInCanvas];
    }

    [NSGraphicsContext restoreGraphicsState];

    if (self.activeTool == ScreenshotCanvasToolText) {
        [self drawTextGuides];
    }

    if (self.activeTool == ScreenshotCanvasToolSelect || self.hasSelectionRect || self.isCreatingSelection) {
        [self drawSelectionOverlay];
    }
}

- (void)drawTextGuides {
    NSColor *outline = [NSColor keyboardFocusIndicatorColor] ?: [NSColor grayColor];
    CGFloat dashPattern[] = {6.0f, 4.0f};
    const NSInteger dashCount = 2;
    CGFloat phase = self.selectionDashPhase;

    if (!NSIsEmptyRect(self.pendingTextRect) && self.isCreatingTextBox) {
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:[self viewRectForImageRect:self.pendingTextRect]];
        [path setLineWidth:1.0f];
        [path setLineDash:dashPattern count:dashCount phase:phase];
        [outline setStroke];
        [path stroke];
    }

    if (self.activeTextView && self.currentTextEntry) {
        NSRect viewRect = [self viewRectForImageRect:self.currentTextEntry.bounds];
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:viewRect];
        [path setLineWidth:1.0f];
        [path setLineDash:dashPattern count:dashCount phase:phase];
        [outline setStroke];
        [path stroke];

        NSRect handle = NSMakeRect(NSMaxX(viewRect) - STSelectionHandleSize,
                                   NSMaxY(viewRect) - STSelectionHandleSize,
                                   STSelectionHandleSize,
                                   STSelectionHandleSize);
        [[outline colorWithAlphaComponent:0.8f] setFill];
        NSBezierPath *handlePath = [NSBezierPath bezierPathWithRect:handle];
        [handlePath fill];
    }
}

- (NSRect)selectionHandleRectInView {
    if (!self.hasSelectionRect) {
        return NSZeroRect;
    }
    NSRect viewRect = [self viewRectForImageRect:self.selectionRect];
    return NSMakeRect(NSMaxX(viewRect) - STSelectionHandleSize,
                      NSMaxY(viewRect) - STSelectionHandleSize,
                      STSelectionHandleSize,
                      STSelectionHandleSize);
}

- (void)drawSelectionOverlay {
    if (!self.hasSelectionRect && !self.isCreatingSelection) {
        return;
    }
    CGFloat dashPattern[] = {5.0f, 3.0f};
    const NSInteger dashCount = 2;
    CGFloat phase = self.selectionDashPhase;

    NSRect clamped = [self clampedImageRect:self.selectionRect];
    if (NSIsEmptyRect(clamped)) {
        return;
    }
    NSRect viewRect = [self viewRectForImageRect:clamped];

    NSBezierPath *border = [NSBezierPath bezierPathWithRect:viewRect];
    [border setLineWidth:1.0f];
    [border setLineDash:dashPattern count:dashCount phase:phase];
    [[NSColor blackColor] setStroke];
    [border stroke];
    [border setLineDash:dashPattern count:dashCount phase:phase + 4.0f];
    [[NSColor whiteColor] setStroke];
    [border stroke];

    NSRect handleView = NSMakeRect(NSMaxX(viewRect) - STSelectionHandleSize,
                                   NSMaxY(viewRect) - STSelectionHandleSize,
                                   STSelectionHandleSize,
                                   STSelectionHandleSize);
    NSColor *handleColor = [NSColor alternateSelectedControlColor] ?: [NSColor grayColor];
    [[handleColor colorWithAlphaComponent:0.7f] setFill];
    [[NSBezierPath bezierPathWithRect:handleView] fill];
}

- (NSPoint)imagePointForEvent:(NSEvent *)event {
    NSPoint locationInView = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint imagePoint = NSMakePoint(locationInView.x / self.zoomScale,
                                     locationInView.y / self.zoomScale);
    if (self.image) {
        NSSize size = self.image.size;
        imagePoint.x = MAX(0.0, MIN(size.width, imagePoint.x));
        imagePoint.y = MAX(0.0, MIN(size.height, imagePoint.y));
    }
    return imagePoint;
}

- (void)eraseAtPoint:(NSPoint)point {
    [self commitActiveTextIfNeeded];

    CGFloat tolerance = 10.0 / self.zoomScale;
    BOOL removedStroke = NO;
    NSEnumerator<MarkupStroke *> *enumerator = [self.strokes reverseObjectEnumerator];
    MarkupStroke *stroke = nil;
    NSMutableArray<MarkupStroke *> *remaining = [[NSMutableArray alloc] init];

    while ((stroke = [enumerator nextObject])) {
        if (!removedStroke && [stroke containsPoint:point tolerance:tolerance]) {
            removedStroke = YES;
            continue;
        }
        [remaining insertObject:stroke atIndex:0];
    }

    BOOL removedText = NO;
    if (!removedStroke) {
        for (NSInteger idx = (NSInteger)self.texts.count - 1; idx >= 0; idx--) {
            MarkupText *text = self.texts[(NSUInteger)idx];
            if ([text containsPoint:point]) {
                [self.texts removeObjectAtIndex:(NSUInteger)idx];
                removedText = YES;
                break;
            }
        }
    }

    if (removedStroke) {
        self.strokes = remaining;
        [self setNeedsDisplay:YES];
        return;
    }

    if (removedText) {
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.image) {
        return;
    }

    NSPoint imagePoint = [self imagePointForEvent:event];
    NSPoint locationInView = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.activeTool == ScreenshotCanvasToolText) {
        if (self.activeTextView && self.currentTextEntry) {
            NSRect activeRect = [self viewRectForImageRect:self.currentTextEntry.bounds];
            NSRect handleRect = NSMakeRect(NSMaxX(activeRect) - STSelectionHandleSize,
                                           NSMaxY(activeRect) - STSelectionHandleSize,
                                           STSelectionHandleSize,
                                           STSelectionHandleSize);
            if (NSPointInRect(locationInView, handleRect)) {
                self.isResizingTextBox = YES;
                self.textResizeStartImagePoint = imagePoint;
                self.textResizeStartBoxSize = self.currentTextEntry.boxSize;
                [self updateSelectionAnimationState];
                return;
            }
            if (NSPointInRect(locationInView, activeRect)) {
                NSWindow *window = self.window;
                if (window) {
                    [window makeFirstResponder:self.activeTextView];
                }
                [super mouseDown:event];
                return;
            }
        }

        if (self.activeTextView) {
            [self commitActiveTextIfNeeded];
        }

        MarkupText *hitText = [self textOverlayContainingImagePoint:imagePoint];
        if (hitText) {
            [self.texts removeObject:hitText];
            [self beginTextEntryWithImageRect:[hitText bounds] existingText:hitText];
            return;
        }

        self.isCreatingTextBox = YES;
        self.textDragStartImagePoint = imagePoint;
        self.pendingTextRect = NSMakeRect(imagePoint.x, imagePoint.y, 1.0f, 1.0f);
        self.isResizingTextBox = NO;
        [self updateSelectionAnimationState];
        [self setNeedsDisplay:YES];
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolSelect) {
        [self commitActiveTextIfNeeded];

        if (self.hasSelectionRect) {
            NSRect selectionViewRect = [self viewRectForImageRect:self.selectionRect];
            NSRect handleRect = [self selectionHandleRectInView];
            if (NSPointInRect(locationInView, handleRect)) {
                self.isResizingSelection = YES;
                self.isMovingSelection = NO;
                self.isCreatingSelection = NO;
                self.selectionDragStartImagePoint = imagePoint;
                self.selectionStartRect = self.selectionRect;
                [self updateSelectionAnimationState];
                return;
            }
            if (NSPointInRect(locationInView, selectionViewRect)) {
                self.isMovingSelection = YES;
                self.isResizingSelection = NO;
                self.isCreatingSelection = NO;
                self.selectionDragStartImagePoint = imagePoint;
                self.selectionStartRect = self.selectionRect;
                [self updateSelectionAnimationState];
                return;
            }
        }

        self.isCreatingSelection = YES;
        self.isMovingSelection = NO;
        self.isResizingSelection = NO;
        self.selectionDragStartImagePoint = imagePoint;
        self.selectionRect = NSMakeRect(imagePoint.x, imagePoint.y, 1.0f, 1.0f);
        self.selectionStartRect = self.selectionRect;
        self.hasSelectionRect = YES;
        [self updateSelectionAnimationState];
        [self setNeedsDisplay:YES];
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolEraser) {
        [self eraseAtPoint:imagePoint];
        return;
    }

    MarkupStrokeType strokeType = (self.activeTool == ScreenshotCanvasToolHighlighter)
        ? MarkupStrokeTypeHighlighter
        : MarkupStrokeTypePen;
    NSColor *strokeColor = (strokeType == MarkupStrokeTypeHighlighter) ? self.highlighterColor : self.penColor;
    CGFloat width = (strokeType == MarkupStrokeTypeHighlighter) ? self.highlighterLineWidth : self.penLineWidth;

    self.currentStroke = [[MarkupStroke alloc] initWithType:strokeType
                                                      color:strokeColor
                                                   lineWidth:width];
    [self.currentStroke addPoint:imagePoint];
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.image) {
        return;
    }

    NSPoint imagePoint = [self imagePointForEvent:event];
    if (self.activeTool == ScreenshotCanvasToolText) {
        if (self.isCreatingTextBox) {
            NSRect rect = [self normalizedImageRectFromStart:self.textDragStartImagePoint end:imagePoint];
            if (self.image) {
                NSSize canvas = self.image.size;
                rect.origin.x = MAX(0.0f, MIN(rect.origin.x, canvas.width));
                rect.origin.y = MAX(0.0f, MIN(rect.origin.y, canvas.height));
                rect.size.width = MIN(rect.size.width, MAX(1.0f, canvas.width - rect.origin.x));
                rect.size.height = MIN(rect.size.height, MAX(1.0f, canvas.height - rect.origin.y));
            }
            self.pendingTextRect = rect;
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.isResizingTextBox && self.currentTextEntry) {
            CGFloat deltaX = imagePoint.x - self.textResizeStartImagePoint.x;
            CGFloat deltaY = imagePoint.y - self.textResizeStartImagePoint.y;
            CGFloat newWidth = MAX(40.0f, self.textResizeStartBoxSize.width + deltaX);
            CGFloat newHeight = MAX(30.0f, self.textResizeStartBoxSize.height + deltaY);
            if (self.image) {
                NSSize canvas = self.image.size;
                CGFloat maxWidth = MAX(1.0f, canvas.width - self.currentTextEntry.origin.x);
                CGFloat maxHeight = MAX(1.0f, canvas.height - self.currentTextEntry.origin.y);
                newWidth = MIN(MAX(newWidth, 40.0f), maxWidth);
                newHeight = MIN(MAX(newHeight, 30.0f), maxHeight);
            }
            self.currentTextEntry.boxSize = NSMakeSize(newWidth, newHeight);
            [self.currentTextEntry updateMeasuredSize];
            [self updateActiveTextViewFrame];
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.activeTextView) {
            [super mouseDragged:event];
        }
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolSelect) {
        if (self.isCreatingSelection) {
            NSRect rect = [self normalizedImageRectFromStart:self.selectionDragStartImagePoint end:imagePoint];
            rect = [self clampedImageRect:rect];
            self.selectionRect = rect;
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.isResizingSelection) {
            CGFloat deltaX = imagePoint.x - self.selectionDragStartImagePoint.x;
            CGFloat deltaY = imagePoint.y - self.selectionDragStartImagePoint.y;
            NSRect rect = self.selectionStartRect;
            rect.size.width = MAX(1.0f, rect.size.width + deltaX);
            rect.size.height = MAX(1.0f, rect.size.height + deltaY);
            rect = [self clampedImageRect:rect];
            self.selectionRect = rect;
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.isMovingSelection) {
            CGFloat deltaX = imagePoint.x - self.selectionDragStartImagePoint.x;
            CGFloat deltaY = imagePoint.y - self.selectionDragStartImagePoint.y;
            NSRect rect = self.selectionStartRect;
            rect.origin.x += deltaX;
            rect.origin.y += deltaY;
            rect = [self clampedImageRect:rect];
            self.selectionRect = rect;
            [self setNeedsDisplay:YES];
            return;
        }
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolEraser) {
        [self eraseAtPoint:imagePoint];
        return;
    }

    [self.currentStroke addPoint:imagePoint];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (!self.image) {
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolText) {
        if (self.isCreatingTextBox) {
            NSRect rect = self.pendingTextRect;
            self.isCreatingTextBox = NO;
            self.pendingTextRect = NSZeroRect;
            if (rect.size.width < 5.0f && rect.size.height < 5.0f) {
                rect = NSMakeRect(self.textDragStartImagePoint.x,
                                  self.textDragStartImagePoint.y,
                                  220.0f,
                                  80.0f);
            }
            rect.size.width = MAX(40.0f, rect.size.width);
            rect.size.height = MAX(30.0f, rect.size.height);
            if (self.image) {
                NSSize canvas = self.image.size;
                CGFloat maxWidth = MAX(1.0f, canvas.width - rect.origin.x);
                CGFloat maxHeight = MAX(1.0f, canvas.height - rect.origin.y);
                rect.size.width = MIN(MAX(rect.size.width, 40.0f), maxWidth);
                rect.size.height = MIN(MAX(rect.size.height, 30.0f), maxHeight);
                rect.origin.x = MAX(0.0f, MIN(rect.origin.x, canvas.width - rect.size.width));
                rect.origin.y = MAX(0.0f, MIN(rect.origin.y, canvas.height - rect.size.height));
            }
            [self beginTextEntryWithImageRect:rect existingText:nil];
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.isResizingTextBox) {
            self.isResizingTextBox = NO;
            if (self.currentTextEntry) {
                [self.currentTextEntry updateMeasuredSize];
                [self updateActiveTextViewFrame];
            }
            [self setNeedsDisplay:YES];
            [self updateSelectionAnimationState];
            return;
        }
        if (self.activeTextView) {
            [super mouseUp:event];
        }
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolSelect) {
        if (self.isCreatingSelection) {
            self.isCreatingSelection = NO;
            self.selectionRect = [self clampedImageRect:self.selectionRect];
            if (self.selectionRect.size.width < 2.0f || self.selectionRect.size.height < 2.0f) {
                [self clearSelection];
            } else {
                self.hasSelectionRect = YES;
                [self setNeedsDisplay:YES];
                [self updateSelectionAnimationState];
            }
            return;
        }
        if (self.isResizingSelection || self.isMovingSelection) {
            self.isResizingSelection = NO;
            self.isMovingSelection = NO;
            self.selectionRect = [self clampedImageRect:self.selectionRect];
            if (self.selectionRect.size.width < 2.0f || self.selectionRect.size.height < 2.0f) {
                [self clearSelection];
            } else {
                self.hasSelectionRect = YES;
                [self setNeedsDisplay:YES];
                [self updateSelectionAnimationState];
            }
            return;
        }
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolEraser) {
        return;
    }

    if (!self.currentStroke) {
        return;
    }

    NSPoint imagePoint = [self imagePointForEvent:event];
    [self.currentStroke addPoint:imagePoint];
    [self.strokes addObject:self.currentStroke];
    self.currentStroke = nil;
    [self setNeedsDisplay:YES];
}

- (NSImage *)flattenedImageWithinRect:(NSRect)clipRect {
    if (!self.image) {
        return nil;
    }

    [self commitActiveTextIfNeeded];

    NSSize size = self.image.size;
    if (size.width <= 0.0 || size.height <= 0.0) {
        return nil;
    }

    NSRect effectiveClip = clipRect;
    if (!NSIsEmptyRect(effectiveClip)) {
        effectiveClip = [self clampedImageRect:effectiveClip];
        if (effectiveClip.size.width < 1.0f || effectiveClip.size.height < 1.0f) {
            effectiveClip = NSZeroRect;
        }
    }

    NSInteger width = (NSInteger)lrint(size.width);
    NSInteger height = (NSInteger)lrint(size.height);
    if (width <= 0 || height <= 0) {
        return nil;
    }

    NSBitmapImageRep *bitmap = STBitmapImageRepFromImage(self.image, size);
    if (!bitmap) {
        bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                         pixelsWide:width
                                                         pixelsHigh:height
                                                      bitsPerSample:8
                                                    samplesPerPixel:4
                                                           hasAlpha:YES
                                                           isPlanar:NO
                                                     colorSpaceName:NSDeviceRGBColorSpace
                                                        bytesPerRow:0
                                                       bitsPerPixel:0];
        if (!bitmap) {
            return nil;
        }
        [bitmap setSize:size];

        NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        if (ctx) {
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:ctx];
            [[NSColor clearColor] setFill];
            NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
            [self.image drawInRect:NSMakeRect(0.0, 0.0, size.width, size.height)
                          fromRect:NSZeroRect
                         operation:NSCompositeSourceOver
                          fraction:1.0
                    respectFlipped:NO
                             hints:nil];
            [NSGraphicsContext restoreGraphicsState];
        }
    }

    NSGraphicsContext *bitmapContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    if (!bitmapContext) {
        return nil;
    }

    STBitmapBuffer buffer;
    BOOL canRasterizeDirectly = STPrepareBitmapBuffer(bitmap, &buffer);
    BOOL needsContextDrawing = !canRasterizeDirectly;

    if (needsContextDrawing) {
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:bitmapContext];

        for (MarkupText *text in self.texts) {
            [text renderInContext:bitmapContext canvasSize:size];
        }
        for (MarkupStroke *stroke in self.strokes) {
            [stroke renderInContext:bitmapContext canvasSize:size];
        }
        if (self.currentStroke) {
            [self.currentStroke renderInContext:bitmapContext canvasSize:size];
        }

        [NSGraphicsContext restoreGraphicsState];
    } else {
        for (MarkupStroke *stroke in self.strokes) {
            STRasterizeStrokeOntoBitmap(stroke, &buffer, size);
        }
        if (self.currentStroke) {
            STRasterizeStrokeOntoBitmap(self.currentStroke, &buffer, size);
        }
        for (MarkupText *text in self.texts) {
            STRasterizeTextOntoBitmap(text, &buffer, size);
        }
    }

    NSImage *output = [[NSImage alloc] initWithSize:size];
    if (!output) {
        return nil;
    }
    [output addRepresentation:bitmap];

    if (!NSIsEmptyRect(effectiveClip)) {
        NSBitmapImageRep *cropped = STBitmapImageRepCrop(bitmap, effectiveClip, size);
        if (cropped) {
            NSImage *croppedImage = [[NSImage alloc] initWithSize:cropped.size];
            [croppedImage addRepresentation:cropped];
            return croppedImage;
        }
    }
    return output;
}

- (NSImage *)flattenedImage {
    return [self flattenedImageWithinRect:NSZeroRect];
}

- (NSImage *)flattenedImageForSelection {
    if (!self.hasSelectionRect) {
        return [self flattenedImage];
    }
    NSRect integral = [self integralSelectionRect];
    if (NSIsEmptyRect(integral)) {
        return [self flattenedImage];
    }
    return [self flattenedImageWithinRect:integral];
}

- (NSImage *)croppedBaseImageWithRect:(NSRect)clipRect {
    if (!self.image) {
        return nil;
    }
    NSData *tiffData = [self.image TIFFRepresentation];
    if (!tiffData) {
        return nil;
    }
    NSImageRep *rep = [NSBitmapImageRep imageRepWithData:tiffData];
    if (![rep isKindOfClass:[NSBitmapImageRep class]]) {
        return nil;
    }
    NSBitmapImageRep *source = (NSBitmapImageRep *)rep;
    NSBitmapImageRep *cropped = STBitmapImageRepCrop(source, clipRect, self.image.size);
    if (!cropped) {
        return nil;
    }
    NSImage *output = [[NSImage alloc] initWithSize:cropped.size];
    [output addRepresentation:cropped];
    return output;
}

- (BOOL)cropToActiveSelection {
    if (!self.hasSelectionRect) {
        return NO;
    }
    NSRect clipRect = [self integralSelectionRect];
    if (NSIsEmptyRect(clipRect)) {
        return NO;
    }

    [self commitActiveTextIfNeeded];

    NSImage *croppedImage = [self croppedBaseImageWithRect:clipRect];
    if (!croppedImage) {
        return NO;
    }

    NSPoint offset = clipRect.origin;
    NSSize newSize = croppedImage.size;

    NSMutableArray<MarkupStroke *> *updatedStrokes = [[NSMutableArray alloc] initWithCapacity:self.strokes.count];
    for (MarkupStroke *stroke in self.strokes) {
        [stroke translateByOffset:offset clampToSize:newSize];
        [updatedStrokes addObject:stroke];
    }
    self.strokes = updatedStrokes;

    NSMutableArray<MarkupText *> *updatedTexts = [[NSMutableArray alloc] init];
    for (MarkupText *text in self.texts) {
        if (!NSIntersectsRect([text bounds], clipRect)) {
            continue;
        }
        [text translateByOffset:offset clampToSize:newSize];
        [updatedTexts addObject:text];
    }
    self.texts = updatedTexts;

    self.image = croppedImage;
    [self clearSelection];

    [self updateFrameSize];
    [self updateForEnclosingBoundsChange];
    [self setNeedsDisplay:YES];
    return YES;
}

@end
