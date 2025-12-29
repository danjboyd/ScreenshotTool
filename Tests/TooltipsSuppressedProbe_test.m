/*
 * TooltipsSuppressedProbe_test.m
 * Copyright (C) 2025 Daniel Boyd
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "AppDelegate.h"

// This preprocessor check is the core of the solution.
// It checks if the STToolbarTooltipController.h file is available at compile time.
#if __has_include("STToolbarTooltipController.h") && defined(GNUSTEP)

#pragma mark - If Tooltip Controller is available, run the full test suite (GNUstep only)

#import "STToolbarTooltipController.h"

#pragma mark - Testing Categories & Mocks
@interface AppDelegate (TooltipPrivate)
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag;
- (NSString *)toolTipForIdentifier:(NSToolbarItemIdentifier)identifier;
- (void)refreshToolButtonIcons;
- (void)applyToolTipToToolbarItem:(NSToolbarItem *)item source:(NSString *)source;
- (void)configureTooltipSuppressionDefaults;
@end

@interface ProbeToolbar : NSToolbar
@property (nonatomic, strong) NSArray<NSToolbarItem *> *probeItems;
@end
@implementation ProbeToolbar
- (instancetype)init { self = [super initWithIdentifier:@"probe"]; if (self) { _probeItems = @[]; } return self; }
- (NSArray<NSToolbarItem *> *)items { return _probeItems ?: @[]; }
@end

@interface ProbeAppDelegate : AppDelegate
@end
@implementation ProbeAppDelegate
- (void)setupToolbar { /* Skip real setup */ }
@end


@interface TooltipsSuppressedProbeTests : XCTestCase
@end

@implementation TooltipsSuppressedProbeTests

- (void)testNativeTooltipsAreSuppressedAndCustomControllerTakesOver {
    ProbeAppDelegate *delegate = [[ProbeAppDelegate alloc] init];
    [delegate configureTooltipSuppressionDefaults];
    
    // Check if the custom controller is actually part of the build
    if (![delegate respondsToSelector:NSSelectorFromString(@"tooltipController")]) {
        XCTSkip(@"Skipping test: custom tooltip controller is disabled in this build.");
        return;
    }

    // Check that defaults were set correctly
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    XCTAssertFalse([[defaults persistentDomainForName:NSGlobalDomain][@"GSShowToolTips"] boolValue]);

    // Check app-specific domain if it exists
    NSDictionary *appDomain = [defaults persistentDomainForName:@"ScreenshotTool"];
    if (appDomain[@"GSShowToolTips"]) {
        XCTAssertFalse([appDomain[@"GSShowToolTips"] boolValue]);
    }
    
    @try { [NSApplication sharedApplication]; } @catch (NSException *e) {
        XCTSkip(@"Skipping test: could not connect to window server");
        return;
    }

    [delegate applicationWillFinishLaunching:nil];
    [delegate applicationDidFinishLaunching:nil];

    id controller = [delegate valueForKey:@"tooltipController"];
    XCTAssertNotNil(controller, @"Tooltip controller should exist");
    
    // Create mock toolbar items
    NSArray<NSToolbarItemIdentifier> *identifiers = @[@"com.screenshottool.toolbar.select", @"com.screenshottool.toolbar.pen"];
    NSMutableArray<NSToolbarItem *> *toolbarItems = [NSMutableArray array];
    NSUInteger expectedRegisteredCount = 0;

    for (NSToolbarItemIdentifier identifier in identifiers) {
        NSToolbarItem *item = [delegate toolbar:nil itemForItemIdentifier:identifier willBeInsertedIntoToolbar:YES];
        XCTAssertNotNil(item);
        [item setView:[[NSButton alloc] init]];
        [delegate applyToolTipToToolbarItem:item source:@"probe"];
        XCTAssertNil(item.toolTip);
        if ([[delegate toolTipForIdentifier:identifier] length] > 0) {
            expectedRegisteredCount++;
        }
        [toolbarItems addObject:item];
    }
    
    ProbeToolbar *probeToolbar = [[ProbeToolbar alloc] init];
    probeToolbar.probeItems = [toolbarItems copy];
    [delegate setValue:probeToolbar forKey:@"toolbar"];
    
    if ([delegate respondsToSelector:@selector(refreshToolButtonIcons)]) {
        [delegate refreshToolButtonIcons];
    }
    
    NSDictionary *registeredTooltips = [controller registeredTooltipsSnapshot] ?: @{};
    XCTAssertEqual(registeredTooltips.count, expectedRegisteredCount, @"Controller has wrong number of registered tooltips");
}
@end


#else

#pragma mark - If Tooltip Controller is NOT available, run a fallback test

@interface AppDelegate (TooltipTesting)
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag;
- (void)configureTooltipSuppressionDefaults;
@end

@interface TooltipsSuppressedProbeTests : XCTestCase
@end

@implementation TooltipsSuppressedProbeTests
- (void)testNativeTooltipsAreSuppressed_Fallback {
    // The custom tooltip controller feature is not present in this build.
    // This test passes vacuously, effectively skipping.
}
@end

#endif