/*
 * STFontPicker.h
 * Copyright (C) 2026 Daniel Boyd
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class STFontFamilyList;
@class STFontPicker;

@protocol STFontPickerDelegate <NSObject>
/// A family was chosen: clicked, or Return on the selected or first match.
- (void)fontPicker:(STFontPicker *)picker didChooseFamily:(NSString *)family;
/// The picker closed, with or without a choice.
- (void)fontPickerDidClose:(STFontPicker *)picker;
@end

/// The text bar's font list, as GTK 4's GtkDropDown with search: a popover below the font button
/// with a search field and a list of families, each in its own face, the current one checked.
/// Without a search, recent families and those for the user's language, under headings; with
/// one, every installed family whose name contains it. Built from standard controls (a search
/// field and a source-list table view in the app's popover), so the theme draws them.
@interface STFontPicker : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>

- (instancetype)initWithFamilies:(STFontFamilyList *)families;

@property (nonatomic, strong) STFontFamilyList *families;
@property (nonatomic, weak, nullable) id<STFontPickerDelegate> delegate;
/// The family shown checked.
@property (nonatomic, copy, nullable) NSString *currentFamily;

/// Shows the picker below `view` (the font button), with the search field taking the keyboard.
- (void)showBelowView:(NSView *)view;
- (void)close;
- (BOOL)isShown;

/// What the list shows, for tests: a family's name, or a heading as "# Heading".
- (NSArray<NSString *> *)shownRowTitles;
/// Filters as typing in the search field does.
- (void)setSearchString:(NSString *)search;
/// Return in the search field: the selected family, or the first one shown.
- (void)chooseSelectedOrFirst;
/// The row selected for Return (moved by Up and Down in the search field), or -1.
- (NSInteger)selectedRow;
- (void)moveSelectionBy:(NSInteger)delta;

@end

NS_ASSUME_NONNULL_END
