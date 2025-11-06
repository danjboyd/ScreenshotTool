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

@interface STFakeToolbar : NSToolbar
@property (nonatomic, strong) NSArray<NSToolbarItem *> *mockItems;
@end

@implementation STFakeToolbar

- (NSArray *)items {
    return self.mockItems ?: [super items];
}

@end

@interface AppDelegate (TooltipPrivate)
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
    itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag;
- (NSString *)toolTipForIdentifier:(NSToolbarItemIdentifier)identifier;
- (void)refreshToolButtonIcons;
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
        if (!controller) {
            FailAndExit(@"TooltipsSuppressedProbe: tooltip controller unavailable");
        }

        NSArray<NSToolbarItemIdentifier> *toolIdentifiers = @[
            @"com.screenshottool.toolbar.highlighter",
            @"com.screenshottool.toolbar.pen",
            @"com.screenshottool.toolbar.text",
            @"com.screenshottool.toolbar.select",
            @"com.screenshottool.toolbar.eraser"
        ];

        NSMutableArray<NSToolbarItem *> *toolbarItems = [[NSMutableArray alloc] init];
        for (NSToolbarItemIdentifier identifier in toolIdentifiers) {
            NSToolbarItem *item = [delegate toolbar:nil
                                itemForItemIdentifier:identifier
                             willBeInsertedIntoToolbar:YES];
            if (!item) {
                FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: missing toolbar item for %@", identifier]);
            }
            if (!item.view) {
                FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: toolbar item %@ missing custom view", identifier]);
            }
            [toolbarItems addObject:item];
        }

        NSDictionary *trackingTags = [controller registeredTrackingSnapshot];
        if (trackingTags.count == 0) {
            FailAndExit(@"TooltipsSuppressedProbe: custom controller did not register tracking rects");
        }

        NSDictionary *registeredTooltips = [controller registeredTooltipsSnapshot];
        if (registeredTooltips.count == 0) {
            FailAndExit(@"TooltipsSuppressedProbe: custom controller did not capture tooltip strings");
        }

        STFakeToolbar *fakeToolbar = [[STFakeToolbar alloc] initWithIdentifier:@"ProbeToolbar"];
        fakeToolbar.mockItems = toolbarItems;
        [delegate setValue:fakeToolbar forKey:@"toolbar"];
        [delegate refreshToolButtonIcons];

        trackingTags = [controller registeredTrackingSnapshot];
        if (trackingTags.count < toolbarItems.count) {
            FailAndExit(@"TooltipsSuppressedProbe: controller tracking rect count too low after refresh");
        }
        registeredTooltips = [controller registeredTooltipsSnapshot];
        if (registeredTooltips.count < toolbarItems.count) {
            FailAndExit(@"TooltipsSuppressedProbe: controller tooltip count too low after refresh");
        }

        for (NSToolbarItem *item in toolbarItems) {
            NSView *view = item.view;
            if (!view) {
                FailAndExit(@"TooltipsSuppressedProbe: toolbar item lost custom view after refresh");
            }
            if (item.toolTip != nil) {
                FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: toolbar item exposes native tooltip (%@)", item.itemIdentifier]);
            }
            if (view.toolTip != nil) {
                FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: toolbar view exposes native tooltip (%@)", item.itemIdentifier]);
            }
            NSString *expected = [delegate toolTipForIdentifier:item.itemIdentifier] ?: @"";
            NSString *registered = registeredTooltips[[NSValue valueWithNonretainedObject:view]];
            if (expected.length > 0 && (!registered || ![registered isEqualToString:expected])) {
                FailAndExit([NSString stringWithFormat:@"TooltipsSuppressedProbe: controller registered '%@' but expected '%@' (%@)",
                                                         registered ?: @"<nil>", expected, item.itemIdentifier]);
            }
        }
#endif
    }
    return EXIT_SUCCESS;
}
