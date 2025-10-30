#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface STHyperlinkButton : NSButton

+ (instancetype)hyperlinkButtonWithTitle:(NSString *)title
                                   target:(id)target
                                   action:(SEL)action;

@end

NS_ASSUME_NONNULL_END
