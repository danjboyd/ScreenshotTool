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

/// Dates in other forms, a date with a time, timestamps, versions and an ISBN have a phone number's
/// digits but aren't one: a reader's look-alikes ("/" read as 7) mustn't make them one either.
- (void)testDatesVersionsAndISBNsInEveryFormAreLeftAlone {
    NSArray<NSArray<NSString *> *> *cases = @[
        @[@"2026/10/22"], @[@"22.10.2026"], @[@"10/22/2026"], @[@"22/10/2026"], @[@"10-22-2026"], @[@"10/22/26"],
        @[@"2026", @"10", @"22"], @[@"22", @"10", @"2026"], @[@"2026-10-22", @"12:00"], @[@"2026-10-22", @"13:45:07"],
        @[@"(2026-10-22)"], @[@"20261022-134507"], @[@"10.0.19045.3803"], @[@"978-3-16-148410-0"],
    ];
    for (NSArray<NSString *> *words in cases) {
        NSMutableArray<NSString *> *line = [@[@"Invoice"] mutableCopy];
        [line addObjectsFromArray:words];
        [line addObjectsFromArray:@[@"was", @"paid"]];
        NSArray<NSValue *> *rects = STSensitiveTextRects(@[ [self lineWithWords:line y:0.0] ]);
        XCTAssertEqual(rects.count, (NSUInteger)0, @"%@ matched: %@", [words componentsJoinedByString:@" "], rects);
    }
}

/// A phone number beside a date is still found, without the date; numbers written with dots stay
/// phone numbers.
- (void)testAPhoneNumberBesideADateIsStillFound {
    NSArray<NSArray<NSString *> *> *phones = @[
        @[@"07700", @"900123"], @[@"01.23.45.67.89"], @[@"1.512.555.0199"], @[@"512.555.0177"], @[@"+33", @"1", @"23", @"45", @"67", @"89"],
    ];
    for (NSArray<NSString *> *phone in phones) {
        NSMutableArray<NSString *> *texts = [@[@"On", @"22.10.2026"] mutableCopy];
        [texts addObjectsFromArray:phone];
        [texts addObject:@"called"];
        NSArray<NSValue *> *rects = [self rectsForWords:texts height:10.0];
        XCTAssertEqual(rects.count, (NSUInteger)1, @"%@", [phone componentsJoinedByString:@" "]);
        NSRange covered = rects.count == 1 ? [self wordsCoveredBy:rects[0]] : NSMakeRange(0, 0);
        XCTAssertEqual(covered.location, (NSUInteger)2, @"Not the date, for %@", [phone componentsJoinedByString:@" "]);
        XCTAssertEqual(covered.length, phone.count, @"All of %@", [phone componentsJoinedByString:@" "]);
    }
}

/// The words of `texts` that `rectsForWords:` covers, as a set of indexes.
- (NSIndexSet *)coveredWordsOf:(NSArray<NSString *> *)texts {
    NSMutableIndexSet *covered = [NSMutableIndexSet indexSet];
    for (NSValue *rect in [self rectsForWords:texts height:10.0]) {
        [covered addIndexesInRange:[self wordsCoveredBy:rect]];
    }
    return covered;
}

/// A reader that drops a dot from a date before a phone number makes the pattern stop a group short:
/// the rest of the number is covered too, never left readable (Windows OCR, 2 of 12 sizes).
- (void)testAPhoneNumberIsNeverLeftHalfCovered {
    for (NSString *date in @[ @"22.102026", @"2210.2026" ]) {
        NSIndexSet *covered = [self coveredWordsOf:@[ @"On", date, @"07700", @"900123", @"called" ]];
        XCTAssertTrue([covered containsIndex:2] && [covered containsIndex:3], @"all of 07700 900123 after %@: %@", date, covered);
        XCTAssertFalse([covered containsIndex:0] || [covered containsIndex:4], @"not the words around it: %@", covered);
    }
}

/// The cover grows only over digit groups right beside the number: not over a time, a short count, a
/// word, a code running into letters ("4F"; "4B" reads as 48 through the look-alikes), or a number
/// further along the line.
- (void)testANumberDoesntGrowIntoUnrelatedText {
    NSArray<NSArray<NSString *> *> *lines = @[
        @[ @"Call", @"512-555-0199", @"at", @"14:32", @"on", @"3", @"floors" ],
        @[ @"At", @"14:32", @"+1", @"(512)", @"555-0134", @"and", @"all", @"3", @"regions" ],
        @[ @"Suite", @"4F", @"512.555.0177", @"4F", @"wing" ],
        @[ @"Call", @"07700", @"900123", @"or", @"ext", @"20456", @"later" ],
    ];
    NSArray<NSIndexSet *> *expected = @[
        [NSIndexSet indexSetWithIndex:1],
        [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(2, 3)],
        [NSIndexSet indexSetWithIndex:2],
        [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)],
    ];
    for (NSUInteger i = 0; i < lines.count; i++) {
        XCTAssertEqualObjects([self coveredWordsOf:lines[i]], expected[i], @"%@", [lines[i] componentsJoinedByString:@" "]);
    }
}

#pragma mark - Reading order in columns

/// A line of one word, `text`, over x..x+width at row `row` (24 px apart, 20 high).
static STRecognizedLine *STColumnLine(NSString *text, CGFloat x, CGFloat width, NSInteger row) {
    STRecognizedWord *word = [[STRecognizedWord alloc] initWithText:text bounds:NSMakeRect(x, 40.0 + row * 24.0, width, 20.0)];
    return [[STRecognizedLine alloc] initWithWords:@[ word ]];
}

/// The lines' texts, joined with spaces.
static NSString *STColumnOrder(NSArray<STRecognizedLine *> *lines) {
    return [[lines valueForKey:@"text"] componentsJoinedByString:@" "];
}

/// `columns` side by side (each `rows` lines of the given width), in rows as a reader returns them.
static NSArray<STRecognizedLine *> *STColumnsInRows(NSArray<NSString *> *columns, NSInteger rows, NSInteger firstRow, CGFloat width) {
    NSMutableArray<STRecognizedLine *> *lines = [NSMutableArray array];
    for (NSInteger row = 0; row < rows; row++) {
        for (NSUInteger c = 0; c < columns.count; c++) {
            [lines addObject:STColumnLine([NSString stringWithFormat:@"%@%ld", columns[c], (long)row + 1], 20.0 + c * (width + 60.0),
                                          width, firstRow + row)];
        }
    }
    return lines;
}

- (void)testTwoColumnsReadColumnByColumn {
    NSArray<STRecognizedLine *> *rows = STColumnsInRows(@[ @"L", @"R" ], 4, 0, 600.0);
    XCTAssertEqualObjects(STColumnOrder(rows), @"L1 R1 L2 R2 L3 R3 L4 R4");
    XCTAssertEqualObjects(STColumnOrder(STOrderLinesInColumns(rows)), @"L1 L2 L3 L4 R1 R2 R3 R4");
}

- (void)testThreeColumnsReadColumnByColumn {
    NSArray<STRecognizedLine *> *rows = STColumnsInRows(@[ @"A", @"B", @"C" ], 3, 0, 400.0);
    XCTAssertEqualObjects(STColumnOrder(STOrderLinesInColumns(rows)), @"A1 A2 A3 B1 B2 B3 C1 C2 C3");
}

/// A heading across the columns comes first, the columns under it after, and a second heading
/// starts a new run: its columns don't mix with those above.
- (void)testAHeadingAcrossColumnsStartsANewRun {
    NSMutableArray<STRecognizedLine *> *rows = [NSMutableArray array];
    [rows addObject:STColumnLine(@"Title", 20.0, 1260.0, 0)];
    [rows addObjectsFromArray:STColumnsInRows(@[ @"L", @"R" ], 3, 1, 600.0)];
    [rows addObject:STColumnLine(@"Section", 20.0, 1260.0, 4)];
    [rows addObjectsFromArray:STColumnsInRows(@[ @"l", @"r" ], 2, 5, 600.0)];
    XCTAssertEqualObjects(STColumnOrder(STOrderLinesInColumns(rows)), @"Title L1 L2 L3 R1 R2 R3 Section l1 l2 r1 r2");
}

/// A form's labels and values, or text in one column with a short last line, keep their rows.
- (void)testFormsAndOneColumnKeepTheirRows {
    NSMutableArray<STRecognizedLine *> *form = [NSMutableArray array];
    for (NSInteger row = 0; row < 4; row++) {
        [form addObject:STColumnLine([NSString stringWithFormat:@"Label%ld", (long)row], 20.0, 90.0, row)];
        [form addObject:STColumnLine([NSString stringWithFormat:@"Value%ld", (long)row], 300.0, 700.0, row)];
    }
    XCTAssertEqualObjects(STColumnOrder(STOrderLinesInColumns(form)), STColumnOrder(form));
    NSArray<STRecognizedLine *> *one = @[ STColumnLine(@"a", 20.0, 900.0, 0), STColumnLine(@"b", 20.0, 880.0, 1),
                                          STColumnLine(@"c", 60.0, 840.0, 2), STColumnLine(@"d", 20.0, 200.0, 3) ];
    XCTAssertEqualObjects(STColumnOrder(STOrderLinesInColumns(one)), @"a b c d");
}

/// A word or two a reader split off the end of a line follows that line, and doesn't keep its
/// columns from being read column by column.
- (void)testAStrayPieceFollowsItsLine {
    NSMutableArray<STRecognizedLine *> *rows = [STColumnsInRows(@[ @"L", @"R" ], 4, 0, 600.0) mutableCopy];
    [rows insertObject:STColumnLine(@"tail", 1340.0, 40.0, 1) atIndex:4];
    XCTAssertEqualObjects(STColumnOrder(STOrderLinesInColumns(rows)), @"L1 L2 L3 L4 R1 R2 tail R3 R4");
}

/// Two pieces of a line side by side on a row, which the tiles' edges split, are one line again.
- (void)testPiecesOfALineSplitByTilesAreJoined {
    STRecognizedWord *head = [[STRecognizedWord alloc] initWithText:@"all 3 regions" bounds:NSMakeRect(1900, 100, 650, 20)];
    STRecognizedWord *tail = [[STRecognizedWord alloc] initWithText:@"report healthy" bounds:NSMakeRect(2557, 100, 140, 20)];
    NSArray<NSValue *> *tiles = @[ [NSValue valueWithRect:NSMakeRect(0, 0, 2560, 720)], [NSValue valueWithRect:NSMakeRect(1280, 0, 2560, 720)] ];
    NSArray<STRecognizedLine *> *merged = STMergeTiledLines(@[ @[ [[STRecognizedLine alloc] initWithWords:@[ head ]] ],
                                                               @[ [[STRecognizedLine alloc] initWithWords:@[ tail ]] ] ],
                                                            tiles, NSMakeRect(0, 0, 3840, 720));
    XCTAssertEqual(merged.count, (NSUInteger)1);
    XCTAssertEqualObjects(merged.firstObject.text, @"all 3 regions report healthy");
}

/// A tile that read under half of what a neighbour read where they overlap is read again, shifted an
/// eighth of its width each way; tiles that agree aren't.
- (void)testAThinTileIsReadAgainShifted {
    NSArray<NSValue *> *tiles = @[ [NSValue valueWithRect:NSMakeRect(0, 0, 2560, 720)], [NSValue valueWithRect:NSMakeRect(1280, 0, 2560, 720)] ];
    NSMutableArray<STRecognizedLine *> *column = [NSMutableArray array];
    for (NSInteger row = 0; row < 6; row++) {
        [column addObject:STColumnLine(@"Meeting moved to room 4B bring the printed agenda", 1913.0, 600.0, row)];
    }
    NSArray<NSValue *> *retries = STVisionRetryTiles(tiles, @[ column, @[] ]);
    NSArray<NSValue *> *expected = @[ [NSValue valueWithRect:NSMakeRect(1600, 0, 2240, 720)], [NSValue valueWithRect:NSMakeRect(1280, 0, 2240, 720)] ];
    XCTAssertEqualObjects(retries, expected);
    XCTAssertEqual(STVisionRetryTiles(tiles, @[ column, column ]).count, (NSUInteger)0, @"tiles that agree");
    XCTAssertEqual(STVisionRetryTiles(tiles, @[ @[ STColumnLine(@"ok", 1913.0, 40.0, 0) ], @[] ]).count, (NSUInteger)0, @"too little to tell");
}

/// Tiles merged from a two-column page come back column by column.
- (void)testTiledColumnsMergeColumnByColumn {
    NSArray<STRecognizedLine *> *rows = STColumnsInRows(@[ @"L", @"R" ], 4, 0, 600.0);
    NSArray<NSValue *> *tiles = @[ [NSValue valueWithRect:NSMakeRect(0, 0, 700, 200)], [NSValue valueWithRect:NSMakeRect(600, 0, 800, 200)] ];
    NSMutableArray<STRecognizedLine *> *left = [NSMutableArray array], *right = [NSMutableArray array];
    for (STRecognizedLine *line in rows) {
        [([line.text hasPrefix:@"L"] ? left : right) addObject:line];
    }
    NSArray<STRecognizedLine *> *merged = STMergeTiledLines(@[ left, right ], tiles, NSMakeRect(0, 0, 1400, 200));
    XCTAssertEqualObjects(STColumnOrder(merged), @"L1 L2 L3 L4 R1 R2 R3 R4");
}

/// The redaction for one line of `words`, each 10 px wide and `height` high with a 4 px gap.
- (NSArray<NSValue *> *)rectsForWords:(NSArray<NSString *> *)texts height:(CGFloat)height {
    NSMutableArray<STRecognizedWord *> *words = [[NSMutableArray alloc] init];
    CGFloat x = 10.0;
    for (NSString *text in texts) {
        [words addObject:[[STRecognizedWord alloc] initWithText:text bounds:NSMakeRect(x, 0.0, 10.0, height)]];
        x += 14.0;
    }
    return STSensitiveTextRects(@[ [[STRecognizedLine alloc] initWithWords:words] ]);
}

/// The x-range of a redaction, in words of the line `rectsForWords:` laid out (word 0 starts at 10).
- (NSRange)wordsCoveredBy:(NSValue *)rect {
    NSRect r = rect.rectValue;
    NSUInteger first = (NSUInteger)lround((NSMinX(r) + 3.0 - 10.0) / 14.0);
    NSUInteger last = (NSUInteger)lround((NSMaxX(r) - 3.0 - 20.0) / 14.0);
    return NSMakeRange(first, last - first + 1);
}

/// International numbers: a single-digit area code after the country code, and longer groups.
- (void)testInternationalPhoneNumbers {
    NSArray *france = [self rectsForWords:@[@"Paris", @"+33", @"1", @"23", @"45", @"67", @"89", @"office"] height:12.0];
    XCTAssertEqual(france.count, (NSUInteger)1, @"%@", france);
    XCTAssertTrue(NSEqualRanges([self wordsCoveredBy:france.firstObject], NSMakeRange(1, 6)), @"%@", france);
    NSArray *berlin = [self rectsForWords:@[@"Berlin", @"+49", @"30", @"901820"] height:12.0];
    XCTAssertTrue(berlin.count == 1 && NSEqualRanges([self wordsCoveredBy:berlin.firstObject], NSMakeRange(1, 3)), @"%@", berlin);
    NSArray *mobile = [self rectsForWords:@[@"Mobile", @"07700", @"900123"] height:12.0];
    XCTAssertTrue(mobile.count == 1 && NSEqualRanges([self wordsCoveredBy:mobile.firstObject], NSMakeRange(1, 2)), @"%@", mobile);
}

/// A reader puts spaces into email addresses, after a dot or around the "@": the address is still
/// found, all of it.
- (void)testEmailsTheReaderSplitAreFound {
    NSArray<NSArray<NSString *> *> *cases = @[
        @[ @"Mail", @"jane.", @"doe@example.com", @"today" ],
        @[ @"Mail", @"Support@Example.", @"COM", @"today" ],
        @[ @"Mail", @"doe", @"@example.com", @"today" ],
        @[ @"Mail", @"doe@", @"example.com", @"today" ],
        @[ @"Mail", @"rachel.o'", @"neil@example.ie", @"today" ],
    ];
    for (NSArray<NSString *> *words in cases) {
        NSArray *rects = [self rectsForWords:words height:12.0];
        XCTAssertEqual(rects.count, (NSUInteger)1, @"%@: %@", words, rects);
        XCTAssertTrue(NSEqualRanges([self wordsCoveredBy:rects.firstObject], NSMakeRange(1, 2)), @"%@: %@", words, rects);
    }
}

/// Sentences aren't joined into addresses: a full stop, or an "@" alone, finds nothing.
- (void)testSentencesAreNotJoinedIntoEmails {
    NSArray *thanks = [self rectsForWords:@[@"Thanks.", @"See", @"you", @"at", @"example.com"] height:12.0];
    XCTAssertEqual(thanks.count, (NSUInteger)0, @"%@", thanks);
    NSArray *reply = [self rectsForWords:@[@"Reply", @"@", @"noon.", @"Bring", @"notes"] height:12.0];
    XCTAssertEqual(reply.count, (NSUInteger)0, @"%@", reply);
}

/// A digit the reader took for a letter ("/" for 7, "Ø" for 0, "6/" for 67) doesn't leave the rest of
/// the number unredacted; words that merely look like digits aren't numbers.
- (void)testMisreadDigitsInPhoneNumbers {
    NSArray *london = [self rectsForWords:@[@"Call", @"+44", @"20", @"/946", @"0958", @"now"] height:12.0];
    XCTAssertTrue(london.count == 1 && NSEqualRanges([self wordsCoveredBy:london.firstObject], NSMakeRange(1, 4)), @"%@", london);
    NSArray *austin = [self rectsForWords:@[@"Call", @"(512)", @"555", @"Ø123"] height:12.0];
    XCTAssertTrue(austin.count == 1 && NSEqualRanges([self wordsCoveredBy:austin.firstObject], NSMakeRange(1, 3)), @"%@", austin);
    NSArray *paris = [self rectsForWords:@[@"+33", @"1", @"23", @"45", @"6/", @"89"] height:12.0];
    XCTAssertTrue(paris.count == 1 && NSEqualRanges([self wordsCoveredBy:paris.firstObject], NSMakeRange(0, 6)), @"%@", paris);
    NSArray *lookalikes = [self rectsForWords:@[@"Room", @"4B;", @"Is", @"it", @"lO", @"or", @"Il?"] height:12.0];
    XCTAssertEqual(lookalikes.count, (NSUInteger)0, @"%@", lookalikes);
}

/// The padding grows with the text: 15% of its height, and never under 3 px.
- (void)testPaddingFollowsTheTextHeight {
    NSRect small = [self rectsForWords:@[@"alex@example.com"] height:12.0].firstObject.rectValue;
    XCTAssertTrue(NSEqualRects(small, NSMakeRect(7.0, -3.0, 16.0, 18.0)), @"%@", NSStringFromRect(small));
    NSRect large = [self rectsForWords:@[@"alex@example.com"] height:40.0].firstObject.rectValue;
    XCTAssertTrue(NSEqualRects(large, NSMakeRect(4.0, -6.0, 22.0, 52.0)), @"%@", NSStringFromRect(large));
}

/// A large image is read in tiles that overlap and cover it; a small one in one piece.
- (void)testTilesCoverALargeImage {
    NSArray<NSValue *> *small = STVisionTilesForRegion(NSMakeRect(0, 0, 1600, 900));
    XCTAssertEqual(small.count, (NSUInteger)1);
    NSRect region = NSMakeRect(0, 0, 3840, 2160);
    NSArray<NSValue *> *tiles = STVisionTilesForRegion(region);
    XCTAssertEqual(tiles.count, (NSUInteger)8, @"2 across, 4 down: %@", tiles);
    for (CGFloat y = 1; y < 2160; y += 37) {
        for (CGFloat x = 1; x < 3840; x += 53) {
            BOOL covered = NO;
            for (NSValue *tile in tiles) {
                covered = covered || NSPointInRect(NSMakePoint(x, y), tile.rectValue);
            }
            XCTAssertTrue(covered, @"%.0f,%.0f", x, y);
        }
    }
    for (NSValue *tile in tiles) {
        XCTAssertTrue(NSContainsRect(region, tile.rectValue), @"%@", tile);
        XCTAssertLessThanOrEqual(NSWidth(tile.rectValue), 2560.0);
    }
    // A part of the image is tiled within the part.
    NSRect part = NSMakeRect(500, 300, 2000, 400);
    for (NSValue *tile in STVisionTilesForRegion(part)) {
        XCTAssertTrue(NSContainsRect(part, tile.rectValue), @"%@", tile);
    }
}

/// Two tiles' readings of one line longer than either: the word cut by a tile's edge is dropped, the
/// word both read is kept once, and the line is joined up, in order.
- (void)testTiledReadingsJoinIntoOneLine {
    NSRect region = NSMakeRect(0, 0, 3000, 100);
    NSArray<NSValue *> *tiles = @[ [NSValue valueWithRect:NSMakeRect(0, 0, 2000, 100)], [NSValue valueWithRect:NSMakeRect(1000, 0, 2000, 100)] ];
    STRecognizedWord *(^word)(NSString *, CGFloat) = ^STRecognizedWord *(NSString *text, CGFloat x) {
        return [[STRecognizedWord alloc] initWithText:text bounds:NSMakeRect(x, 40, 300, 20)];
    };
    // The left tile reads "one two thr" (cut at its right edge, 2000); the right "ee four five" (cut at 1000).
    STRecognizedLine *left = [[STRecognizedLine alloc] initWithWords:@[ word(@"one", 100), word(@"two", 1200), word(@"thr", 1700) ]];
    STRecognizedWord *cutRight = [[STRecognizedWord alloc] initWithText:@"thr" bounds:NSMakeRect(1700, 40, 300, 20)];
    left = [[STRecognizedLine alloc] initWithWords:@[ word(@"one", 100), word(@"two", 1200), cutRight ]];
    STRecognizedWord *cutLeft = [[STRecognizedWord alloc] initWithText:@"o" bounds:NSMakeRect(1000, 40, 150, 20)];
    STRecognizedLine *right = [[STRecognizedLine alloc] initWithWords:@[ cutLeft, word(@"two", 1201), word(@"three", 1700), word(@"four", 2400) ]];
    NSArray<STRecognizedLine *> *lines = STMergeTiledLines(@[ @[ left ], @[ right ] ], tiles, region);
    XCTAssertEqual(lines.count, (NSUInteger)1, @"%@", STRecognizedText(lines));
    XCTAssertEqualObjects(lines.firstObject.text, @"one two three four");
    // Two lines, one under the other, come out top first, whatever order a tile read them in.
    NSArray<NSValue *> *rows = @[ [NSValue valueWithRect:NSMakeRect(0, 0, 3000, 720)], [NSValue valueWithRect:NSMakeRect(0, 480, 3000, 720)] ];
    STRecognizedLine *upper = [[STRecognizedLine alloc] initWithWords:@[ [[STRecognizedWord alloc] initWithText:@"upper" bounds:NSMakeRect(10, 600, 200, 20)] ]];
    STRecognizedLine *lower = [[STRecognizedLine alloc] initWithWords:@[ [[STRecognizedWord alloc] initWithText:@"lower" bounds:NSMakeRect(10, 900, 200, 20)] ]];
    // The second tile read both, the lower first.
    NSArray<STRecognizedLine *> *ordered = STMergeTiledLines(@[ @[], @[ lower, upper ] ], rows, NSMakeRect(0, 0, 3000, 1200));
    XCTAssertEqualObjects(STRecognizedText(ordered), @"upper\nlower");
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

#if !defined(GNUSTEP)
/// macOS reads the app's image in memory (perf, 0.4.0): the same lines and boxes as from its file,
/// for the whole image and for a part.
- (void)testAnImageInMemoryReadsAsItsFileDoes {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:[self samplePath]];
    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    XCTAssertTrue(cgImage != NULL);
    NSSize size = NSMakeSize(CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
    for (NSValue *rectValue in @[ [NSValue valueWithRect:NSZeroRect],
                                  [NSValue valueWithRect:NSMakeRect(0.0, 0.0, size.width, floor(size.height / 2.0))] ]) {
        NSRect rect = rectValue.rectValue;
        __block NSArray<STRecognizedLine *> *lines = nil;
        __block BOOL done = NO;
        [STTextRecognizer recognizeTextInCGImage:cgImage rect:rect completion:^(NSArray<STRecognizedLine *> *l, NSString *f) {
            (void)f;
            lines = l;
            done = YES;
        }];
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30.0];
        while (!done && [until timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        NSArray<STRecognizedLine *> *fromFile = [self linesOfSampleInRect:rect];
        XCTAssertGreaterThan(lines.count, (NSUInteger)0);
        XCTAssertEqualObjects(STRecognizedText(lines), STRecognizedText(fromFile), @"rect %@", NSStringFromRect(rect));
        XCTAssertEqual(lines.count, fromFile.count);
        for (NSUInteger i = 0; i < MIN(lines.count, fromFile.count); i++) {
            XCTAssertTrue(NSEqualRects(lines[i].bounds, fromFile[i].bounds), @"line %lu", (unsigned long)i);
        }
    }
}
#endif

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
