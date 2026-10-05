#import "PreferencesWindowController.h"
#import "ScreenshotToolSettings.h"
#import "STThemeUtilities.h"
#import <AppKit/NSSegmentedCell.h>
#include <math.h>

static const CGFloat STPreferencesWidth = 760.0f;
static const CGFloat STPreferencesHeight = 500.0f;

typedef NS_ENUM(NSInteger, STPreferencesSection) {
    STPreferencesSectionAppearance = 0,
    STPreferencesSectionDrawing = 1,
    STPreferencesSectionText = 2,
    STPreferencesSectionWorkspace = 3,
};

@interface STPreferencesBackgroundView : NSView
@property (nonatomic, assign) NSRect contentCardRect;
@end

/// Lays out the page; draws nothing of its own, so the window looks however the theme draws it (#56).
@implementation STPreferencesBackgroundView
@end

@interface PreferencesWindowController () <NSWindowDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) STPreferencesBackgroundView *backgroundView;
@property (nonatomic, strong) NSSegmentedControl *sectionControl;
@property (nonatomic, strong) NSTextField *pageTitleLabel;
@property (nonatomic, strong) NSTextField *pageDescriptionLabel;
@property (nonatomic, assign) STPreferencesSection currentSection;
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
@property (nonatomic, strong) NSTextField *statusBarLabel;
@property (nonatomic, strong) NSSwitch *statusBarSwitch;
@property (nonatomic, strong) NSButton *restoreDefaultsButton;
@end

@implementation PreferencesWindowController

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (instancetype)initWithDelegate:(id<PreferencesWindowControllerDelegate>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
        _currentSection = STPreferencesSectionAppearance;
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
    [self.window setBackgroundColor:STThemeWindowBackgroundColor()];

    STPreferencesBackgroundView *content = [[STPreferencesBackgroundView alloc] initWithFrame:NSMakeRect(0, 0, STPreferencesWidth, STPreferencesHeight)];
    self.backgroundView = content;
    self.contentView = content;
    [self.window setContentView:content];

    self.sectionControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    [self.sectionControl setSegmentCount:4];
    [self.sectionControl setLabel:@"Appearance" forSegment:0];
    [self.sectionControl setLabel:@"Drawing" forSegment:1];
    [self.sectionControl setLabel:@"Text" forSegment:2];
    [self.sectionControl setLabel:@"Workspace" forSegment:3];
    [(NSSegmentedCell *)[self.sectionControl cell] setTrackingMode:NSSegmentSwitchTrackingSelectOne];
    [self.sectionControl setSelectedSegment:self.currentSection];
    [self.sectionControl setTarget:self];
    [self.sectionControl setAction:@selector(sectionSelectionChanged:)];
    [content addSubview:self.sectionControl];

    self.pageTitleLabel = [self headerLabelWithString:@"Appearance"];
    [self.pageTitleLabel setFont:[NSFont boldSystemFontOfSize:18.0f]];
    [content addSubview:self.pageTitleLabel];

    self.pageDescriptionLabel = [self fieldLabelWithString:@"" frame:NSZeroRect];
    [self.pageDescriptionLabel setFont:[NSFont systemFontOfSize:13.0f]];
    [[self.pageDescriptionLabel cell] setWraps:YES];
    [[self.pageDescriptionLabel cell] setScrollable:NO];
    [[self.pageDescriptionLabel cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [content addSubview:self.pageDescriptionLabel];

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
        [button setBezelStyle:NSRoundedBezelStyle];
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
        [button setBezelStyle:NSRoundedBezelStyle];
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

    // On/off settings are switches, labelled on the left: standard controls the theme draws (#56).
    self.statusBarLabel = [self fieldLabelWithString:@"Show status bar" frame:NSZeroRect];
    [self.statusBarLabel setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
    [content addSubview:self.statusBarLabel];
    self.statusBarSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    [self.statusBarSwitch setTarget:self];
    [self.statusBarSwitch setAction:@selector(statusBarToggled:)];
    [content addSubview:self.statusBarSwitch];

    self.restoreDefaultsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [self.restoreDefaultsButton setTitle:@"Restore Defaults"];
    [self.restoreDefaultsButton setButtonType:NSMomentaryPushInButton];
    [self.restoreDefaultsButton setBezelStyle:NSRoundedBezelStyle];
    [self.restoreDefaultsButton setTarget:self];
    [self.restoreDefaultsButton setAction:@selector(restoreDefaultsPressed:)];
    [content addSubview:self.restoreDefaultsButton];

    [self.window setContentMinSize:NSMakeSize(STPreferencesWidth, STPreferencesHeight)];
    [self layoutContentView];
    [self applyThemeAppearance];
}

- (NSTextField *)headerLabelWithString:(NSString *)string {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, STPreferencesWidth - 40.0f, 22.0f)];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setSelectable:NO];
    [label setFont:[NSFont boldSystemFontOfSize:14.0f]];
    [label setTextColor:STThemeSectionHeaderColor()];
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
    [label setTextColor:STThemeSecondaryTextColor()];
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
    [label setTextColor:STThemePrimaryTextColor()];
}

- (NSString *)titleForSection:(STPreferencesSection)section {
    switch (section) {
        case STPreferencesSectionAppearance:
            return @"Appearance";
        case STPreferencesSectionDrawing:
            return @"Drawing Defaults";
        case STPreferencesSectionText:
            return @"Text Defaults";
        case STPreferencesSectionWorkspace:
            return @"Workspace";
    }
    return @"Preferences";
}

- (NSString *)descriptionForSection:(STPreferencesSection)section {
    switch (section) {
        case STPreferencesSectionAppearance:
            return @"Choose which parts of the window to show.";
        case STPreferencesSectionDrawing:
            return @"Set the default stroke width and color for the pen and highlighter tools.";
        case STPreferencesSectionText:
            return @"Choose the default color and typeface used when you add text annotations.";
        case STPreferencesSectionWorkspace:
            return @"Pick the folder used when saving screenshots and exports by default.";
    }
    return @"";
}

- (void)setViews:(NSArray<NSView *> *)views hidden:(BOOL)hidden {
    for (NSView *view in views) {
        [view setHidden:hidden];
    }
}

- (void)hideAllPageControls {
    [self setViews:@[
        self.drawingHeaderLabel,
        self.penLabel,
        self.penWidthSlider,
        self.penWidthValueLabel,
        self.penColorLabel,
        self.penColorWell,
        self.highlighterLabel,
        self.highlighterWidthSlider,
        self.highlighterWidthValueLabel,
        self.highlighterColorLabel,
        self.highlighterColorWell,
        self.textHeaderLabel,
        self.textColorLabel,
        self.textColorWell,
        self.textFontLabel,
        self.textFontSummaryLabel,
        self.textFontButton,
        self.workspaceHeaderLabel,
        self.directoryLabel,
        self.saveDirectoryField,
        self.chooseDirectoryButton,
        self.interfaceHeaderLabel,
        self.statusBarLabel,
        self.statusBarSwitch
    ] hidden:YES];
    [self setViews:self.penQuickButtons hidden:YES];
    [self setViews:self.highlighterQuickButtons hidden:YES];
}

- (void)applyThemeAppearance {
    [self.window setBackgroundColor:STThemeWindowBackgroundColor()];
    [self.sectionControl setSelectedSegment:self.currentSection];
    [self.pageTitleLabel setTextColor:STThemePrimaryTextColor()];
    [self.pageDescriptionLabel setTextColor:STThemeSecondaryTextColor()];
    [self.drawingHeaderLabel setTextColor:STThemeSectionHeaderColor()];
    [self.textHeaderLabel setTextColor:STThemeSectionHeaderColor()];
    [self.workspaceHeaderLabel setTextColor:STThemeSectionHeaderColor()];
    [self.interfaceHeaderLabel setTextColor:STThemeSectionHeaderColor()];
    [self.penColorLabel setTextColor:STThemeSecondaryTextColor()];
    [self.highlighterColorLabel setTextColor:STThemeSecondaryTextColor()];
    [self.saveDirectoryField setBackgroundColor:STThemeInsetBackgroundColor()];
    [self.saveDirectoryField setTextColor:STThemePrimaryTextColor()];
    [self.textFontSummaryLabel setTextColor:STThemePrimaryTextColor()];
    [self.penWidthValueLabel setTextColor:STThemePrimaryTextColor()];
    [self.highlighterWidthValueLabel setTextColor:STThemePrimaryTextColor()];
    [self.statusBarLabel setTextColor:STThemePrimaryTextColor()];
    [self.directoryLabel setTextColor:STThemeSecondaryTextColor()];
    [self.textColorLabel setTextColor:STThemeSecondaryTextColor()];
    [self.textFontLabel setTextColor:STThemeSecondaryTextColor()];
    [self.penLabel setTextColor:STThemePrimaryTextColor()];
    [self.highlighterLabel setTextColor:STThemePrimaryTextColor()];
    [self.pageTitleLabel setStringValue:[self titleForSection:self.currentSection]];
    [self.pageDescriptionLabel setStringValue:[self descriptionForSection:self.currentSection]];
}

- (void)layoutContentView {
    NSView *content = self.contentView ?: self.window.contentView;
    if (!content) {
        return;
    }

    CGFloat outerPadding = 24.0f;
    CGFloat switcherHeight = 40.0f;
    CGFloat switcherGap = 16.0f;
    CGFloat cardInnerPadding = 28.0f;
    CGFloat footerHeight = 32.0f;
    CGFloat footerInset = 24.0f;
    CGFloat contentWidth = MAX(620.0f, content.bounds.size.width - (outerPadding * 2.0f));

    CGFloat switcherY = content.bounds.size.height - outerPadding - switcherHeight;
    [self.sectionControl setFrame:NSMakeRect(outerPadding, switcherY, contentWidth, switcherHeight)];
    CGFloat segmentWidth = floor(contentWidth / 4.0f);
    for (NSInteger segment = 0; segment < 4; segment++) {
        CGFloat width = (segment == 3) ? (contentWidth - (segmentWidth * 3.0f)) : segmentWidth;
        [self.sectionControl setWidth:width forSegment:segment];
    }

    NSRect cardRect = NSMakeRect(outerPadding,
                                 outerPadding,
                                 contentWidth,
                                 MAX(220.0f, switcherY - switcherGap - outerPadding));
    self.backgroundView.contentCardRect = cardRect;

    CGFloat innerX = NSMinX(cardRect) + cardInnerPadding;
    CGFloat innerWidth = NSWidth(cardRect) - (cardInnerPadding * 2.0f);
    CGFloat y = NSMaxY(cardRect) - cardInnerPadding;

    [self.pageTitleLabel setFrame:NSMakeRect(innerX, y - 28.0f, innerWidth, 28.0f)];
    y -= 34.0f;
    [self.pageDescriptionLabel setFrame:NSMakeRect(innerX, y - 36.0f, innerWidth, 36.0f)];
    y -= 52.0f;

    CGFloat footerY = NSMinY(cardRect) + footerInset;
    [self.restoreDefaultsButton setFrame:NSMakeRect(innerX, footerY, 150.0f, footerHeight)];

    [self hideAllPageControls];

    CGFloat rowLabelWidth = 138.0f;
    CGFloat valueWidth = 72.0f;
    CGFloat contentBottom = footerY + footerHeight + 20.0f;

    switch (self.currentSection) {
        case STPreferencesSectionAppearance: {
            // Label on the left, switch on the right, a row each.
            CGFloat switchWidth = 44.0f;
            CGFloat switchHeight = 24.0f;
            CGFloat rowHeight = 28.0f;
            CGFloat switchX = innerX + innerWidth - switchWidth;
            CGFloat labelWidth = innerWidth - switchWidth - 16.0f;
            [self setViews:@[self.statusBarLabel, self.statusBarSwitch] hidden:NO];
            [self.statusBarLabel setFrame:NSMakeRect(innerX, y - rowHeight + 4.0f, labelWidth, 20.0f)];
            [self.statusBarSwitch setFrame:NSMakeRect(switchX, y - rowHeight + 2.0f, switchWidth, switchHeight)];
            break;
        }

        case STPreferencesSectionDrawing: {
            [self setViews:@[
                self.penLabel,
                self.penWidthSlider,
                self.penWidthValueLabel,
                self.penColorLabel,
                self.penColorWell,
                self.highlighterLabel,
                self.highlighterWidthSlider,
                self.highlighterWidthValueLabel,
                self.highlighterColorLabel,
                self.highlighterColorWell
            ] hidden:NO];
            [self setViews:self.penQuickButtons hidden:NO];
            [self setViews:self.highlighterQuickButtons hidden:NO];

            y = [self layoutToolSectionWithLabel:self.penLabel
                                          slider:self.penWidthSlider
                                     valueLabel:self.penWidthValueLabel
                                    quickButtons:self.penQuickButtons
                                     colorLabel:self.penColorLabel
                                      colorWell:self.penColorWell
                                             y:y
                                   contentWidth:innerWidth
                                        padding:innerX
                                     labelWidth:rowLabelWidth
                                     valueWidth:valueWidth];
            y -= 18.0f;
            if (y > contentBottom) {
                y = [self layoutToolSectionWithLabel:self.highlighterLabel
                                              slider:self.highlighterWidthSlider
                                         valueLabel:self.highlighterWidthValueLabel
                                        quickButtons:self.highlighterQuickButtons
                                         colorLabel:self.highlighterColorLabel
                                          colorWell:self.highlighterColorWell
                                                 y:y
                                       contentWidth:innerWidth
                                            padding:innerX
                                         labelWidth:rowLabelWidth
                                         valueWidth:valueWidth];
            }
            break;
        }

        case STPreferencesSectionText: {
            [self setViews:@[self.textColorLabel, self.textColorWell, self.textFontLabel, self.textFontSummaryLabel, self.textFontButton] hidden:NO];
            CGFloat colorRowY = y - 30.0f;
            [self.textColorLabel setFrame:NSMakeRect(innerX, colorRowY + 5.0f, rowLabelWidth, 20.0f)];
            [self.textColorWell setFrame:NSMakeRect(innerX + rowLabelWidth + 16.0f, colorRowY - 1.0f, 54.0f, 32.0f)];
            y = colorRowY - 24.0f;

            CGFloat fontButtonWidth = 140.0f;
            CGFloat fontRowY = y - 30.0f;
            CGFloat summaryWidth = MAX(170.0f, innerWidth - rowLabelWidth - fontButtonWidth - 28.0f);
            [self.textFontLabel setFrame:NSMakeRect(innerX, fontRowY + 5.0f, rowLabelWidth, 20.0f)];
            [self.textFontSummaryLabel setFrame:NSMakeRect(innerX + rowLabelWidth + 16.0f, fontRowY + 5.0f, summaryWidth, 20.0f)];
            [self.textFontButton setFrame:NSMakeRect(NSMaxX(cardRect) - cardInnerPadding - fontButtonWidth,
                                                     fontRowY - 1.0f,
                                                     fontButtonWidth,
                                                     30.0f)];
            break;
        }

        case STPreferencesSectionWorkspace: {
            [self setViews:@[self.directoryLabel, self.saveDirectoryField, self.chooseDirectoryButton] hidden:NO];
            [self.directoryLabel setFrame:NSMakeRect(innerX, y - 18.0f, innerWidth, 18.0f)];
            y -= 28.0f;
            CGFloat chooseWidth = 116.0f;
            CGFloat fieldRowY = y - 30.0f;
            CGFloat fieldWidth = MAX(180.0f, innerWidth - chooseWidth - 12.0f);
            [self.saveDirectoryField setFrame:NSMakeRect(innerX, fieldRowY, fieldWidth, 30.0f)];
            [self.chooseDirectoryButton setFrame:NSMakeRect(innerX + fieldWidth + 12.0f, fieldRowY - 1.0f, chooseWidth, 30.0f)];
            break;
        }
    }
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
    // Never narrower than the theme needs for the widest title, or two-digit widths get clipped.
    for (NSButton *button in quickButtons) {
        quickButtonWidth = MAX(quickButtonWidth, ceil([[button cell] cellSize].width));
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
    [self applyThemeAppearance];
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
    [self.statusBarSwitch setState:showStatusBar ? NSControlStateValueOn : NSControlStateValueOff];
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

- (void)sectionSelectionChanged:(NSSegmentedControl *)sender {
    NSInteger selectedSegment = sender.selectedSegment;
    if (selectedSegment < STPreferencesSectionAppearance || selectedSegment > STPreferencesSectionWorkspace) {
        return;
    }
    self.currentSection = (STPreferencesSection)selectedSegment;
    [self applyThemeAppearance];
    [self layoutContentView];
}

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

- (void)statusBarToggled:(NSSwitch *)sender {
    BOOL show = (sender.state == NSControlStateValueOn);
    [self.delegate preferencesController:self didToggleStatusBar:show];
}

- (void)restoreDefaultsPressed:(id)sender {
    (void)sender;
    if (![self confirmRestoreDefaults]) {
        return;
    }
    [self.delegate preferencesControllerRestoreDefaults:self];
    [self refresh];
}

/// Changes apply as they're made, so there's no Close button; restoring defaults asks first.
- (BOOL)confirmRestoreDefaults {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Restore the default settings?";
    alert.informativeText = @"Tool widths, colours, the text font, the save folder and the window options go back to their defaults.";
    [alert addButtonWithTitle:@"Restore Defaults"];
    [alert addButtonWithTitle:@"Cancel"];
    return [alert runModal] == NSAlertFirstButtonReturn;
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
