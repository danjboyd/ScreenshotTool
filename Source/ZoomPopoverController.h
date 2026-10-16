#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ZoomPopoverController;

/// The zoom slider's position, 0 to 1, for a scale, and back: logarithmic, so each doubling
/// takes the same distance. The status bar's zoom slider uses the same mapping (#221).
CGFloat STZoomSliderFractionForScale(CGFloat scale);
CGFloat STZoomScaleForSliderFraction(CGFloat fraction);

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
