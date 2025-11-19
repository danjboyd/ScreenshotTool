/*
 * TextFontComboProbe.m
 * Validates that the TextTool font combo keeps GNUstep's data-source mode.
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
#import <stdio.h>
#import "TextToolPopoverController.h"

@interface TextToolPopoverController (Testing)
@property (nonatomic, strong) NSComboBox *fontComboBox;
@property (nonatomic, copy) NSArray<NSString *> *filteredFontFamilies;
@property (nonatomic, copy) NSString *currentFontComboSelection;
@property (nonatomic, copy) NSString *pendingFontComboStringValue;
- (void)comboBoxSelectionDidChange:(NSNotification *)notification;
- (void)finalizeFontComboSelectionWithInput:(NSString *)input;
- (void)applyFontSelectionChange;
- (void)setFontComboSelectionToFamily:(NSString *)family;
- (void)flushPendingFontComboStringValueIfNeeded;
@end

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    exit(EXIT_FAILURE);
}

@interface STFakeFieldEditor : NSResponder
@end

@implementation STFakeFieldEditor
@end

@interface STProbeComboBox : NSComboBox
@property (nonatomic, assign) NSInteger testingIndex;
@property (nonatomic, copy) NSString *testingStringValue;
@property (nonatomic, assign) BOOL editing;
@property (nonatomic, strong) STFakeFieldEditor *fakeEditor;
@end

@implementation STProbeComboBox

- (instancetype)init {
    self = [super init];
    if (self) {
        _testingIndex = -1;
        _fakeEditor = [[STFakeFieldEditor alloc] init];
    }
    return self;
}

- (NSInteger)indexOfSelectedItem {
    return self.testingIndex;
}

- (void)selectItemAtIndex:(NSInteger)index {
    self.testingIndex = index;
}

- (void)deselectItemAtIndex:(NSInteger)index {
    if (self.testingIndex == index) {
        self.testingIndex = -1;
    }
}

- (NSString *)stringValue {
    return self.testingStringValue ?: @"";
}

- (void)setStringValue:(NSString *)string {
    self.testingStringValue = [string copy];
}

- (void)reloadData {
    // Tests do not depend on live AppKit data here.
}

- (void)noteNumberOfItemsChanged {
}

- (id)currentEditor {
    return self.editing ? self.fakeEditor : nil;
}

- (id)objectValueOfSelectedItem {
    FailAndExit(@"font combo attempted to call objectValueOfSelectedItem while in data-source mode");
    return nil;
}

@end

@interface ProbeTextToolPopoverController : TextToolPopoverController
@property (nonatomic, assign) NSInteger finalizeInvocations;
@property (nonatomic, assign) NSInteger applyFontInvocations;
@property (nonatomic, copy) NSString *lastFinalizeInput;
@end

@implementation ProbeTextToolPopoverController

- (void)finalizeFontComboSelectionWithInput:(NSString *)input {
    self.finalizeInvocations += 1;
    self.lastFinalizeInput = input ?: @"";
    self.currentFontComboSelection = input ?: @"";
}

- (void)applyFontSelectionChange {
    self.applyFontInvocations += 1;
}

@end

static void RunSelectionScenario(ProbeTextToolPopoverController *controller,
                                 STProbeComboBox *combo,
                                 NSInteger index,
                                 NSString *typedString,
                                 NSString *expectedSelection) {
    combo.testingIndex = index;
    combo.testingStringValue = typedString;
    NSNotification *note = [NSNotification notificationWithName:NSComboBoxSelectionDidChangeNotification
                                                        object:combo
                                                      userInfo:nil];
    [controller comboBoxSelectionDidChange:note];

    if (![controller.lastFinalizeInput isEqualToString:expectedSelection]) {
        NSString *message = [NSString stringWithFormat:@"Expected selection '%@' but saw '%@'",
                             expectedSelection, controller.lastFinalizeInput];
        FailAndExit(message);
    }
}

static void RunEditingDeferralScenario(ProbeTextToolPopoverController *controller,
                                       STProbeComboBox *combo) {
    combo.testingStringValue = @"Initial";
    controller.pendingFontComboStringValue = nil;
    combo.editing = YES;
    [controller setFontComboSelectionToFamily:@"Fira Code"];
    if (controller.pendingFontComboStringValue.length == 0 ||
        ![controller.pendingFontComboStringValue isEqualToString:@"Fira Code"]) {
        FailAndExit(@"Expected pending combo string to capture new value while editing");
    }
    if (![combo.stringValue isEqualToString:@"Initial"]) {
        FailAndExit(@"Combo string should not change while editing");
    }
    combo.editing = NO;
    [controller flushPendingFontComboStringValueIfNeeded];
    if (![combo.stringValue isEqualToString:@"Fira Code"]) {
        FailAndExit(@"Pending combo string did not flush after editing ended");
    }
    if (controller.pendingFontComboStringValue.length != 0) {
        FailAndExit(@"Pending combo string should clear after flushing");
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        if (!app) {
            FailAndExit(@"TextFontComboProbe: NSApplication unavailable");
        }
        ProbeTextToolPopoverController *controller = [[ProbeTextToolPopoverController alloc] init];
        STProbeComboBox *combo = [[STProbeComboBox alloc] init];
        controller.fontComboBox = combo;
        controller.filteredFontFamilies = @[ @"Arial", @"Courier", @"Fira Code" ];

        RunSelectionScenario(controller, combo, 1, @"Courier", @"Courier");
        RunSelectionScenario(controller, combo, -1, @"Papyrus", @"Papyrus");
        RunEditingDeferralScenario(controller, combo);

        if (controller.finalizeInvocations != 2 || controller.applyFontInvocations != 2) {
            FailAndExit(@"Expected combo selection handler to invoke finalize/apply exactly twice");
        }
    }
    return EXIT_SUCCESS;
}
