/*
 * STFontPicker.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import "STFontPicker.h"
#import "STFontFamilyList.h"
#import "STFloatingPopover.h"
#import "STThemeUtilities.h"
#import <objc/runtime.h>

/// GtkDropDown's metrics: 6pt around the contents, 38pt rows with 12pt at each side.
static const CGFloat STFontPickerPadding = 6.0;
static const CGFloat STFontPickerRowHeight = 38.0;
static const CGFloat STFontPickerHeadingHeight = 32.0;
static const CGFloat STFontPickerRowInset = 12.0;
static const CGFloat STFontPickerCheckWidth = 16.0;
static const CGFloat STFontPickerSearchHeight = 34.0;
static const NSSize STFontPickerSize = {300.0, 420.0};
/// The size families are drawn at in the list.
static const CGFloat STFontPickerFontSize = 13.0;
/// How many matches a search lists: enough to scroll through, few enough to draw at once.
static const NSUInteger STFontPickerSearchLimit = 300;

/// A row: a family, or a heading over the ones after it.
@interface STFontPickerRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *family;
@end

@implementation STFontPickerRow
+ (instancetype)rowWithTitle:(NSString *)title family:(nullable NSString *)family {
    STFontPickerRow *row = [[self alloc] init];
    row.title = title;
    row.family = family;
    return row;
}
- (BOOL)isHeading {
    return self.family == nil;
}
@end

/// Draws a row as GTK's list does: the family's name in its own face, 12pt in from the edge, a
/// check mark at the right of the current one; a heading small, bold and dim. The theme draws
/// the row's background and selection.
@interface STFontPickerCell : NSTextFieldCell
@property (nonatomic, assign) BOOL heading;
@property (nonatomic, assign) BOOL checked;
@property (nonatomic, strong, nullable) NSFont *rowFont;
@end

@implementation STFontPickerCell

- (id)copyWithZone:(NSZone *)zone {
    STFontPickerCell *copy = [super copyWithZone:zone];
    copy.heading = self.heading;
    copy.checked = self.checked;
    copy.rowFont = self.rowFont;
    return copy;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    [self drawInteriorWithFrame:cellFrame inView:controlView];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    NSRect textRect = NSInsetRect(cellFrame, STFontPickerRowInset, 0.0);
    if (self.checked) {
        textRect.size.width -= STFontPickerCheckWidth + 8.0;
    }
    NSColor *color = self.heading ? STThemeSecondaryTextColor() : [NSColor controlTextColor];
    NSFont *font = self.heading ? [NSFont boldSystemFontOfSize:11.0]
                                : (self.rowFont ?: [NSFont systemFontOfSize:STFontPickerFontSize]);
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attributes = @{NSFontAttributeName: font,
                                 NSForegroundColorAttributeName: color,
                                 NSParagraphStyleAttributeName: paragraph};
    NSString *title = self.stringValue ?: @"";
    CGFloat height = MIN(NSHeight(textRect), ceil([title sizeWithAttributes:attributes].height));
    // A heading sits at the bottom of its row, over the families it heads, as GTK's do.
    CGFloat y = self.heading
        ? ([controlView isFlipped] ? NSMaxY(textRect) - height - 4.0 : NSMinY(textRect) + 4.0)
        : NSMinY(textRect) + floor((NSHeight(textRect) - height) / 2.0);
    [title drawInRect:NSMakeRect(NSMinX(textRect), y, NSWidth(textRect), height) withAttributes:attributes];

    if (self.checked) {
        // object-select-symbolic: a check, 2pt wide with round ends, in a 16pt square.
        CGFloat x = NSMaxX(cellFrame) - STFontPickerRowInset - STFontPickerCheckWidth;
        CGFloat midY = NSMidY(cellFrame);
        CGFloat dir = [controlView isFlipped] ? 1.0 : -1.0;
        NSBezierPath *check = [NSBezierPath bezierPath];
        [check moveToPoint:NSMakePoint(x + 3.0, midY)];
        [check lineToPoint:NSMakePoint(x + 6.5, midY + 3.5 * dir)];
        [check lineToPoint:NSMakePoint(x + 13.0, midY - 3.5 * dir)];
        [check setLineWidth:2.0];
        [check setLineCapStyle:NSRoundLineCapStyle];
        [check setLineJoinStyle:NSRoundLineJoinStyle];
        [[NSColor controlTextColor] set];
        [check stroke];
    }
}

@end

@interface STFontPicker ()
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong, nullable) STFloatingPopover *popover;
@property (nonatomic, copy) NSArray<STFontPickerRow *> *rows;
@property (nonatomic, copy) NSString *search;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSFont *> *fontsByFamily;
@end

@implementation STFontPicker

- (instancetype)initWithFamilies:(STFontFamilyList *)families {
    self = [super init];
    if (self) {
        _families = families;
        _search = @"";
        _rows = @[];
        _fontsByFamily = [[NSMutableDictionary alloc] init];
        [self buildContent];
        [self rebuildRows];
    }
    return self;
}

- (void)setFamilies:(STFontFamilyList *)families {
    _families = families;
    [self rebuildRows];
}

- (void)buildContent {
    NSRect bounds = NSMakeRect(0.0, 0.0, STFontPickerSize.width, STFontPickerSize.height);
    self.contentView = [[NSView alloc] initWithFrame:bounds];

    CGFloat searchY = NSHeight(bounds) - STFontPickerPadding - STFontPickerSearchHeight;
    self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(STFontPickerPadding, searchY,
                                                                       NSWidth(bounds) - 2.0 * STFontPickerPadding,
                                                                       STFontPickerSearchHeight)];
    // As its text field delegate (AppKit types it as NSSearchFieldDelegate, which GNUstep lacks).
    [self.searchField setDelegate:(id)self];
    [self.searchField setPlaceholderString:@"Search…"];
    [[self.searchField cell] setPlaceholderString:@"Search…"];
    [self.searchField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [self.contentView addSubview:self.searchField];

    NSRect listFrame = NSMakeRect(STFontPickerPadding, STFontPickerPadding,
                                  NSWidth(bounds) - 2.0 * STFontPickerPadding,
                                  searchY - 2.0 * STFontPickerPadding);
    self.scrollView = [[NSScrollView alloc] initWithFrame:listFrame];
    [self.scrollView setHasVerticalScroller:YES];
    [self.scrollView setHasHorizontalScroller:NO];
    [self.scrollView setBorderType:NSNoBorder];
    [self.scrollView setDrawsBackground:NO];
    [self.scrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

    self.tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0.0, 0.0, NSWidth(listFrame), NSHeight(listFrame))];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"family"];
    [column setWidth:NSWidth(listFrame)];
    [column setResizingMask:NSTableColumnAutoresizingMask];
    [column setEditable:NO];
    [column setDataCell:[[STFontPickerCell alloc] initTextCell:@""]];
    [self.tableView addTableColumn:column];
    [self.tableView setHeaderView:nil];
    [self.tableView setRowHeight:STFontPickerRowHeight];
    [self.tableView setIntercellSpacing:NSMakeSize(0.0, 0.0)];
    [self.tableView setGridStyleMask:NSTableViewGridNone];
    // Libadwaita's list in a popover: the theme draws source-list tables that way.
    [self.tableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
    [self.tableView setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
    [self.tableView setAllowsEmptySelection:YES];
    [self.tableView setRefusesFirstResponder:YES];
    [self.tableView setDataSource:self];
    [self.tableView setDelegate:self];
    [self.tableView setTarget:self];
    [self.tableView setAction:@selector(rowClicked:)];
    [self.scrollView setDocumentView:self.tableView];
    [self.contentView addSubview:self.scrollView];
}

#pragma mark - Rows

- (NSString *)languageHeading {
    NSString *language = [STFontFamilyList userLanguage];
    NSString *name = language.length > 0
        ? [[NSLocale currentLocale] displayNameForKey:NSLocaleLanguageCode value:language] : nil;
    return name.length > 0 ? [name capitalizedString] : @"Your Language";
}

- (void)rebuildRows {
    NSMutableArray<STFontPickerRow *> *rows = [[NSMutableArray alloc] init];
    if (self.search.length > 0) {
        for (NSString *family in [self.families familiesMatching:self.search limit:STFontPickerSearchLimit]) {
            [rows addObject:[STFontPickerRow rowWithTitle:[STFontFamilyList displayNameForFamily:family] family:family]];
        }
    } else {
        NSArray<NSString *> *recent = self.families.recentFamilies;
        if (recent.count > 0) {
            [rows addObject:[STFontPickerRow rowWithTitle:@"Recent" family:nil]];
            for (NSString *family in recent) {
                [rows addObject:[STFontPickerRow rowWithTitle:[STFontFamilyList displayNameForFamily:family] family:family]];
            }
        }
        NSArray<NSString *> *listed = self.families.listedFamilies;
        if (listed.count > recent.count) {
            [rows addObject:[STFontPickerRow rowWithTitle:[self languageHeading] family:nil]];
            for (NSString *family in [listed subarrayWithRange:NSMakeRange(recent.count, listed.count - recent.count)]) {
                [rows addObject:[STFontPickerRow rowWithTitle:[STFontFamilyList displayNameForFamily:family] family:family]];
            }
        }
    }
    self.rows = rows;
    [self.tableView reloadData];
    [self.tableView deselectAll:nil];
}

- (NSArray<NSString *> *)shownRowTitles {
    NSMutableArray<NSString *> *titles = [[NSMutableArray alloc] init];
    for (STFontPickerRow *row in self.rows) {
        [titles addObject:[row isHeading] ? [@"# " stringByAppendingString:row.title] : row.title];
    }
    return titles;
}

- (NSInteger)rowOfFamily:(NSString *)family {
    for (NSUInteger index = 0; index < self.rows.count; index++) {
        if (![self.rows[index] isHeading] && [self.rows[index].family isEqualToString:family]) {
            return (NSInteger)index;
        }
    }
    return -1;
}

- (NSFont *)fontForFamily:(NSString *)family {
    NSFont *font = self.fontsByFamily[family];
    if (!font) {
        font = [[NSFontManager sharedFontManager] fontWithFamily:family traits:0 weight:5 size:STFontPickerFontSize]
            ?: [NSFont systemFontOfSize:STFontPickerFontSize];
        self.fontsByFamily[family] = font;
    }
    return font;
}

#pragma mark - Showing

- (void)showBelowView:(NSView *)view {
    if (!self.popover) {
        self.popover = [[STFloatingPopover alloc] initWithContentView:self.contentView];
        self.popover.contentSize = STFontPickerSize;
        self.popover.showsArrow = NO;
        __weak STFontPicker *weakSelf = self;
        self.popover.didCloseHandler = ^{
            STFontPicker *picker = weakSelf;
            [picker.delegate fontPickerDidClose:picker];
        };
    }
    [self.searchField setStringValue:@""];
    self.search = @"";
    [self rebuildRows];
    // STFloatingPopover names the edge its arrow is on: NSMaxYEdge opens below the view.
    [self.popover showRelativeToRect:view.bounds ofView:view preferredEdge:NSMaxYEdge];
    [[self.searchField window] makeFirstResponder:self.searchField];
    // The current family in view, checked (not selected: Return picks a match or the first row).
    NSInteger current = self.currentFamily ? [self rowOfFamily:self.currentFamily] : -1;
    if (current >= 0) {
        [self.tableView scrollRowToVisible:current];
    }
}

- (void)close {
    [self.popover close];
}

- (BOOL)isShown {
    return [self.popover isShown];
}

#pragma mark - Choosing

- (void)chooseRow:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= self.rows.count || [self.rows[(NSUInteger)row] isHeading]) {
        return;
    }
    NSString *family = self.rows[(NSUInteger)row].family;
    self.currentFamily = family;
    [self.delegate fontPicker:self didChooseFamily:family];
    [self close];
}

- (void)rowClicked:(id)sender {
    (void)sender;
    [self chooseRow:[self.tableView clickedRow]];
}

- (void)chooseSelectedOrFirst {
    NSInteger row = [self.tableView selectedRow];
    if (row < 0) {
        for (NSUInteger index = 0; index < self.rows.count; index++) {
            if (![self.rows[index] isHeading]) {
                row = (NSInteger)index;
                break;
            }
        }
    }
    [self chooseRow:row];
}

- (NSInteger)selectedRow {
    return [self.tableView selectedRow];
}

- (void)moveSelectionBy:(NSInteger)delta {
    NSInteger count = (NSInteger)self.rows.count;
    if (count == 0 || delta == 0) {
        return;
    }
    NSInteger row = [self.tableView selectedRow];
    if (row < 0) {
        row = delta > 0 ? -1 : count;
    }
    // Over the headings.
    do {
        row += delta > 0 ? 1 : -1;
    } while (row >= 0 && row < count && [self.rows[(NSUInteger)row] isHeading]);
    if (row < 0 || row >= count) {
        return;
    }
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [self.tableView scrollRowToVisible:row];
}

- (void)setSearchString:(NSString *)search {
    self.search = search ?: @"";
    [self rebuildRows];
}

#pragma mark - The search field

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.searchField) {
        [self setSearchString:[self.searchField stringValue]];
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    (void)textView;
    if (control != self.searchField) {
        return NO;
    }
    if (sel_isEqual(commandSelector, @selector(moveDown:))) {
        [self moveSelectionBy:1];
        return YES;
    }
    if (sel_isEqual(commandSelector, @selector(moveUp:))) {
        [self moveSelectionBy:-1];
        return YES;
    }
    if (sel_isEqual(commandSelector, @selector(insertNewline:))) {
        [self chooseSelectedOrFirst];
        return YES;
    }
    // Escape: GNUstep binds it to complete:, Cocoa sends cancelOperation:.
    if (sel_isEqual(commandSelector, @selector(cancelOperation:)) || sel_isEqual(commandSelector, @selector(complete:))) {
        [self close];
        return YES;
    }
    return NO;
}

#pragma mark - The table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.rows.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    (void)tableView;
    (void)column;
    return (row >= 0 && (NSUInteger)row < self.rows.count) ? self.rows[(NSUInteger)row].title : nil;
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    (void)tableView;
    (void)column;
    if (![cell isKindOfClass:[STFontPickerCell class]] || row < 0 || (NSUInteger)row >= self.rows.count) {
        return;
    }
    STFontPickerRow *item = self.rows[(NSUInteger)row];
    STFontPickerCell *fontCell = cell;
    fontCell.heading = [item isHeading];
    fontCell.rowFont = [item isHeading] ? nil : [self fontForFamily:item.family];
    fontCell.checked = ![item isHeading] && self.currentFamily && [item.family isEqualToString:self.currentFamily];
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row {
    (void)tableView;
    return row >= 0 && (NSUInteger)row < self.rows.count && [self.rows[(NSUInteger)row] isHeading];
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    return ![self tableView:tableView isGroupRow:row];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return [self tableView:tableView isGroupRow:row] ? STFontPickerHeadingHeight : STFontPickerRowHeight;
}

@end
