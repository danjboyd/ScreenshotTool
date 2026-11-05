/*
 * PrintPortalProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * What Linux reads from the print dialog's answer (#355): its paper, from millimetres. The portal
 * itself is checked end to end in a GNOME session, where the dialog exists.
 */

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#if defined(__linux__)

#include <gio/gio.h>
#import "STPrintPortal.h"

@interface PrintPortalProbeTests : XCTestCase
@end

@implementation PrintPortalProbeTests

- (STPrintPortalPageSetup)setupFrom:(const char *)text {
    GVariant *variant = g_variant_parse(G_VARIANT_TYPE_VARDICT, text, NULL, NULL, NULL);
    XCTAssertTrue(variant != NULL, @"%s", text);
    STPrintPortalPageSetup setup = STPrintPortalPageSetupFromVariant(variant);
    g_variant_unref(variant);
    return setup;
}

- (void)testA4AndItsMarginsInPoints {
    STPrintPortalPageSetup setup = [self setupFrom:
        "{'PPDName': <'A4'>, 'Width': <210.0>, 'Height': <297.0>, 'MarginTop': <6.35>, 'MarginBottom': <12.7>,"
        " 'MarginLeft': <25.4>, 'MarginRight': <3.175>, 'Orientation': <'landscape'>}"];
    XCTAssertTrue(setup.valid);
    XCTAssertEqualWithAccuracy(setup.paper.width, 595.28, 0.01);
    XCTAssertEqualWithAccuracy(setup.paper.height, 841.89, 0.01);
    XCTAssertEqualWithAccuracy(setup.printerMargins.top, 18.0, 0.01);
    XCTAssertEqualWithAccuracy(setup.printerMargins.bottom, 36.0, 0.01);
    XCTAssertEqualWithAccuracy(setup.printerMargins.left, 72.0, 0.01);
    XCTAssertEqualWithAccuracy(setup.printerMargins.right, 9.0, 0.01);
}

- (void)testNoMarginsIsNoPrinterMargin {
    STPrintPortalPageSetup setup = [self setupFrom:"{'Width': <215.9>, 'Height': <279.4>}"];
    XCTAssertTrue(setup.valid);
    XCTAssertEqualWithAccuracy(setup.paper.width, 612.0, 0.01);
    XCTAssertEqualWithAccuracy(setup.printerMargins.top, 0.0, 1e-9);
}

- (void)testNoPaperIsNotValid {
    XCTAssertFalse([self setupFrom:"{'PPDName': <'A4'>}"].valid);
    XCTAssertFalse([self setupFrom:"{'Width': <210.0>, 'Height': <0.0>}"].valid);
    XCTAssertFalse([self setupFrom:"{'Width': <'210'>, 'Height': <297.0>}"].valid, @"not a number");
    XCTAssertFalse(STPrintPortalPageSetupFromVariant(NULL).valid);
}

@end

#endif
