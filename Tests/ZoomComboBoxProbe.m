/*
 * ZoomComboBoxProbe.m
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

static NSString * const ToolbarItemZoomIdentifier = @"com.screenshottool.toolbar.zoom";

@interface AppDelegate (ZoomPopUpTesting)
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) ScreenshotCanvasView *canvasView;
@property (nonatomic, strong) NSToolbar *toolbar;
@property (nonatomic, strong) NSPopUpButton *zoomPopUpButton;
@property (nonatomic, strong) NSMutableArray<NSString *> *zoomOptions;
- (void)rebuildZoomPopUpButton;
- (void)updateZoomPopUpSelection;
- (void)setupWindowAndContent;
- (void)setupToolbar;
- (NSToolbarItem *)toolbarItemForZoomControl;
@end

@interface ComboBoxProbeAppDelegate : AppDelegate
@end

@implementation ComboBoxProbeAppDelegate
@end

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    exit(EXIT_FAILURE);
}

static void AssertPopUpHasItems(NSPopUpButton *popUp, NSArray<NSString *> *expected, NSString *context) {
    if (!popUp) {
        FailAndExit([NSString stringWithFormat:@"Pop-up button was nil (%@)", context]);
    }
    if ((NSInteger)popUp.numberOfItems != (NSInteger)expected.count) {
        NSString *message = [NSString stringWithFormat:@"Expected %lu items, got %ld (%@)",
                             (unsigned long)expected.count, (long)popUp.numberOfItems, context];
        FailAndExit(message);
    }
    for (NSInteger index = 0; index < (NSInteger)expected.count; index++) {
        NSString *title = [popUp itemTitleAtIndex:index];
        if (![title isEqualToString:expected[(NSUInteger)index]]) {
            NSString *message = [NSString stringWithFormat:@"Item %ld mismatch: %@ vs %@ (%@)",
                                 (long)index, title, expected[(NSUInteger)index], context];
            FailAndExit(message);
        }
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        if (!app) {
            FailAndExit(@"NSApplication sharedApplication returned nil");
        }

        ComboBoxProbeAppDelegate *delegate = [[ComboBoxProbeAppDelegate alloc] init];
        [app setDelegate:delegate];

        NSToolbarItem *zoomItem = [delegate toolbarItemForZoomControl];
        NSPopUpButton *attachedPopUp = (NSPopUpButton *)zoomItem.view;
        if (!attachedPopUp || ![attachedPopUp isKindOfClass:[NSPopUpButton class]]) {
            FailAndExit(@"Zoom toolbar item did not provide an NSPopUpButton view");
        }
        if (delegate.zoomPopUpButton != attachedPopUp) {
            FailAndExit(@"Zoom pop-up property did not track attached toolbar view");
        }
        if ([attachedPopUp target] != delegate || [attachedPopUp action] != @selector(zoomPopUpSelectionChanged:)) {
            FailAndExit(@"Zoom pop-up target/action not set on AppDelegate");
        }

        AssertPopUpHasItems(attachedPopUp, delegate.zoomOptions, @"initial toolbar pop-up");

        // Simulate GNUstep cloning the pop-up button when embedding in a toolbar item.
        NSPopUpButton *clonedPopUp = [[NSPopUpButton alloc] initWithFrame:attachedPopUp.frame pullsDown:NO];
        [clonedPopUp setAutoenablesItems:NO];
        [clonedPopUp setTarget:delegate];
        [clonedPopUp setAction:@selector(zoomPopUpSelectionChanged:)];
        [delegate setZoomPopUpButton:clonedPopUp];
        [delegate rebuildZoomPopUpButton];
        [delegate updateZoomPopUpSelection];
        AssertPopUpHasItems(clonedPopUp, delegate.zoomOptions, @"cloned toolbar pop-up");
    }
    return EXIT_SUCCESS;
}
