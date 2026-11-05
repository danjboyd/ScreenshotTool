#import <AppKit/AppKit.h>
#import "STPrintLayout.h"
#import "STPrintOptions.h"

NS_ASSUME_NONNULL_BEGIN

#if defined(__linux__)
/// Linux's Print panel (#355): our options with a live preview and page count, shown before the
/// desktop's own print dialog, which has no room for them. The options here don't depend on a printer;
/// the dialog then picks the printer and paper, and the print path re-lays out for the paper it got.
@interface STPrintPanelController : NSObject

/// `flattenedImage` is what's printed, with its annotations: redactions are annotations, so nothing
/// here can print without them. `selection` is the selection in pixels from the image's top left, or
/// NSZeroRect. `selectionOnly` is what the panel starts on: YES for Print Selection. It's ignored
/// without a selection.
- (instancetype)initWithFlattenedImage:(NSImage *)flattenedImage
                             selection:(NSRect)selection
                         selectionOnly:(BOOL)selectionOnly
                              defaults:(NSUserDefaults *)defaults;

@property (nonatomic, readonly) NSPanel *panel;
@property (nonatomic, readonly) STPrintOptions *options;
/// The paper the preview shows. It starts on the last paper printed on, or NSPrintInfo's.
@property (nonatomic) NSSize paperSize;

/// A new layout of the current options and paper.
- (STPrintLayout *)currentLayout;

/// Shows the panel until it's answered. YES for Print, having saved the options.
- (BOOL)runModal;

// The controls, for tests.
@property (nonatomic, readonly) NSPopUpButton *contentPopUp;
@property (nonatomic, readonly) NSPopUpButton *fitPopUp;
@property (nonatomic, readonly) NSPopUpButton *orientationPopUp;
@property (nonatomic, readonly) NSTextField *scaleField;
@property (nonatomic, readonly) NSButton *enlargeCheckbox;
@property (nonatomic, readonly) NSButton *previousPageButton;
@property (nonatomic, readonly) NSButton *nextPageButton;
@property (nonatomic, readonly) NSButton *printButton;
@property (nonatomic, readonly) NSTextField *summaryLabel;
@property (nonatomic, readonly) NSUInteger previewPage;
/// As Print does: saves the options and ends a modal run.
- (void)confirm:(nullable id)sender;

@end

/// The print margins we ask for, on every side, in points.
extern const CGFloat STPrintDefaultMargin;
/// Sets the layout's content for an image: `options`' source (all of it or `selection`), the image's
/// resolution, and the fit options. Paper and margins are the caller's.
FOUNDATION_EXPORT void STConfigurePrintLayout(STPrintLayout *layout, STPrintOptions *options, NSImage *image, NSRect selection);
/// The paper last printed on, or NSPrintInfo's, or US Letter.
FOUNDATION_EXPORT NSSize STPrintLastPaperSize(NSUserDefaults *defaults);
FOUNDATION_EXPORT void STPrintSavePaperSize(NSUserDefaults *defaults, NSSize paper);
#endif

NS_ASSUME_NONNULL_END
