#import "STScreenshotCapture.h"

#if defined(GNUSTEP) && !defined(_WIN32)
#define ST_CAPTURE_PORTAL 1
#include <gio/gio.h>
#include <string.h>
#include <unistd.h>
#import <GNUstepGUI/GSDisplayServer.h>
#elif defined(_WIN32)
#define ST_CAPTURE_SNIPPING_TOOL 1
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#endif

/// The capture under way, if any.
static id STCurrentCapture = nil;

/// Holds a block for -performSelector:withObject:afterDelay:inModes:.
@interface STCaptureBlockRunner : NSObject
@property (nonatomic, copy) void (^block)(void);
- (void)run;
@end

@implementation STCaptureBlockRunner
- (void)run {
    void (^block)(void) = self.block;
    self.block = nil;
    if (block) {
        block();
    }
}
@end

/// Runs `block` on the main thread on a later turn of the run loop, in any mode.
static void STCaptureFinishLater(void (^block)(void)) {
    STCaptureBlockRunner *runner = [[STCaptureBlockRunner alloc] init];
    runner.block = block;
    [runner performSelector:@selector(run)
                 withObject:nil
                 afterDelay:0.0
                    inModes:@[NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode]];
}

/// A repeating timer that keeps firing while menus track and panels run.
static NSTimer *STCapturePollTimer(NSTimeInterval interval, id target, SEL selector) {
    NSTimer *timer = [NSTimer timerWithTimeInterval:interval target:target selector:selector userInfo:nil repeats:YES];
    for (NSString *mode in @[NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode]) {
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:mode];
    }
    return timer;
}

#if ST_CAPTURE_PORTAL

/// org.freedesktop.portal.Screenshot: the portal shows the desktop's own screenshot tool
/// (interactive), then answers with a Response signal on the request it returned. The signal is
/// dispatched on a GLib context of our own, which a timer drains while the run loop runs.
@interface STPortalCapture : NSObject {
@public
    GMainContext *_context;
    GDBusConnection *_bus;
    guint _subscription;
    BOOL _answered;
    guint32 _response;
    GVariant *_results;
}
@property (nonatomic, copy) STScreenshotCaptureCompletion completion;
@property (nonatomic, strong) NSTimer *timer;
- (BOOL)startForWindow:(NSWindow *)window failure:(NSString **)failure;
@end

static void STPortalCaptureResponse(GDBusConnection *connection, const gchar *sender, const gchar *path,
                                    const gchar *interface, const gchar *signal, GVariant *parameters,
                                    gpointer data) {
    (void)connection; (void)sender; (void)path; (void)interface; (void)signal;
    STPortalCapture *capture = (__bridge STPortalCapture *)data;
    if (!capture->_answered && g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ua{sv})"))) {
        g_variant_get(parameters, "(u@a{sv})", &capture->_response, &capture->_results);
        capture->_answered = YES;
    }
}

@implementation STPortalCapture

- (instancetype)init {
    self = [super init];
    if (self) {
        _context = g_main_context_new();
    }
    return self;
}

- (void)dealloc {
    if (_subscription != 0 && _bus != NULL) {
        g_dbus_connection_signal_unsubscribe(_bus, _subscription);
    }
    if (_bus != NULL) {
        g_object_unref(_bus);
    }
    if (_results != NULL) {
        g_variant_unref(_results);
    }
    if (_context != NULL) {
        g_main_context_unref(_context);
    }
}

- (void)subscribeToPath:(const char *)path {
    if (_subscription != 0) {
        g_dbus_connection_signal_unsubscribe(_bus, _subscription);
    }
    // The signal is dispatched on the context that is the thread's default when subscribing.
    g_main_context_push_thread_default(_context);
    _subscription = g_dbus_connection_signal_subscribe(_bus, "org.freedesktop.portal.Desktop",
                                                       "org.freedesktop.portal.Request", "Response", path,
                                                       NULL, G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE,
                                                       STPortalCaptureResponse, (__bridge gpointer)self, NULL);
    g_main_context_pop_thread_default(_context);
}

/// "x11:<id>" for a window on X11 (or XWayland), with which the portal attaches its tool to it.
static NSString *STPortalParentWindow(NSWindow *window) {
    if (window == nil || [window windowNumber] <= 0) {
        return @"";
    }
    void *device = [GSCurrentServer() windowDevice:[window windowNumber]];
    if (device == NULL) {
        return @"";
    }
    return [NSString stringWithFormat:@"x11:%lx", (unsigned long)(uintptr_t)device];
}

- (BOOL)startForWindow:(NSWindow *)window failure:(NSString **)failure {
    static unsigned long serial = 0;
    GError *error = NULL;
    _bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (_bus == NULL) {
        *failure = [NSString stringWithFormat:@"No session bus (%s).", error ? error->message : "unknown error"];
        g_clear_error(&error);
        return NO;
    }

    // The request's path follows from the token and the bus name: subscribe before calling, as
    // the answer can come before the reply.
    NSString *token = [NSString stringWithFormat:@"screenshottool%d_%lu", (int)getpid(), ++serial];
    NSMutableString *sender = [NSMutableString stringWithUTF8String:g_dbus_connection_get_unique_name(_bus) + 1];
    [sender replaceOccurrencesOfString:@"." withString:@"_" options:0 range:NSMakeRange(0, sender.length)];
    NSString *expected = [NSString stringWithFormat:@"/org/freedesktop/portal/desktop/request/%@/%@", sender, token];
    [self subscribeToPath:expected.UTF8String];

    GVariantBuilder options;
    g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&options, "{sv}", "handle_token", g_variant_new_string(token.UTF8String));
    g_variant_builder_add(&options, "{sv}", "interactive", g_variant_new_boolean(TRUE));
    g_variant_builder_add(&options, "{sv}", "modal", g_variant_new_boolean(TRUE));
    GVariant *reply = g_dbus_connection_call_sync(_bus, "org.freedesktop.portal.Desktop",
                                                  "/org/freedesktop/portal/desktop",
                                                  "org.freedesktop.portal.Screenshot", "Screenshot",
                                                  g_variant_new("(sa{sv})", STPortalParentWindow(window).UTF8String, &options),
                                                  G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
    if (reply == NULL) {
        *failure = [NSString stringWithFormat:@"The desktop's screenshot tool isn't available (%s).",
                    error ? error->message : "unknown error"];
        g_clear_error(&error);
        return NO;
    }
    // Portals before 0.9 choose the path themselves.
    const char *handle = NULL;
    g_variant_get(reply, "(&o)", &handle);
    if (handle != NULL && strcmp(handle, expected.UTF8String) != 0) {
        [self subscribeToPath:handle];
    }
    g_variant_unref(reply);

    self.timer = STCapturePollTimer(0.05, self, @selector(poll:));
    return YES;
}

- (void)poll:(NSTimer *)timer {
    (void)timer;
    while (g_main_context_iteration(_context, FALSE)) {
    }
    if (!_answered) {
        return;
    }
    [self.timer invalidate];
    self.timer = nil;

    STScreenshotCaptureResult result = STScreenshotCaptureResultNone;
    NSURL *url = nil;
    NSString *failure = nil;
    const char *uri = NULL;
    if (_response == 0 && _results != NULL && g_variant_lookup(_results, "uri", "&s", &uri) && uri != NULL) {
        url = [NSURL URLWithString:[NSString stringWithUTF8String:uri]];
        if (url.isFileURL) {
            result = STScreenshotCaptureResultFile;
        } else {
            url = nil;
            failure = @"The screenshot wasn't saved to a file.";
        }
    } else if (_response == 2) {
        failure = @"The screenshot couldn't be taken.";
    }
    // 1: cancelled.
    STScreenshotCaptureCompletion completion = self.completion;
    self.completion = nil;
    STCurrentCapture = nil;
    completion(result, url, failure);
}

@end

#elif ST_CAPTURE_SNIPPING_TOOL

/// The Snipping Tool's overlay (ms-screenclip:), whose snip goes to the clipboard. Nothing tells
/// the app when it's done or cancelled: the clipboard is watched for a new image, for a while.
@interface STSnippingToolCapture : NSObject
@property (nonatomic, copy) STScreenshotCaptureCompletion completion;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) DWORD sequence;
@property (nonatomic, strong) NSDate *deadline;
- (BOOL)start:(NSString **)failure;
@end

/// How long a snip is waited for: Esc in the overlay can't be seen.
static const NSTimeInterval STSnippingToolWait = 120.0;

@implementation STSnippingToolCapture

- (BOOL)start:(NSString **)failure {
    self.sequence = GetClipboardSequenceNumber();
    HINSTANCE launched = ShellExecuteW(NULL, L"open", L"ms-screenclip:", NULL, NULL, SW_SHOWNORMAL);
    if ((INT_PTR)launched <= 32) {
        *failure = @"The Snipping Tool couldn't be started.";
        return NO;
    }
    self.deadline = [NSDate dateWithTimeIntervalSinceNow:STSnippingToolWait];
    self.timer = STCapturePollTimer(0.25, self, @selector(poll:));
    return YES;
}

static BOOL STClipboardHasImage(void) {
    static UINT png = 0;
    if (png == 0) {
        png = RegisterClipboardFormatW(L"PNG");
    }
    return IsClipboardFormatAvailable(CF_DIB) || IsClipboardFormatAvailable(CF_DIBV5)
        || IsClipboardFormatAvailable(CF_BITMAP) || (png != 0 && IsClipboardFormatAvailable(png));
}

- (void)poll:(NSTimer *)timer {
    (void)timer;
    STScreenshotCaptureResult result = STScreenshotCaptureResultNone;
    if (GetClipboardSequenceNumber() != self.sequence) {
        // Something new on the clipboard: the snip, unless something else was copied meanwhile.
        if (STClipboardHasImage()) {
            result = STScreenshotCaptureResultClipboard;
        }
    } else if ([self.deadline timeIntervalSinceNow] > 0) {
        return;
    }
    [self.timer invalidate];
    self.timer = nil;
    STScreenshotCaptureCompletion completion = self.completion;
    self.completion = nil;
    STCurrentCapture = nil;
    completion(result, nil, nil);
}

@end

#endif

@implementation STScreenshotCapture

+ (BOOL)isAvailable {
#if ST_CAPTURE_PORTAL
    // A session bus to reach the portal on; whether the portal answers is known when it's asked.
    NSDictionary<NSString *, NSString *> *environment = [[NSProcessInfo processInfo] environment];
    if ([environment[@"DBUS_SESSION_BUS_ADDRESS"] length] > 0) {
        return YES;
    }
    NSString *runtime = environment[@"XDG_RUNTIME_DIR"];
    return runtime.length > 0
        && [[NSFileManager defaultManager] fileExistsAtPath:[runtime stringByAppendingPathComponent:@"bus"]];
#elif ST_CAPTURE_SNIPPING_TOOL
    return YES;
#else
    return NO;
#endif
}

+ (BOOL)isCapturing {
    return STCurrentCapture != nil;
}

+ (void)captureForWindow:(NSWindow *)window completion:(STScreenshotCaptureCompletion)completion {
    if (STCurrentCapture != nil) {
        return;
    }
    NSString *failure = nil;
#if ST_CAPTURE_PORTAL
    STPortalCapture *capture = [[STPortalCapture alloc] init];
    capture.completion = completion;
    STCurrentCapture = capture;
    if ([capture startForWindow:window failure:&failure]) {
        return;
    }
#elif ST_CAPTURE_SNIPPING_TOOL
    (void)window;
    STSnippingToolCapture *capture = [[STSnippingToolCapture alloc] init];
    capture.completion = completion;
    STCurrentCapture = capture;
    if ([capture start:&failure]) {
        return;
    }
#else
    (void)window;
    failure = @"Screenshots are taken with the system's tools on this platform.";
#endif
    STCurrentCapture = nil;
    STScreenshotCaptureCompletion done = [completion copy];
    STCaptureFinishLater(^{
        done(STScreenshotCaptureResultNone, nil, failure);
    });
}

@end
