#import <AppKit/AppKit.h>

@interface STHudView : NSView
@property (nonatomic, copy) NSString *message;
@property (nonatomic, strong) NSFont *font;
@property (nonatomic, strong) NSColor *textColor;
@property (nonatomic, strong) NSColor *fillColor;
@property (nonatomic, assign) NSSize textPadding;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) CGFloat hudAlpha;
@end
