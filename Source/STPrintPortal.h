#import <AppKit/AppKit.h>
#import "STPrintLayout.h"

NS_ASSUME_NONNULL_BEGIN

#if defined(__linux__)
/// The paper the print dialog answered with: in points, from the millimetres it reports.
typedef struct {
    NSSize paper;
    STPrintMargins printerMargins;
    BOOL valid;
} STPrintPortalPageSetup;

/// Reads the portal's page-setup dictionary, a GVariant `a{sv}` (Width, Height and Margin* in mm).
/// `valid` is NO without a usable width and height. Its Orientation is ignored: the layout chooses
/// the sheet's shape, and the PDF's pages have that shape.
FOUNDATION_EXPORT STPrintPortalPageSetup STPrintPortalPageSetupFromVariant(void *pageSetup);

/// Writes the PDF for the paper the dialog chose, at `path`. YES if it did.
typedef BOOL (^STPrintPortalWriter)(STPrintPortalPageSetup setup, NSString *path);
/// `failure` is nil if it printed or the user cancelled; `printed` says which.
typedef void (^STPrintPortalCompletion)(BOOL printed, NSString * _Nullable failure);

/// Prints through org.freedesktop.portal.Print: the desktop's dialog picks the printer and paper, then
/// `writer` builds the PDF for that paper, and the portal sends it. The app keeps running meanwhile,
/// and the completion is called once, on the main thread.
@interface STPrintPortal : NSObject
/// Whether a print is under way: a second one isn't started meanwhile.
+ (BOOL)isPrinting;
+ (void)printForWindow:(nullable NSWindow *)window
                 title:(NSString *)title
                writer:(STPrintPortalWriter)writer
            completion:(STPrintPortalCompletion)completion;
@end
#endif

NS_ASSUME_NONNULL_END
