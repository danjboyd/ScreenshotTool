#import <AppKit/AppKit.h>
#import "ScreenshotCanvasView.h"

FOUNDATION_EXPORT void ScreenshotToolAppendLog(NSString *message);
/// Writes data atomically. On Windows it retries for about half a second, then fills in an error (#261).
FOUNDATION_EXPORT BOOL STWriteDataAtomically(NSData *data, NSURL *url, NSError **error);
/// Removes the exports in `directory` last changed before `cutoff`, leaving newer ones that another
/// instance may still be using (#294).
FOUNDATION_EXPORT void STRemoveExportsChangedBefore(NSURL *directory, NSDate *cutoff);

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end
