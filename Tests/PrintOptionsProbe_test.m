/*
 * PrintOptionsProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The print options (#355): their defaults, that they're remembered, and that a saved value this
 * version doesn't understand reads as the default instead of reaching the print UI.
 */

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#import "STPrintLayout.h"
#import "STPrintOptions.h"

@interface PrintOptionsProbeTests : XCTestCase
@end

@implementation PrintOptionsProbeTests

- (void)clearDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[ STDefaultsPrintFitKey, STDefaultsPrintCustomScaleKey, STDefaultsPrintEnlargeToFillKey,
                             STDefaultsPrintOrientationKey, STDefaultsPrintAnnotationsKey ]) {
        [defaults removeObjectForKey:key];
    }
}

- (void)setUp {
    [super setUp];
    [self clearDefaults];
}

- (void)tearDown {
    [self clearDefaults];
    [super tearDown];
}

- (void)testTheDefaults {
    STPrintOptions *options = [STPrintOptions optionsFromDefaults:[NSUserDefaults standardUserDefaults]];
    XCTAssertEqual(options.fit, STPrintFitToPage);
    XCTAssertEqualWithAccuracy(options.customScale, 1.0, 1e-9);
    XCTAssertFalse(options.enlargeToFill);
    XCTAssertEqual(options.orientation, STPrintOrientationAutomatic);
    XCTAssertTrue(options.includeAnnotations);
    XCTAssertFalse(options.selectionOnly);
}

- (void)testTheyAreRemembered {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.fit = STPrintFitCustomScale;
    options.customScale = 0.5;
    options.enlargeToFill = YES;
    options.orientation = STPrintOrientationLandscape;
    options.includeAnnotations = NO;
    [options saveToDefaults:defaults];

    STPrintOptions *read = [STPrintOptions optionsFromDefaults:defaults];
    XCTAssertEqual(read.fit, STPrintFitCustomScale);
    XCTAssertEqualWithAccuracy(read.customScale, 0.5, 1e-9);
    XCTAssertTrue(read.enlargeToFill);
    XCTAssertEqual(read.orientation, STPrintOrientationLandscape);
    XCTAssertFalse(read.includeAnnotations);

    options.fit = STPrintFitActualSize;
    options.orientation = STPrintOrientationPortrait;
    [options saveToDefaults:defaults];
    read = [STPrintOptions optionsFromDefaults:defaults];
    XCTAssertEqual(read.fit, STPrintFitActualSize);
    XCTAssertEqual(read.orientation, STPrintOrientationPortrait);
}

/// It's about one print's image, so the next print doesn't start with it on.
- (void)testSelectionOnlyIsNotRemembered {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.selectionOnly = YES;
    [options saveToDefaults:defaults];
    XCTAssertFalse([STPrintOptions optionsFromDefaults:defaults].selectionOnly);
}

- (void)testUnknownSavedValuesReadAsTheDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@"booklet" forKey:STDefaultsPrintFitKey];
    [defaults setObject:@7 forKey:STDefaultsPrintOrientationKey];
    [defaults setObject:@[ @1 ] forKey:STDefaultsPrintCustomScaleKey];
    STPrintOptions *options = [STPrintOptions optionsFromDefaults:defaults];
    XCTAssertEqual(options.fit, STPrintFitToPage);
    XCTAssertEqual(options.orientation, STPrintOrientationAutomatic);
    XCTAssertEqualWithAccuracy(options.customScale, 1.0, 1e-9);
}

- (void)testTheScaleStaysInRange {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:100.0 forKey:STDefaultsPrintCustomScaleKey];
    XCTAssertEqualWithAccuracy([STPrintOptions optionsFromDefaults:defaults].customScale, STPrintOptionsMaximumScale, 1e-9);
    [defaults setDouble:0.001 forKey:STDefaultsPrintCustomScaleKey];
    XCTAssertEqualWithAccuracy([STPrintOptions optionsFromDefaults:defaults].customScale, STPrintOptionsMinimumScale, 1e-9);
    [defaults setDouble:-1.0 forKey:STDefaultsPrintCustomScaleKey];
    XCTAssertEqualWithAccuracy([STPrintOptions optionsFromDefaults:defaults].customScale, 1.0, 1e-9);
    [defaults setDouble:0.0 forKey:STDefaultsPrintCustomScaleKey];
    XCTAssertEqualWithAccuracy([STPrintOptions optionsFromDefaults:defaults].customScale, 1.0, 1e-9);
}

- (void)testTheyApplyToALayout {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.sourceRect = NSMakeRect(0, 0, 400, 200);
    layout.paperSize = NSMakeSize(612, 792);
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.fit = STPrintFitCustomScale;
    options.customScale = 2.0;
    options.enlargeToFill = YES;
    options.orientation = STPrintOrientationPortrait;
    [options applyToLayout:layout];
    XCTAssertEqual(layout.fit, STPrintFitCustomScale);
    XCTAssertEqualWithAccuracy(layout.customScale, 2.0, 1e-9);
    XCTAssertTrue(layout.enlargeToFill);
    XCTAssertEqual(layout.orientation, STPrintOrientationPortrait);
    XCTAssertTrue(NSEqualRects(layout.sourceRect, NSMakeRect(0, 0, 400, 200)), @"not the options' to change");
}

- (void)testACopyIsIndependent {
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.selectionOnly = YES;
    options.customScale = 0.5;
    STPrintOptions *copy = [options copy];
    XCTAssertTrue(copy.selectionOnly);
    XCTAssertEqualWithAccuracy(copy.customScale, 0.5, 1e-9);
    copy.customScale = 2.0;
    XCTAssertEqualWithAccuracy(options.customScale, 0.5, 1e-9);
}

@end
