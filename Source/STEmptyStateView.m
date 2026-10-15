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
    if (self.dragOperation && self.performDrop) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL, NSPasteboardTypePNG, NSPasteboardTypeTIFF]];
    } else {
        [self unregisterDraggedTypes];
    }
}

- (void)setDragOperation:(NSDragOperation (^)(id<NSDraggingInfo>))dragOperation {
    _dragOperation = [dragOperation copy];
    [self updateDraggedTypes];
}

- (void)setPerformDrop:(BOOL (^)(id<NSDraggingInfo>))performDrop {
    _performDrop = [performDrop copy];
    [self updateDraggedTypes];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    // The theme draws the window's background; only the outline is the view's own.
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
