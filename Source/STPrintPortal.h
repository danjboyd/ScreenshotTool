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

/// The dialog's page-setup dictionary as property-list values, to save and pass back next time, and
/// back to a GVariant `a{sv}`. The portal refuses a partial one (the dialog answers 2 and never shows),
/// so one without its paper name, size or margins comes back empty, which asks for the default.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *STPrintPortalPageSetupDictionaryFromVariant(void *pageSetup);
FOUNDATION_EXPORT void *STPrintPortalPageSetupVariantFromDictionary(NSDictionary<NSString *, id> * _Nullable pageSetup);

/// Writes the PDF for the paper the dialog chose, at `path`. YES if it did. `pageSetup` is the
/// dictionary form of `setup`, to remember.
typedef BOOL (^STPrintPortalWriter)(STPrintPortalPageSetup setup, NSDictionary<NSString *, id> *pageSetup, NSString *path);
/// `failure` is nil if it printed or the user cancelled; `printed` says which. `unavailable` says the
/// desktop has no print service to ask, so there's no dialog, as opposed to a print that went wrong.
typedef void (^STPrintPortalCompletion)(BOOL printed, BOOL unavailable, NSString * _Nullable failure);

/// Prints through org.freedesktop.portal.Print: the desktop's dialog picks the printer and paper, then
/// `writer` builds the PDF for that paper, and the portal sends it. The app keeps running meanwhile,
/// and the completion is called once, on the main thread.
@interface STPrintPortal : NSObject
/// Whether a print is under way: a second one isn't started meanwhile.
+ (BOOL)isPrinting;
+ (void)printForWindow:(nullable NSWindow *)window
                 title:(NSString *)title
             pageSetup:(nullable NSDictionary<NSString *, id> *)pageSetup
                writer:(STPrintPortalWriter)writer
            completion:(STPrintPortalCompletion)completion;
@end
#endif

NS_ASSUME_NONNULL_END
