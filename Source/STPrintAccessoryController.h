#import <AppKit/AppKit.h>
#import "STPrintOptions.h"

NS_ASSUME_NONNULL_BEGIN

#if !defined(GNUSTEP)
@class STPrintView;

/// The macOS print panel's own options (#355): how the image is sized, whether only the selection
/// prints, and whether the sheet turns to suit the image. Annotations always print: a redaction is
/// one, and printing never shows what a redaction hides. They're STPrintOptions,
/// saved under the keys every platform shares; the panel itself keeps the paper and printer.
///
/// Orientation: "Turn automatically" is STPrintOrientationAutomatic. Choosing portrait or landscape
/// in the panel turns it off, and that choice is what's saved, as on the other platforms.
@interface STPrintAccessoryController : NSViewController <NSPrintPanelAccessorizing>

- (instancetype)initWithOptions:(STPrintOptions *)options hasSelection:(BOOL)hasSelection NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// What's chosen now, a copy.
@property (nonatomic, readonly) STPrintOptions *options;

/// The print view to keep in step: its layout takes the options at once.
@property (nonatomic, weak, nullable) STPrintView *printView;
/// Called after any change, once the print view's layout has the options: the app gives the view the
/// source rect they ask for (the selection or all of it).
@property (nonatomic, copy, nullable) void (^optionsDidChange)(STPrintOptions *options);

/// The controls' values, for bindings and probes. 0 fit to page, 1 actual size, 2 custom scale.
@property (nonatomic) NSInteger fitIndex;
/// The custom scale in percent, kept to STPrintOptions' range.
@property (nonatomic) NSInteger scalePercent;
@property (nonatomic) BOOL enlargeToFill;
/// Always NO when there's no selection.
@property (nonatomic) BOOL selectionOnly;
@property (nonatomic) BOOL automaticOrientation;
@property (nonatomic, readonly) BOOL hasSelection;

/// The panel's orientation changed, from the print view's print info: turns "Turn automatically" off
/// and takes it as the choice.
- (void)printViewChoseOrientation:(STPrintOrientation)orientation;

/// Saves the options under the shared keys, after a print or a saved PDF, not a cancel.
- (void)saveToDefaults:(NSUserDefaults *)defaults;

@end
#endif

NS_ASSUME_NONNULL_END
