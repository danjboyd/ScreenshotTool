#import <AppKit/AppKit.h>
#import "ScreenshotCanvasView.h"

NS_ASSUME_NONNULL_BEGIN

@class PreferencesWindowController;

@protocol PreferencesWindowControllerDelegate <NSObject>
- (CGFloat)preferencesController:(PreferencesWindowController *)controller defaultWidthForTool:(ScreenshotCanvasTool)tool;
- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultWidth:(CGFloat)width forTool:(ScreenshotCanvasTool)tool;
- (NSColor *)preferencesController:(PreferencesWindowController *)controller defaultColorForTool:(ScreenshotCanvasTool)tool;
- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultColor:(NSColor *)color forTool:(ScreenshotCanvasTool)tool;
- (NSFont *)preferencesControllerDefaultTextFont:(PreferencesWindowController *)controller;
- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultTextFont:(NSFont *)font;
- (NSColor *)preferencesControllerDefaultTextColor:(PreferencesWindowController *)controller;
- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultTextColor:(NSColor *)color;
- (NSString *)preferencesControllerDefaultSaveDirectory:(PreferencesWindowController *)controller;
- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultSaveDirectory:(NSString *)path;
- (BOOL)preferencesControllerShouldShowStatusBar:(PreferencesWindowController *)controller;
- (void)preferencesController:(PreferencesWindowController *)controller didToggleStatusBar:(BOOL)show;
- (NSString *)preferencesControllerInterfaceThemePreference:(PreferencesWindowController *)controller;
- (void)preferencesController:(PreferencesWindowController *)controller didChangeInterfaceThemePreference:(NSString *)preference;
/// Whether to offer "Show toolbar in the title bar": the Adwaita theme is active.
- (BOOL)preferencesControllerOffersToolbarInTitleBar:(PreferencesWindowController *)controller;
/// Whether that option can take effect: the theme draws the title bar (its header bar).
- (BOOL)preferencesControllerCanShowToolbarInTitleBar:(PreferencesWindowController *)controller;
- (BOOL)preferencesControllerShowsToolbarInTitleBar:(PreferencesWindowController *)controller;
- (void)preferencesController:(PreferencesWindowController *)controller didToggleToolbarInTitleBar:(BOOL)show;
- (void)preferencesControllerRestoreDefaults:(PreferencesWindowController *)controller;
- (void)preferencesControllerDidRequestClose:(PreferencesWindowController *)controller;
@end

@interface PreferencesWindowController : NSResponder <NSWindowDelegate>

@property (nonatomic, weak) id<PreferencesWindowControllerDelegate> delegate;

- (instancetype)initWithDelegate:(id<PreferencesWindowControllerDelegate>)delegate;
- (void)showRelativeToWindow:(NSWindow *)window;
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
