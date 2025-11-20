#import "PreferencesWindowController.h"
#import "ScreenshotToolSettings.h"
#include <math.h>

static const CGFloat STPreferencesWidth = 560.0f;
static const CGFloat STPreferencesHeight = 580.0f;

@interface PreferencesWindowController () <NSWindowDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSTextField *drawingHeaderLabel;

@property (nonatomic, strong) NSTextField *penLabel;
@property (nonatomic, strong) NSTextField *penColorLabel;
@property (nonatomic, strong) NSSlider *penWidthSlider;
@property (nonatomic, strong) NSTextField *penWidthValueLabel;
@property (nonatomic, strong) NSArray<NSButton *> *penQuickButtons;
@property (nonatomic, strong) NSColorWell *penColorWell;

@property (nonatomic, strong) NSTextField *highlighterLabel;
@property (nonatomic, strong) NSTextField *highlighterColorLabel;
@property (nonatomic, strong) NSSlider *highlighterWidthSlider;
@property (nonatomic, strong) NSTextField *highlighterWidthValueLabel;
@property (nonatomic, strong) NSArray<NSButton *> *highlighterQuickButtons;
@property (nonatomic, strong) NSColorWell *highlighterColorWell;

@property (nonatomic, strong) NSTextField *textHeaderLabel;
@property (nonatomic, strong) NSTextField *textColorLabel;
@property (nonatomic, strong) NSTextField *textFontLabel;
@property (nonatomic, strong) NSColorWell *textColorWell;
@property (nonatomic, strong) NSTextField *textFontSummaryLabel;
@property (nonatomic, strong) NSButton *textFontButton;

@property (nonatomic, weak) NSResponder *previousFirstResponder;

@property (nonatomic, strong) NSTextField *workspaceHeaderLabel;
@property (nonatomic, strong) NSTextField *directoryLabel;
@property (nonatomic, strong) NSTextField *saveDirectoryField;
@property (nonatomic, strong) NSButton *chooseDirectoryButton;

@property (nonatomic, strong) NSTextField *interfaceHeaderLabel;
@property (nonatomic, strong) NSTextField *themeLabel;
@property (nonatomic, strong) NSButton *statusBarCheckbox;
@property (nonatomic, strong) NSPopUpButton *interfaceThemePopUp;
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
                                                         NSWindowStyleMaskMiniaturizable |
                                                         NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [self.window setReleasedWhenClosed:NO];
    self.window.title = @"Preferences";
    self.window.delegate = self;

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, STPreferencesWidth, STPreferencesHeight)];
    self.contentView = content;
    [self.window setContentView:content];

    self.drawingHeaderLabel = [self headerLabelWithString:@"Drawing Defaults"];
    [content addSubview:self.drawingHeaderLabel];

    self.penLabel = [self fieldLabelWithString:@"Pen" frame:NSZeroRect];
    [self.penLabel setFont:[NSFont boldSystemFontOfSize:12.0f]];
    [content addSubview:self.penLabel];

    self.penWidthSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    [self.penWidthSlider setMinValue:STToolWidthMin];
    [self.penWidthSlider setMaxValue:STToolWidthMax];
    [self.penWidthSlider setNumberOfTickMarks:0];
    [self.penWidthSlider setContinuous:YES];
    [self.penWidthSlider setTarget:self];
    [self.penWidthSlider setAction:@selector(penWidthSliderChanged:)];
    [content addSubview:self.penWidthSlider];

    self.penWidthValueLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [self configureSummaryLabel:self.penWidthValueLabel];
    [self.penWidthValueLabel setAlignment:NSTextAlignmentRight];
    [self.penWidthValueLabel setStringValue:@"0 px"];
    [content addSubview:self.penWidthValueLabel];

    NSMutableArray<NSButton *> *penButtons = [[NSMutableArray alloc] initWithCapacity:3];
    for (NSNumber *value in @[@2.0f, @4.0f, @6.0f]) {
        NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
        [button setButtonType:NSMomentaryPushInButton];
        [button setBezelStyle:NSTexturedRoundedBezelStyle];
        [button setTitle:[NSString stringWithFormat:@"%.0f", value.doubleValue]];
        [button setTag:(NSInteger)lrint(value.doubleValue)];
        [button setTarget:self];
        [button setAction:@selector(penQuickWidthPressed:)];
        [content addSubview:button];
        [penButtons addObject:button];
    }
    self.penQuickButtons = penButtons;

    self.penColorLabel = [self fieldLabelWithString:@"Color" frame:NSZeroRect];
    [content addSubview:self.penColorLabel];

    self.penColorWell = [[NSColorWell alloc] initWithFrame:NSZeroRect];
    [self.penColorWell setTarget:self];
    [self.penColorWell setAction:@selector(penColorChanged:)];
    [content addSubview:self.penColorWell];

    self.highlighterLabel = [self fieldLabelWithString:@"Highlighter" frame:NSZeroRect];
    [self.highlighterLabel setFont:[NSFont boldSystemFontOfSize:12.0f]];
    [content addSubview:self.highlighterLabel];

    self.highlighterWidthSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    [self.highlighterWidthSlider setMinValue:STToolWidthMin];
    [self.highlighterWidthSlider setMaxValue:STToolWidthMax];
    [self.highlighterWidthSlider setNumberOfTickMarks:0];
    [self.highlighterWidthSlider setContinuous:YES];
    [self.highlighterWidthSlider setTarget:self];
    [self.highlighterWidthSlider setAction:@selector(highlighterWidthSliderChanged:)];
    [content addSubview:self.highlighterWidthSlider];

    self.highlighterWidthValueLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [self configureSummaryLabel:self.highlighterWidthValueLabel];
    [self.highlighterWidthValueLabel setAlignment:NSTextAlignmentRight];
    [self.highlighterWidthValueLabel setStringValue:@"0 px"];
    [content addSubview:self.highlighterWidthValueLabel];

    NSMutableArray<NSButton *> *highlighterButtons = [[NSMutableArray alloc] initWithCapacity:3];
    for (NSNumber *value in @[@8.0f, @12.0f, @20.0f]) {
        NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
        [button setButtonType:NSMomentaryPushInButton];
        [button setBezelStyle:NSTexturedRoundedBezelStyle];
        [button setTitle:[NSString stringWithFormat:@"%.0f", value.doubleValue]];
        [button setTag:(NSInteger)lrint(value.doubleValue)];
        [button setTarget:self];
        [button setAction:@selector(highlighterQuickWidthPressed:)];
        [content addSubview:button];
        [highlighterButtons addObject:button];
    }
    self.highlighterQuickButtons = highlighterButtons;

    self.highlighterColorLabel = [self fieldLabelWithString:@"Color" frame:NSZeroRect];
    [content addSubview:self.highlighterColorLabel];

    self.highlighterColorWell = [[NSColorWell alloc] initWithFrame:NSZeroRect];
    [self.highlighterColorWell setTarget:self];
    [self.highlighterColorWell setAction:@selector(highlighterColorChanged:)];
    [content addSubview:self.highlighterColorWell];

    self.textHeaderLabel = [self headerLabelWithString:@"Text Defaults"];
    [content addSubview:self.textHeaderLabel];

    self.textColorLabel = [self fieldLabelWithString:@"Color" frame:NSZeroRect];
    [content addSubview:self.textColorLabel];

    self.textColorWell = [[NSColorWell alloc] initWithFrame:NSZeroRect];
    [self.textColorWell setTarget:self];
    [self.textColorWell setAction:@selector(textColorChanged:)];
    [content addSubview:self.textColorWell];

    self.textFontLabel = [self fieldLabelWithString:@"Font" frame:NSZeroRect];
    [content addSubview:self.textFontLabel];

    self.textFontSummaryLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [self configureSummaryLabel:self.textFontSummaryLabel];
    [self.textFontSummaryLabel setAlignment:NSTextAlignmentLeft];
    [self.textFontSummaryLabel setStringValue:@"Current font"];
    [content addSubview:self.textFontSummaryLabel];

    self.textFontButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [self.textFontButton setTitle:@"Choose Font…"];
    [self.textFontButton setButtonType:NSMomentaryPushInButton];
    [self.textFontButton setBezelStyle:NSRoundedBezelStyle];
    [self.textFontButton setTarget:self];
    [self.textFontButton setAction:@selector(chooseTextFont:)];
    [content addSubview:self.textFontButton];

    self.workspaceHeaderLabel = [self headerLabelWithString:@"Workspace"];
    [content addSubview:self.workspaceHeaderLabel];

    self.directoryLabel = [self fieldLabelWithString:@"Default Save Folder" frame:NSZeroRect];
    [self.directoryLabel setAlignment:NSTextAlignmentLeft];
    [content addSubview:self.directoryLabel];

    self.saveDirectoryField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [self.saveDirectoryField setEditable:NO];
    [self.saveDirectoryField setBezeled:YES];
    [self.saveDirectoryField setBordered:YES];
    [self.saveDirectoryField setDrawsBackground:YES];
    [self.saveDirectoryField setFont:[NSFont systemFontOfSize:12.0f]];
    [content addSubview:self.saveDirectoryField];

    self.chooseDirectoryButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [self.chooseDirectoryButton setTitle:@"Choose…"];
    [self.chooseDirectoryButton setButtonType:NSMomentaryPushInButton];
    [self.chooseDirectoryButton setBezelStyle:NSRoundedBezelStyle];
    [self.chooseDirectoryButton setTarget:self];
    [self.chooseDirectoryButton setAction:@selector(chooseSaveDirectory:)];
    [content addSubview:self.chooseDirectoryButton];

    self.interfaceHeaderLabel = [self headerLabelWithString:@"Interface"];
    [content addSubview:self.interfaceHeaderLabel];

    self.statusBarCheckbox = [[NSButton alloc] initWithFrame:NSZeroRect];
    [self.statusBarCheckbox setButtonType:NSSwitchButton];
    [self.statusBarCheckbox setTitle:@"Show status bar"];
    [self.statusBarCheckbox setTarget:self];
    [self.statusBarCheckbox setAction:@selector(statusBarToggled:)];
    [content addSubview:self.statusBarCheckbox];

    self.themeLabel = [self fieldLabelWithString:@"Toolbar Theme" frame:NSZeroRect];
    [content addSubview:self.themeLabel];

    self.interfaceThemePopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.interfaceThemePopUp setTarget:self];
    [self.interfaceThemePopUp setAction:@selector(interfaceThemeSelectionChanged:)];
    [self.interfaceThemePopUp removeAllItems];
    [self.interfaceThemePopUp addItemWithTitle:@"Light"];
    [[self.interfaceThemePopUp itemAtIndex:0] setTag:0];
    [self.interfaceThemePopUp addItemWithTitle:@"Dark"];
    [[self.interfaceThemePopUp itemAtIndex:1] setTag:1];
    [content addSubview:self.interfaceThemePopUp];

    self.restoreDefaultsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [self.restoreDefaultsButton setTitle:@"Restore Defaults"];
    [self.restoreDefaultsButton setButtonType:NSMomentaryPushInButton];
    [self.restoreDefaultsButton setBezelStyle:NSRoundedBezelStyle];
    [self.restoreDefaultsButton setTarget:self];
    [self.restoreDefaultsButton setAction:@selector(restoreDefaultsPressed:)];
    [content addSubview:self.restoreDefaultsButton];

    self.closeButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [self.closeButton setTitle:@"Close"];
    [self.closeButton setButtonType:NSMomentaryPushInButton];
    [self.closeButton setBezelStyle:NSRoundedBezelStyle];
    [self.closeButton setTarget:self];
    [self.closeButton setAction:@selector(closePressed:)];
    [content addSubview:self.closeButton];

    [self.window setContentMinSize:NSMakeSize(STPreferencesWidth, STPreferencesHeight)];
    [self layoutContentView];
}

- (NSTextField *)headerLabelWithString:(NSString *)string {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, STPreferencesWidth - 40.0f, 22.0f)];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setSelectable:NO];
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
    [label setSelectable:NO];
    [label setFont:[NSFont systemFontOfSize:12.0f]];
    [label setStringValue:string ?: @""];
    return label;
}

- (void)configureSummaryLabel:(NSTextField *)label {
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setSelectable:NO];
    [label setFont:[NSFont systemFontOfSize:12.0f]];
}

- (void)layoutContentView {
    NSView *content = self.contentView ?: self.window.contentView;
    if (!content) {
        return;
    }

    CGFloat padding = 20.0f;
    CGFloat headerSpacing = 8.0f;
    CGFloat sectionSpacing = 18.0f;
    CGFloat labelWidth = 110.0f;
    CGFloat valueWidth = 72.0f;
    CGFloat contentWidth = MAX(420.0f, content.bounds.size.width - (padding * 2.0f));
    CGFloat headerHeight = 22.0f;

    CGFloat y = content.bounds.size.height - padding;

    // Drawing Defaults
    [self.drawingHeaderLabel setFrame:NSMakeRect(padding, y - headerHeight, contentWidth, headerHeight)];
    y -= (headerHeight + headerSpacing);

    y = [self layoutToolSectionWithLabel:self.penLabel
                                   slider:self.penWidthSlider
                              valueLabel:self.penWidthValueLabel
                             quickButtons:self.penQuickButtons
                              colorLabel:self.penColorLabel
                               colorWell:self.penColorWell
                                      y:y
                            contentWidth:contentWidth
                                 padding:padding
                              labelWidth:labelWidth
                              valueWidth:valueWidth];

    y = [self layoutToolSectionWithLabel:self.highlighterLabel
                                   slider:self.highlighterWidthSlider
                              valueLabel:self.highlighterWidthValueLabel
                             quickButtons:self.highlighterQuickButtons
                              colorLabel:self.highlighterColorLabel
                               colorWell:self.highlighterColorWell
                                      y:y
                            contentWidth:contentWidth
                                 padding:padding
                              labelWidth:labelWidth
                              valueWidth:valueWidth];

    y -= sectionSpacing;

    // Text Defaults
    [self.textHeaderLabel setFrame:NSMakeRect(padding, y - headerHeight, contentWidth, headerHeight)];
    y -= (headerHeight + headerSpacing);

    CGFloat colorWellWidth = 52.0f;
    CGFloat colorWellHeight = 30.0f;
    CGFloat colorRowHeight = colorWellHeight;
    CGFloat colorRowY = y - colorRowHeight;
    [self.textColorLabel setFrame:NSMakeRect(padding, colorRowY + 6.0f, labelWidth, 20.0f)];
    [self.textColorWell setFrame:NSMakeRect(padding + labelWidth + 12.0f,
                                            colorRowY - 2.0f,
                                            colorWellWidth,
                                            colorWellHeight)];
    y = colorRowY - headerSpacing;

    CGFloat fontButtonWidth = 140.0f;
    CGFloat fontButtonHeight = 28.0f;
    CGFloat fontRowHeight = fontButtonHeight;
    CGFloat fontRowY = y - fontRowHeight;
    CGFloat fontSummaryWidth = MAX(160.0f, contentWidth - labelWidth - fontButtonWidth - 32.0f);
    [self.textFontLabel setFrame:NSMakeRect(padding, fontRowY + 4.0f, labelWidth, 20.0f)];
    [self.textFontSummaryLabel setFrame:NSMakeRect(padding + labelWidth + 12.0f,
                                                   fontRowY + 4.0f,
                                                   fontSummaryWidth,
                                                   20.0f)];
    [self.textFontButton setFrame:NSMakeRect(padding + labelWidth + 12.0f + fontSummaryWidth + 12.0f,
                                             fontRowY,
                                             fontButtonWidth,
                                             fontButtonHeight)];
    y = fontRowY - sectionSpacing;

    // Workspace
    [self.workspaceHeaderLabel setFrame:NSMakeRect(padding, y - headerHeight, contentWidth, headerHeight)];
    y -= (headerHeight + headerSpacing);

    [self.directoryLabel setFrame:NSMakeRect(padding, y - 18.0f, contentWidth, 18.0f)];
    y -= (18.0f + 8.0f);

    CGFloat chooseWidth = 110.0f;
    CGFloat fieldHeight = 26.0f;
    CGFloat fieldY = y - fieldHeight;
    CGFloat fieldWidth = MAX(160.0f, contentWidth - chooseWidth - 10.0f);
    [self.saveDirectoryField setFrame:NSMakeRect(padding, fieldY, fieldWidth, fieldHeight)];
    [self.chooseDirectoryButton setFrame:NSMakeRect(padding + fieldWidth + 10.0f,
                                                    fieldY - 1.0f,
                                                    chooseWidth,
                                                    fieldHeight)];
    y = fieldY - sectionSpacing;

    // Interface
    [self.interfaceHeaderLabel setFrame:NSMakeRect(padding, y - headerHeight, contentWidth, headerHeight)];
    y -= (headerHeight + headerSpacing);

    CGFloat checkboxHeight = 24.0f;
    CGFloat checkboxY = y - checkboxHeight;
    [self.statusBarCheckbox setFrame:NSMakeRect(padding, checkboxY, contentWidth, checkboxHeight)];
    y = checkboxY - headerSpacing;

    CGFloat themeRowHeight = 26.0f;
    CGFloat themeRowY = y - themeRowHeight;
    CGFloat themeLabelWidth = labelWidth + 40.0f;
    CGFloat popupWidth = 200.0f;
    [self.themeLabel setFrame:NSMakeRect(padding, themeRowY + 4.0f, themeLabelWidth, 20.0f)];
    [self.interfaceThemePopUp setFrame:NSMakeRect(padding + themeLabelWidth + 12.0f,
                                                  themeRowY - 1.0f,
                                                  popupWidth,
                                                  themeRowHeight)];

    // Footer buttons pinned to bottom
    CGFloat footerHeight = 32.0f;
    CGFloat footerY = padding;
    [self.restoreDefaultsButton setFrame:NSMakeRect(padding, footerY, 170.0f, footerHeight)];
    [self.closeButton setFrame:NSMakeRect(padding + contentWidth - 110.0f, footerY, 110.0f, footerHeight)];
}

- (CGFloat)layoutToolSectionWithLabel:(NSTextField *)label
                               slider:(NSSlider *)slider
                          valueLabel:(NSTextField *)valueLabel
                         quickButtons:(NSArray<NSButton *> *)quickButtons
                          colorLabel:(NSTextField *)colorLabel
                           colorWell:(NSColorWell *)colorWell
                                  y:(CGFloat)y
                        contentWidth:(CGFloat)contentWidth
                             padding:(CGFloat)padding
                          labelWidth:(CGFloat)labelWidth
                          valueWidth:(CGFloat)valueWidth {
    if (!label || !slider || !valueLabel || !colorLabel || !colorWell) {
        return y;
    }

    CGFloat sliderHeight = 22.0f;
    CGFloat sliderSpacing = 12.0f;
    CGFloat valueHeight = 18.0f;
    CGFloat rowSpacing = 8.0f;
    CGFloat quickHeight = 26.0f;
    CGFloat quickSpacing = 8.0f;
    CGFloat postSpacing = 12.0f;
    CGFloat colorLabelWidth = 50.0f;
    CGFloat colorWellWidth = 52.0f;

    CGFloat sliderWidth = MAX(180.0f, contentWidth - labelWidth - valueWidth - (sliderSpacing * 2.0f));
    CGFloat sliderRowY = y - sliderHeight;
    [label setFrame:NSMakeRect(padding, sliderRowY + 2.0f, labelWidth, 20.0f)];
    [slider setFrame:NSMakeRect(padding + labelWidth + sliderSpacing, sliderRowY, sliderWidth, sliderHeight)];
    [valueLabel setFrame:NSMakeRect(NSMaxX(slider.frame) + sliderSpacing, sliderRowY + 2.0f, valueWidth, valueHeight)];

    CGFloat quickRowY = sliderRowY - rowSpacing - quickHeight;

    CGFloat colorWellX = padding + contentWidth - colorWellWidth;
    CGFloat colorLabelX = colorWellX - 6.0f - colorLabelWidth;
    [colorLabel setFrame:NSMakeRect(colorLabelX, quickRowY + 4.0f, colorLabelWidth, 18.0f)];
    [colorWell setFrame:NSMakeRect(colorWellX, quickRowY - 2.0f, colorWellWidth, 30.0f)];

    CGFloat quickStartX = padding + labelWidth;
    CGFloat quickEndX = colorLabelX - 10.0f;
    CGFloat availableQuickWidth = MAX(0.0f, quickEndX - quickStartX);
    CGFloat quickButtonWidth = 0.0f;
    NSInteger count = (NSInteger)quickButtons.count;
    if (count > 0) {
        quickButtonWidth = (availableQuickWidth - (quickSpacing * (count - 1))) / (CGFloat)count;
        quickButtonWidth = MIN(64.0f, MAX(44.0f, quickButtonWidth));
    }
    CGFloat quickX = quickStartX;
    for (NSButton *button in quickButtons) {
        [button setFrame:NSMakeRect(quickX, quickRowY, quickButtonWidth, quickHeight)];
        quickX += quickButtonWidth + quickSpacing;
    }

    return quickRowY - postSpacing;
}

- (void)showRelativeToWindow:(NSWindow *)window {
    if (!self.window) {
        return;
    }
    [self layoutContentView];
    [self refresh];
    if (window) {
        NSRect parentFrame = window.frame;
        NSSize size = self.window.frame.size;
        NSPoint origin = NSMakePoint(NSMidX(parentFrame) - (size.width / 2.0f),
                                     NSMidY(parentFrame) - (size.height / 2.0f));
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

    BOOL prefersDark = [delegate preferencesControllerPrefersDarkInterface:self];
    NSInteger themeTag = prefersDark ? 1 : 0;
    if ([self.interfaceThemePopUp indexOfItemWithTag:themeTag] != -1) {
        [self.interfaceThemePopUp selectItemWithTag:themeTag];
    }
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

- (void)interfaceThemeSelectionChanged:(NSPopUpButton *)sender {
    NSInteger tag = sender.selectedTag;
    BOOL prefersDark = (tag == 1);
    [self.delegate preferencesController:self didChangePrefersDarkInterface:prefersDark];
}

- (void)restoreDefaultsPressed:(id)sender {
    (void)sender;
    [self.delegate preferencesControllerRestoreDefaults:self];
    [self refresh];
}

- (void)closePressed:(id)sender {
    (void)sender;
    [self.window orderOut:nil];
}

#pragma mark - NSWindowDelegate

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    [self layoutContentView];
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    self.previousFirstResponder = nil;
    if ([self.delegate respondsToSelector:@selector(preferencesControllerDidRequestClose:)]) {
        [self.delegate preferencesControllerDidRequestClose:self];
    }
}

@end
