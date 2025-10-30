#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TextToolPopoverController;

@protocol TextToolPopoverControllerDelegate <NSObject>
- (NSColor *)textToolPopoverCurrentColor:(TextToolPopoverController *)controller;
- (NSColor *)textToolPopoverDefaultColor:(TextToolPopoverController *)controller;
- (void)textToolPopover:(TextToolPopoverController *)controller didChangeColor:(NSColor *)color;
- (NSFont *)textToolPopoverCurrentFont:(TextToolPopoverController *)controller;
- (NSFont *)textToolPopoverDefaultFont:(TextToolPopoverController *)controller;
- (void)textToolPopover:(TextToolPopoverController *)controller didChangeFont:(NSFont *)font;
- (void)textToolPopoverDidRequestReset:(TextToolPopoverController *)controller;
- (void)textToolPopoverDidRequestSetDefault:(TextToolPopoverController *)controller;
@end

@interface TextToolPopoverController : NSObject

@property (nonatomic, weak) id<TextToolPopoverControllerDelegate> delegate;

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge;
- (void)close;
- (BOOL)isShown;
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
