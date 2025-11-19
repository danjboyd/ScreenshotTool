#import "TextToolPopoverController.h"
#import "STHyperlinkButton.h"
#import "ScreenshotToolSettings.h"
#import "AppDelegate.h"
#import "STFloatingPopover.h"
#import "STThemeUtilities.h"
#include <math.h>

#define STTextPopoverMinFontSize 8.0f
#define STTextPopoverMaxFontSize 128.0f

@class TextToolPopoverController;

@interface STTextPopoverContentView : NSView
@property (nonatomic, weak) TextToolPopoverController *owner;
@end

@implementation STTextPopoverContentView

- (BOOL)acceptsFirstResponder {
    return YES;
}

@end

@interface STTextPopoverPreviewTextView : NSTextView
@end

@implementation STTextPopoverPreviewTextView
@end

@interface TextToolPopoverController () <NSTextFieldDelegate, NSTextViewDelegate, NSComboBoxDelegate, NSComboBoxDataSource>
@property (nonatomic, strong) STFloatingPopover *popover;
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSTextView *previewTextView;
@property (nonatomic, strong) NSColorWell *colorWell;
@property (nonatomic, strong) NSComboBox *fontComboBox;
@property (nonatomic, strong) NSPopUpButton *fontFacePopUp;
@property (nonatomic, strong) NSTextField *fontSizeField;
@property (nonatomic, strong) NSStepper *fontSizeStepper;
@property (nonatomic, strong) STHyperlinkButton *resetButton;
@property (nonatomic, strong) STHyperlinkButton *defaultButton;
@property (nonatomic, strong) NSArray<NSButton *> *colorSwatchButtons;
@property (nonatomic, copy) NSArray<NSColor *> *colorSwatches;
@property (nonatomic, copy) NSArray<NSString *> *allFontFamilies;
@property (nonatomic, copy) NSArray<NSString *> *filteredFontFamilies;
@property (nonatomic, copy) NSString *fontFilterQuery;
@property (nonatomic, copy) NSString *currentFontComboSelection;
@property (nonatomic, copy) NSString *pendingFontComboStringValue;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *currentFontFaces;
@property (nonatomic, copy) NSString *previewSampleText;
@property (nonatomic, assign) CGFloat colorSwatchSize;
@end

@implementation TextToolPopoverController

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge {
    if (!self.popover) {
        [self buildPopover];
    }
    [self refresh];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"TextToolPopoverController showRelativeToRect entry (popover=%@ isShown=%@)",
                             self.popover ? @"YES" : @"NO",
                             self.popover.isShown ? @"YES" : @"NO"]);
    if (self.popover.isShown) {
        ScreenshotToolAppendLog(@"TextToolPopoverController showRelativeToRect skipped because popover already shown");
        return;
    }
    ScreenshotToolAppendLog([NSString stringWithFormat:@"TextToolPopoverController showRelativeToRect requested (view=%@ rect=%@ edge=%ld)",
                             NSStringFromClass([view class]),
                             NSStringFromRect(rect),
                             (long)edge]);
    [self.popover showRelativeToRect:rect ofView:view preferredEdge:edge];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"TextToolPopoverController showRelativeToRect invoked (isShown=%@)",
                             self.popover.isShown ? @"YES" : @"NO"]);
}

- (void)close {
    if (!self.popover) {
        return;
    }
    if (!self.popover.isShown) {
        ScreenshotToolAppendLog(@"TextToolPopoverController close skipped (popover not shown)");
        return;
    }
    [self.popover close];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"TextToolPopoverController close invoked (wasShown=YES nowShown=%@)",
                             self.popover.isShown ? @"YES" : @"NO"]);
}

- (BOOL)isShown {
    return self.popover.isShown;
}

- (void)refresh {
    if (!self.popover) {
        return;
    }
    id<TextToolPopoverControllerDelegate> delegate = self.delegate;
    if (!delegate) {
        return;
    }

    NSColor *color = [delegate textToolPopoverCurrentColor:self] ?: STDefaultTextColor();
    NSColor *defaultColor = [delegate textToolPopoverDefaultColor:self] ?: STDefaultTextColor();
    NSFont *font = [delegate textToolPopoverCurrentFont:self] ?: STDefaultTextFont();
    NSFont *defaultFont = [delegate textToolPopoverDefaultFont:self] ?: STDefaultTextFont();

    [self.colorWell setColor:color];
    [self updateSwatchSelectionForColor:color];
    [self updateFontControlsWithFont:font];

    if (!self.previewSampleText) {
        self.previewSampleText = @"Sample Text";
    }
    [self.previewTextView setString:self.previewSampleText];
    [self updatePreviewWithFont:font color:color];

    BOOL canResetColor = ![self colorsEqual:color other:defaultColor];
    BOOL canResetFont = ![self fontsEqual:font other:defaultFont];
    BOOL enableActions = (canResetColor || canResetFont);
    [self.resetButton setEnabled:enableActions];
    [self.defaultButton setEnabled:enableActions];
}

#pragma mark - Private helpers

- (void)buildPopover {
    ScreenshotToolAppendLog(@"TextToolPopoverController buildPopover begin");
    CGFloat popoverWidth = 340.0f;
    CGFloat popoverHeight = 320.0f;

    STTextPopoverContentView *content = [[STTextPopoverContentView alloc] initWithFrame:NSMakeRect(0, 0, popoverWidth, popoverHeight)];
    content.owner = self;
    self.contentView = content;
    self.popover = [[STFloatingPopover alloc] initWithContentView:self.contentView];
    self.popover.contentSize = self.contentView.bounds.size;
    ScreenshotToolAppendLog(@"TextToolPopoverController floating popover created");

    CGFloat padding = 14.0f;
    CGFloat contentWidth = self.contentView.bounds.size.width - (padding * 2.0f);
    CGFloat y = self.contentView.bounds.size.height - padding - 22.0f;

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, contentWidth, 22.0f)];
    [self configureLabel:title font:[NSFont boldSystemFontOfSize:13.0f]];
    [title setStringValue:@"Text Settings"];
    [self.contentView addSubview:title];

    y -= 30.0f;
    NSTextField *fontLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 60.0f, 18.0f)];
    [self configureLabel:fontLabel font:[NSFont systemFontOfSize:12.0f]];
    [fontLabel setStringValue:@"Font"];
    [self.contentView addSubview:fontLabel];

    CGFloat typefaceWidth = 130.0f;
    CGFloat typefaceSpacing = 8.0f;
    CGFloat familyFieldX = padding + 64.0f;
    CGFloat familyWidth = contentWidth - 64.0f - typefaceSpacing - typefaceWidth;
    if (familyWidth < 140.0f) {
        CGFloat deficit = 140.0f - familyWidth;
        familyWidth = 140.0f;
        typefaceWidth = MAX(90.0f, typefaceWidth - deficit);
    }

    self.fontComboBox = [[NSComboBox alloc] initWithFrame:NSMakeRect(familyFieldX,
                                                                     y - 4.0f,
                                                                     familyWidth,
                                                                     26.0f)];
    [self.fontComboBox setUsesDataSource:YES];
    [self.fontComboBox setCompletes:NO];
    [self.fontComboBox setDelegate:self];
    [self.fontComboBox setDataSource:self];
    [self.fontComboBox setNumberOfVisibleItems:12];
    [self.fontComboBox setAutoresizingMask:NSViewWidthSizable];
    [self populateFontFamilies];
    [self.contentView addSubview:self.fontComboBox];
    [fontLabel setAutoresizingMask:(NSViewMaxYMargin | NSViewWidthSizable)];

    NSTextField *typefaceLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(NSMaxX(self.fontComboBox.frame) + typefaceSpacing,
                                                                               y,
                                                                               typefaceWidth,
                                                                               18.0f)];
    [self configureLabel:typefaceLabel font:[NSFont systemFontOfSize:12.0f]];
    [typefaceLabel setStringValue:@"Typeface"];
    [typefaceLabel setAlignment:NSTextAlignmentLeft];
    [typefaceLabel setAutoresizingMask:(NSViewMaxYMargin | NSViewMinXMargin)];
    [self.contentView addSubview:typefaceLabel];

    self.fontFacePopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(typefaceLabel.frame.origin.x,
                                                                         y - 4.0f,
                                                                         typefaceWidth,
                                                                         26.0f)];
    [self.fontFacePopUp setTarget:self];
    [self.fontFacePopUp setAction:@selector(fontFaceChanged:)];
    [self.fontFacePopUp setAutoresizingMask:(NSViewMinXMargin)];
    [self.contentView addSubview:self.fontFacePopUp];

    y -= 36.0f;
    NSTextField *sizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 60.0f, 18.0f)];
    [self configureLabel:sizeLabel font:[NSFont systemFontOfSize:12.0f]];
    [sizeLabel setStringValue:@"Size"];
    [self.contentView addSubview:sizeLabel];

    CGFloat sizeFieldWidth = 64.0f;
    self.fontSizeField = [[NSTextField alloc] initWithFrame:NSMakeRect(padding + 64.0f,
                                                                       y - 2.0f,
                                                                       sizeFieldWidth,
                                                                       24.0f)];
    [self.fontSizeField setFont:[NSFont systemFontOfSize:12.0f]];
    [self.fontSizeField setAlignment:NSTextAlignmentRight];
    [self.fontSizeField setDelegate:self];
    [self.fontSizeField setAutoresizingMask:NSViewMaxYMargin];
    [self.fontSizeField setTarget:self];
    [self.fontSizeField setAction:@selector(fontSizeFieldChanged:)];
    [self.fontSizeField setStringValue:@"14"];
    [self.contentView addSubview:self.fontSizeField];

    self.fontSizeStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(NSMaxX(self.fontSizeField.frame) + 6.0f,
                                                                       y - 2.0f,
                                                                       18.0f,
                                                                       24.0f)];
    [self.fontSizeStepper setMinValue:STTextPopoverMinFontSize];
    [self.fontSizeStepper setMaxValue:STTextPopoverMaxFontSize];
    [self.fontSizeStepper setIncrement:1.0];
    [self.fontSizeStepper setTarget:self];
    [self.fontSizeStepper setAction:@selector(fontSizeStepperChanged:)];
    [self.fontSizeStepper setAutoresizingMask:NSViewMaxYMargin];
    [self.contentView addSubview:self.fontSizeStepper];

    y -= 44.0f;
    NSTextField *colorTitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 60.0f, 18.0f)];
    [self configureLabel:colorTitleLabel font:[NSFont systemFontOfSize:12.0f]];
    [colorTitleLabel setStringValue:@"Color"];
    [self.contentView addSubview:colorTitleLabel];

    CGFloat colorWellWidth = 44.0f;
    self.colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(padding + 64.0f,
                                                                   y - 4.0f,
                                                                   colorWellWidth,
                                                                   28.0f)];
    [self.colorWell setTarget:self];
    [self.colorWell setAction:@selector(colorChanged:)];
    [self.colorWell setAutoresizingMask:NSViewMaxYMargin];
    [self.contentView addSubview:self.colorWell];

    NSArray<NSColor *> *swatches = [NSArray arrayWithObjects:
        [NSColor blackColor],
        [NSColor colorWithCalibratedWhite:0.35 alpha:1.0],
        [NSColor whiteColor],
        [NSColor colorWithCalibratedRed:0.22 green:0.56 blue:0.95 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.16 green:0.78 blue:0.37 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.99 green:0.75 blue:0.20 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.91 green:0.30 blue:0.24 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.76 green:0.33 blue:0.85 alpha:1.0],
        nil];
    self.colorSwatches = swatches;
    CGFloat swatchSize = 26.0f;
    NSUInteger columns = swatches.count;
    CGFloat swatchSpacing = 6.0f;
    CGFloat availableWidth = MAX(0.0f, contentWidth - ((columns - 1) * swatchSpacing));
    CGFloat effectiveSwatchSize = MIN(swatchSize, MAX(20.0f, availableWidth / MAX(columns, 1)));
    self.colorSwatchSize = effectiveSwatchSize;
    CGFloat swatchAreaHeight = effectiveSwatchSize;

    CGFloat buttonAreaHeight = 32.0f;
    CGFloat previewBottom = padding + buttonAreaHeight + 18.0f;
    CGFloat swatchTopLimit = y - 8.0f;
    CGFloat swatchBottom = swatchTopLimit - swatchAreaHeight;
    CGFloat minimumPreviewGap = 12.0f;
    if (swatchBottom < previewBottom + minimumPreviewGap) {
        swatchBottom = previewBottom + minimumPreviewGap;
    }

    NSRect swatchContainerFrame = NSMakeRect(padding,
                                             swatchBottom,
                                             contentWidth,
                                             swatchAreaHeight);
    NSView *swatchContainer = [[NSView alloc] initWithFrame:swatchContainerFrame];
    [swatchContainer setAutoresizingMask:(NSViewMinYMargin | NSViewWidthSizable)];
    [self.contentView addSubview:swatchContainer];

    NSMutableArray<NSButton *> *swatchButtons = [[NSMutableArray alloc] initWithCapacity:swatches.count];
    for (NSUInteger idx = 0; idx < swatches.count; idx++) {
        NSUInteger col = idx;
        CGFloat originX = (effectiveSwatchSize + swatchSpacing) * col;
        CGFloat originY = 0.0f;
        NSButton *swatch = [[NSButton alloc] initWithFrame:NSMakeRect(originX,
                                                                      originY,
                                                                      effectiveSwatchSize,
                                                                      effectiveSwatchSize)];
        [swatch setButtonType:NSMomentaryChangeButton];
        [swatch setBordered:NO];
        [swatch setBezelStyle:NSShadowlessSquareBezelStyle];
        [swatch setImage:[self swatchImageWithColor:swatches[idx] highlighted:NO size:effectiveSwatchSize]];
        [swatch setAutoresizingMask:NSViewMaxXMargin];
        swatch.target = self;
        swatch.action = @selector(colorSwatchPressed:);
        swatch.tag = (NSInteger)idx;
        [swatchContainer addSubview:swatch];
        [swatchButtons addObject:swatch];
    }
    self.colorSwatchButtons = swatchButtons;
    [self updateSwatchSelectionForColor:self.colorWell.color];

    y = NSMinY(swatchContainer.frame) - 12.0f;
    CGFloat previewAvailableHeight = y - previewBottom;
    if (previewAvailableHeight < 0.0f) {
        previewAvailableHeight = 0.0f;
    }
    CGFloat previewHeight = previewAvailableHeight;
    NSScrollView *previewScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(padding,
                                                                                 previewBottom,
                                                                                 contentWidth,
                                                                                 previewHeight)];
    [previewScroll setBorderType:NSNoBorder];
    [previewScroll setHasVerticalScroller:NO];
    [previewScroll setHasHorizontalScroller:NO];
    [previewScroll setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];

    STTextPopoverPreviewTextView *preview = [[STTextPopoverPreviewTextView alloc] initWithFrame:previewScroll.contentView.bounds];
    [preview setRichText:NO];
    [preview setAllowsUndo:YES];
    [preview setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    NSColor *previewBackground = STThemeIsDark()
        ? [NSColor colorWithCalibratedWhite:0.18f alpha:1.0f]
        : [NSColor colorWithCalibratedWhite:0.95f alpha:1.0f];
    [previewScroll setDrawsBackground:YES];
    [previewScroll setBackgroundColor:previewBackground];
    [preview setDrawsBackground:YES];
    [preview setBackgroundColor:previewBackground];
    [preview setFont:STDefaultTextFont()];
    [preview setTextColor:STDefaultTextColor()];
    [preview setDelegate:self];
    [preview setString:@"Sample Text"];
    previewScroll.documentView = preview;
    [self.contentView addSubview:previewScroll];
    self.previewTextView = preview;
    self.previewSampleText = @"Sample Text";

    CGFloat buttonY = padding;

    self.resetButton = [STHyperlinkButton hyperlinkButtonWithTitle:@"Reset"
                                                          target:self
                                                          action:@selector(resetPressed:)];
    [self.contentView addSubview:self.resetButton];

    self.defaultButton = [STHyperlinkButton hyperlinkButtonWithTitle:@"Set as Default"
                                                             target:self
                                                             action:@selector(defaultPressed:)];
    [self.contentView addSubview:self.defaultButton];

    [self.resetButton sizeToFit];
    [self.defaultButton sizeToFit];
    [self.resetButton setAutoresizingMask:NSViewMaxYMargin];
    [self.defaultButton setAutoresizingMask:NSViewMaxYMargin];

    CGFloat buttonsWidth = self.resetButton.frame.size.width + 12.0f + self.defaultButton.frame.size.width;
    CGFloat originX = padding + (contentWidth - buttonsWidth);
    self.resetButton.frame = NSMakeRect(originX,
                                        buttonY,
                                        self.resetButton.frame.size.width,
                                        self.resetButton.frame.size.height);
    self.defaultButton.frame = NSMakeRect(NSMaxX(self.resetButton.frame) + 12.0f,
                                          buttonY,
                                          self.defaultButton.frame.size.width,
                                          self.defaultButton.frame.size.height);
}

- (void)configureLabel:(NSTextField *)label font:(NSFont *)font {
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setFont:font];
}

- (void)populateFontFamilies {
    NSArray<NSString *> *families = [[NSFontManager sharedFontManager] availableFontFamilies];
    NSArray<NSString *> *sorted = [families sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    self.allFontFamilies = sorted ?: @[];
    self.fontFilterQuery = @"";
    [self applyFontFilterAndReloadPreservingQuery:NO];
}

- (void)updateFontControlsWithFont:(NSFont *)font {
    NSString *family = font.familyName ?: STDefaultTextFont().familyName;
    self.fontFilterQuery = @"";
    [self applyFontFilterAndReloadPreservingQuery:NO];
    [self setFontComboSelectionToFamily:family ?: @"System"];
    self.currentFontComboSelection = family ?: @"";
    [self reloadFontFacesForFamily:family selectingFont:font];

    CGFloat size = MAX(STTextPopoverMinFontSize, MIN(STTextPopoverMaxFontSize, font.pointSize));
    [self.fontSizeField setStringValue:[NSString stringWithFormat:@"%.0f", roundf(size)]];
    [self.fontSizeStepper setDoubleValue:size];
}

- (void)applyFontFilterAndReloadPreservingQuery:(BOOL)preserveQuery {
    NSString *query = self.fontFilterQuery ?: @"";
    NSArray<NSString *> *source = self.allFontFamilies ?: @[];
    if (query.length == 0) {
        self.filteredFontFamilies = source;
    } else {
        NSMutableArray<NSString *> *matches = [[NSMutableArray alloc] init];
        for (NSString *family in source) {
            if ([family rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [matches addObject:family];
            }
        }
        self.filteredFontFamilies = matches.count > 0 ? matches : @[];
    }
    NSString *restoredSelection = preserveQuery ? (self.fontComboBox.stringValue ?: @"") : (self.currentFontComboSelection ?: @"");
    [self.fontComboBox reloadData];
    [self.fontComboBox noteNumberOfItemsChanged];
    if (preserveQuery) {
        if (![self.fontComboBox currentEditor]) {
            [self setFontComboBoxStringValue:restoredSelection allowDuringEditing:YES];
        }
    } else if (restoredSelection.length > 0) {
        [self setFontComboBoxStringValue:restoredSelection allowDuringEditing:NO];
    } else {
        [self setFontComboBoxStringValue:@"" allowDuringEditing:NO];
    }
}

- (NSInteger)indexOfFamily:(NSString *)family inArray:(NSArray<NSString *> *)array {
    if (family.length == 0) {
        return NSNotFound;
    }
    __block NSInteger found = NSNotFound;
    [array enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj caseInsensitiveCompare:family] == NSOrderedSame) {
            found = (NSInteger)idx;
            *stop = YES;
        }
    }];
    return found;
}

- (void)setFontComboSelectionToFamily:(NSString *)family {
    if (family.length == 0) {
        [self setFontComboBoxStringValue:@"" allowDuringEditing:NO];
        [self.fontComboBox deselectItemAtIndex:self.fontComboBox.indexOfSelectedItem];
        return;
    }
    NSInteger index = [self indexOfFamily:family inArray:self.filteredFontFamilies];
    [self setFontComboBoxStringValue:family allowDuringEditing:NO];
    if (index != NSNotFound) {
        [self.fontComboBox selectItemAtIndex:index];
    } else {
        NSInteger selectedIndex = self.fontComboBox.indexOfSelectedItem;
        if (selectedIndex != -1) {
            [self.fontComboBox deselectItemAtIndex:selectedIndex];
        }
    }
}

- (void)reloadFontFacesForFamily:(NSString *)family selectingFont:(NSFont *)font {
    if (!self.fontFacePopUp) {
        return;
    }
    [self.fontFacePopUp setAutoenablesItems:YES];
    [self.fontFacePopUp setEnabled:YES];
    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSArray<NSArray *> *members = (family.length > 0) ? [manager availableMembersOfFontFamily:family] : nil;
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *faces = [[NSMutableArray alloc] init];
    for (NSArray *entry in members) {
        if (![entry isKindOfClass:[NSArray class]] || entry.count == 0) {
            continue;
        }
        NSString *postscript = ([entry[0] isKindOfClass:[NSString class]]) ? entry[0] : nil;
        NSString *style = (entry.count > 1 && [entry[1] isKindOfClass:[NSString class]]) ? entry[1] : postscript;
        if (postscript.length == 0 || style.length == 0) {
            continue;
        }
        [faces addObject:@{ @"title" : style, @"postscript" : postscript }];
    }
    if (!faces.count && family.length > 0) {
        NSFont *fallbackFont = font ?: [manager fontWithFamily:family traits:0 weight:5 size:MAX(12.0f, STDefaultTextFont().pointSize)];
        NSString *fallbackName = fallbackFont.fontName ?: STDefaultTextFont().fontName;
        if (fallbackName.length > 0) {
            [faces addObject:@{ @"title" : @"Regular", @"postscript" : fallbackName }];
        }
    }
    self.currentFontFaces = faces;
    [self.fontFacePopUp removeAllItems];
    for (NSDictionary<NSString *, NSString *> *face in faces) {
        NSString *title = face[@"title"] ?: @"";
        [self.fontFacePopUp addItemWithTitle:title.length ? title : @"Regular"];
        NSMenuItem *item = (NSMenuItem *)[self.fontFacePopUp itemAtIndex:self.fontFacePopUp.numberOfItems - 1];
        item.representedObject = face[@"postscript"];
    }
    [self.fontFacePopUp setEnabled:(faces.count > 0)];
    NSInteger selectionIndex = 0;
    NSString *targetPostscript = font.fontName;
    if (targetPostscript.length == 0 && faces.count > 0) {
        targetPostscript = faces[0][@"postscript"];
    }
    for (NSUInteger idx = 0; idx < faces.count; idx++) {
        NSString *candidate = faces[idx][@"postscript"];
        if (candidate.length > 0 && [candidate isEqualToString:targetPostscript]) {
            selectionIndex = (NSInteger)idx;
            break;
        }
    }
    if (faces.count > 0) {
        [self.fontFacePopUp selectItemAtIndex:selectionIndex];
    } else {
        [self.fontFacePopUp setEnabled:NO];
    }
}

- (void)finalizeFontComboSelectionWithInput:(NSString *)input {
    NSString *resolved = [self resolvedFamilyNameForInput:input];
    self.fontFilterQuery = @"";
    [self applyFontFilterAndReloadPreservingQuery:NO];
    [self setFontComboSelectionToFamily:resolved];
    self.currentFontComboSelection = resolved ?: @"";
    [self reloadFontFacesForFamily:resolved selectingFont:nil];
}

- (void)updatePreviewWithFont:(NSFont *)font color:(NSColor *)color {
    NSColor *displayColor = color ?: [NSColor blackColor];
    NSFont *resolvedFont = font ?: STDefaultTextFont();
    NSRange range = NSMakeRange(0, self.previewTextView.string.length);
    [[self.previewTextView textStorage] setAttributes:@{ NSFontAttributeName : resolvedFont,
                                                         NSForegroundColorAttributeName : displayColor }
                                                range:range];
}

- (NSImage *)swatchImageWithColor:(NSColor *)color highlighted:(BOOL)highlighted size:(CGFloat)size {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, size, size)
                                                         xRadius:4.0f
                                                         yRadius:4.0f];
    [[color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color setFill];
    [path fill];
    NSColor *strokeColor = highlighted ? [NSColor colorWithCalibratedRed:0.18 green:0.8 blue:0.44 alpha:1.0]
                                       : [NSColor colorWithCalibratedWhite:0.0 alpha:0.25];
    CGFloat strokeWidth = highlighted ? 2.0f : 1.0f;
    [strokeColor setStroke];
    [path setLineWidth:strokeWidth];
    [path stroke];
    [image unlockFocus];
    return image;
}

- (void)updateSwatchSelectionForColor:(NSColor *)color {
    if (!self.colorSwatchButtons.count) {
        return;
    }
    NSColor *comparison = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color;
    CGFloat size = (self.colorSwatchSize > 0.0f) ? self.colorSwatchSize : 22.0f;
    for (NSUInteger idx = 0; idx < self.colorSwatchButtons.count; idx++) {
        NSButton *swatch = self.colorSwatchButtons[idx];
        NSColor *candidate = [self.colorSwatches[idx] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: self.colorSwatches[idx];
        BOOL match = NO;
        if (comparison) {
            CGFloat cr, cg, cb, ca;
            CGFloat rr, rg, rb, ra;
            [comparison getRed:&cr green:&cg blue:&cb alpha:&ca];
            [candidate getRed:&rr green:&rg blue:&rb alpha:&ra];
            match = (fabs(cr - rr) < 0.01 && fabs(cg - rg) < 0.01 && fabs(cb - rb) < 0.01 && fabs(ca - ra) < 0.01);
        }
        [swatch setImage:[self swatchImageWithColor:self.colorSwatches[idx] highlighted:match size:size]];
    }
}

- (NSString *)resolvedFamilyNameForInput:(NSString *)input {
    if (input.length == 0) {
        return STDefaultTextFont().familyName;
    }
    NSInteger index = [self indexOfFamily:input inArray:self.allFontFamilies];
    if (index != NSNotFound && (NSUInteger)index < self.allFontFamilies.count) {
        return self.allFontFamilies[(NSUInteger)index];
    }
    for (NSString *candidate in self.allFontFamilies) {
        if ([candidate rangeOfString:input options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return candidate;
        }
    }
    return input;
}

- (void)setFontComboBoxStringValue:(NSString *)value allowDuringEditing:(BOOL)allowEditing {
    NSString *target = value ?: @"";
    if (!allowEditing && [self.fontComboBox currentEditor]) {
        self.pendingFontComboStringValue = target;
        return;
    }
    self.pendingFontComboStringValue = nil;
    [self.fontComboBox setStringValue:target];
}

- (void)flushPendingFontComboStringValueIfNeeded {
    if (!self.pendingFontComboStringValue.length) {
        return;
    }
    if ([self.fontComboBox currentEditor]) {
        return;
    }
    NSString *pending = self.pendingFontComboStringValue;
    self.pendingFontComboStringValue = nil;
    [self.fontComboBox setStringValue:pending];
}

- (NSFont *)fontFromCurrentControls {
    NSString *inputFamily = self.fontComboBox.stringValue ?: @"";
    NSString *family = [self resolvedFamilyNameForInput:inputFamily];
    CGFloat size = self.fontSizeField.doubleValue;
    if (!isfinite(size) || size <= 0.0f) {
        size = STDefaultTextFont().pointSize;
    }
    size = MAX(STTextPopoverMinFontSize, MIN(STTextPopoverMaxFontSize, size));
    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSFont *font = nil;
    if (self.fontFacePopUp && self.fontFacePopUp.numberOfItems > 0) {
        NSMenuItem *selectedItem = (NSMenuItem *)self.fontFacePopUp.selectedItem;
        NSString *postscriptName = nil;
        if (selectedItem) {
            postscriptName = (NSString *)selectedItem.representedObject;
            if (![postscriptName isKindOfClass:[NSString class]]) {
                postscriptName = nil;
            }
        }
        if (postscriptName.length == 0 && self.currentFontFaces.count > 0) {
            postscriptName = self.currentFontFaces.firstObject[@"postscript"];
        }
        if (postscriptName.length > 0) {
            font = [NSFont fontWithName:postscriptName size:size];
        }
    }
    if (!font && family.length > 0) {
        font = [manager fontWithFamily:family traits:0 weight:5 size:size];
        if (!font) {
            NSArray<NSArray *> *members = [manager availableMembersOfFontFamily:family];
            for (NSArray *entry in members) {
                if (![entry isKindOfClass:[NSArray class]] || entry.count == 0) {
                    continue;
                }
                NSString *name = entry[0];
                if (![name isKindOfClass:[NSString class]]) {
                    continue;
                }
                font = [NSFont fontWithName:name size:size];
                if (font) {
                    break;
                }
            }
        }
    }
    if (!font) {
        font = [NSFont fontWithName:STDefaultTextFont().fontName size:size];
    }
    return font ?: STDefaultTextFont();
}

- (BOOL)colorsEqual:(NSColor *)lhs other:(NSColor *)rhs {
    if (!lhs && !rhs) {
        return YES;
    }
    if (!lhs || !rhs) {
        return NO;
    }
    NSColor *left = [lhs colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: lhs;
    NSColor *right = [rhs colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: rhs;
    CGFloat lr, lg, lb, la;
    CGFloat rr, rg, rb, ra;
    [left getRed:&lr green:&lg blue:&lb alpha:&la];
    [right getRed:&rr green:&rg blue:&rb alpha:&ra];
    return (fabs(lr - rr) < 0.001 && fabs(lg - rg) < 0.001 && fabs(lb - rb) < 0.001 && fabs(la - ra) < 0.001);
}

- (BOOL)fontsEqual:(NSFont *)lhs other:(NSFont *)rhs {
    if (!lhs && !rhs) {
        return YES;
    }
    if (!lhs || !rhs) {
        return NO;
    }
    return ([lhs.fontName isEqualToString:rhs.fontName] && fabs(lhs.pointSize - rhs.pointSize) < 0.01f);
}

- (void)applyFontSelectionChange {
    NSFont *font = [self fontFromCurrentControls];
    [self.delegate textToolPopover:self didChangeFont:font];
    [self refresh];
}

#pragma mark - Actions

- (void)colorChanged:(NSColorWell *)sender {
    NSColor *color = sender.color ?: STDefaultTextColor();
    [self.delegate textToolPopover:self didChangeColor:color];
    [self updateSwatchSelectionForColor:color];
    [self refresh];
}

- (void)colorSwatchPressed:(NSButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || (NSUInteger)index >= self.colorSwatches.count) {
        return;
    }
    NSColor *selected = self.colorSwatches[(NSUInteger)index];
    [self.colorWell setColor:selected];
    [self.delegate textToolPopover:self didChangeColor:selected];
    [self updateSwatchSelectionForColor:selected];
    [self refresh];
}

- (void)fontSizeFieldChanged:(id)sender {
    (void)sender;
    CGFloat size = self.fontSizeField.doubleValue;
    if (!isfinite(size) || size <= 0.0f) {
        size = STDefaultTextFont().pointSize;
    }
    size = MAX(STTextPopoverMinFontSize, MIN(STTextPopoverMaxFontSize, size));
    [self.fontSizeField setStringValue:[NSString stringWithFormat:@"%.0f", roundf(size)]]; 
    [self.fontSizeStepper setDoubleValue:size];
    [self applyFontSelectionChange];
}

- (void)fontSizeStepperChanged:(NSStepper *)sender {
    CGFloat size = MAX(STTextPopoverMinFontSize, MIN(STTextPopoverMaxFontSize, sender.doubleValue));
    [self.fontSizeField setStringValue:[NSString stringWithFormat:@"%.0f", roundf(size)]];
    [self.fontSizeStepper setDoubleValue:size];
    [self applyFontSelectionChange];
}

- (void)fontFaceChanged:(id)sender {
    (void)sender;
    [self applyFontSelectionChange];
}

- (void)resetPressed:(id)sender {
    (void)sender;
    [self.delegate textToolPopoverDidRequestReset:self];
    self.previewSampleText = @"Sample Text";
    [self refresh];
}

- (void)defaultPressed:(id)sender {
    (void)sender;
    [self.delegate textToolPopoverDidRequestSetDefault:self];
    [self refresh];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.fontSizeField) {
        [self fontSizeFieldChanged:self.fontSizeField];
    } else if (notification.object == self.fontComboBox) {
        [self finalizeFontComboSelectionWithInput:self.fontComboBox.stringValue ?: @""];
        [self applyFontSelectionChange];
        [self flushPendingFontComboStringValueIfNeeded];
    }
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.fontComboBox) {
        self.fontFilterQuery = self.fontComboBox.stringValue ?: @"";
        [self applyFontFilterAndReloadPreservingQuery:YES];
    }
}

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object == self.previewTextView) {
        self.previewSampleText = self.previewTextView.string ?: @"";
        NSFont *font = [self.delegate textToolPopoverCurrentFont:self] ?: STDefaultTextFont();
        NSColor *color = [self.delegate textToolPopoverCurrentColor:self] ?: STDefaultTextColor();
        [self updatePreviewWithFont:font color:color];
    }
}

- (void)comboBoxSelectionDidChange:(NSNotification *)notification {
    if (notification.object != self.fontComboBox) {
        return;
    }
    NSString *selection = nil;
    NSInteger selectedIndex = self.fontComboBox.indexOfSelectedItem;
    if (selectedIndex >= 0 && (NSUInteger)selectedIndex < self.filteredFontFamilies.count) {
        selection = self.filteredFontFamilies[(NSUInteger)selectedIndex];
    }
    if (selection.length == 0) {
        selection = self.fontComboBox.stringValue ?: @"";
    }
    self.currentFontComboSelection = selection ?: @"";
    [self finalizeFontComboSelectionWithInput:self.currentFontComboSelection];
    [self applyFontSelectionChange];
}

#pragma mark - NSComboBoxDataSource

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)comboBox {
    if (comboBox != self.fontComboBox) {
        return 0;
    }
    return (NSInteger)self.filteredFontFamilies.count;
}

- (id)comboBox:(NSComboBox *)comboBox objectValueForItemAtIndex:(NSInteger)index {
    if (comboBox != self.fontComboBox) {
        return nil;
    }
    if (index < 0 || (NSUInteger)index >= self.filteredFontFamilies.count) {
        return nil;
    }
    return self.filteredFontFamilies[(NSUInteger)index];
}

- (NSUInteger)comboBox:(NSComboBox *)comboBox indexOfItemWithStringValue:(NSString *)string {
    if (comboBox != self.fontComboBox) {
        return NSNotFound;
    }
    NSInteger idx = [self indexOfFamily:string inArray:self.filteredFontFamilies];
    return (idx == NSNotFound) ? NSNotFound : (NSUInteger)idx;
}

- (NSString *)comboBox:(NSComboBox *)comboBox completedString:(NSString *)uncompletedString {
    if (comboBox != self.fontComboBox) {
        return nil;
    }
    if (uncompletedString.length == 0) {
        return nil;
    }
    for (NSString *family in self.filteredFontFamilies) {
        if ([family rangeOfString:uncompletedString options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location != NSNotFound) {
            return family;
        }
    }
    return nil;
}

@end
