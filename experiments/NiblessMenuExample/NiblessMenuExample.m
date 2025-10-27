#import <AppKit/AppKit.h>

@interface NMAppDelegate : NSObject <NSApplicationDelegate>
@end

@interface NMAppDelegate ()
@property (nonatomic, copy) NSString *applicationName;
@end

@implementation NMAppDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *bundleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
        if (bundleName.length > 0) {
            _applicationName = [bundleName copy];
        } else {
            _applicationName = @"NiblessMenu";
        }
    }
    return self;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    [self populateMainMenu];
}

- (void)populateMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    NSMenuItem *appItem = [mainMenu addItemWithTitle:@"Application" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Application"];
    [self populateApplicationMenu:appMenu];
    [mainMenu setSubmenu:appMenu forItem:appItem];

    NSMenuItem *fileItem = [mainMenu addItemWithTitle:@"File" action:NULL keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"File", @"File menu")];
    [self populateFileMenu:fileMenu];
    [mainMenu setSubmenu:fileMenu forItem:fileItem];

    NSMenuItem *editItem = [mainMenu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Edit", @"Edit menu")];
    [self populateEditMenu:editMenu];
    [mainMenu setSubmenu:editMenu forItem:editItem];

    NSMenuItem *viewItem = [mainMenu addItemWithTitle:@"View" action:NULL keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"View", @"View menu")];
    [self populateViewMenu:viewMenu];
    [mainMenu setSubmenu:viewMenu forItem:viewItem];

    NSMenuItem *windowItem = [mainMenu addItemWithTitle:@"Window" action:NULL keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Window", @"Window menu")];
    [self populateWindowMenu:windowMenu];
    [mainMenu setSubmenu:windowMenu forItem:windowItem];
    [NSApp setWindowsMenu:windowMenu];

    NSMenuItem *helpItem = [mainMenu addItemWithTitle:@"Help" action:NULL keyEquivalent:@""];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Help", @"Help menu")];
    [self populateHelpMenu:helpMenu];
    [mainMenu setSubmenu:helpMenu forItem:helpItem];
    [NSApp setHelpMenu:helpMenu];

    [NSApp setMainMenu:mainMenu];
}

- (void)populateApplicationMenu:(NSMenu *)menu {
    NSString *title = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"About", @"About menu item"), self.applicationName];
    NSMenuItem *item = [menu addItemWithTitle:title action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [item setTarget:NSApp];

    [menu addItem:[NSMenuItem separatorItem]];

    title = NSLocalizedString(@"Services", @"Services menu item");
    item = [menu addItemWithTitle:title action:NULL keyEquivalent:@""];
    NSMenu *services = [[NSMenu alloc] initWithTitle:@"Services"];
    [menu setSubmenu:services forItem:item];
    [NSApp setServicesMenu:services];

    [menu addItem:[NSMenuItem separatorItem]];

    title = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"Hide", @"Hide menu item"), self.applicationName];
    item = [menu addItemWithTitle:title action:@selector(hide:) keyEquivalent:@"h"];
    [item setTarget:NSApp];

    title = NSLocalizedString(@"Hide Others", @"Hide Others menu item");
    item = [menu addItemWithTitle:title action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    [item setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagOption)];
    [item setTarget:NSApp];

    title = NSLocalizedString(@"Show All", @"Show All menu item");
    item = [menu addItemWithTitle:title action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [item setTarget:NSApp];

    [menu addItem:[NSMenuItem separatorItem]];

    title = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"Quit", @"Quit menu item"), self.applicationName];
    item = [menu addItemWithTitle:title action:@selector(terminate:) keyEquivalent:@"q"];
    [item setTarget:NSApp];
}

- (void)populateFileMenu:(NSMenu *)menu {
    NSString *title = NSLocalizedString(@"Close Window", @"Close Window menu item");
    [menu addItemWithTitle:title action:@selector(performClose:) keyEquivalent:@"w"];
}

- (void)populateEditMenu:(NSMenu *)menu {
    NSString *title = NSLocalizedString(@"Undo", @"Undo menu item");
    [menu addItemWithTitle:title action:@selector(undo:) keyEquivalent:@"z"];

    title = NSLocalizedString(@"Redo", @"Redo menu item");
    [menu addItemWithTitle:title action:@selector(redo:) keyEquivalent:@"Z"];

    [menu addItem:[NSMenuItem separatorItem]];

    title = NSLocalizedString(@"Cut", @"Cut menu item");
    [menu addItemWithTitle:title action:@selector(cut:) keyEquivalent:@"x"];

    title = NSLocalizedString(@"Copy", @"Copy menu item");
    [menu addItemWithTitle:title action:@selector(copy:) keyEquivalent:@"c"];

    title = NSLocalizedString(@"Paste", @"Paste menu item");
    [menu addItemWithTitle:title action:@selector(paste:) keyEquivalent:@"v"];

    title = NSLocalizedString(@"Delete", @"Delete menu item");
    [menu addItemWithTitle:title action:@selector(delete:) keyEquivalent:@"\177"]; // delete key

    title = NSLocalizedString(@"Select All", @"Select All menu item");
    [menu addItemWithTitle:title action:@selector(selectAll:) keyEquivalent:@"a"];
}

- (void)populateViewMenu:(NSMenu *)menu {
    NSString *title = NSLocalizedString(@"Show Toolbar", @"Show Toolbar menu item");
    NSMenuItem *item = [menu addItemWithTitle:title action:@selector(toggleToolbarShown:) keyEquivalent:@"t"];
    [item setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagOption)];

    title = NSLocalizedString(@"Enter Full Screen", @"Enter Full Screen menu item");
    item = [menu addItemWithTitle:title action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
    [item setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagControl)];
}

- (void)populateWindowMenu:(NSMenu *)menu {
    NSString *title = NSLocalizedString(@"Minimize", @"Minimize menu item");
    [menu addItemWithTitle:title action:@selector(performMiniaturize:) keyEquivalent:@"m"];

    title = NSLocalizedString(@"Zoom", @"Zoom menu item");
    [menu addItemWithTitle:title action:@selector(performZoom:) keyEquivalent:@""];

    [menu addItem:[NSMenuItem separatorItem]];

    title = NSLocalizedString(@"Bring All to Front", @"Bring All to Front menu item");
    NSMenuItem *item = [menu addItemWithTitle:title action:@selector(arrangeInFront:) keyEquivalent:@""];
    [item setTarget:NSApp];
}

- (void)populateHelpMenu:(NSMenu *)menu {
    NSString *title = [self.applicationName stringByAppendingFormat:@" %@", NSLocalizedString(@"Help", @"Help menu item")];
    NSMenuItem *item = [menu addItemWithTitle:title action:@selector(showHelp:) keyEquivalent:@""];
    [item setTarget:NSApp];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        NMAppDelegate *delegate = [[NMAppDelegate alloc] init];
        [app setDelegate:delegate];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        return NSApplicationMain(argc, argv);
    }
}
