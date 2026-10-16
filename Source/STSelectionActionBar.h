#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A small bar of the region selection's commands (Crop, Copy, Redact, and Share where there's a
/// share picker) shown next to the
/// selection when it's made, so the next step is one click from the pointer, as CleanShot X and
/// Shottr do. The buttons are standard push buttons the theme draws, sent to `target`; Crop is
/// the accent button. The same commands are in the Edit menu and the right-click menu.
@interface STSelectionActionBar : NSView

/// With `showsShare`, a Share button too, sent to the target's -shareImage:.
- (instancetype)initWithTarget:(id)target showsShare:(BOOL)showsShare;

/// The bar's buttons, Crop first.
@property (nonatomic, readonly) NSArray<NSButton *> *buttons;

/// Where the bar goes for a selection at `selection`, both in its superview's coordinates: centred
/// below it, above it if there's no room below `visible`, else just inside its bottom edge, and
/// kept inside `visible`.
- (NSRect)frameForSelection:(NSRect)selection visible:(NSRect)visible;

@end

NS_ASSUME_NONNULL_END
