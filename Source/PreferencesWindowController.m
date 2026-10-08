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
    // A panel, as preferences are everywhere: it never becomes the main window, so a theme that puts
    // the menu bar in the window gives it none, and it has no minimize button.
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:(NSWindowStyleMaskTitled |
                                                           NSWindowStyleMaskClosable |
                                                           NSWindowStyleMaskResizable)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    [panel setHidesOnDeactivate:NO];
    [panel setFloatingPanel:NO];
    self.window = panel;
    [self.window setReleasedWhenClosed:NO];
    self.window.title = @"Preferences";
    self.window.delegate = self;

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
    [self.pageTitleLabel setFont:[NSFont boldSystemFontOfSize:round([NSFont systemFontSize] * 1.35)]];
    [content addSubview:self.pageTitleLabel];

    self.pageDescriptionLabel = [self fieldLabelWithString:@"" frame:NSZeroRect];
    [[self.pageDescriptionLabel cell] setWraps:YES];
    [[self.pageDescriptionLabel cell] setScrollable:NO];
    [[self.pageDescriptionLabel cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [content addSubview:self.pageDescriptionLabel];

    self.drawingHeaderLabel = [self headerLabelWithString:@"Drawing Defaults"];
    [content addSubview:self.drawingHeaderLabel];

    self.penLabel = [self fieldLabelWithString:@"Pen" frame:NSZeroRect];
    [self.penLabel setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
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
    [self.highlighterLabel setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
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

    [self.window setContentMinSize:NSMakeSize(560.0f, 400.0f)];
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
    [label setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
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
    [label setFont:[NSFont systemFontOfSize:0.0f]];
    [label setTextColor:STThemePrimaryTextColor()];
    [label setStringValue:string ?: @""];
    return label;
}

- (void)configureSummaryLabel:(NSTextField *)label {
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setSelectable:NO];
    [label setFont:[NSFont systemFontOfSize:0.0f]];
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
    [self.sectionControl setSelectedSegment:self.currentSection];
    [self.pageTitleLabel setTextColor:STThemePrimaryTextColor()];
    [self.pageDescriptionLabel setTextColor:STThemeSecondaryTextColor()];
    [self.drawingHeaderLabel setTextColor:STThemeSectionHeaderColor()];
    [self.textHeaderLabel setTextColor:STThemeSectionHeaderColor()];
    [self.workspaceHeaderLabel setTextColor:STThemeSectionHeaderColor()];
    [self.interfaceHeaderLabel setTextColor:STThemeSectionHeaderColor()];
    [self.penColorLabel setTextColor:STThemePrimaryTextColor()];
    [self.highlighterColorLabel setTextColor:STThemePrimaryTextColor()];
    [self.textFontSummaryLabel setTextColor:STThemePrimaryTextColor()];
    [self.penWidthValueLabel setTextColor:STThemePrimaryTextColor()];
    [self.highlighterWidthValueLabel setTextColor:STThemePrimaryTextColor()];
    [self.statusBarLabel setTextColor:STThemePrimaryTextColor()];
    [self.directoryLabel setTextColor:STThemePrimaryTextColor()];
    [self.textColorLabel setTextColor:STThemePrimaryTextColor()];
    [self.textFontLabel setTextColor:STThemePrimaryTextColor()];
    [self.penLabel setTextColor:STThemePrimaryTextColor()];
    [self.highlighterLabel setTextColor:STThemePrimaryTextColor()];
    [self.pageTitleLabel setStringValue:[self titleForSection:self.currentSection]];
    [self.pageDescriptionLabel setStringValue:[self descriptionForSection:self.currentSection]];
}

/// The size a control asks for in the theme's font and metrics, or the fallback where it has no opinion.
static NSSize STPreferencesNaturalSize(NSControl *control, NSSize fallback) {
    NSSize size = [[control cell] cellSize];
    return NSMakeSize(size.width > 0.0f ? ceil(size.width) : fallback.width,
                      size.height > 0.0f ? ceil(size.height) : fallback.height);
}

/// Places a view of the given height centred in a row, so labels line up with the controls beside them.
static void STPreferencesPlaceInRow(NSView *view, CGFloat x, CGFloat width, CGFloat height, CGFloat rowY, CGFloat rowHeight) {
    [view setFrame:NSMakeRect(x, rowY + floor((rowHeight - height) / 2.0f), width, height)];
}

/// Lays out the current page, and returns the content height it needs.
- (CGFloat)layoutContentView {
    NSView *content = self.contentView ?: self.window.contentView;
    if (!content) {
        return 0.0f;
    }

    // Only spacing is the app's; every size comes from the theme's fonts and controls.
    CGFloat padding = 24.0f;
    CGFloat gap = 12.0f;
    CGFloat rowGap = 10.0f;
    CGFloat groupGap = 22.0f;
#if defined(GNUSTEP)
    NSSize switchSize = NSMakeSize(44.0f, 24.0f); // GNUstep's NSSwitch has no size of its own to ask
#else
    NSSize switchSize = self.statusBarSwitch.intrinsicContentSize;
#endif

    CGFloat innerX = padding;
    CGFloat innerWidth = MAX(200.0f, NSWidth(content.bounds) - (padding * 2.0f));
    self.backgroundView.contentCardRect = NSInsetRect(content.bounds, padding, padding);

    // A push button's height is the theme's control height; some cells (segmented, slider, text
    // field) report only what their text needs, so they get at least this much.
    NSSize buttonSize = STPreferencesNaturalSize(self.restoreDefaultsButton, NSMakeSize(150.0f, 24.0f));
    CGFloat controlHeight = buttonSize.height;
    NSSize colorWellSize = NSMakeSize(round(controlHeight * 1.75f), controlHeight);

    CGFloat y = NSMaxY(content.bounds) - padding;
    CGFloat switcherHeight = MAX(controlHeight, STPreferencesNaturalSize(self.sectionControl, NSZeroSize).height);
    y -= switcherHeight;
    [self.sectionControl setFrame:NSMakeRect(innerX, y, innerWidth, switcherHeight)];
    CGFloat segmentWidth = floor(innerWidth / 4.0f);
    for (NSInteger segment = 0; segment < 4; segment++) {
        CGFloat width = (segment == 3) ? (innerWidth - (segmentWidth * 3.0f)) : segmentWidth;
        [self.sectionControl setWidth:width forSegment:segment];
    }
    y -= groupGap;

    CGFloat titleHeight = STPreferencesNaturalSize(self.pageTitleLabel, NSZeroSize).height;
    y -= titleHeight;
    [self.pageTitleLabel setFrame:NSMakeRect(innerX, y, innerWidth, titleHeight)];
    y -= 4.0f;
    CGFloat descriptionHeight = ceil([[self.pageDescriptionLabel cell] cellSizeForBounds:NSMakeRect(0.0f, 0.0f, innerWidth, 10000.0f)].height);
    y -= descriptionHeight;
    [self.pageDescriptionLabel setFrame:NSMakeRect(innerX, y, innerWidth, descriptionHeight)];
    y -= groupGap;

    [self.restoreDefaultsButton setFrame:NSMakeRect(innerX, padding, buttonSize.width, controlHeight)];

    [self hideAllPageControls];

    CGFloat labelWidth = 0.0f;
    for (NSTextField *label in @[self.penLabel, self.highlighterLabel, self.textColorLabel, self.textFontLabel]) {
        labelWidth = MAX(labelWidth, STPreferencesNaturalSize(label, NSZeroSize).width);
    }
    CGFloat fieldX = innerX + labelWidth + gap;

    switch (self.currentSection) {
        case STPreferencesSectionAppearance: {
            // Label on the left, switch on the right, a row each.
            [self setViews:@[self.statusBarLabel, self.statusBarSwitch] hidden:NO];
            CGFloat rowHeight = MAX(controlHeight, switchSize.height);
            y -= rowHeight;
            STPreferencesPlaceInRow(self.statusBarLabel, innerX, innerWidth - switchSize.width - gap,
                                    STPreferencesNaturalSize(self.statusBarLabel, NSZeroSize).height, y, rowHeight);
            STPreferencesPlaceInRow(self.statusBarSwitch, innerX + innerWidth - switchSize.width, switchSize.width,
                                    switchSize.height, y, rowHeight);
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
                                        labelX:innerX
                                        fieldX:fieldX
                                         right:innerX + innerWidth
                                 controlHeight:controlHeight
                                 colorWellSize:colorWellSize];
            y -= groupGap;
            y = [self layoutToolSectionWithLabel:self.highlighterLabel
                                      slider:self.highlighterWidthSlider
                                 valueLabel:self.highlighterWidthValueLabel
                                quickButtons:self.highlighterQuickButtons
                                 colorLabel:self.highlighterColorLabel
                                  colorWell:self.highlighterColorWell
                                         y:y
                                    labelX:innerX
                                    fieldX:fieldX
                                     right:innerX + innerWidth
                             controlHeight:controlHeight
                             colorWellSize:colorWellSize];
            break;
        }

        case STPreferencesSectionText: {
            [self setViews:@[self.textColorLabel, self.textColorWell, self.textFontLabel, self.textFontSummaryLabel, self.textFontButton] hidden:NO];
            y -= controlHeight;
            STPreferencesPlaceInRow(self.textColorLabel, innerX, labelWidth,
                                    STPreferencesNaturalSize(self.textColorLabel, NSZeroSize).height, y, controlHeight);
            STPreferencesPlaceInRow(self.textColorWell, fieldX, colorWellSize.width, colorWellSize.height, y, controlHeight);
            y -= rowGap + controlHeight;

            CGFloat fontButtonWidth = STPreferencesNaturalSize(self.textFontButton, NSMakeSize(140.0f, controlHeight)).width;
            CGFloat fontButtonX = innerX + innerWidth - fontButtonWidth;
            STPreferencesPlaceInRow(self.textFontLabel, innerX, labelWidth,
                                    STPreferencesNaturalSize(self.textFontLabel, NSZeroSize).height, y, controlHeight);
            STPreferencesPlaceInRow(self.textFontSummaryLabel, fieldX, MAX(0.0f, fontButtonX - gap - fieldX),
                                    STPreferencesNaturalSize(self.textFontSummaryLabel, NSZeroSize).height, y, controlHeight);
            STPreferencesPlaceInRow(self.textFontButton, fontButtonX, fontButtonWidth, controlHeight, y, controlHeight);
            break;
        }

        case STPreferencesSectionWorkspace: {
            [self setViews:@[self.directoryLabel, self.saveDirectoryField, self.chooseDirectoryButton] hidden:NO];
            CGFloat labelHeight = STPreferencesNaturalSize(self.directoryLabel, NSZeroSize).height;
            y -= labelHeight;
            [self.directoryLabel setFrame:NSMakeRect(innerX, y, innerWidth, labelHeight)];
            y -= 6.0f;

            CGFloat chooseWidth = STPreferencesNaturalSize(self.chooseDirectoryButton, NSMakeSize(116.0f, controlHeight)).width;
            CGFloat fieldHeight = MAX(controlHeight, STPreferencesNaturalSize(self.saveDirectoryField, NSZeroSize).height);
            CGFloat rowHeight = MAX(controlHeight, fieldHeight);
            CGFloat fieldWidth = MAX(0.0f, innerWidth - chooseWidth - gap);
            y -= rowHeight;
            STPreferencesPlaceInRow(self.saveDirectoryField, innerX, fieldWidth, fieldHeight, y, rowHeight);
            STPreferencesPlaceInRow(self.chooseDirectoryButton, innerX + fieldWidth + gap, chooseWidth, controlHeight, y, rowHeight);
            break;
        }
    }

    // The page, then a gap, then Restore Defaults on the bottom margin.
    return (NSMaxY(content.bounds) - y) + groupGap + controlHeight + padding;
}

/// The content height the tallest page needs.
- (CGFloat)contentHeightForTallestPage {
    STPreferencesSection shown = self.currentSection;
    CGFloat height = 0.0f;
    for (NSInteger section = STPreferencesSectionAppearance; section <= STPreferencesSectionWorkspace; section++) {
        self.currentSection = (STPreferencesSection)section;
        height = MAX(height, ceil([self layoutContentView]));
    }
    self.currentSection = shown;
    return height;
}

/// Lays out a tool's two rows (label, slider and value; then the quick widths and colour), and returns
/// the y below them.
- (CGFloat)layoutToolSectionWithLabel:(NSTextField *)label
                               slider:(NSSlider *)slider
                          valueLabel:(NSTextField *)valueLabel
                         quickButtons:(NSArray<NSButton *> *)quickButtons
                          colorLabel:(NSTextField *)colorLabel
                           colorWell:(NSColorWell *)colorWell
                                  y:(CGFloat)y
                              labelX:(CGFloat)labelX
                              fieldX:(CGFloat)fieldX
                               right:(CGFloat)right
                       controlHeight:(CGFloat)controlHeight
                       colorWellSize:(NSSize)colorWellSize {
    if (!label || !slider || !valueLabel || !colorLabel || !colorWell) {
        return y;
    }

    CGFloat gap = 12.0f;
    CGFloat rowGap = 10.0f;

    // Wide enough for the widest value the slider can show.
    NSDictionary *valueAttributes = @{ NSFontAttributeName: valueLabel.font ?: [NSFont systemFontOfSize:0.0f] };
    CGFloat valueWidth = ceil([[self displayStringForWidth:STToolWidthMax] sizeWithAttributes:valueAttributes].width) + 8.0f;
    CGFloat sliderHeight = MAX(controlHeight, STPreferencesNaturalSize(slider, NSZeroSize).height);
    CGFloat rowHeight = MAX(controlHeight, sliderHeight);

    y -= rowHeight;
    CGFloat sliderWidth = MAX(80.0f, right - valueWidth - gap - fieldX);
    STPreferencesPlaceInRow(label, labelX, MAX(0.0f, fieldX - gap - labelX),
                            STPreferencesNaturalSize(label, NSZeroSize).height, y, rowHeight);
    STPreferencesPlaceInRow(slider, fieldX, sliderWidth, sliderHeight, y, rowHeight);
    STPreferencesPlaceInRow(valueLabel, right - valueWidth, valueWidth,
                            STPreferencesNaturalSize(valueLabel, NSZeroSize).height, y, rowHeight);

    y -= rowGap + controlHeight;
    CGFloat colorWellX = right - colorWellSize.width;
    CGFloat colorLabelWidth = STPreferencesNaturalSize(colorLabel, NSZeroSize).width;
    CGFloat colorLabelX = colorWellX - 8.0f - colorLabelWidth;
    STPreferencesPlaceInRow(colorLabel, colorLabelX, colorLabelWidth,
                            STPreferencesNaturalSize(colorLabel, NSZeroSize).height, y, controlHeight);
    STPreferencesPlaceInRow(colorWell, colorWellX, colorWellSize.width, colorWellSize.height, y, controlHeight);

    // Never narrower than the theme needs for the widest title, or two-digit widths get clipped.
    CGFloat quickButtonWidth = round(controlHeight * 1.75f);
    for (NSButton *button in quickButtons) {
        quickButtonWidth = MAX(quickButtonWidth, STPreferencesNaturalSize(button, NSZeroSize).width);
    }
    CGFloat quickX = fieldX;
    for (NSButton *button in quickButtons) {
        STPreferencesPlaceInRow(button, quickX, quickButtonWidth, controlHeight, y, controlHeight);
        quickX += quickButtonWidth + 8.0f;
    }

    return y;
}

- (void)showRelativeToWindow:(NSWindow *)window {
    if (!self.window) {
        return;
    }
    // As tall as the tallest page needs in the theme's fonts, so no page leaves a gap or clips.
    CGFloat height = [self contentHeightForTallestPage];
    NSRect frame = [self.window frameRectForContentRect:NSMakeRect(0.0f, 0.0f, NSWidth([self.window.contentView bounds]), height)];
    [self.window setContentMinSize:NSMakeSize(560.0f, height)];
    [self.window setFrame:NSMakeRect(NSMinX(self.window.frame), NSMaxY(self.window.frame) - NSHeight(frame), NSWidth(frame), NSHeight(frame)) display:NO];
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
