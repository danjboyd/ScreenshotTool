#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// What a right-click on the canvas is about.
typedef NS_ENUM(NSInteger, STCanvasContextKind) {
    /// No image: no menu.
    STCanvasContextKindNone = 0,
    /// The image, with nothing under the pointer selected.
    STCanvasContextKindImage = 1,
    /// Inside the region selection.
    STCanvasContextKindSelection = 2,
    /// One or more selected annotations, the one under the pointer among them.
    STCanvasContextKindAnnotation = 3,
};

/// The canvas's own commands for the menu's annotation and selection items. The canvas
/// implements them and validates them.
@protocol STCanvasContextCommands <NSObject>
- (IBAction)redactSelection:(nullable id)sender;
- (IBAction)deselect:(nullable id)sender;
- (IBAction)editSelectedText:(nullable id)sender;
- (IBAction)duplicateAnnotations:(nullable id)sender;
- (IBAction)bringAnnotationsToFront:(nullable id)sender;
- (IBAction)sendAnnotationsToBack:(nullable id)sender;
- (IBAction)deleteAnnotations:(nullable id)sender;
@end

/// The right-click menu for the canvas: only what fits what was clicked, the likely command
/// first, and every command one the menu bar or a key also has. `canvas` gets the canvas's own
/// items; `controller` the window's (Copy, Crop to Selection, Save As…, zooming), which it
/// validates as for the menu bar. `extraItems` (the custom actions) go last on the image's menu.
/// `singleText` is whether the one annotation selected is a text label (Edit Text); `canShare`
/// whether there's a share picker to show (Share…, sent to the controller's -shareImage:).
NSMenu * _Nullable STCanvasContextMenu(STCanvasContextKind kind, BOOL singleText, BOOL canShare,
                                       id<STCanvasContextCommands> canvas, id controller,
                                       NSArray<NSMenuItem *> * _Nullable extraItems);

NS_ASSUME_NONNULL_END
