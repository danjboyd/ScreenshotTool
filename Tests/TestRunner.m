/*
 * TestRunner.m
 * Minimal test runner for GNUstep XCTest bundles on Windows.
 */

#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <stdio.h>
#if defined(_WIN32)
#include <io.h>
#define dup2 _dup2
#define fileno _fileno
#endif

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
        NSString *logPath = [cwd stringByAppendingPathComponent:@"tests_runner.log"];
        FILE *logFile = fopen(logPath.UTF8String, "w");
        if (logFile) {
            dup2(fileno(logFile), fileno(stderr));
            dup2(fileno(logFile), fileno(stdout));
        }
        NSString *bundlePath = @"Tests/ScreenshotToolTests.bundle";
        if (argc > 1 && argv[1]) {
            bundlePath = [NSString stringWithUTF8String:argv[1]];
        }

        NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
        if (!bundle || ![bundle load]) {
            fprintf(stderr, "Failed to load test bundle at %s\n", bundlePath.UTF8String);
            return 2;
        }

        Class runnerClass = NSClassFromString(@"GSXCTestRunner");
        if (!runnerClass) {
            fprintf(stderr, "GSXCTestRunner not found after loading bundle\n");
            return 3;
        }

        id runner = [[runnerClass alloc] init];
        BOOL (*runAll)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
        fprintf(stderr, "Running ScreenshotTool XCTest bundle...\n");
        BOOL ok = runAll(runner, @selector(runAll));
        fprintf(stderr, "XCTest bundle finished: %s\n", ok ? "PASS" : "FAIL");
        if (logFile) {
            fclose(logFile);
        }
#if !__has_feature(objc_arc)
        [runner release];
#endif
        return ok ? 0 : 1;
    }
}
