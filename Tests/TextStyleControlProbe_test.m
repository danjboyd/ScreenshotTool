/*
 * TextStyleControlProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The text bar's style is a segmented control, Plain / Outline / Shadow / Box, rather than a
 * pop-up whose menu flickered while a text box was being edited (#102): it shows the box's style
 * and reports a choice in one click.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "STTextOptionsBar.h"
#import "TestEnvironmentHelpers.h"

@interface STTextOptionsBar (TextStyleControlTesting)
@property (nonatomic, strong) NSSegmentedControl *styleControl;
- (void)styleChanged:(id)sender;
@end

@interface TextStyleControlRecorder : NSObject <STTextOptionsBarDelegate>
@property (nonatomic, assign) NSInteger pickedStyle;
@end

@implementation TextStyleControlRecorder
- (instancetype)init {
    if ((self = [super init])) {
        _pickedStyle = -1;
    }
    return self;
}
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickStyle:(MarkupTextStyle)style { self.pickedStyle = style; }
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickColor:(NSColor *)color {}
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickSizePreset:(STTextSizePreset)preset {}
- (void)textOptionsBar:(STTextOptionsBar *)bar didStepSizeBy:(CGFloat)delta {}
- (void)textOptionsBarDidTogglePointer:(STTextOptionsBar *)bar {}
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickFontFamily:(NSString *)family {}
- (void)textOptionsBarDidToggleBold:(STTextOptionsBar *)bar {}
- (void)textOptionsBarDidToggleItalic:(STTextOptionsBar *)bar {}
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickAlignment:(NSTextAlignment)alignment {}
@end

@interface TextStyleControlProbeTests : XCTestCase {
    BOOL _shouldSkip;
}
@end

@implementation TextStyleControlProbeTests

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

- (STTextOptionsBar *)barShowingStyle:(MarkupTextStyle)style {
    STTextOptionsBar *bar = [[STTextOptionsBar alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1400.0, [STTextOptionsBar preferredHeight])];
    [bar updateWithFont:[NSFont systemFontOfSize:24.0]
                  color:[NSColor redColor]
                  style:style
             sizePreset:STTextSizePresetExact
              alignment:NSTextAlignmentLeft
          boldAvailable:YES
        italicAvailable:YES];
    return bar;
}

- (void)testStyleIsASegmentPerStyle {
    XCTSkipIf(_shouldSkip, @"No window server");
    STTextOptionsBar *bar = [self barShowingStyle:MarkupTextStyleShadow];
    NSSegmentedControl *control = bar.styleControl;
    XCTAssertTrue([control isKindOfClass:[NSSegmentedControl class]]);
    XCTAssertEqual(control.segmentCount, 4);
    NSArray<NSString *> *names = @[@"Plain", @"Outline", @"Shadow", @"Box"];
    for (NSInteger segment = 0; segment < 4; segment++) {
        // Each segment shows its style on an "A", a symbolic icon a theme can tint, and names it.
        NSImage *image = [control imageForSegment:segment];
        XCTAssertNotNil(image, @"segment %ld has a sample image", (long)segment);
        XCTAssertTrue([[image name] hasSuffix:@"-symbolic"], @"%@ is a symbolic icon", [image name]);
        XCTAssertEqualObjects([[control cell] toolTipForSegment:segment], names[segment]);
    }
    XCTAssertEqual(control.selectedSegment, MarkupTextStyleShadow, @"The bar shows the box's style");
    XCTAssertTrue([bar.visibleControls containsObject:control], @"The style control fits a wide bar");
}

- (void)testChoosingASegmentReportsTheStyle {
    XCTSkipIf(_shouldSkip, @"No window server");
    STTextOptionsBar *bar = [self barShowingStyle:MarkupTextStylePlain];
    TextStyleControlRecorder *recorder = [[TextStyleControlRecorder alloc] init];
    bar.delegate = recorder;
    [bar.styleControl setSelectedSegment:MarkupTextStyleBackground];
    [bar styleChanged:bar.styleControl];
    XCTAssertEqual(recorder.pickedStyle, MarkupTextStyleBackground);
}

@end
