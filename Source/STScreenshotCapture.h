#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// What a capture gave: the screenshot's file, or an image the system put on the clipboard.
typedef NS_ENUM(NSInteger, STScreenshotCaptureResult) {
    /// Cancelled, or the system's capture tool couldn't be started.
    STScreenshotCaptureResultNone = 0,
    /// `url` is the screenshot.
    STScreenshotCaptureResultFile = 1,
    /// The screenshot is on the clipboard.
    STScreenshotCaptureResultClipboard = 2,
};

typedef void (^STScreenshotCaptureCompletion)(STScreenshotCaptureResult result, NSURL * _Nullable url,
                                              NSString * _Nullable failure);

/// Takes a screenshot with the system's own tool, which lets the user choose an area, a window or
/// the screen: GNOME's (and other desktops') through the desktop portal's Screenshot interface,
/// Windows' through the Snipping Tool, whose snip goes to the clipboard. The app keeps running
/// meanwhile; the completion is called once, on the main thread. `failure` is nil when the user
/// cancelled.
@interface STScreenshotCapture : NSObject

/// Whether this platform has a capture tool to ask: a session bus with the portal on Linux,
/// Windows 10 and later; not macOS, which captures on its own.
+ (BOOL)isAvailable;

/// Whether a capture is under way: a second one isn't started meanwhile.
+ (BOOL)isCapturing;

/// Starts a capture for `window` (the system's tool attaches to it where it can).
+ (void)captureForWindow:(nullable NSWindow *)window completion:(STScreenshotCaptureCompletion)completion;

@end

NS_ASSUME_NONNULL_END
