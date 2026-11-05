#import "STPrintOptions.h"

const CGFloat STPrintOptionsMinimumScale = 0.1;
const CGFloat STPrintOptionsMaximumScale = 4.0;

NSString * const STDefaultsPrintFitKey = @"ScreenshotToolPrintFit";
NSString * const STDefaultsPrintCustomScaleKey = @"ScreenshotToolPrintCustomScale";
NSString * const STDefaultsPrintEnlargeToFillKey = @"ScreenshotToolPrintEnlargeToFill";
NSString * const STDefaultsPrintOrientationKey = @"ScreenshotToolPrintOrientation";
NSString * const STDefaultsPrintAnnotationsKey = @"ScreenshotToolPrintAnnotations";

static NSString * const STPrintFitPage = @"page";
static NSString * const STPrintFitActual = @"actual";
static NSString * const STPrintFitCustom = @"custom";
static NSString * const STPrintOrientationAuto = @"auto";
static NSString * const STPrintOrientationTall = @"portrait";
static NSString * const STPrintOrientationWide = @"landscape";

@implementation STPrintOptions

- (instancetype)init {
    self = [super init];
    if (self) {
        _fit = STPrintFitToPage;
        _customScale = 1.0;
        _orientation = STPrintOrientationAutomatic;
        _includeAnnotations = YES;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    STPrintOptions *copy = [[[self class] allocWithZone:zone] init];
    copy.fit = self.fit;
    copy.customScale = self.customScale;
    copy.enlargeToFill = self.enlargeToFill;
    copy.orientation = self.orientation;
    copy.includeAnnotations = self.includeAnnotations;
    copy.selectionOnly = self.selectionOnly;
    return copy;
}

- (void)setCustomScale:(CGFloat)customScale {
    if (customScale > 0.0) {
        _customScale = MIN(MAX(customScale, STPrintOptionsMinimumScale), STPrintOptionsMaximumScale);
    }
}

+ (instancetype)optionsFromDefaults:(NSUserDefaults *)defaults {
    STPrintOptions *options = [[self alloc] init];

    id fit = [defaults objectForKey:STDefaultsPrintFitKey];
    if ([STPrintFitActual isEqual:fit]) {
        options.fit = STPrintFitActualSize;
    } else if ([STPrintFitCustom isEqual:fit]) {
        options.fit = STPrintFitCustomScale;
    }

    id orientation = [defaults objectForKey:STDefaultsPrintOrientationKey];
    if ([STPrintOrientationTall isEqual:orientation]) {
        options.orientation = STPrintOrientationPortrait;
    } else if ([STPrintOrientationWide isEqual:orientation]) {
        options.orientation = STPrintOrientationLandscape;
    }

    id scale = [defaults objectForKey:STDefaultsPrintCustomScaleKey];
    if ([scale isKindOfClass:[NSNumber class]] || [scale isKindOfClass:[NSString class]]) {
        options.customScale = (CGFloat)[scale doubleValue];
    }
    if ([defaults objectForKey:STDefaultsPrintEnlargeToFillKey]) {
        options.enlargeToFill = [defaults boolForKey:STDefaultsPrintEnlargeToFillKey];
    }
    if ([defaults objectForKey:STDefaultsPrintAnnotationsKey]) {
        options.includeAnnotations = [defaults boolForKey:STDefaultsPrintAnnotationsKey];
    }
    return options;
}

- (void)saveToDefaults:(NSUserDefaults *)defaults {
    NSString *fit = STPrintFitPage;
    if (self.fit == STPrintFitActualSize) {
        fit = STPrintFitActual;
    } else if (self.fit == STPrintFitCustomScale) {
        fit = STPrintFitCustom;
    }
    NSString *orientation = STPrintOrientationAuto;
    if (self.orientation == STPrintOrientationPortrait) {
        orientation = STPrintOrientationTall;
    } else if (self.orientation == STPrintOrientationLandscape) {
        orientation = STPrintOrientationWide;
    }
    [defaults setObject:fit forKey:STDefaultsPrintFitKey];
    [defaults setDouble:self.customScale forKey:STDefaultsPrintCustomScaleKey];
    [defaults setBool:self.enlargeToFill forKey:STDefaultsPrintEnlargeToFillKey];
    [defaults setObject:orientation forKey:STDefaultsPrintOrientationKey];
    [defaults setBool:self.includeAnnotations forKey:STDefaultsPrintAnnotationsKey];
}

- (void)applyToLayout:(STPrintLayout *)layout {
    layout.fit = self.fit;
    layout.customScale = self.customScale;
    layout.enlargeToFill = self.enlargeToFill;
    layout.orientation = self.orientation;
}

@end
