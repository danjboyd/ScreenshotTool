/*
 * main.m
 * Copyright (C) 2025 Daniel Boyd
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA.
 */

#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

static const char *STBootstrapLogPath(void) {
    const char *override = getenv("SCREENSHOT_TOOL_BOOTSTRAP_LOG");
    if (override && override[0] != '\0') {
        return override;
    }
#if defined(_WIN32)
    const char *localAppData = getenv("LOCALAPPDATA");
    if (localAppData && localAppData[0] != '\0') {
        static char path[1024];
        snprintf(path, sizeof(path), "%s\\ScreenshotTool-bootstrap.log", localAppData);
        return path;
    }
    return "ScreenshotTool-bootstrap.log";
#else
    // Elsewhere the regular log covers startup; only write this trace when asked to.
    return NULL;
#endif
}

static void STBootstrapLog(const char *format, ...) {
    const char *path = STBootstrapLogPath();
    if (!path) {
        return;
    }
    FILE *fp = fopen(path, "a");
    if (!fp) {
        return;
    }

    va_list args;
    va_start(args, format);
    vfprintf(fp, format, args);
    va_end(args);
    fputc('\n', fp);
    fclose(fp);
}

int main(int argc, const char *argv[]) {
    STBootstrapLog("main: entry argc=%d", argc);
    @try {
        @autoreleasepool {
#if defined(_WIN32)
            if (getenv("GSTheme") == NULL) {
                _putenv("GSTheme=WinUITheme");
                STBootstrapLog("main: defaulted GSTheme=WinUITheme");
            }
#endif
            STBootstrapLog("main: before sharedApplication");
            [NSApplication sharedApplication];
            STBootstrapLog("main: after sharedApplication");

            [NSUserDefaults standardUserDefaults];
            STBootstrapLog("main: after standardUserDefaults");

            AppDelegate *delegate = [[AppDelegate alloc] init];
            STBootstrapLog("main: after AppDelegate init delegate=%p", delegate);

            [NSApp setDelegate:delegate];
            STBootstrapLog("main: after setDelegate");

            [NSApp run];
            STBootstrapLog("main: after NSApp run");
            return 0;
        }
    } @catch (NSException *exception) {
        STBootstrapLog("main: caught NSException name=%s reason=%s",
                       [[exception name] UTF8String] ?: "<nil>",
                       [[exception reason] UTF8String] ?: "<nil>");
        @throw;
    } @catch (id exceptionObject) {
        STBootstrapLog("main: caught non-NSException Objective-C object=%p", exceptionObject);
        @throw;
    }
}
