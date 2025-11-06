/*
 * ToolbarIconThemeProbe.m
 * Regression probe for toolbar icon + label rendering on GNUstep dark themes
 * Copyright (C) 2025 Daniel Boyd
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA.
 */

#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "STThemeUtilities.h"

#if defined(GNUSTEP)
@interface AppDelegate (ToolbarExposure)
@property (nonatomic, assign) BOOL usesDarkTheme;
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
    itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag;
@end

@interface STToolbarItemContainer : NSView
@property (nonatomic, strong) NSButton *button;
@property (nonatomic, strong) NSTextField *labelField;
@end
#endif

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    exit(EXIT_FAILURE);
}

static void ConfigureDarkThemeDefaults(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@"Sombre" forKey:@"GSTheme"];
    [defaults synchronize];
}

static NSColor *DeviceColor(NSColor *color) {
    return [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
#if !defined(GNUSTEP)
        fprintf(stderr, "ToolbarIconThemeProbe: SKIP (not running under GNUstep)\n");
        return EXIT_SUCCESS;
#else
        NSApplication *application = nil;
        @try {
            application = [NSApplication sharedApplication];
        } @catch (NSException *exception) {
            fprintf(stderr, "ToolbarIconThemeProbe: SKIP (failed to connect to window server: %s)\n",
                    [[exception reason] UTF8String]);
            return EXIT_SUCCESS;
        }
        if (!application) {
            fprintf(stderr, "ToolbarIconThemeProbe: SKIP (NSApplication sharedApplication returned nil)\n");
            return EXIT_SUCCESS;
        }

        ConfigureDarkThemeDefaults();

        AppDelegate *delegate = [[AppDelegate alloc] init];
        if (!delegate) {
            FailAndExit(@"ToolbarIconThemeProbe: failed to create AppDelegate");
        }
        delegate.usesDarkTheme = YES;

        NSArray<NSToolbarItemIdentifier> *identifiers = @[
            @"com.screenshottool.toolbar.select",
            @"com.screenshottool.toolbar.highlighter",
            @"com.screenshottool.toolbar.pen",
            @"com.screenshottool.toolbar.text",
            @"com.screenshottool.toolbar.eraser"
        ];

        for (NSToolbarItemIdentifier identifier in identifiers) {
            NSToolbarItem *toolbarItem = [delegate toolbar:nil
                                      itemForItemIdentifier:identifier
                                   willBeInsertedIntoToolbar:YES];
            if (!toolbarItem) {
                FailAndExit([NSString stringWithFormat:@"ToolbarIconThemeProbe: unable to build %@", identifier]);
            }
            if (![toolbarItem.view isKindOfClass:[STToolbarItemContainer class]]) {
                FailAndExit([NSString stringWithFormat:@"ToolbarIconThemeProbe: %@ missing custom container view", identifier]);
            }

            STToolbarItemContainer *container = (STToolbarItemContainer *)toolbarItem.view;
            if (!container.button) {
                FailAndExit([NSString stringWithFormat:@"ToolbarIconThemeProbe: container missing button (%@)", identifier]);
            }

            if (!container.button.image) {
                FailAndExit([NSString stringWithFormat:@"ToolbarIconThemeProbe: toolbar icon image missing for %@", identifier]);
            }

            NSUInteger repCount = container.button.image.representations.count;
            if (repCount == 0) {
                NSLog(@"ToolbarIconThemeProbe: %@ image class=%@ reps=%lu image=%@", identifier, NSStringFromClass([container.button.image class]), (unsigned long)repCount, container.button.image);
                FailAndExit([NSString stringWithFormat:@"ToolbarIconThemeProbe: toolbar icon lacks bitmap data for %@", identifier]);
            }

            NSTextField *labelField = container.labelField;
            if (!labelField) {
                FailAndExit([NSString stringWithFormat:@"ToolbarIconThemeProbe: container missing label for %@", identifier]);
            }
            NSColor *labelColor = DeviceColor(labelField.textColor);
            if (!labelColor) {
                FailAndExit(@"ToolbarIconThemeProbe: label text color unavailable");
            }

            NSColor *expected = DeviceColor(STThemeToolbarLabelColor());
            if (!expected) {
                FailAndExit(@"ToolbarIconThemeProbe: expected theme color unavailable");
            }

            CGFloat tolerance = 0.25f;
            if (fabs(labelColor.redComponent - expected.redComponent) > tolerance ||
                fabs(labelColor.greenComponent - expected.greenComponent) > tolerance ||
                fabs(labelColor.blueComponent - expected.blueComponent) > tolerance) {
                NSString *message = [NSString stringWithFormat:@"ToolbarIconThemeProbe: label colour mismatch for %@. Expected approx (%.3f, %.3f, %.3f) got (%.3f, %.3f, %.3f)",
                                     identifier,
                                     expected.redComponent,
                                     expected.greenComponent,
                                     expected.blueComponent,
                                     labelColor.redComponent,
                                     labelColor.greenComponent,
                                     labelColor.blueComponent];
                FailAndExit(message);
            }
        }
#endif
    }
    return EXIT_SUCCESS;
}
