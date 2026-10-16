#import "STEmptyStateView.h"
#import "STThemeUtilities.h"

@interface STEmptyStateView ()
@property (nonatomic, readwrite, getter=isDropHighlighted) BOOL dropHighlighted;
@end

@implementation STEmptyStateView

+ (CGFloat)outlineInset {
    return 16.0;
}

- (BOOL)isFlipped {
    return NO;
}

- (void)setDropHighlighted:(BOOL)dropHighlighted {
    if (_dropHighlighted == dropHighlighted) {
        return;
    }
    _dropHighlighted = dropHighlighted;
    [self setNeedsDisplay:YES];
}

- (void)updateDraggedTypes {
#if defined(GNUSTEP)
    // GNUstep has no NSPasteboardTypeFileURL, and the app takes drops only on macOS so far.
    [self unregisterDraggedTypes];
#else
    if (self.dragOperation && self.performDrop) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL, NSPasteboardTypePNG, NSPasteboardTypeTIFF]];
    } else {
        [self unregisterDraggedTypes];
    }
#endif
}

- (void)setDragOperation:(NSDragOperation (^)(id<NSDraggingInfo>))dragOperation {
    _dragOperation = [dragOperation copy];
    [self updateDraggedTypes];
    [self setNeedsDisplay:YES];
}

- (void)setPerformDrop:(BOOL (^)(id<NSDraggingInfo>))performDrop {
    _performDrop = [performDrop copy];
    [self updateDraggedTypes];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    // The outline says "drop an image here", so only a view that takes drops draws it (GNUstep
    // doesn't yet). The theme draws the window's background.
    if (!self.dragOperation || !self.performDrop) {
        return;
    }
    CGFloat inset = [[self class] outlineInset];
    NSRect outline = NSInsetRect(self.bounds, inset, inset);
    if (NSWidth(outline) < 24.0 || NSHeight(outline) < 24.0) {
        return;
    }
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:outline xRadius:12.0 yRadius:12.0];
    if (self.dropHighlighted) {
        [[STThemeAccentColor() colorWithAlphaComponent:0.08] setFill];
        [path fill];
        [STThemeAccentColor() setStroke];
        [path setLineWidth:2.0];
    } else {
        [[STThemeSecondaryTextColor() colorWithAlphaComponent:0.45] setStroke];
        [path setLineWidth:1.5];
    }
    CGFloat dash[2] = {6.0, 4.0};
    [path setLineDash:dash count:2 phase:0.0];
    [path stroke];
}

#pragma mark - Dropping

- (NSDragOperation)operationForDrag:(id<NSDraggingInfo>)sender {
    return self.dragOperation ? self.dragOperation(sender) : NSDragOperationNone;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSDragOperation operation = [self operationForDrag:sender];
    self.dropHighlighted = (operation != NSDragOperationNone);
    return operation;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    NSDragOperation operation = [self operationForDrag:sender];
    self.dropHighlighted = (operation != NSDragOperationNone);
    return operation;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    (void)sender;
    self.dropHighlighted = NO;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    self.dropHighlighted = NO;
    return self.performDrop ? self.performDrop(sender) : NO;
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {
    (void)sender;
    self.dropHighlighted = NO;
}

@end

static const CGFloat STRecentCardPadding = 8.0;
static const CGFloat STRecentCardThumbnailHeight = 112.0;

@implementation STRecentCard

+ (CGFloat)heightForWidth:(CGFloat)width {
    (void)width;
    return STRecentCardPadding + STRecentCardThumbnailHeight + 8.0 + 34.0;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setBordered:NO];
        [self setButtonType:NSMomentaryChangeButton];
        [self setImagePosition:NSNoImage];
        _detail = @"";
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setDetail:(NSString *)detail {
    _detail = [detail copy] ?: @"";
    [self setNeedsDisplay:YES];
}

- (void)setThumbnail:(NSImage *)thumbnail {
    _thumbnail = thumbnail;
    [self setNeedsDisplay:YES];
}

- (void)setPlaceholder:(NSImage *)placeholder {
    _placeholder = placeholder;
    [self setNeedsDisplay:YES];
}

- (NSRect)thumbnailFrame {
    return NSMakeRect(STRecentCardPadding, STRecentCardPadding,
                      MAX(0.0, NSWidth(self.bounds) - 2.0 * STRecentCardPadding), STRecentCardThumbnailHeight);
}

- (void)drawText:(NSString *)text inRect:(NSRect)rect font:(NSFont *)font color:(NSColor *)color {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    [text drawInRect:rect withAttributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: style,
    }];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect card = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *cardPath = [NSBezierPath bezierPathWithRoundedRect:card xRadius:8.0 yRadius:8.0];
    [STThemeCardBackgroundColor() setFill];
    [cardPath fill];
    BOOL pressed = [[self cell] isHighlighted];
    if (pressed) {
        [[STThemePrimaryTextColor() colorWithAlphaComponent:0.06] setFill];
        [cardPath fill];
    }
    [[STThemeHairlineColor() colorWithAlphaComponent:0.3] setStroke];
    [cardPath setLineWidth:1.0];
    [cardPath stroke];

    NSRect thumbFrame = [self thumbnailFrame];
    [NSGraphicsContext saveGraphicsState];
    NSBezierPath *thumbPath = [NSBezierPath bezierPathWithRoundedRect:thumbFrame xRadius:4.0 yRadius:4.0];
    [STThemeInsetBackgroundColor() setFill];
    [thumbPath fill];
    [thumbPath addClip];
    NSImage *image = self.thumbnail;
    if (image && image.size.width > 0.0 && image.size.height > 0.0) {
        // Fill the frame and crop, centred, as a photo grid does.
        CGFloat scale = MAX(NSWidth(thumbFrame) / image.size.width, NSHeight(thumbFrame) / image.size.height);
        NSSize drawn = NSMakeSize(image.size.width * scale, image.size.height * scale);
        NSRect target = NSMakeRect(NSMidX(thumbFrame) - drawn.width / 2.0, NSMidY(thumbFrame) - drawn.height / 2.0,
                                   drawn.width, drawn.height);
        [image drawInRect:target fromRect:NSZeroRect operation:NSCompositeSourceOver
                 fraction:1.0 respectFlipped:YES hints:nil];
    } else if (self.placeholder) {
        NSRect icon = NSMakeRect(NSMidX(thumbFrame) - 24.0, NSMidY(thumbFrame) - 24.0, 48.0, 48.0);
        [self.placeholder drawInRect:icon fromRect:NSZeroRect operation:NSCompositeSourceOver
                            fraction:1.0 respectFlipped:YES hints:nil];
    }
    [NSGraphicsContext restoreGraphicsState];
    [[STThemeHairlineColor() colorWithAlphaComponent:0.25] setStroke];
    [thumbPath setLineWidth:1.0];
    [thumbPath stroke];

    CGFloat textX = STRecentCardPadding + 2.0;
    CGFloat textWidth = MAX(0.0, NSWidth(self.bounds) - 2.0 * textX);
    CGFloat y = NSMaxY(thumbFrame) + 8.0;
    NSFont *nameFont = [NSFont systemFontOfSize:[NSFont systemFontSize] - 0.5];
    NSFont *detailFont = [NSFont systemFontOfSize:[NSFont smallSystemFontSize] - 0.5];
    [self drawText:self.title inRect:NSMakeRect(textX, y, textWidth, 17.0) font:nameFont color:STThemePrimaryTextColor()];
    [self drawText:self.detail inRect:NSMakeRect(textX, y + 17.0, textWidth, 15.0)
              font:detailFont color:STThemeSecondaryTextColor()];

    if ([self.window firstResponder] == self && [self.window isKeyWindow]) {
        [[STThemeAccentColor() colorWithAlphaComponent:0.8] setStroke];
        NSBezierPath *focus = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1.0, 1.0) xRadius:7.0 yRadius:7.0];
        [focus setLineWidth:2.0];
        [focus stroke];
    }
}

@end

#if !defined(GNUSTEP)
@implementation STAccentButton {
    NSString *_plainTitle;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setButtonType:NSButtonTypeMomentaryPushIn];
        [self setBezelStyle:NSBezelStyleRounded];
        [self setBezelColor:[NSColor controlAccentColor]];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setTitle:(NSString *)title {
    _plainTitle = [title copy];
    [super setTitle:title];
    [self updateTitleColours];
}

- (void)setShortcut:(NSString *)shortcut {
    _shortcut = [shortcut copy];
    [self updateTitleColours];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (self.window) {
        [center removeObserver:self name:NSWindowDidBecomeKeyNotification object:self.window];
        [center removeObserver:self name:NSWindowDidResignKeyNotification object:self.window];
    }
    if (newWindow) {
        [center addObserver:self selector:@selector(windowKeyStateChanged:) name:NSWindowDidBecomeKeyNotification object:newWindow];
        [center addObserver:self selector:@selector(windowKeyStateChanged:) name:NSWindowDidResignKeyNotification object:newWindow];
    }
    [super viewWillMoveToWindow:newWindow];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self updateTitleColours];
}

- (void)windowKeyStateChanged:(NSNotification *)notification {
    (void)notification;
    [self updateTitleColours];
}

- (void)updateTitleColours {
    NSString *title = _plainTitle;
    if (title.length == 0) {
        return;
    }
    BOOL accented = self.window.isKeyWindow && self.isEnabled;
    NSColor *titleColour = accented ? [NSColor whiteColor] : [NSColor labelColor];
    NSColor *hintColour = accented ? [[NSColor whiteColor] colorWithAlphaComponent:0.7] : [NSColor secondaryLabelColor];
    NSFont *font = self.font ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
    NSMutableParagraphStyle *centred = [[NSMutableParagraphStyle alloc] init];
    centred.alignment = NSTextAlignmentCenter;
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: font, NSForegroundColorAttributeName: titleColour, NSParagraphStyleAttributeName: centred,
    }];
    if (self.shortcut.length > 0) {
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[@"   " stringByAppendingString:self.shortcut] attributes:@{
            NSFontAttributeName: font, NSForegroundColorAttributeName: hintColour, NSParagraphStyleAttributeName: centred,
        }]];
    }
    [super setAttributedTitle:text];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self updateTitleColours];
}

@end
#endif
