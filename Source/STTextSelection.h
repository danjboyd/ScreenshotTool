#import <Foundation/Foundation.h>
#import "STTextRecognizer.h"

NS_ASSUME_NONNULL_BEGIN

/// Selecting recognised words in reading order, as a text view selects characters (#330).
/// Foundation only: points and rects are in the image's pixels, top-left origin, as
/// STRecognizedWord's boxes are. Words are addressed by a flat reading-order index: line by line,
/// word by word. The lines never change; make a new selection for a new OCR result.
@interface STTextSelection : NSObject

- (instancetype)initWithLines:(NSArray<STRecognizedLine *> *)lines;

@property (nonatomic, copy, readonly) NSArray<STRecognizedLine *> *lines;

@property (nonatomic, readonly) NSUInteger wordCount;
/// NSZeroRect out of range.
- (NSRect)boundsOfWordAtIndex:(NSUInteger)index;
/// The index in `lines` of the line the word is on; NSNotFound out of range.
- (NSUInteger)lineIndexOfWordAtIndex:(NSUInteger)index;

/// The word whose box, grown by `slop`, holds `point` (the nearest box if several do), or else the
/// nearest word on the line whose band (its bounds grown by `slop` vertically) holds the point;
/// NSNotFound when there's none.
- (NSUInteger)wordIndexAtImagePoint:(NSPoint)point slop:(CGFloat)slop;

/// The selection, as a reading-order range of word indexes; length 0 for none. Setting a range
/// that doesn't fit clears it.
@property (nonatomic) NSRange selectedRange;
/// Where the selection started: the word a drag began on, the first of a word, line or rect
/// selection, 0 for all. NSNotFound with no selection.
@property (nonatomic, readonly) NSUInteger anchorIndex;

/// From the word at one point to the word at another, in either direction (a drag). A point on
/// no word, such as the margin left of a paragraph or below it, snaps to the nearest word.
- (void)selectFromImagePoint:(NSPoint)start toImagePoint:(NSPoint)end;
/// From the anchor to the word at `point`, snapping as a drag does (Shift-click). With no anchor,
/// selects the word at `point`.
- (void)extendSelectionToImagePoint:(NSPoint)point;
- (void)selectWordAtIndex:(NSUInteger)index;
- (void)selectLineOfWordAtIndex:(NSUInteger)index;
- (void)selectAll;
/// The words whose middle is in `rect` (a canvas selection on entry), and any between them in
/// reading order; none clears the selection.
- (void)selectWordsInImageRect:(NSRect)rect;
- (void)clearSelection;

/// Words joined with spaces, lines with "\n", as STRecognizedText joins them: all of it selected
/// gives STRecognizedText(lines).
@property (nonatomic, copy, readonly) NSString *selectedText;
/// One rect per line the selection touches, in reading order: the union of its selected words.
@property (nonatomic, copy, readonly) NSArray<NSValue *> *selectedRects;

@end

NS_ASSUME_NONNULL_END
