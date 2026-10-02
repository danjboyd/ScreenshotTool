/*
 * STTextOptionsBar.h
 * Copyright (C) 2026 Daniel Boyd
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import <AppKit/AppKit.h>
#import "MarkupText.h"
#import "ScreenshotToolSettings.h"

NS_ASSUME_NONNULL_BEGIN

@class STTextOptionsBar;

@protocol STTextOptionsBarDelegate <NSObject>
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickColor:(NSColor *)color;
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickSizePreset:(STTextSizePreset)preset;
- (void)textOptionsBar:(STTextOptionsBar *)bar didStepSizeBy:(CGFloat)delta;
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickStyle:(MarkupTextStyle)style;
- (void)textOptionsBarDidTogglePointer:(STTextOptionsBar *)bar;
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickFontFamily:(NSString *)family;
- (void)textOptionsBarDidToggleBold:(STTextOptionsBar *)bar;
- (void)textOptionsBarDidToggleItalic:(STTextOptionsBar *)bar;
- (void)textOptionsBar:(STTextOptionsBar *)bar didPickAlignment:(NSTextAlignment)alignment;
@end

/// The strip of text controls shown over the canvas while a text box is being edited (#34).
/// Its controls never take first responder, so the caret stays in the text box.
@interface STTextOptionsBar : NSView

@property (nonatomic, weak, nullable) id<STTextOptionsBarDelegate> delegate;

+ (CGFloat)preferredHeight;

/// Shows the box's current values. Bold and italic are enabled only when the font has those faces.
- (void)updateWithFont:(NSFont *)font
                 color:(NSColor *)color
                 style:(MarkupTextStyle)style
            sizePreset:(STTextSizePreset)sizePreset
             alignment:(NSTextAlignment)alignment
         boldAvailable:(BOOL)boldAvailable
       italicAvailable:(BOOL)italicAvailable;

/// Shows whether the label being edited has a callout pointer.
- (void)setPointerOn:(BOOL)on available:(BOOL)available;

/// Controls that are currently laid out (the rest didn't fit); for tests.
- (NSArray<NSView *> *)visibleControls;

@end

NS_ASSUME_NONNULL_END
