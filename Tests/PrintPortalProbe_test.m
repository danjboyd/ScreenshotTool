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

/// What the dialog answered goes back to it as it was, through the defaults.
- (void)testAPageSetupRoundTrips {
    GVariant *answer = g_variant_parse(G_VARIANT_TYPE_VARDICT,
        "{'PPDName': <'na_letter'>, 'DisplayName': <'US Letter'>, 'Width': <215.9>, 'Height': <279.4>, 'MarginTop': <6.35>,"
        " 'MarginBottom': <14.22>, 'MarginLeft': <6.35>, 'MarginRight': <6.35>, 'Orientation': <'portrait'>}", NULL, NULL, NULL);
    NSDictionary *saved = STPrintPortalPageSetupDictionaryFromVariant(answer);
    XCTAssertEqualObjects(saved[@"PPDName"], @"na_letter");
    GVariant *back = (GVariant *)STPrintPortalPageSetupVariantFromDictionary(saved);
    g_variant_ref_sink(back);
    // Compared as dictionaries, since the variant's entries needn't keep their order.
    XCTAssertEqualObjects(STPrintPortalPageSetupDictionaryFromVariant(back), saved);
    XCTAssertEqual(g_variant_n_children(back), g_variant_n_children(answer));
    g_variant_unref(back);
    g_variant_unref(answer);
}

/// A partial one fails the whole dialog, so it's never sent.
- (void)testAnIncompletePageSetupAsksForTheDefault {
    NSArray *incomplete = @[ @{}, @{ @"PPDName" : @"A4" },
                             @{ @"PPDName" : @"A4", @"DisplayName" : @"A4", @"Width" : @210.0, @"Height" : @297.0 },
                             @{ @"PPDName" : @7, @"DisplayName" : @"A4", @"Width" : @210.0, @"Height" : @297.0, @"MarginTop" : @1.0,
                                @"MarginBottom" : @1.0, @"MarginLeft" : @1.0, @"MarginRight" : @1.0 } ];
    for (NSDictionary *pageSetup in incomplete) {
        GVariant *variant = (GVariant *)STPrintPortalPageSetupVariantFromDictionary(pageSetup);
        g_variant_ref_sink(variant);
        XCTAssertEqual(g_variant_n_children(variant), (gsize)0, @"%@", pageSetup);
        g_variant_unref(variant);
    }
    GVariant *none = (GVariant *)STPrintPortalPageSetupVariantFromDictionary(nil);
    g_variant_ref_sink(none);
    XCTAssertEqual(g_variant_n_children(none), (gsize)0);
    g_variant_unref(none);
}

/// No portal on this bus (the tests run on a private one): told so, at once, and not asked to write.
- (void)testNoPortalIsReportedAsUnavailable {
    if (![[[NSProcessInfo processInfo] environment][@"DBUS_SESSION_BUS_ADDRESS"] length]) {
        return;
    }
    __block BOOL called = NO, unavailable = NO, wrote = NO;
    __block NSString *message = nil;
    [STPrintPortal printForWindow:nil
                            title:@"Probe"
                        pageSetup:nil
                           writer:^BOOL(STPrintPortalPageSetup setup, NSDictionary<NSString *, id> *pageSetup, NSString *path) {
        wrote = YES;
        return NO;
    }
                       completion:^(BOOL printed, BOOL noService, NSString *failure) {
        called = YES;
        unavailable = noService;
        message = failure;
    }];
    XCTAssertTrue(called);
    XCTAssertTrue(unavailable);
    XCTAssertFalse(wrote);
    XCTAssertTrue([message containsString:@"No print service"], @"%@", message);
    XCTAssertFalse([STPrintPortal isPrinting], @"a next print can start");
}

- (void)testNoPaperIsNotValid {
    XCTAssertFalse([self setupFrom:"{'PPDName': <'A4'>}"].valid);
    XCTAssertFalse([self setupFrom:"{'Width': <210.0>, 'Height': <0.0>}"].valid);
    XCTAssertFalse([self setupFrom:"{'Width': <'210'>, 'Height': <297.0>}"].valid, @"not a number");
    XCTAssertFalse(STPrintPortalPageSetupFromVariant(NULL).valid);
}

@end

#endif
