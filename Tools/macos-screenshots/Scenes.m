// Sets up a screen for Tools/screenshots_macos.sh, loaded into the app with DYLD_INSERT_LIBRARIES.
//
//   SCREENSHOT_SCENE=text      the text tool, a red label being typed (the text bar shows)
//   SCREENSHOT_SCENE=popover   the highlighter's settings popover
//   SCREENSHOT_DARK=1          dark mode, for the app only
//
// The app's own classes are reached by name: this is built on its own, not with the app.

#import <AppKit/AppKit.h>
#import <objc/message.h>

static NSWindow *STMainWindow(void) {
    for (NSWindow *window in [NSApp windows]) {
        if (window.toolbar) {
            return window;
        }
    }
    return nil;
}

static NSView *STFindView(NSView *view, Class cls) {
    if ([view isKindOfClass:cls]) {
        return view;
    }
    for (NSView *subview in view.subviews) {
        NSView *found = STFindView(subview, cls);
        if (found) {
            return found;
        }
    }
    return nil;
}

static void STSceneText(void) {
    NSWindow *window = STMainWindow();
    [window makeKeyAndOrderFront:nil];
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(NSApp.delegate, NSSelectorFromString(@"selectTool:"), 3); // Text
    NSView *canvas = STFindView(window.contentView, NSClassFromString(@"ScreenshotCanvasView"));
    [canvas setValue:[NSColor colorWithSRGBRed:0.86 green:0.10 blue:0.12 alpha:1.0] forKey:@"textColor"];
    // Once the window is key, so the label keeps the keyboard.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ((void (*)(id, SEL, NSRect, id))objc_msgSend)(canvas, NSSelectorFromString(@"beginTextEntryWithImageRect:existingText:"),
                                                      NSMakeRect(395.0, 120.0, 1.0, 1.0), nil);
        ((BOOL (*)(id, SEL))objc_msgSend)(canvas, NSSelectorFromString(@"focusActiveTextView"));
        NSTextView *textView = [canvas valueForKey:@"activeTextView"];
        [textView insertText:@"Best day" replacementRange:NSMakeRange(NSNotFound, 0)];
    });
}

/// A double click on the tool switcher's highlighter segment, which opens its settings.
static void STScenePopover(void) {
    NSWindow *window = STMainWindow();
    [window makeKeyAndOrderFront:nil];
    for (NSToolbarItem *item in window.toolbar.items) {
        if (![item.view isKindOfClass:[NSSegmentedControl class]]) {
            continue;
        }
        NSSegmentedControl *control = (NSSegmentedControl *)item.view;
        NSInteger segment = 1; // Highlighter
        CGFloat x = 0.0;
        for (NSInteger index = 0; index < segment; index++) {
            x += [control widthForSegment:index];
        }
        NSPoint point = [control convertPoint:NSMakePoint(x + [control widthForSegment:segment] * 0.5, NSMidY(control.bounds))
                                       toView:nil];
        NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:0
                                        windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:2 pressure:1.0];
        [control mouseDown:click];
    }
}

__attribute__((constructor)) static void STScenesLoad(void) {
    const char *scene = getenv("SCREENSHOT_SCENE");
    if (!scene) {
        return;
    }
    BOOL dark = getenv("SCREENSHOT_DARK") != NULL;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (dark) {
            NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        }
    });
    NSString *name = @(scene);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([name isEqualToString:@"text"]) {
            STSceneText();
        } else if ([name isEqualToString:@"popover"]) {
            STScenePopover();
        }
    });
}
