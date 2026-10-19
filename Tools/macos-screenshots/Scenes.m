// Sets up a screen for Tools/screenshots_macos.sh, loaded into the app with DYLD_INSERT_LIBRARIES.
//
//   SCREENSHOT_SCENE=text      the sample marked up, with "Turn this on" being typed (the text bar shows)
//   SCREENSHOT_SCENE=popover   the same markup finished, and the highlighter's settings popover
//   SCREENSHOT_DARK=1          dark mode, for the app only
//
// The markup is the README's shared scene, as the Windows shots have it, in the sample's pixels
// (Tools/screenshot-sample/security-settings.png, origin at the top left).
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

static NSString *STColorString(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color;
    return [NSString stringWithFormat:@"%f,%f,%f,%f", rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent];
}

static void STAddStroke(NSView *canvas, NSDictionary *representation) {
    id stroke = ((id (*)(id, SEL, id))objc_msgSend)(NSClassFromString(@"MarkupStroke"),
                                                     NSSelectorFromString(@"strokeWithProjectRepresentation:"), representation);
    NSUInteger count = [[canvas valueForKey:@"strokes"] count];
    ((void (*)(id, SEL, id, NSUInteger, BOOL, id))objc_msgSend)(canvas,
        NSSelectorFromString(@"insertStroke:atIndex:registeringUndo:actionName:"), stroke, count, NO, @"Scene");
}

/// Redact the email and API key, highlight the 2FA status, number two steps and point at the toggle,
/// each in the colour and width its tool has by default.
static void STAddMarkup(NSView *canvas) {
    NSString *pen = STColorString([canvas valueForKey:@"penColor"]);
    NSNumber *penWidth = [canvas valueForKey:@"penLineWidth"];
    NSString *highlighter = STColorString([canvas valueForKey:@"highlighterColor"]);
    NSNumber *highlighterWidth = [canvas valueForKey:@"highlighterLineWidth"];
    // Types: 1 highlighter, 2 arrow, 4 step, 5 redact.
    STAddStroke(canvas, @{ @"type": @5, @"color": pen, @"lineWidth": penWidth, @"points": @[@[@354, @151], @[@548, @177]] });
    STAddStroke(canvas, @{ @"type": @5, @"color": pen, @"lineWidth": penWidth, @"points": @[@[@354, @263], @[@568, @289]] });
    STAddStroke(canvas, @{ @"type": @1, @"color": highlighter, @"lineWidth": highlighterWidth,
                           @"points": @[@[@242, @349], @[@530, @349]] });
    STAddStroke(canvas, @{ @"type": @4, @"color": pen, @"lineWidth": penWidth, @"number": @1, @"points": @[@[@158, @147]] });
    STAddStroke(canvas, @{ @"type": @4, @"color": pen, @"lineWidth": penWidth, @"number": @2, @"points": @[@[@212, @327]] });
    STAddStroke(canvas, @{ @"type": @2, @"color": pen, @"lineWidth": penWidth, @"points": @[@[@680, @337], @[@764, @337]] });
}

/// The text tool typing "Turn this on" left of the arrow: red, M, bold, no outline. Set on the canvas
/// rather than through the text bar, which would save them as the user's defaults.
static void STTypeLabel(NSView *canvas) {
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(NSApp.delegate, NSSelectorFromString(@"selectTool:"), 3); // Text
    [canvas setValue:[NSColor colorWithSRGBRed:0.86 green:0.10 blue:0.12 alpha:1.0] forKey:@"textColor"];
    [canvas setValue:@2 forKey:@"textSizePreset"]; // M
    [canvas setValue:@0 forKey:@"textStyle"];      // Plain
    NSFont *font = [canvas valueForKey:@"textFont"] ?: [NSFont systemFontOfSize:18.0];
    [canvas setValue:[[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSBoldFontMask] forKey:@"textFont"];
    ((void (*)(id, SEL, NSRect, id))objc_msgSend)(canvas, NSSelectorFromString(@"beginTextEntryWithImageRect:existingText:"),
                                                  NSMakeRect(590.0, 326.0, 1.0, 1.0), nil);
    ((BOOL (*)(id, SEL))objc_msgSend)(canvas, NSSelectorFromString(@"focusActiveTextView"));
    NSTextView *textView = [canvas valueForKey:@"activeTextView"];
    [textView insertText:@"Turn this on" replacementRange:NSMakeRange(NSNotFound, 0)];
}

static void STRunScene(NSString *name) {
    NSWindow *window = STMainWindow();
    [window makeKeyAndOrderFront:nil];
    NSView *canvas = STFindView(window.contentView, NSClassFromString(@"ScreenshotCanvasView"));
    STAddMarkup(canvas);
    // Once the window is key, so the label keeps the keyboard.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        STTypeLabel(canvas);
        if (![name isEqualToString:@"popover"]) {
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // Choosing the highlighter finishes the label.
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(NSApp.delegate, NSSelectorFromString(@"selectTool:"), 0);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // What the colour button's click does: the current tool's settings.
                ((void (*)(id, SEL, id))objc_msgSend)(NSApp.delegate, NSSelectorFromString(@"showActiveToolColorSettings:"), nil);
            });
        });
    });
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
        STRunScene(name);
    });
}
