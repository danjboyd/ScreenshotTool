#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The view behind the window's empty state (#55, #221). Once it takes drops (`dragOperation` and
/// `performDrop` set), it draws a dashed outline inset from its edges, the place an image can be
/// dropped, in the theme's accent while a drop is over it. Its controls are ordinary subviews.
@interface STEmptyStateView : NSView

/// The outline's distance from the view's edges.
+ (CGFloat)outlineInset;

/// The drag's operation, or NSDragOperationNone where nothing can be dropped. Setting this and
/// `performDrop` makes the view take drops; without them it only draws the outline.
@property (nonatomic, copy, nullable) NSDragOperation (^dragOperation)(id<NSDraggingInfo> info);
@property (nonatomic, copy, nullable) BOOL (^performDrop)(id<NSDraggingInfo> info);

/// Whether a drop that can be taken is over the view.
@property (nonatomic, readonly, getter=isDropHighlighted) BOOL dropHighlighted;

@end

/// One of the empty state's Recent cards (#221): a file's thumbnail with its name and when it
/// changed, on a card in the theme's colours. A button, so it's clicked, focused and read out as
/// one; its title is the name. Its action gets the card as sender, the file's path its
/// representedObject, as an Open Recent menu item's.
@interface STRecentCard : NSButton

/// The card's size for a given width: the thumbnail is 112pt tall.
+ (CGFloat)heightForWidth:(CGFloat)width;

@property (nonatomic, copy, nullable) id representedObject;
@property (nonatomic, copy) NSString *detail;
/// Drawn to fill the thumbnail's frame, cropped. Without one, `placeholder` is drawn small.
@property (nonatomic, strong, nullable) NSImage *thumbnail;
@property (nonatomic, strong, nullable) NSImage *placeholder;

@end

#if !defined(GNUSTEP)
/// The empty state's accent push button on macOS (#221): the accent bezel, its title and a dimmer
/// key hint after it. White on the accent while the window is key; in the label colours when it
/// isn't, as AppKit then draws the bezel grey and white wouldn't read on it.
@interface STAccentButton : NSButton
/// The key hint after the title, as "⇧⌘T"; nil for none.
@property (nonatomic, copy, nullable) NSString *shortcut;
@end
#endif

NS_ASSUME_NONNULL_END
