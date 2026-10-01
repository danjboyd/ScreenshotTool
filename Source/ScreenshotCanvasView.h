/*
 * ScreenshotCanvasView.h
 * Copyright (C) 2025 Daniel Boyd
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA.
 */

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class MarkupStroke;
@class MarkupText;

typedef NS_ENUM(NSInteger, ScreenshotCanvasTool) {
    ScreenshotCanvasToolHighlighter = 0,
    ScreenshotCanvasToolPen = 1,
    ScreenshotCanvasToolEraser = 2,
    ScreenshotCanvasToolText = 3,
    ScreenshotCanvasToolSelect = 4
};

@interface ScreenshotCanvasView : NSView

@property (nonatomic, strong, nullable) NSImage *image;
@property (nonatomic, assign) ScreenshotCanvasTool activeTool;
@property (nonatomic, strong) NSColor *penColor;
@property (nonatomic, strong) NSColor *highlighterColor;
@property (nonatomic, strong) NSColor *textColor;
@property (nonatomic, assign) CGFloat penLineWidth;
@property (nonatomic, assign) CGFloat highlighterLineWidth;
@property (nonatomic, strong) NSFont *textFont;
@property (nonatomic, assign) CGFloat zoomScale;
@property (nonatomic, assign, getter=isFitToWindow) BOOL fitToWindow;
@property (nonatomic, weak, nullable) NSScrollView *hostScrollView;

- (void)loadImage:(nullable NSImage *)image;
- (void)updateForEnclosingBoundsChange;
- (nullable NSImage *)flattenedImage;
- (nullable NSImage *)flattenedImageForSelection;
- (BOOL)hasImage;
- (BOOL)hasSelection;
- (void)clearMarkup;
- (void)clearSelection;
- (void)refreshCursor;
- (BOOL)cropToActiveSelection;

@end

/// Clip view for the canvas scroll view: centres an image smaller than the viewport on a
/// contrasting backdrop and outlines it, so the image edge stays visible on any screenshot.
@interface STCanvasClipView : NSClipView
@end

NS_ASSUME_NONNULL_END
#import <AppKit/AppKit.h>

extern NSString * const _Nonnull ScreenshotCanvasViewDidRestoreStateNotification;
