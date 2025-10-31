#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "STHyperlinkButton.h"
#import "ScreenshotToolSettings.h"
#import "ToolSettingsPopoverController.h"
#import "TextToolPopoverController.h"
#import "PreferencesWindowController.h"
#import <AppKit/NSInterfaceStyle.h>
#include <math.h>
#include <stdlib.h>

static NSString *ScreenshotToolLogFilePath(void) {
    static NSString *logPath = nil;
    if (!logPath) {
        NSDictionary *env = [[NSProcessInfo processInfo] environment];
        NSString *custom = env[@"SCREENSHOT_TOOL_LOG_PATH"];
        if (custom.length > 0) {
            logPath = [custom stringByExpandingTildeInPath];
        } else {
            logPath = [@"~/git/ScreenshotTool/screenshottool.log" stringByExpandingTildeInPath];
        }
        logPath = [logPath copy];
    }
    return logPath;
}

void ScreenshotToolAppendLog(NSString *message) {
    if (message.length == 0) {
        return;
    }
    unichar newline = 0x000A;
    NSString *line = [message stringByAppendingFormat:@"%C", newline];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = ScreenshotToolLogFilePath();
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [path stringByDeletingLastPathComponent];
    if (dir.length > 0 && ![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    if (![fm fileExistsAtPath:path]) {
        [fm createFileAtPath:path contents:data attributes:nil];
        return;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [fm createFileAtPath:path contents:data attributes:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

static NSString *STDebugToolName(ScreenshotCanvasTool tool) {
    switch (tool) {
        case ScreenshotCanvasToolHighlighter:
            return @"Highlighter";
        case ScreenshotCanvasToolPen:
            return @"Pen";
        case ScreenshotCanvasToolEraser:
            return @"Eraser";
        case ScreenshotCanvasToolText:
            return @"Text";
        case ScreenshotCanvasToolSelect:
            return @"Select";
    }
    return @"Unknown";
}

static NSString *STDebugDescriptionForEvent(NSEvent *event) {
    if (!event) {
        return @"<no NSEvent>";
    }
    NSEventType type = event.type;
    NSInteger clickCount = event.clickCount;
    NSInteger buttonNumber = event.buttonNumber;
    unsigned long modifiers = (unsigned long)event.modifierFlags;
    NSPoint location = event.locationInWindow;
    NSTimeInterval timestamp = event.timestamp;
    return [NSString stringWithFormat:@"type=%ld button=%ld clickCount=%ld modifiers=0x%lx location=(%.1f, %.1f) timestamp=%.3f",
                                      (long)type,
                                      (long)buttonNumber,
                                      (long)clickCount,
                                      modifiers,
                                      location.x,
                                      location.y,
                                      timestamp];
}

static NSString *STDebugDescriptionForSender(id sender) {
    if (!sender) {
        return @"<nil sender>";
    }
    if ([sender isKindOfClass:[NSToolbarItem class]]) {
        NSToolbarItem *item = (NSToolbarItem *)sender;
        NSString *identifier = item.itemIdentifier ?: @"<no identifier>";
        return [NSString stringWithFormat:@"NSToolbarItem(%@)", identifier];
    }
    return NSStringFromClass([sender class]);
}



static NSString * const ToolbarIdentifier = @"com.screenshottool.toolbar";
static NSString * const ToolbarItemHighlighter = @"com.screenshottool.toolbar.highlighter";
static NSString * const ToolbarItemPen = @"com.screenshottool.toolbar.pen";
static NSString * const ToolbarItemEraser = @"com.screenshottool.toolbar.eraser";
static NSString * const ToolbarItemText = @"com.screenshottool.toolbar.text";
static NSString * const ToolbarItemSelect = @"com.screenshottool.toolbar.select";
static NSString * const ToolbarItemZoom = @"com.screenshottool.toolbar.zoom";
static NSString * const ToolbarItemCopy = @"com.screenshottool.toolbar.copy";
static NSString * const ToolbarItemPreferences = @"com.screenshottool.toolbar.preferences";
static const CGFloat StatusBarHeight = 24.0f;
static const CGFloat ToolbarIconDimension = 32.0f;

@interface AppDelegate () <NSToolbarDelegate, ToolSettingsPopoverControllerDelegate, TextToolPopoverControllerDelegate, PreferencesWindowControllerDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) ScreenshotCanvasView *canvasView;
@property (nonatomic, strong) NSToolbar *toolbar;
@property (nonatomic, strong) NSPopUpButton *zoomPopUpButton;
@property (nonatomic, strong) NSView *statusBarView;
@property (nonatomic, strong) NSTextField *statusTextField;
@property (nonatomic, strong) NSTimer *statusClearTimer;
@property (nonatomic, strong) NSView *statusControlsContainer;
@property (nonatomic, strong) NSTextField *toolWidthTitleLabel;
@property (nonatomic, strong) NSSlider *toolWidthSlider;
@property (nonatomic, strong) NSTextField *toolWidthValueLabel;
@property (nonatomic, strong) STHyperlinkButton *toolWidthResetButton;
@property (nonatomic, strong) STHyperlinkButton *toolWidthSetDefaultButton;
@property (nonatomic, assign) CGFloat penDefaultWidth;
@property (nonatomic, assign) CGFloat highlighterDefaultWidth;
@property (nonatomic, strong) NSColor *penDefaultColor;
@property (nonatomic, strong) NSColor *highlighterDefaultColor;
@property (nonatomic, strong) NSColor *textDefaultColor;
@property (nonatomic, strong) NSFont *textDefaultFont;
@property (nonatomic, strong) ToolSettingsPopoverController *penPopoverController;
@property (nonatomic, strong) ToolSettingsPopoverController *highlighterPopoverController;
@property (nonatomic, strong) TextToolPopoverController *textPopoverController;
@property (nonatomic, strong) PreferencesWindowController *preferencesWindowController;
@property (nonatomic, assign) ScreenshotCanvasTool lastWidthTool;
@property (nonatomic, copy) NSString *defaultSaveDirectory;
@property (nonatomic, assign) BOOL statusBarVisiblePreference;
@property (nonatomic, copy) NSString *pendingOpenPath;
@property (nonatomic, strong) NSURL *currentImageURL;
@end

@implementation AppDelegate

- (void)applyToolTipToToolbarItem:(NSToolbarItem *)item source:(NSString *)source {
    if (!item) {
        return;
    }
    NSString *identifier = item.itemIdentifier;
    NSString *tip = [self toolTipForIdentifier:identifier];
    if (!tip) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"applyToolTip skipped %@ (source=%@)", identifier ?: @"<nil>", source ?: @"<nil>"]);
        return;
    }
    item.toolTip = tip;
    if (item.view) {
        [item.view setToolTip:tip];
    }
    ScreenshotToolAppendLog([NSString stringWithFormat:@"applyToolTip %@ -> %@ (source=%@)", identifier, tip, source ?: @"<nil>"]);
}

- (NSString *)toolTipForIdentifier:(NSToolbarItemIdentifier)identifier {
    if ([identifier isEqualToString:ToolbarItemHighlighter]) {
        return @"Highlighter Tool — double-click to configure";
    }
    if ([identifier isEqualToString:ToolbarItemPen]) {
        return @"Pen Tool — double-click to configure";
    }
    if ([identifier isEqualToString:ToolbarItemText]) {
        return @"Text Tool — double-click to configure";
    }
    return nil;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    ScreenshotToolAppendLog(@"ScreenshotTool will finish launching");
    [self setupMenus];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    ScreenshotToolAppendLog(@"ScreenshotTool launched");
    [self setupWindowAndContent];
    [self setupToolbar];
    self.lastWidthTool = ScreenshotCanvasToolHighlighter;
    [self loadToolSettingsFromDefaults];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    [self selectTool:ScreenshotCanvasToolHighlighter];
    [self reflectZoomSelection];

    if (self.pendingOpenPath.length > 0) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"applicationDidFinishLaunching: attempting deferred open for %@",
                                 self.pendingOpenPath]);
        [self openImageAtURL:[NSURL fileURLWithPath:self.pendingOpenPath]];
        self.pendingOpenPath = nil;
    } else {
        NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
        ScreenshotToolAppendLog([NSString stringWithFormat:@"applicationDidFinishLaunching: argc=%lu",
                                 (unsigned long)arguments.count]);
        if (arguments.count > 1) {
            for (NSUInteger idx = 1; idx < arguments.count; idx++) {
                NSString *candidate = arguments[idx];
                ScreenshotToolAppendLog([NSString stringWithFormat:@"applicationDidFinishLaunching: CLI arg[%lu]=%@",
                                         (unsigned long)idx,
                                         candidate]);
                if ([self openImageAtURL:[NSURL fileURLWithPath:candidate]]) {
                    ScreenshotToolAppendLog([NSString stringWithFormat:@"applicationDidFinishLaunching: opened CLI arg[%lu]",
                                             (unsigned long)idx]);
                    break;
                } else {
                    ScreenshotToolAppendLog([NSString stringWithFormat:@"applicationDidFinishLaunching: failed to open CLI arg[%lu]",
                                             (unsigned long)idx]);
                }
            }
        }
    }

}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    ScreenshotToolAppendLog([NSString stringWithFormat:@"application:openFile: received %@", filename ?: @"<nil>"]);
    if (!self.canvasView) {
        self.pendingOpenPath = filename;
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Canvas not ready; deferring open for %@", filename ?: @"<nil>"]);
        return YES;
    }
    BOOL opened = [self openImageAtURL:[NSURL fileURLWithPath:filename]];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"application:openFile: %@ %@", opened ? @"opened" : @"failed",
                             filename ?: @"<nil>"]);
    return opened;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
    if (!flag) {
        [self.window makeKeyAndOrderFront:self];
    }
    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    if (action == @selector(saveDocumentAs:) || action == @selector(copy:) ||
        action == @selector(zoomIn:) || action == @selector(zoomOut:)) {
        return [self.canvasView hasImage];
    }
    if (action == @selector(cropImage:)) {
        return [self.canvasView hasSelection];
    }
    return YES;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem {
    NSString *identifier = toolbarItem.itemIdentifier;
    if ([identifier isEqualToString:ToolbarItemCopy]) {
        return [self.canvasView hasImage];
    }
    return YES;
}

#pragma mark - Setup

- (void)setupMenus {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"GSMainMenu"];
    [NSApp setMainMenu:mainMenu];

    NSString *appName = [[NSProcessInfo processInfo] processName];
    NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);

    NSMenuItem *appMenuItem = nil;
    NSMenu *appMenu = nil;

    if (style == NSWindows95InterfaceStyle && [mainMenu numberOfItems] > 0) {
        appMenuItem = [mainMenu itemAtIndex:0];
        appMenu = appMenuItem.submenu;
        if (!appMenu) {
            appMenu = [[NSMenu alloc] initWithTitle:appName];
            [mainMenu setSubmenu:appMenu forItem:appMenuItem];
        }
    } else {
        appMenuItem = [[NSMenuItem alloc] initWithTitle:appName action:NULL keyEquivalent:@""];
        appMenu = [[NSMenu alloc] initWithTitle:appName];
        [mainMenu addItem:appMenuItem];
        [mainMenu setSubmenu:appMenu forItem:appMenuItem];
    }

    NSString *aboutTitle = [NSString stringWithFormat:@"About %@", appName];
    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:aboutTitle
                                                       action:@selector(orderFrontStandardAboutPanel:)
                                                keyEquivalent:@""];
    [appMenu addItem:aboutItem];

    NSMenuItem *preferencesItem = [[NSMenuItem alloc] initWithTitle:@"Preferences…"
                                                             action:@selector(showPreferences:)
                                                      keyEquivalent:@","];
    [preferencesItem setTarget:self];
    [preferencesItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [appMenu addItem:preferencesItem];
    [appMenu addItem:[NSMenuItem separatorItem]];

    NSString *quitTitle = [NSString stringWithFormat:@"Quit %@", appName];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:quitTitle
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [quitItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [appMenu addItem:quitItem];

    // File menu
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];

    NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"Open…"
                                                      action:@selector(openDocument:)
                                               keyEquivalent:@"o"];
    [openItem setTarget:self];
    [openItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [fileMenu addItem:openItem];

    NSMenuItem *saveAsItem = [[NSMenuItem alloc] initWithTitle:@"Save As…"
                                                        action:@selector(saveDocumentAs:)
                                                 keyEquivalent:@"s"];
    [saveAsItem setTarget:self];
    [saveAsItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [fileMenu addItem:saveAsItem];

    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"File" action:NULL keyEquivalent:@""];
    [fileMenuItem setSubmenu:fileMenu];
    [mainMenu addItem:fileMenuItem];

    // Edit menu
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy"
                                                      action:@selector(copy:)
                                               keyEquivalent:@"c"];
    [copyItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [copyItem setTarget:self];
    [editMenu addItem:copyItem];

    NSMenuItem *cropSelectionItem = [[NSMenuItem alloc] initWithTitle:@"Crop to Selection"
                                                               action:@selector(cropImage:)
                                                        keyEquivalent:@"k"];
    [cropSelectionItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [cropSelectionItem setTarget:self];
    [editMenu addItem:cropSelectionItem];

    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    [editMenuItem setSubmenu:editMenu];
    [mainMenu addItem:editMenuItem];

    // View menu
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];

    NSMenuItem *zoomInItem = [[NSMenuItem alloc] initWithTitle:@"Zoom In"
                                                        action:@selector(zoomIn:)
                                                 keyEquivalent:@"="];
    [zoomInItem setTarget:self];
    [zoomInItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [viewMenu addItem:zoomInItem];

    NSMenuItem *zoomOutItem = [[NSMenuItem alloc] initWithTitle:@"Zoom Out"
                                                         action:@selector(zoomOut:)
                                                  keyEquivalent:@"-"];
    [zoomOutItem setTarget:self];
    [zoomOutItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [viewMenu addItem:zoomOutItem];

    NSMenuItem *viewMenuItem = [[NSMenuItem alloc] initWithTitle:@"View" action:NULL keyEquivalent:@""];
    [viewMenuItem setSubmenu:viewMenu];
    [mainMenu addItem:viewMenuItem];

    [NSApp setMainMenu:mainMenu];
    ScreenshotToolAppendLog(@"Main menu configured");
}

- (void)setupWindowAndContent {
    NSRect frame = NSMakeRect(100.0, 100.0, 1000.0, 700.0);
    NSUInteger styleMask = (NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable |
                            NSWindowStyleMaskResizable);

    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:styleMask
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [self.window setTitle:@"ScreenshotTool"];
    [self.window center];
    [self.window setDelegate:self];

    NSRect contentBounds = [[self.window contentView] bounds];
    NSView *container = [[NSView alloc] initWithFrame:contentBounds];
    container.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);

    NSRect scrollFrame = NSMakeRect(0.0f,
                                    StatusBarHeight,
                                    contentBounds.size.width,
                                    MAX(0.0f, contentBounds.size.height - StatusBarHeight));
    self.scrollView = [[NSScrollView alloc] initWithFrame:scrollFrame];
    [self.scrollView setAutoresizesSubviews:YES];
    [self.scrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [self.scrollView setHasVerticalScroller:NO];
    [self.scrollView setHasHorizontalScroller:NO];
    [self.scrollView setAutohidesScrollers:YES];
    [self.scrollView setBorderType:NSNoBorder];
    [self.scrollView setDrawsBackground:NO];

    self.canvasView = [[ScreenshotCanvasView alloc] initWithFrame:self.scrollView.contentView.bounds];
    self.canvasView.hostScrollView = self.scrollView;
    self.canvasView.autoresizingMask = NSViewNotSizable;
    self.canvasView.activeTool = ScreenshotCanvasToolHighlighter;
    self.canvasView.textColor = self.canvasView.penColor;

    [self.scrollView setDocumentView:self.canvasView];
    [container addSubview:self.scrollView];

    NSView *statusBar = [[NSView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, contentBounds.size.width, StatusBarHeight)];
    [statusBar setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    self.statusBarView = statusBar;
    [container addSubview:statusBar];

    NSTextField *statusField = [[NSTextField alloc] initWithFrame:NSInsetRect(statusBar.bounds, 8.0f, 4.0f)];
    [statusField setEditable:NO];
    [statusField setBezeled:NO];
    [statusField setBordered:NO];
    [statusField setDrawsBackground:NO];
    [statusField setTextColor:[NSColor secondaryLabelColor]];
    [statusField setFont:[NSFont systemFontOfSize:12.0f]];
    [statusField setAlignment:NSTextAlignmentLeft];
    statusField.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    [statusField setStringValue:@""];
    self.statusTextField = statusField;
    [statusBar addSubview:statusField];
    [self setupStatusControls];

    self.statusBarVisiblePreference = YES;

    [self.window setContentView:container];
    [self layoutContentSubviews];

    NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
    if (style == NSWindows95InterfaceStyle) {
        NSMenu *mainMenu = [NSApp mainMenu];
        if (mainMenu) {
            [self.window setMenu:mainMenu];
        }
    }
}

- (void)setupToolbar {
    self.toolbar = [[NSToolbar alloc] initWithIdentifier:ToolbarIdentifier];
    self.toolbar.delegate = self;
    self.toolbar.allowsUserCustomization = NO;
    self.toolbar.autosavesConfiguration = NO;
    self.toolbar.sizeMode = NSToolbarSizeModeRegular;
    self.toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(toolbarWillAddItemNotification:)
                                             name:NSToolbarWillAddItemNotification
                                           object:self.toolbar];

    [self.window setToolbar:self.toolbar];
    [self.toolbar setSelectedItemIdentifier:ToolbarItemHighlighter];
    [self refreshToolButtonIcons];
    (void)[self imageNamed:@"CopyImage-active"];
}

- (NSToolbarItemIdentifier)identifierForTool:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolHighlighter:
            return ToolbarItemHighlighter;
        case ScreenshotCanvasToolPen:
            return ToolbarItemPen;
        case ScreenshotCanvasToolEraser:
            return ToolbarItemEraser;
        case ScreenshotCanvasToolText:
            return ToolbarItemText;
        case ScreenshotCanvasToolSelect:
            return ToolbarItemSelect;
    }
    return nil;
}

- (BOOL)isIdentifierSelected:(NSToolbarItemIdentifier)identifier {
    NSToolbarItemIdentifier selected = [self identifierForTool:self.canvasView.activeTool];
    return (identifier != nil && selected != nil && [identifier isEqualToString:selected]);
}

- (NSToolbarItem *)toolbarItemForIdentifier:(NSToolbarItemIdentifier)identifier {
    for (NSToolbarItem *item in self.toolbar.items) {
        if ([item.itemIdentifier isEqualToString:identifier]) {
            return item;
        }
    }
    return nil;
}

- (NSString *)iconNameForToolbarIdentifier:(NSToolbarItemIdentifier)identifier active:(BOOL)active {
    if ([identifier isEqualToString:ToolbarItemHighlighter]) {
        return active ? @"Highligher-active" : @"Highligher";
    }
    if ([identifier isEqualToString:ToolbarItemPen]) {
        return active ? @"PenTool-active" : @"PenTool";
    }
    if ([identifier isEqualToString:ToolbarItemEraser]) {
        return active ? @"Eraser-active" : @"Eraser";
    }
    if ([identifier isEqualToString:ToolbarItemText]) {
        return active ? @"AddText-active" : @"AddText";
    }
    if ([identifier isEqualToString:ToolbarItemSelect]) {
        return active ? @"MarqueeTool-active" : @"MarqueeTool";
    }
    if ([identifier isEqualToString:ToolbarItemCopy]) {
        return @"CopyImage";
    }
    if ([identifier isEqualToString:ToolbarItemPreferences]) {
        return @"Preferences";
    }
    return nil;
}


#pragma mark - NSToolbarDelegate


#pragma mark - NSToolbarDelegate

- (NSString *)debugDescriptionForColor:(NSColor *)color {
    if (!color) {
        return @"<nil>";
    }
    NSColor *device = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color;
    return [NSString stringWithFormat:@"(r=%.3f g=%.3f b=%.3f a=%.3f)", device.redComponent, device.greenComponent, device.blueComponent, device.alphaComponent];
}

- (void)refreshToolButtonIcons {
    if (!self.toolbar) {
        ScreenshotToolAppendLog(@"refreshToolButtonIcons: toolbar unavailable");
        return;
    }
    NSToolbarItemIdentifier activeIdentifier = [self identifierForTool:self.canvasView.activeTool];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"refreshToolButtonIcons: active=%@", activeIdentifier]);

    NSArray<NSToolbarItemIdentifier> *toolIdentifiers = @[
        ToolbarItemSelect,
        ToolbarItemHighlighter,
        ToolbarItemPen,
        ToolbarItemEraser,
        ToolbarItemText
    ];
    for (NSToolbarItemIdentifier identifier in toolIdentifiers) {
        NSToolbarItem *item = [self toolbarItemForIdentifier:identifier];
        if (!item) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ missing", identifier]);
            continue;
        }

        NSString *toolTip = [self toolTipForIdentifier:identifier];
        if (toolTip) {
            item.toolTip = toolTip;
            if (item.view) {
                [item.view setToolTip:toolTip];
            }
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ tooltip set -> %@", identifier, toolTip]);
        } else {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ tooltip not updated", identifier]);
        }

        BOOL isActive = (activeIdentifier && [identifier isEqualToString:activeIdentifier]);
        NSString *iconName = [self iconNameForToolbarIdentifier:identifier active:isActive];
        if (!iconName && isActive) {
            iconName = [self iconNameForToolbarIdentifier:identifier active:NO];
        }
        if (!iconName) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ has no icon name (active=%@)", identifier, isActive ? @"YES" : @"NO"]);
            continue;
        }

        NSImage *icon = [self imageNamed:iconName];
        NSString *resolvedName = iconName;
        if (!icon && isActive) {
            NSString *fallbackName = [self iconNameForToolbarIdentifier:identifier active:NO];
            icon = [self imageNamed:fallbackName];
            resolvedName = fallbackName ?: iconName;
            if (icon) {
                ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ active icon missing, fell back to %@", identifier, resolvedName]);
            }
        }

        if (icon) {
            NSImage *rendered = [icon copy];
            NSColor *badgeColor = nil;
            if ([identifier isEqualToString:ToolbarItemPen]) {
                badgeColor = self.canvasView.penColor;
            } else if ([identifier isEqualToString:ToolbarItemHighlighter]) {
                badgeColor = self.canvasView.highlighterColor;
            } else if ([identifier isEqualToString:ToolbarItemText]) {
                badgeColor = self.canvasView.textColor;
            }
            if (badgeColor) {
                rendered = [self imageByAddingColorBadgeToImage:rendered color:badgeColor];
                ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ badge color %@", identifier, [self debugDescriptionForColor:badgeColor]]);
            }
            [rendered setSize:NSMakeSize(ToolbarIconDimension, ToolbarIconDimension)];
            item.image = rendered;
            if (item.view && [item.view respondsToSelector:@selector(setImage:)]) {
                id buttonView = item.view;
                if ([buttonView respondsToSelector:@selector(setImage:)]) {
                    [buttonView setImage:rendered];
                }
            }
            NSString *state = isActive ? @"active" : @"inactive";
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ set to %@ icon %@", identifier, state, resolvedName]);
        } else {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ missing icon %@", identifier, resolvedName]);
        }
    }
}

- (void)toolbarWillAddItemNotification:(NSNotification *)notification {
    NSToolbarItem *item = notification.userInfo[@"item"];
    [self applyToolTipToToolbarItem:item source:@"willAdd"];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[ToolbarItemSelect,
             ToolbarItemHighlighter,
             ToolbarItemPen,
             ToolbarItemText,
             ToolbarItemEraser,
             ToolbarItemCopy,
             ToolbarItemPreferences,
             ToolbarItemZoom,
             NSToolbarSpaceItemIdentifier,
             NSToolbarFlexibleSpaceItemIdentifier];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[ToolbarItemSelect,
             ToolbarItemHighlighter,
             ToolbarItemPen,
             ToolbarItemText,
             ToolbarItemEraser,
             ToolbarItemCopy,
             ToolbarItemPreferences,
             NSToolbarFlexibleSpaceItemIdentifier,
             ToolbarItemZoom,
             NSToolbarSpaceItemIdentifier];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
    itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {
    if ([itemIdentifier isEqualToString:ToolbarItemHighlighter]) {
        return [self standardToolbarItemWithIdentifier:ToolbarItemHighlighter
                                                 label:@"Highlighter"
                                                action:@selector(activateHighlighter:)];
    }
    if ([itemIdentifier isEqualToString:ToolbarItemPen]) {
        return [self standardToolbarItemWithIdentifier:ToolbarItemPen
                                                 label:@"Pen"
                                                action:@selector(activatePen:)];
    }
    if ([itemIdentifier isEqualToString:ToolbarItemText]) {
        return [self standardToolbarItemWithIdentifier:ToolbarItemText
                                                 label:@"Text"
                                                action:@selector(activateText:)];
    }
    if ([itemIdentifier isEqualToString:ToolbarItemSelect]) {
        return [self standardToolbarItemWithIdentifier:ToolbarItemSelect
                                                 label:@"Select"
                                                action:@selector(activateSelect:)];
    }
    if ([itemIdentifier isEqualToString:ToolbarItemEraser]) {
        return [self standardToolbarItemWithIdentifier:ToolbarItemEraser
                                                 label:@"Eraser"
                                                action:@selector(activateEraser:)];
    }
    if ([itemIdentifier isEqualToString:ToolbarItemCopy]) {
        return [self standardToolbarItemWithIdentifier:ToolbarItemCopy
                                                 label:@"Copy"
                                                action:@selector(copy:)];
    }
    if ([itemIdentifier isEqualToString:ToolbarItemPreferences]) {
        return [self standardToolbarItemWithIdentifier:ToolbarItemPreferences
                                                 label:@"Preferences"
                                                action:@selector(showPreferences:)];
    }
    if ([itemIdentifier isEqualToString:ToolbarItemZoom]) {
        return [self toolbarItemForZoomControl];
    }
    return nil;
}

- (NSToolbarItem *)standardToolbarItemWithIdentifier:(NSToolbarItemIdentifier)identifier
                                               label:(NSString *)label
                                              action:(SEL)selector {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"Standard item build %@", identifier]);
    item.label = label;
    item.paletteLabel = label;
    NSString *initialTip = [self toolTipForIdentifier:identifier] ?: label;
    item.toolTip = initialTip;
    ScreenshotToolAppendLog([NSString stringWithFormat:@"Set initial tooltip for %@ -> %@", identifier, initialTip]);
    item.target = self;
    item.action = selector;
    NSToolbarItemIdentifier activeIdentifier = [self identifierForTool:self.canvasView.activeTool];
    BOOL isActive = (activeIdentifier && [identifier isEqualToString:activeIdentifier]);
    NSString *iconName = [self iconNameForToolbarIdentifier:identifier active:isActive];
    if (!iconName) {
        iconName = [self iconNameForToolbarIdentifier:identifier active:NO];
    }
    if (iconName) {
        NSImage *icon = [self imageNamed:iconName];
        if (!icon && isActive) {
            icon = [self imageNamed:[self iconNameForToolbarIdentifier:identifier active:NO]];
        }
        if (icon) {
            if ([identifier isEqualToString:ToolbarItemPen]) {
                icon = [self imageByAddingColorBadgeToImage:icon color:self.canvasView.penColor];
            } else if ([identifier isEqualToString:ToolbarItemHighlighter]) {
                icon = [self imageByAddingColorBadgeToImage:icon color:self.canvasView.highlighterColor];
            } else if ([identifier isEqualToString:ToolbarItemText]) {
                icon = [self imageByAddingColorBadgeToImage:icon color:self.canvasView.textColor];
            }
            [icon setSize:NSMakeSize(ToolbarIconDimension, ToolbarIconDimension)];
            item.image = icon;
        }
    }
    return item;
}
- (NSToolbarItem *)toolbarItemForZoomControl {
    if (!self.zoomPopUpButton) {
        self.zoomPopUpButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 160.0, 28.0) pullsDown:NO];
        [self.zoomPopUpButton setAutoenablesItems:NO];
        NSArray *titles = @[@"Fit to Window", @"25%", @"50%", @"100%", @"200%"];
        [self.zoomPopUpButton removeAllItems];
        [self.zoomPopUpButton addItemsWithTitles:titles];
        [self.zoomPopUpButton setTarget:self];
        [self.zoomPopUpButton setAction:@selector(zoomPopUpAction:)];
        [self.zoomPopUpButton selectItemAtIndex:0];
    }

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ToolbarItemZoom];
    item.label = @"Zoom";
    item.paletteLabel = @"Zoom";
    item.view = self.zoomPopUpButton;
    item.minSize = NSMakeSize(160.0, 28.0);
    item.maxSize = NSMakeSize(180.0, 28.0);
    return item;
}

#pragma mark - Status Bar

- (void)setupStatusControls {
    if (!self.statusBarView) {
        return;
    }

    NSView *container = [[NSView alloc] initWithFrame:NSZeroRect];
    container.autoresizingMask = (NSViewMinXMargin | NSViewHeightSizable);
    self.statusControlsContainer = container;
    [self.statusBarView addSubview:container];

    NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [titleLabel setEditable:NO];
    [titleLabel setBezeled:NO];
    [titleLabel setBordered:NO];
    [titleLabel setDrawsBackground:NO];
    [titleLabel setAlignment:NSTextAlignmentRight];
    [titleLabel setFont:[NSFont boldSystemFontOfSize:12.0f]];
    self.toolWidthTitleLabel = titleLabel;
    [container addSubview:titleLabel];

    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    [slider setMinValue:STToolWidthMin];
    [slider setMaxValue:STToolWidthMax];
    [slider setDoubleValue:STHighlighterWidthDefault];
    [slider setContinuous:YES];
    [slider setNumberOfTickMarks:0];
    [slider setAltIncrementValue:1.0];
    slider.target = self;
    slider.action = @selector(toolWidthSliderChanged:);
    self.toolWidthSlider = slider;
    [container addSubview:slider];

    NSTextField *valueLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [valueLabel setEditable:NO];
    [valueLabel setBezeled:NO];
    [valueLabel setBordered:NO];
    [valueLabel setDrawsBackground:NO];
    [valueLabel setAlignment:NSTextAlignmentRight];
    [valueLabel setFont:[NSFont systemFontOfSize:12.0f]];
    [valueLabel setStringValue:@"0 px"];
    self.toolWidthValueLabel = valueLabel;
    [container addSubview:valueLabel];

    STHyperlinkButton *resetButton = [STHyperlinkButton hyperlinkButtonWithTitle:@"Reset"
                                                                           target:self
                                                                           action:@selector(resetActiveToolWidth:)];
    self.toolWidthResetButton = resetButton;
    [container addSubview:resetButton];

    STHyperlinkButton *defaultButton = [STHyperlinkButton hyperlinkButtonWithTitle:@"Set as Default"
                                                                            target:self
                                                                            action:@selector(setActiveToolWidthAsDefault:)];
    self.toolWidthSetDefaultButton = defaultButton;
    [container addSubview:defaultButton];

    container.hidden = NO;
    [self updateToolWidthControls];
}

- (void)layoutStatusControls {
    if (!self.statusBarView || !self.statusTextField) {
        return;
    }

    NSRect bounds = self.statusBarView.bounds;
    CGFloat padding = 8.0f;
    CGFloat verticalInset = 4.0f;
    CGFloat availableHeight = MAX(0.0f, bounds.size.height - (verticalInset * 2.0f));

    CGFloat controlsWidth = 0.0f;
    if (self.statusControlsContainer && !self.statusControlsContainer.isHidden) {
        [self.toolWidthResetButton sizeToFit];
        [self.toolWidthSetDefaultButton sizeToFit];

        NSSize titleSize = self.toolWidthTitleLabel ? [[self.toolWidthTitleLabel cell] cellSize] : NSZeroSize;
        NSSize valueSize = self.toolWidthValueLabel ? [[self.toolWidthValueLabel cell] cellSize] : NSZeroSize;
        NSSize resetSize = self.toolWidthResetButton.frame.size;
        NSSize defaultSize = self.toolWidthSetDefaultButton.frame.size;

        CGFloat labelWidth = MAX(100.0f, titleSize.width + 6.0f);
        CGFloat valueWidth = MAX(52.0f, valueSize.width + 10.0f);
        CGFloat sliderWidth = MIN(280.0f, MAX(220.0f, bounds.size.width * 0.30f));
        CGFloat spacing = 6.0f;
        controlsWidth = labelWidth + sliderWidth + valueWidth + resetSize.width + defaultSize.width + (spacing * 4.0f);

        CGFloat maxControlsWidth = bounds.size.width - (padding * 2.0f);
        if (controlsWidth > maxControlsWidth) {
            sliderWidth = MAX(140.0f, maxControlsWidth - (labelWidth + valueWidth + resetSize.width + defaultSize.width + (spacing * 4.0f)));
            controlsWidth = labelWidth + sliderWidth + valueWidth + resetSize.width + defaultSize.width + (spacing * 4.0f);
        }

        CGFloat containerX = bounds.size.width - padding - controlsWidth;
        if (containerX < padding) {
            containerX = padding;
        }

        NSRect containerFrame = NSMakeRect(containerX,
                                           verticalInset,
                                           controlsWidth,
                                           availableHeight);
        [self.statusControlsContainer setFrame:containerFrame];

        CGFloat controlHeight = MIN(availableHeight, 18.0f);
        CGFloat centerY = (containerFrame.size.height - controlHeight) / 2.0f;
        CGFloat x = 0.0f;

        if (self.toolWidthTitleLabel) {
            self.toolWidthTitleLabel.frame = NSMakeRect(x, centerY, labelWidth, controlHeight);
        }
        x += labelWidth + spacing;

        if (self.toolWidthSlider) {
            CGFloat sliderHeight = MIN(16.0f, availableHeight);
            self.toolWidthSlider.frame = NSMakeRect(x,
                                                    (containerFrame.size.height - sliderHeight) / 2.0f,
                                                    sliderWidth,
                                                    sliderHeight);
        }
        x += sliderWidth + spacing;

        if (self.toolWidthValueLabel) {
            self.toolWidthValueLabel.frame = NSMakeRect(x, centerY, valueWidth, controlHeight);
        }
        x += valueWidth + spacing;

        CGFloat resetHeight = MIN(controlHeight, resetSize.height);
        self.toolWidthResetButton.frame = NSMakeRect(x,
                                                     (containerFrame.size.height - resetHeight) / 2.0f,
                                                     resetSize.width,
                                                     resetHeight);
        x += resetSize.width + spacing;

        CGFloat defaultHeight = MIN(controlHeight, defaultSize.height);
        self.toolWidthSetDefaultButton.frame = NSMakeRect(x,
                                                          (containerFrame.size.height - defaultHeight) / 2.0f,
                                                          defaultSize.width,
                                                          defaultHeight);
    } else if (self.statusControlsContainer) {
        self.statusControlsContainer.frame = NSMakeRect(bounds.size.width - padding,
                                                        verticalInset,
                                                        0.0f,
                                                        availableHeight);
    }

    CGFloat textWidth = MAX(0.0f, bounds.size.width - (padding * 2.0f));
    if (self.statusControlsContainer && !self.statusControlsContainer.isHidden) {
        CGFloat limit = self.statusControlsContainer.frame.origin.x - padding;
        textWidth = MAX(0.0f, limit - padding);
    }
    self.statusTextField.frame = NSMakeRect(padding,
                                            verticalInset,
                                            textWidth,
                                            availableHeight);
}

- (CGFloat)statusBarHeight {
    return self.statusBarVisiblePreference ? StatusBarHeight : 0.0f;
}

- (void)updateStatusBarVisibility {
    BOOL show = self.statusBarVisiblePreference;
    if (self.statusBarView) {
        [self.statusBarView setHidden:!show];
    }
    if (self.statusControlsContainer) {
        [self.statusControlsContainer setHidden:!show];
    }
    if (self.statusTextField) {
        [self.statusTextField setHidden:!show];
    }
    if (!show) {
        [self.statusClearTimer invalidate];
        self.statusClearTimer = nil;
    }
    [self layoutContentSubviews];
}

- (void)loadToolSettingsFromDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.penDefaultWidth = [self storedWidthForKey:STDefaultsPenDefaultWidthKey
                                          fallback:STPenWidthDefault
                               registerIfMissing:YES];
    self.highlighterDefaultWidth = [self storedWidthForKey:STDefaultsHighlighterDefaultWidthKey
                                                  fallback:STHighlighterWidthDefault
                                       registerIfMissing:YES];

    CGFloat penWidth = [self storedWidthForKey:STDefaultsPenWidthKey
                                      fallback:self.penDefaultWidth
                           registerIfMissing:YES];
    CGFloat highlighterWidth = [self storedWidthForKey:STDefaultsHighlighterWidthKey
                                              fallback:self.highlighterDefaultWidth
                                   registerIfMissing:YES];

    self.canvasView.penLineWidth = penWidth;
    self.canvasView.highlighterLineWidth = highlighterWidth;

    self.penDefaultColor = [self storedColorForKey:STDefaultsPenDefaultColorKey
                                          fallback:STDefaultPenColor()
                               registerIfMissing:YES];
    self.highlighterDefaultColor = [self storedColorForKey:STDefaultsHighlighterDefaultColorKey
                                                  fallback:STDefaultHighlighterColor()
                                       registerIfMissing:YES];
    self.textDefaultColor = [self storedColorForKey:STDefaultsTextDefaultColorKey
                                           fallback:STDefaultTextColor()
                                registerIfMissing:YES];
    self.textDefaultFont = [self storedFontWithNameKey:STDefaultsTextDefaultFontNameKey
                                               sizeKey:STDefaultsTextDefaultFontSizeKey
                                              fallback:STDefaultTextFont()
                                   registerIfMissing:YES];

    NSColor *penColor = [self storedColorForKey:STDefaultsPenColorKey
                                       fallback:self.penDefaultColor
                            registerIfMissing:YES];
    NSColor *highlighterColor = [self storedColorForKey:STDefaultsHighlighterColorKey
                                              fallback:self.highlighterDefaultColor
                                   registerIfMissing:YES];
    NSColor *textColor = [self storedColorForKey:STDefaultsTextColorKey
                                         fallback:self.textDefaultColor
                              registerIfMissing:YES];
    NSFont *textFont = [self storedFontWithNameKey:STDefaultsTextFontNameKey
                                           sizeKey:STDefaultsTextFontSizeKey
                                          fallback:self.textDefaultFont
                               registerIfMissing:YES];

    self.canvasView.penColor = penColor;
    self.canvasView.highlighterColor = highlighterColor;
    self.canvasView.textColor = textColor;
    self.canvasView.textFont = textFont;
    [self.canvasView refreshCursor];
    [self refreshToolButtonIcons];
    [self updateToolWidthControls];

    NSString *savedDirectory = [defaults stringForKey:STDefaultsSaveDirectoryKey];
    if (savedDirectory.length == 0) {
        savedDirectory = [@"~/Pictures/Screenshots" stringByExpandingTildeInPath];
        [defaults setObject:savedDirectory forKey:STDefaultsSaveDirectoryKey];
    }
    self.defaultSaveDirectory = savedDirectory;
    [self ensureDirectoryExistsAtPath:self.defaultSaveDirectory];

    if ([defaults objectForKey:STDefaultsShowStatusBarKey] == nil) {
        [defaults setBool:YES forKey:STDefaultsShowStatusBarKey];
    }
    self.statusBarVisiblePreference = [defaults boolForKey:STDefaultsShowStatusBarKey];
    [self updateStatusBarVisibility];

    if (self.preferencesWindowController) {
        [self.preferencesWindowController refresh];
    }
}

- (CGFloat)storedWidthForKey:(NSString *)key
                    fallback:(CGFloat)fallback
         registerIfMissing:(BOOL)registerDefault {
    if (key.length == 0) {
        return fallback;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id value = [defaults objectForKey:key];
    if (!value) {
        if (registerDefault) {
            [defaults setDouble:fallback forKey:key];
        }
        return [self clampedWidth:fallback];
    }
    double number = [value doubleValue];
    if (number <= 0.0) {
        number = fallback;
    }
    return [self clampedWidth:(CGFloat)number];
}

- (void)updateToolWidthControls {
    if (!self.toolWidthSlider || !self.toolWidthTitleLabel) {
        return;
    }
    ScreenshotCanvasTool tool = [self widthTargetTool];
    CGFloat currentWidth = [self currentWidthForTool:tool];
    CGFloat defaultWidth = [self defaultWidthForTool:tool];
    NSString *title = [self titleForToolWidth:tool];
    [self.toolWidthTitleLabel setStringValue:title];
    [self.toolWidthSlider setMinValue:STToolWidthMin];
    [self.toolWidthSlider setMaxValue:STToolWidthMax];
    [self.toolWidthSlider setDoubleValue:currentWidth];
    [self updateToolWidthValueLabelWithWidth:currentWidth];
    BOOL canReset = fabs(currentWidth - defaultWidth) > 0.01f;
    [self.toolWidthResetButton setEnabled:canReset];
    [self.toolWidthSetDefaultButton setEnabled:canReset];
    [self layoutStatusControls];
}

- (ScreenshotCanvasTool)widthTargetTool {
    ScreenshotCanvasTool tool = self.canvasView.activeTool;
    if (tool == ScreenshotCanvasToolPen || tool == ScreenshotCanvasToolHighlighter) {
        self.lastWidthTool = tool;
        return tool;
    }
    if (self.lastWidthTool == ScreenshotCanvasToolPen || self.lastWidthTool == ScreenshotCanvasToolHighlighter) {
        return self.lastWidthTool;
    }
    self.lastWidthTool = ScreenshotCanvasToolHighlighter;
    return self.lastWidthTool;
}

- (NSString *)titleForToolWidth:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolPen:
            return @"Pen Width";
        case ScreenshotCanvasToolHighlighter:
            return @"Highlighter Width";
        default:
            break;
    }
    return @"Tool Width";
}

- (CGFloat)currentWidthForTool:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolPen:
            return [self clampedWidth:self.canvasView.penLineWidth];
        case ScreenshotCanvasToolHighlighter:
            return [self clampedWidth:self.canvasView.highlighterLineWidth];
        default:
            return 0.0f;
    }
}

- (CGFloat)defaultWidthForTool:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolPen:
            return [self clampedWidth:self.penDefaultWidth];
        case ScreenshotCanvasToolHighlighter:
            return [self clampedWidth:self.highlighterDefaultWidth];
        default:
            return STPenWidthDefault;
    }
}

- (void)updateToolWidthValueLabelWithWidth:(CGFloat)width {
    if (!self.toolWidthValueLabel) {
        return;
    }
    NSString *value = [NSString stringWithFormat:@"%.0f px", roundf(width)];
    [self.toolWidthValueLabel setStringValue:value];
}

- (CGFloat)clampedWidth:(CGFloat)value {
    if (value < STToolWidthMin) {
        return STToolWidthMin;
    }
    if (value > STToolWidthMax) {
        return STToolWidthMax;
    }
    return value;
}

- (void)toolWidthSliderChanged:(NSSlider *)slider {
    ScreenshotCanvasTool tool = [self widthTargetTool];
    CGFloat rawValue = slider.doubleValue;
    CGFloat rounded = roundf(rawValue);
    CGFloat clamped = [self clampedWidth:rounded];
    if (fabs(clamped - rawValue) > 0.01f) {
        [slider setDoubleValue:clamped];
    }
    [self applyWidth:clamped toTool:tool persist:YES];
}

- (void)resetActiveToolWidth:(id)sender {
    ScreenshotCanvasTool tool = [self widthTargetTool];
    CGFloat defaultWidth = [self defaultWidthForTool:tool];
    [self applyWidth:defaultWidth toTool:tool persist:YES];
    NSString *message = [NSString stringWithFormat:@"%@ reset to %.0f px",
                         [self titleForToolWidth:tool],
                         roundf(defaultWidth)];
    [self showStatusMessage:message duration:2.0];
}

- (void)setActiveToolWidthAsDefault:(id)sender {
    ScreenshotCanvasTool tool = [self widthTargetTool];
    CGFloat width = [self currentWidthForTool:tool];
    [self setDefaultWidth:width forTool:tool];
    NSString *message = [NSString stringWithFormat:@"%@ default set to %.0f px",
                         [self titleForToolWidth:tool],
                         roundf(width)];
    [self showStatusMessage:message duration:2.0];
    [self updateToolWidthControls];
}

- (void)setDefaultWidth:(CGFloat)width forTool:(ScreenshotCanvasTool)tool {
    CGFloat clamped = [self clampedWidth:width];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    switch (tool) {
        case ScreenshotCanvasToolPen:
            self.penDefaultWidth = clamped;
            [defaults setDouble:clamped forKey:STDefaultsPenDefaultWidthKey];
            break;
        case ScreenshotCanvasToolHighlighter:
            self.highlighterDefaultWidth = clamped;
            [defaults setDouble:clamped forKey:STDefaultsHighlighterDefaultWidthKey];
            break;
        default:
            break;
    }
}

- (void)applyWidth:(CGFloat)width
           toTool:(ScreenshotCanvasTool)tool
          persist:(BOOL)persist {
    CGFloat clamped = [self clampedWidth:width];
    switch (tool) {
        case ScreenshotCanvasToolPen:
            self.canvasView.penLineWidth = clamped;
            if (persist) {
                [[NSUserDefaults standardUserDefaults] setDouble:clamped forKey:STDefaultsPenWidthKey];
            }
            break;
        case ScreenshotCanvasToolHighlighter:
            self.canvasView.highlighterLineWidth = clamped;
            if (persist) {
                [[NSUserDefaults standardUserDefaults] setDouble:clamped forKey:STDefaultsHighlighterWidthKey];
            }
            break;
        default:
            break;
    }
    ScreenshotCanvasTool displayedTool = [self widthTargetTool];
    if (displayedTool == tool) {
        [self.toolWidthSlider setDoubleValue:clamped];
        [self updateToolWidthValueLabelWithWidth:clamped];
    }
    [self.canvasView setNeedsDisplay:YES];
    [self updateToolWidthControls];
    if (self.preferencesWindowController) {
        [self.preferencesWindowController refresh];
    }
}

#pragma mark - Tool Appearance

- (NSColor *)storedColorForKey:(NSString *)key
                       fallback:(NSColor *)fallback
            registerIfMissing:(BOOL)registerDefault {
    if (key.length == 0) {
        return fallback ?: STDefaultPenColor();
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *encoded = [defaults stringForKey:key];
    if (encoded.length == 0) {
        if (registerDefault && fallback) {
            [defaults setObject:STEncodeColor(fallback) forKey:key];
        }
        return fallback ? [fallback copy] : STDefaultPenColor();
    }
    NSColor *decoded = STDecodeColor(encoded, fallback);
    return decoded ?: (fallback ? [fallback copy] : STDefaultPenColor());
}

- (void)persistColor:(NSColor *)color forKey:(NSString *)key {
    if (key.length == 0) {
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (!color) {
        [defaults removeObjectForKey:key];
        return;
    }
    NSString *encoded = STEncodeColor(color);
    if (encoded.length > 0) {
        [defaults setObject:encoded forKey:key];
    }
}

- (NSFont *)storedFontWithNameKey:(NSString *)nameKey
                            sizeKey:(NSString *)sizeKey
                           fallback:(NSFont *)fallback
                registerIfMissing:(BOOL)registerDefault {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *name = nameKey.length > 0 ? [defaults stringForKey:nameKey] : nil;
    double sizeValue = (sizeKey.length > 0) ? [defaults doubleForKey:sizeKey] : 0.0;
    if (name.length == 0 || sizeValue <= 0.0) {
        if (registerDefault && fallback) {
            if (nameKey.length > 0) {
                [defaults setObject:fallback.fontName forKey:nameKey];
            }
            if (sizeKey.length > 0) {
                [defaults setDouble:fallback.pointSize forKey:sizeKey];
            }
        }
        return fallback ?: STDefaultTextFont();
    }
    NSFont *font = [NSFont fontWithName:name size:(CGFloat)sizeValue];
    if (!font) {
        font = fallback ?: STDefaultTextFont();
    }
    return font;
}

- (void)persistFont:(NSFont *)font nameKey:(NSString *)nameKey sizeKey:(NSString *)sizeKey {
    if (!font) {
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (nameKey.length > 0) {
        [defaults setObject:font.fontName ?: font.familyName ?: @"" forKey:nameKey];
    }
    if (sizeKey.length > 0) {
        [defaults setDouble:font.pointSize forKey:sizeKey];
    }
}

- (NSColor *)currentColorForTool:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolPen:
            return self.canvasView.penColor;
        case ScreenshotCanvasToolHighlighter:
            return self.canvasView.highlighterColor;
        case ScreenshotCanvasToolText:
            return self.canvasView.textColor;
        default:
            return nil;
    }
}

- (NSColor *)defaultColorForTool:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolPen:
            return self.penDefaultColor ?: STDefaultPenColor();
        case ScreenshotCanvasToolHighlighter:
            return self.highlighterDefaultColor ?: STDefaultHighlighterColor();
        case ScreenshotCanvasToolText:
            return self.textDefaultColor ?: STDefaultTextColor();
        default:
            return STDefaultPenColor();
    }
}

- (void)setDefaultColor:(NSColor *)color forTool:(ScreenshotCanvasTool)tool {
    NSColor *resolved = color ?: STDefaultPenColor();
    switch (tool) {
        case ScreenshotCanvasToolPen:
            self.penDefaultColor = resolved;
            [self persistColor:resolved forKey:STDefaultsPenDefaultColorKey];
            break;
        case ScreenshotCanvasToolHighlighter:
            self.highlighterDefaultColor = resolved;
            [self persistColor:resolved forKey:STDefaultsHighlighterDefaultColorKey];
            break;
        case ScreenshotCanvasToolText:
            self.textDefaultColor = resolved;
            [self persistColor:resolved forKey:STDefaultsTextDefaultColorKey];
            break;
        default:
            break;
    }
}

- (void)applyColor:(NSColor *)color toTool:(ScreenshotCanvasTool)tool persist:(BOOL)persist {
    NSColor *resolved = color ?: [self defaultColorForTool:tool];
    switch (tool) {
        case ScreenshotCanvasToolPen:
            self.canvasView.penColor = resolved;
            if (persist) {
                [self persistColor:resolved forKey:STDefaultsPenColorKey];
            }
            break;
        case ScreenshotCanvasToolHighlighter:
            self.canvasView.highlighterColor = resolved;
            if (persist) {
                [self persistColor:resolved forKey:STDefaultsHighlighterColorKey];
            }
            break;
        case ScreenshotCanvasToolText:
            self.canvasView.textColor = resolved;
            if (persist) {
                [self persistColor:resolved forKey:STDefaultsTextColorKey];
            }
            break;
        default:
            break;
    }
    [self.canvasView refreshCursor];
    [self refreshToolButtonIcons];
    [self.canvasView setNeedsDisplay:YES];
    if (self.preferencesWindowController) {
        [self.preferencesWindowController refresh];
    }
}

- (void)setDefaultTextFont:(NSFont *)font {
    self.textDefaultFont = font ?: STDefaultTextFont();
    [self persistFont:self.textDefaultFont nameKey:STDefaultsTextDefaultFontNameKey sizeKey:STDefaultsTextDefaultFontSizeKey];
}

- (void)applyTextFont:(NSFont *)font persist:(BOOL)persist {
    NSFont *resolved = font ?: (self.textDefaultFont ?: STDefaultTextFont());
    self.canvasView.textFont = resolved;
    if (persist) {
        [self persistFont:resolved nameKey:STDefaultsTextFontNameKey sizeKey:STDefaultsTextFontSizeKey];
    }
    [self.canvasView setNeedsDisplay:YES];
    if (self.preferencesWindowController) {
        [self.preferencesWindowController refresh];
    }
}

- (void)ensureDirectoryExistsAtPath:(NSString *)path {
    if (path.length == 0) {
        return;
    }
    BOOL isDir = NO;
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:path isDirectory:&isDir] || !isDir) {
        [manager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (void)closeActivePopovers {
    BOOL penWasShown = self.penPopoverController.isShown;
    BOOL highlighterWasShown = self.highlighterPopoverController.isShown;
    BOOL textWasShown = self.textPopoverController.isShown;
    ScreenshotToolAppendLog([NSString stringWithFormat:@"closeActivePopovers called (penShown=%@ highlighterShown=%@ textShown=%@)",
                             penWasShown ? @"YES" : @"NO",
                             highlighterWasShown ? @"YES" : @"NO",
                             textWasShown ? @"YES" : @"NO"]);
    [self.penPopoverController close];
    [self.highlighterPopoverController close];
    [self.textPopoverController close];
}

- (ToolSettingsPopoverController *)popoverControllerForTool:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolPen:
            if (!self.penPopoverController) {
                self.penPopoverController = [[ToolSettingsPopoverController alloc] initWithTool:ScreenshotCanvasToolPen];
                self.penPopoverController.delegate = self;
                ScreenshotToolAppendLog(@"Created Pen ToolSettingsPopoverController");
            }
            return self.penPopoverController;
        case ScreenshotCanvasToolHighlighter:
            if (!self.highlighterPopoverController) {
                self.highlighterPopoverController = [[ToolSettingsPopoverController alloc] initWithTool:ScreenshotCanvasToolHighlighter];
                self.highlighterPopoverController.delegate = self;
                ScreenshotToolAppendLog(@"Created Highlighter ToolSettingsPopoverController");
            }
            return self.highlighterPopoverController;
        default:
            return nil;
    }
}

- (TextToolPopoverController *)textSettingsPopoverController {
    if (!self.textPopoverController) {
        self.textPopoverController = [[TextToolPopoverController alloc] init];
        self.textPopoverController.delegate = self;
        ScreenshotToolAppendLog(@"Created TextToolPopoverController");
    }
    return self.textPopoverController;
}

- (NSRect)anchorRectForEvent:(NSEvent *)event inView:(NSView *)view {
    if (!view) {
        return NSZeroRect;
    }
    NSPoint location = event ? [view convertPoint:event.locationInWindow fromView:nil] : NSMakePoint(NSMidX(view.bounds), NSMaxY(view.bounds) - 4.0f);
    location.x = MAX(4.0f, MIN(location.x, view.bounds.size.width - 4.0f));
    location.y = view.bounds.size.height - 2.0f;
    return NSMakeRect(location.x - 2.0f, location.y - 2.0f, 4.0f, 4.0f);
}

- (BOOL)isDoubleClickEvent:(NSEvent *)event {
    if (!event) {
        ScreenshotToolAppendLog(@"isDoubleClickEvent: nil NSEvent encountered");
        return NO;
    }
    NSEventType type = event.type;
    if (type != NSEventTypeLeftMouseDown && type != NSEventTypeLeftMouseUp) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"isDoubleClickEvent: ignored event type %ld (clickCount=%ld)",
                                 (long)type,
                                 (long)event.clickCount]);
        return NO;
    }
    BOOL result = event.clickCount >= 2;
    if (!result) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"isDoubleClickEvent: clickCount %ld below threshold",
                                 (long)event.clickCount]);
    } else {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"isDoubleClickEvent: detected double-click with clickCount=%ld",
                                 (long)event.clickCount]);
    }
    return result;
}

- (void)showToolSettingsPopoverForTool:(ScreenshotCanvasTool)tool event:(NSEvent *)event {
    NSView *anchorView = self.window.contentView;
    if (!anchorView) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Skipping popover for %@: missing content view",
                                 STDebugToolName(tool)]);
        return;
    }
    NSRect anchor = [self anchorRectForEvent:event inView:anchorView];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"Requesting %@ popover (anchorView=%@ rect=%@ event=%@)",
                             STDebugToolName(tool),
                             NSStringFromClass([anchorView class]),
                             NSStringFromRect(anchor),
                             STDebugDescriptionForEvent(event)]);
    if (tool == ScreenshotCanvasToolPen || tool == ScreenshotCanvasToolHighlighter) {
        ToolSettingsPopoverController *controller = [self popoverControllerForTool:tool];
        if (!controller) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Popover controller unavailable for %@",
                                     STDebugToolName(tool)]);
            return;
        }
        BOOL wasShown = controller.isShown;
        [controller showRelativeToRect:anchor ofView:anchorView preferredEdge:NSMaxYEdge];
        ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ popover show invoked (wasShown=%@ nowShown=%@)",
                                 STDebugToolName(tool),
                                 wasShown ? @"YES" : @"NO",
                                 controller.isShown ? @"YES" : @"NO"]);
    } else if (tool == ScreenshotCanvasToolText) {
        TextToolPopoverController *controller = [self textSettingsPopoverController];
        if (!controller) {
            ScreenshotToolAppendLog(@"Popover controller unavailable for Text tool");
            return;
        }
        BOOL wasShown = controller.isShown;
        [controller showRelativeToRect:anchor ofView:anchorView preferredEdge:NSMaxYEdge];
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Text popover show invoked (wasShown=%@ nowShown=%@)",
                                 wasShown ? @"YES" : @"NO",
                                 controller.isShown ? @"YES" : @"NO"]);
    } else {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"No popover registered for %@", STDebugToolName(tool)]);
    }
}

#pragma mark - ToolSettingsPopoverControllerDelegate

- (CGFloat)toolSettingsPopover:(ToolSettingsPopoverController *)controller currentWidthForTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    return [self currentWidthForTool:tool];
}

- (CGFloat)toolSettingsPopover:(ToolSettingsPopoverController *)controller defaultWidthForTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    return [self defaultWidthForTool:tool];
}

- (void)toolSettingsPopover:(ToolSettingsPopoverController *)controller didChangeWidth:(CGFloat)width forTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    [self applyWidth:width toTool:tool persist:YES];
}

- (NSColor *)toolSettingsPopover:(ToolSettingsPopoverController *)controller currentColorForTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    return [self currentColorForTool:tool];
}

- (NSColor *)toolSettingsPopover:(ToolSettingsPopoverController *)controller defaultColorForTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    return [self defaultColorForTool:tool];
}

- (void)toolSettingsPopover:(ToolSettingsPopoverController *)controller didChangeColor:(NSColor *)color forTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    [self applyColor:color toTool:tool persist:YES];
}

- (void)toolSettingsPopoverDidRequestReset:(ToolSettingsPopoverController *)controller forTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    CGFloat width = [self defaultWidthForTool:tool];
    NSColor *color = [self defaultColorForTool:tool];
    [self applyWidth:width toTool:tool persist:YES];
    [self applyColor:color toTool:tool persist:YES];
    NSString *message = [NSString stringWithFormat:@"%@ reset to defaults", [self titleForToolWidth:tool]];
    [self showStatusMessage:message duration:2.0];
}

- (void)toolSettingsPopoverDidRequestSetDefault:(ToolSettingsPopoverController *)controller forTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    CGFloat width = [self currentWidthForTool:tool];
    NSColor *color = [self currentColorForTool:tool];
    [self setDefaultWidth:width forTool:tool];
    [self setDefaultColor:color forTool:tool];
    NSString *message = [NSString stringWithFormat:@"%@ defaults updated", [self titleForToolWidth:tool]];
    [self showStatusMessage:message duration:2.0];
    [self updateToolWidthControls];
}

#pragma mark - TextToolPopoverControllerDelegate

- (NSColor *)textToolPopoverCurrentColor:(TextToolPopoverController *)controller {
    (void)controller;
    return self.canvasView.textColor;
}

- (NSColor *)textToolPopoverDefaultColor:(TextToolPopoverController *)controller {
    (void)controller;
    return self.textDefaultColor ?: STDefaultTextColor();
}

- (void)textToolPopover:(TextToolPopoverController *)controller didChangeColor:(NSColor *)color {
    (void)controller;
    [self applyColor:color toTool:ScreenshotCanvasToolText persist:YES];
}

- (NSFont *)textToolPopoverCurrentFont:(TextToolPopoverController *)controller {
    (void)controller;
    return self.canvasView.textFont ?: STDefaultTextFont();
}

- (NSFont *)textToolPopoverDefaultFont:(TextToolPopoverController *)controller {
    (void)controller;
    return self.textDefaultFont ?: STDefaultTextFont();
}

- (void)textToolPopover:(TextToolPopoverController *)controller didChangeFont:(NSFont *)font {
    (void)controller;
    [self applyTextFont:font persist:YES];
}

- (void)textToolPopoverDidRequestReset:(TextToolPopoverController *)controller {
    (void)controller;
    [self applyColor:self.textDefaultColor toTool:ScreenshotCanvasToolText persist:YES];
    [self applyTextFont:self.textDefaultFont persist:YES];
    [self showStatusMessage:@"Text defaults restored" duration:2.0];
}

- (void)textToolPopoverDidRequestSetDefault:(TextToolPopoverController *)controller {
    (void)controller;
    NSColor *color = self.canvasView.textColor ?: STDefaultTextColor();
    NSFont *font = self.canvasView.textFont ?: STDefaultTextFont();
    [self setDefaultColor:color forTool:ScreenshotCanvasToolText];
    [self setDefaultTextFont:font];
    [self showStatusMessage:@"Text defaults updated" duration:2.0];
}

#pragma mark - PreferencesWindowControllerDelegate

- (CGFloat)preferencesController:(PreferencesWindowController *)controller defaultWidthForTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    return [self defaultWidthForTool:tool];
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultWidth:(CGFloat)width forTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    [self setDefaultWidth:width forTool:tool];
    [self applyWidth:width toTool:tool persist:YES];
}

- (NSColor *)preferencesController:(PreferencesWindowController *)controller defaultColorForTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    return [self defaultColorForTool:tool];
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultColor:(NSColor *)color forTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    [self setDefaultColor:color forTool:tool];
    [self applyColor:color toTool:tool persist:YES];
}

- (NSFont *)preferencesControllerDefaultTextFont:(PreferencesWindowController *)controller {
    (void)controller;
    return self.textDefaultFont ?: STDefaultTextFont();
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultTextFont:(NSFont *)font {
    (void)controller;
    [self setDefaultTextFont:font];
    [self applyTextFont:font persist:YES];
}

- (NSColor *)preferencesControllerDefaultTextColor:(PreferencesWindowController *)controller {
    (void)controller;
    return self.textDefaultColor ?: STDefaultTextColor();
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultTextColor:(NSColor *)color {
    (void)controller;
    [self setDefaultColor:color forTool:ScreenshotCanvasToolText];
    [self applyColor:color toTool:ScreenshotCanvasToolText persist:YES];
}

- (NSString *)preferencesControllerDefaultSaveDirectory:(PreferencesWindowController *)controller {
    (void)controller;
    return self.defaultSaveDirectory ?: @"";
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultSaveDirectory:(NSString *)path {
    (void)controller;
    if (path.length == 0) {
        return;
    }
    NSString *expanded = [path stringByExpandingTildeInPath];
    self.defaultSaveDirectory = expanded;
    [[NSUserDefaults standardUserDefaults] setObject:expanded forKey:STDefaultsSaveDirectoryKey];
    [self ensureDirectoryExistsAtPath:expanded];
    if (self.preferencesWindowController) {
        [self.preferencesWindowController refresh];
    }
}

- (BOOL)preferencesControllerShouldShowStatusBar:(PreferencesWindowController *)controller {
    (void)controller;
    return self.statusBarVisiblePreference;
}

- (void)preferencesController:(PreferencesWindowController *)controller didToggleStatusBar:(BOOL)show {
    (void)controller;
    self.statusBarVisiblePreference = show;
    [[NSUserDefaults standardUserDefaults] setBool:show forKey:STDefaultsShowStatusBarKey];
    [self updateStatusBarVisibility];
}

- (void)preferencesControllerRestoreDefaults:(PreferencesWindowController *)controller {
    (void)controller;
    [self setDefaultWidth:STPenWidthDefault forTool:ScreenshotCanvasToolPen];
    [self applyWidth:STPenWidthDefault toTool:ScreenshotCanvasToolPen persist:YES];
    [self setDefaultWidth:STHighlighterWidthDefault forTool:ScreenshotCanvasToolHighlighter];
    [self applyWidth:STHighlighterWidthDefault toTool:ScreenshotCanvasToolHighlighter persist:YES];

    NSColor *penColor = STDefaultPenColor();
    [self setDefaultColor:penColor forTool:ScreenshotCanvasToolPen];
    [self applyColor:penColor toTool:ScreenshotCanvasToolPen persist:YES];

    NSColor *highlighterColor = STDefaultHighlighterColor();
    [self setDefaultColor:highlighterColor forTool:ScreenshotCanvasToolHighlighter];
    [self applyColor:highlighterColor toTool:ScreenshotCanvasToolHighlighter persist:YES];

    NSColor *textColor = STDefaultTextColor();
    [self setDefaultColor:textColor forTool:ScreenshotCanvasToolText];
    [self applyColor:textColor toTool:ScreenshotCanvasToolText persist:YES];

    NSFont *textFont = STDefaultTextFont();
    [self setDefaultTextFont:textFont];
    [self applyTextFont:textFont persist:YES];

    NSString *fallbackDirectory = [@"~/Pictures/Screenshots" stringByExpandingTildeInPath];
    self.defaultSaveDirectory = fallbackDirectory;
    [[NSUserDefaults standardUserDefaults] setObject:fallbackDirectory forKey:STDefaultsSaveDirectoryKey];
    [self ensureDirectoryExistsAtPath:fallbackDirectory];

    self.statusBarVisiblePreference = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:STDefaultsShowStatusBarKey];
    [self updateStatusBarVisibility];

    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateToolWidthControls];
    [self showStatusMessage:@"Preferences restored" duration:2.0];
}

- (void)preferencesControllerDidRequestClose:(PreferencesWindowController *)controller {
    (void)controller;
}

- (void)showStatusMessage:(NSString *)message duration:(NSTimeInterval)duration {
    if (!self.statusTextField) {
        return;
    }
    [self.statusClearTimer invalidate];
    self.statusClearTimer = nil;

    NSString *text = message.length > 0 ? message : @"";
    [self.statusTextField setStringValue:text];

    if (duration > 0.0) {
        self.statusClearTimer = [NSTimer scheduledTimerWithTimeInterval:duration
                                                                 target:self
                                                               selector:@selector(clearStatusMessage)
                                                               userInfo:nil
                                                                repeats:NO];
    }
}

- (void)clearStatusMessage {
    [self.statusClearTimer invalidate];
    self.statusClearTimer = nil;
    if (self.statusTextField) {
        [self.statusTextField setStringValue:@""];
    }
}

- (void)layoutContentSubviews {
    if (!self.window || !self.scrollView || !self.statusBarView) {
        return;
    }
    NSView *contentView = self.window.contentView;
    NSRect bounds = contentView.bounds;
    CGFloat barHeight = [self statusBarHeight];
    NSRect statusFrame = NSMakeRect(0.0f, 0.0f, bounds.size.width, barHeight);
    [self.statusBarView setFrame:statusFrame];
    if (self.statusBarVisiblePreference) {
        [self layoutStatusControls];
    }

    CGFloat scrollHeight = MAX(0.0f, bounds.size.height - barHeight);
    NSRect scrollFrame = NSMakeRect(0.0f, barHeight, bounds.size.width, scrollHeight);
    [self.scrollView setFrame:scrollFrame];
    [self.scrollView.contentView setNeedsDisplay:YES];
}

- (void)resizeWindowToImageSize:(NSSize)imageSize {
    if (imageSize.width <= 0.0f || imageSize.height <= 0.0f || !self.window) {
        return;
    }

    NSScreen *screen = self.window.screen ?: [NSScreen mainScreen];
    NSRect visibleFrame = screen ? screen.visibleFrame : NSMakeRect(0.0f, 0.0f, 1600.0f, 1000.0f);
    CGFloat maxWidth = visibleFrame.size.width * 0.95f;
    CGFloat maxHeight = visibleFrame.size.height * 0.95f;
    CGFloat maxContentHeight = MAX(100.0f, maxHeight - StatusBarHeight);

    CGFloat scale = 1.0f;
    if (imageSize.width > maxWidth || imageSize.height > maxContentHeight) {
        CGFloat widthScale = maxWidth / imageSize.width;
        CGFloat heightScale = maxContentHeight / imageSize.height;
        scale = MIN(widthScale, heightScale);
    }
    scale = MIN(scale, 1.0f);

    CGFloat contentWidth = floor(imageSize.width * scale);
    CGFloat contentHeight = floor(imageSize.height * scale);
    if (contentWidth < 1.0f || contentHeight < 1.0f) {
        contentWidth = MAX(1.0f, contentWidth);
        contentHeight = MAX(1.0f, contentHeight);
    }

    CGFloat targetWidth = contentWidth;
    CGFloat targetHeight = contentHeight + StatusBarHeight;

    [self.window setContentSize:NSMakeSize(targetWidth, targetHeight)];
    [self layoutContentSubviews];
    if (self.canvasView.isFitToWindow) {
        [self.canvasView updateForEnclosingBoundsChange];
    }
    [self.window center];
}

#pragma mark - Actions

- (void)openDocument:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:NO];
    [panel setAllowedFileTypes:@[@"png", @"PNG"]];

    if (self.currentImageURL) {
        [panel setDirectoryURL:self.currentImageURL.URLByDeletingLastPathComponent];
    } else if (self.defaultSaveDirectory.length > 0) {
        NSURL *dirURL = [NSURL fileURLWithPath:self.defaultSaveDirectory];
        if (dirURL) {
            [panel setDirectoryURL:dirURL];
        }
    }

    if ([panel runModal] == NSModalResponseOK) {
        [self openImageAtURL:panel.URL];
    }
}

- (void)showPreferences:(id)sender {
    (void)sender;
    if (!self.preferencesWindowController) {
        self.preferencesWindowController = [[PreferencesWindowController alloc] initWithDelegate:self];
    }
    [self.preferencesWindowController showRelativeToWindow:self.window];
}

- (void)saveDocumentAs:(id)sender {
    if (![self.canvasView hasImage]) {
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes:@[@"png"]];
    [panel setCanCreateDirectories:YES];

    if (self.currentImageURL) {
        [panel setDirectoryURL:self.currentImageURL.URLByDeletingLastPathComponent];
        [panel setNameFieldStringValue:self.currentImageURL.lastPathComponent];
    } else if (self.defaultSaveDirectory.length > 0) {
        NSURL *dirURL = [NSURL fileURLWithPath:self.defaultSaveDirectory];
        if (dirURL) {
            [panel setDirectoryURL:dirURL];
        }
    }

    if ([panel runModal] != NSModalResponseOK) {
        return;
    }

    NSURL *destination = panel.URL;
    NSImage *flattened = [self.canvasView flattenedImage];
    if (!flattened) {
        return;
    }

    NSData *pngData = [self pngDataForImage:flattened];
    if (!pngData) {
        return;
    }

    [self ensureDirectoryExistsAtPath:[destination.path stringByDeletingLastPathComponent]];

    NSError *error = nil;
    if (![pngData writeToURL:destination options:NSDataWritingAtomic error:&error]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Unable to Save Image";
        alert.informativeText = error.localizedDescription ?: @"An unknown error occurred.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    self.currentImageURL = destination;
    [self.window setTitleWithRepresentedFilename:destination.path];
}

- (void)copy:(id)sender {
    if (![self.canvasView hasImage]) {
        [self showStatusMessage:@"No image to copy" duration:2.0];
        return;
    }

    NSImage *flattened = [self.canvasView flattenedImageForSelection];
    if (!flattened) {
        [self showStatusMessage:@"Copy failed" duration:2.0];
        return;
    }

    NSData *pngData = [self pngDataForImage:flattened];
    NSData *tiffData = [flattened TIFFRepresentation];

    NSMutableArray *types = [NSMutableArray array];
    if (pngData) {
        [types addObject:NSPasteboardTypePNG];
    }
    if (tiffData) {
        [types addObject:NSPasteboardTypeTIFF];
    }
    if (types.count == 0) {
        [self showStatusMessage:@"Copy failed" duration:2.0];
        return;
    }

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:types owner:nil];
    if (pngData) {
        [pasteboard setData:pngData forType:NSPasteboardTypePNG];
    }
    if (tiffData) {
        [pasteboard setData:tiffData forType:NSPasteboardTypeTIFF];
    }

    NSString *status = [self.canvasView hasSelection] ? @"Copied selection to clipboard" : @"Copied image to clipboard";
    [self showStatusMessage:status duration:3.0];
}

- (void)cropImage:(id)sender {
    if (![self.canvasView hasSelection]) {
        NSBeep();
        [self showStatusMessage:@"No active selection" duration:2.0];
        return;
    }

    if (![self.canvasView cropToActiveSelection]) {
        [self showStatusMessage:@"Crop failed" duration:2.0];
        return;
    }

    if ([self.canvasView hasImage]) {
        [self resizeWindowToImageSize:self.canvasView.image.size];
    }
    [self showStatusMessage:@"Cropped image" duration:2.0];
}


- (void)zoomPopUpAction:(id)sender {
    ScreenshotToolAppendLog(@"ScreenshotTool: zoom pop-up action invoked");
    [self zoomSelectionChanged:self.zoomPopUpButton];
}

- (void)zoomSelectionChanged:(id)sender {
    NSInteger index = [self.zoomPopUpButton indexOfSelectedItem];
    switch (index) {
        case 0:
            self.canvasView.fitToWindow = YES;
            [self.canvasView updateForEnclosingBoundsChange];
            [self reflectZoomSelection];
            return;
        case 1:
            [self setZoomScale:0.25];
            return;
        case 2:
            [self setZoomScale:0.5];
            return;
        case 3:
            [self setZoomScale:1.0];
            return;
        case 4:
            [self setZoomScale:2.0];
            return;
        default:
            break;
    }

    NSString *title = self.zoomPopUpButton.titleOfSelectedItem;
    if (![self applyZoomTitle:title]) {
        NSBeep();
        [self reflectZoomSelection];
    }
}

- (void)zoomIn:(id)sender {
    if (![self.canvasView hasImage]) {
        return;
    }
    if (self.canvasView.isFitToWindow) {
        [self setZoomScale:1.0];
        return;
    }

    CGFloat current = self.canvasView.zoomScale;
    CGFloat next = [self nextZoomScaleAbove:current];
    [self setZoomScale:next];
}

- (void)zoomOut:(id)sender {
    if (![self.canvasView hasImage]) {
        return;
    }
    if (self.canvasView.isFitToWindow) {
        [self setZoomScale:0.5];
        return;
    }

    CGFloat current = self.canvasView.zoomScale;
    CGFloat next = [self nextZoomScaleBelow:current];
    [self setZoomScale:next];
}

- (BOOL)applyZoomTitle:(NSString *)title {
    if (title.length == 0) {
        return NO;
    }

    NSString *lower = [title lowercaseString];
    if ([lower isEqualToString:@"fit"] || [lower isEqualToString:@"fit to window"]) {
        self.canvasView.fitToWindow = YES;
        [self.canvasView updateForEnclosingBoundsChange];
        [self reflectZoomSelection];
        return YES;
    }

    NSString *sanitized = [lower stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([sanitized hasSuffix:@"%"] && sanitized.length > 1) {
        sanitized = [sanitized substringToIndex:(sanitized.length - 1)];
    }

    double percent = strtod([sanitized UTF8String], NULL);
    if (percent <= 0.0) {
        return NO;
    }

    [self setZoomScale:(percent / 100.0)];
    return YES;
}

- (CGFloat)nextZoomScaleAbove:(CGFloat)scale {
    NSArray<NSNumber *> *levels = [self orderedZoomLevels];
    for (NSNumber *number in levels) {
        CGFloat candidate = number.floatValue;
        if (candidate > scale + 0.0001f) {
            return candidate;
        }
    }
    CGFloat expanded = MIN(scale * 1.25f, 8.0f);
    return MAX(MIN(expanded, 8.0f), 0.05f);
}

- (CGFloat)nextZoomScaleBelow:(CGFloat)scale {
    NSArray<NSNumber *> *levels = [self orderedZoomLevels];
    CGFloat previous = 0.0f;
    for (NSNumber *number in levels) {
        CGFloat candidate = number.floatValue;
        if (candidate >= scale - 0.0001f) {
            break;
        }
        previous = candidate;
    }
    if (previous > 0.0f) {
        return previous;
    }
    CGFloat reduced = MAX(scale / 1.25f, 0.05f);
    return MAX(0.05f, MIN(reduced, scale - 0.05f));
}

- (NSString *)displayStringForScale:(CGFloat)scale {
    CGFloat percent = scale * 100.0f;
    CGFloat rounded = roundf(percent);
    if (fabs(percent - rounded) < 0.01f) {
        return [NSString stringWithFormat:@"%.0f%%", rounded];
    }
    return [NSString stringWithFormat:@"%.1f%%", percent];
}

- (NSArray<NSNumber *> *)orderedZoomLevels {
    static NSArray<NSNumber *> *levels = nil;
    if (!levels) {
        levels = @[@0.25f, @0.5f, @1.0f, @1.5f, @2.0f, @3.0f, @4.0f, @6.0f, @8.0f];
    }
    return levels;
}

- (void)activateHighlighter:(id)sender {
    NSEvent *event = [NSApp currentEvent];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ toolbar action fired (sender=%@, event=%@)",
                             STDebugToolName(ScreenshotCanvasToolHighlighter),
                             STDebugDescriptionForSender(sender),
                             STDebugDescriptionForEvent(event)]);
    BOOL openPopover = [self isDoubleClickEvent:event];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ toolbar action doubleClick=%@ (clickCount=%ld)",
                             STDebugToolName(ScreenshotCanvasToolHighlighter),
                             openPopover ? @"YES" : @"NO",
                             (long)(event ? event.clickCount : 0)]);
    [self selectTool:ScreenshotCanvasToolHighlighter];
    if (openPopover) {
        ScreenshotToolAppendLog(@"Opening Highlighter popover after double-click toolbar activation");
        [self showToolSettingsPopoverForTool:ScreenshotCanvasToolHighlighter event:event];
    } else {
        ScreenshotToolAppendLog(@"Highlighter popover not opened (no double-click detected)");
    }
}

- (void)activatePen:(id)sender {
    NSEvent *event = [NSApp currentEvent];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ toolbar action fired (sender=%@, event=%@)",
                             STDebugToolName(ScreenshotCanvasToolPen),
                             STDebugDescriptionForSender(sender),
                             STDebugDescriptionForEvent(event)]);
    BOOL openPopover = [self isDoubleClickEvent:event];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ toolbar action doubleClick=%@ (clickCount=%ld)",
                             STDebugToolName(ScreenshotCanvasToolPen),
                             openPopover ? @"YES" : @"NO",
                             (long)(event ? event.clickCount : 0)]);
    [self selectTool:ScreenshotCanvasToolPen];
    if (openPopover) {
        ScreenshotToolAppendLog(@"Opening Pen popover after double-click toolbar activation");
        [self showToolSettingsPopoverForTool:ScreenshotCanvasToolPen event:event];
    } else {
        ScreenshotToolAppendLog(@"Pen popover not opened (no double-click detected)");
    }
}

- (void)activateEraser:(id)sender {
    [self selectTool:ScreenshotCanvasToolEraser];
}

- (void)activateText:(id)sender {
    NSEvent *event = [NSApp currentEvent];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ toolbar action fired (sender=%@, event=%@)",
                             STDebugToolName(ScreenshotCanvasToolText),
                             STDebugDescriptionForSender(sender),
                             STDebugDescriptionForEvent(event)]);
    BOOL openPopover = [self isDoubleClickEvent:event];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ toolbar action doubleClick=%@ (clickCount=%ld)",
                             STDebugToolName(ScreenshotCanvasToolText),
                             openPopover ? @"YES" : @"NO",
                             (long)(event ? event.clickCount : 0)]);
    [self selectTool:ScreenshotCanvasToolText];
    if (openPopover) {
        ScreenshotToolAppendLog(@"Opening Text popover after double-click toolbar activation");
        [self showToolSettingsPopoverForTool:ScreenshotCanvasToolText event:event];
    } else {
        ScreenshotToolAppendLog(@"Text popover not opened (no double-click detected)");
    }
}

- (void)activateSelect:(id)sender {
    [self selectTool:ScreenshotCanvasToolSelect];
}

#pragma mark - Helpers

- (NSImage *)imageForToolbarIdentifier:(NSToolbarItemIdentifier)identifier active:(BOOL)active {
    NSString *filename = [self iconNameForToolbarIdentifier:identifier active:active];
    if (!filename) {
        return nil;
    }

    static NSMutableDictionary<NSString *, NSImage *> *toolbarCache = nil;
    if (!toolbarCache) {
        toolbarCache = [[NSMutableDictionary alloc] init];
    }

    NSImage *icon = toolbarCache[filename];
    if (!icon) {
        NSImage *base = [self imageNamed:filename];
        if (base) {
            icon = [base copy];
            [icon setSize:NSMakeSize(32.0, 32.0)];
            toolbarCache[filename] = icon;
            ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: loaded toolbar icon %@", filename]);
        } else {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: toolbar icon %@ missing base image", filename]);
        }
    }
    return icon;
}

- (NSImage *)imageNamed:(NSString *)filename {
    if (filename.length == 0) {
        return nil;
    }

    static NSMutableDictionary<NSString *, NSImage *> *cache = nil;
    if (!cache) {
        cache = [[NSMutableDictionary alloc] init];
    }

    NSImage *cached = cache[filename];
    if (cached) {
        return cached;
    }

    NSArray<NSString *> *extensions = @[@"png", @"tiff", @"tif", @"bmp"];
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *path = nil;
    for (NSString *ext in extensions) {
        path = [bundle pathForResource:filename ofType:ext];
        if (path) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: attempting to load image %@", path]);
            break;
        }
    }
    if (!path) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: missing resource %@", filename]);
        return nil;
    }

    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    if (image) {
        cache[filename] = image;
        ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: loaded image %@", path]);
    } else {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: failed to load image %@", path]);
    }
    return image;
}

- (NSImage *)imageByAddingColorBadgeToImage:(NSImage *)image color:(NSColor *)color {
    if (!image || !color) {
        return image;
    }
    NSColor *deviceColor = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color;
    NSImage *composed = [image copy];
    NSSize size = composed.size;
    if (size.width <= 0.0f || size.height <= 0.0f) {
        size = NSMakeSize(ToolbarIconDimension, ToolbarIconDimension);
        [composed setSize:size];
    }
    [composed lockFocus];
    CGFloat badgeSize = 10.0f;
    NSRect badgeRect = NSMakeRect(size.width - badgeSize - 2.0f,
                                  2.0f,
                                  badgeSize,
                                  badgeSize);
    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:badgeRect];
    [deviceColor setFill];
    [path fill];
    [[NSColor colorWithCalibratedWhite:0.0f alpha:0.25f] setStroke];
    [path setLineWidth:1.0f];
    [path stroke];
    [composed unlockFocus];
    return composed;
}

- (void)selectTool:(ScreenshotCanvasTool)tool {
    [self closeActivePopovers];
    self.canvasView.activeTool = tool;

    NSString *selectedIdentifier = nil;
    switch (tool) {
        case ScreenshotCanvasToolHighlighter:
            selectedIdentifier = ToolbarItemHighlighter;
            break;
        case ScreenshotCanvasToolPen:
            selectedIdentifier = ToolbarItemPen;
            break;
        case ScreenshotCanvasToolEraser:
            selectedIdentifier = ToolbarItemEraser;
            break;
        case ScreenshotCanvasToolText:
            selectedIdentifier = ToolbarItemText;
            break;
        case ScreenshotCanvasToolSelect:
            selectedIdentifier = ToolbarItemSelect;
            break;
    }

    if (tool == ScreenshotCanvasToolPen || tool == ScreenshotCanvasToolHighlighter) {
        self.lastWidthTool = tool;
    }
    [self updateToolWidthControls];

    if (self.toolbar) {
        [self.toolbar setSelectedItemIdentifier:selectedIdentifier];
        [self refreshToolButtonIcons];
    }
}

- (void)setZoomScale:(CGFloat)scale {
    self.canvasView.fitToWindow = NO;
    self.canvasView.zoomScale = scale;
    [self.canvasView setNeedsDisplay:YES];
    [self reflectZoomSelection];
}

- (void)reflectZoomSelection {
    if (!self.zoomPopUpButton) {
        return;
    }

    if (self.canvasView.isFitToWindow) {
        [self.zoomPopUpButton selectItemAtIndex:0];
        return;
    }

    CGFloat scale = self.canvasView.zoomScale;
    NSString *value = [self displayStringForScale:scale];
    if (fabs(scale - 0.25) < 0.001) {
        [self.zoomPopUpButton selectItemAtIndex:1];
    } else if (fabs(scale - 0.5) < 0.001) {
        [self.zoomPopUpButton selectItemAtIndex:2];
    } else if (fabs(scale - 1.0) < 0.001) {
        [self.zoomPopUpButton selectItemAtIndex:3];
    } else if (fabs(scale - 2.0) < 0.001) {
        [self.zoomPopUpButton selectItemAtIndex:4];
    } else {
        NSInteger existingIndex = [self.zoomPopUpButton indexOfItemWithTitle:value];
        if (existingIndex == -1) {
            [self.zoomPopUpButton addItemWithTitle:value];
            existingIndex = [self.zoomPopUpButton indexOfItemWithTitle:value];
        }
        if (existingIndex >= 0) {
            [self.zoomPopUpButton selectItemAtIndex:existingIndex];
        }
    }
}

- (BOOL)openImageAtURL:(NSURL *)url {
    if (!url) {
        ScreenshotToolAppendLog(@"openImageAtURL invoked with nil URL");
        return NO;
    }

    NSImage *image = nil;
    @try {
        image = [[NSImage alloc] initWithContentsOfURL:url];
    } @catch (NSException *exception) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"openImageAtURL exception for %@ (%@ - %@)",
                                 url.path ?: url.absoluteString ?: @"<unknown>",
                                 exception.name ?: @"<no name>",
                                 exception.reason ?: @"<no reason>"]);
        image = nil;
    }
    if (!image) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"openImageAtURL failed to load image at %@",
                                 url.path ?: url.absoluteString ?: @"<unknown>"]);
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Unable to Open Image";
        alert.informativeText = url.path;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return NO;
    }

    NSSize size = image.size;
    ScreenshotToolAppendLog([NSString stringWithFormat:@"openImageAtURL loaded %@ (%.0fx%.0f)",
                             url.path ?: url.absoluteString ?: @"<unknown>",
                             size.width,
                             size.height]);
    self.currentImageURL = url;
    [self.canvasView loadImage:image];
    [self.window setTitleWithRepresentedFilename:url.path];
    [self resizeWindowToImageSize:image.size];
    [self.canvasView updateForEnclosingBoundsChange];
    [self reflectZoomSelection];
    return YES;
}

- (NSData *)pngDataForImage:(NSImage *)image {
    NSArray<NSImageRep *> *representations = [image representations];
    NSBitmapImageRep *bitmapRep = nil;
    for (NSImageRep *rep in representations) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            bitmapRep = (NSBitmapImageRep *)rep;
            break;
        }
    }

    if (!bitmapRep) {
        return nil;
    }

    return [bitmapRep representationUsingType:NSPNGFileType properties:@{}];
}

#pragma mark - NSWindowDelegate

- (void)windowDidResize:(NSNotification *)notification {
    [self layoutContentSubviews];
    [self.canvasView updateForEnclosingBoundsChange];
}

@end
