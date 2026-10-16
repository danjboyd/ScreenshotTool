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
#import "MarkupText.h"
#import "ScreenshotToolSettings.h"
#import "STCanvasContextMenu.h"

NS_ASSUME_NONNULL_BEGIN

@class MarkupStroke;
@class MarkupText;

typedef NS_ENUM(NSInteger, ScreenshotCanvasTool) {
    ScreenshotCanvasToolHighlighter = 0,
    ScreenshotCanvasToolPen = 1,
    ScreenshotCanvasToolEraser = 2,
    ScreenshotCanvasToolText = 3,
    ScreenshotCanvasToolSelect = 4,
    /// Straight arrows (#33); shares the pen's colour and width.
    ScreenshotCanvasToolArrow = 5,
    /// Rectangles' outlines (v0.2.0, #221); shares the pen's colour and width.
    ScreenshotCanvasToolRectangle = 6,
    /// Numbered steps, 1, 2, 3… (v0.2.0, #221); in the pen's colour, sized by its width.
    ScreenshotCanvasToolStep = 7,
    /// Redactions: the image pixelated in a rect (v0.2.0, #221).
    ScreenshotCanvasToolRedact = 8
};

/// A view next to the canvas whose controls can take the keyboard while a text box is being edited
/// (the text bar's font field, #103). Moving focus into it doesn't finish the text box.
@protocol STTextEditingCompanion <NSObject>
/// YES while keyboard focus is moving from the text box into the companion.
- (BOOL)isTakingTextFocus;
@end

@interface ScreenshotCanvasView : NSView <STCanvasContextCommands>

@property (nonatomic, strong, nullable) NSImage *image;
@property (nonatomic, assign) ScreenshotCanvasTool activeTool;
@property (nonatomic, strong) NSColor *penColor;
@property (nonatomic, strong) NSColor *highlighterColor;
@property (nonatomic, strong) NSColor *textColor;
@property (nonatomic, assign) CGFloat penLineWidth;
@property (nonatomic, assign) CGFloat highlighterLineWidth;
@property (nonatomic, strong) NSFont *textFont;
/// Style for new text annotations; changing it restyles the box being edited.
@property (nonatomic, assign) MarkupTextStyle textStyle;
/// Size preset for new text; anything but Exact sizes the font from the image (#27).
@property (nonatomic, assign) STTextSizePreset textSizePreset;
/// Alignment for new text; changing it realigns the box being edited (#31).
@property (nonatomic, assign) NSTextAlignment textAlignment;
/// While YES, Fit to Window doesn't rescale when the viewport changes (the text toolbar row
/// appearing shouldn't shrink the image mid-edit).
@property (nonatomic, assign) BOOL suspendsFitUpdates;
/// The text annotation being edited, or nil.
- (nullable MarkupText *)activeTextEntry;
/// The box being edited, in this view's coordinates, or NSZeroRect.
- (NSRect)activeTextRectInView;
/// Adds or removes a callout pointer on the label being edited; NO when nothing is being edited.
- (BOOL)toggleActiveTextPointer;
/// The image (unflattened) and its annotations as a ScreenshotTool project file (#32).
- (nullable NSData *)projectDataWithError:(NSError **)error;
/// Replaces the canvas with a project's image and editable annotations.
- (BOOL)loadProjectData:(NSData *)data error:(NSError **)error;
/// A snapshot of the annotations and image size, compared to tell whether there are unsaved changes.
- (NSData *)annotationFingerprint;
/// textFont at the preset's size for the current image, or textFont itself for Exact.
- (NSFont *)effectiveTextFont;
/// The undo history for typing in the open text box, or nil when no box is being edited.
- (nullable NSUndoManager *)activeTextUndoManager;
/// View points per image pixel.
@property (nonatomic, assign) CGFloat zoomScale;
/// The zoom the user sees: screen pixels per image pixel, so 1.0 is a screenshot's actual size.
/// It's zoomScale on macOS and at a Windows display scale of 100%.
@property (nonatomic, assign) CGFloat displayZoomScale;
/// Screen pixels per view point: the Windows display scale, 1.0 elsewhere.
@property (nonatomic, readonly) CGFloat screenPixelsPerPoint;
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

/// Asked for the right-click menu (-menuForEvent:) once the canvas has worked out what was clicked.
@property (nonatomic, copy, nullable) NSMenu * _Nullable (^contextMenuProvider)(STCanvasContextKind kind);
/// What a right-click at this point is about. Like a left click with the select tool, it selects
/// the annotation under the pointer first (switching to the select tool), unless the point is in
/// the region selection, which keeps it; a point outside the region selection clears it.
- (STCanvasContextKind)prepareContextMenuAtViewPoint:(NSPoint)viewPoint;
/// YES when the one annotation selected is a text label.
- (BOOL)hasSingleTextSelection;

/// See STTextEditingCompanion.
@property (nonatomic, weak, nullable) id<STTextEditingCompanion> textEditingCompanion;
/// Gives the keyboard back to the text box being edited, after a companion had it. NO if none is.
- (BOOL)focusActiveTextView;
/// Scrolls so the text box being edited is on screen, if one is.
- (void)scrollActiveTextToVisible;

@end

/// Clip view for the canvas scroll view: centres an image smaller than the viewport on a
/// contrasting backdrop and outlines it, so the image edge stays visible on any screenshot.
@interface STCanvasClipView : NSClipView
@end

/// The least space between the image and the stage's edge, in points.
extern const CGFloat STCanvasStageMargin;

/// The canvas scroll view's document view: the canvas centred on a stage at least as big as the
/// viewport, with a margin round the image, a dot grid, a soft shadow and a hairline (v0.2.0,
/// #221). Display only: exports and Copy come from the canvas, which draws as before.
@interface STCanvasStageView : NSView
@property (nonatomic, strong, readonly) ScreenshotCanvasView *canvasView;
- (instancetype)initWithCanvasView:(ScreenshotCanvasView *)canvasView;
/// Sizes the stage to the viewport and the canvas, and centres the canvas on it.
- (void)layoutCanvas;
/// The canvas's frame, which the stage draws round.
@property (nonatomic, readonly) NSRect imageFrame;
@end

NS_ASSUME_NONNULL_END
#import <AppKit/AppKit.h>

extern NSString * const _Nonnull ScreenshotCanvasViewDidRestoreStateNotification;
/// Posted when a tool shortcut key (S, H, P, A, T, E) is pressed on the canvas; userInfo[ScreenshotCanvasViewToolKey] is the tool.
extern NSString * const _Nonnull ScreenshotCanvasViewRequestsToolNotification;
extern NSString * const _Nonnull ScreenshotCanvasViewToolKey;
/// Posted when a text box opens for editing.
extern NSString * const _Nonnull ScreenshotCanvasViewDidBeginTextEditingNotification;
/// Posted when the open text box closes (committed or cancelled).
extern NSString * const _Nonnull ScreenshotCanvasViewDidEndTextEditingNotification;
/// Posted for formatting key commands while editing; userInfo[ScreenshotCanvasViewTextFormatKey] is
/// @"bold", @"italic", @"bigger" or @"smaller".
extern NSString * const _Nonnull ScreenshotCanvasViewRequestsTextFormatNotification;
extern NSString * const _Nonnull ScreenshotCanvasViewTextFormatKey;
/// Posted when the canvas changes its own zoom (a trackpad pinch, say), for the zoom controls.
extern NSString * const _Nonnull ScreenshotCanvasViewDidChangeZoomNotification;
