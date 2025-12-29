/*
 * TestEnvironmentHelpers.h
 * Helpers for test environment setup across platforms.
 */

#import <Foundation/Foundation.h>
#include <stdlib.h>

static inline void STSetEnvVar(const char *name, const char *value) {
#if defined(_WIN32)
    if (name && value) {
        _putenv_s(name, value);
    }
#else
    if (name && value) {
        setenv(name, value, 1);
    }
#endif
}

static inline void STUnsetEnvVar(const char *name) {
#if defined(_WIN32)
    if (name) {
        _putenv_s(name, "");
    }
#else
    if (name) {
        unsetenv(name);
    }
#endif
}

static inline void STConfigureTestDefaults(void) {
    NSString *tempRoot = NSTemporaryDirectory();
    if (!tempRoot.length) {
        return;
    }

    NSString *defaultsDir = [tempRoot stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"ScreenshotToolDefaults-%@", [NSUUID UUID].UUIDString]];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:defaultsDir
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&error]) {
        NSLog(@"Failed to create defaults dir for tests: %@", error);
        return;
    }

    NSString *defaultsFile = [defaultsDir stringByAppendingPathComponent:@"GNUstepDefaults.plist"];
    STSetEnvVar("GNUSTEP_DEFAULTS_ROOT", defaultsDir.UTF8String);
    STSetEnvVar("GNUSTEP_USER_DEFAULTS", defaultsFile.UTF8String);
}
