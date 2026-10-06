/*
 * TextFontMenuProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The text toolbar's font pop-up lists every font family, built in one pass (#82), and its
 * items look like a pop-up's own: no tick next to the selected font.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "STTextOptionsBar.h"
#import "TestEnvironmentHelpers.h"

@interface STTextOptionsBar (TextFontMenuTesting)
@property (nonatomic, strong) NSPopUpButton *fontPopUp;
@end

@interface TextFontMenuProbeTests : XCTestCase {
    BOOL _shouldSkip;
}
@end

@implementation TextFontMenuProbeTests

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

- (void)testFontPopUpListsEveryFamilyWithoutTicks {
    if (_shouldSkip) {
        return;
    }
    STTextOptionsBar *bar = [[STTextOptionsBar alloc] initWithFrame:NSMakeRect(0.0, 0.0, 900.0, [STTextOptionsBar preferredHeight])];
    NSPopUpButton *popUp = bar.fontPopUp;
    XCTAssertNotNil(popUp);

    NSArray<NSString *> *families = [[[NSFontManager sharedFontManager] availableFontFamilies]
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    XCTAssertEqual(popUp.numberOfItems, (NSInteger)families.count);
    if (families.count > 0) {
        XCTAssertEqualObjects([popUp itemTitleAtIndex:0], families.firstObject);
        XCTAssertEqualObjects([popUp itemTitleAtIndex:popUp.numberOfItems - 1], families.lastObject);
        XCTAssertGreaterThan(popUp.titleOfSelectedItem.length, 0u);
    }
    for (NSMenuItem *item in popUp.itemArray) {
        XCTAssertNil(item.onStateImage, @"%@ would show a tick when selected", item.title);
        XCTAssertNil(item.mixedStateImage, @"%@ has a mixed-state image", item.title);
    }
}

@end
