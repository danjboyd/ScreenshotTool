/*
 * MenuValidationExceptionProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * A menu item whose check raises doesn't stop the rest of the menu being checked (#354).
 * GNUstep checks a whole menu inside one exception handler (-[NSMenu update]), so before the
 * fix a raise in -validateMenuItem: (Paste as New Image asking an unresponsive pasteboard
 * server, say) left every later item as it was: Copy Text and Redact showed disabled with an
 * image open. The tests use a private clipboard check that raises; no real pasteboard.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (MenuValidationExceptionTesting)
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
- (void)pasteAsNewImage:(id)sender;
@end

/// Its clipboard check raises, as GNUstep's pasteboard does when its server doesn't answer.
@interface MenuValidationRaisingDelegate : AppDelegate
@end

@implementation MenuValidationRaisingDelegate
- (BOOL)clipboardHasImage {
    [NSException raise:@"NSPasteboardCommunicationException" format:@"test: pasteboard server did not answer"];
    return NO;
}

/// An always-available item: -validateMenuItem: has no check for it.
- (void)probeAlwaysAvailable:(id)sender {
    (void)sender;
}
@end

/// A validator that raises without the fix's guard, to show what GNUstep does with it.
@interface MenuValidationUnguardedTarget : NSObject
@end

@implementation MenuValidationUnguardedTarget
- (void)raisingAction:(id)sender {
    (void)sender;
}

- (void)plainAction:(id)sender {
    (void)sender;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(raisingAction:)) {
        [NSException raise:NSGenericException format:@"test: validator raised"];
    }
    return YES;
}
@end

@interface MenuValidationExceptionProbeTests : XCTestCase {
    BOOL _shouldSkip;
}
@end

@implementation MenuValidationExceptionProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (NSMenuItem *)itemWithAction:(SEL)action target:(id)target enabled:(BOOL)enabled {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSStringFromSelector(action) action:action keyEquivalent:@""];
    item.target = target;
    item.enabled = enabled;
    return item;
}

- (void)testACheckThatRaisesDisablesItsItemWithoutRaising {
    if (_shouldSkip) {
        return;
    }
    MenuValidationRaisingDelegate *delegate = [[MenuValidationRaisingDelegate alloc] init];
    NSMenuItem *paste = [self itemWithAction:@selector(pasteAsNewImage:) target:delegate enabled:YES];

    BOOL valid = YES;
    XCTAssertNoThrow(valid = [delegate validateMenuItem:paste]);
    XCTAssertFalse(valid, @"an item whose check raised must not show as available");
}

- (void)testItemsAfterARaisingCheckAreStillChecked {
    if (_shouldSkip) {
        return;
    }
    MenuValidationRaisingDelegate *delegate = [[MenuValidationRaisingDelegate alloc] init];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [menu setAutoenablesItems:YES];
    NSMenuItem *paste = [self itemWithAction:@selector(pasteAsNewImage:) target:delegate enabled:YES];
    // Starts disabled, as #354's later items had: only a check that runs enables it.
    NSMenuItem *later = [self itemWithAction:@selector(probeAlwaysAvailable:) target:delegate enabled:NO];
    [menu addItem:paste];
    [menu addItem:later];

    XCTAssertNoThrow([menu update]);
    XCTAssertFalse(paste.isEnabled, @"the item whose check raised is disabled");
    XCTAssertTrue(later.isEnabled, @"the item after it was still checked and enabled");
}

#if defined(GNUSTEP)
/// What the fix guards against: libs-gui stops the menu's pass at a raise, leaving later items
/// as they were. If this ever fails, GNUstep has started checking past a raise itself.
- (void)testGNUstepStopsTheMenuPassAtAnUnguardedRaise {
    if (_shouldSkip) {
        return;
    }
    MenuValidationUnguardedTarget *target = [[MenuValidationUnguardedTarget alloc] init];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [menu setAutoenablesItems:YES];
    NSMenuItem *raising = [self itemWithAction:@selector(raisingAction:) target:target enabled:YES];
    NSMenuItem *later = [self itemWithAction:@selector(plainAction:) target:target enabled:NO];
    [menu addItem:raising];
    [menu addItem:later];

    XCTAssertNoThrow([menu update], @"-[NSMenu update] catches the raise itself");
    XCTAssertFalse(later.isEnabled, @"the item after the raise was never checked, so it stays disabled");
}
#endif

@end
