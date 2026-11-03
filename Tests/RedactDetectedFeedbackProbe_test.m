/*
 * RedactDetectedFeedbackProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Redact Emails and Phone Numbers always says how it went, and tells "no text" apart from
 * "nothing matched" (#333). The recognizer is replaced by a canned result, so this runs the same
 * with every engine (Vision, tesseract, Windows.Media.Ocr).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "STTextRecognizer.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (RedactDetectedFeedbackTesting)
- (void)setupWindowAndContent;
- (ScreenshotCanvasView *)canvasView;
- (void)redactDetectedText:(id)sender;
- (void)readTextInImageRect:(NSRect)rect completion:(void (^)(NSArray<STRecognizedLine *> *lines))completion;
- (void)showCopyFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration;
@end

extern NSString *STRedactDetectedFeedback(BOOL foundText, NSUInteger redacted);

@interface RedactDetectedFeedbackProbeAppDelegate : AppDelegate
@property (nonatomic, copy) NSArray<STRecognizedLine *> *cannedLines;
@property (nonatomic, strong) NSMutableArray<NSString *> *feedbackMessages;
@end

@implementation RedactDetectedFeedbackProbeAppDelegate

- (void)readTextInImageRect:(NSRect)rect completion:(void (^)(NSArray<STRecognizedLine *> *lines))completion {
    (void)rect;
    completion(self.cannedLines ?: @[]);
}

- (void)showCopyFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration {
    (void)duration;
    if (!self.feedbackMessages) {
        self.feedbackMessages = [NSMutableArray array];
    }
    [self.feedbackMessages addObject:[message copy] ?: @""];
}

@end

@interface RedactDetectedFeedbackProbeTests : XCTestCase {
    RedactDetectedFeedbackProbeAppDelegate *_appDelegate;
    BOOL _shouldSkip;
}
@end

@implementation RedactDetectedFeedbackProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
    _appDelegate = [[RedactDetectedFeedbackProbeAppDelegate alloc] init];
    @try {
        [_appDelegate setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
        return;
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(400.0, 200.0)];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 400.0, 200.0));
    [image unlockFocus];
    [_appDelegate.canvasView loadImage:image];
}

- (void)tearDown {
    _appDelegate = nil;
    [super tearDown];
}

- (STRecognizedLine *)lineWithWords:(NSArray<NSString *> *)texts {
    NSMutableArray<STRecognizedWord *> *words = [NSMutableArray array];
    CGFloat x = 10.0;
    for (NSString *text in texts) {
        CGFloat width = 8.0 * text.length;
        [words addObject:[[STRecognizedWord alloc] initWithText:text bounds:NSMakeRect(x, 20.0, width, 14.0)]];
        x += width + 6.0;
    }
    return [[STRecognizedLine alloc] initWithWords:words];
}

- (void)testNoTextSaysSo {
    if (_shouldSkip) {
        return;
    }
    _appDelegate.cannedLines = @[];
    [_appDelegate redactDetectedText:nil];
    XCTAssertEqualObjects(_appDelegate.feedbackMessages, @[ @"No text found in the image" ]);
}

- (void)testTextWithoutMatchesSaysNothingMatched {
    if (_shouldSkip) {
        return;
    }
    _appDelegate.cannedLines = @[ [self lineWithWords:@[ @"Quarterly", @"report", @"draft" ]] ];
    [_appDelegate redactDetectedText:nil];
    XCTAssertEqualObjects(_appDelegate.feedbackMessages, @[ @"No email addresses or phone numbers found" ]);
}

- (void)testAMatchIsRedactedAndCounted {
    if (_shouldSkip) {
        return;
    }
    _appDelegate.cannedLines = @[ [self lineWithWords:@[ @"Mail", @"dan@example.com", @"today" ]] ];
    [_appDelegate redactDetectedText:nil];
    XCTAssertEqualObjects(_appDelegate.feedbackMessages, @[ @"Redacted 1 item" ]);
}

- (void)testFeedbackWording {
    XCTAssertEqualObjects(STRedactDetectedFeedback(NO, 0), @"No text found in the image");
    XCTAssertEqualObjects(STRedactDetectedFeedback(YES, 0), @"No email addresses or phone numbers found");
    XCTAssertEqualObjects(STRedactDetectedFeedback(YES, 1), @"Redacted 1 item");
    XCTAssertEqualObjects(STRedactDetectedFeedback(YES, 3), @"Redacted 3 items");
}

@end
