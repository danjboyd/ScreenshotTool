#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Shows each segment's own tool tip (-[NSSegmentedCell setToolTip:forSegment:]) as the pointer
/// rests on it. AppKit does this itself; GNUstep keeps the tips but never shows them, so there the
/// control gets a tool tip area per segment, kept in step with its frame. The tips are read when
/// shown, so later setToolTip:forSegment: calls need no reinstall. A no-op on macOS.
void STInstallSegmentToolTips(NSSegmentedControl *control);

/// Where GNUstep draws a segment, in the control's bounds: its set width, or an even share of
/// what's left (as -[NSSegmentedCell drawInteriorWithFrame:inView:]). NSZeroRect past the end.
NSRect STSegmentToolTipRect(NSSegmentedControl *control, NSInteger segment);

NS_ASSUME_NONNULL_END
