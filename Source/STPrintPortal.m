#import "STPrintPortal.h"

#if defined(__linux__)

#include <fcntl.h>
#include <gio/gio.h>
#include <gio/gunixfdlist.h>
#include <string.h>
#include <unistd.h>
#import "STScreenshotCapture.h"

static const CGFloat STPointsPerMillimetre = 72.0 / 25.4;

static CGFloat STPageSetupPoints(GVariant *setup, const char *key) {
    gdouble millimetres = 0.0;
    if (!g_variant_lookup(setup, key, "d", &millimetres) || !(millimetres > 0.0)) {
        return 0.0;
    }
    return (CGFloat)millimetres * STPointsPerMillimetre;
}

STPrintPortalPageSetup STPrintPortalPageSetupFromVariant(void *pageSetup) {
    STPrintPortalPageSetup setup = { NSZeroSize, STPrintMarginsMake(0, 0, 0, 0), NO };
    GVariant *variant = (GVariant *)pageSetup;
    if (variant == NULL || !g_variant_is_of_type(variant, G_VARIANT_TYPE_VARDICT)) {
        return setup;
    }
    setup.paper = NSMakeSize(STPageSetupPoints(variant, "Width"), STPageSetupPoints(variant, "Height"));
    setup.printerMargins = STPrintMarginsMake(STPageSetupPoints(variant, "MarginTop"), STPageSetupPoints(variant, "MarginLeft"),
                                              STPageSetupPoints(variant, "MarginBottom"), STPageSetupPoints(variant, "MarginRight"));
    setup.valid = setup.paper.width > 0.0 && setup.paper.height > 0.0;
    return setup;
}

static NSArray<NSString *> *STPageSetupStringKeys(void) {
    return @[ @"PPDName", @"Name", @"DisplayName", @"Orientation" ];
}

static NSArray<NSString *> *STPageSetupNumberKeys(void) {
    return @[ @"Width", @"Height", @"MarginTop", @"MarginBottom", @"MarginLeft", @"MarginRight" ];
}

NSDictionary<NSString *, id> *STPrintPortalPageSetupDictionaryFromVariant(void *pageSetup) {
    NSMutableDictionary<NSString *, id> *dictionary = [NSMutableDictionary dictionary];
    GVariant *variant = (GVariant *)pageSetup;
    if (variant == NULL || !g_variant_is_of_type(variant, G_VARIANT_TYPE_VARDICT)) {
        return dictionary;
    }
    for (NSString *key in STPageSetupStringKeys()) {
        const char *value = NULL;
        if (g_variant_lookup(variant, key.UTF8String, "&s", &value) && value != NULL) {
            dictionary[key] = [NSString stringWithUTF8String:value];
        }
    }
    for (NSString *key in STPageSetupNumberKeys()) {
        gdouble value = 0.0;
        if (g_variant_lookup(variant, key.UTF8String, "d", &value)) {
            dictionary[key] = @(value);
        }
    }
    return dictionary;
}

void *STPrintPortalPageSetupVariantFromDictionary(NSDictionary<NSString *, id> *pageSetup) {
    GVariantBuilder builder;
    g_variant_builder_init(&builder, G_VARIANT_TYPE_VARDICT);
    BOOL complete = [pageSetup[@"PPDName"] isKindOfClass:[NSString class]] &&
                    [pageSetup[@"DisplayName"] isKindOfClass:[NSString class]];
    for (NSString *key in STPageSetupNumberKeys()) {
        complete = complete && [pageSetup[key] isKindOfClass:[NSNumber class]];
    }
    if (complete) {
        for (NSString *key in STPageSetupStringKeys()) {
            id value = pageSetup[key];
            if ([value isKindOfClass:[NSString class]]) {
                g_variant_builder_add(&builder, "{sv}", key.UTF8String, g_variant_new_string([value UTF8String]));
            }
        }
        for (NSString *key in STPageSetupNumberKeys()) {
            g_variant_builder_add(&builder, "{sv}", key.UTF8String, g_variant_new_double([pageSetup[key] doubleValue]));
        }
    }
    return g_variant_builder_end(&builder);
}

static NSString * const STPrintNoServiceMessage = @"No print service is available on this desktop (xdg-desktop-portal's Print).";

static STPrintPortal *STActivePrint = nil;

@interface STPrintPortal () {
@public
    GMainContext *_context;
    GDBusConnection *_bus;
    guint _subscription;
    BOOL _answered;
    guint32 _response;
    GVariant *_results;
}
@property (nonatomic, weak) NSWindow *window;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *savedPageSetup;
@property (nonatomic, copy) STPrintPortalWriter writer;
@property (nonatomic, copy) STPrintPortalCompletion completion;
@property (nonatomic, strong) NSTimer *timer;
/// The second request, Print, is under way.
@property (nonatomic) BOOL sending;
@end

static void STPrintPortalResponse(GDBusConnection *connection, const gchar *sender, const gchar *path,
                                  const gchar *interface, const gchar *signal, GVariant *parameters, gpointer data) {
    (void)connection; (void)sender; (void)path; (void)interface; (void)signal;
    STPrintPortal *print = (__bridge STPrintPortal *)data;
    if (!print->_answered && g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ua{sv})"))) {
        g_variant_get(parameters, "(u@a{sv})", &print->_response, &print->_results);
        print->_answered = YES;
    }
}

@implementation STPrintPortal

+ (BOOL)isPrinting {
    return STActivePrint != nil;
}

+ (void)printForWindow:(NSWindow *)window
                 title:(NSString *)title
             pageSetup:(NSDictionary<NSString *, id> *)pageSetup
                writer:(STPrintPortalWriter)writer
            completion:(STPrintPortalCompletion)completion {
    if (STActivePrint) {
        return;
    }
    STPrintPortal *print = [[STPrintPortal alloc] init];
    print.window = window;
    print.title = title;
    print.savedPageSetup = pageSetup;
    print.writer = writer;
    print.completion = completion;
    STActivePrint = print;
    [print prepare];
}

- (void)unsubscribe {
    if (_subscription != 0) {
        g_dbus_connection_signal_unsubscribe(_bus, _subscription);
        _subscription = 0;
    }
}

- (void)finishPrinted:(BOOL)printed failure:(nullable NSString *)failure {
    [self finishPrinted:printed unavailable:NO failure:failure];
}

- (void)finishPrinted:(BOOL)printed unavailable:(BOOL)unavailable failure:(nullable NSString *)failure {
    [self.timer invalidate];
    self.timer = nil;
    [self unsubscribe];
    g_clear_pointer(&_results, g_variant_unref);
    g_clear_object(&_bus);
    g_clear_pointer(&_context, g_main_context_unref);
    STPrintPortalCompletion completion = self.completion;
    self.completion = nil;
    STActivePrint = nil;
    if (completion) {
        completion(printed, unavailable, failure);
    }
}

/// Listens on the request a call will return, and gives its token, so that an answer that comes before
/// the call's reply isn't missed.
- (NSString *)subscribeForNextRequest:(NSString **)token {
    static unsigned long serial = 0;
    *token = [NSString stringWithFormat:@"screenshottool_print%d_%lu", (int)getpid(), ++serial];
    NSMutableString *sender = [NSMutableString stringWithUTF8String:g_dbus_connection_get_unique_name(_bus) + 1];
    [sender replaceOccurrencesOfString:@"." withString:@"_" options:0 range:NSMakeRange(0, sender.length)];
    NSString *path = [NSString stringWithFormat:@"/org/freedesktop/portal/desktop/request/%@/%@", sender, *token];
    [self subscribeToPath:path.UTF8String];
    return path;
}

- (void)subscribeToPath:(const char *)path {
    [self unsubscribe];
    _subscription = g_dbus_connection_signal_subscribe(_bus, "org.freedesktop.portal.Desktop",
                                                       "org.freedesktop.portal.Request", "Response", path, NULL,
                                                       G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE, STPrintPortalResponse,
                                                       (__bridge void *)self, NULL);
}

/// Portals before 0.9 choose the request's path themselves.
- (void)followReply:(GVariant *)reply expected:(NSString *)expected {
    const char *handle = NULL;
    g_variant_get(reply, "(&o)", &handle);
    if (handle != NULL && strcmp(handle, expected.UTF8String) != 0) {
        [self subscribeToPath:handle];
    }
}

- (void)prepare {
    GError *error = NULL;
    _context = g_main_context_new();
    g_main_context_push_thread_default(_context);
    _bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (_bus == NULL) {
        g_main_context_pop_thread_default(_context);
        NSLog(@"Print: no session bus (%s)", error ? error->message : "unknown error");
        g_clear_error(&error);
        [self finishPrinted:NO unavailable:YES failure:STPrintNoServiceMessage];
        return;
    }
    NSString *token = nil;
    NSString *expected = [self subscribeForNextRequest:&token];
    g_main_context_pop_thread_default(_context);

    GVariantBuilder settings, options;
    g_variant_builder_init(&settings, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&options, "{sv}", "handle_token", g_variant_new_string(token.UTF8String));
    g_variant_builder_add(&options, "{sv}", "modal", g_variant_new_boolean(TRUE));
    GVariant *reply = g_dbus_connection_call_sync(_bus, "org.freedesktop.portal.Desktop",
                                                  "/org/freedesktop/portal/desktop",
                                                  "org.freedesktop.portal.Print", "PreparePrint",
                                                  g_variant_new("(ssa{sv}@a{sv}a{sv})", STPortalParentWindow(self.window).UTF8String,
                                                                self.title.UTF8String, &settings,
                                                                (GVariant *)STPrintPortalPageSetupVariantFromDictionary(self.savedPageSetup),
                                                                &options),
                                                  G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
    if (reply == NULL) {
        NSLog(@"Print: PreparePrint failed (%s)", error ? error->message : "unknown error");
        g_clear_error(&error);
        [self finishPrinted:NO unavailable:YES failure:STPrintNoServiceMessage];
        return;
    }
    [self followReply:reply expected:expected];
    g_variant_unref(reply);
    [self startPolling];
}

- (void)startPolling {
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.05 target:self selector:@selector(poll:) userInfo:nil repeats:YES];
    for (NSString *mode in @[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode ]) {
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:mode];
    }
    self.timer = timer;
}

- (void)poll:(NSTimer *)timer {
    (void)timer;
    while (g_main_context_iteration(_context, FALSE)) {
    }
    if (!_answered) {
        return;
    }
    if (self.sending) {
        // 1 is a cancel; a sent job that the portal then refuses is the only failure left.
        guint32 response = _response;
        if (response == 0) {
            [self finishPrinted:YES failure:nil];
        } else {
            [self finishPrinted:NO failure:response == 1 ? nil : @"The desktop couldn't send this to the printer."];
        }
        return;
    }
    [self.timer invalidate];
    self.timer = nil;
    guint32 response = _response;
    if (response != 0) {
        // As with the screenshot portal, 2 is also what some portals answer to a closed dialog.
        NSLog(@"Print: the print dialog answered %u", response);
        [self finishPrinted:NO failure:nil];
        return;
    }
    [self sendPrepared];
}

/// The dialog was answered: writes the PDF for its paper and hands it to the portal.
- (void)sendPrepared {
    guint32 printToken = 0;
    GVariant *pageSetup = NULL;
    if (!g_variant_lookup(_results, "token", "u", &printToken) ||
        !g_variant_lookup(_results, "page-setup", "@a{sv}", &pageSetup)) {
        [self finishPrinted:NO failure:@"The desktop's print dialog gave no printer to print on."];
        return;
    }
    STPrintPortalPageSetup setup = STPrintPortalPageSetupFromVariant(pageSetup);
    NSDictionary<NSString *, id> *chosen = STPrintPortalPageSetupDictionaryFromVariant(pageSetup);
    g_variant_unref(pageSetup);
    if (!setup.valid) {
        [self finishPrinted:NO failure:@"The desktop's print dialog gave no paper size."];
        return;
    }

    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                 [NSString stringWithFormat:@"ScreenshotTool-print-%@.pdf", [[NSUUID UUID] UUIDString]]];
    BOOL wrote = self.writer(setup, chosen, path);
    int fd = wrote ? open(path.fileSystemRepresentation, O_RDONLY | O_CLOEXEC) : -1;
    // Unlinked at once: the open file is all the portal needs, and nothing's left behind on a crash.
    unlink(path.fileSystemRepresentation);
    if (fd < 0) {
        [self finishPrinted:NO failure:@"The pages to print couldn't be written."];
        return;
    }

    GError *error = NULL;
    GUnixFDList *fds = g_unix_fd_list_new();
    gint index = g_unix_fd_list_append(fds, fd, &error);
    close(fd);
    if (index < 0) {
        g_clear_error(&error);
        g_object_unref(fds);
        [self finishPrinted:NO failure:@"The pages to print couldn't be sent."];
        return;
    }

    [self unsubscribe];
    g_clear_pointer(&_results, g_variant_unref);
    _answered = NO;
    self.sending = YES;
    NSString *token = nil;
    g_main_context_push_thread_default(_context);
    NSString *expected = [self subscribeForNextRequest:&token];
    g_main_context_pop_thread_default(_context);

    GVariantBuilder options;
    g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&options, "{sv}", "handle_token", g_variant_new_string(token.UTF8String));
    g_variant_builder_add(&options, "{sv}", "token", g_variant_new_uint32(printToken));
    GVariant *reply = g_dbus_connection_call_with_unix_fd_list_sync(_bus, "org.freedesktop.portal.Desktop",
                                                                    "/org/freedesktop/portal/desktop",
                                                                    "org.freedesktop.portal.Print", "Print",
                                                                    g_variant_new("(ssha{sv})", STPortalParentWindow(self.window).UTF8String,
                                                                                  self.title.UTF8String, index, &options),
                                                                    G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, -1, fds, NULL, NULL, &error);
    g_object_unref(fds);
    if (reply == NULL) {
        NSString *failure = [NSString stringWithFormat:@"The desktop couldn't send this to the printer (%s).",
                                                       error ? error->message : "unknown error"];
        g_clear_error(&error);
        [self finishPrinted:NO failure:failure];
        return;
    }
    [self followReply:reply expected:expected];
    g_variant_unref(reply);
    [self startPolling];
}

@end

#endif
