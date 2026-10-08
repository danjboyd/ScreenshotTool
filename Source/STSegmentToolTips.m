#import "STSegmentToolTips.h"
#import <objc/runtime.h>

NSRect STSegmentToolTipRect(NSSegmentedControl *control, NSInteger segment) {
    NSRect bounds = control.bounds;
    NSInteger count = control.segmentCount;
    CGFloat x = NSMinX(bounds);
    for (NSInteger index = 0; index < count && x < NSMaxX(bounds); index++) {
        CGFloat width = [control widthForSegment:index];
        if (width <= 0.0) {
            width = (NSMaxX(bounds) - x) / (CGFloat)(count - index);
        }
        if (index == segment) {
            return NSMakeRect(x, NSMinY(bounds), width, NSHeight(bounds));
        }
        x += width;
    }
    return NSZeroRect;
}

#if defined(GNUSTEP)

static const void *STSegmentToolTipsKey = &STSegmentToolTipsKey;

/// Owns a control's per-segment tool tip areas and answers for them.
@interface STSegmentToolTipProvider : NSObject
@property (nonatomic, weak) NSSegmentedControl *control;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *tags;
- (void)install;
@end

@implementation STSegmentToolTipProvider

- (void)install {
    NSSegmentedControl *control = self.control;
    for (NSNumber *tag in self.tags) {
        [control removeToolTip:tag.integerValue];
    }
    [self.tags removeAllObjects];
    if (!control) {
        return;
    }
    // A tip for the whole control would overlap the segments' and win at random.
    [control setToolTip:nil];

    for (NSInteger segment = 0; segment < control.segmentCount; segment++) {
        NSRect rect = STSegmentToolTipRect(control, segment);
        if (NSIsEmptyRect(rect)) {
            break;
        }
        NSToolTipTag tag = [control addToolTipRect:rect owner:self userData:(void *)(intptr_t)segment];
        if (tag != -1) {
            [self.tags addObject:@(tag)];
        }
    }
}

- (void)controlFrameDidChange:(NSNotification *)notification {
    (void)notification;
    [self install];
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data {
    (void)view;
    (void)tag;
    (void)point;
    NSInteger segment = (NSInteger)(intptr_t)data;
    NSSegmentedControl *control = self.control;
    if (!control || segment >= control.segmentCount) {
        return nil;
    }
    return [[control cell] toolTipForSegment:segment];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

void STInstallSegmentToolTips(NSSegmentedControl *control) {
    if (!control) {
        return;
    }
    STSegmentToolTipProvider *provider = objc_getAssociatedObject(control, STSegmentToolTipsKey);
    if (!provider) {
        provider = [[STSegmentToolTipProvider alloc] init];
        provider.control = control;
        provider.tags = [NSMutableArray array];
        objc_setAssociatedObject(control, STSegmentToolTipsKey, provider, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [control setPostsFrameChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:provider
                                                 selector:@selector(controlFrameDidChange:)
                                                     name:NSViewFrameDidChangeNotification
                                                   object:control];
    }
    [provider install];
}

#else

void STInstallSegmentToolTips(NSSegmentedControl *control) {
    (void)control;
}

#endif
