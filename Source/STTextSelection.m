#import "STTextSelection.h"

/// How far `point` is from `rect`: 0 inside it.
static CGFloat STDistanceToRect(NSPoint point, NSRect rect) {
    CGFloat dx = MAX(MAX(NSMinX(rect) - point.x, point.x - NSMaxX(rect)), 0.0);
    CGFloat dy = MAX(MAX(NSMinY(rect) - point.y, point.y - NSMaxY(rect)), 0.0);
    return (CGFloat)sqrt(dx * dx + dy * dy);
}

/// How far `value` is from [min, max]: 0 inside it.
static CGFloat STDistanceToSpan(CGFloat value, CGFloat min, CGFloat max) {
    return MAX(MAX(min - value, value - max), 0.0);
}

@implementation STTextSelection {
    /// Per word, in reading order: its box and its line's index in `lines`.
    NSArray<NSValue *> *_wordBounds;
    NSArray<NSNumber *> *_wordLines;
    NSArray<NSString *> *_wordTexts;
    /// Per line in `lines`: the range of its words.
    NSArray<NSValue *> *_lineWordRanges;
}

- (instancetype)initWithLines:(NSArray<STRecognizedLine *> *)lines {
    self = [super init];
    if (self) {
        _lines = [lines copy];
        NSMutableArray<NSValue *> *bounds = [[NSMutableArray alloc] init];
        NSMutableArray<NSNumber *> *wordLines = [[NSMutableArray alloc] init];
        NSMutableArray<NSString *> *texts = [[NSMutableArray alloc] init];
        NSMutableArray<NSValue *> *lineRanges = [[NSMutableArray alloc] initWithCapacity:_lines.count];
        [_lines enumerateObjectsUsingBlock:^(STRecognizedLine *line, NSUInteger lineIndex, BOOL *stop) {
            (void)stop;
            [lineRanges addObject:[NSValue valueWithRange:NSMakeRange(bounds.count, line.words.count)]];
            for (STRecognizedWord *word in line.words) {
                [bounds addObject:[NSValue valueWithRect:word.bounds]];
                [wordLines addObject:@(lineIndex)];
                [texts addObject:word.text];
            }
        }];
        _wordBounds = [bounds copy];
        _wordLines = [wordLines copy];
        _wordTexts = [texts copy];
        _lineWordRanges = [lineRanges copy];
        _selectedRange = NSMakeRange(0, 0);
        _anchorIndex = NSNotFound;
    }
    return self;
}

- (NSUInteger)wordCount {
    return _wordBounds.count;
}

- (NSRect)boundsOfWordAtIndex:(NSUInteger)index {
    return index < _wordBounds.count ? _wordBounds[index].rectValue : NSZeroRect;
}

- (NSUInteger)lineIndexOfWordAtIndex:(NSUInteger)index {
    return index < _wordLines.count ? _wordLines[index].unsignedIntegerValue : NSNotFound;
}

#pragma mark - Hit testing

- (NSUInteger)wordIndexAtImagePoint:(NSPoint)point slop:(CGFloat)slop {
    NSUInteger best = NSNotFound;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (NSUInteger index = 0; index < _wordBounds.count; index++) {
        NSRect bounds = _wordBounds[index].rectValue;
        if (!NSPointInRect(point, NSInsetRect(bounds, -slop, -slop))) {
            continue;
        }
        CGFloat distance = STDistanceToRect(point, bounds);
        if (distance < bestDistance) {
            best = index;
            bestDistance = distance;
        }
    }
    if (best != NSNotFound) {
        return best;
    }
    // Between words, or just off one: the nearest word on the line whose band holds the point.
    NSUInteger line = [self lineNearestToY:point.y within:slop];
    return line == NSNotFound ? NSNotFound : [self wordOnLine:line nearestToX:point.x];
}

/// The line with words whose bounds, grown by `slop` vertically (CGFLOAT_MAX: any line), are
/// nearest `y`; the line whose middle is nearer wins when several hold it.
- (NSUInteger)lineNearestToY:(CGFloat)y within:(CGFloat)slop {
    NSUInteger best = NSNotFound;
    CGFloat bestDistance = CGFLOAT_MAX;
    CGFloat bestMiddle = CGFLOAT_MAX;
    for (NSUInteger lineIndex = 0; lineIndex < _lines.count; lineIndex++) {
        if (_lineWordRanges[lineIndex].rangeValue.length == 0) {
            continue;
        }
        NSRect bounds = _lines[lineIndex].bounds;
        CGFloat distance = STDistanceToSpan(y, NSMinY(bounds), NSMaxY(bounds));
        if (distance > slop) {
            continue;
        }
        CGFloat middle = (CGFloat)fabs(y - NSMidY(bounds));
        if (distance < bestDistance || (distance == bestDistance && middle < bestMiddle)) {
            best = lineIndex;
            bestDistance = distance;
            bestMiddle = middle;
        }
    }
    return best;
}

- (NSUInteger)wordOnLine:(NSUInteger)lineIndex nearestToX:(CGFloat)x {
    NSRange words = _lineWordRanges[lineIndex].rangeValue;
    NSUInteger best = NSNotFound;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (NSUInteger index = words.location; index < NSMaxRange(words); index++) {
        NSRect bounds = _wordBounds[index].rectValue;
        CGFloat distance = STDistanceToSpan(x, NSMinX(bounds), NSMaxX(bounds));
        if (distance < bestDistance) {
            best = index;
            bestDistance = distance;
        }
    }
    return best;
}

/// The word at `point`, or the nearest one when it's on none: on the nearest line, the nearest
/// word across, so a point left of a line gives its first word and one below the text the last
/// line's. NSNotFound only with no words.
- (NSUInteger)snappedWordIndexAtImagePoint:(NSPoint)point {
    NSUInteger index = [self wordIndexAtImagePoint:point slop:0.0];
    if (index != NSNotFound) {
        return index;
    }
    NSUInteger line = [self lineNearestToY:point.y within:CGFLOAT_MAX];
    return line == NSNotFound ? NSNotFound : [self wordOnLine:line nearestToX:point.x];
}

#pragma mark - Selecting

- (void)setSelectedRange:(NSRange)range {
    if (range.length == 0 || range.location >= _wordBounds.count ||
        range.length > _wordBounds.count - range.location) {
        _selectedRange = NSMakeRange(0, 0);
        _anchorIndex = NSNotFound;
        return;
    }
    _selectedRange = range;
    _anchorIndex = range.location;
}

/// Selects from `anchor` to `focus`, in whichever order they come, keeping `anchor`.
- (void)selectFromIndex:(NSUInteger)anchor toIndex:(NSUInteger)focus {
    if (anchor == NSNotFound || focus == NSNotFound) {
        [self clearSelection];
        return;
    }
    NSUInteger first = MIN(anchor, focus);
    _selectedRange = NSMakeRange(first, MAX(anchor, focus) - first + 1);
    _anchorIndex = anchor;
}

- (void)selectFromImagePoint:(NSPoint)start toImagePoint:(NSPoint)end {
    [self selectFromIndex:[self snappedWordIndexAtImagePoint:start] toIndex:[self snappedWordIndexAtImagePoint:end]];
}

- (void)extendSelectionToImagePoint:(NSPoint)point {
    NSUInteger focus = [self snappedWordIndexAtImagePoint:point];
    [self selectFromIndex:(_anchorIndex != NSNotFound ? _anchorIndex : focus) toIndex:focus];
}

- (void)selectWordAtIndex:(NSUInteger)index {
    if (index >= _wordBounds.count) {
        [self clearSelection];
        return;
    }
    [self selectFromIndex:index toIndex:index];
}

- (void)selectLineOfWordAtIndex:(NSUInteger)index {
    NSUInteger line = [self lineIndexOfWordAtIndex:index];
    if (line == NSNotFound) {
        [self clearSelection];
        return;
    }
    NSRange words = _lineWordRanges[line].rangeValue;
    [self selectFromIndex:words.location toIndex:NSMaxRange(words) - 1];
}

- (void)selectAll {
    if (_wordBounds.count == 0) {
        [self clearSelection];
        return;
    }
    [self selectFromIndex:0 toIndex:_wordBounds.count - 1];
}

- (void)selectWordsInImageRect:(NSRect)rect {
    NSUInteger first = NSNotFound;
    NSUInteger last = NSNotFound;
    for (NSUInteger index = 0; index < _wordBounds.count; index++) {
        NSRect bounds = _wordBounds[index].rectValue;
        if (NSPointInRect(NSMakePoint(NSMidX(bounds), NSMidY(bounds)), rect)) {
            if (first == NSNotFound) {
                first = index;
            }
            last = index;
        }
    }
    [self selectFromIndex:first toIndex:last];
}

- (void)clearSelection {
    _selectedRange = NSMakeRange(0, 0);
    _anchorIndex = NSNotFound;
}

#pragma mark - What's selected

/// Calls `block` once per line the selection touches, with that line's selected words.
- (void)enumerateSelectedLineRuns:(void (^)(NSUInteger lineIndex, NSRange words))block {
    if (_selectedRange.length == 0) {
        return;
    }
    NSUInteger index = _selectedRange.location;
    while (index < NSMaxRange(_selectedRange)) {
        NSUInteger line = _wordLines[index].unsignedIntegerValue;
        NSUInteger end = MIN(NSMaxRange(_lineWordRanges[line].rangeValue), NSMaxRange(_selectedRange));
        block(line, NSMakeRange(index, end - index));
        index = end;
    }
}

- (NSString *)selectedText {
    NSMutableArray<NSString *> *lines = [[NSMutableArray alloc] init];
    [self enumerateSelectedLineRuns:^(NSUInteger lineIndex, NSRange words) {
        (void)lineIndex;
        [lines addObject:[[self->_wordTexts subarrayWithRange:words] componentsJoinedByString:@" "]];
    }];
    return [lines componentsJoinedByString:@"\n"];
}

- (NSArray<NSValue *> *)selectedRects {
    NSMutableArray<NSValue *> *rects = [[NSMutableArray alloc] init];
    [self enumerateSelectedLineRuns:^(NSUInteger lineIndex, NSRange words) {
        (void)lineIndex;
        NSRect run = NSZeroRect;
        for (NSUInteger index = words.location; index < NSMaxRange(words); index++) {
            NSRect bounds = self->_wordBounds[index].rectValue;
            run = NSIsEmptyRect(run) ? bounds : NSUnionRect(run, bounds);
        }
        [rects addObject:[NSValue valueWithRect:run]];
    }];
    return rects;
}

@end
