/*
 * TooltipsSuppressedProbe.m
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
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "AppDelegate.h"
#if defined(GNUSTEP)
#import <AppKit/NSApplication.h>
#import "STToolbarTooltipController.h"

@interface ProbeAppDelegate : AppDelegate
@end

@implementation ProbeAppDelegate

- (void)setupToolbar {
    // Skip real NSToolbar wiring during probe execution to avoid GNUstep crashes
}

@end

@interface AppDelegate (TooltipPrivate)
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
    itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag;
- (NSString *)toolTipForIdentifier:(NSToolbarItemIdentifier)identifier;
- (void)refreshToolButtonIcons;
- (void)applyToolTipToToolbarItem:(NSToolbarItem *)item source:(NSString *)source;
@end

#endif

@interface AppDelegate (TooltipTesting)
- (void)configureTooltipSuppressionDefaults;
@end

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    exit(EXIT_FAILURE);
}

static void AssertBooleanDisabled(NSDictionary *domain, NSString *key, NSString *context) {
    id value = domain[key];
    if (!value) {
        FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: %@ missing (%@)", key, context]);
    }
    if (![value respondsToSelector:@selector(boolValue)]) {
        FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: %@ not boolean (%@)", key, context]);
    }
    if ([(NSNumber *)value boolValue]) {
        FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: %@ still enabled (%@)", key, context]);
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
#if defined(GNUSTEP)
        AppDelegate *delegate = [[ProbeAppDelegate alloc] init];
#else
        AppDelegate *delegate = [[AppDelegate alloc] init];
#endif
        if ([delegate respondsToSelector:@selector(configureTooltipSuppressionDefaults)]) {
            [delegate configureTooltipSuppressionDefaults];
        }

        if (![delegate respondsToSelector:NSSelectorFromString(@"tooltipController")]) {
            fprintf(stderr, "TooltipsSuppressedProbe: SKIP (custom tooltip controller disabled)\n");
            return EXIT_SUCCESS;
        }

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSDictionary *globalDomain = [defaults persistentDomainForName:NSGlobalDomain];
        if (!globalDomain) {
            FailAndExit(@"TooltipsSuppressedProbe: GlobalDomain missing");
        }
        AssertBooleanDisabled(globalDomain, @"GSShowToolTips", @"GlobalDomain");

        NSDictionary *appDomain = [defaults persistentDomainForName:@"ScreenshotTool"];
    if (appDomain && appDomain[@"GSShowToolTips"]) {
        AssertBooleanDisabled(appDomain, @"GSShowToolTips", @"ScreenshotTool");
    }

#if defined(GNUSTEP)
        NSApplication *application = nil;
        @try {
            application = [NSApplication sharedApplication];
        } @catch (NSException *exception) {
            fprintf(stderr, "TooltipsSuppressedProbe: SKIP (failed to connect to window server: %s)\n",
                    [[exception reason] UTF8String]);
            return EXIT_SUCCESS;
        }
        if (!application) {
            fprintf(stderr, "TooltipsSuppressedProbe: SKIP (NSApplication sharedApplication returned nil)\n");
            return EXIT_SUCCESS;
        }

        [delegate applicationWillFinishLaunching:nil];
       [delegate applicationDidFinishLaunching:nil];

        STToolbarTooltipController *controller = [delegate valueForKey:@"tooltipController"];

        NSArray<NSToolbarItemIdentifier> *toolIdentifiers = @[
            @"com.screenshottool.toolbar.highlighter",
            @"com.screenshottool.toolbar.pen",
            @"com.screenshottool.toolbar.text",
            @"com.screenshottool.toolbar.select",
            @"com.screenshottool.toolbar.eraser"
        ];

        NSMutableArray<NSToolbarItem *> *toolbarItems = [[NSMutableArray alloc] init];
        NSMutableDictionary<NSValue *, NSView *> *containersByView = [[NSMutableDictionary alloc] init];
        NSMutableDictionary<NSValue *, NSString *> *expectedTooltipsByView = [[NSMutableDictionary alloc] init];
        NSUInteger expectedRegisteredCount = 0;

        for (NSToolbarItemIdentifier identifier in toolIdentifiers) {
            NSToolbarItem *item = [delegate toolbar:nil
                                itemForItemIdentifier:identifier
                             willBeInsertedIntoToolbar:YES];
            if (!item) {
                FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: missing toolbar item for %@", identifier]);
            }
            NSView *view = item.view;
            if (!view) {
                continue;
            }

            NSRect containerFrame = NSIsEmptyRect(view.bounds) ? NSMakeRect(0, 0, 32, 32) : view.bounds;
            NSView *nativeContainer = [[NSView alloc] initWithFrame:containerFrame];
            [nativeContainer setToolTip:@"native-tooltip"];
            if ([nativeContainer respondsToSelector:@selector(addToolTipRect:owner:userData:)]) {
                [nativeContainer addToolTipRect:nativeContainer.bounds owner:@"native-owner" userData:NULL];
            }
            [nativeContainer addSubview:view];

            [delegate applyToolTipToToolbarItem:item source:@"probe-native-container"];

            if (item.toolTip != nil) {
                FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: toolbar item exposes native tooltip after suppression (%@)", identifier]);
            }
            if (view.toolTip != nil) {
                FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: toolbar view exposes native tooltip after suppression (%@)", identifier]);
            }
            if (nativeContainer.toolTip != nil) {
                FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: container view retained native tooltip (%@)", identifier]);
            }
            if ([nativeContainer respondsToSelector:NSSelectorFromString(@"_toolTips")]) {
                id stored = nil;
                @try {
                    stored = [nativeContainer valueForKey:@"_toolTips"];
                } @catch (NSException *exception) {
                    stored = [NSString stringWithFormat:@"<error:%@>", exception.reason ?: @"unknown"];
                }
                if ([stored respondsToSelector:@selector(count)] && [stored count] > 0) {
                    FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: container still has registered tooltips (%@)", identifier]);
                }
                if (stored && ![stored respondsToSelector:@selector(count)]) {
                    FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: container tooltip storage unexpected type (%@ -> %@)",
                                                             identifier,
                                                             stored]);
                }
            }

            containersByView[[NSValue valueWithNonretainedObject:view]] = nativeContainer;
            NSString *expectedTip = [delegate toolTipForIdentifier:item.itemIdentifier] ?: @"";
            expectedTooltipsByView[[NSValue valueWithNonretainedObject:view]] = expectedTip;
            if (expectedTip.length > 0) {
                expectedRegisteredCount++;
            }
            [toolbarItems addObject:item];
        }

        NSDictionary *trackingTags = @{};
        NSDictionary *registeredTooltips = @{};
        if (controller) {
            trackingTags = [controller registeredTrackingSnapshot] ?: @{};
            if (trackingTags.count != expectedRegisteredCount) {
                FailAndExit(@"TooltipsSuppressedProbe: controller tracking rect mismatch after suppression");
            }
            registeredTooltips = [controller registeredTooltipsSnapshot] ?: @{};
            if (registeredTooltips.count != expectedRegisteredCount) {
                FailAndExit(@"TooltipsSuppressedProbe: controller tooltip count mismatch after suppression");
            }
        }

        for (NSToolbarItem *item in toolbarItems) {
            NSView *view = item.view;
            if (!view) {
                continue;
            }
            NSView *container = containersByView[[NSValue valueWithNonretainedObject:view]];
            if (!container) {
                FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: missing container mapping for %@", item.itemIdentifier]);
            }
            if (container.toolTip != nil) {
                FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: container regained native tooltip (%@)", item.itemIdentifier]);
            }
            NSValue *viewKey = [NSValue valueWithNonretainedObject:view];
            NSString *expected = expectedTooltipsByView[viewKey] ?: @"";
            NSString *registered = registeredTooltips[viewKey];
            NSNumber *tracking = trackingTags[viewKey];
            if (expected.length > 0) {
                if (!registered || ![registered isEqualToString:expected]) {
                    FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: controller registered '%@' but expected '%@' (%@)",
                                                             registered ?: @"<nil>", expected, item.itemIdentifier]);
                }
                if (!tracking) {
                    FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: tracking rect missing for %@", item.itemIdentifier]);
                }
            } else {
                if (registered) {
                    FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: controller retained tooltip for identifier without custom string (%@ -> %@)",
                                                             item.itemIdentifier,
                                                             registered]);
                }
                if (tracking) {
                    FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: tracking rect retained for identifier without custom string (%@)", item.itemIdentifier]);
                }
            }
        }
#else
        NSArray<NSToolbarItemIdentifier> *toolIdentifiers = @[
            @"com.screenshottool.toolbar.highlighter",
            @"com.screenshottool.toolbar.pen",
            @"com.screenshottool.toolbar.text",
            @"com.screenshottool.toolbar.select",
            @"com.screenshottool.toolbar.eraser"
        ];

        for (NSToolbarItemIdentifier identifier in toolIdentifiers) {
            NSToolbarItem *item = [delegate toolbar:nil
                                itemForItemIdentifier:identifier
                             willBeInsertedIntoToolbar:YES];
            if (!item) {
                FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: missing toolbar item for %@", identifier]);
            }
            if (item.toolTip != nil) {
                FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: toolbar item exposes native tooltip (%@)", identifier]);
            }
        }
#endif
        objc_retain(delegate);
    }
    return EXIT_SUCCESS;
}
