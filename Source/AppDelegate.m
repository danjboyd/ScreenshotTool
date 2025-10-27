#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
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

static void ScreenshotToolAppendLog(NSString *message) {
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



static NSString * const ToolbarIdentifier = @"com.screenshottool.toolbar";
static NSString * const ToolbarItemHighlighter = @"com.screenshottool.toolbar.highlighter";
static NSString * const ToolbarItemHighlighterColor = @"com.screenshottool.toolbar.highlighterColor";
static NSString * const ToolbarItemPen = @"com.screenshottool.toolbar.pen";
static NSString * const ToolbarItemPenColor = @"com.screenshottool.toolbar.penColor";
static NSString * const ToolbarItemEraser = @"com.screenshottool.toolbar.eraser";
static NSString * const ToolbarItemText = @"com.screenshottool.toolbar.text";
static NSString * const ToolbarItemSelect = @"com.screenshottool.toolbar.select";
static NSString * const ToolbarItemZoom = @"com.screenshottool.toolbar.zoom";
static NSString * const ToolbarItemCopy = @"com.screenshottool.toolbar.copy";
static const CGFloat StatusBarHeight = 24.0f;
static const CGFloat ToolbarIconDimension = 32.0f;

@interface AppDelegate () <NSToolbarDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) ScreenshotCanvasView *canvasView;
@property (nonatomic, strong) NSToolbar *toolbar;
@property (nonatomic, strong) NSPopUpButton *zoomPopUpButton;
@property (nonatomic, strong) NSColorWell *penColorWell;
@property (nonatomic, strong) NSColorWell *highlighterColorWell;
@property (nonatomic, strong) NSView *statusBarView;
@property (nonatomic, strong) NSTextField *statusTextField;
@property (nonatomic, strong) NSTimer *statusClearTimer;
@property (nonatomic, copy) NSString *pendingOpenPath;
@property (nonatomic, strong) NSURL *currentImageURL;
@end

@implementation AppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    ScreenshotToolAppendLog(@"ScreenshotTool will finish launching");
    [self setupMenus];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    ScreenshotToolAppendLog(@"ScreenshotTool launched");
    [self setupWindowAndContent];
    [self setupToolbar];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    [self selectTool:ScreenshotCanvasToolHighlighter];
    [self reflectZoomSelection];

    if (self.pendingOpenPath.length > 0) {
        [self openImageAtURL:[NSURL fileURLWithPath:self.pendingOpenPath]];
        self.pendingOpenPath = nil;
    } else {
        NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
        if (arguments.count > 1) {
            for (NSUInteger idx = 1; idx < arguments.count; idx++) {
                NSString *candidate = arguments[idx];
                if ([self openImageAtURL:[NSURL fileURLWithPath:candidate]]) {
                    break;
                }
            }
        }
    }

}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    if (!self.canvasView) {
        self.pendingOpenPath = filename;
        return YES;
    }
    return [self openImageAtURL:[NSURL fileURLWithPath:filename]];
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
                                                 keyEquivalent:@"S"];
    [saveAsItem setTarget:self];
    [saveAsItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagShift)];
    [fileMenu addItem:saveAsItem];

    NSMenuItem *cropItem = [[NSMenuItem alloc] initWithTitle:@"Crop Image"
                                                      action:@selector(cropImage:)
                                               keyEquivalent:@"k"];
    [cropItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand)];
    [cropItem setTarget:self];
    [fileMenu addItem:cropItem];

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
    return nil;
}


#pragma mark - NSToolbarDelegate


#pragma mark - NSToolbarDelegate

- (void)refreshToolButtonIcons {
    if (!self.toolbar) {
        return;
    }
    NSToolbarItemIdentifier activeIdentifier = [self identifierForTool:self.canvasView.activeTool];
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
            continue;
        }
        BOOL isActive = (activeIdentifier && [identifier isEqualToString:activeIdentifier]);
        NSString *iconName = [self iconNameForToolbarIdentifier:identifier active:isActive];
        if (!iconName && isActive) {
            iconName = [self iconNameForToolbarIdentifier:identifier active:NO];
        }
        if (!iconName) {
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
            [icon setSize:NSMakeSize(ToolbarIconDimension, ToolbarIconDimension)];
            item.image = icon;
            NSString *state = isActive ? @"active" : @"inactive";
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ set to %@ icon %@", identifier, state, resolvedName]);
        } else {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ missing icon %@", identifier, resolvedName]);
        }
    }
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[ToolbarItemSelect,
             ToolbarItemHighlighter,
             ToolbarItemHighlighterColor,
             ToolbarItemPen,
             ToolbarItemPenColor,
             ToolbarItemText,
             ToolbarItemEraser,
             ToolbarItemCopy,
             ToolbarItemZoom,
             NSToolbarSpaceItemIdentifier,
             NSToolbarFlexibleSpaceItemIdentifier];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[ToolbarItemSelect,
             ToolbarItemHighlighter,
             ToolbarItemHighlighterColor,
             ToolbarItemPen,
             ToolbarItemPenColor,
             ToolbarItemText,
             ToolbarItemEraser,
             ToolbarItemCopy,
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
    if ([itemIdentifier isEqualToString:ToolbarItemHighlighterColor]) {
        return [self toolbarItemForColorWellWithIdentifier:ToolbarItemHighlighterColor
                                                     title:@"Highlight Color"
                                                  colorWell:&_highlighterColorWell
                                                     action:@selector(highlighterColorChanged:)];
    }
    if ([itemIdentifier isEqualToString:ToolbarItemPenColor]) {
        return [self toolbarItemForColorWellWithIdentifier:ToolbarItemPenColor
                                                     title:@"Pen Color"
                                                  colorWell:&_penColorWell
                                                     action:@selector(penColorChanged:)];
    }
    if ([itemIdentifier isEqualToString:ToolbarItemCopy]) {
        return [self standardToolbarItemWithIdentifier:ToolbarItemCopy
                                                 label:@"Copy"
                                                action:@selector(copy:)];
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
    item.label = label;
    item.paletteLabel = label;
    item.toolTip = label;
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
            [icon setSize:NSMakeSize(ToolbarIconDimension, ToolbarIconDimension)];
            item.image = icon;
        }
    }
    return item;
}
- (NSToolbarItem *)toolbarItemForColorWellWithIdentifier:(NSToolbarItemIdentifier)identifier
                                                   title:(NSString *)title
                                                colorWell:(NSColorWell * __strong *)colorWell
                                                   action:(SEL)selector {
    if (*colorWell == nil) {
        NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 40, 24)];
        well.target = self;
        well.action = selector;
        if (selector == @selector(penColorChanged:)) {
            [well setColor:self.canvasView.penColor];
        } else {
            [well setColor:self.canvasView.highlighterColor];
        }
        [well setBordered:YES];
        *colorWell = well;
    }

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = title;
    item.paletteLabel = title;
    item.toolTip = title;
    item.target = self;
    item.action = selector;

    NSImage *icon = [self imageForColorToolbarItem:identifier];
    if (icon) {
        item.image = icon;
    }

    NSColorWell *well = *colorWell;
    if (well.superview) {
        [well removeFromSuperview];
    }
    item.view = well;
    item.minSize = well.frame.size;
    item.maxSize = well.frame.size;
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
    NSRect statusFrame = NSMakeRect(0.0f, 0.0f, bounds.size.width, StatusBarHeight);
    [self.statusBarView setFrame:statusFrame];
    if (self.statusTextField) {
        [self.statusTextField setFrame:NSInsetRect(statusFrame, 8.0f, 4.0f)];
    }

    CGFloat scrollHeight = MAX(0.0f, bounds.size.height - StatusBarHeight);
    NSRect scrollFrame = NSMakeRect(0.0f, StatusBarHeight, bounds.size.width, scrollHeight);
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
    }

    if ([panel runModal] == NSModalResponseOK) {
        [self openImageAtURL:panel.URL];
    }
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
    [self selectTool:ScreenshotCanvasToolHighlighter];
}

- (void)activatePen:(id)sender {
    [self selectTool:ScreenshotCanvasToolPen];
}

- (void)activateEraser:(id)sender {
    [self selectTool:ScreenshotCanvasToolEraser];
}

- (void)activateText:(id)sender {
    [self selectTool:ScreenshotCanvasToolText];
}

- (void)activateSelect:(id)sender {
    [self selectTool:ScreenshotCanvasToolSelect];
}

- (void)highlighterColorChanged:(NSColorWell *)sender {
    self.canvasView.highlighterColor = sender.color ?: [NSColor yellowColor];
    [self.canvasView setNeedsDisplay:YES];
}

- (void)penColorChanged:(NSColorWell *)sender {
    self.canvasView.penColor = sender.color ?: [NSColor redColor];
    self.canvasView.textColor = sender.color ?: [NSColor redColor];
    [self.canvasView setNeedsDisplay:YES];
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

- (NSImage *)imageForColorToolbarItem:(NSToolbarItemIdentifier)identifier {
    if (!identifier) {
        return nil;
    }

    NSString *filename = nil;
    if ([identifier isEqualToString:ToolbarItemHighlighterColor]) {
        filename = @"HighligherChangeColor";
    } else if ([identifier isEqualToString:ToolbarItemPenColor]) {
        filename = @"PenChangeColor";
    } else {
        filename = nil;
    }

    if (!filename) {
        return nil;
    }

    static NSMutableDictionary<NSString *, NSImage *> *colorCache = nil;
    if (!colorCache) {
        colorCache = [[NSMutableDictionary alloc] init];
    }

    NSImage *icon = colorCache[filename];
    if (!icon) {
        NSImage *base = [self imageNamed:filename];
        if (base) {
            icon = [base copy];
            [icon setSize:NSMakeSize(32.0, 32.0)];
            colorCache[filename] = icon;
            ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: loaded color icon %@", filename]);
        } else {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: color icon %@ missing base image", filename]);
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

- (void)selectTool:(ScreenshotCanvasTool)tool {
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
        return NO;
    }

    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    if (!image) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Unable to Open Image";
        alert.informativeText = url.path;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return NO;
    }

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
