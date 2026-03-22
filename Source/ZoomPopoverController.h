#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ZoomPopoverController;

@protocol ZoomPopoverControllerDelegate <NSObject>
- (BOOL)zoomPopoverHasImage:(ZoomPopoverController *)controller;
- (BOOL)zoomPopoverIsFitToWindow:(ZoomPopoverController *)controller;
- (CGFloat)zoomPopoverCurrentScale:(ZoomPopoverController *)controller;
- (void)zoomPopover:(ZoomPopoverController *)controller didChangeScale:(CGFloat)scale;
- (void)zoomPopoverDidRequestFitToWindow:(ZoomPopoverController *)controller;
@end

@interface ZoomPopoverController : NSObject

@property (nonatomic, weak) id<ZoomPopoverControllerDelegate> delegate;

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge;
- (void)close;
- (BOOL)isShown;
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
