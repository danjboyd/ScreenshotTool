/*
 * StatusBarToggleProbe.m
 * Ensures hiding the status bar collapses its reserved space so the scroll view
 * reclaiming the content height does not leave a blank strip.
 */

#import <AppKit/AppKit.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#import "AppDelegate.h"
#import "PreferencesWindowController.h"

static const CGFloat kStatusBarHeight = 24.0f;

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", message.UTF8String ?: "StatusBarToggleProbe: failure");
    exit(EXIT_FAILURE);
}

static void STConfigureDefaultsRoot(void) __attribute__((constructor));

static void STConfigureDefaultsRoot(void) {
    char templatePath[] = "/tmp/ScreenshotToolDefaultsXXXXXX";
    char *defaultsDir = mkdtemp(templatePath);
    if (defaultsDir) {
        setenv("GNUSTEP_DEFAULTS_ROOT", defaultsDir, 1);
        char defaultsFile[PATH_MAX];
        snprintf(defaultsFile, sizeof(defaultsFile), "%s/GNUstepDefaults.plist", defaultsDir);
        setenv("GNUSTEP_USER_DEFAULTS", defaultsFile, 1);
    }
}

@interface AppDelegate (StatusBarToggleTesting)
- (void)setupWindowAndContent;
- (void)resizeWindowToImageSize:(NSSize)size;
- (NSWindow *)window;
- (NSScrollView *)scrollView;
- (NSView *)statusBarView;
- (void)preferencesController:(PreferencesWindowController *)controller didToggleStatusBar:(BOOL)show;
- (void)layoutContentSubviews;
@end

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *application = nil;
        @try {
            application = [NSApplication sharedApplication];
        } @catch (NSException *exception) {
            fprintf(stderr, "StatusBarToggleProbe: SKIP (failed to connect to window server: %s)\n",
                    [[exception reason] UTF8String]);
            return EXIT_SUCCESS;
        }
        if (!application) {
            fprintf(stderr, "StatusBarToggleProbe: SKIP (NSApplication sharedApplication returned nil)\n");
            return EXIT_SUCCESS;
        }

        AppDelegate *delegate = [[AppDelegate alloc] init];
        [delegate setupWindowAndContent];
        [delegate.window makeKeyAndOrderFront:nil];

        // Match the normal sizing path the app uses when loading an image.
        NSSize imageSize = NSMakeSize(640.0f, 480.0f);
        [delegate resizeWindowToImageSize:imageSize];
        [delegate layoutContentSubviews];

        NSView *contentView = delegate.window.contentView;
        if (!contentView) {
            FailAndExit(@"StatusBarToggleProbe: missing content view");
        }
        NSScrollView *scrollView = delegate.scrollView;
        if (!scrollView) {
            FailAndExit(@"StatusBarToggleProbe: missing scroll view");
        }
        NSView *statusBar = delegate.statusBarView;
        if (!statusBar) {
            FailAndExit(@"StatusBarToggleProbe: missing status bar view");
        }

        CGFloat initialContentHeight = contentView.frame.size.height;
        CGFloat initialScrollHeight = scrollView.frame.size.height;
        CGFloat initialScrollOrigin = scrollView.frame.origin.y;
        if (fabs(initialScrollOrigin - kStatusBarHeight) > 0.75f) {
            FailAndExit(@"StatusBarToggleProbe: initial scroll view origin did not account for status bar height");
        }

        [delegate preferencesController:nil didToggleStatusBar:NO];
        [delegate layoutContentSubviews];

        CGFloat hiddenContentHeight = contentView.frame.size.height;
        CGFloat hiddenScrollOrigin = scrollView.frame.origin.y;
        CGFloat hiddenScrollHeight = scrollView.frame.size.height;
        CGFloat statusBarHeight = statusBar.frame.size.height;

        if (statusBarHeight > 0.5f) {
            FailAndExit(@"StatusBarToggleProbe: status bar frame height not collapsed when hidden");
        }
        if (hiddenScrollOrigin > 0.5f) {
            FailAndExit(@"StatusBarToggleProbe: scroll view did not slide to the bottom after hiding status bar");
        }
        if (hiddenContentHeight > initialContentHeight - (kStatusBarHeight - 0.5f)) {
            FailAndExit(@"StatusBarToggleProbe: content view did not reclaim the status bar height when hidden");
        }
        if (hiddenScrollHeight - initialScrollHeight > 1.0f) {
            FailAndExit(@"StatusBarToggleProbe: scroll view grew instead of reusing the reclaimed height");
        }

        [delegate preferencesController:nil didToggleStatusBar:YES];
        [delegate layoutContentSubviews];

        CGFloat restoredContentHeight = contentView.frame.size.height;
        CGFloat restoredScrollOrigin = scrollView.frame.origin.y;
        if (fabs(restoredContentHeight - initialContentHeight) > 1.0f) {
            FailAndExit(@"StatusBarToggleProbe: content view height not restored after re-showing status bar");
        }
        if (fabs(restoredScrollOrigin - kStatusBarHeight) > 0.75f) {
            FailAndExit(@"StatusBarToggleProbe: scroll view origin not restored after re-showing status bar");
        }
    }
    return EXIT_SUCCESS;
}
