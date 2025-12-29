#import <AppKit/AppKit.h>
#import "ScreenshotCanvasView.h"

NS_ASSUME_NONNULL_BEGIN

@class ToolSettingsPopoverController;

@protocol ToolSettingsPopoverControllerDelegate <NSObject>
- (CGFloat)toolSettingsPopover:(ToolSettingsPopoverController *)controller currentWidthForTool:(ScreenshotCanvasTool)tool;
- (CGFloat)toolSettingsPopover:(ToolSettingsPopoverController *)controller defaultWidthForTool:(ScreenshotCanvasTool)tool;
- (void)toolSettingsPopover:(ToolSettingsPopoverController *)controller didChangeWidth:(CGFloat)width forTool:(ScreenshotCanvasTool)tool;
- (NSColor *)toolSettingsPopover:(ToolSettingsPopoverController *)controller currentColorForTool:(ScreenshotCanvasTool)tool;
- (NSColor *)toolSettingsPopover:(ToolSettingsPopoverController *)controller defaultColorForTool:(ScreenshotCanvasTool)tool;
- (void)toolSettingsPopover:(ToolSettingsPopoverController *)controller didChangeColor:(NSColor *)color forTool:(ScreenshotCanvasTool)tool;
- (void)toolSettingsPopoverDidRequestReset:(ToolSettingsPopoverController *)controller forTool:(ScreenshotCanvasTool)tool;
- (void)toolSettingsPopoverDidRequestSetDefault:(ToolSettingsPopoverController *)controller forTool:(ScreenshotCanvasTool)tool;
@end

@interface ToolSettingsPopoverController : NSObject

@property (nonatomic, weak) id<ToolSettingsPopoverControllerDelegate> delegate;
@property (nonatomic, assign, readonly) ScreenshotCanvasTool tool;

- (instancetype)initWithTool:(ScreenshotCanvasTool)tool;
- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge;
- (void)close;
- (BOOL)isShown;
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
