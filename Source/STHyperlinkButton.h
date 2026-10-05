#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A small push button for popover actions ("Reset", "Set as Default"), drawn by the theme.
@interface STHyperlinkButton : NSButton

+ (instancetype)hyperlinkButtonWithTitle:(NSString *)title
                                   target:(id)target
                                   action:(SEL)action;

@end

NS_ASSUME_NONNULL_END
