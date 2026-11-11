/*
 * PrintAccessoryProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The macOS print panel's options (#355): STPrintAccessoryController starts from STPrintOptions,
 * keeps the print view's layout in step as they change, takes the panel's orientation as a choice,
 * and saves under the keys every platform shares. No print panel is shown. macOS only.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if !defined(GNUSTEP)
#import "STPrintAccessoryController.h"
#import "STPrintLayout.h"
#import "STPrintOptions.h"
#import "STPrintView.h"

@interface PrintAccessoryProbeTests : XCTestCase
@end

@implementation PrintAccessoryProbeTests

- (NSUserDefaults *)scratchDefaults:(NSString **)suiteName {
    NSString *name = [NSString stringWithFormat:@"com.danboyd.screenshottool.printprobe.%@", [NSUUID UUID].UUIDString];
    *suiteName = name;
    return [[NSUserDefaults alloc] initWithSuiteName:name];
}

/// A 2000 × 1000 image on Letter: wide, so automatic orientation is landscape.
- (STPrintLayout *)letterLayout {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.sourceRect = NSMakeRect(0, 0, 2000, 1000);
    layout.pixelsPerInch = 72.0;
    layout.paperSize = NSMakeSize(612, 792);
    layout.margins = STPrintMarginsMake(18, 18, 18, 18);
    return layout;
}

- (void)testItStartsFromTheOptions {
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.fit = STPrintFitCustomScale;
    options.customScale = 1.5;
    options.orientation = STPrintOrientationPortrait;
    options.selectionOnly = YES;
    STPrintAccessoryController *controller = [[STPrintAccessoryController alloc] initWithOptions:options hasSelection:NO];
    XCTAssertEqual(controller.fitIndex, 2);
    XCTAssertEqual(controller.scalePercent, 150);
    XCTAssertFalse(controller.automaticOrientation);
    XCTAssertFalse(controller.selectionOnly, @"no selection, so not the selection");
    STPrintOptions *back = controller.options;
    XCTAssertEqual(back.fit, STPrintFitCustomScale);
    XCTAssertEqualWithAccuracy(back.customScale, 1.5, 0.001);
    XCTAssertEqual(back.orientation, STPrintOrientationPortrait);
}

/// A change reaches the print view's layout at once, so the preview's page count follows it, and
/// the app hears about it to give the view the image it needs.
- (void)testChangesReachTheLayout {
    STPrintLayout *layout = [self letterLayout];
    STPrintView *view = [[STPrintView alloc] initWithLayout:layout image:[[NSImage alloc] initWithSize:NSMakeSize(2000, 1000)]];
    STPrintAccessoryController *controller = [[STPrintAccessoryController alloc] initWithOptions:[[STPrintOptions alloc] init]
                                                                                    hasSelection:YES];
    NSPrintInfo *info = [[NSPrintInfo alloc] initWithDictionary:@{}];
    info.paperSize = layout.paperSize;
    controller.representedObject = info;
    controller.printView = view;
    __block STPrintOptions *heard = nil;
    controller.optionsDidChange = ^(STPrintOptions *options) {
        heard = options;
    };

    controller.fitIndex = 1;
    XCTAssertEqual(layout.fit, STPrintFitActualSize);
    XCTAssertGreaterThan(layout.pageCount, (NSUInteger)1, @"2000 px at 72 ppi takes several pages");
    XCTAssertEqual(heard.fit, STPrintFitActualSize);
    XCTAssertEqual(info.orientation, NSPaperOrientationLandscape, @"the sheet turns with the layout");

    controller.fitIndex = 2;
    controller.scalePercent = 5;
    XCTAssertEqual(controller.scalePercent, 10, @"kept to the options' minimum");
    XCTAssertEqualWithAccuracy(layout.customScale, 0.1, 0.001);
    XCTAssertEqual(layout.pageCount, (NSUInteger)1);

    controller.selectionOnly = YES;
    XCTAssertTrue(heard.selectionOnly);
}

/// Turning the sheet in the panel is a choice: "Turn automatically" goes off, and it's saved.
- (void)testThePanelsOrientationIsAChoice {
    STPrintLayout *layout = [self letterLayout];
    STPrintView *view = [[STPrintView alloc] initWithLayout:layout image:[[NSImage alloc] initWithSize:NSMakeSize(2000, 1000)]];
    STPrintAccessoryController *controller = [[STPrintAccessoryController alloc] initWithOptions:[[STPrintOptions alloc] init]
                                                                                    hasSelection:NO];
    controller.printView = view;
    __weak STPrintAccessoryController *weakController = controller;
    view.printInfoChoseOrientation = ^(STPrintOrientation orientation) {
        [weakController printViewChoseOrientation:orientation];
    };
    NSPrintInfo *info = [[NSPrintInfo alloc] initWithDictionary:@{}];
    info.paperSize = layout.paperSize;
    STPreparePrintInfo(info, layout);
    XCTAssertEqual(info.orientation, NSPaperOrientationLandscape);

    // Nothing turned: still automatic.
    [view takePaperFromPrintInfo:info];
    XCTAssertTrue(controller.automaticOrientation);
    XCTAssertEqual(layout.orientation, STPrintOrientationAutomatic);

    info.orientation = NSPaperOrientationPortrait;
    [view takePaperFromPrintInfo:info];
    XCTAssertFalse(controller.automaticOrientation);
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationPortrait);
    XCTAssertEqual(controller.options.orientation, STPrintOrientationPortrait);
    XCTAssertEqualWithAccuracy(view.frame.size.width, 612.0, 0.5, @"the view is the portrait sheet");

    NSString *suite = nil;
    NSUserDefaults *defaults = [self scratchDefaults:&suite];
    [controller saveToDefaults:defaults];
    XCTAssertEqualObjects([defaults stringForKey:STDefaultsPrintOrientationKey], @"portrait");
    [defaults removePersistentDomainForName:suite];
}

/// Turning automatic off without touching the panel's orientation keeps its current direction.
- (void)testTurningAutomaticOffSavesTheCurrentPanelOrientation {
    STPrintLayout *layout = [self letterLayout];
    STPrintOptions *initial = [[STPrintOptions alloc] init];
    [initial applyToLayout:layout];
    NSPrintInfo *info = [[NSPrintInfo alloc] initWithDictionary:@{}];
    info.paperSize = layout.paperSize;
    STPreparePrintInfo(info, layout);
    XCTAssertEqual(info.orientation, NSPaperOrientationLandscape);

    STPrintAccessoryController *controller = [[STPrintAccessoryController alloc] initWithOptions:initial hasSelection:NO];
    STPrintView *view = [[STPrintView alloc] initWithLayout:layout image:[[NSImage alloc] initWithSize:NSMakeSize(2000, 1000)]];
    controller.printView = view;
    controller.representedObject = info;
    controller.automaticOrientation = NO;
    XCTAssertEqual(controller.options.orientation, STPrintOrientationLandscape);
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationLandscape);

    NSString *suite = nil;
    NSUserDefaults *defaults = [self scratchDefaults:&suite];
    [controller saveToDefaults:defaults];
    XCTAssertEqualObjects([defaults stringForKey:STDefaultsPrintOrientationKey], @"landscape");
    STPrintAccessoryController *reopened = [[STPrintAccessoryController alloc]
        initWithOptions:[STPrintOptions optionsFromDefaults:defaults] hasSelection:NO];
    XCTAssertFalse(reopened.automaticOrientation);
    XCTAssertEqual(reopened.options.orientation, STPrintOrientationLandscape);

    // A later automatic interval must not reuse an older explicit portrait choice.
    layout.orientation = STPrintOrientationPortrait;
    [controller printViewChoseOrientation:STPrintOrientationPortrait];
    controller.automaticOrientation = YES;
    XCTAssertEqual(layout.resolvedOrientation, STPrintOrientationLandscape);
    controller.automaticOrientation = NO;
    XCTAssertEqual(controller.options.orientation, STPrintOrientationLandscape);
    [defaults removePersistentDomainForName:suite];
}

/// Dismissing the sheet does not persist a temporary orientation choice.
- (void)testCancellingAfterTurningAutomaticOffKeepsSavedOrientation {
    NSString *suite = nil;
    NSUserDefaults *defaults = [self scratchDefaults:&suite];
    STPrintAccessoryController *controller = [[STPrintAccessoryController alloc]
        initWithOptions:[STPrintOptions optionsFromDefaults:defaults] hasSelection:NO];
    controller.automaticOrientation = NO;
    XCTAssertFalse(controller.automaticOrientation);

    STPrintAccessoryController *reopened = [[STPrintAccessoryController alloc]
        initWithOptions:[STPrintOptions optionsFromDefaults:defaults] hasSelection:NO];
    XCTAssertTrue(reopened.automaticOrientation);
    XCTAssertNil([defaults objectForKey:STDefaultsPrintOrientationKey]);
    [defaults removePersistentDomainForName:suite];
}

/// The shared keys, as Linux and Windows read them.
- (void)testItSavesTheSharedKeys {
    STPrintAccessoryController *controller = [[STPrintAccessoryController alloc] initWithOptions:[[STPrintOptions alloc] init]
                                                                                    hasSelection:YES];
    controller.fitIndex = 2;
    controller.scalePercent = 250;
    controller.enlargeToFill = YES;
    controller.selectionOnly = YES;
    NSString *suite = nil;
    NSUserDefaults *defaults = [self scratchDefaults:&suite];
    [controller saveToDefaults:defaults];
    XCTAssertEqualObjects([defaults stringForKey:STDefaultsPrintFitKey], @"custom");
    XCTAssertEqualWithAccuracy([defaults doubleForKey:STDefaultsPrintCustomScaleKey], 2.5, 0.001);
    XCTAssertTrue([defaults boolForKey:STDefaultsPrintEnlargeToFillKey]);
    XCTAssertEqualObjects([defaults stringForKey:STDefaultsPrintOrientationKey], @"auto");

    STPrintOptions *read = [STPrintOptions optionsFromDefaults:defaults];
    XCTAssertEqual(read.fit, STPrintFitCustomScale);
    XCTAssertFalse(read.selectionOnly, @"the selection isn't remembered");
    [defaults removePersistentDomainForName:suite];
}

/// The panel shows the options as controls bound to them, and sums them up.
- (void)testTheViewAndSummary {
    STPrintAccessoryController *controller = [[STPrintAccessoryController alloc] initWithOptions:[[STPrintOptions alloc] init]
                                                                                    hasSelection:NO];
    NSView *view = controller.view;
    NSMutableDictionary<NSString *, NSView *> *byIdentifier = [NSMutableDictionary dictionary];
    NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithObject:view];
    while (pending.count > 0) {
        NSView *next = pending.lastObject;
        [pending removeLastObject];
        if (next.identifier) {
            byIdentifier[next.identifier] = next;
        }
        [pending addObjectsFromArray:next.subviews];
    }
    NSPopUpButton *fit = (NSPopUpButton *)byIdentifier[@"fit"];
    XCTAssertEqual(fit.numberOfItems, 3);
    XCTAssertEqual(fit.indexOfSelectedItem, 0);
    XCTAssertFalse(((NSTextField *)byIdentifier[@"scale"]).enabled, @"the scale is for Custom Scale");
    XCTAssertFalse(((NSButton *)byIdentifier[@"selection"]).enabled, @"no selection to print");
    XCTAssertTrue(((NSButton *)byIdentifier[@"enlarge"]).enabled);

    controller.fitIndex = 2;
    XCTAssertEqual(fit.indexOfSelectedItem, 2, @"the popup follows its binding");
    XCTAssertTrue(((NSTextField *)byIdentifier[@"scale"]).enabled);
    XCTAssertFalse(((NSButton *)byIdentifier[@"enlarge"]).enabled, @"enlarging is for Fit to Page");

    NSSet *keys = [controller keyPathsForValuesAffectingPreview];
    XCTAssertTrue([keys containsObject:@"fitIndex"]);
    XCTAssertTrue([keys containsObject:@"selectionOnly"]);
    NSArray *summary = [controller localizedSummaryItems];
    XCTAssertEqualObjects(summary.firstObject[NSPrintPanelAccessorySummaryItemDescriptionKey], @"100% of actual size");
}

/// Annotations always print (a redaction is one): there's no option for them.
- (void)testThereIsNoAnnotationsOption {
    STPrintAccessoryController *controller = [[STPrintAccessoryController alloc] initWithOptions:[[STPrintOptions alloc] init]
                                                                                    hasSelection:YES];
    NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithObject:controller.view];
    while (pending.count > 0) {
        NSView *next = pending.lastObject;
        [pending removeLastObject];
        if ([next isKindOfClass:[NSButton class]]) {
            XCTAssertFalse([((NSButton *)next).title localizedCaseInsensitiveContainsString:@"annotation"],
                           @"no annotations option: %@", ((NSButton *)next).title);
        }
        [pending addObjectsFromArray:next.subviews];
    }
}

@end
#endif
