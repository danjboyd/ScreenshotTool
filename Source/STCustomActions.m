#import "STCustomActions.h"

static const NSTimeInterval STCustomActionDefaultTimeout = 120.0;

static NSString *STTrimmed(NSString *string) {
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@interface STCustomAction ()
@property (nonatomic, copy, readwrite) NSString *identifier;
@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *command;
@property (nonatomic, copy, readwrite, nullable) NSArray<NSString *> *choicesCommand;
@property (nonatomic, assign, readwrite) STCustomActionOutput output;
@property (nonatomic, assign, readwrite) BOOL showsInToolbar;
@property (nonatomic, assign, readwrite) NSTimeInterval timeout;
@property (nonatomic, copy, readwrite, nullable) NSString *iconPath;
@end

@implementation STCustomAction

/// An environment variable as it is now (GNUstep's NSProcessInfo keeps the launch's).
static NSString *STEnvironmentValue(const char *name) {
    const char *value = getenv(name);
    return (value && value[0] != '\0') ? [NSString stringWithUTF8String:value] : nil;
}

+ (NSString *)actionsDirectory {
    NSString *override = STEnvironmentValue("SCREENSHOT_TOOL_ACTIONS_DIR");
    if (override.length > 0) {
        return [override stringByExpandingTildeInPath];
    }
#if defined(_WIN32)
    NSString *appData = STEnvironmentValue("APPDATA");
    if (appData.length == 0) {
        appData = [NSHomeDirectory() stringByAppendingPathComponent:@"AppData/Roaming"];
    }
    return [[appData stringByAppendingPathComponent:@"ScreenshotTool"] stringByAppendingPathComponent:@"Actions"];
#elif defined(GNUSTEP)
    NSString *config = STEnvironmentValue("XDG_CONFIG_HOME");
    if (config.length == 0 || ![config isAbsolutePath]) {
        config = [NSHomeDirectory() stringByAppendingPathComponent:@".config"];
    }
    return [[config stringByAppendingPathComponent:@"screenshottool"] stringByAppendingPathComponent:@"actions"];
#else
    NSString *support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    if (support.length == 0) {
        support = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    }
    return [[support stringByAppendingPathComponent:@"ScreenshotTool"] stringByAppendingPathComponent:@"Actions"];
#endif
}

+ (NSArray<STCustomAction *> *)actionsInDirectory:(NSString *)directory problems:(NSMutableArray<NSString *> *)problems {
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL];
    NSMutableArray<STCustomAction *> *actions = [[NSMutableArray alloc] init];
    for (NSString *name in [names sortedArrayUsingSelector:@selector(compare:)]) {
        if (![[name pathExtension] isEqualToString:@"json"] || [name hasPrefix:@"."]) {
            continue;
        }
        NSString *problem = nil;
        STCustomAction *action = [self actionWithContentsOfFile:[directory stringByAppendingPathComponent:name] problem:&problem];
        if (action) {
            [actions addObject:action];
        } else if (problem) {
            [problems addObject:[NSString stringWithFormat:@"%@: %@", name, problem]];
        }
    }
    [actions sortUsingComparator:^NSComparisonResult(STCustomAction *a, STCustomAction *b) {
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    return actions;
}

/// An array of one or more strings, the first not empty: a command and its arguments.
static NSArray<NSString *> *STCommandFromJSON(id value) {
    if (![value isKindOfClass:[NSArray class]] || [(NSArray *)value count] == 0) {
        return nil;
    }
    for (id part in (NSArray *)value) {
        if (![part isKindOfClass:[NSString class]]) {
            return nil;
        }
    }
    NSArray<NSString *> *command = value;
    return command.firstObject.length > 0 ? command : nil;
}

+ (instancetype)actionWithContentsOfFile:(NSString *)path problem:(NSString **)problem {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        if (problem) {
            *problem = @"can't be read";
        }
        return nil;
    }
    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (problem) {
            *problem = json ? @"isn't a JSON object" : [NSString stringWithFormat:@"isn't valid JSON (%@)", error.localizedDescription ?: @"parse error"];
        }
        return nil;
    }
    NSDictionary *object = json;

    id title = object[@"title"];
    if (![title isKindOfClass:[NSString class]] || STTrimmed(title).length == 0) {
        if (problem) {
            *problem = @"needs a \"title\"";
        }
        return nil;
    }
    NSArray<NSString *> *command = STCommandFromJSON(object[@"command"]);
    if (!command) {
        if (problem) {
            *problem = @"needs a \"command\": the program and its arguments, as strings";
        }
        return nil;
    }
    NSArray<NSString *> *choices = nil;
    if (object[@"choices"]) {
        choices = STCommandFromJSON(object[@"choices"]);
        if (!choices) {
            if (problem) {
                *problem = @"\"choices\" must be a command: the program and its arguments, as strings";
            }
            return nil;
        }
    }
    STCustomActionOutput output = STCustomActionOutputClipboard;
    id outputValue = object[@"output"];
    if (outputValue) {
        if ([outputValue isEqual:@"clipboard"]) {
            output = STCustomActionOutputClipboard;
        } else if ([outputValue isEqual:@"none"]) {
            output = STCustomActionOutputNone;
        } else {
            if (problem) {
                *problem = @"\"output\" must be \"clipboard\" or \"none\"";
            }
            return nil;
        }
    }
    NSTimeInterval timeout = STCustomActionDefaultTimeout;
    id timeoutValue = object[@"timeout"];
    if ([timeoutValue isKindOfClass:[NSNumber class]] && [timeoutValue doubleValue] > 0.0) {
        timeout = [timeoutValue doubleValue];
    }

    STCustomAction *action = [[self alloc] init];
    action.identifier = [[path lastPathComponent] stringByDeletingPathExtension];
    action.title = STTrimmed(title);
    action.command = command;
    action.choicesCommand = choices;
    action.output = output;
    action.showsInToolbar = [object[@"toolbar"] respondsToSelector:@selector(boolValue)] && [object[@"toolbar"] boolValue];
    action.timeout = timeout;
    id icon = object[@"icon"];
    if ([icon isKindOfClass:[NSString class]] && [icon length] > 0) {
        NSString *iconPath = [icon stringByExpandingTildeInPath];
        if (![iconPath isAbsolutePath]) {
            iconPath = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:iconPath];
        }
        action.iconPath = iconPath;
    }
    return action;
}

- (NSArray<NSString *> *)argumentsForFile:(NSString *)file choice:(NSString *)choice problem:(NSString **)problem {
    NSMutableArray<NSString *> *arguments = [[NSMutableArray alloc] initWithCapacity:self.command.count];
    for (NSString *part in self.command) {
        NSString *argument = [part stringByReplacingOccurrencesOfString:@"{file}" withString:file];
        if ([argument rangeOfString:@"{choice}"].location != NSNotFound) {
            if (choice.length == 0) {
                if (problem) {
                    *problem = self.choicesCommand ? @"There's nothing to choose from." : @"Its command uses {choice}, but it has no \"choices\".";
                }
                return nil;
            }
            argument = [argument stringByReplacingOccurrencesOfString:@"{choice}" withString:choice];
        }
        [arguments addObject:argument];
    }
    arguments[0] = [arguments[0] stringByExpandingTildeInPath];
    return arguments;
}

@end

@implementation STCustomActionResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _standardOutput = @"";
        _standardError = @"";
    }
    return self;
}

- (BOOL)succeeded {
    return self.launched && !self.timedOut && self.status == 0;
}

- (NSString *)failureSummary {
    if (!self.launched) {
        NSString *reason = STTrimmed(self.standardError);
        return reason.length > 0 ? reason : @"The command couldn't be started.";
    }
    if (self.timedOut) {
        return @"The command took too long and was stopped.";
    }
    NSArray<NSString *> *lines = [STTrimmed(self.standardError) componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSString *last = STTrimmed(lines.lastObject ?: @"");
    return last.length > 0 ? last : [NSString stringWithFormat:@"The command failed (exit status %d).", self.status];
}

@end

@implementation STCustomActionRunner

+ (NSDictionary<NSString *, NSString *> *)childEnvironmentFrom:(NSDictionary<NSString *, NSString *> *)environment {
    NSString *appDir = environment[@"APPDIR"];
    if (appDir.length == 0 && environment[@"APPIMAGE"].length == 0) {
        return environment; // Not an AppImage: the environment is the user's own.
    }
    NSMutableDictionary<NSString *, NSString *> *child = [environment mutableCopy];
    for (NSString *key in environment) {
        if ([key hasPrefix:@"GNUSTEP_"] || [key isEqualToString:@"LD_LIBRARY_PATH"] ||
            [key isEqualToString:@"FONTCONFIG_FILE"] || [key isEqualToString:@"FONTCONFIG_PATH"] ||
            [key isEqualToString:@"GSETTINGS_SCHEMA_DIR"] || [key hasPrefix:@"GDK_PIXBUF_"] ||
            [key isEqualToString:@"GIO_MODULE_DIR"] || [key isEqualToString:@"PYTHONHOME"] ||
            [key isEqualToString:@"PYTHONPATH"]) {
            [child removeObjectForKey:key];
        }
    }
    // The AppImage's own folders on PATH: inside its mount (or extraction) and, for the CI build,
    // its usr/bin.
    NSString *path = environment[@"PATH"];
    if (path.length > 0) {
        NSMutableArray<NSString *> *kept = [[NSMutableArray alloc] init];
        for (NSString *entry in [path componentsSeparatedByString:@":"]) {
            BOOL inAppImage = (appDir.length > 0 && [entry hasPrefix:appDir]) || [entry hasPrefix:@"/tmp/.mount_"];
            if (entry.length > 0 && !inAppImage) {
                [kept addObject:entry];
            }
        }
        child[@"PATH"] = [kept componentsJoinedByString:@":"];
    }
    return child;
}

+ (NSString *)resolvedExecutable:(NSString *)name searchPath:(NSString *)path {
    NSFileManager *files = [NSFileManager defaultManager];
    if ([name isAbsolutePath] || [name rangeOfString:@"/"].location != NSNotFound
#if defined(_WIN32)
        || [name rangeOfString:@"\\"].location != NSNotFound
#endif
    ) {
        return [files isExecutableFileAtPath:name] ? name : nil;
    }
#if defined(_WIN32)
    NSString *separator = @";";
    NSArray<NSString *> *suffixes = @[@"", @".exe", @".bat", @".cmd"];
#else
    NSString *separator = @":";
    NSArray<NSString *> *suffixes = @[@""];
#endif
    for (NSString *folder in [path componentsSeparatedByString:separator]) {
        if (folder.length == 0) {
            continue;
        }
        for (NSString *suffix in suffixes) {
            NSString *candidate = [folder stringByAppendingPathComponent:[name stringByAppendingString:suffix]];
            BOOL isDirectory = NO;
            if ([files fileExistsAtPath:candidate isDirectory:&isDirectory] && !isDirectory && [files isExecutableFileAtPath:candidate]) {
                return candidate;
            }
        }
    }
    return nil;
}

+ (void)runArguments:(NSArray<NSString *> *)arguments
             timeout:(NSTimeInterval)timeout
          completion:(void (^)(STCustomActionResult *))completion {
    NSDictionary<NSString *, NSString *> *environment = [self childEnvironmentFrom:[[NSProcessInfo processInfo] environment]];
    NSString *program = arguments.count > 0 ? [self resolvedExecutable:arguments[0] searchPath:environment[@"PATH"]] : nil;
    NSDictionary *job = @{ @"arguments": [arguments copy], @"environment": environment, @"program": program ?: [NSNull null],
                           @"timeout": @(timeout), @"completion": [completion copy] };
    // The whole run on a thread of its own: GNUstep's NSTask watches for the process ending on
    // the run loop of the thread that launched it (on Windows the main thread never heard).
    NSThread *thread = [[NSThread alloc] initWithTarget:self selector:@selector(runJob:) object:job];
    [thread start];
}

+ (void)runJob:(NSDictionary *)job {
    @autoreleasepool {
        NSArray<NSString *> *arguments = job[@"arguments"];
        id program = job[@"program"];
        NSTimeInterval timeout = [job[@"timeout"] doubleValue];
        void (^completion)(STCustomActionResult *) = job[@"completion"];
        STCustomActionResult *result = [[STCustomActionResult alloc] init];

        if (![program isKindOfClass:[NSString class]]) {
            result.standardError = arguments.count > 0
                ? [NSString stringWithFormat:@"%@ isn't a program that can be run.", arguments[0]]
                : @"There's no command.";
            [self finish:result completion:completion];
            return;
        }

        // Output goes to files, not pipes: a helper the command leaves running (an SSH connection
        // kept open, say) would hold a pipe open, and reading it would never end.
        NSString *stem = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"screenshottool-action-%@", [[NSProcessInfo processInfo] globallyUniqueString]]];
        NSString *outPath = [stem stringByAppendingString:@".out"];
        NSString *errPath = [stem stringByAppendingString:@".err"];
        NSFileManager *files = [NSFileManager defaultManager];
        [files createFileAtPath:outPath contents:nil attributes:nil];
        [files createFileAtPath:errPath contents:nil attributes:nil];
        NSFileHandle *outHandle = [NSFileHandle fileHandleForWritingAtPath:outPath];
        NSFileHandle *errHandle = [NSFileHandle fileHandleForWritingAtPath:errPath];

        NSTask *task = [[NSTask alloc] init];
        task.launchPath = program;
        task.arguments = [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)];
        task.environment = job[@"environment"];
        task.standardInput = [NSFileHandle fileHandleWithNullDevice];
        task.standardOutput = outHandle;
        task.standardError = errHandle;
        @try {
            [task launch];
            result.launched = YES;
        } @catch (NSException *exception) {
            result.standardError = [NSString stringWithFormat:@"%@ couldn't be started: %@", program, exception.reason ?: exception.name];
        }
        [outHandle closeFile];
        [errHandle closeFile];

        if (result.launched) {
            // This thread's run loop is where NSTask hears that the process ended.
            NSDate *deadline = timeout > 0.0 ? [NSDate dateWithTimeIntervalSinceNow:timeout] : nil;
            while ([task isRunning]) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
                if (deadline && [deadline timeIntervalSinceNow] <= 0.0 && [task isRunning]) {
                    result.timedOut = YES;
                    [task terminate];
                    deadline = nil;
                }
            }
            result.status = [task terminationStatus];
            result.standardOutput = [[NSString alloc] initWithData:[NSData dataWithContentsOfFile:outPath] ?: [NSData data]
                                                          encoding:NSUTF8StringEncoding] ?: @"";
            result.standardError = [[NSString alloc] initWithData:[NSData dataWithContentsOfFile:errPath] ?: [NSData data]
                                                         encoding:NSUTF8StringEncoding] ?: @"";
        }
        [files removeItemAtPath:outPath error:NULL];
        [files removeItemAtPath:errPath error:NULL];
        [self finish:result completion:completion];
    }
}

/// Calls `completion` with `result` on the main thread.
+ (void)finish:(STCustomActionResult *)result completion:(void (^)(STCustomActionResult *))completion {
    void (^call)(void) = ^{
        completion(result);
    };
    [self performSelectorOnMainThread:@selector(runBlock:) withObject:[call copy] waitUntilDone:NO];
}

+ (void)runBlock:(void (^)(void))block {
    block();
}

@end
