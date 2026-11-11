#import "STPrintAccessoryController.h"
#import "STPrintView.h"

#if !defined(GNUSTEP)

static NSString * const STFitIndexKey = @"fitIndex";
static NSString * const STScalePercentKey = @"scalePercent";
static NSString * const STEnlargeKey = @"enlargeToFill";
static NSString * const STSelectionOnlyKey = @"selectionOnly";
static NSString * const STAutomaticOrientationKey = @"automaticOrientation";

@interface STPrintAccessoryController ()
@property (nonatomic, readwrite) BOOL hasSelection;
@property (nonatomic) STPrintOrientation chosenOrientation;
@end

@implementation STPrintAccessoryController

- (instancetype)initWithOptions:(STPrintOptions *)options hasSelection:(BOOL)hasSelection {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _hasSelection = hasSelection;
        _fitIndex = options.fit == STPrintFitActualSize ? 1 : (options.fit == STPrintFitCustomScale ? 2 : 0);
        _scalePercent = (NSInteger)lround(options.customScale * 100.0);
        _enlargeToFill = options.enlargeToFill;
        _selectionOnly = hasSelection && options.selectionOnly;
        _automaticOrientation = options.orientation == STPrintOrientationAutomatic;
        _chosenOrientation = options.orientation;
        self.title = @"ScreenshotTool";
    }
    return self;
}

- (STPrintOptions *)options {
    STPrintOptions *options = [[STPrintOptions alloc] init];
    options.fit = self.fitIndex == 1 ? STPrintFitActualSize : (self.fitIndex == 2 ? STPrintFitCustomScale : STPrintFitToPage);
    options.customScale = self.scalePercent / 100.0;
    options.enlargeToFill = self.enlargeToFill;
    options.selectionOnly = self.hasSelection && self.selectionOnly;
    options.orientation = self.automaticOrientation ? STPrintOrientationAutomatic : self.chosenOrientation;
    return options;
}

#pragma mark - Values

- (void)setFitIndex:(NSInteger)fitIndex {
    _fitIndex = MIN(MAX(fitIndex, 0), 2);
    [self optionsChanged];
}

- (void)setScalePercent:(NSInteger)scalePercent {
    NSInteger minimum = (NSInteger)lround(STPrintOptionsMinimumScale * 100.0);
    NSInteger maximum = (NSInteger)lround(STPrintOptionsMaximumScale * 100.0);
    _scalePercent = MIN(MAX(scalePercent, minimum), maximum);
    [self optionsChanged];
}

- (void)setEnlargeToFill:(BOOL)enlargeToFill {
    _enlargeToFill = enlargeToFill;
    [self optionsChanged];
}

- (void)setSelectionOnly:(BOOL)selectionOnly {
    _selectionOnly = self.hasSelection && selectionOnly;
    [self optionsChanged];
}

- (void)setAutomaticOrientation:(BOOL)automaticOrientation {
    if (!automaticOrientation && _automaticOrientation) {
        STPrintLayout *layout = self.printView.layout;
        if (layout) {
            _chosenOrientation = layout.resolvedOrientation;
        } else {
            NSPrintInfo *info = [self.representedObject isKindOfClass:[NSPrintInfo class]] ? self.representedObject : nil;
            if (info) {
                _chosenOrientation = info.orientation == NSPaperOrientationLandscape
                    ? STPrintOrientationLandscape : STPrintOrientationPortrait;
            } else if (_chosenOrientation == STPrintOrientationAutomatic) {
                _chosenOrientation = STPrintOrientationPortrait;
            }
        }
    }
    _automaticOrientation = automaticOrientation;
    [self optionsChanged];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingIsCustomScale {
    return [NSSet setWithObject:STFitIndexKey];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingIsFitToPage {
    return [NSSet setWithObject:STFitIndexKey];
}

- (BOOL)isCustomScale {
    return self.fitIndex == 2;
}

- (BOOL)isFitToPage {
    return self.fitIndex == 0;
}

- (void)printViewChoseOrientation:(STPrintOrientation)orientation {
    if (orientation == STPrintOrientationAutomatic) {
        return;
    }
    self.chosenOrientation = orientation;
    // Through the setter, so the checkbox follows; the layout already has the panel's orientation.
    self.automaticOrientation = NO;
}

/// The layout takes the options at once, so the preview's page count follows them. With "Turn
/// automatically", the panel's sheet turns with the layout too.
- (void)optionsChanged {
    STPrintOptions *options = self.options;
    STPrintView *view = self.printView;
    if (view) {
        [options applyToLayout:view.layout];
        if (self.optionsDidChange) {
            self.optionsDidChange(options);
        }
        NSPrintInfo *info = [self.representedObject isKindOfClass:[NSPrintInfo class]] ? self.representedObject : nil;
        if (info) {
            STPreparePrintInfo(info, view.layout);
        }
    } else if (self.optionsDidChange) {
        self.optionsDidChange(options);
    }
}

- (void)saveToDefaults:(NSUserDefaults *)defaults {
    [self.options saveToDefaults:defaults];
}

#pragma mark - NSPrintPanelAccessorizing

- (NSSet<NSString *> *)keyPathsForValuesAffectingPreview {
    return [NSSet setWithObjects:STFitIndexKey, STScalePercentKey, STEnlargeKey,
                                 STSelectionOnlyKey, STAutomaticOrientationKey, nil];
}

- (NSArray<NSDictionary<NSPrintPanelAccessorySummaryKey, NSString *> *> *)localizedSummaryItems {
    NSString *size = @"Fit to page";
    if (self.fitIndex == 0 && self.enlargeToFill) {
        size = @"Fit to page, enlarged to fill";
    } else if (self.fitIndex == 1) {
        size = @"Actual size";
    } else if (self.fitIndex == 2) {
        size = [NSString stringWithFormat:@"%ld%% of actual size", (long)self.scalePercent];
    }
    NSMutableArray *items = [NSMutableArray arrayWithObjects:
        @{ NSPrintPanelAccessorySummaryItemNameKey: @"Size", NSPrintPanelAccessorySummaryItemDescriptionKey: size },
        @{ NSPrintPanelAccessorySummaryItemNameKey: @"Orientation",
           NSPrintPanelAccessorySummaryItemDescriptionKey: self.automaticOrientation ? @"Turned to suit the image" : @"As chosen" },
        nil];
    if (self.hasSelection) {
        [items addObject:@{ NSPrintPanelAccessorySummaryItemNameKey: @"Print",
                            NSPrintPanelAccessorySummaryItemDescriptionKey: self.selectionOnly ? @"The selection" : @"The whole image" }];
    }
    return items;
}

#pragma mark - View

- (NSButton *)checkboxTitled:(NSString *)title key:(NSString *)key {
    NSButton *box = [NSButton checkboxWithTitle:title target:nil action:NULL];
    [box bind:NSValueBinding toObject:self withKeyPath:key options:nil];
    return box;
}

- (void)loadView {
    NSPopUpButton *fit = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [fit addItemsWithTitles:@[ @"Fit to Page", @"Actual Size", @"Custom Scale" ]];
    [fit bind:NSSelectedIndexBinding toObject:self withKeyPath:STFitIndexKey options:nil];
    fit.identifier = @"fit";

    NSTextField *scale = [NSTextField textFieldWithString:@""];
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterNoStyle;
    formatter.minimum = @((NSInteger)lround(STPrintOptionsMinimumScale * 100.0));
    formatter.maximum = @((NSInteger)lround(STPrintOptionsMaximumScale * 100.0));
    scale.formatter = formatter;
    scale.alignment = NSTextAlignmentRight;
    scale.identifier = @"scale";
    [scale bind:NSValueBinding toObject:self withKeyPath:STScalePercentKey
        options:@{ NSContinuouslyUpdatesValueBindingOption: @YES }];
    [scale bind:NSEnabledBinding toObject:self withKeyPath:@"isCustomScale" options:nil];
    [scale.widthAnchor constraintEqualToConstant:52].active = YES;
    NSTextField *percent = [NSTextField labelWithString:@"%"];

    NSButton *enlarge = [self checkboxTitled:@"Enlarge small images to fill the page" key:STEnlargeKey];
    [enlarge bind:NSEnabledBinding toObject:self withKeyPath:@"isFitToPage" options:nil];
    enlarge.identifier = @"enlarge";
    NSButton *selection = [self checkboxTitled:@"Print only the selection" key:STSelectionOnlyKey];
    selection.enabled = self.hasSelection;
    selection.identifier = @"selection";
    NSButton *turn = [self checkboxTitled:@"Turn the page to suit the image" key:STAutomaticOrientationKey];
    turn.identifier = @"orientation";

    NSStackView *sizeRow = [NSStackView stackViewWithViews:@[ [NSTextField labelWithString:@"Size:"], fit, scale, percent ]];
    sizeRow.spacing = 6;
    NSStackView *stack = [NSStackView stackViewWithViews:@[ sizeRow, enlarge, selection, turn ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.edgeInsets = NSEdgeInsetsMake(12, 20, 12, 20);
    self.view = stack;
}

@end

#endif
