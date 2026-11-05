#import "STPrintPanelController.h"

#if defined(__linux__)

#import "STPrintPage.h"

const CGFloat STPrintDefaultMargin = 36.0;

static NSString * const STDefaultsPrintPaperWidthKey = @"ScreenshotToolPrintPaperWidth";
static NSString * const STDefaultsPrintPaperHeightKey = @"ScreenshotToolPrintPaperHeight";

static const CGFloat STPanelWidth = 720.0;
static const CGFloat STPanelHeight = 460.0;
static const CGFloat STPanelGutter = 20.0;
static const CGFloat STControlsWidth = 250.0;
static const CGFloat STRowHeight = 28.0;
static const CGFloat STRowGap = 14.0;

void STConfigurePrintLayout(STPrintLayout *layout, STPrintOptions *options, NSImage *image, NSRect selection) {
    NSSize pixels = STPrintImagePixelSize(image);
    NSRect whole = NSMakeRect(0.0, 0.0, pixels.width, pixels.height);
    NSRect source = options.selectionOnly ? NSIntersectionRect(selection, whole) : whole;
    layout.sourceRect = NSIsEmptyRect(source) ? whole : source;
    // A size that differs from the pixels is the image's own resolution; otherwise it has none.
    layout.pixelsPerInch = image.size.width > 0.0 && fabs(image.size.width - pixels.width) > 0.5
                               ? 72.0 * pixels.width / image.size.width
                               : STPrintDefaultPixelsPerInch;
    [options applyToLayout:layout];
}

NSSize STPrintLastPaperSize(NSUserDefaults *defaults) {
    CGFloat width = (CGFloat)[defaults doubleForKey:STDefaultsPrintPaperWidthKey];
    CGFloat height = (CGFloat)[defaults doubleForKey:STDefaultsPrintPaperHeightKey];
    if (width > 0.0 && height > 0.0) {
        return NSMakeSize(width, height);
    }
    NSSize paper = [[NSPrintInfo sharedPrintInfo] paperSize];
    return paper.width > 0.0 && paper.height > 0.0 ? paper : NSMakeSize(612.0, 792.0);
}

void STPrintSavePaperSize(NSUserDefaults *defaults, NSSize paper) {
    [defaults setDouble:paper.width forKey:STDefaultsPrintPaperWidthKey];
    [defaults setDouble:paper.height forKey:STDefaultsPrintPaperHeightKey];
}

/// The sheet as it will print: one page of the layout on white paper.
@interface STPrintPreviewView : NSView
@property (nonatomic, strong, nullable) STPrintLayout *layout;
@property (nonatomic, strong, nullable) NSImage *image;
@property (nonatomic) NSUInteger page;
@end

@implementation STPrintPreviewView

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    STPrintLayout *layout = self.layout;
    NSSize paper = layout ? layout.orientedPaperSize : NSZeroSize;
    NSRect bounds = NSInsetRect(self.bounds, 8.0, 8.0);
    if (!(paper.width > 0.0) || !(paper.height > 0.0) || NSIsEmptyRect(bounds)) {
        return;
    }
    CGFloat scale = MIN(NSWidth(bounds) / paper.width, NSHeight(bounds) / paper.height);
    NSRect sheet = NSMakeRect(floor(NSMidX(bounds) - paper.width * scale / 2.0),
                              floor(NSMidY(bounds) - paper.height * scale / 2.0),
                              floor(paper.width * scale), floor(paper.height * scale));
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.25] setFill];
    NSRectFillUsingOperation(NSOffsetRect(sheet, 0.0, -2.0), NSCompositeSourceOver);
    [[NSColor whiteColor] setFill];
    NSRectFill(sheet);

    if (self.image && layout.pageCount > 0) {
        NSGraphicsContext *context = [NSGraphicsContext currentContext];
        [context saveGraphicsState];
        NSRectClip(sheet);
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:NSMinX(sheet) yBy:NSMinY(sheet)];
        [transform scaleBy:NSWidth(sheet) / paper.width];
        [transform concat];
        STDrawPrintPage(layout, self.page, self.image, NO);
        [context restoreGraphicsState];
    }
}

@end

@interface STPrintPanelController () <NSTextFieldDelegate, NSWindowDelegate>
@property (nonatomic, strong) NSImage *flattenedImage;
@property (nonatomic, strong) NSImage *bareImage;
@property (nonatomic) NSRect selection;
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, readwrite, strong) NSPanel *panel;
@property (nonatomic, readwrite, strong) STPrintOptions *options;
@property (nonatomic, readwrite, strong) NSPopUpButton *contentPopUp;
@property (nonatomic, readwrite, strong) NSPopUpButton *fitPopUp;
@property (nonatomic, readwrite, strong) NSPopUpButton *orientationPopUp;
@property (nonatomic, readwrite, strong) NSTextField *scaleField;
@property (nonatomic, strong) NSTextField *scaleLabel;
@property (nonatomic, readwrite, strong) NSButton *enlargeCheckbox;
@property (nonatomic, readwrite, strong) NSButton *annotationsCheckbox;
@property (nonatomic, readwrite, strong) NSButton *previousPageButton;
@property (nonatomic, readwrite, strong) NSButton *nextPageButton;
@property (nonatomic, readwrite, strong) NSButton *printButton;
@property (nonatomic, readwrite, strong) NSTextField *summaryLabel;
@property (nonatomic, strong) STPrintPreviewView *preview;
@property (nonatomic, readwrite) NSUInteger previewPage;
@property (nonatomic) BOOL confirmed;
@end

@implementation STPrintPanelController

- (instancetype)initWithFlattenedImage:(NSImage *)flattenedImage
                             bareImage:(NSImage *)bareImage
                             selection:(NSRect)selection
                         selectionOnly:(BOOL)selectionOnly
                              defaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        _flattenedImage = flattenedImage;
        _bareImage = bareImage;
        _selection = selection;
        _defaults = defaults;
        _options = [STPrintOptions optionsFromDefaults:defaults];
        _options.selectionOnly = selectionOnly && !NSIsEmptyRect(selection);
        _paperSize = STPrintLastPaperSize(defaults);
        [self buildPanel];
        [self showOptions];
        [self refresh];
    }
    return self;
}

- (NSTextField *)labelWithString:(NSString *)string frame:(NSRect)frame {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:string];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    return label;
}

- (NSPopUpButton *)popUpWithTitles:(NSArray<NSString *> *)titles frame:(NSRect)frame action:(SEL)action {
    NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO];
    [popUp addItemsWithTitles:titles];
    [popUp setTarget:self];
    [popUp setAction:action];
    return popUp;
}

- (NSButton *)checkboxWithTitle:(NSString *)title frame:(NSRect)frame {
    NSButton *checkbox = [[NSButton alloc] initWithFrame:frame];
    [checkbox setButtonType:NSSwitchButton];
    [checkbox setTitle:title];
    [checkbox setTarget:self];
    [checkbox setAction:@selector(optionChanged:)];
    return checkbox;
}

- (NSButton *)buttonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    [button setTitle:title];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setTarget:self];
    [button setAction:action];
    return button;
}

- (void)buildPanel {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, STPanelWidth, STPanelHeight)
                                                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    [panel setReleasedWhenClosed:NO];
    [panel setHidesOnDeactivate:NO];
    [panel setTitle:@"Print"];
    [panel setDelegate:self];
    self.panel = panel;
    NSView *content = panel.contentView;

    CGFloat x = STPanelGutter;
    CGFloat labelHeight = 18.0;
    CGFloat y = STPanelHeight - STPanelGutter;

    NSRect (^nextRow)(CGFloat) = ^NSRect(CGFloat height) {
        NSRect row = NSMakeRect(x, y - height, STControlsWidth, height);
        return row;
    };

    NSTextField *contentLabel = [self labelWithString:@"Print" frame:nextRow(labelHeight)];
    [content addSubview:contentLabel];
    y -= labelHeight + 2.0;
    self.contentPopUp = [self popUpWithTitles:@[ @"Whole image", @"Selection" ] frame:nextRow(STRowHeight)
                                       action:@selector(optionChanged:)];
    [content addSubview:self.contentPopUp];
    y -= STRowHeight + STRowGap;

    NSTextField *fitLabel = [self labelWithString:@"Size" frame:nextRow(labelHeight)];
    [content addSubview:fitLabel];
    y -= labelHeight + 2.0;
    self.fitPopUp = [self popUpWithTitles:@[ @"Fit to page", @"Actual size", @"Custom scale" ] frame:nextRow(STRowHeight)
                                   action:@selector(optionChanged:)];
    [content addSubview:self.fitPopUp];
    y -= STRowHeight + 6.0;

    // Enlarge and the scale share a row: each belongs to one size, and only one shows.
    self.enlargeCheckbox = [self checkboxWithTitle:@"Enlarge small images to fill" frame:nextRow(STRowHeight - 4.0)];
    [content addSubview:self.enlargeCheckbox];
    NSRect scaleRow = nextRow(STRowHeight);
    self.scaleLabel = [self labelWithString:@"Scale (%)" frame:NSMakeRect(x, NSMinY(scaleRow) + 3.0, 90.0, labelHeight)];
    [content addSubview:self.scaleLabel];
    self.scaleField = [[NSTextField alloc] initWithFrame:NSMakeRect(x + 90.0, NSMinY(scaleRow), 80.0, STRowHeight - 4.0)];
    [self.scaleField setDelegate:self];
    [self.scaleField setTarget:self];
    [self.scaleField setAction:@selector(optionChanged:)];
    [content addSubview:self.scaleField];
    y -= STRowHeight + STRowGap;

    NSTextField *orientationLabel = [self labelWithString:@"Orientation" frame:nextRow(labelHeight)];
    [content addSubview:orientationLabel];
    y -= labelHeight + 2.0;
    self.orientationPopUp = [self popUpWithTitles:@[ @"Automatic", @"Portrait", @"Landscape" ] frame:nextRow(STRowHeight)
                                           action:@selector(optionChanged:)];
    [content addSubview:self.orientationPopUp];
    y -= STRowHeight + STRowGap;

    self.annotationsCheckbox = [self checkboxWithTitle:@"Include annotations" frame:nextRow(STRowHeight - 4.0)];
    [content addSubview:self.annotationsCheckbox];

    CGFloat previewX = x + STControlsWidth + STPanelGutter;
    CGFloat previewWidth = STPanelWidth - previewX - STPanelGutter;
    CGFloat buttonHeight = 30.0;
    CGFloat buttonsY = STPanelGutter;
    CGFloat pagerY = buttonsY + buttonHeight + 12.0;
    CGFloat previewY = pagerY + 28.0 + 8.0;
    self.preview = [[STPrintPreviewView alloc]
        initWithFrame:NSMakeRect(previewX, previewY, previewWidth, STPanelHeight - STPanelGutter - previewY)];
    [content addSubview:self.preview];

    self.previousPageButton = [self buttonWithTitle:@"‹" frame:NSMakeRect(previewX, pagerY, 36.0, 28.0)
                                             action:@selector(showPreviousPage:)];
    [content addSubview:self.previousPageButton];
    self.nextPageButton = [self buttonWithTitle:@"›" frame:NSMakeRect(previewX + previewWidth - 36.0, pagerY, 36.0, 28.0)
                                         action:@selector(showNextPage:)];
    [content addSubview:self.nextPageButton];
    self.summaryLabel = [self labelWithString:@"" frame:NSMakeRect(previewX + 42.0, pagerY + 5.0, previewWidth - 84.0, labelHeight)];
    [self.summaryLabel setAlignment:NSCenterTextAlignment];
    [content addSubview:self.summaryLabel];

    self.printButton = [self buttonWithTitle:@"Print…"
                                       frame:NSMakeRect(STPanelWidth - STPanelGutter - 110.0, buttonsY, 110.0, buttonHeight)
                                      action:@selector(confirm:)];
    [self.printButton setKeyEquivalent:@"\r"];
    [content addSubview:self.printButton];
    NSButton *cancel = [self buttonWithTitle:@"Cancel"
                                       frame:NSMakeRect(STPanelWidth - STPanelGutter - 110.0 - 8.0 - 100.0, buttonsY, 100.0, buttonHeight)
                                      action:@selector(cancel:)];
    [cancel setKeyEquivalent:@"\033"];
    [content addSubview:cancel];
}

/// The controls from the options.
- (void)showOptions {
    STPrintOptions *options = self.options;
    BOOL hasSelection = !NSIsEmptyRect(self.selection);
    [self.contentPopUp selectItemAtIndex:options.selectionOnly ? 1 : 0];
    [self.contentPopUp setEnabled:hasSelection];
    [self.fitPopUp selectItemAtIndex:options.fit == STPrintFitToPage ? 0 : (options.fit == STPrintFitActualSize ? 1 : 2)];
    [self.scaleField setStringValue:[NSString stringWithFormat:@"%.0f", options.customScale * 100.0]];
    [self.enlargeCheckbox setState:options.enlargeToFill ? NSOnState : NSOffState];
    [self.orientationPopUp selectItemAtIndex:options.orientation == STPrintOrientationAutomatic
                                                 ? 0
                                                 : (options.orientation == STPrintOrientationPortrait ? 1 : 2)];
    [self.annotationsCheckbox setState:options.includeAnnotations ? NSOnState : NSOffState];
}

/// The options from the controls.
- (void)readOptions {
    STPrintOptions *options = self.options;
    options.selectionOnly = self.contentPopUp.isEnabled && self.contentPopUp.indexOfSelectedItem == 1;
    NSInteger fit = self.fitPopUp.indexOfSelectedItem;
    options.fit = fit == 0 ? STPrintFitToPage : (fit == 1 ? STPrintFitActualSize : STPrintFitCustomScale);
    double percent = self.scaleField.stringValue.doubleValue;
    if (percent > 0.0) {
        options.customScale = (CGFloat)(percent / 100.0);
    }
    options.enlargeToFill = self.enlargeCheckbox.state == NSOnState;
    NSInteger orientation = self.orientationPopUp.indexOfSelectedItem;
    options.orientation = orientation == 0 ? STPrintOrientationAutomatic
                                           : (orientation == 1 ? STPrintOrientationPortrait : STPrintOrientationLandscape);
    options.includeAnnotations = self.annotationsCheckbox.state == NSOnState;
}

- (NSImage *)currentImage {
    return self.options.includeAnnotations ? self.flattenedImage : self.bareImage;
}

- (STPrintLayout *)currentLayout {
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.paperSize = self.paperSize;
    layout.margins = STPrintMarginsMake(STPrintDefaultMargin, STPrintDefaultMargin, STPrintDefaultMargin, STPrintDefaultMargin);
    STConfigurePrintLayout(layout, self.options, self.currentImage, self.selection);
    return layout;
}

- (void)setPaperSize:(NSSize)paperSize {
    _paperSize = paperSize;
    if (self.panel) {
        [self refresh];
    }
}

- (void)refresh {
    STPrintLayout *layout = [self currentLayout];
    NSUInteger pages = layout.pageCount;
    if (self.previewPage >= pages) {
        self.previewPage = pages > 0 ? pages - 1 : 0;
    }
    BOOL custom = self.options.fit == STPrintFitCustomScale;
    [self.scaleLabel setHidden:!custom];
    [self.scaleField setHidden:!custom];
    [self.enlargeCheckbox setHidden:self.options.fit != STPrintFitToPage];

    self.preview.layout = layout;
    self.preview.image = self.currentImage;
    self.preview.page = self.previewPage;
    [self.preview setNeedsDisplay:YES];

    BOOL several = pages > 1;
    [self.previousPageButton setHidden:!several];
    [self.nextPageButton setHidden:!several];
    [self.previousPageButton setEnabled:several && self.previewPage > 0];
    [self.nextPageButton setEnabled:several && self.previewPage + 1 < pages];
    [self.printButton setEnabled:pages > 0];

    NSString *summary = @"Nothing to print";
    if (pages == 1) {
        summary = [NSString stringWithFormat:@"1 page, %.0f%% of actual size", layout.effectiveScale * 100.0];
    } else if (pages > 1) {
        summary = [NSString stringWithFormat:@"Page %lu of %lu, %.0f%% of actual size",
                                             (unsigned long)self.previewPage + 1, (unsigned long)pages,
                                             layout.effectiveScale * 100.0];
    }
    [self.summaryLabel setStringValue:summary];
}

- (void)optionChanged:(id)sender {
    (void)sender;
    [self readOptions];
    [self refresh];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    (void)notification;
    [self readOptions];
    [self refresh];
}

- (void)showPreviousPage:(id)sender {
    (void)sender;
    if (self.previewPage > 0) {
        self.previewPage -= 1;
        [self refresh];
    }
}

- (void)showNextPage:(id)sender {
    (void)sender;
    if (self.previewPage + 1 < [self currentLayout].pageCount) {
        self.previewPage += 1;
        [self refresh];
    }
}

- (void)confirm:(id)sender {
    (void)sender;
    [self readOptions];
    [self.options saveToDefaults:self.defaults];
    self.confirmed = YES;
    [self endModal];
}

- (void)cancel:(id)sender {
    (void)sender;
    self.confirmed = NO;
    [self endModal];
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    [self endModal];
}

- (void)endModal {
    if ([NSApp modalWindow] == self.panel) {
        [NSApp stopModal];
    }
    if (self.panel.isVisible) {
        [self.panel orderOut:nil];
    }
}

- (BOOL)runModal {
    self.confirmed = NO;
    [self.panel center];
    [NSApp runModalForWindow:self.panel];
    [self.panel orderOut:nil];
    return self.confirmed;
}

@end

#endif
