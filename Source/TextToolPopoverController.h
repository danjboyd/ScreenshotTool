#import <AppKit/AppKit.h>
#import "MarkupText.h"
#import "ScreenshotToolSettings.h"

NS_ASSUME_NONNULL_BEGIN

@class TextToolPopoverController;

@protocol TextToolPopoverControllerDelegate <NSObject>
- (NSColor *)textToolPopoverCurrentColor:(TextToolPopoverController *)controller;
- (NSColor *)textToolPopoverDefaultColor:(TextToolPopoverController *)controller;
- (void)textToolPopover:(TextToolPopoverController *)controller didChangeColor:(NSColor *)color;
- (NSFont *)textToolPopoverCurrentFont:(TextToolPopoverController *)controller;
- (NSFont *)textToolPopoverDefaultFont:(TextToolPopoverController *)controller;
- (void)textToolPopover:(TextToolPopoverController *)controller didChangeFont:(NSFont *)font;
- (MarkupTextStyle)textToolPopoverCurrentStyle:(TextToolPopoverController *)controller;
- (MarkupTextStyle)textToolPopoverDefaultStyle:(TextToolPopoverController *)controller;
- (void)textToolPopover:(TextToolPopoverController *)controller didChangeStyle:(MarkupTextStyle)style;
- (STTextSizePreset)textToolPopoverCurrentSizePreset:(TextToolPopoverController *)controller;
- (STTextSizePreset)textToolPopoverDefaultSizePreset:(TextToolPopoverController *)controller;
- (void)textToolPopover:(TextToolPopoverController *)controller didChangeSizePreset:(STTextSizePreset)preset;
- (void)textToolPopoverDidRequestReset:(TextToolPopoverController *)controller;
- (void)textToolPopoverDidRequestSetDefault:(TextToolPopoverController *)controller;
@end

@interface TextToolPopoverController : NSObject <NSTextFieldDelegate, NSTextViewDelegate>

@property (nonatomic, weak) id<TextToolPopoverControllerDelegate> delegate;

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge;
- (void)close;
- (BOOL)isShown;
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
