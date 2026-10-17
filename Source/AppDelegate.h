#import <AppKit/AppKit.h>
#import "ScreenshotCanvasView.h"

FOUNDATION_EXPORT void ScreenshotToolAppendLog(NSString *message);
/// Writes data atomically. On Windows it retries for about half a second, then fills in an error (#261).
FOUNDATION_EXPORT BOOL STWriteDataAtomically(NSData *data, NSURL *url, NSError **error);

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end
