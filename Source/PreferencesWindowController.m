#import "PreferencesWindowController.h"
#import "ScreenshotToolSettings.h"
#include <math.h>

static const CGFloat STPreferencesWidth = 520.0f;
static const CGFloat STPreferencesHeight = 470.0f;

@interface PreferencesWindowController () <NSWindowDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSSlider *penWidthSlider;
@property (nonatomic, strong) NSTextField *penWidthValueLabel;
@property (nonatomic, strong) NSArray<NSButton *> *penQuickButtons;
@property (nonatomic, strong) NSColorWell *penColorWell;

@property (nonatomic, strong) NSSlider *highlighterWidthSlider;
@property (nonatomic, strong) NSTextField *highlighterWidthValueLabel;
@property (nonatomic, strong) NSArray<NSButton *> *highlighterQuickButtons;
@property (nonatomic, strong) NSColorWell *highlighterColorWell;

@property (nonatomic, strong) NSColorWell *textColorWell;
@property (nonatomic, strong) NSTextField *textFontSummaryLabel;
@property (nonatomic, strong) NSButton *textFontButton;

@property (nonatomic, weak) NSResponder *previousFirstResponder;

@property (nonatomic, strong) NSTextField *saveDirectoryField;
@property (nonatomic, strong) NSButton *chooseDirectoryButton;

@property (nonatomic, strong) NSButton *statusBarCheckbox;
@property (nonatomic, strong) NSButton *restoreDefaultsButton;
@property (nonatomic, strong) NSButton *closeButton;
@end

@implementation PreferencesWindowController

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (instancetype)initWithDelegate:(id<PreferencesWindowControllerDelegate>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
        [self buildInterface];
    }
    return self;
}

- (void)buildInterface {
    NSRect frame = NSMakeRect(0, 0, STPreferencesWidth, STPreferencesHeight);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskMiniaturizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"Preferences";
    self.window.delegate = self;

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, STPreferencesWidth, STPreferencesHeight)];
    [self.window setContentView:content];

    CGFloat padding = 20.0f;
    CGFloat y = STPreferencesHeight - padding - 24.0f;
    CGFloat sectionSpacing = 30.0f;
    CGFloat controlSpacing = 18.0f;
    CGFloat labelWidth = 90.0f;
    CGFloat sliderWidth = 260.0f;
    CGFloat valueWidth = 64.0f;

    // Drawing Defaults header
    NSTextField *drawingHeader = [self headerLabelWithString:@"Drawing Defaults" y:y width:STPreferencesWidth - (padding * 2.0f)];
    [content addSubview:drawingHeader];
    y -= sectionSpacing;

    y = [self addToolSectionWithTitle:@"Pen"
                                baseY:y
                            labelWidth:labelWidth
                           sliderWidth:sliderWidth
                            valueWidth:valueWidth
                           quickValues:@[@2.0f, @4.0f, @6.0f]
                             colorWell:&_penColorWell
                                 slider:&_penWidthSlider
                              valueLabel:&_penWidthValueLabel
                                 buttons:&_penQuickButtons
                                content:content];
    y -= controlSpacing;

    y = [self addToolSectionWithTitle:@"Highlighter"
                                baseY:y
                            labelWidth:labelWidth
                           sliderWidth:sliderWidth
                            valueWidth:valueWidth
                           quickValues:@[@8.0f, @12.0f, @20.0f]
                             colorWell:&_highlighterColorWell
                                 slider:&_highlighterWidthSlider
                              valueLabel:&_highlighterWidthValueLabel
                                 buttons:&_highlighterQuickButtons
                                content:content];
    y -= sectionSpacing;

    // Text Defaults
    NSTextField *textHeader = [self headerLabelWithString:@"Text Defaults" y:y width:STPreferencesWidth - (padding * 2.0f)];
    [content addSubview:textHeader];
    y -= (controlSpacing + 6.0f);

    NSTextField *textColorLabel = [self fieldLabelWithString:@"Color" frame:NSMakeRect(padding, y, labelWidth, 20.0f)];
    [content addSubview:textColorLabel];

    self.textColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(padding + labelWidth,
                                                                       y - 4.0f,
                                                                       52.0f,
                                                                       30.0f)];
    [self.textColorWell setTarget:self];
    [self.textColorWell setAction:@selector(textColorChanged:)];
    [content addSubview:self.textColorWell];

    y -= (controlSpacing + 8.0f);
    NSTextField *fontLabel = [self fieldLabelWithString:@"Font" frame:NSMakeRect(padding, y, labelWidth, 20.0f)];
    [content addSubview:fontLabel];

    CGFloat summaryWidth = STPreferencesWidth - (padding * 2.0f) - labelWidth - 140.0f;
    self.textFontSummaryLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding + labelWidth,
                                                                              y,
                                                                              MAX(summaryWidth, 160.0f),
                                                                              20.0f)];
    [self configureSummaryLabel:self.textFontSummaryLabel];
    [self.textFontSummaryLabel setAlignment:NSTextAlignmentLeft];
    [self.textFontSummaryLabel setStringValue:@"Current font"];
    [content addSubview:self.textFontSummaryLabel];

    self.textFontButton = [[NSButton alloc] initWithFrame:NSMakeRect(NSMaxX(self.textFontSummaryLabel.frame) + 16.0f,
                                                                     y - 4.0f,
                                                                     120.0f,
                                                                     28.0f)];
    [self.textFontButton setTitle:@"Choose Font…"];
    [self.textFontButton setButtonType:NSMomentaryPushInButton];
    [self.textFontButton setBezelStyle:NSRoundedBezelStyle];
    [self.textFontButton setTarget:self];
    [self.textFontButton setAction:@selector(chooseTextFont:)];
    [content addSubview:self.textFontButton];

    y -= sectionSpacing;

    // Workspace section
    NSTextField *workspaceHeader = [self headerLabelWithString:@"Workspace" y:y width:STPreferencesWidth - (padding * 2.0f)];
    [content addSubview:workspaceHeader];
    y -= (controlSpacing + 6.0f);

    NSTextField *directoryLabel = [self fieldLabelWithString:@"Default Save Folder"
                                                       frame:NSMakeRect(padding, y, STPreferencesWidth - (padding * 2.0f), 18.0f)];
    [content addSubview:directoryLabel];
    y -= (controlSpacing - 6.0f);

    CGFloat directoryWidth = STPreferencesWidth - (padding * 2.0f) - 120.0f;
    self.saveDirectoryField = [[NSTextField alloc] initWithFrame:NSMakeRect(padding,
                                                                            y,
                                                                            directoryWidth,
                                                                            24.0f)];
    [self.saveDirectoryField setEditable:NO];
    [self.saveDirectoryField setBezeled:YES];
    [self.saveDirectoryField setBordered:YES];
    [self.saveDirectoryField setDrawsBackground:YES];
    [self.saveDirectoryField setFont:[NSFont systemFontOfSize:12.0f]];
    [content addSubview:self.saveDirectoryField];

    self.chooseDirectoryButton = [[NSButton alloc] initWithFrame:NSMakeRect(NSMaxX(self.saveDirectoryField.frame) + 10.0f,
                                                                           y - 2.0f,
                                                                           100.0f,
                                                                           28.0f)];
    [self.chooseDirectoryButton setTitle:@"Choose…"];
    [self.chooseDirectoryButton setButtonType:NSMomentaryPushInButton];
    [self.chooseDirectoryButton setBezelStyle:NSRoundedBezelStyle];
    [self.chooseDirectoryButton setTarget:self];
    [self.chooseDirectoryButton setAction:@selector(chooseSaveDirectory:)];
    [content addSubview:self.chooseDirectoryButton];

    y -= sectionSpacing;

    // Interface section
    NSTextField *interfaceHeader = [self headerLabelWithString:@"Interface" y:y width:STPreferencesWidth - (padding * 2.0f)];
    [content addSubview:interfaceHeader];
    y -= (controlSpacing + 6.0f);

    self.statusBarCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(padding, y, STPreferencesWidth - (padding * 2.0f), 24.0f)];
    [self.statusBarCheckbox setButtonType:NSSwitchButton];
    [self.statusBarCheckbox setTitle:@"Show status bar"];
    [self.statusBarCheckbox setTarget:self];
    [self.statusBarCheckbox setAction:@selector(statusBarToggled:)];
    [content addSubview:self.statusBarCheckbox];

    y = padding + 60.0f;

    self.restoreDefaultsButton = [[NSButton alloc] initWithFrame:NSMakeRect(padding,
                                                                            y - 6.0f,
                                                                            150.0f,
                                                                            32.0f)];
    [self.restoreDefaultsButton setTitle:@"Restore Defaults"];
    [self.restoreDefaultsButton setButtonType:NSMomentaryPushInButton];
    [self.restoreDefaultsButton setBezelStyle:NSRoundedBezelStyle];
    [self.restoreDefaultsButton setTarget:self];
    [self.restoreDefaultsButton setAction:@selector(restoreDefaultsPressed:)];
    [content addSubview:self.restoreDefaultsButton];

    self.closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(STPreferencesWidth - padding - 100.0f,
                                                                  y - 6.0f,
                                                                  100.0f,
                                                                  32.0f)];
    [self.closeButton setTitle:@"Close"];
    [self.closeButton setButtonType:NSMomentaryPushInButton];
    [self.closeButton setBezelStyle:NSRoundedBezelStyle];
    [self.closeButton setTarget:self];
    [self.closeButton setAction:@selector(closePressed:)];
    [content addSubview:self.closeButton];

    [self ensureWindowAccommodatesContent];
}

- (NSTextField *)headerLabelWithString:(NSString *)string y:(CGFloat)y width:(CGFloat)width {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20.0f, y, width, 22.0f)];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setFont:[NSFont boldSystemFontOfSize:14.0f]];
    [label setStringValue:string ?: @""];
    return label;
}

- (NSTextField *)fieldLabelWithString:(NSString *)string frame:(NSRect)frame {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setFont:[NSFont systemFontOfSize:12.0f]];
    [label setStringValue:string ?: @""];
    return label;
}

- (void)configureSummaryLabel:(NSTextField *)label {
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setFont:[NSFont systemFontOfSize:12.0f]];
}

- (CGFloat)addToolSectionWithTitle:(NSString *)title
                              baseY:(CGFloat)y
                          labelWidth:(CGFloat)labelWidth
                          sliderWidth:(CGFloat)sliderWidth
                           valueWidth:(CGFloat)valueWidth
                          quickValues:(NSArray<NSNumber *> *)quickValues
                            colorWell:(NSColorWell *__strong *)colorWell
                                slider:(NSSlider *__strong *)slider
                             valueLabel:(NSTextField *__strong *)valueLabel
                                buttons:(NSArray<NSButton *> *__strong *)buttons
                               content:(NSView *)content {
    CGFloat padding = 20.0f;

    NSTextField *toolLabel = [self fieldLabelWithString:title
                                                  frame:NSMakeRect(padding, y, labelWidth, 20.0f)];
    [toolLabel setFont:[NSFont boldSystemFontOfSize:12.0f]];
    [content addSubview:toolLabel];

    NSSlider *toolSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(padding + labelWidth,
                                                                      y - 2.0f,
                                                                      sliderWidth,
                                                                      22.0f)];
    [toolSlider setMinValue:STToolWidthMin];
    [toolSlider setMaxValue:STToolWidthMax];
    [toolSlider setNumberOfTickMarks:0];
    [toolSlider setContinuous:YES];
    [toolSlider setTarget:self];
    if ([title isEqualToString:@"Pen"]) {
        [toolSlider setAction:@selector(penWidthSliderChanged:)];
    } else {
        [toolSlider setAction:@selector(highlighterWidthSliderChanged:)];
    }
    [content addSubview:toolSlider];

    NSTextField *toolValueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(NSMaxX(toolSlider.frame) + 12.0f,
                                                                              y,
                                                                              valueWidth,
                                                                              18.0f)];
    [self configureSummaryLabel:toolValueLabel];
    [toolValueLabel setAlignment:NSTextAlignmentRight];
    [toolValueLabel setStringValue:@"0 px"];
    [content addSubview:toolValueLabel];

    CGFloat quickButtonWidth = 48.0f;
    CGFloat quickSpacing = 8.0f;
    NSMutableArray<NSButton *> *quickButtons = [[NSMutableArray alloc] initWithCapacity:quickValues.count];
    CGFloat quickY = y - 32.0f;
    CGFloat quickX = padding + labelWidth;
    for (NSNumber *value in quickValues) {
        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(quickX,
                                                                      quickY,
                                                                      quickButtonWidth,
                                                                      26.0f)];
        [button setButtonType:NSMomentaryPushInButton];
        [button setBezelStyle:NSTexturedRoundedBezelStyle];
        [button setTitle:[NSString stringWithFormat:@"%.0f", value.doubleValue]];
        [button setTag:(NSInteger)lrint(value.doubleValue)];
        if ([title isEqualToString:@"Pen"]) {
            [button setTarget:self];
            [button setAction:@selector(penQuickWidthPressed:)];
        } else {
            [button setTarget:self];
            [button setAction:@selector(highlighterQuickWidthPressed:)];
        }
        [content addSubview:button];
        [quickButtons addObject:button];
        quickX += quickButtonWidth + quickSpacing;
    }

    NSTextField *colorLabel = [self fieldLabelWithString:@"Color"
                                                  frame:NSMakeRect(padding + labelWidth + sliderWidth + valueWidth + 24.0f,
                                                                   quickY + 4.0f,
                                                                   50.0f,
                                                                   18.0f)];
    [content addSubview:colorLabel];

    NSColorWell *toolColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(NSMaxX(colorLabel.frame) + 6.0f,
                                                                             quickY - 2.0f,
                                                                             52.0f,
                                                                             30.0f)];
    [toolColorWell setTarget:self];
    if ([title isEqualToString:@"Pen"]) {
        [toolColorWell setAction:@selector(penColorChanged:)];
    } else {
        [toolColorWell setAction:@selector(highlighterColorChanged:)];
    }
    [content addSubview:toolColorWell];

    if (slider) {
        *slider = toolSlider;
    }
    if (valueLabel) {
        *valueLabel = toolValueLabel;
    }
    if (buttons) {
        *buttons = quickButtons;
    }
    if (colorWell) {
        *colorWell = toolColorWell;
    }

    return quickY - 12.0f;
}

- (void)showRelativeToWindow:(NSWindow *)window {
    if (!self.window) {
        return;
    }
    [self refresh];
    if (window) {
        NSRect parentFrame = window.frame;
        NSPoint origin = NSMakePoint(NSMidX(parentFrame) - (STPreferencesWidth / 2.0f),
                                     NSMidY(parentFrame) - (STPreferencesHeight / 2.0f));
        [self.window setFrameOrigin:origin];
    } else {
        [self.window center];
    }
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)refresh {
    id<PreferencesWindowControllerDelegate> delegate = self.delegate;
    if (!delegate) {
        return;
    }

    CGFloat penWidth = [delegate preferencesController:self defaultWidthForTool:ScreenshotCanvasToolPen];
    [self.penWidthSlider setDoubleValue:penWidth];
    [self.penWidthValueLabel setStringValue:[self displayStringForWidth:penWidth]];
    NSColor *penColor = [delegate preferencesController:self defaultColorForTool:ScreenshotCanvasToolPen] ?: STDefaultPenColor();
    [self.penColorWell setColor:penColor];

    CGFloat highlighterWidth = [delegate preferencesController:self defaultWidthForTool:ScreenshotCanvasToolHighlighter];
    [self.highlighterWidthSlider setDoubleValue:highlighterWidth];
    [self.highlighterWidthValueLabel setStringValue:[self displayStringForWidth:highlighterWidth]];
    NSColor *highlighterColor = [delegate preferencesController:self defaultColorForTool:ScreenshotCanvasToolHighlighter] ?: STDefaultHighlighterColor();
    [self.highlighterColorWell setColor:highlighterColor];

    NSColor *textColor = [delegate preferencesControllerDefaultTextColor:self] ?: STDefaultTextColor();
    [self.textColorWell setColor:textColor];
    NSFont *textFont = [delegate preferencesControllerDefaultTextFont:self] ?: STDefaultTextFont();
    [self updateTextFontSummaryWithFont:textFont];

    NSString *directory = [delegate preferencesControllerDefaultSaveDirectory:self] ?: @"";
    [self.saveDirectoryField setStringValue:[directory stringByAbbreviatingWithTildeInPath]];

    BOOL showStatusBar = [delegate preferencesControllerShouldShowStatusBar:self];
    [self.statusBarCheckbox setState:showStatusBar ? NSControlStateValueOn : NSControlStateValueOff];
}

- (NSString *)displayStringForWidth:(CGFloat)width {
    return [NSString stringWithFormat:@"%.0f px", roundf(width)];
}

- (void)updateTextFontSummaryWithFont:(NSFont *)font {
    NSString *family = font.displayName ?: font.familyName ?: font.fontName ?: @"Font";
    CGFloat size = MAX(1.0f, font.pointSize);
    NSString *summary = [NSString stringWithFormat:@"%@ — %.0f pt", family, roundf(size)];
    [self.textFontSummaryLabel setStringValue:summary];
}

- (void)ensureWindowAccommodatesContent {
    NSView *content = self.window.contentView;
    if (!content) {
        return;
    }

    CGFloat minY = CGFLOAT_MAX;
    CGFloat maxY = 0.0f;
    CGFloat maxX = 0.0f;
    for (NSView *subview in content.subviews) {
        if (subview.isHidden) {
            continue;
        }
        NSRect frame = subview.frame;
        minY = MIN(minY, NSMinY(frame));
        maxY = MAX(maxY, NSMaxY(frame));
        maxX = MAX(maxX, NSMaxX(frame));
    }

    CGFloat bottomPadding = 20.0f;
    if (minY < bottomPadding) {
        CGFloat delta = bottomPadding - minY;
        for (NSView *subview in content.subviews) {
            NSRect frame = subview.frame;
            frame.origin.y += delta;
            [subview setFrame:frame];
        }
        maxY += delta;
    }

    CGFloat targetHeight = MAX(maxY + 20.0f, STPreferencesHeight);
    CGFloat targetWidth = MAX(maxX + 20.0f, STPreferencesWidth);

    NSSize currentSize = content.bounds.size;
    if (fabs(targetWidth - currentSize.width) > 0.5f ||
        fabs(targetHeight - currentSize.height) > 0.5f) {
        [self.window setContentSize:NSMakeSize(targetWidth, targetHeight)];
    }
}

- (void)chooseTextFont:(id)sender {
    (void)sender;
    NSFont *current = [self.delegate preferencesControllerDefaultTextFont:self] ?: STDefaultTextFont();
    NSFontManager *manager = [NSFontManager sharedFontManager];
    self.previousFirstResponder = self.window.firstResponder;
    [self.window makeFirstResponder:self];
    [manager setAction:@selector(changeFont:)];
    [manager orderFrontFontPanel:self];
    [[manager fontPanel:YES] setPanelFont:current isMultiple:NO];
}

- (void)changeFont:(id)sender {
    if (![sender isKindOfClass:[NSFontManager class]]) {
        return;
    }
    NSFontManager *manager = (NSFontManager *)sender;
    NSFont *baseFont = [self.delegate preferencesControllerDefaultTextFont:self] ?: STDefaultTextFont();
    NSFont *converted = [manager convertFont:baseFont];
    if (!converted) {
        return;
    }
    [self.delegate preferencesController:self didChangeDefaultTextFont:converted];
    [self updateTextFontSummaryWithFont:converted];
    if (self.previousFirstResponder) {
        if ([self.window makeFirstResponder:self.previousFirstResponder]) {
            self.previousFirstResponder = nil;
        }
    }
}

#pragma mark - Actions

- (void)penWidthSliderChanged:(NSSlider *)sender {
    CGFloat value = MAX(STToolWidthMin, MIN(STToolWidthMax, roundf(sender.doubleValue)));
    [sender setDoubleValue:value];
    [self.penWidthValueLabel setStringValue:[self displayStringForWidth:value]];
    [self.delegate preferencesController:self didChangeDefaultWidth:value forTool:ScreenshotCanvasToolPen];
}

- (void)highlighterWidthSliderChanged:(NSSlider *)sender {
    CGFloat value = MAX(STToolWidthMin, MIN(STToolWidthMax, roundf(sender.doubleValue)));
    [sender setDoubleValue:value];
    [self.highlighterWidthValueLabel setStringValue:[self displayStringForWidth:value]];
    [self.delegate preferencesController:self didChangeDefaultWidth:value forTool:ScreenshotCanvasToolHighlighter];
}

- (void)penQuickWidthPressed:(NSButton *)sender {
    CGFloat value = (CGFloat)sender.tag;
    [self.penWidthSlider setDoubleValue:value];
    [self.penWidthValueLabel setStringValue:[self displayStringForWidth:value]];
    [self.delegate preferencesController:self didChangeDefaultWidth:value forTool:ScreenshotCanvasToolPen];
}

- (void)highlighterQuickWidthPressed:(NSButton *)sender {
    CGFloat value = (CGFloat)sender.tag;
    [self.highlighterWidthSlider setDoubleValue:value];
    [self.highlighterWidthValueLabel setStringValue:[self displayStringForWidth:value]];
    [self.delegate preferencesController:self didChangeDefaultWidth:value forTool:ScreenshotCanvasToolHighlighter];
}

- (void)penColorChanged:(NSColorWell *)sender {
    NSColor *color = sender.color ?: STDefaultPenColor();
    [self.delegate preferencesController:self didChangeDefaultColor:color forTool:ScreenshotCanvasToolPen];
}

- (void)highlighterColorChanged:(NSColorWell *)sender {
    NSColor *color = sender.color ?: STDefaultHighlighterColor();
    [self.delegate preferencesController:self didChangeDefaultColor:color forTool:ScreenshotCanvasToolHighlighter];
}

- (void)textColorChanged:(NSColorWell *)sender {
    NSColor *color = sender.color ?: STDefaultTextColor();
    [self.delegate preferencesController:self didChangeDefaultTextColor:color];
}

- (void)chooseSaveDirectory:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setPrompt:@"Choose"];
    if ([panel runModal] == NSModalResponseOK) {
        NSURL *url = panel.URL;
        if (url) {
            [self.delegate preferencesController:self didChangeDefaultSaveDirectory:url.path];
        }
    }
}

- (void)statusBarToggled:(NSButton *)sender {
    BOOL show = (sender.state == NSControlStateValueOn);
    [self.delegate preferencesController:self didToggleStatusBar:show];
}

- (void)restoreDefaultsPressed:(id)sender {
    (void)sender;
    [self.delegate preferencesControllerRestoreDefaults:self];
    [self refresh];
}

- (void)closePressed:(id)sender {
    (void)sender;
    [self.window close];
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    self.previousFirstResponder = nil;
    if ([self.delegate respondsToSelector:@selector(preferencesControllerDidRequestClose:)]) {
        [self.delegate preferencesControllerDidRequestClose:self];
    }
}

@end
