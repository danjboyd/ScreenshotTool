/*
 * CustomActionsProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Custom actions: the user's commands that get the annotated image (#221).
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotCanvasView.h"
#import "STCustomActions.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (CustomActionsTesting)
- (void)setupWindowAndContent;
- (ScreenshotCanvasView *)canvasView;
- (NSWindow *)window;
- (void)setupToolbar;
- (NSArray<STCustomAction *> *)loadedCustomActions;
- (BOOL)isRunningCustomAction:(STCustomAction *)action;
- (void)runCustomAction:(STCustomAction *)action choice:(NSString *)choice;
- (NSArray<NSString *> *)choicesForCustomAction:(STCustomAction *)action;
- (NSMenuItem *)menuItemForCustomAction:(STCustomAction *)action;
- (NSArray<NSString *> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
- (NSToolbarItem *)toolbarItemForCustomAction:(STCustomAction *)action;
@end

@interface CustomActionsProbeTests : XCTestCase {
    NSString *_directory;
    NSString *_savedActionsDirectory;
}
@end

@implementation CustomActionsProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    const char *saved = getenv("SCREENSHOT_TOOL_ACTIONS_DIR");
    _savedActionsDirectory = saved ? [NSString stringWithUTF8String:saved] : nil;
    _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"custom-actions-%@", [[NSProcessInfo processInfo] globallyUniqueString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:_directory error:NULL];
    if (_savedActionsDirectory) {
        setenv("SCREENSHOT_TOOL_ACTIONS_DIR", [_savedActionsDirectory fileSystemRepresentation], 1);
    } else {
        unsetenv("SCREENSHOT_TOOL_ACTIONS_DIR");
    }
    [super tearDown];
}

- (NSString *)writeAction:(NSString *)name json:(NSString *)json {
    NSString *path = [_directory stringByAppendingPathComponent:name];
    [json writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return path;
}

/// Runs the main run loop until `done` says so, for at most `seconds`.
- (BOOL)spinUntil:(BOOL (^)(void))done seconds:(NSTimeInterval)seconds {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return done();
}

#pragma mark - Action files

- (void)testActionFileIsRead {
    [self writeAction:@"send.json" json:@"{\"title\": \"Send It\", \"command\": [\"/bin/echo\", \"{file}\"], "
                                         "\"choices\": [\"/bin/echo\", \"a\"], \"output\": \"none\", \"toolbar\": true, \"timeout\": 9}"];
    NSMutableArray<NSString *> *problems = [[NSMutableArray alloc] init];
    NSArray<STCustomAction *> *actions = [STCustomAction actionsInDirectory:_directory problems:problems];
    XCTAssertEqual(actions.count, (NSUInteger)1, @"%@", problems);
    STCustomAction *action = actions.firstObject;
    XCTAssertEqualObjects(action.identifier, @"send", @"The identifier is the file's name");
    XCTAssertEqualObjects(action.title, @"Send It");
    XCTAssertEqualObjects(action.command, (@[@"/bin/echo", @"{file}"]));
    XCTAssertEqualObjects(action.choicesCommand, (@[@"/bin/echo", @"a"]));
    XCTAssertEqual(action.output, STCustomActionOutputNone);
    XCTAssertTrue(action.showsInToolbar);
    XCTAssertEqualWithAccuracy(action.timeout, 9.0, 0.001);
}

- (void)testDefaultsAndOrder {
    [self writeAction:@"b.json" json:@"{\"title\": \"zeta\", \"command\": [\"x\"]}"];
    [self writeAction:@"a.json" json:@"{\"title\": \"Alpha\", \"command\": [\"x\"]}"];
    NSArray<STCustomAction *> *actions = [STCustomAction actionsInDirectory:_directory problems:nil];
    XCTAssertEqualObjects([actions valueForKey:@"title"], (@[@"Alpha", @"zeta"]), @"By title, ignoring case");
    XCTAssertEqual(actions.firstObject.output, STCustomActionOutputClipboard, @"Output goes to the clipboard by default");
    XCTAssertFalse(actions.firstObject.showsInToolbar, @"...and actions are menu-only by default");
    XCTAssertEqualWithAccuracy(actions.firstObject.timeout, 120.0, 0.001);
}

- (void)testFilesThatArentActionsAreSkippedWithAReason {
    [self writeAction:@"broken.json" json:@"{ not json"];
    [self writeAction:@"untitled.json" json:@"{\"command\": [\"x\"]}"];
    [self writeAction:@"nocommand.json" json:@"{\"title\": \"T\", \"command\": []}"];
    [self writeAction:@"badoutput.json" json:@"{\"title\": \"T\", \"command\": [\"x\"], \"output\": \"file\"}"];
    [self writeAction:@"notes.txt" json:@"ignored"];
    NSMutableArray<NSString *> *problems = [[NSMutableArray alloc] init];
    NSArray<STCustomAction *> *actions = [STCustomAction actionsInDirectory:_directory problems:problems];
    XCTAssertEqual(actions.count, (NSUInteger)0);
    XCTAssertEqual(problems.count, (NSUInteger)4, @"Each JSON file says why: %@", problems);
    XCTAssertTrue([[problems componentsJoinedByString:@"\n"] rangeOfString:@"untitled.json: needs a \"title\""].location != NSNotFound, @"%@", problems);
}

- (void)testPlaceholders {
    [self writeAction:@"a.json" json:@"{\"title\": \"T\", \"command\": [\"~/bin/up\", \"--file={file}\", \"{choice}\"], \"choices\": [\"x\"]}"];
    STCustomAction *action = [STCustomAction actionsInDirectory:_directory problems:nil].firstObject;
    NSArray<NSString *> *arguments = [action argumentsForFile:@"/tmp/a b.png" choice:@"work" problem:NULL];
    XCTAssertEqualObjects(arguments, (@[[@"~/bin/up" stringByExpandingTildeInPath], @"--file=/tmp/a b.png", @"work"]),
                          @"{file} and {choice} are filled in, one argument each, and ~ expanded");
    NSString *problem = nil;
    XCTAssertNil([action argumentsForFile:@"/tmp/a.png" choice:nil problem:&problem], @"{choice} needs a choice");
    XCTAssertTrue(problem.length > 0);
}

- (void)testDirectoryCanBeOverridden {
    setenv("SCREENSHOT_TOOL_ACTIONS_DIR", [_directory fileSystemRepresentation], 1);
    XCTAssertEqualObjects([STCustomAction actionsDirectory], _directory);
}

#pragma mark - Running

- (void)testChildEnvironmentDropsWhatAnAppImageAdds {
    NSDictionary *environment = @{ @"APPDIR": @"/tmp/.mount_ScreenXYZ", @"APPIMAGE": @"/home/u/ScreenshotTool.AppImage",
                                   @"LD_LIBRARY_PATH": @"/tmp/.mount_ScreenXYZ/usr/runtime/lib",
                                   @"GNUSTEP_CONFIG_FILE": @"/tmp/.mount_ScreenXYZ/usr/runtime/etc/GNUstep/GNUstep.conf",
                                   @"FONTCONFIG_FILE": @"/tmp/.mount_ScreenXYZ/fonts.conf",
                                   @"PATH": @"/tmp/.mount_ScreenXYZ/usr/runtime/bin:/usr/local/bin:/usr/bin",
                                   @"HOME": @"/home/u", @"SSH_AUTH_SOCK": @"/run/user/1000/ssh" };
    NSDictionary *child = [STCustomActionRunner childEnvironmentFrom:environment];
    XCTAssertNil(child[@"LD_LIBRARY_PATH"]);
    XCTAssertNil(child[@"GNUSTEP_CONFIG_FILE"]);
    XCTAssertNil(child[@"FONTCONFIG_FILE"]);
    XCTAssertEqualObjects(child[@"PATH"], @"/usr/local/bin:/usr/bin", @"The AppImage's own folders leave PATH");
    XCTAssertEqualObjects(child[@"HOME"], @"/home/u");
    XCTAssertEqualObjects(child[@"SSH_AUTH_SOCK"], @"/run/user/1000/ssh", @"The user's SSH agent stays");

    NSDictionary *plain = @{ @"LD_LIBRARY_PATH": @"/opt/lib", @"PATH": @"/usr/bin" };
    XCTAssertEqualObjects([STCustomActionRunner childEnvironmentFrom:plain], plain, @"Outside an AppImage nothing changes");
}

/// Windows calls it "Path" (ScreenshotTool Windows's check of #234).
- (void)testSearchPathIsFoundUnderItsWindowsName {
    XCTAssertEqualObjects([STCustomActionRunner searchPathInEnvironment:@{ @"PATH": @"/usr/bin" }], @"/usr/bin");
#if defined(_WIN32)
    XCTAssertEqualObjects([STCustomActionRunner searchPathInEnvironment:@{ @"Path": @"C:\\Windows\\system32" }],
                          @"C:\\Windows\\system32");
    XCTAssertNotNil([STCustomActionRunner resolvedExecutable:@"cmd.exe"
                                                  searchPath:[STCustomActionRunner searchPathInEnvironment:[[NSProcessInfo processInfo] environment]]],
                    @"cmd.exe is found on this system's Path");
    XCTAssertNotNil([STCustomActionRunner resolvedExecutable:@"cmd"
                                                  searchPath:[STCustomActionRunner searchPathInEnvironment:[[NSProcessInfo processInfo] environment]]],
                    @"...and as cmd, by PATHEXT");
#else
    XCTAssertNil([STCustomActionRunner searchPathInEnvironment:@{ @"Path": @"/usr/bin" }], @"Elsewhere names are exact");
#endif
}

#if !defined(_WIN32)
- (void)testRunnerReportsOutputAndFailure {
    __block STCustomActionResult *result = nil;
    [STCustomActionRunner runArguments:@[@"sh", @"-c", @"printf '%s\\n' \"$1\"; echo 'first' >&2; echo 'last line' >&2; exit 3", @"sh", @"hello world"]
                               timeout:10.0
                            completion:^(STCustomActionResult *r) { result = r; }];
    XCTAssertTrue([self spinUntil:^BOOL { return result != nil; } seconds:10.0]);
    XCTAssertTrue(result.launched, @"sh is found on PATH");
    XCTAssertEqual(result.status, 3);
    XCTAssertFalse(result.succeeded);
    XCTAssertEqualObjects(result.standardOutput, @"hello world\n");
    XCTAssertEqualObjects(result.failureSummary, @"last line", @"The error output's last line says why");
}

- (void)testRunnerStopsACommandThatHangs {
    __block STCustomActionResult *result = nil;
    [STCustomActionRunner runArguments:@[@"/bin/sleep", @"30"] timeout:0.5
                            completion:^(STCustomActionResult *r) { result = r; }];
    XCTAssertTrue([self spinUntil:^BOOL { return result != nil; } seconds:10.0], @"It's stopped, not waited for");
    XCTAssertTrue(result.timedOut);
    XCTAssertFalse(result.succeeded);
}

- (void)testRunnerReportsAMissingProgram {
    __block STCustomActionResult *result = nil;
    [STCustomActionRunner runArguments:@[@"no-such-program-anywhere"] timeout:5.0
                            completion:^(STCustomActionResult *r) { result = r; }];
    XCTAssertTrue([self spinUntil:^BOOL { return result != nil; } seconds:5.0]);
    XCTAssertFalse(result.launched);
    XCTAssertTrue([result.failureSummary rangeOfString:@"no-such-program-anywhere"].location != NSNotFound, @"%@", result.failureSummary);
}

#pragma mark - In the app

- (AppDelegate *)appWithActions {
    setenv("SCREENSHOT_TOOL_ACTIONS_DIR", [_directory fileSystemRepresentation], 1);
    AppDelegate *app = nil;
    @try {
        [NSApplication sharedApplication];
        app = [[AppDelegate alloc] init];
        [app setupWindowAndContent];
    } @catch (NSException *exception) {
        return nil;
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(120.0, 80.0)];
    [image lockFocus];
    [[NSColor orangeColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 120.0, 80.0));
    [image unlockFocus];
    [app.canvasView loadImage:image];
    return app;
}

- (NSString *)pasteboardString {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
#if defined(GNUSTEP)
    return [pasteboard stringForType:NSStringPboardType];
#else
    return [pasteboard stringForType:NSPasteboardTypeString];
#endif
}

/// The action gets the annotated image as a PNG, and what it prints is copied.
- (void)testRunningAnActionCopiesWhatItPrints {
    [self writeAction:@"upload.json" json:@"{\"title\": \"Upload\", \"command\": [\"/bin/sh\", \"-c\", "
                                           "\"head -c 8 \\\"$1\\\" | od -An -c | grep -q 'P   N   G' && echo \\\"/remote/$(basename \\\"$1\\\")\\\"\", "
                                           "\"sh\", \"{file}\"]}"];
    AppDelegate *app = [self appWithActions];
    XCTSkipIf(app == nil, @"No window server");
    STCustomAction *action = [app loadedCustomActions].firstObject;
    XCTAssertNotNil(action);

    [app runCustomAction:action choice:nil];
    XCTAssertTrue([app isRunningCustomAction:action], @"It runs in the background");
    XCTAssertTrue([self spinUntil:^BOOL { return ![app isRunningCustomAction:action]; } seconds:15.0]);
    XCTAssertEqualObjects([self pasteboardString], @"/remote/Screenshot.png",
                          @"The command got a PNG file, and its output is on the clipboard");
}

/// "choices": the lines become a menu, and the button (no choice) takes the first.
- (void)testChoicesBecomeAMenuAndTheFirstIsTheDefault {
    [self writeAction:@"send.json" json:@"{\"title\": \"Send\", \"command\": [\"/bin/echo\", \"sent to {choice}\"], "
                                         "\"choices\": [\"/bin/sh\", \"-c\", \"printf 'home\\\\nwork\\\\n'\"], \"toolbar\": true}"];
    AppDelegate *app = [self appWithActions];
    XCTSkipIf(app == nil, @"No window server");
    STCustomAction *action = [app loadedCustomActions].firstObject;
    XCTAssertTrue([self spinUntil:^BOOL { return [app choicesForCustomAction:action] != nil; } seconds:10.0]);
    XCTAssertEqualObjects([app choicesForCustomAction:action], (@[@"home", @"work"]));

    NSMenuItem *item = [app menuItemForCustomAction:action];
    XCTAssertEqualObjects([item.submenu.itemArray valueForKey:@"title"], (@[@"home", @"work"]), @"A submenu of the choices");

    [app runCustomAction:action choice:nil];
    XCTAssertTrue([self spinUntil:^BOOL { return ![app isRunningCustomAction:action]; } seconds:10.0]);
    XCTAssertEqualObjects([self pasteboardString], @"sent to home");
    [app runCustomAction:action choice:@"work"];
    XCTAssertTrue([self spinUntil:^BOOL { return ![app isRunningCustomAction:action]; } seconds:10.0]);
    XCTAssertEqualObjects([self pasteboardString], @"sent to work");

    // Its button goes just before Copy, after Save where the toolbar has it (not under GNOME).
    NSArray<NSString *> *identifiers = [app toolbarDefaultItemIdentifiers:[[NSToolbar alloc] initWithIdentifier:@"test"]];
    NSUInteger save = [identifiers indexOfObject:@"com.screenshottool.toolbar.save"];
    NSUInteger send = [identifiers indexOfObject:@"com.screenshottool.toolbar.action.send"];
    NSUInteger copy = [identifiers indexOfObject:@"com.screenshottool.toolbar.copy"];
    XCTAssertTrue(send != NSNotFound && copy != NSNotFound && send < copy, @"The action, then Copy: %@", identifiers);
    XCTAssertTrue(save == NSNotFound || save < send, @"Save, then the action: %@", identifiers);
}
#endif

#if defined(GNUSTEP) && !defined(_WIN32)
/// Under GNOME an action with an icon is an icon button, as the header bar's others are, so the
/// window's title keeps its room.
- (void)testToolbarButtonShowsItsIcon {
    [self writeAction:@"send.json" json:@"{\"title\": \"Send\", \"command\": [\"/bin/echo\", \"{choice}\"], "
                                         "\"choices\": [\"/bin/echo\", \"a\"], \"toolbar\": true, \"icon\": \"icon.png\"}"];
    AppDelegate *app = [self appWithActions];
    XCTSkipIf(app == nil, @"No window server");
    NSString *iconPath = [_directory stringByAppendingPathComponent:@"icon.png"];
    NSImage *icon = [[NSImage alloc] initWithSize:NSMakeSize(48.0, 48.0)];
    [icon lockFocus];
    [[NSColor colorWithDeviceRed:1.0 green:0.0 blue:1.0 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 48.0, 48.0));
    [icon unlockFocus];
    NSBitmapImageRep *iconRep = [NSBitmapImageRep imageRepWithData:[icon TIFFRepresentation]];
    [[iconRep representationUsingType:NSPNGFileType properties:@{}] writeToFile:iconPath atomically:YES];
    STCustomAction *action = [app loadedCustomActions].firstObject;
    XCTAssertEqualObjects(action.iconPath, iconPath, @"A relative icon is in the actions folder");

    // The item as the window's toolbar has it, laid out (GNUstep's layout once cleared the image).
    [app setupToolbar];
    NSToolbarItem *item = nil;
    for (NSToolbarItem *candidate in app.window.toolbar.items) {
        if ([candidate.itemIdentifier isEqualToString:@"com.screenshottool.toolbar.action.send"]) {
            item = candidate;
        }
    }
    XCTAssertNotNil(item, @"The action is in the toolbar: %@ (toolbar %@)", [app.window.toolbar.items valueForKey:@"itemIdentifier"], app.window.toolbar);
    [app.window orderFront:nil];
    [app.window display];
    NSButton *button = (NSButton *)item.view;
    XCTAssertTrue([button isKindOfClass:[NSButton class]]);
    XCTAssertEqualObjects(button.title, @"", @"No label beside the icon");
    XCTAssertNotNil(button.image);
    XCTAssertLessThan(NSWidth(button.frame), 70.0, @"Compact: %@", NSStringFromRect(button.frame));

    button.enabled = YES;
    [button display];
    [button lockFocus];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:button.bounds];
    [button unlockFocus];
    [app.window orderOut:nil];
    // The window outlives this app delegate; its toolbar must not call back into it.
    [app.window.toolbar setDelegate:nil];
    NSInteger magenta = 0;
    for (NSInteger y = 0; y < rep.pixelsHigh; y++) {
        for (NSInteger x = 0; x < rep.pixelsWide; x++) {
            NSColor *p = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
            if (p.redComponent > 0.8 && p.blueComponent > 0.8 && p.greenComponent < 0.3) {
                magenta++;
            }
        }
    }
    XCTAssertGreaterThan(magenta, 100, @"The icon is drawn (%ld pixels)", (long)magenta);
}
#endif

@end
