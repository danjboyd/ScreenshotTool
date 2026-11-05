#import <Foundation/Foundation.h>
#import "STPrintLayout.h"

NS_ASSUME_NONNULL_BEGIN

/// The smallest and largest custom scale the print options keep: 1 is the image's real size.
extern const CGFloat STPrintOptionsMinimumScale;
extern const CGFloat STPrintOptionsMaximumScale;

extern NSString * const STDefaultsPrintFitKey;              // @"page", @"actual" or @"custom"
extern NSString * const STDefaultsPrintCustomScaleKey;      // a number; 1 is the real size
extern NSString * const STDefaultsPrintEnlargeToFillKey;    // a bool
extern NSString * const STDefaultsPrintOrientationKey;      // @"auto", @"portrait" or @"landscape"
extern NSString * const STDefaultsPrintAnnotationsKey;      // a bool

/// What the user chooses when printing (#355), the same on every platform: each one's print UI shows
/// these, and they're remembered from one print to the next under the same keys.
///
/// A saved value that isn't one of these (a newer version's, or a hand edit) reads as the default.
@interface STPrintOptions : NSObject <NSCopying>

/// Fit to page.
@property (nonatomic) STPrintFit fit;
/// 1. Kept between the minimum and maximum; a value that isn't above 0 is ignored.
@property (nonatomic) CGFloat customScale;
/// NO.
@property (nonatomic) BOOL enlargeToFill;
/// Automatic.
@property (nonatomic) STPrintOrientation orientation;
/// YES: print the annotations along with the image.
@property (nonatomic) BOOL includeAnnotations;
/// NO: print the selection, not the whole image. Not remembered: it's about this print's image, so the
/// print UI sets it for each print.
@property (nonatomic) BOOL selectionOnly;

/// The defaults, with any saved values from `defaults` over them.
+ (instancetype)optionsFromDefaults:(NSUserDefaults *)defaults;
/// Saves everything except `selectionOnly`.
- (void)saveToDefaults:(NSUserDefaults *)defaults;
/// Sets the layout's fit, scale, enlargement and orientation. The source rect, paper, margins and
/// resolution belong to the print path: it knows the selection and the printer.
- (void)applyToLayout:(STPrintLayout *)layout;

@end

NS_ASSUME_NONNULL_END
