/*
 * TextRecognizerProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Copy Text and Redact Emails and Phone Numbers (#278): reading tesseract's output, finding the
 * emails and phone numbers in what was read, and, where tesseract is installed, reading the
 * README's sample screenshot.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "STTextRecognizer.h"
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "MarkupStroke.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (TextRecognizerTesting)
- (void)setupWindowAndContent;
- (ScreenshotCanvasView *)canvasView;
- (BOOL)readingText;
- (void)redactDetectedText:(id)sender;
- (NSUndoManager *)activeUndoManager;
@end

@interface ScreenshotCanvasView (TextRecognizerTesting)
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@end

@interface TextRecognizerProbeTests : XCTestCase
@end

@implementation TextRecognizerProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

/// A line of words, each 10 px wide with a 4 px gap, at `y`.
- (STRecognizedLine *)lineWithWords:(NSArray<NSString *> *)texts y:(CGFloat)y {
    NSMutableArray<STRecognizedWord *> *words = [[NSMutableArray alloc] init];
    CGFloat x = 10.0;
    for (NSString *text in texts) {
        [words addObject:[[STRecognizedWord alloc] initWithText:text bounds:NSMakeRect(x, y, 10.0, 12.0)]];
        x += 14.0;
    }
    return [[STRecognizedLine alloc] initWithWords:words];
}

- (void)testTesseractTSVGroupsWordsIntoLines {
    NSString *tsv = @"level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n"
                    @"1\t1\t0\t0\t0\t0\t0\t0\t860\t520\t-1\t\n"
                    @"4\t1\t1\t1\t1\t0\t21\t16\t102\t21\t-1\t\n"
                    @"5\t1\t1\t1\t1\t1\t21\t16\t40\t21\t95.1\tEmail\n"
                    @"5\t1\t1\t1\t1\t2\t70\t16\t180\t21\t91.0\talex@example.com\n"
                    @"5\t1\t1\t1\t2\t1\t21\t50\t60\t21\t90.2\tPassword\n"
                    @"5\t1\t1\t1\t2\t2\t90\t50\t8\t21\t10.0\t \n"
                    @"5\t1\t2\t1\t1\t1\t21\t90\t30\t21\t88.0\tTeam\n";
    NSArray<STRecognizedLine *> *lines = STLinesFromTesseractTSV(tsv);
    XCTAssertEqual(lines.count, (NSUInteger)3);
    XCTAssertEqualObjects(lines[0].text, @"Email alex@example.com");
    XCTAssertEqualObjects(lines[1].text, @"Password", @"blank words are left out");
    XCTAssertEqualObjects(lines[2].text, @"Team", @"a new block is a new line");
    XCTAssertTrue(NSEqualRects(lines[0].words[1].bounds, NSMakeRect(70.0, 16.0, 180.0, 21.0)));
    XCTAssertTrue(NSEqualRects(lines[0].bounds, NSMakeRect(21.0, 16.0, 229.0, 21.0)));
    XCTAssertEqualObjects(STRecognizedText(lines), @"Email alex@example.com\nPassword\nTeam");
    XCTAssertEqual(STLinesFromTesseractTSV(@"").count, (NSUInteger)0);
}

- (void)testEmailsAndPhoneNumbersAreFound {
    NSArray<STRecognizedLine *> *lines = @[
        [self lineWithWords:@[@"Mail", @"alex.rivera@example.co.uk", @"today"] y:0.0],
        [self lineWithWords:@[@"Call", @"(512)", @"555-0142", @"now"] y:20.0],
        [self lineWithWords:@[@"Intl", @"+44", @"20", @"7946", @"0958"] y:40.0],
    ];
    NSArray<NSValue *> *rects = STSensitiveTextRects(lines);
    XCTAssertEqual(rects.count, (NSUInteger)3);
    // The email's word alone, a little larger.
    XCTAssertTrue(NSEqualRects(rects[0].rectValue, NSMakeRect(21.0, -3.0, 16.0, 18.0)), @"%@", rects[0]);
    // "(512) 555-0142": its two words.
    XCTAssertTrue(NSEqualRects(rects[1].rectValue, NSMakeRect(21.0, 17.0, 30.0, 18.0)), @"%@", rects[1]);
    // "+44 20 7946 0958": four words.
    XCTAssertTrue(NSEqualRects(rects[2].rectValue, NSMakeRect(21.0, 37.0, 58.0, 18.0)), @"%@", rects[2]);
}

- (void)testDatesTimesAndCountsAreLeftAlone {
    NSArray<STRecognizedLine *> *lines = @[
        [self lineWithWords:@[@"Last", @"changed", @"2026-10-22", @"at", @"13:45"] y:0.0],
        [self lineWithWords:@[@"Version", @"0.3.3", @"of", @"12", @"files"] y:20.0],
        [self lineWithWords:@[@"Not", @"an", @"email:", @"alex@", @"or", @"@home"] y:40.0],
    ];
    XCTAssertEqual(STSensitiveTextRects(lines).count, (NSUInteger)0, @"%@", STSensitiveTextRects(lines));
}

/// With an engine (Vision on macOS, Windows.Media.Ocr on Windows, tesseract on Linux when it's
/// installed), the README's sample reads, and its email address is found.
/// The README's sample: a settings page with one email address and no phone number.
- (NSString *)samplePath {
    // The suite runs from the repository's root.
    NSString *sample = [[[NSFileManager defaultManager] currentDirectoryPath]
        stringByAppendingPathComponent:@"Tools/screenshot-sample/security-settings.png"];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:sample], @"%@", sample);
    return sample;
}

/// Redact Emails and Phone Numbers on the sample: one redaction, over the email, undone in one step.
- (void)testRedactDetectedTextAddsOneUndoableStep {
    if (![STTextRecognizer isAvailable]) {
        NSLog(@"tesseract isn't installed: the sample isn't read");
        return;
    }
    AppDelegate *delegate = nil;
    @try {
        [NSApplication sharedApplication];
        delegate = [[AppDelegate alloc] init];
        [delegate setupWindowAndContent];
    } @catch (NSException *exception) {
        delegate = nil;
    }
    XCTSkipIf(delegate == nil, @"No window server");
    [delegate.canvasView loadImage:[[NSImage alloc] initWithContentsOfFile:[self samplePath]]];
    NSBitmapImageRep *before = [NSBitmapImageRep imageRepWithData:[[delegate.canvasView flattenedImage] TIFFRepresentation]];

    [delegate redactDetectedText:nil];
    XCTAssertTrue(delegate.readingText, @"reads in the background");
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30.0];
    while (delegate.readingText && [until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    XCTAssertFalse(delegate.readingText);
    XCTAssertEqual(delegate.canvasView.strokes.count, (NSUInteger)1);
    XCTAssertEqual(delegate.canvasView.strokes.firstObject.type, MarkupStrokeTypeRedact);

    // It pixelates the email where it is, not its mirror image: the boxes read are from the top,
    // as the canvas's image coordinates are.
    NSRect box = [delegate.canvasView.strokes.firstObject shapeRect];
    NSBitmapImageRep *after = [NSBitmapImageRep imageRepWithData:[[delegate.canvasView flattenedImage] TIFFRepresentation]];
    NSUInteger changedInside = 0;
    NSUInteger changedMirror = 0;
    NSUInteger a[5] = {0};
    NSUInteger b[5] = {0};
    for (NSInteger y = (NSInteger)NSMinY(box); y < (NSInteger)NSMaxY(box); y++) {
        for (NSInteger x = (NSInteger)NSMinX(box); x < (NSInteger)NSMaxX(box); x++) {
            [before getPixel:a atX:x y:y];
            [after getPixel:b atX:x y:y];
            changedInside += (a[0] != b[0] || a[1] != b[1] || a[2] != b[2]) ? 1 : 0;
            NSInteger mirrorY = before.pixelsHigh - 1 - y;
            [before getPixel:a atX:x y:mirrorY];
            [after getPixel:b atX:x y:mirrorY];
            changedMirror += (a[0] != b[0] || a[1] != b[1] || a[2] != b[2]) ? 1 : 0;
        }
    }
    XCTAssertGreaterThan(changedInside, (NSUInteger)50, @"the email is pixelated");
    XCTAssertEqual(changedMirror, (NSUInteger)0, @"and nothing at its mirror image");

    NSUndoManager *undo = [delegate activeUndoManager];
    XCTAssertTrue(undo.canUndo);
    [undo undo];
    XCTAssertEqual(delegate.canvasView.strokes.count, (NSUInteger)0, @"one step undoes them all");
}

/// The engine's lines for `rect` of the sample (all of it for NSZeroRect).
- (NSArray<STRecognizedLine *> *)linesOfSampleInRect:(NSRect)rect {
    __block NSArray<STRecognizedLine *> *lines = nil;
    __block BOOL done = NO;
    [STTextRecognizer recognizeTextInImageAtURL:[NSURL fileURLWithPath:[self samplePath]]
                                           rect:rect
                                     completion:^(NSArray<STRecognizedLine *> *l, NSString *f) {
        (void)f;
        lines = l;
        done = YES;
    }];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30.0];
    while (!done && [until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    XCTAssertTrue(done);
    return lines;
}

/// Reading a part of the image (Copy Text on a selection) reads only what's there, with its boxes
/// still in the whole image's pixels, where reading all of it puts them.
- (void)testAPartReadsOnlyThatPart {
    if (![STTextRecognizer isAvailable]) {
        NSLog(@"tesseract isn't installed: the sample isn't read");
        return;
    }
    NSArray<STRecognizedLine *> *all = [self linesOfSampleInRect:NSZeroRect];
    STRecognizedLine *security = nil;
    for (STRecognizedLine *line in all) {
        if ([line.text rangeOfString:@"Security"].location != NSNotFound) {
            security = line;
            break;
        }
    }
    XCTAssertNotNil(security, @"%@", STRecognizedText(all));
    NSRect part = NSInsetRect(security.bounds, -6.0, -6.0);
    NSArray<STRecognizedLine *> *lines = [self linesOfSampleInRect:part];
    XCTAssertTrue([STRecognizedText(lines) rangeOfString:@"Security"].location != NSNotFound, @"%@", STRecognizedText(lines));
    XCTAssertLessThan(lines.count, all.count, @"not the whole image");
    for (STRecognizedLine *line in lines) {
        for (STRecognizedWord *word in line.words) {
            XCTAssertTrue(NSPointInRect(NSMakePoint(NSMidX(word.bounds), NSMidY(word.bounds)), part),
                          @"%@ at %@ is outside %@", word.text, NSStringFromRect(word.bounds), NSStringFromRect(part));
        }
    }
    NSRect again = lines.firstObject.bounds;
    // Its middle: an engine may box a part's text a little looser than the whole image's.
    XCTAssertTrue(fabs(NSMidX(again) - NSMidX(security.bounds)) < 4.0 && fabs(NSMidY(again) - NSMidY(security.bounds)) < 4.0,
                  @"%@ is where %@ was", NSStringFromRect(again), NSStringFromRect(security.bounds));
}

- (void)testTesseractReadsTheSample {
    if (![STTextRecognizer isAvailable]) {
        NSLog(@"tesseract isn't installed: the sample isn't read");
        return;
    }
    NSString *sample = [self samplePath];
    __block NSArray<STRecognizedLine *> *lines = nil;
    __block NSString *failure = nil;
    __block BOOL done = NO;
    [STTextRecognizer recognizeTextInImageAtURL:[NSURL fileURLWithPath:sample]
                                           rect:NSZeroRect
                                     completion:^(NSArray<STRecognizedLine *> *l, NSString *f) {
        lines = l;
        failure = f;
        done = YES;
    }];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30.0];
    while (!done && [until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    XCTAssertTrue(done);
    XCTAssertNil(failure);
    NSString *text = STRecognizedText(lines);
    XCTAssertTrue([text rangeOfString:@"Security"].location != NSNotFound, @"%@", text);
    NSArray<NSValue *> *rects = STSensitiveTextRects(lines);
    XCTAssertEqual(rects.count, (NSUInteger)1, @"the sample's one email address");
    // It's on the Email row, right of its label, in the sample's top half.
    NSRect email = rects.firstObject.rectValue;
    XCTAssertTrue(NSMinX(email) > 300.0 && NSMaxY(email) < 260.0, @"%@", NSStringFromRect(email));
}

@end
