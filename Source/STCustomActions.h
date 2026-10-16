#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// What happens to a custom action's standard output when it succeeds.
typedef NS_ENUM(NSInteger, STCustomActionOutput) {
    /// Copied to the clipboard as text, trimmed, and shown: "Copied …".
    STCustomActionOutputClipboard = 0,
    /// Ignored; the app just says the action finished.
    STCustomActionOutputNone = 1,
};

/// A command the user adds to the app: it gets the annotated image (the selection, if there is
/// one, as Copy copies) as a PNG file and runs (#221).
/// Each is a JSON file in +actionsDirectory:
///
///     { "title": "Send to Server",
///       "command": ["/usr/local/bin/upload", "--file", "{file}", "--host", "{choice}"],
///       "choices": ["/usr/local/bin/upload", "--list-hosts"],
///       "output": "clipboard",
///       "toolbar": true }
///
/// `command` is the program and its arguments. `{file}` is the PNG's path, and `{choice}` the
/// choice picked from the action's menu, or the first one. `choices`, optional, is a command
/// whose output lines are the choices. `output` is "clipboard" (the default) or "none".
/// `toolbar` adds a button for it, and `icon`, an image file (relative to the actions folder or
/// absolute), makes the button that image, as GNOME's header bar needs to keep room for the
/// window's title. `timeout` (seconds, 120 by default) stops a command that hangs. The PNG and
/// its folder are removed once the command exits, so a command that hands the file to a
/// process it leaves running must copy it first. Actions are personal: the app ships none.
@interface STCustomAction : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSArray<NSString *> *command;
@property (nonatomic, copy, readonly, nullable) NSArray<NSString *> *choicesCommand;
@property (nonatomic, assign, readonly) STCustomActionOutput output;
@property (nonatomic, assign, readonly) BOOL showsInToolbar;
@property (nonatomic, assign, readonly) NSTimeInterval timeout;
/// The image file for its button, resolved, or nil.
@property (nonatomic, copy, readonly, nullable) NSString *iconPath;

/// The folder the app reads actions from: $SCREENSHOT_TOOL_ACTIONS_DIR if set, else
/// ~/.config/screenshottool/actions on Linux and the BSDs ($XDG_CONFIG_HOME),
/// %APPDATA%\ScreenshotTool\Actions on Windows, and
/// ~/Library/Application Support/ScreenshotTool/Actions on macOS.
+ (NSString *)actionsDirectory;

/// Every valid action in `directory`, by title. A file that isn't one is skipped, and why goes
/// in `problems` (one line each, naming the file).
+ (NSArray<STCustomAction *> *)actionsInDirectory:(NSString *)directory
                                         problems:(nullable NSMutableArray<NSString *> *)problems;

/// The action a JSON file describes, or nil with the reason in `problem`.
+ (nullable instancetype)actionWithContentsOfFile:(NSString *)path problem:(NSString * _Nullable * _Nullable)problem;

/// `command` with `{file}` and `{choice}` filled in. nil, with the reason in `problem`, if it
/// needs a choice and there's none.
- (nullable NSArray<NSString *> *)argumentsForFile:(NSString *)file
                                            choice:(nullable NSString *)choice
                                           problem:(NSString * _Nullable * _Nullable)problem;

@end

/// How a command run ended.
@interface STCustomActionResult : NSObject
@property (nonatomic, assign) int status;
@property (nonatomic, assign) BOOL timedOut;
@property (nonatomic, assign) BOOL launched;
@property (nonatomic, copy) NSString *standardOutput;
@property (nonatomic, copy) NSString *standardError;
/// Launched, exited 0 and didn't time out.
@property (nonatomic, readonly) BOOL succeeded;
/// A line for the user on why it failed: the error output's last line, or the status.
@property (nonatomic, readonly) NSString *failureSummary;
@end

/// Runs a command in the background, with its own environment (+childEnvironmentFrom:).
@interface STCustomActionRunner : NSObject

/// Runs `arguments` (a program, found on PATH if it's a bare name, and its arguments), and
/// calls `completion` on the main thread. `timeout` > 0 stops it after that many seconds.
+ (void)runArguments:(NSArray<NSString *> *)arguments
             timeout:(NSTimeInterval)timeout
          completion:(void (^)(STCustomActionResult *result))completion;

/// The environment for a command the app runs: the app's own, less what an AppImage adds for
/// its bundled libraries (LD_LIBRARY_PATH, GNUstep's and fontconfig's settings, and its own
/// folders on PATH), which would load them into the user's tools.
+ (NSDictionary<NSString *, NSString *> *)childEnvironmentFrom:(NSDictionary<NSString *, NSString *> *)environment;

/// The environment's PATH. On Windows it's matched in any case: it's usually "Path" there.
+ (nullable NSString *)searchPathInEnvironment:(NSDictionary<NSString *, NSString *> *)environment;

/// `name` if it's a path, else the first executable of that name on `path` (PATH's format).
+ (nullable NSString *)resolvedExecutable:(NSString *)name searchPath:(nullable NSString *)path;

@end

NS_ASSUME_NONNULL_END
