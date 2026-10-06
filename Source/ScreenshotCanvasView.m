/*
 * ScreenshotCanvasView.m
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

#import "ScreenshotCanvasView.h"
#import <objc/runtime.h>
#import "MarkupStroke.h"
#import "MarkupText.h"
#import "STThemeUtilities.h"
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColorSpace.h>
#import <AppKit/NSMenuItem.h>
#include <stdarg.h>
#include <math.h>
#include <string.h>
#include <float.h>
#include <stdlib.h>
#if defined(GNUSTEP) && !defined(__APPLE__)
#define ST_ENABLE_GNUSTEP_WORKAROUNDS 1
#else
#define ST_ENABLE_GNUSTEP_WORKAROUNDS 0
#endif

NSString * const ScreenshotCanvasViewDidRestoreStateNotification = @"ScreenshotCanvasViewDidRestoreStateNotification";
NSString * const ScreenshotCanvasViewRequestsToolNotification = @"ScreenshotCanvasViewRequestsToolNotification";
NSString * const ScreenshotCanvasViewToolKey = @"tool";
NSString * const ScreenshotCanvasViewDidBeginTextEditingNotification = @"ScreenshotCanvasViewDidBeginTextEditingNotification";
NSString * const ScreenshotCanvasViewDidEndTextEditingNotification = @"ScreenshotCanvasViewDidEndTextEditingNotification";
NSString * const ScreenshotCanvasViewRequestsTextFormatNotification = @"ScreenshotCanvasViewRequestsTextFormatNotification";
NSString * const ScreenshotCanvasViewTextFormatKey = @"format";
#if ST_ENABLE_GNUSTEP_WORKAROUNDS
BOOL ScreenshotUndoLoggingEnabled(void) __attribute__((weak));
#else
static BOOL ScreenshotUndoLoggingEnabled(void) {
    return NO;
}
#endif

#if ST_ENABLE_GNUSTEP_WORKAROUNDS
@interface STTransparentTextView : NSTextView
/// Modifiers of the key event being handled, so key commands (Ctrl+Return) can see them
/// without relying on -[NSApp currentEvent].
@property (nonatomic, assign) NSEventModifierFlags handlingKeyModifierFlags;
@end

@implementation STTransparentTextView
- (BOOL)isOpaque {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
}

- (void)drawViewBackgroundInRect:(NSRect)rect {
    // Skip GNUstep's default background fill so the text box stays transparent.
}

- (void)keyDown:(NSEvent *)event {
    self.handlingKeyModifierFlags = event.modifierFlags;
    NSString *characters = event.charactersIgnoringModifiers;
    unichar key = characters.length > 0 ? [characters characterAtIndex:0] : 0;
    BOOL isReturn = (key == NSCarriageReturnCharacter || key == NSEnterCharacter || key == NSNewlineCharacter);
    NSString *format = [self formatCommandForEvent:event];
    if (format) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ScreenshotCanvasViewRequestsTextFormatNotification
                                                            object:self.delegate
                                                          userInfo:@{ ScreenshotCanvasViewTextFormatKey: format }];
    } else if (isReturn && (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) != 0) {
        // GNUstep's key bindings have no command for Control+Return; send the one the delegate
        // reads as "finish" so Ctrl+Return works whichever modifier the Ctrl key maps to.
        [self doCommandBySelector:@selector(insertNewline:)];
    } else {
        [super keyDown:event];
    }
    self.handlingKeyModifierFlags = 0;
}

/// Ctrl (or Cmd)+B / I toggle bold and italic; with Shift, > and < step the size.
- (nullable NSString *)formatCommandForEvent:(NSEvent *)event {
    NSEventModifierFlags flags = event.modifierFlags;
    if ((flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) == 0) {
        return nil;
    }
    NSString *characters = event.charactersIgnoringModifiers.lowercaseString;
    if (characters.length != 1) {
        return nil;
    }
    unichar key = [characters characterAtIndex:0];
    BOOL shift = (flags & NSEventModifierFlagShift) != 0;
    if (!shift && key == 'b') {
        return @"bold";
    }
    if (!shift && key == 'i') {
        return @"italic";
    }
    if (key == '>' || (shift && key == '.')) {
        return @"bigger";
    }
    if (key == '<' || (shift && key == ',')) {
        return @"smaller";
    }
    return nil;
}
@end
#endif

static BOOL ScreenshotCursorLoggingEnabled(void) {
    static int initialized = 0;
    static BOOL enabled = NO;
    if (!initialized) {
        const char *env = getenv("SCREENSHOT_CURSOR_DEBUG");
        enabled = (env && env[0] != '\0');
        initialized = 1;
    }
    return enabled;
}

static void ScreenshotCursorLog(NSString *format, ...) {
    if (!ScreenshotCursorLoggingEnabled() || !format) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSLogv(format, args);
    va_end(args);
}

static NSString *STCursorToolName(ScreenshotCanvasTool tool) {
    switch (tool) {
        case ScreenshotCanvasToolPen:
            return @"pen";
        case ScreenshotCanvasToolHighlighter:
            return @"highlighter";
        case ScreenshotCanvasToolEraser:
            return @"eraser";
        case ScreenshotCanvasToolSelect:
            return @"select";
        case ScreenshotCanvasToolText:
            return @"text";
        case ScreenshotCanvasToolArrow:
            return @"arrow";
        default:
            return @"unknown";
    }
}

static void STCursorWarnFallback(NSString *toolKey, NSString *reason) {
#if ST_ENABLE_GNUSTEP_WORKAROUNDS
    NSLog(@"[Cursor][WARN] tool=%@ fallback=arrow reason=%@", toolKey ?: @"<nil>", reason ?: @"unknown");
#else
    ScreenshotCursorLog(@"[CursorFallback] tool=%@ reason=%@", toolKey ?: @"<nil>", reason ?: @"unknown");
#endif
}

typedef struct {
    unsigned char *data;
    NSInteger width;
    NSInteger height;
    NSInteger bytesPerRow;
    NSInteger bytesPerPixel;
    NSInteger rIndex;
    NSInteger gIndex;
    NSInteger bIndex;
    NSInteger aIndex;
    BOOL hasAlpha;
} STBitmapBuffer;

static const CGFloat STSelectionHandleSize = 10.0f;
// The editor has no text padding, so the guide sits outside the text instead of on it.
static const CGFloat STTextGuideOutset = 4.0f;

static CGFloat STReadGSScaleFactor(void) {
    const char *rawValue = getenv("GSScaleFactor");
    if (rawValue && rawValue[0] != '\0') {
        CGFloat parsed = (CGFloat)atof(rawValue);
        if (parsed > 0.0f) {
            return parsed;
        }
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id raw = [defaults objectForKey:@"GSScaleFactor"];
    if ([raw respondsToSelector:@selector(doubleValue)]) {
        CGFloat parsed = [raw doubleValue];
        if (parsed > 0.0f) {
            return parsed;
        }
    }

    NSString *domainName = NSGlobalDomain;
    NSDictionary *global = [defaults persistentDomainForName:domainName];
    id rawGlobal = global[@"GSScaleFactor"];
    if ([rawGlobal respondsToSelector:@selector(doubleValue)]) {
        CGFloat parsed = [rawGlobal doubleValue];
        if (parsed > 0.0f) {
            return parsed;
        }
    }

    return 0.0f;
}

static BOOL STPrepareBitmapBuffer(NSBitmapImageRep *rep, STBitmapBuffer *buffer);

static inline unsigned char STRoundToByte(double value);

static BOOL STColorSpaceIsRGB(NSString *name) {
    return [name isEqualToString:NSDeviceRGBColorSpace] || [name isEqualToString:NSCalibratedRGBColorSpace];
}

/// YES for the layout the byte-wise pixel code handles: chunky 8-bit RGB or RGBA, whole bytes per pixel.
static BOOL STBitmapRepIsRGBBytes(NSBitmapImageRep *rep) {
    if (!rep || rep.isPlanar || rep.bitsPerSample != 8 || !STColorSpaceIsRGB(rep.colorSpaceName)) {
        return NO;
    }
    NSInteger samples = rep.samplesPerPixel;
    if (samples != (rep.hasAlpha ? 4 : 3)) {
        return NO;
    }
    return rep.bitsPerPixel >= samples * 8 && rep.bitsPerPixel % 8 == 0;
}

/// The same pixels as chunky 8-bit RGBA, or `source` itself when it already has a layout the
/// byte-wise code handles. Grayscale, 1/2/4/16-bit and planar images are converted (#46).
static NSBitmapImageRep *STRGBABitmapFromRep(NSBitmapImageRep *source) {
    if (!source || STBitmapRepIsRGBBytes(source)) {
        return source;
    }
    NSInteger width = source.pixelsWide;
    NSInteger height = source.pixelsHigh;
    if (width <= 0 || height <= 0) {
        return nil;
    }
    BOOL keepsPremultiplication = source.hasAlpha && ((source.bitmapFormat & NSAlphaNonpremultipliedBitmapFormat) == 0);
    NSBitmapImageRep *converted = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                          pixelsWide:width
                                                                          pixelsHigh:height
                                                                       bitsPerSample:8
                                                                     samplesPerPixel:4
                                                                            hasAlpha:YES
                                                                            isPlanar:NO
                                                                      colorSpaceName:NSDeviceRGBColorSpace
                                                                        bitmapFormat:(keepsPremultiplication ? 0 : NSAlphaNonpremultipliedBitmapFormat)
                                                                         bytesPerRow:0
                                                                        bitsPerPixel:0];
    unsigned char *destination = converted.bitmapData;
    if (!destination) {
        return nil;
    }
    [converted setSize:source.size];
    NSInteger destBytesPerRow = converted.bytesPerRow;

    NSString *space = source.colorSpaceName ?: @"";
    BOOL isRGB = STColorSpaceIsRGB(space);
    BOOL isWhite = [space isEqualToString:NSDeviceWhiteColorSpace] || [space isEqualToString:NSCalibratedWhiteColorSpace];
    BOOL isBlack = [space isEqualToString:NSDeviceBlackColorSpace] || [space isEqualToString:NSCalibratedBlackColorSpace];
    NSInteger samples = source.samplesPerPixel;
    NSInteger colorSamples = samples - (source.hasAlpha ? 1 : 0);
    BOOL knownLayout = source.bitsPerSample > 0 && source.bitsPerSample <= 16 && samples <= 5 &&
                       ((isRGB && colorSamples == 3) || ((isWhite || isBlack) && colorSamples == 1));

    if (knownLayout) {
        // getPixel: unpacks any sample size and planar data; scale each sample to a byte.
        BOOL alphaFirst = (source.bitmapFormat & NSAlphaFirstBitmapFormat) != 0;
        NSInteger colorStart = (source.hasAlpha && alphaFirst) ? 1 : 0;
        NSInteger alphaIndex = source.hasAlpha ? (alphaFirst ? 0 : colorSamples) : -1;
        double maxValue = (double)((1u << source.bitsPerSample) - 1u);
        NSUInteger pixel[5] = {0};
        for (NSInteger y = 0; y < height; y++) {
            unsigned char *row = destination + y * destBytesPerRow;
            for (NSInteger x = 0; x < width; x++) {
                [source getPixel:pixel atX:x y:y];
                unsigned char *out = row + x * 4;
                if (isRGB) {
                    out[0] = STRoundToByte(pixel[colorStart] / maxValue);
                    out[1] = STRoundToByte(pixel[colorStart + 1] / maxValue);
                    out[2] = STRoundToByte(pixel[colorStart + 2] / maxValue);
                } else {
                    double level = pixel[colorStart] / maxValue;
                    unsigned char value = STRoundToByte(isBlack ? (1.0 - level) : level);
                    out[0] = value;
                    out[1] = value;
                    out[2] = value;
                }
                out[3] = alphaIndex >= 0 ? STRoundToByte(pixel[alphaIndex] / maxValue) : 255;
            }
        }
        return converted;
    }

    // Other colour spaces (CMYK, named, …): go through NSColor, slower but general.
    for (NSInteger y = 0; y < height; y++) {
        unsigned char *row = destination + y * destBytesPerRow;
        for (NSInteger x = 0; x < width; x++) {
            NSColor *color = [[source colorAtX:x y:y] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
            unsigned char *out = row + x * 4;
            CGFloat alpha = color ? color.alphaComponent : 0.0;
            // NSColor components are unpremultiplied; match the destination's convention.
            CGFloat scale = keepsPremultiplication ? alpha : 1.0;
            out[0] = color ? STRoundToByte(color.redComponent * scale) : 0;
            out[1] = color ? STRoundToByte(color.greenComponent * scale) : 0;
            out[2] = color ? STRoundToByte(color.blueComponent * scale) : 0;
            out[3] = STRoundToByte(alpha);
        }
    }
    return converted;
}

static NSBitmapImageRep *STScaledCursorRep(NSBitmapImageRep *rep, CGFloat scale) {
    if (!rep || scale <= 1.01f) {
        return rep;
    }
    NSInteger srcWidth = rep.pixelsWide;
    NSInteger srcHeight = rep.pixelsHigh;
    NSInteger dstWidth = (NSInteger)lrint(srcWidth * scale);
    NSInteger dstHeight = (NSInteger)lrint(srcHeight * scale);
    if (srcWidth <= 0 || srcHeight <= 0 || dstWidth <= 0 || dstHeight <= 0) {
        return rep;
    }
    NSBitmapImageRep *scaled = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                       pixelsWide:dstWidth
                                                                       pixelsHigh:dstHeight
                                                                    bitsPerSample:8
                                                                  samplesPerPixel:4
                                                                         hasAlpha:YES
                                                                         isPlanar:NO
                                                                   colorSpaceName:NSDeviceRGBColorSpace
                                                                      bitmapFormat:0
                                                                       bytesPerRow:0
                                                                      bitsPerPixel:0];
    if (!scaled) {
        return rep;
    }
    [scaled setSize:NSMakeSize(dstWidth, dstHeight)];

    STBitmapBuffer src;
    STBitmapBuffer dst;
    if (!STPrepareBitmapBuffer(rep, &src) || !STPrepareBitmapBuffer(scaled, &dst)) {
        return rep;
    }

    for (NSInteger y = 0; y < dst.height; y++) {
        NSInteger srcY = (NSInteger)floor((double)y / scale);
        if (srcY < 0) {
            srcY = 0;
        } else if (srcY >= src.height) {
            srcY = src.height - 1;
        }
        unsigned char *dstRow = dst.data + (y * dst.bytesPerRow);
        unsigned char *srcRow = src.data + (srcY * src.bytesPerRow);
        for (NSInteger x = 0; x < dst.width; x++) {
            NSInteger srcX = (NSInteger)floor((double)x / scale);
            if (srcX < 0) {
                srcX = 0;
            } else if (srcX >= src.width) {
                srcX = src.width - 1;
            }
            unsigned char *dstPixel = dstRow + (x * dst.bytesPerPixel);
            unsigned char *srcPixel = srcRow + (srcX * src.bytesPerPixel);
            dstPixel[dst.rIndex] = srcPixel[src.rIndex];
            dstPixel[dst.gIndex] = srcPixel[src.gIndex];
            dstPixel[dst.bIndex] = srcPixel[src.bIndex];
            if (dst.hasAlpha) {
                dstPixel[dst.aIndex] = src.hasAlpha ? srcPixel[src.aIndex] : 255;
            }
        }
    }

    return scaled;
}

static CGFloat STCursorScaleFactor(void) {
    static int initialized = 0;
    static CGFloat scale = 1.0f;
    if (!initialized) {
        initialized = 1;
        CGFloat parsed = STReadGSScaleFactor();
        if (parsed > 0.0f) {
            scale = parsed;
        }
        if (scale < 1.0f) {
            scale = 1.0f;
        }
        ScreenshotCursorLog(@"[CursorScale] scale=%.3f", scale);
    }
    return scale;
}

#if ST_ENABLE_GNUSTEP_WORKAROUNDS
#define STUndoLoggingActive() (ScreenshotUndoLoggingEnabled && ScreenshotUndoLoggingEnabled())
#else
#define STUndoLoggingActive() (ScreenshotUndoLoggingEnabled())
#endif

static inline unsigned char STRoundToByte(double value) {
    if (value <= 0.0) {
        return 0;
    }
    if (value >= 1.0) {
        return 255;
    }
    return (unsigned char)lrint(value * 255.0);
}

static inline double STClamp01(double value) {
    if (value <= 0.0) {
        return 0.0;
    }
    if (value >= 1.0) {
        return 1.0;
    }
    return value;
}

static BOOL STPrepareBitmapBuffer(NSBitmapImageRep *rep, STBitmapBuffer *buffer) {
    if (!rep || !buffer) {
        return NO;
    }
    // The byte-wise code below reads and writes R, G, B (and A) bytes in place: anything else
    // (grayscale, sub-byte or 16-bit samples, planar data) would be read and written out of
    // bounds (#46). Callers normalise with STRGBABitmapFromRep first.
    if (!STBitmapRepIsRGBBytes(rep)) {
        return NO;
    }
    NSInteger width = rep.pixelsWide;
    NSInteger height = rep.pixelsHigh;
    NSInteger bytesPerRow = rep.bytesPerRow;
    if (width <= 0 || height <= 0 || bytesPerRow <= 0) {
        return NO;
    }
    unsigned char *data = rep.bitmapData;
    if (!data) {
        return NO;
    }

    NSInteger bytesPerPixel = bytesPerRow / width;
    if (bytesPerPixel < rep.samplesPerPixel) {
        bytesPerPixel = rep.samplesPerPixel;
    }

    BOOL hasAlpha = rep.hasAlpha;
    NSBitmapFormat format = rep.bitmapFormat;
    BOOL alphaFirst = ((format & NSAlphaFirstBitmapFormat) == NSAlphaFirstBitmapFormat);

    NSInteger aIndex = -1;
    NSInteger rIndex = 0;
    NSInteger gIndex = 1;
    NSInteger bIndex = 2;

    if (hasAlpha) {
        if (alphaFirst) {
            aIndex = 0;
            rIndex = 1;
            gIndex = 2;
            bIndex = 3;
        } else {
            aIndex = MIN(bytesPerPixel - 1, 3);
        }
    }

    buffer->data = data;
    buffer->width = width;
    buffer->height = height;
    buffer->bytesPerRow = bytesPerRow;
    buffer->bytesPerPixel = bytesPerPixel;
    buffer->rIndex = rIndex;
    buffer->gIndex = gIndex;
    buffer->bIndex = bIndex;
    buffer->aIndex = aIndex;
    buffer->hasAlpha = hasAlpha && (aIndex >= 0);
    return YES;
}

static inline void STBlendPixel(STBitmapBuffer *buffer,
                                NSInteger x,
                                NSInteger y,
                                double sr,
                                double sg,
                                double sb,
                                double sa) {
    if (!buffer || sa <= 0.0) {
        return;
    }
    if (x < 0 || x >= buffer->width || y < 0 || y >= buffer->height) {
        return;
    }

    NSInteger rowIndex = buffer->height - 1 - y;
    unsigned char *row = buffer->data + (buffer->bytesPerRow * rowIndex);
    unsigned char *pixel = row + (buffer->bytesPerPixel * x);

    double dr = pixel[buffer->rIndex] / 255.0;
    double dg = pixel[buffer->gIndex] / 255.0;
    double db = pixel[buffer->bIndex] / 255.0;

    double outR = sr * sa + dr * (1.0 - sa);
    double outG = sg * sa + dg * (1.0 - sa);
    double outB = sb * sa + db * (1.0 - sa);

    pixel[buffer->rIndex] = STRoundToByte(outR);
    pixel[buffer->gIndex] = STRoundToByte(outG);
    pixel[buffer->bIndex] = STRoundToByte(outB);

    if (buffer->hasAlpha) {
        double da = pixel[buffer->aIndex] / 255.0;
        double outA = sa + da * (1.0 - sa);
        pixel[buffer->aIndex] = STRoundToByte(outA);
    }
}

static inline void STBlendPixelWithMask(STBitmapBuffer *buffer,
                                        uint8_t *mask,
                                        NSInteger x,
                                        NSInteger y,
                                        double sr,
                                        double sg,
                                        double sb,
                                        double sa) {
    if (mask) {
        size_t rowIndex = (size_t)(buffer->height - 1 - y);
        size_t idx = rowIndex * (size_t)buffer->width + (size_t)x;
        if (mask[idx]) {
            return;
        }
        mask[idx] = 1;
    }
    STBlendPixel(buffer, x, y, sr, sg, sb, sa);
}

static void STBlendDiskWithMask(STBitmapBuffer *buffer,
                                double centerX,
                                double centerY,
                                double radius,
                                double sr,
                                double sg,
                                double sb,
                                double sa,
                                uint8_t *mask) {
    if (!buffer || sa <= 0.0 || radius <= 0.0) {
        return;
    }

    NSInteger minX = (NSInteger)floor(centerX - radius);
    NSInteger maxX = (NSInteger)ceil(centerX + radius);
    NSInteger minY = (NSInteger)floor(centerY - radius);
    NSInteger maxY = (NSInteger)ceil(centerY + radius);

    minX = MAX(0, minX);
    minY = MAX(0, minY);
    maxX = MIN(buffer->width - 1, maxX);
    maxY = MIN(buffer->height - 1, maxY);

    double radiusSquared = radius * radius;
    for (NSInteger y = minY; y <= maxY; ++y) {
        double dy = ((double)y + 0.5) - centerY;
        double dy2 = dy * dy;
        for (NSInteger x = minX; x <= maxX; ++x) {
            double dx = ((double)x + 0.5) - centerX;
            double distanceSquared = dx * dx + dy2;
            if (distanceSquared <= radiusSquared) {
                STBlendPixelWithMask(buffer, mask, x, y, sr, sg, sb, sa);
            }
        }
    }
}

static void STBlendDisk(STBitmapBuffer *buffer,
                        double centerX,
                        double centerY,
                        double radius,
                        double sr,
                        double sg,
                        double sb,
                        double sa) {
    STBlendDiskWithMask(buffer, centerX, centerY, radius, sr, sg, sb, sa, NULL);
}

static NSBitmapImageRep *STCreateDeviceRGBBitmapFromRep(NSBitmapImageRep *source) {
    if (!source) {
        return nil;
    }
    NSInteger width = source.pixelsWide;
    NSInteger height = source.pixelsHigh;
    if (width <= 0 || height <= 0) {
        return nil;
    }

    NSBitmapImageRep *converted = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                          pixelsWide:width
                                                                          pixelsHigh:height
                                                                       bitsPerSample:8
                                                                     samplesPerPixel:4
                                                                            hasAlpha:YES
                                                                            isPlanar:NO
                                                                      colorSpaceName:NSDeviceRGBColorSpace
                                                                         bytesPerRow:0
                                                                        bitsPerPixel:0];
    if (!converted) {
        return nil;
    }

    [converted setSize:source.size];

    unsigned char *destination = [converted bitmapData];
    if (!destination) {
        return nil;
    }
    NSInteger destBytesPerRow = [converted bytesPerRow];

    STBitmapBuffer sourceBuffer;
    BOOL hasSourceBuffer = STPrepareBitmapBuffer(source, &sourceBuffer);
    if (hasSourceBuffer && sourceBuffer.bytesPerPixel >= 3) {
        for (NSInteger y = 0; y < height; y++) {
            unsigned char *dstRow = destination + (y * destBytesPerRow);
            NSInteger sourceRowIndex = sourceBuffer.height - 1 - y;
            unsigned char *srcRow = sourceBuffer.data + (sourceBuffer.bytesPerRow * sourceRowIndex);
            for (NSInteger x = 0; x < width; x++) {
                unsigned char *dstPixel = dstRow + (x * 4);
                unsigned char *srcPixel = srcRow + (x * sourceBuffer.bytesPerPixel);

                double sr = srcPixel[sourceBuffer.rIndex] / 255.0;
                double sg = srcPixel[sourceBuffer.gIndex] / 255.0;
                double sb = srcPixel[sourceBuffer.bIndex] / 255.0;
                double sa = sourceBuffer.hasAlpha ? (srcPixel[sourceBuffer.aIndex] / 255.0) : 1.0;

                dstPixel[0] = STRoundToByte(sr);
                dstPixel[1] = STRoundToByte(sg);
                dstPixel[2] = STRoundToByte(sb);
                dstPixel[3] = STRoundToByte(sa);
            }
        }
    } else {
        for (NSInteger y = 0; y < height; y++) {
            unsigned char *dstRow = destination + (y * destBytesPerRow);
            for (NSInteger x = 0; x < width; x++) {
                unsigned char *dstPixel = dstRow + (x * 4);
                NSColor *color = [source colorAtX:x y:y];
                if (!color) {
                    dstPixel[0] = 0;
                    dstPixel[1] = 0;
                    dstPixel[2] = 0;
                    dstPixel[3] = 0;
                    continue;
                }
                NSColor *deviceColor = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color;
                double r = 0.0;
                double g = 0.0;
                double b = 0.0;
                double a = 1.0;
                [deviceColor getRed:&r green:&g blue:&b alpha:&a];
                dstPixel[0] = STRoundToByte(r);
                dstPixel[1] = STRoundToByte(g);
                dstPixel[2] = STRoundToByte(b);
                dstPixel[3] = STRoundToByte(a);
            }
        }
    }

    return converted;
}

static void STRasterizeHighlighterStrokeOntoBitmap(MarkupStroke *stroke,
                                                   STBitmapBuffer *buffer,
                                                   NSSize canvasSize) {
    if (!stroke || !buffer) {
        return;
    }

    NSArray<NSValue *> *points = [stroke points];
    NSUInteger count = points.count;
    if (count == 0) {
        return;
    }

    NSColor *strokeColor = stroke.color;
    NSColor *calibrated = [strokeColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (!calibrated) {
        calibrated = strokeColor;
    }
    strokeColor = [calibrated colorWithAlphaComponent:0.35];

    NSColor *deviceColor = [strokeColor colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    if (!deviceColor) {
        deviceColor = strokeColor;
    }

    double sr = [deviceColor redComponent];
    double sg = [deviceColor greenComponent];
    double sb = [deviceColor blueComponent];
    double sa = [deviceColor alphaComponent];
    if (sa <= 0.0) {
        return;
    }

    double radius = MAX(stroke.lineWidth * 0.5, 0.5);
    double spacing = MAX(radius * 0.5, 0.75);

    size_t maskLength = (size_t)buffer->width * (size_t)buffer->height;
    NSMutableData *maskData = nil;
    uint8_t *mask = NULL;
    if (maskLength > 0) {
        maskData = [[NSMutableData alloc] initWithLength:maskLength];
        mask = (uint8_t *)maskData.mutableBytes;
    }

    NSPoint firstPoint = [points.firstObject pointValue];
    double prevX = firstPoint.x;
    double prevY = canvasSize.height - firstPoint.y;
    STBlendDiskWithMask(buffer, prevX, prevY, radius, sr, sg, sb, sa, mask);

    for (NSUInteger idx = 1; idx < count; ++idx) {
        NSPoint current = [points[idx] pointValue];
        double currX = current.x;
        double currY = canvasSize.height - current.y;

        double dx = currX - prevX;
        double dy = currY - prevY;
        double distance = hypot(dx, dy);
        NSUInteger steps = (NSUInteger)ceil(distance / spacing);
        if (steps < 1) {
            steps = 1;
        }

        for (NSUInteger step = 1; step <= steps; ++step) {
            double t = (double)step / (double)steps;
            double sampleX = prevX + dx * t;
            double sampleY = prevY + dy * t;
            STBlendDiskWithMask(buffer, sampleX, sampleY, radius, sr, sg, sb, sa, mask);
        }

        prevX = currX;
        prevY = currY;
    }
}

static void STRasterizeArrowOntoBitmap(MarkupStroke *stroke, STBitmapBuffer *buffer, NSSize canvasSize);

static void STRasterizeStrokeOntoBitmap(MarkupStroke *stroke,
                                        STBitmapBuffer *buffer,
                                        NSSize canvasSize) {
    if (!stroke || !buffer) {
        return;
    }

    NSArray<NSValue *> *points = [stroke points];
    NSUInteger count = points.count;
    if (count == 0) {
        return;
    }

    if (stroke.type == MarkupStrokeTypeHighlighter) {
        STRasterizeHighlighterStrokeOntoBitmap(stroke, buffer, canvasSize);
        return;
    }
    if (stroke.type == MarkupStrokeTypeArrow) {
        STRasterizeArrowOntoBitmap(stroke, buffer, canvasSize);
        return;
    }

    NSColor *strokeColor = stroke.color;
    NSColor *deviceColor = [strokeColor colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    if (!deviceColor) {
        deviceColor = strokeColor;
    }

    double sr = [deviceColor redComponent];
    double sg = [deviceColor greenComponent];
    double sb = [deviceColor blueComponent];
    double sa = [deviceColor alphaComponent];
    if (sa <= 0.0) {
        return;
    }

    double radius = MAX(stroke.lineWidth * 0.5, 0.5);
    double spacing = MAX(radius * 0.5, 0.75);

    NSPoint firstPoint = [points.firstObject pointValue];
    double prevX = firstPoint.x;
    double prevY = canvasSize.height - firstPoint.y;
    STBlendDisk(buffer, prevX, prevY, radius, sr, sg, sb, sa);

    for (NSUInteger idx = 1; idx < count; ++idx) {
        NSPoint current = [points[idx] pointValue];
        double currX = current.x;
        double currY = canvasSize.height - current.y;

        double dx = currX - prevX;
        double dy = currY - prevY;
        double distance = hypot(dx, dy);
        NSUInteger steps = (NSUInteger)ceil(distance / spacing);
        if (steps < 1) {
            steps = 1;
        }

        for (NSUInteger step = 1; step <= steps; ++step) {
            double t = (double)step / (double)steps;
            double sampleX = prevX + dx * t;
            double sampleY = prevY + dy * t;
            STBlendDisk(buffer, sampleX, sampleY, radius, sr, sg, sb, sa);
        }

        prevX = currX;
        prevY = currY;
    }
}

// GNUstep draws no glyphs into an NSBitmapImageRep graphics context (GNUSTEP_BUG_REPORT.md), but
// it does into a locked NSImage. Annotations whose look depends on AppKit drawing (text, arrows)
// are drawn there with the canvas's own code, read back, and composited, so export matches the
// screen. `draw` receives the unflipped height to map canvas coordinates into that image.
static void STRasterizeDrawingOntoBitmap(NSRect canvasArea,
                                         STBitmapBuffer *buffer,
                                         NSSize canvasSize,
                                         void (^draw)(CGFloat unflippedHeight)) {
    if (!buffer || !buffer->data || !draw) {
        return;
    }

    NSRect area = NSIntersectionRect(NSIntegralRect(canvasArea),
                                     NSMakeRect(0.0, 0.0, canvasSize.width, canvasSize.height));
    NSInteger width = (NSInteger)NSWidth(area);
    NSInteger height = (NSInteger)NSHeight(area);
    if (width <= 0 || height <= 0) {
        return;
    }

    NSImage *image = [[NSImage alloc] initWithSize:area.size];
    NSBitmapImageRep *rep = nil;
    [image lockFocus];
    @try {
        [[NSColor clearColor] set];
        NSRectFillUsingOperation(NSMakeRect(0.0, 0.0, width, height), NSCompositeCopy);
        // Shift the drawing into this small image: x by translation, y through the unflipped
        // mapping, so a top-down canvas y of area.origin.y lands on the image's top row.
        [NSGraphicsContext saveGraphicsState];
        NSAffineTransform *shift = [NSAffineTransform transform];
        [shift translateXBy:-NSMinX(area) yBy:0.0];
        [shift concat];
        draw(height + NSMinY(area));
        [NSGraphicsContext restoreGraphicsState];
        rep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0.0, 0.0, width, height)];
    } @finally {
        [image unlockFocus];
    }
    rep = STRGBABitmapFromRep(rep);
    if (!rep || !rep.bitmapData || rep.pixelsWide <= 0 || rep.pixelsHigh <= 0) {
        return;
    }

    unsigned char *data = rep.bitmapData;
    NSInteger bytesPerPixel = rep.bitsPerPixel / 8;
    NSInteger bytesPerRow = rep.bytesPerRow;
    NSBitmapFormat format = rep.bitmapFormat;
    BOOL alphaFirst = ((format & NSAlphaFirstBitmapFormat) == NSAlphaFirstBitmapFormat);
    BOOL premultiplied = rep.hasAlpha && ((format & NSAlphaNonpremultipliedBitmapFormat) == 0);
    NSInteger aIndex = rep.hasAlpha ? (alphaFirst ? 0 : MIN(bytesPerPixel - 1, 3)) : -1;
    NSInteger rIndex = alphaFirst ? MIN(bytesPerPixel - 1, 1) : 0;
    NSInteger gIndex = alphaFirst ? MIN(bytesPerPixel - 1, 2) : MIN(bytesPerPixel - 1, 1);
    NSInteger bIndex = alphaFirst ? MIN(bytesPerPixel - 1, 3) : MIN(bytesPerPixel - 1, 2);

    NSInteger rows = MIN(height, rep.pixelsHigh);
    NSInteger columns = MIN(width, rep.pixelsWide);
    for (NSInteger row = 0; row < rows; row++) {
        // Bitmap rows run top-down; the export buffer counts rows from the bottom.
        NSInteger destY = (NSInteger)canvasSize.height - 1 - ((NSInteger)NSMinY(area) + row);
        if (destY < 0 || destY >= buffer->height) {
            continue;
        }
        unsigned char *srcRow = data + row * bytesPerRow;
        for (NSInteger col = 0; col < columns; col++) {
            NSInteger destX = (NSInteger)NSMinX(area) + col;
            if (destX < 0 || destX >= buffer->width) {
                continue;
            }
            unsigned char *srcPixel = srcRow + col * bytesPerPixel;
            double alpha = (aIndex >= 0) ? (srcPixel[aIndex] / 255.0) : 1.0;
            if (alpha <= 0.0) {
                continue;
            }
            double sr = srcPixel[rIndex] / 255.0;
            double sg = srcPixel[gIndex] / 255.0;
            double sb = srcPixel[bIndex] / 255.0;
            if (premultiplied) {
                sr = MIN(1.0, sr / alpha);
                sg = MIN(1.0, sg / alpha);
                sb = MIN(1.0, sb / alpha);
            }
            STBlendPixel(buffer, destX, destY, sr, sg, sb, alpha);
        }
    }
}

static void STRasterizeTextOntoBitmap(MarkupText *text,
                                      STBitmapBuffer *buffer,
                                      NSSize canvasSize) {
    if (!text || text.text.length == 0) {
        return;
    }
    STRasterizeDrawingOntoBitmap([text decoratedBounds], buffer, canvasSize, ^(CGFloat unflippedHeight) {
        [text drawAtScale:1.0 unflippedHeight:unflippedHeight decorationsOnly:NO];
    });
}

static void STRasterizeArrowOntoBitmap(MarkupStroke *stroke,
                                       STBitmapBuffer *buffer,
                                       NSSize canvasSize) {
    STRasterizeDrawingOntoBitmap([stroke bounds], buffer, canvasSize, ^(CGFloat unflippedHeight) {
        [stroke drawArrowWithUnflippedHeight:unflippedHeight];
    });
}

static NSBitmapImageRep *STBitmapImageRepCrop(NSBitmapImageRep *source, NSRect clipRect, NSSize canvasSize) {
    // The row copy below needs whole bytes per pixel; a 1-bit image used to be copied 8x past
    // each row (#46). The result is always chunky 8-bit RGB(A).
    source = STRGBABitmapFromRep(source);
    if (!source) {
        return nil;
    }

    NSInteger srcWidth = source.pixelsWide;
    NSInteger srcHeight = source.pixelsHigh;
    if (srcWidth <= 0 || srcHeight <= 0) {
        return nil;
    }

    CGFloat maxClipWidth = canvasSize.width > 0.0 ? canvasSize.width : (CGFloat)srcWidth;
    CGFloat maxClipHeight = canvasSize.height > 0.0 ? canvasSize.height : (CGFloat)srcHeight;

    CGFloat originXFloat = MAX(0.0, MIN(clipRect.origin.x, maxClipWidth));
    CGFloat originYTopFloat = MAX(0.0, MIN(clipRect.origin.y, maxClipHeight));
    CGFloat widthFloat = MAX(1.0, MIN(clipRect.size.width, maxClipWidth - originXFloat));
    CGFloat heightFloat = MAX(1.0, MIN(clipRect.size.height, maxClipHeight - originYTopFloat));

    NSInteger originX = (NSInteger)floor(originXFloat);
    NSInteger originYTop = (NSInteger)floor(originYTopFloat);
    NSInteger clipWidth = (NSInteger)ceil(widthFloat);
    NSInteger clipHeight = (NSInteger)ceil(heightFloat);

    if (originX >= srcWidth || originYTop >= srcHeight) {
        return nil;
    }

    if (originX + clipWidth > srcWidth) {
        clipWidth = srcWidth - originX;
    }
    if (originYTop + clipHeight > srcHeight) {
        clipHeight = srcHeight - originYTop;
    }

    if (clipWidth <= 0 || clipHeight <= 0) {
        return nil;
    }

    NSBitmapImageRep *dest = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                     pixelsWide:clipWidth
                                                                     pixelsHigh:clipHeight
                                                                  bitsPerSample:source.bitsPerSample
                                                                samplesPerPixel:source.samplesPerPixel
                                                                       hasAlpha:source.hasAlpha
                                                                       isPlanar:source.isPlanar
                                                                 colorSpaceName:source.colorSpaceName ?: NSDeviceRGBColorSpace
                                                                   bitmapFormat:source.bitmapFormat
                                                                    bytesPerRow:0
                                                                   bitsPerPixel:source.bitsPerPixel];
    if (!dest) {
        return nil;
    }

    unsigned char *srcData = source.bitmapData;
    unsigned char *dstData = dest.bitmapData;
    if (!srcData || !dstData) {
        return dest;
    }

    NSInteger bytesPerPixel = source.bitsPerPixel / 8;
    NSInteger srcBytesPerRow = source.bytesPerRow;
    NSInteger dstBytesPerRow = dest.bytesPerRow;

    NSInteger topStartRow = originYTop;
    if (topStartRow < 0) {
        topStartRow = 0;
    }

    for (NSInteger row = 0; row < clipHeight; row++) {
        unsigned char *srcRow = srcData + ((topStartRow + row) * srcBytesPerRow) + originX * bytesPerPixel;
        unsigned char *dstRow = dstData + (row * dstBytesPerRow);
        memcpy(dstRow, srcRow, (size_t)clipWidth * (size_t)bytesPerPixel);
    }

    [dest setSize:NSMakeSize((CGFloat)clipWidth, (CGFloat)clipHeight)];
    return dest;
}
@interface ScreenshotCanvasView () <NSTextViewDelegate>
@property (nonatomic, strong) NSMutableArray<MarkupStroke *> *strokes;
@property (nonatomic, strong, nullable) MarkupStroke *currentStroke;
@property (nonatomic, strong) NSMutableArray<MarkupText *> *texts;
@property (nonatomic, strong, nullable) MarkupText *currentTextEntry;
@property (nonatomic, strong, nullable) NSTextView *activeTextView;
@property (nonatomic, assign) BOOL isCreatingTextBox;
@property (nonatomic, assign) BOOL isResizingTextBox;
@property (nonatomic, assign) BOOL isDraggingPointer;
@property (nonatomic, assign) BOOL textClickOnlyCommitted;
// Typing has its own undo history while a box is open, so Ctrl+Z undoes keystrokes, not canvas
// actions, and nothing from a closed editor is left on the canvas's undo stack (#28).
@property (nonatomic, strong, nullable) NSUndoManager *textEditingUndoManager;
// The annotation under the pointer, outlined on hover (#29).
@property (nonatomic, weak, nullable) id hoverAnnotation;
// Object selection (#25): strokes and texts picked with the Select tool.
@property (nonatomic, strong) NSMutableArray<id> *selectedAnnotations;
@property (nonatomic, assign) BOOL isMovingAnnotations;
@property (nonatomic, assign) BOOL annotationsMoved;
@property (nonatomic, assign) NSPoint annotationMoveLastPoint;
@property (nonatomic, strong, nullable) NSDictionary *annotationMoveSnapshot;
@property (nonatomic, assign) BOOL activeTextOverflowsImage;
@property (nonatomic, assign) NSRect pendingTextRect;
@property (nonatomic, assign) NSPoint textDragStartImagePoint;
@property (nonatomic, assign) NSPoint textResizeStartImagePoint;
@property (nonatomic, assign) NSSize textResizeStartBoxSize;
@property (nonatomic, strong, nullable) MarkupText *editingTextSnapshot;
@property (nonatomic, assign) NSInteger editingTextIndex;
@property (nonatomic, assign) BOOL hasSelectionRect;
@property (nonatomic, assign) NSRect selectionRect;
@property (nonatomic, assign) BOOL isUpdatingFit;
@property (nonatomic, assign) BOOL isCreatingSelection;
@property (nonatomic, assign) BOOL isResizingSelection;
@property (nonatomic, assign) BOOL isMovingSelection;
@property (nonatomic, assign) NSPoint selectionDragStartImagePoint;
@property (nonatomic, assign) NSRect selectionStartRect;
@property (nonatomic, strong, nullable) NSTimer *selectionDashTimer;
@property (nonatomic, assign) CGFloat selectionDashPhase;
@property (nonatomic, assign) NSTrackingRectTag cursorTrackingTag;
@property (nonatomic, assign) BOOL mouseInsideCanvas;
@end

@implementation ScreenshotCanvasView

- (BOOL)acceptsFirstResponder {
    // GNUstep's NSWindow makes the clicked view first responder before -mouseDown:. Taking it
    // from an open text editor would commit the text before the click can reach the handle.
    return self.activeTextView == nil;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    if (action == @selector(undo:)) {
        NSUndoManager *undo = [self undoManager];
        return (undo && [undo canUndo]);
    }
    if (action == @selector(redo:)) {
        NSUndoManager *undo = [self undoManager];
        return (undo && [undo canRedo]);
    }
    if (action == @selector(cropImage:)) {
        return self.hasSelectionRect;
    }
    return [super validateMenuItem:menuItem];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _strokes = [[NSMutableArray alloc] init];
        _texts = [[NSMutableArray alloc] init];
        _penColor = [NSColor redColor];
        _highlighterColor = [NSColor yellowColor];
        _textColor = [_penColor copy];
        _textFont = [NSFont systemFontOfSize:24.0f];
        _penLineWidth = 3.0;
        _highlighterLineWidth = 12.0;
        _zoomScale = 1.0;
        _fitToWindow = YES;
        _isCreatingTextBox = NO;
        _isResizingTextBox = NO;
        _pendingTextRect = NSZeroRect;
        _editingTextIndex = NSNotFound;
        _selectionDashPhase = 0.0f;
        _cursorTrackingTag = 0;
        _mouseInsideCanvas = NO;
        [self setPostsFrameChangedNotifications:YES];
    }
    return self;
}

- (NSUndoManager *)undoManager {
    NSWindow *window = self.window;
    NSUndoManager *manager = window.undoManager;
    if (!manager && [window.delegate respondsToSelector:@selector(activeUndoManager)]) {
        manager = [window.delegate performSelector:@selector(activeUndoManager)];
    }
    return manager ?: [super undoManager];
}

- (void)insertStroke:(MarkupStroke *)stroke
             atIndex:(NSUInteger)index
    registeringUndo:(BOOL)registerUndo
          actionName:(NSString *)actionName {
    if (!stroke) {
        return;
    }
    if (index > self.strokes.count) {
        index = self.strokes.count;
    }
    [self.strokes insertObject:stroke atIndex:index];
    [self setNeedsDisplay:YES];

    if (registerUndo) {
        NSUndoManager *undo = [self undoManager];
        [[undo prepareWithInvocationTarget:self] removeStrokeAtIndex:index registeringUndo:YES actionName:actionName];
        if (actionName.length > 0) {
            [undo setActionName:actionName];
        }
    }
}

- (void)removeStrokeAtIndex:(NSUInteger)index
           registeringUndo:(BOOL)registerUndo
                actionName:(NSString *)actionName {
    if (index >= self.strokes.count) {
        return;
    }
    MarkupStroke *stroke = self.strokes[index];
    [self.strokes removeObjectAtIndex:index];
    [self setNeedsDisplay:YES];

    if (registerUndo) {
        NSUndoManager *undo = [self undoManager];
        [[undo prepareWithInvocationTarget:self] insertStroke:stroke atIndex:index registeringUndo:YES actionName:actionName];
        if (actionName.length > 0) {
            [undo setActionName:actionName];
        }
    }
}

- (void)insertText:(MarkupText *)text
            atIndex:(NSUInteger)index
   registeringUndo:(BOOL)registerUndo
         actionName:(NSString *)actionName {
    if (!text) {
        return;
    }
    if (index > self.texts.count) {
        index = self.texts.count;
    }
    [self.texts insertObject:text atIndex:index];
    [self setNeedsDisplay:YES];

    if (registerUndo) {
        NSUndoManager *undo = [self undoManager];
        [[undo prepareWithInvocationTarget:self] removeTextAtIndex:index registeringUndo:YES actionName:actionName];
        if (actionName.length > 0) {
            [undo setActionName:actionName];
        }
    }
}

- (void)removeTextAtIndex:(NSUInteger)index
          registeringUndo:(BOOL)registerUndo
               actionName:(NSString *)actionName {
    if (index >= self.texts.count) {
        return;
    }
    MarkupText *text = self.texts[index];
    [self.texts removeObjectAtIndex:index];
    [self setNeedsDisplay:YES];

    if (registerUndo) {
        NSUndoManager *undo = [self undoManager];
        [[undo prepareWithInvocationTarget:self] insertText:text atIndex:index registeringUndo:YES actionName:actionName];
        if (actionName.length > 0) {
            [undo setActionName:actionName];
        }
    }
}

- (void)applyTextSnapshot:(MarkupText *)snapshot
                   toIndex:(NSUInteger)index
           registeringUndo:(BOOL)registerUndo {
    if (!snapshot || index >= self.texts.count) {
        return;
    }

    MarkupText *target = self.texts[index];
    MarkupText *previous = [target copy];

    target.text = snapshot.text;
    target.color = snapshot.color;
    target.font = snapshot.font;
    target.origin = snapshot.origin;
    target.boxSize = snapshot.boxSize;
    target.widthIsFixed = snapshot.widthIsFixed;
    target.style = snapshot.style;
    target.alignment = snapshot.alignment;
    target.hasPointer = snapshot.hasPointer;
    target.pointerTarget = snapshot.pointerTarget;
    [target updateMeasuredSize];

    [self setNeedsDisplay:YES];

    if (registerUndo) {
        NSUndoManager *undo = [self undoManager];
        [[undo prepareWithInvocationTarget:self] applyTextSnapshot:previous toIndex:index registeringUndo:YES];
        [undo setActionName:@"Edit Text"];
    }
}

- (NSDictionary *)snapshotCanvasState {
    NSMutableArray<MarkupStroke *> *strokeCopies = [[NSMutableArray alloc] initWithCapacity:self.strokes.count];
    for (MarkupStroke *stroke in self.strokes) {
        [strokeCopies addObject:[stroke copy]];
    }

    NSMutableArray<MarkupText *> *textCopies = [[NSMutableArray alloc] initWithCapacity:self.texts.count];
    for (MarkupText *text in self.texts) {
        [textCopies addObject:[text copy]];
    }

    id imageObject = self.image ? [self.image copy] : [NSNull null];
    NSValue *selectionValue = [NSValue valueWithRect:self.selectionRect];

    return @{ @"image": imageObject,
              @"strokes": strokeCopies,
              @"texts": textCopies,
              @"hasSelection": @(self.hasSelectionRect),
              @"selectionRect": selectionValue };
}

- (void)restoreCanvasStateFromSnapshot:(NSDictionary *)snapshot
                       registeringUndo:(BOOL)registerUndo {
    if (!snapshot) {
        return;
    }

    NSDictionary *currentSnapshot = registerUndo ? [self snapshotCanvasState] : nil;

    id imageObject = snapshot[@"image"];
    if ([imageObject isKindOfClass:[NSImage class]]) {
        self.image = [imageObject copy];
    } else {
        self.image = nil;
    }

    self.strokes = [snapshot[@"strokes"] mutableCopy] ?: [[NSMutableArray alloc] init];
    self.texts = [snapshot[@"texts"] mutableCopy] ?: [[NSMutableArray alloc] init];
    [self clearAnnotationSelection];

    BOOL hasSelection = [snapshot[@"hasSelection"] boolValue];
    NSRect selection = hasSelection ? [snapshot[@"selectionRect"] rectValue] : NSZeroRect;
    self.hasSelectionRect = hasSelection;
    self.selectionRect = selection;

    [self cancelActiveTextEntry];
    self.currentStroke = nil;

    [self updateFrameSize];
    [self updateForEnclosingBoundsChange];
    [self updateSelectionAnimationState];
    [self setNeedsDisplay:YES];
    [self updateCursorForActiveTool];
    [[NSNotificationCenter defaultCenter] postNotificationName:ScreenshotCanvasViewDidRestoreStateNotification object:self];

    if (registerUndo && currentSnapshot) {
        NSUndoManager *undo = [self undoManager];
        [[undo prepareWithInvocationTarget:self] restoreCanvasStateFromSnapshot:currentSnapshot registeringUndo:YES];
    }
}
static NSBitmapImageRep *STBitmapImageRepFromImage(NSImage *image, NSSize size) {
    if (!image) {
        return nil;
    }

    NSBitmapImageRep *source = nil;
    for (NSImageRep *rep in [image representations]) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            source = (NSBitmapImageRep *)rep;
            break;
        }
    }

    if (!source) {
        NSData *tiff = [image TIFFRepresentation];
        if (tiff) {
            NSImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
            if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
                source = (NSBitmapImageRep *)rep;
            }
        }
    }

    if (!source) {
        return nil;
    }

    return STBitmapImageRepCrop(source, NSMakeRect(0.0, 0.0, size.width, size.height), size);
}

- (void)dealloc {
    if (self.hostScrollView) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSViewBoundsDidChangeNotification
                                                      object:self.hostScrollView.contentView];
    }
    if (self.activeTextView) {
        self.activeTextView.delegate = nil;
    }
    [self.selectionDashTimer invalidate];
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self updateCursorForActiveTool];
}

- (void)setHostScrollView:(NSScrollView *)hostScrollView {
    if (_hostScrollView == hostScrollView) {
        return;
    }

    if (_hostScrollView) {
        NSClipView *clipView = _hostScrollView.contentView;
        [clipView setPostsBoundsChangedNotifications:NO];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSViewBoundsDidChangeNotification
                                                      object:clipView];
    }

    _hostScrollView = hostScrollView;
    [self applyScrollerPolicy];

    if (_hostScrollView) {
        NSClipView *clipView = _hostScrollView.contentView;
        [clipView setPostsBoundsChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(clipViewBoundsDidChange:)
                                                     name:NSViewBoundsDidChangeNotification
                                                 object:clipView];
    }
}

- (void)setActiveTool:(ScreenshotCanvasTool)activeTool {
    if (_activeTool == activeTool) {
        return;
    }
    if (_activeTool == ScreenshotCanvasToolText) {
        [self commitActiveTextIfNeeded];
    }
    _activeTool = activeTool;
    self.hoverAnnotation = nil;
    if (_activeTool != ScreenshotCanvasToolSelect) {
        [self clearAnnotationSelection];
    }
    if (_activeTool != ScreenshotCanvasToolText) {
        [self commitActiveTextIfNeeded];
        self.isCreatingTextBox = NO;
        self.isResizingTextBox = NO;
        self.pendingTextRect = NSZeroRect;
    }
    [self updateSelectionAnimationState];
    [self setNeedsDisplay:YES];
    [self updateCursorForActiveTool];
}

- (NSCursor *)cursorForActiveTool {
    switch (self.activeTool) {
        case ScreenshotCanvasToolHighlighter:
            return [[self class] tintedCursorForToolKey:@"highlighter" color:self.highlighterColor fallback:[NSCursor crosshairCursor]];
        case ScreenshotCanvasToolPen:
            return [[self class] tintedCursorForToolKey:@"pen" color:self.penColor fallback:[NSCursor crosshairCursor]];
        case ScreenshotCanvasToolEraser: {
            NSCursor *cursor = [[self class] customCursorForToolKey:@"eraser" fallback:[NSCursor pointingHandCursor]];
            return cursor ?: [NSCursor pointingHandCursor];
        }
        case ScreenshotCanvasToolSelect:
        case ScreenshotCanvasToolArrow:
            return [NSCursor crosshairCursor];
        case ScreenshotCanvasToolText:
            // Over empty canvas a click creates a box; text under the pointer shows an I-beam (#29).
            return [NSCursor crosshairCursor];
        default:
            return [NSCursor arrowCursor];
    }
}

- (BOOL)shouldShowCanvasCursor {
    if (![self hasImage]) {
        return NO;
    }
    if (!self.window) {
        return self.mouseInsideCanvas;
    }
    if (!self.window.isKeyWindow) {
        return NO;
    }
    return self.mouseInsideCanvas;
}

- (NSCursor *)cursorForTestingWithMouseInside:(BOOL)mouseInside {
    BOOL previous = self.mouseInsideCanvas;
    self.mouseInsideCanvas = mouseInside;
    NSCursor *cursor = [self shouldShowCanvasCursor] ? [self cursorForActiveTool] : [NSCursor arrowCursor];
    self.mouseInsideCanvas = previous;
    return cursor;
}

- (void)updateCursorForActiveTool {
    if (self.window) {
        [self.window invalidateCursorRectsForView:self];
        [self updateMouseInsideFromWindowLocation];
    }
    NSCursor *cursor = [self shouldShowCanvasCursor] ? [self cursorForActiveTool] : [NSCursor arrowCursor];
    [cursor set];
    NSString *toolName = STCursorToolName(self.activeTool);
    BOOL isArrow = (cursor == [NSCursor arrowCursor]);
    ScreenshotCursorLog(@"[CursorSet] tool=%@ mouseInside=%d cursor=%@ pointer=%p isArrow=%d",
                        toolName,
                        self.mouseInsideCanvas,
                        NSStringFromClass([cursor class]),
                        cursor,
                        isArrow);
}

- (void)resetCursorRects {
    [super resetCursorRects];
    BOOL currentlyInside = self.mouseInsideCanvas;
    if (self.window) {
        currentlyInside = [self updateMouseInsideFromWindowLocation];
    }
    self.mouseInsideCanvas = currentlyInside;
    if (![self hasImage]) {
        [self addCursorRect:self.bounds cursor:[NSCursor arrowCursor]];
        if (self.cursorTrackingTag != 0) {
            [self removeTrackingRect:self.cursorTrackingTag];
            self.cursorTrackingTag = 0;
        }
        self.mouseInsideCanvas = NO;
        return;
    }
    NSCursor *rectCursor = [self shouldShowCanvasCursor] ? [self cursorForActiveTool] : [NSCursor arrowCursor];
    [self addCursorRect:self.bounds cursor:rectCursor];
    if (self.cursorTrackingTag != 0) {
        [self removeTrackingRect:self.cursorTrackingTag];
        self.cursorTrackingTag = 0;
    }
    self.cursorTrackingTag = [self addTrackingRect:self.bounds
                                             owner:self
                                          userData:NULL
                                      assumeInside:self.mouseInsideCanvas];
    NSString *toolName = STCursorToolName(self.activeTool);
    BOOL isArrow = (rectCursor == [NSCursor arrowCursor]);
    ScreenshotCursorLog(@"[CursorRectApplied] tool=%@ bounds=%@ trackingTag=%ld assumeInside=%d cursor=%@ isArrow=%d",
                        toolName,
                        NSStringFromRect(self.bounds),
                        (long)self.cursorTrackingTag,
                        self.mouseInsideCanvas,
                        NSStringFromClass([rectCursor class]),
                        isArrow);
}

- (BOOL)updateMouseInsideFromWindowLocation {
    if (!self.window) {
        return self.mouseInsideCanvas;
    }
    NSPoint mouseLocation = [self.window mouseLocationOutsideOfEventStream];
    NSPoint localPoint = [self convertPoint:mouseLocation fromView:nil];
    BOOL inside = NSMouseInRect(localPoint, self.bounds, self.isFlipped);
    if (inside != self.mouseInsideCanvas) {
        ScreenshotCursorLog(@"[CursorEvent] event=mouseLocation point=%@ bounds=%@ flipped=%d inside=%d",
                            NSStringFromPoint(localPoint),
                            NSStringFromRect(self.bounds),
                            self.isFlipped,
                            inside);
        self.mouseInsideCanvas = inside;
    }
    return inside;
}

- (void)mouseEntered:(NSEvent *)event {
    [super mouseEntered:event];
    self.mouseInsideCanvas = YES;
    ScreenshotCursorLog(@"[CursorEvent] event=mouseEntered point=%@", NSStringFromPoint(event.locationInWindow));
    [self updateCursorForActiveTool];
}

- (void)mouseExited:(NSEvent *)event {
    [super mouseExited:event];
    self.mouseInsideCanvas = NO;
    [self setHoverAnnotationIfChanged:nil];
    ScreenshotCursorLog(@"[CursorEvent] event=mouseExited point=%@", NSStringFromPoint(event.locationInWindow));
    [self updateCursorForActiveTool];
}

- (void)mouseMoved:(NSEvent *)event {
    [super mouseMoved:event];
    if (!self.window) {
        return;
    }
    NSPoint localPoint = [self convertPoint:event.locationInWindow fromView:nil];
    BOOL inside = NSMouseInRect(localPoint, self.bounds, self.isFlipped);
    if (inside != self.mouseInsideCanvas) {
        self.mouseInsideCanvas = inside;
        ScreenshotCursorLog(@"[CursorEvent] event=mouseMoved point=%@ inside=%d",
                            NSStringFromPoint(event.locationInWindow),
                            inside);
        [self updateCursorForActiveTool];
    }
    [self updateHoverAtViewPoint:localPoint];
}

/// What the pointer is over, and the cursor that says what a click there will do (#29).
- (void)updateHoverAtViewPoint:(NSPoint)viewPoint {
    if (!self.image || !self.mouseInsideCanvas) {
        [self setHoverAnnotationIfChanged:nil];
        return;
    }
    NSPoint imagePoint = NSMakePoint(viewPoint.x / self.zoomScale, viewPoint.y / self.zoomScale);
    id hover = nil;
    if (self.activeTool == ScreenshotCanvasToolText || self.activeTool == ScreenshotCanvasToolSelect) {
        hover = [self annotationAtImagePoint:imagePoint];
        if (self.activeTool == ScreenshotCanvasToolText && ![hover isKindOfClass:[MarkupText class]]) {
            hover = nil;
        }
        if (hover == self.currentTextEntry && self.activeTextView) {
            hover = nil;
        }
    }
    [self setHoverAnnotationIfChanged:hover];
    if ([self shouldShowCanvasCursor]) {
        NSCursor *cursor = [self contextCursorAtViewPoint:viewPoint hover:hover];
        if (cursor && [NSCursor currentCursor] != cursor) {
            [cursor set];
        }
    }
}

- (void)setHoverAnnotationIfChanged:(nullable id)hover {
    if (self.hoverAnnotation == hover) {
        return;
    }
    self.hoverAnnotation = hover;
    [self setNeedsDisplay:YES];
}

- (nullable NSCursor *)contextCursorAtViewPoint:(NSPoint)viewPoint hover:(nullable id)hover {
    switch (self.activeTool) {
        case ScreenshotCanvasToolText:
            if (self.isDraggingPointer) {
                return [NSCursor closedHandCursor];
            }
            if (self.activeTextView && NSPointInRect(viewPoint, NSInsetRect([self activePointerHandleRectInView], -3.0, -3.0))) {
                return [NSCursor openHandCursor];
            }
            if (self.activeTextView && NSPointInRect(viewPoint, [self activeTextHandleHitRectInView])) {
                return [NSCursor resizeLeftRightCursor];
            }
            if (self.activeTextView && NSPointInRect(viewPoint, [self activeTextGuideRectInView])) {
                return [NSCursor IBeamCursor];
            }
            return hover ? [NSCursor IBeamCursor] : [NSCursor crosshairCursor];
        case ScreenshotCanvasToolSelect:
            if (self.isMovingAnnotations) {
                return [NSCursor closedHandCursor];
            }
            return hover ? [NSCursor openHandCursor] : [NSCursor crosshairCursor];
        default:
            return nil;
    }
}

/// The drawn handle is small; give it a few extra points to hit at any zoom.
- (NSRect)activeTextHandleHitRectInView {
    NSRect handle = [self activeTextHandleRectInView];
    return NSIsEmptyRect(handle) ? handle : NSInsetRect(handle, -3.0, -3.0);
}

- (void)drawHoverOutline {
    id hover = self.hoverAnnotation;
    if (!hover || [self isAnnotationSelected:hover] || (hover == self.currentTextEntry && self.activeTextView)) {
        return;
    }
    if ([self.texts indexOfObjectIdenticalTo:hover] == NSNotFound &&
        [self.strokes indexOfObjectIdenticalTo:hover] == NSNotFound) {
        return;
    }
    NSRect viewRect = NSInsetRect([self viewRectForImageRect:[self boundsOfAnnotation:hover]], -4.0, -4.0);
    NSBezierPath *path = [NSBezierPath bezierPathWithRect:viewRect];
    CGFloat dashPattern[] = {3.0f, 3.0f};
    [path setLineWidth:1.0f];
    [path setLineDash:dashPattern count:2 phase:0.0];
    [[[NSColor keyboardFocusIndicatorColor] ?: [NSColor grayColor] colorWithAlphaComponent:0.55f] setStroke];
    [path stroke];
}

- (void)refreshCursor {
    [self updateCursorForActiveTool];
}

+ (NSCursor *)tintedCursorForToolKey:(NSString *)toolKey color:(NSColor *)color fallback:(NSCursor *)fallback {
    if (toolKey.length == 0) {
        ScreenshotCursorLog(@"[CursorTintRequest] tool=<empty> status=missing-tool");
        return fallback;
    }
    NSColor *resolvedColor = color ?: [NSColor whiteColor];
    NSColor *deviceColor = [resolvedColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: resolvedColor;
    CGFloat tr = 0.0, tg = 0.0, tb = 0.0, ta = 1.0;
    [deviceColor getRed:&tr green:&tg blue:&tb alpha:&ta];
    ScreenshotCursorLog(@"[CursorTintRequest] tool=%@ color=(%.3f,%.3f,%.3f,%.3f)",
                        toolKey,
                        tr,
                        tg,
                        tb,
                        ta);
    CGFloat cursorScale = STCursorScaleFactor();
    NSString *cacheKey = [NSString stringWithFormat:@"%@:%0.4f:%0.4f:%0.4f:%0.4f:%0.3f", toolKey, tr, tg, tb, ta, cursorScale];
    static NSMutableDictionary<NSString *, NSCursor *> *tintedCache = nil;
    if (!tintedCache) {
        tintedCache = [[NSMutableDictionary alloc] init];
    }
    NSCursor *cached = tintedCache[cacheKey];
    if (cached) {
        ScreenshotCursorLog(@"[CursorConstructed] tool=%@ source=tinted-cache hotspot=(%.2f,%.2f)",
                            toolKey,
                            cached.hotSpot.x,
                            cached.hotSpot.y);
        return cached;
    }

    NSDictionary *info = [self cursorMetadata][toolKey];
    if (!info) {
        ScreenshotCursorLog(@"[CursorTintRequest] tool=%@ status=missing-metadata", toolKey);
        return fallback;
    }
    NSString *file1x = info[@"file1x"] ?: info[@"file"];
    NSNumber *sizeNumber = info[@"size1x"];
    NSValue *hotspotValue = info[@"hotspot"];
    NSPoint hotspot = hotspotValue ? hotspotValue.pointValue : NSMakePoint(0.0, 0.0);

    NSBitmapImageRep *source = [self cursorBitmapNamed:file1x];
    if (!source) {
        ScreenshotCursorLog(@"[CursorTintRequest] tool=%@ status=missing-source name=%@",
                            toolKey,
                            file1x ?: @"<nil>");
        return fallback;
    }
    NSBitmapImageRep *mutableRep = [source copy];
    if (!mutableRep) {
        mutableRep = source;
    }

    STBitmapBuffer buffer;
    if (!STPrepareBitmapBuffer(mutableRep, &buffer)) {
        ScreenshotCursorLog(@"[CursorTintRequest] tool=%@ status=buffer-prepare-failed", toolKey);
        return fallback;
    }
    if (!buffer.data || buffer.bytesPerPixel < 3) {
        ScreenshotCursorLog(@"[CursorTintRequest] tool=%@ status=invalid-buffer", toolKey);
        return fallback;
    }

    NSArray<NSColor *> *templateColors = [self templateColorsForToolKey:toolKey];
    NSMutableArray<NSColor *> *deviceTemplates = [[NSMutableArray alloc] initWithCapacity:templateColors.count];
    for (NSColor *templateColor in templateColors) {
        NSColor *deviceTemplate = [templateColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: templateColor;
        [deviceTemplates addObject:deviceTemplate];
    }

    NSUInteger templateCount = deviceTemplates.count;
    typedef struct {
        double r;
        double g;
        double b;
        double a;
    } STColorComponents;
    STColorComponents *templateComponents = NULL;
    if (templateCount > 0) {
        templateComponents = calloc(templateCount, sizeof(STColorComponents));
        if (!templateComponents) {
            ScreenshotCursorLog(@"[CursorTintRequest] tool=%@ status=no-memory", toolKey);
            return fallback;
        }
        for (NSUInteger idx = 0; idx < templateCount; idx++) {
            NSColor *templateColor = deviceTemplates[idx];
            double cr = 0.0, cg = 0.0, cb = 0.0, ca = 1.0;
            [templateColor getRed:&cr green:&cg blue:&cb alpha:&ca];
            templateComponents[idx].r = cr;
            templateComponents[idx].g = cg;
            templateComponents[idx].b = cb;
            templateComponents[idx].a = ca;
        }
    }

    const double tolerance = 0.35;
    const double toleranceSquared = tolerance * tolerance;

    for (NSInteger y = 0; y < buffer.height; y++) {
        unsigned char *row = buffer.data + (y * buffer.bytesPerRow);
        for (NSInteger x = 0; x < buffer.width; x++) {
            unsigned char *pixel = row + (x * buffer.bytesPerPixel);
            double alpha = buffer.hasAlpha ? (pixel[buffer.aIndex] / 255.0) : 1.0;
            if (alpha <= 0.05) {
                continue;
            }
            double pr = pixel[buffer.rIndex] / 255.0;
            double pg = pixel[buffer.gIndex] / 255.0;
            double pb = pixel[buffer.bIndex] / 255.0;

            if (templateCount == 0) {
                pixel[buffer.rIndex] = STRoundToByte(tr);
                pixel[buffer.gIndex] = STRoundToByte(tg);
                pixel[buffer.bIndex] = STRoundToByte(tb);
                continue;
            }

            NSInteger bestIndex = -1;
            double bestDistance = toleranceSquared;
            for (NSUInteger idx = 0; idx < templateCount; idx++) {
                STColorComponents comps = templateComponents[idx];
                double dr = pr - comps.r;
                double dg = pg - comps.g;
                double db = pb - comps.b;
                double distance = (dr * dr) + (dg * dg) + (db * db);
                if (distance <= bestDistance) {
                    bestDistance = distance;
                    bestIndex = (NSInteger)idx;
                }
            }

            if (bestIndex >= 0) {
                STColorComponents comps = templateComponents[bestIndex];
                double newR = STClamp01(tr + (pr - comps.r));
                double newG = STClamp01(tg + (pg - comps.g));
                double newB = STClamp01(tb + (pb - comps.b));
                pixel[buffer.rIndex] = STRoundToByte(newR);
                pixel[buffer.gIndex] = STRoundToByte(newG);
                pixel[buffer.bIndex] = STRoundToByte(newB);
            }
        }
    }

    if (templateComponents) {
        free(templateComponents);
    }

    NSBitmapImageRep *scaledRep = STScaledCursorRep(mutableRep, cursorScale);
    CGFloat baseSize = sizeNumber ? sizeNumber.doubleValue : mutableRep.size.width;
    if (baseSize <= 0.0) {
        baseSize = mutableRep.pixelsWide > 0 ? mutableRep.pixelsWide : 24.0;
    }
    CGFloat sizeInPoints = baseSize * cursorScale;
    if (sizeInPoints <= 0.0) {
        sizeInPoints = scaledRep.pixelsWide > 0 ? scaledRep.pixelsWide : 24.0;
    }
    NSSize targetSize = NSMakeSize(sizeInPoints, sizeInPoints);
    hotspot = NSMakePoint(hotspot.x * cursorScale, hotspot.y * cursorScale);
    [scaledRep setSize:targetSize];
    NSImage *cursorImage = [[NSImage alloc] initWithSize:targetSize];
    [cursorImage addRepresentation:scaledRep];

    NSCursor *cursor = [[NSCursor alloc] initWithImage:cursorImage hotSpot:hotspot];
    if (cursor) {
        ScreenshotCursorLog(@"[CursorConstructed] tool=%@ hotspot=(%.2f,%.2f) size=%@ tinted=YES reps=%lu",
                            toolKey,
                            hotspot.x,
                            hotspot.y,
                            NSStringFromSize(targetSize),
                            (unsigned long)cursorImage.representations.count);
        tintedCache[cacheKey] = cursor;
        return cursor;
    }
    ScreenshotCursorLog(@"[CursorTintRequest] tool=%@ status=cursor-init-failed", toolKey);
    return fallback ?: [NSCursor arrowCursor];
}

+ (NSBitmapImageRep *)cursorBitmapNamed:(NSString *)name {
    if (name.length == 0) {
        ScreenshotCursorLog(@"[CursorAssetLoad] name=<empty> status=missing-name");
        return nil;
    }
    static NSMutableDictionary<NSString *, NSBitmapImageRep *> *bitmapCache = nil;
    if (!bitmapCache) {
        bitmapCache = [[NSMutableDictionary alloc] init];
    }
    NSBitmapImageRep *cached = bitmapCache[name];
    if (cached) {
        return [cached copy];
    }

    NSBundle *bundle = [NSBundle mainBundle];
    NSString *path = [bundle pathForResource:name ofType:@"tiff" inDirectory:@"Cursors"];
    if (!path) {
        path = [bundle pathForResource:name ofType:@"png" inDirectory:@"Cursors"];
    }
    if (!path) {
        path = [bundle pathForResource:name ofType:@"tiff"];
    }
    if (!path) {
        path = [bundle pathForResource:name ofType:@"png"];
    }
    ScreenshotCursorLog(@"[CursorAssetLoad] name=%@ path=%@ exists=%d",
                        name,
                        path ?: @"<not-found>",
                        path ? 1 : 0);
    if (!path) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        ScreenshotCursorLog(@"[CursorAssetLoad] name=%@ status=no-data", name);
        return nil;
    }

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:data];
    if (!rep) {
        NSArray *candidates = [NSBitmapImageRep imageRepsWithData:data];
        for (NSImageRep *candidate in candidates) {
            if ([candidate isKindOfClass:[NSBitmapImageRep class]]) {
                rep = [(NSBitmapImageRep *)candidate copy];
                break;
            }
        }
    }
    if (!rep) {
        NSImage *image = [[NSImage alloc] initWithData:data];
        if (image) {
            ScreenshotCursorLog(@"[CursorAssetLoad] name=%@ status=convertedFromImage size=%@", name, NSStringFromSize(image.size));
            NSRect rect = NSMakeRect(0.0, 0.0, image.size.width, image.size.height);
            [image lockFocus];
            rep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:rect];
            [image unlockFocus];
        }
    }
    if (!rep) {
        ScreenshotCursorLog(@"[CursorAssetLoad] name=%@ status=rep-failed", name);
        return nil;
    }

    NSBitmapImageRep *standardized = STCreateDeviceRGBBitmapFromRep(rep);
    if (!standardized) {
        ScreenshotCursorLog(@"[CursorAssetLoad] name=%@ status=standardize-failed", name);
        return nil;
    }
    ScreenshotCursorLog(@"[CursorAssetLoad] name=%@ status=ok width=%ld height=%ld bpp=%ld",
                        name,
                        (long)standardized.pixelsWide,
                        (long)standardized.pixelsHigh,
                        (long)standardized.bitsPerPixel);
    bitmapCache[name] = standardized;
    return [standardized copy];
}

+ (NSArray<NSColor *> *)templateColorsForToolKey:(NSString *)toolKey {
    static NSDictionary<NSString *, NSArray<NSColor *> *> *templates = nil;
    if (!templates) {
        templates = @{
            @"pen": @[[NSColor colorWithCalibratedRed:33.0/255.0 green:150.0/255.0 blue:243.0/255.0 alpha:1.0],
                       [NSColor colorWithCalibratedRed:25.0/255.0 green:118.0/255.0 blue:210.0/255.0 alpha:1.0]],
            @"highlighter": @[[NSColor colorWithCalibratedRed:255.0/255.0 green:235.0/255.0 blue:59.0/255.0 alpha:1.0]]
        };
    }
    NSArray<NSColor *> *colors = templates[toolKey];
    return colors ?: @[];
}



+ (NSCursor *)customCursorForToolKey:(NSString *)toolKey fallback:(NSCursor *)fallback {
    if (toolKey.length == 0) {
        STCursorWarnFallback(@"<empty>", @"missing tool key");
        return fallback;
    }
    static NSMutableDictionary<NSString *, NSCursor *> *cache = nil;
    if (!cache) {
        cache = [[NSMutableDictionary alloc] init];
    }
    CGFloat cursorScale = STCursorScaleFactor();
    NSString *cacheKey = [NSString stringWithFormat:@"%@:%0.3f", toolKey, cursorScale];
    NSCursor *cached = cache[cacheKey];
    if (cached) {
        ScreenshotCursorLog(@"[CursorConstructed] tool=%@ source=cache hotspot=(%.2f,%.2f)",
                            toolKey,
                            cached.hotSpot.x,
                            cached.hotSpot.y);
        return cached;
    }

    NSDictionary *info = [self cursorMetadata][toolKey];
    if (!info) {
        STCursorWarnFallback(toolKey, @"metadata missing");
        return fallback;
    }

    NSString *file1x = info[@"file1x"];
    NSNumber *size1xNumber = info[@"size1x"];
    NSValue *hotspotValue = info[@"hotspot"];
    NSPoint hotspot = hotspotValue ? hotspotValue.pointValue : NSMakePoint(0.0, 0.0);

    NSBitmapImageRep *rep = [self cursorBitmapNamed:file1x];
    if (!rep) {
        STCursorWarnFallback(toolKey, @"bitmap missing");
        return fallback;
    }

    NSBitmapImageRep *scaledRep = STScaledCursorRep(rep, cursorScale);
    CGFloat baseSize = size1xNumber ? size1xNumber.doubleValue : rep.size.width;
    if (baseSize <= 0.0) {
        baseSize = rep.pixelsWide > 0 ? rep.pixelsWide : 24.0;
    }
    CGFloat sizeInPoints = baseSize * cursorScale;
    if (sizeInPoints <= 0.0) {
        sizeInPoints = scaledRep.pixelsWide > 0 ? scaledRep.pixelsWide : 24.0;
    }
    NSSize targetSize = NSMakeSize(sizeInPoints, sizeInPoints);
    hotspot = NSMakePoint(hotspot.x * cursorScale, hotspot.y * cursorScale);
    [scaledRep setSize:targetSize];
    NSImage *cursorImage = [[NSImage alloc] initWithSize:targetSize];
    [cursorImage addRepresentation:scaledRep];

    NSCursor *cursor = [[NSCursor alloc] initWithImage:cursorImage hotSpot:hotspot];
    if (cursor) {
        ScreenshotCursorLog(@"[CursorConstructed] tool=%@ hotspot=(%.2f,%.2f) size=%@ reps=%lu",
                            toolKey,
                            hotspot.x,
                            hotspot.y,
                            NSStringFromSize(targetSize),
                            (unsigned long)cursorImage.representations.count);
        cache[cacheKey] = cursor;
        return cursor;
    }
    STCursorWarnFallback(toolKey, @"cursor init failed");
    return fallback ?: [NSCursor arrowCursor];
}



+ (NSImage *)loadCursorImageNamed:(NSString *)name {
    if (name.length == 0) {
        return nil;
    }
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *path = [bundle pathForResource:name ofType:@"tiff" inDirectory:@"Cursors"];
    if (!path) {
        path = [bundle pathForResource:name ofType:@"png" inDirectory:@"Cursors"];
    }
    if (!path) {
        path = [bundle pathForResource:name ofType:@"tiff"];
    }
    if (!path) {
        path = [bundle pathForResource:name ofType:@"png"];
    }
    if (!path) {
        return nil;
    }
    return [[NSImage alloc] initWithContentsOfFile:path];
}

+ (NSDictionary<NSString *, NSDictionary *> *)cursorMetadata {
    static NSDictionary<NSString *, NSDictionary *> *metadata = nil;
    static BOOL attemptedLoad = NO;
    if (!metadata && !attemptedLoad) {
        attemptedLoad = YES;
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *path = [bundle pathForResource:@"markup-cursors.metadata" ofType:@"json" inDirectory:@"Cursors"];
        if (!path) {
            path = [bundle pathForResource:@"markup-cursors.metadata" ofType:@"json"];
        }
        if (path) {
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (data) {
                NSError *error = nil;
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                if ([json isKindOfClass:[NSArray class]]) {
                    NSMutableDictionary<NSString *, NSMutableDictionary *> *mutable = [[NSMutableDictionary alloc] init];
                    for (NSDictionary *entry in (NSArray *)json) {
                        NSString *tool = entry[@"tool"];
                        NSNumber *size = entry[@"size"];
                        NSString *file = entry[@"file"];
                        NSArray *hotspotArray = entry[@"hotspot"];
                        if (![tool isKindOfClass:[NSString class]] || ![size isKindOfClass:[NSNumber class]] || ![file isKindOfClass:[NSString class]]) {
                            continue;
                        }

                        NSMutableDictionary *toolInfo = mutable[tool];
                        if (!toolInfo) {
                            toolInfo = [[NSMutableDictionary alloc] init];
                            mutable[tool] = toolInfo;
                        }

                        if ([size integerValue] <= 32 || !toolInfo[@"file1x"]) {
                            toolInfo[@"file1x"] = file;
                            if ([hotspotArray isKindOfClass:[NSArray class]] && hotspotArray.count >= 2) {
                                CGFloat x = [hotspotArray[0] doubleValue];
                                CGFloat y = [hotspotArray[1] doubleValue];
                                toolInfo[@"hotspot"] = [NSValue valueWithPoint:NSMakePoint(x, y)];
                            }
                            toolInfo[@"size1x"] = size;
                        }
                    }

                    metadata = [[NSDictionary alloc] initWithDictionary:mutable copyItems:YES];
                }
            }
        }
        if (!metadata) {
            metadata = @{};
        }
    }
    return metadata ?: @{};
}


- (void)clipViewBoundsDidChange:(NSNotification *)notification {
    [self updateForEnclosingBoundsChange];
}

- (void)loadImage:(NSImage *)image {
    [[self undoManager] removeAllActions];
    [self cancelActiveTextEntry];
    self.editingTextSnapshot = nil;
    self.image = image;
    [self clearMarkup];
    [self clearSelection];
    [self clearAnnotationSelection];
    _zoomScale = 1.0;
    self.fitToWindow = YES;
    [self updateForEnclosingBoundsChange];
    [self setNeedsDisplay:YES];
}

- (void)clearMarkup {
    [self cancelActiveTextEntry];
    [self.strokes removeAllObjects];
    [self.texts removeAllObjects];
    self.currentStroke = nil;
    self.pendingTextRect = NSZeroRect;
    self.isCreatingTextBox = NO;
    self.isResizingTextBox = NO;
    [self clearSelection];
    [self setNeedsDisplay:YES];
}

- (BOOL)hasImage {
    return (self.image != nil);
}

- (void)setZoomScale:(CGFloat)zoomScale {
    CGFloat clamped = MAX(0.05, MIN(zoomScale, 8.0));
    if (fabs(clamped - _zoomScale) < 0.0001) {
        return;
    }
    _zoomScale = clamped;
    [self updateFrameSize];
    [self setNeedsDisplay:YES];
    [self updateActiveTextViewFrame];
}

- (void)setFitToWindow:(BOOL)fitToWindow {
    if (_fitToWindow == fitToWindow) {
        return;
    }
    _fitToWindow = fitToWindow;
    [self applyScrollerPolicy];
    if (fitToWindow) {
        [self updateForEnclosingBoundsChange];
    }
}

/// Fit never needs a scroller: the canvas fits by construction. Left auto-hiding, GNUstep's
/// scrollers could flip on and off for good during a window resize (NSScrollView -tile <->
/// -reflectScrolledClipView:) until the stack overflowed (#49). Fixed zooms get them back.
- (void)applyScrollerPolicy {
    NSScrollView *scrollView = self.hostScrollView;
    if (!scrollView) {
        return;
    }
    if (self.fitToWindow) {
        [scrollView setAutohidesScrollers:NO];
        [scrollView setHasVerticalScroller:NO];
        [scrollView setHasHorizontalScroller:NO];
    } else {
        [scrollView setAutohidesScrollers:YES];
        [scrollView reflectScrolledClipView:scrollView.contentView];
    }
}

- (void)setTextColor:(NSColor *)textColor {
    NSColor *resolved = textColor ?: [NSColor whiteColor];
    if ([_textColor isEqual:resolved]) {
        return;
    }
    _textColor = [resolved copy];
    if (self.currentTextEntry) {
        self.currentTextEntry.color = _textColor;
    }
    [self updateActiveTextViewFrame];
    [self setNeedsDisplay:YES];
}

- (void)setTextStyle:(MarkupTextStyle)textStyle {
    if (_textStyle == textStyle) {
        return;
    }
    _textStyle = textStyle;
    if (self.currentTextEntry) {
        self.currentTextEntry.style = textStyle;
    }
    [self updateActiveTextViewFrame];
    [self setNeedsDisplay:YES];
}

- (void)setTextSizePreset:(STTextSizePreset)textSizePreset {
    if (_textSizePreset == textSizePreset) {
        return;
    }
    _textSizePreset = textSizePreset;
    if (self.currentTextEntry) {
        self.currentTextEntry.font = [self effectiveTextFont];
    }
    [self updateActiveTextViewFrame];
    [self setNeedsDisplay:YES];
}

- (NSFont *)effectiveTextFont {
    NSFont *font = self.textFont ?: [NSFont systemFontOfSize:24.0f];
    CGFloat presetSize = self.image ? STTextPointSizeForPreset(self.textSizePreset, self.image.size) : 0.0;
    if (presetSize <= 0.0) {
        return font;
    }
    return [NSFont fontWithName:font.fontName size:presetSize] ?: [NSFont systemFontOfSize:presetSize];
}

- (void)setTextAlignment:(NSTextAlignment)textAlignment {
    if (_textAlignment == textAlignment) {
        return;
    }
    _textAlignment = textAlignment;
    if (self.currentTextEntry) {
        self.currentTextEntry.alignment = textAlignment;
    }
    [self updateActiveTextViewFrame];
    [self setNeedsDisplay:YES];
}

- (void)setTextFont:(NSFont *)textFont {
    NSFont *resolved = textFont ?: [NSFont systemFontOfSize:24.0f];
    if ([_textFont isEqual:resolved]) {
        return;
    }
    _textFont = resolved;
    if (self.currentTextEntry) {
        self.currentTextEntry.font = [self effectiveTextFont];
    }
    [self updateActiveTextViewFrame];
    [self setNeedsDisplay:YES];
}

- (void)cancelActiveTextEntry {
    if (!self.activeTextView) {
        return;
    }
    self.activeTextView.delegate = nil;
    [self.activeTextView removeFromSuperview];
    self.activeTextView = nil;
    [self.textEditingUndoManager removeAllActions];
    self.textEditingUndoManager = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:ScreenshotCanvasViewDidEndTextEditingNotification object:self];
    self.activeTextOverflowsImage = NO;
    NSWindow *window = self.window;
    if (window && (window.firstResponder == nil || window.firstResponder == window)) {
        [window makeFirstResponder:self];
    }
    if (self.editingTextIndex != NSNotFound && self.editingTextSnapshot) {
        NSUInteger insertIndex = (NSUInteger)MIN(MAX(0, self.editingTextIndex), (NSInteger)self.texts.count);
        [self.texts insertObject:self.editingTextSnapshot atIndex:insertIndex];
    }
    self.currentTextEntry = nil;
    self.editingTextSnapshot = nil;
    self.editingTextIndex = NSNotFound;
    self.isResizingTextBox = NO;
    self.pendingTextRect = NSZeroRect;
    [self updateSelectionAnimationState];
}

- (void)commitActiveTextIfNeeded {
    if (!self.activeTextView || !self.currentTextEntry) {
        return;
    }

    NSString *submitted = self.activeTextView.string ?: @"";
    NSString *trimmed = [submitted stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    MarkupText *entry = self.currentTextEntry;
    NSInteger editingIndex = self.editingTextIndex;
    NSUInteger existingIndex = [self.texts indexOfObjectIdenticalTo:entry];

    if (trimmed.length > 0) {
        entry.text = submitted;
        [entry fitToTextWithinCanvasSize:self.image.size];

        if (editingIndex != NSNotFound) {
            NSUInteger insertIndex = (NSUInteger)MIN(MAX(0, editingIndex), (NSInteger)self.texts.count);
            [self.texts insertObject:entry atIndex:insertIndex];
            [self setNeedsDisplay:YES];
            if (self.editingTextSnapshot) {
                NSUndoManager *undo = [self undoManager];
                [[undo prepareWithInvocationTarget:self] applyTextSnapshot:self.editingTextSnapshot toIndex:insertIndex registeringUndo:YES];
                [undo setActionName:@"Edit Text"];
            }
        } else if (existingIndex == NSNotFound) {
            [self insertText:entry atIndex:self.texts.count registeringUndo:YES actionName:@"Insert Text"];
        } else {
            [self setNeedsDisplay:YES];
            if (self.editingTextSnapshot) {
                NSUndoManager *undo = [self undoManager];
                [[undo prepareWithInvocationTarget:self] applyTextSnapshot:self.editingTextSnapshot toIndex:existingIndex registeringUndo:YES];
                [undo setActionName:@"Edit Text"];
            }
        }
    }

    if (trimmed.length == 0) {
        // Emptying a label and committing deletes it; make that an undoable step (#30).
        if (editingIndex != NSNotFound && self.editingTextSnapshot) {
            NSUInteger insertIndex = (NSUInteger)MIN(MAX(0, editingIndex), (NSInteger)self.texts.count);
            NSUndoManager *undo = [self undoManager];
            [[undo prepareWithInvocationTarget:self] insertText:[self.editingTextSnapshot copy]
                                                        atIndex:insertIndex
                                                registeringUndo:YES
                                                     actionName:@"Delete Text"];
            [undo setActionName:@"Delete Text"];
        } else if (existingIndex != NSNotFound) {
            [self removeTextAtIndex:existingIndex registeringUndo:YES actionName:@"Delete Text"];
        }
    }

    self.editingTextIndex = NSNotFound;
    self.editingTextSnapshot = nil;
    [self cancelActiveTextEntry];
}

#pragma mark - Annotation selection

- (NSArray *)selectedAnnotationObjects {
    // Drop anything that has left the canvas since it was selected (eraser, undo).
    NSMutableArray *live = [[NSMutableArray alloc] init];
    for (id annotation in self.selectedAnnotations) {
        if ([self.strokes indexOfObjectIdenticalTo:annotation] != NSNotFound ||
            [self.texts indexOfObjectIdenticalTo:annotation] != NSNotFound) {
            [live addObject:annotation];
        }
    }
    return live;
}

- (BOOL)hasAnnotationSelection {
    return [self selectedAnnotationObjects].count > 0;
}

- (void)clearAnnotationSelection {
    if (self.selectedAnnotations.count == 0) {
        return;
    }
    [self.selectedAnnotations removeAllObjects];
    [self setNeedsDisplay:YES];
}

- (BOOL)isAnnotationSelected:(id)annotation {
    // Messaging nil would return 0, which is not NSNotFound.
    if (!annotation || self.selectedAnnotations.count == 0) {
        return NO;
    }
    return [self.selectedAnnotations indexOfObjectIdenticalTo:annotation] != NSNotFound;
}

- (void)selectAnnotation:(id)annotation extending:(BOOL)extending {
    if (!self.selectedAnnotations) {
        self.selectedAnnotations = [[NSMutableArray alloc] init];
    }
    if (extending) {
        NSUInteger index = [self.selectedAnnotations indexOfObjectIdenticalTo:annotation];
        if (index != NSNotFound) {
            [self.selectedAnnotations removeObjectAtIndex:index];
        } else {
            [self.selectedAnnotations addObject:annotation];
        }
    } else if (![self isAnnotationSelected:annotation]) {
        [self.selectedAnnotations removeAllObjects];
        [self.selectedAnnotations addObject:annotation];
    }
    [self setNeedsDisplay:YES];
}

/// The topmost annotation under a point: texts draw above strokes, later ones above earlier.
- (nullable id)annotationAtImagePoint:(NSPoint)point {
    for (MarkupText *text in [self.texts reverseObjectEnumerator]) {
        if ([text containsPoint:point]) {
            return text;
        }
    }
    CGFloat tolerance = 4.0 / MAX(self.zoomScale, 0.05);
    for (MarkupStroke *stroke in [self.strokes reverseObjectEnumerator]) {
        if ([stroke containsPoint:point tolerance:tolerance]) {
            return stroke;
        }
    }
    return nil;
}

- (NSRect)boundsOfAnnotation:(id)annotation {
    if ([annotation isKindOfClass:[MarkupText class]]) {
        return [(MarkupText *)annotation decoratedBounds];
    }
    if ([annotation isKindOfClass:[MarkupStroke class]]) {
        return [(MarkupStroke *)annotation bounds];
    }
    return NSZeroRect;
}

- (void)translateAnnotations:(NSArray *)annotations byDelta:(NSPoint)delta {
    NSPoint offset = NSMakePoint(-delta.x, -delta.y);
    for (id annotation in annotations) {
        if ([annotation respondsToSelector:@selector(translateByOffset:)]) {
            [annotation translateByOffset:offset];
        }
    }
}

// Moves and deletes only touch annotations, so their undo snapshots leave the image alone (a full
// canvas restore also resizes and recentres the window).
- (NSDictionary *)annotationSnapshot {
    NSMutableArray *strokes = [[NSMutableArray alloc] initWithCapacity:self.strokes.count];
    for (MarkupStroke *stroke in self.strokes) {
        [strokes addObject:[stroke copy]];
    }
    NSMutableArray *texts = [[NSMutableArray alloc] initWithCapacity:self.texts.count];
    for (MarkupText *text in self.texts) {
        [texts addObject:[text copy]];
    }
    return @{ @"strokes": strokes, @"texts": texts };
}

- (void)restoreAnnotationSnapshot:(NSDictionary *)snapshot {
    NSDictionary *current = [self annotationSnapshot];
    [self cancelActiveTextEntry];
    self.strokes = [snapshot[@"strokes"] mutableCopy] ?: [[NSMutableArray alloc] init];
    self.texts = [snapshot[@"texts"] mutableCopy] ?: [[NSMutableArray alloc] init];
    [self clearAnnotationSelection];
    [self setNeedsDisplay:YES];
    NSUndoManager *undo = [self undoManager];
    [[undo prepareWithInvocationTarget:self] restoreAnnotationSnapshot:current];
}

- (void)registerAnnotationUndoWithSnapshot:(NSDictionary *)snapshot actionName:(NSString *)actionName {
    NSUndoManager *undo = [self undoManager];
    if (!undo || !snapshot) {
        return;
    }
    [[undo prepareWithInvocationTarget:self] restoreAnnotationSnapshot:snapshot];
    [undo setActionName:actionName];
}

- (BOOL)nudgeSelectedAnnotationsBy:(NSPoint)delta {
    NSArray *selected = [self selectedAnnotationObjects];
    if (selected.count == 0) {
        return NO;
    }
    NSDictionary *before = [self annotationSnapshot];
    [self translateAnnotations:selected byDelta:delta];
    [self registerAnnotationUndoWithSnapshot:before actionName:@"Move"];
    [self setNeedsDisplay:YES];
    return YES;
}

- (BOOL)deleteSelectedAnnotations {
    NSArray *selected = [self selectedAnnotationObjects];
    if (selected.count == 0) {
        return NO;
    }
    NSDictionary *before = [self annotationSnapshot];
    for (id annotation in selected) {
        NSUInteger index = [self.strokes indexOfObjectIdenticalTo:annotation];
        if (index != NSNotFound) {
            [self.strokes removeObjectAtIndex:index];
        }
        index = [self.texts indexOfObjectIdenticalTo:annotation];
        if (index != NSNotFound) {
            [self.texts removeObjectAtIndex:index];
        }
    }
    [self clearAnnotationSelection];
    [self registerAnnotationUndoWithSnapshot:before actionName:(selected.count == 1 ? @"Delete" : @"Delete Annotations")];
    [self setNeedsDisplay:YES];
    return YES;
}

- (BOOL)editSelectedText {
    NSArray *selected = [self selectedAnnotationObjects];
    if (selected.count != 1 || ![selected.firstObject isKindOfClass:[MarkupText class]]) {
        return NO;
    }
    MarkupText *text = selected.firstObject;
    [self clearAnnotationSelection];
    [self beginTextEntryWithImageRect:[text bounds] existingText:text];
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    NSString *characters = event.charactersIgnoringModifiers;
    unichar key = characters.length > 0 ? [characters characterAtIndex:0] : 0;
    BOOL shift = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    CGFloat step = shift ? 10.0 : 1.0;

    switch (key) {
        case NSUpArrowFunctionKey:
            if ([self nudgeSelectedAnnotationsBy:NSMakePoint(0.0, -step)]) return;
            break;
        case NSDownArrowFunctionKey:
            if ([self nudgeSelectedAnnotationsBy:NSMakePoint(0.0, step)]) return;
            break;
        case NSLeftArrowFunctionKey:
            if ([self nudgeSelectedAnnotationsBy:NSMakePoint(-step, 0.0)]) return;
            break;
        case NSRightArrowFunctionKey:
            if ([self nudgeSelectedAnnotationsBy:NSMakePoint(step, 0.0)]) return;
            break;
        case NSDeleteCharacter:
        case NSBackspaceCharacter:
        case NSDeleteFunctionKey:
            if ([self deleteSelectedAnnotations]) return;
            break;
        case NSCarriageReturnCharacter:
        case NSEnterCharacter:
        case NSNewlineCharacter:
            if ([self editSelectedText]) return;
            break;
        case 0x1b:
            if ([self hasAnnotationSelection]) {
                [self clearAnnotationSelection];
                return;
            }
            break;
        default:
            if ([self requestToolForShortcutEvent:event]) {
                return;
            }
            break;
    }
    [super keyDown:event];
}

/// S, H, P, A, T and E switch tools. They only reach the canvas when no text is being edited, and
/// only plain letters count, so menu shortcuts and typing are unaffected.
- (BOOL)requestToolForShortcutEvent:(NSEvent *)event {
    NSEventModifierFlags flags = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl |
                                                        NSEventModifierFlagOption | NSEventModifierFlagShift);
    NSString *characters = event.charactersIgnoringModifiers.lowercaseString;
    if (flags != 0 || characters.length != 1) {
        return NO;
    }
    NSDictionary<NSString *, NSNumber *> *shortcuts = @{
        @"s": @(ScreenshotCanvasToolSelect),
        @"h": @(ScreenshotCanvasToolHighlighter),
        @"p": @(ScreenshotCanvasToolPen),
        @"t": @(ScreenshotCanvasToolText),
        @"e": @(ScreenshotCanvasToolEraser),
        @"a": @(ScreenshotCanvasToolArrow),
    };
    NSNumber *tool = shortcuts[characters];
    if (!tool) {
        return NO;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:ScreenshotCanvasViewRequestsToolNotification
                                                        object:self
                                                      userInfo:@{ ScreenshotCanvasViewToolKey: tool }];
    return YES;
}

- (void)drawAnnotationSelection {
    NSArray *selected = [self selectedAnnotationObjects];
    if (selected.count == 0) {
        return;
    }
    NSColor *outline = [NSColor keyboardFocusIndicatorColor] ?: [NSColor grayColor];
    CGFloat dashPattern[] = {5.0f, 3.0f};
    for (id annotation in selected) {
        NSRect viewRect = NSInsetRect([self viewRectForImageRect:[self boundsOfAnnotation:annotation]], -4.0, -4.0);
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:viewRect];
        [path setLineWidth:1.0f];
        [path setLineDash:dashPattern count:2 phase:0.0];
        [outline setStroke];
        [path stroke];
        // Corner marks show it's an object that can be moved, without suggesting resize handles.
        [[outline colorWithAlphaComponent:0.9f] setFill];
        CGFloat mark = 5.0f;
        for (NSInteger corner = 0; corner < 4; corner++) {
            CGFloat x = (corner % 2 == 0) ? NSMinX(viewRect) : NSMaxX(viewRect);
            CGFloat y = (corner < 2) ? NSMinY(viewRect) : NSMaxY(viewRect);
            NSRectFill(NSMakeRect(x - mark * 0.5, y - mark * 0.5, mark, mark));
        }
    }
}

- (void)clearSelection {
    self.hasSelectionRect = NO;
    self.isCreatingSelection = NO;
    self.isMovingSelection = NO;
    self.isResizingSelection = NO;
    self.selectionRect = NSZeroRect;
    [self setNeedsDisplay:YES];
    [self updateSelectionAnimationState];
}

- (BOOL)hasSelection {
    return self.hasSelectionRect;
}

- (void)startSelectionDashAnimation {
    if (self.selectionDashTimer) {
        return;
    }
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.12
                                             target:self
                                           selector:@selector(selectionDashTimerFired:)
                                           userInfo:nil
                                            repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.selectionDashTimer = timer;
}

- (void)stopSelectionDashAnimation {
    [self.selectionDashTimer invalidate];
    self.selectionDashTimer = nil;
}

- (void)selectionDashTimerFired:(NSTimer *)timer {
    self.selectionDashPhase += 1.0f;
    if (self.selectionDashPhase >= 8.0f) {
        self.selectionDashPhase -= 8.0f;
    }
    [self setNeedsDisplay:YES];
}

- (void)updateSelectionAnimationState {
    if (self.hasSelectionRect || self.isCreatingSelection || self.isMovingSelection ||
        self.isResizingSelection || self.activeTextView || self.isCreatingTextBox || self.isResizingTextBox) {
        [self startSelectionDashAnimation];
    } else {
        [self stopSelectionDashAnimation];
        self.selectionDashPhase = 0.0f;
    }
}

- (NSPoint)viewPointForImagePoint:(NSPoint)imagePoint {
    return NSMakePoint(imagePoint.x * self.zoomScale, imagePoint.y * self.zoomScale);
}

- (NSFont *)scaledFontForEditingWithBaseFont:(NSFont *)baseFont {
    NSFont *font = baseFont ?: self.textFont ?: [NSFont systemFontOfSize:24.0f];
    CGFloat size = font.pointSize * self.zoomScale;
    NSFont *scaled = [NSFont fontWithName:font.fontName size:MAX(1.0, size)];
    if (!scaled) {
        scaled = [NSFont systemFontOfSize:MAX(1.0, size)];
    }
    return scaled;
}

- (NSRect)viewRectForImageRect:(NSRect)imageRect {
    return NSMakeRect(imageRect.origin.x * self.zoomScale,
                      imageRect.origin.y * self.zoomScale,
                      imageRect.size.width * self.zoomScale,
                      imageRect.size.height * self.zoomScale);
}

- (NSRect)normalizedImageRectFromStart:(NSPoint)start end:(NSPoint)end {
    CGFloat minX = MIN(start.x, end.x);
    CGFloat minY = MIN(start.y, end.y);
    CGFloat width = MAX(fabs(end.x - start.x), 1.0f);
    CGFloat height = MAX(fabs(end.y - start.y), 1.0f);
    return NSMakeRect(minX, minY, width, height);
}

- (NSRect)clampedImageRect:(NSRect)rect {
    if (!self.image) {
        return rect;
    }
    NSSize imageSize = self.image.size;
    CGFloat originX = MAX(0.0f, MIN(rect.origin.x, imageSize.width));
    CGFloat originY = MAX(0.0f, MIN(rect.origin.y, imageSize.height));
    CGFloat maxWidth = MAX(0.0f, imageSize.width - originX);
    CGFloat maxHeight = MAX(0.0f, imageSize.height - originY);
    CGFloat width = MAX(0.0f, MIN(rect.size.width, maxWidth));
    CGFloat height = MAX(0.0f, MIN(rect.size.height, maxHeight));
    return NSMakeRect(originX, originY, width, height);
}

- (NSRect)integralSelectionRect {
    if (!self.image || !self.hasSelectionRect) {
        return NSZeroRect;
    }
    NSRect clamped = [self clampedImageRect:self.selectionRect];
    if (clamped.size.width <= 0.5f || clamped.size.height <= 0.5f) {
        return NSZeroRect;
    }
    CGFloat originX = floor(clamped.origin.x);
    CGFloat originY = floor(clamped.origin.y);
    CGFloat maxX = ceil(NSMaxX(clamped));
    CGFloat maxY = ceil(NSMaxY(clamped));
    maxX = MIN(maxX, self.image.size.width);
    maxY = MIN(maxY, self.image.size.height);
    return NSMakeRect(originX,
                      originY,
                      MAX(1.0f, maxX - originX),
                      MAX(1.0f, maxY - originY));
}

- (MarkupText *)textOverlayContainingImagePoint:(NSPoint)point {
    NSEnumerator<MarkupText *> *enumerator = [self.texts reverseObjectEnumerator];
    for (MarkupText *text in enumerator) {
        if ([text containsPoint:point]) {
            return text;
        }
    }
    return nil;
}

- (void)updateActiveTextViewFrame {
    if (!self.activeTextView || !self.currentTextEntry) {
        return;
    }

    MarkupText *entry = self.currentTextEntry;
    BOOL fits = self.image ? [entry fitToTextWithinCanvasSize:self.image.size] : YES;
    self.activeTextOverflowsImage = !fits;

    NSRect frame = [self viewRectForImageRect:entry.bounds];
    [self.activeTextView setFrame:frame];
    [self.activeTextView setMaxSize:NSMakeSize(frame.size.width, FLT_MAX)];

    NSTextContainer *container = self.activeTextView.textContainer;
    if (container) {
        [container setContainerSize:NSMakeSize(frame.size.width, FLT_MAX)];
        [container setWidthTracksTextView:YES];
    }

    NSFont *editingFont = entry.font ?: self.textFont;
    [self.activeTextView setFont:[self scaledFontForEditingWithBaseFont:editingFont]];
    NSColor *editingColor = [entry glyphColor];
    [self.activeTextView setAlignment:entry.alignment];
    [self.activeTextView setTextColor:editingColor];
    [self.activeTextView setInsertionPointColor:editingColor];
}

- (void)beginTextEntryWithImageRect:(NSRect)imageRect existingText:(MarkupText * _Nullable)existingText {
    [self beginTextEntryWithImageRect:imageRect existingText:existingText widthIsFixed:NO];
}

- (void)beginTextEntryWithImageRect:(NSRect)imageRect
                       existingText:(MarkupText * _Nullable)existingText
                       widthIsFixed:(BOOL)widthIsFixed {
    [self commitActiveTextIfNeeded];

    NSFont *baseFont = [self effectiveTextFont];
    NSColor *baseColor = self.textColor ?: [NSColor whiteColor];
    MarkupText *entry = existingText;
    NSInteger existingIndex = NSNotFound;
    if (!entry) {
        entry = [[MarkupText alloc] initWithText:@""
                                            font:baseFont
                                           color:baseColor
                                          origin:imageRect.origin
                                          boxSize:imageRect.size];
        entry.widthIsFixed = widthIsFixed;
        entry.style = self.textStyle;
        entry.alignment = self.textAlignment;
    } else {
        entry.origin = imageRect.origin;
        entry.boxSize = imageRect.size;
        existingIndex = (NSInteger)[self.texts indexOfObjectIdenticalTo:existingText];
        if (existingIndex != NSNotFound) {
            [self.texts removeObjectAtIndex:(NSUInteger)existingIndex];
        }
    }

    self.editingTextIndex = existingIndex;
    self.currentTextEntry = entry;
    if (existingText) {
        self.editingTextSnapshot = [existingText copy];
    } else {
        self.editingTextSnapshot = nil;
    }
    [self.currentTextEntry updateMeasuredSize];
    self.pendingTextRect = NSZeroRect;

    NSRect viewRect = [self viewRectForImageRect:imageRect];
    NSTextView *textView =
#if ST_ENABLE_GNUSTEP_WORKAROUNDS
        [[STTransparentTextView alloc] initWithFrame:viewRect];
#else
        [[NSTextView alloc] initWithFrame:viewRect];
#endif
    [textView setDelegate:self];
    [textView setRichText:NO];
    [textView setEditable:YES];
    [textView setImportsGraphics:NO];
    [textView setDrawsBackground:
#if ST_ENABLE_GNUSTEP_WORKAROUNDS
         NO
#else
         YES
#endif
    ];
#if ST_ENABLE_GNUSTEP_WORKAROUNDS
    [textView setBackgroundColor:[NSColor clearColor]];
#else
    NSColor *background = [NSColor textBackgroundColor] ?: [NSColor lightGrayColor];
    if ([background respondsToSelector:@selector(colorWithAlphaComponent:)]) {
        background = [background colorWithAlphaComponent:0.15f];
    }
    [textView setBackgroundColor:background];
#endif
    // No padding, so text sits at the box origin as it will once committed and exported.
    [[textView textContainer] setLineFragmentPadding:0.0];
    [textView setTextColor:[entry glyphColor]];
    [textView setFont:[self scaledFontForEditingWithBaseFont:entry.font]];
    [textView setInsertionPointColor:entry.color];
    [textView setHorizontallyResizable:NO];
    [textView setVerticallyResizable:YES];
    [textView setMaxSize:NSMakeSize(viewRect.size.width, FLT_MAX)];
    [textView setAutoresizingMask:NSViewNotSizable];
    textView.allowsUndo = YES;
    textView.string = entry.text ?: @"";

    NSTextContainer *container = textView.textContainer;
    if (container) {
        [container setWidthTracksTextView:YES];
        [container setContainerSize:NSMakeSize(viewRect.size.width, FLT_MAX)];
    }

    self.textEditingUndoManager = [[NSUndoManager alloc] init];
    [self addSubview:textView];
    self.activeTextView = textView;

    NSWindow *window = self.window;
    if (window) {
        [window makeFirstResponder:textView];
    }

    [self updateActiveTextViewFrame];
    [self setNeedsDisplay:YES]; // Redraw to hide the stored text while the live editor is visible.
    [self updateSelectionAnimationState];
    [[NSNotificationCenter defaultCenter] postNotificationName:ScreenshotCanvasViewDidBeginTextEditingNotification object:self];
}

- (nullable MarkupText *)activeTextEntry {
    return self.activeTextView ? self.currentTextEntry : nil;
}

#pragma mark - Project files (#32)

static NSString * const STProjectFormat = @"screenshottool-project";

static NSError *STProjectError(NSString *message) {
    return [NSError errorWithDomain:@"ScreenshotToolProject" code:1 userInfo:@{ NSLocalizedDescriptionKey: message }];
}

- (NSData *)projectDataWithError:(NSError **)error {
    [self commitActiveTextIfNeeded];
    if (!self.image) {
        if (error) *error = STProjectError(@"There is no image to save.");
        return nil;
    }
    // The original image, not the flattened one, so the annotations stay editable.
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[self.image TIFFRepresentation]];
    NSData *png = [rep representationUsingType:NSPNGFileType properties:@{}];
    if (png.length == 0) {
        if (error) *error = STProjectError(@"The image could not be encoded.");
        return nil;
    }
    NSMutableArray *strokes = [[NSMutableArray alloc] initWithCapacity:self.strokes.count];
    for (MarkupStroke *stroke in self.strokes) {
        [strokes addObject:[stroke projectRepresentation]];
    }
    NSMutableArray *texts = [[NSMutableArray alloc] initWithCapacity:self.texts.count];
    for (MarkupText *text in self.texts) {
        [texts addObject:[text projectRepresentation]];
    }
    NSDictionary *project = @{ @"format": STProjectFormat,
                               @"version": @1,
                               @"imageSize": @[@(self.image.size.width), @(self.image.size.height)],
                               @"image": [png base64EncodedStringWithOptions:0],
                               @"strokes": strokes,
                               @"texts": texts };
    return [NSJSONSerialization dataWithJSONObject:project options:NSJSONWritingPrettyPrinted error:error];
}

- (NSData *)annotationFingerprint {
    NSMutableArray *strokes = [[NSMutableArray alloc] initWithCapacity:self.strokes.count];
    for (MarkupStroke *stroke in self.strokes) {
        [strokes addObject:[stroke projectRepresentation]];
    }
    NSMutableArray *texts = [[NSMutableArray alloc] initWithCapacity:self.texts.count];
    for (MarkupText *text in self.texts) {
        [texts addObject:[text projectRepresentation]];
    }
    // A label being edited counts with what's typed so far.
    MarkupText *editing = [self activeTextEntry];
    if (editing && self.activeTextView) {
        NSMutableDictionary *live = [[editing projectRepresentation] mutableCopy];
        live[@"text"] = self.activeTextView.string ?: @"";
        [texts addObject:live];
    }
    NSSize size = self.image ? self.image.size : NSZeroSize;
    NSDictionary *state = @{ @"imageSize": @[@(size.width), @(size.height)], @"strokes": strokes, @"texts": texts };
    return [NSJSONSerialization dataWithJSONObject:state options:0 error:NULL] ?: [NSData data];
}

- (BOOL)loadProjectData:(NSData *)data error:(NSError **)error {
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    NSDictionary *project = [object isKindOfClass:[NSDictionary class]] ? object : nil;
    if (![project[@"format"] isEqual:STProjectFormat] || [project[@"version"] integerValue] < 1) {
        if (error) *error = STProjectError(@"This isn't a ScreenshotTool project.");
        return NO;
    }
    if ([project[@"version"] integerValue] > 1) {
        if (error) *error = STProjectError(@"This project was saved by a newer version of ScreenshotTool.");
        return NO;
    }
    NSString *base64 = [project[@"image"] isKindOfClass:[NSString class]] ? project[@"image"] : nil;
    NSData *png = base64 ? [[NSData alloc] initWithBase64EncodedString:base64 options:0] : nil;
    NSBitmapImageRep *rep = png ? [NSBitmapImageRep imageRepWithData:png] : nil;
    if (!rep || rep.pixelsWide <= 0 || rep.pixelsHigh <= 0) {
        if (error) *error = STProjectError(@"The project's image is missing or damaged.");
        return NO;
    }

    NSMutableArray<MarkupStroke *> *strokes = [[NSMutableArray alloc] init];
    for (NSDictionary *item in ([project[@"strokes"] isKindOfClass:[NSArray class]] ? project[@"strokes"] : @[])) {
        MarkupStroke *stroke = [MarkupStroke strokeWithProjectRepresentation:item];
        if (!stroke) {
            if (error) *error = STProjectError(@"The project contains a damaged drawing.");
            return NO;
        }
        [strokes addObject:stroke];
    }
    NSMutableArray<MarkupText *> *texts = [[NSMutableArray alloc] init];
    for (NSDictionary *item in ([project[@"texts"] isKindOfClass:[NSArray class]] ? project[@"texts"] : @[])) {
        MarkupText *text = [MarkupText textWithProjectRepresentation:item];
        if (!text) {
            if (error) *error = STProjectError(@"The project contains a damaged label.");
            return NO;
        }
        [texts addObject:text];
    }

    // One image pixel per point, as when opening an image file.
    NSSize size = NSMakeSize((CGFloat)rep.pixelsWide, (CGFloat)rep.pixelsHigh);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [rep setSize:size];
    [image addRepresentation:rep];
    [self loadImage:image];
    self.strokes = strokes;
    self.texts = texts;
    [self setNeedsDisplay:YES];
    return YES;
}

- (BOOL)toggleActiveTextPointer {
    MarkupText *entry = [self activeTextEntry];
    if (!entry) {
        return NO;
    }
    entry.hasPointer = !entry.hasPointer;
    if (entry.hasPointer && NSPointInRect(entry.pointerTarget, NSInsetRect([entry decoratedTextBounds], -4.0, -4.0))) {
        // Start the pointer below and to the left of the label, inside the image; drag its handle to aim it.
        NSRect box = [entry decoratedTextBounds];
        NSSize size = self.image ? self.image.size : NSMakeSize(NSMaxX(box) + 60.0, NSMaxY(box) + 60.0);
        NSPoint target = NSMakePoint(NSMinX(box) - 40.0, NSMaxY(box) + 50.0);
        if (target.y > size.height - 4.0) {
            target.y = NSMinY(box) - 50.0;
        }
        target.x = MAX(4.0, MIN(size.width - 4.0, target.x));
        target.y = MAX(4.0, MIN(size.height - 4.0, target.y));
        entry.pointerTarget = target;
    }
    [self setNeedsDisplay:YES];
    return YES;
}

- (NSRect)activePointerHandleRectInView {
    MarkupText *entry = [self activeTextEntry];
    if (!entry.hasPointer) {
        return NSZeroRect;
    }
    NSPoint target = [self viewPointForImagePoint:entry.pointerTarget];
    return NSMakeRect(target.x - 6.0, target.y - 6.0, 12.0, 12.0);
}

- (NSRect)activeTextRectInView {
    return self.activeTextView ? [self activeTextGuideRectInView] : NSZeroRect;
}

- (nullable NSUndoManager *)activeTextUndoManager {
    return self.activeTextView ? self.textEditingUndoManager : nil;
}

- (NSUndoManager *)undoManagerForTextView:(NSTextView *)textView {
    if (textView == self.activeTextView && self.textEditingUndoManager) {
        return self.textEditingUndoManager;
    }
    return [self undoManager];
}

#pragma mark - NSTextViewDelegate

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object != self.activeTextView || !self.currentTextEntry) {
        return;
    }
    self.currentTextEntry.text = self.activeTextView.string ?: @"";
    [self updateActiveTextViewFrame];
    [self setNeedsDisplay:YES];
}

- (void)textDidEndEditing:(NSNotification *)notification {
    if (notification.object != self.activeTextView) {
        return;
    }
    // Focus moving into the text bar's font field leaves the box open; the bar gives it back (#103).
    if ([self.textEditingCompanion isTakingTextFocus]) {
        return;
    }
    [self commitActiveTextIfNeeded];
}

- (BOOL)focusActiveTextView {
    if (!self.activeTextView || !self.window) {
        return NO;
    }
    return [self.window makeFirstResponder:self.activeTextView];
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (textView != self.activeTextView) {
        return NO;
    }
    // GNUstep binds Escape to complete: (DefaultKeyBindings.dict); Cocoa sends cancelOperation:.
    // Compare with sel_isEqual: libobjc2 can hand us a typed selector that isn't == the literal.
    // Return adds a line; Ctrl+Return (Cmd+Return on macOS) finishes, like clicking away or Escape.
    if (sel_isEqual(commandSelector, @selector(insertNewline:)) ||
        sel_isEqual(commandSelector, @selector(insertLineBreak:)) ||
        sel_isEqual(commandSelector, @selector(insertNewlineIgnoringFieldEditor:))) {
        NSEventModifierFlags flags = [[NSApp currentEvent] modifierFlags];
#if ST_ENABLE_GNUSTEP_WORKAROUNDS
        if ([textView isKindOfClass:[STTransparentTextView class]]) {
            flags |= [(STTransparentTextView *)textView handlingKeyModifierFlags];
        }
#endif
        if ((flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) != 0) {
            [self performSelector:@selector(commitActiveTextIfNeeded) withObject:nil afterDelay:0.0];
            return YES;
        }
        return NO;
    }
    if (sel_isEqual(commandSelector, @selector(cancelOperation:)) || sel_isEqual(commandSelector, @selector(complete:))) {
        // Commit after this key event: committing removes and releases the text view, which is
        // still running its own -keyDown: here.
        [self performSelector:@selector(commitActiveTextIfNeeded) withObject:nil afterDelay:0.0];
        return YES;
    }
    return NO;
}

- (void)updateFrameSize {
    if (!self.image) {
        return;
    }
    NSSize imageSize = self.image.size;
    CGFloat width = round(imageSize.width * self.zoomScale);
    CGFloat height = round(imageSize.height * self.zoomScale);
    if (self.fitToWindow) {
        // Never a fraction larger than the viewport (rounding 577.5 gave 578): Fit has to fit
        // without scrollers, which it turns off (see -applyScrollerPolicy, #49).
        NSSize available = [self fitViewportSize];
        if (available.width > 0.0 && available.height > 0.0) {
            width = MIN(width, floor(available.width));
            height = MIN(height, floor(available.height));
        }
    }
    NSSize targetSize = NSMakeSize(MAX(width, 1.0f), MAX(height, 1.0f));
    [self setFrameSize:targetSize];
    [self updateActiveTextViewFrame];
}

/// The space Fit fills: the scroll view's content size, measured as if no scrollers were shown.
/// Autohiding scrollers appear while a previous zoom overflows and would otherwise leave Fit a
/// few pixels short of 100%.
- (NSSize)fitViewportSize {
    if (!self.hostScrollView) {
        return NSZeroSize;
    }
    return [NSScrollView contentSizeForFrameSize:self.hostScrollView.frame.size
                           hasHorizontalScroller:NO
                             hasVerticalScroller:NO
                                      borderType:self.hostScrollView.borderType];
}

- (void)updateForEnclosingBoundsChange {
    if (!self.fitToWindow || !self.image || !self.hostScrollView || self.suspendsFitUpdates) {
        return;
    }
    // Resizing the canvas changes the clip view's bounds, which calls back in here.
    if (self.isUpdatingFit) {
        return;
    }
    self.isUpdatingFit = YES;
    [self fitToEnclosingBounds];
    self.isUpdatingFit = NO;
}

- (void)fitToEnclosingBounds {

    NSSize imageSize = self.image.size;
    if (imageSize.width <= 0.0 || imageSize.height <= 0.0) {
        return;
    }

    NSSize available = [self fitViewportSize];
    if (available.width <= 0.0 || available.height <= 0.0) {
        return;
    }

    // Fit only ever shrinks: upscaling a screenshot just blurs it.
    CGFloat newScale = MIN(available.width / imageSize.width, available.height / imageSize.height);
    newScale = MAX(0.05, MIN(newScale, 1.0));
    _zoomScale = newScale;
    [self updateFrameSize];
    [self setNeedsDisplay:YES];
    [self updateActiveTextViewFrame];
}

- (void)drawRect:(NSRect)dirtyRect {
    [STThemeCanvasBackgroundColor() setFill];
    NSRectFill(dirtyRect);

    if (!self.image) {
        return;
    }

    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform scaleBy:self.zoomScale];
    [transform concat];

    NSSize imageSize = self.image.size;
    NSRect imageRect = NSMakeRect(0.0, 0.0, imageSize.width, imageSize.height);
    [self.image drawInRect:imageRect
                  fromRect:NSZeroRect
                 operation:NSCompositeSourceOver
                  fraction:1.0
            respectFlipped:YES
                     hints:nil];

    for (MarkupStroke *stroke in self.strokes) {
        [stroke drawPath];
    }

    [self.currentStroke drawPath];

    [NSGraphicsContext restoreGraphicsState];

    // Text draws in view coordinates with a zoomed font so it matches the editing text view.
    BOOL isEditingExistingText = (self.activeTextView && self.currentTextEntry && [self.texts containsObject:self.currentTextEntry]);
    for (MarkupText *text in self.texts) {
        if (isEditingExistingText && text == self.currentTextEntry) {
            continue; // Hide stored text while editing to avoid double draw.
        }
        [text drawInCanvasAtScale:self.zoomScale];
    }
    if (self.currentTextEntry && !self.activeTextView) {
        [self.currentTextEntry drawInCanvasAtScale:self.zoomScale];
    }
    if (self.currentTextEntry && self.activeTextView) {
        [self.currentTextEntry drawAtScale:self.zoomScale unflippedHeight:0.0 decorationsOnly:YES];
    }

    if (self.activeTool == ScreenshotCanvasToolText || self.activeTextView) {
        [self drawTextGuides];
    }
    [self drawHoverOutline];
    [self drawAnnotationSelection];

    if (self.activeTool == ScreenshotCanvasToolSelect || self.hasSelectionRect || self.isCreatingSelection) {
        [self drawSelectionOverlay];
    }
}

- (void)drawTextGuides {
    NSColor *outline = [NSColor keyboardFocusIndicatorColor] ?: [NSColor grayColor];
    NSRect pointerHandle = [self activePointerHandleRectInView];
    if (!NSIsEmptyRect(pointerHandle)) {
        [[NSColor whiteColor] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:pointerHandle] fill];
        [outline setStroke];
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(pointerHandle, 1.0, 1.0)];
        [ring setLineWidth:2.0];
        [ring stroke];
    }
    CGFloat dashPattern[] = {6.0f, 4.0f};
    const NSInteger dashCount = 2;
    CGFloat phase = self.selectionDashPhase;

    if (!NSIsEmptyRect(self.pendingTextRect) && self.isCreatingTextBox) {
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:[self viewRectForImageRect:self.pendingTextRect]];
        [path setLineWidth:1.0f];
        [path setLineDash:dashPattern count:dashCount phase:phase];
        [outline setStroke];
        [path stroke];
    }

    if (self.activeTextView && self.currentTextEntry) {
        NSRect viewRect = [self activeTextGuideRectInView];
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:viewRect];
        [path setLineWidth:1.0f];
        [path setLineDash:dashPattern count:dashCount phase:phase];
        if (self.activeTextOverflowsImage) {
            outline = [NSColor colorWithDeviceRed:0.88 green:0.11 blue:0.14 alpha:1.0];
        }
        [outline setStroke];
        [path stroke];

        NSRect handle = [self activeTextHandleRectInView];
        [[outline colorWithAlphaComponent:0.8f] setFill];
        NSBezierPath *handlePath = [NSBezierPath bezierPathWithRect:handle];
        [handlePath fill];
    }
}

- (NSRect)activeTextGuideRectInView {
    if (!self.currentTextEntry) {
        return NSZeroRect;
    }
    // Outside the text and its outline/shadow/background, so the guide never sits on them.
    CGFloat outset = STTextGuideOutset + ([self.currentTextEntry decorationOutset] * self.zoomScale);
    return NSInsetRect([self viewRectForImageRect:self.currentTextEntry.bounds], -outset, -outset);
}

- (NSRect)activeTextHandleRectInView {
    NSRect guideRect = [self activeTextGuideRectInView];
    if (NSIsEmptyRect(guideRect)) {
        return NSZeroRect;
    }
    // Centred on the guide's corner so it covers the outline, not the text.
    return NSMakeRect(NSMaxX(guideRect) - (STSelectionHandleSize * 0.5),
                      NSMaxY(guideRect) - (STSelectionHandleSize * 0.5),
                      STSelectionHandleSize,
                      STSelectionHandleSize);
}

- (NSRect)selectionHandleRectInView {
    if (!self.hasSelectionRect) {
        return NSZeroRect;
    }
    NSRect viewRect = [self viewRectForImageRect:self.selectionRect];
    return NSMakeRect(NSMaxX(viewRect) - STSelectionHandleSize,
                      NSMaxY(viewRect) - STSelectionHandleSize,
                      STSelectionHandleSize,
                      STSelectionHandleSize);
}

- (void)drawSelectionOverlay {
    if (!self.hasSelectionRect && !self.isCreatingSelection) {
        return;
    }
    CGFloat dashPattern[] = {5.0f, 3.0f};
    const NSInteger dashCount = 2;
    CGFloat phase = self.selectionDashPhase;

    NSRect clamped = [self clampedImageRect:self.selectionRect];
    if (NSIsEmptyRect(clamped)) {
        return;
    }
    NSRect viewRect = [self viewRectForImageRect:clamped];

    NSBezierPath *border = [NSBezierPath bezierPathWithRect:viewRect];
    [border setLineWidth:1.0f];
    [border setLineDash:dashPattern count:dashCount phase:phase];
    [[NSColor blackColor] setStroke];
    [border stroke];
    [border setLineDash:dashPattern count:dashCount phase:phase + 4.0f];
    [[NSColor whiteColor] setStroke];
    [border stroke];

    NSRect handleView = NSMakeRect(NSMaxX(viewRect) - STSelectionHandleSize,
                                   NSMaxY(viewRect) - STSelectionHandleSize,
                                   STSelectionHandleSize,
                                   STSelectionHandleSize);
    NSColor *handleColor = [NSColor alternateSelectedControlColor] ?: [NSColor grayColor];
    [[handleColor colorWithAlphaComponent:0.7f] setFill];
    [[NSBezierPath bezierPathWithRect:handleView] fill];
}

- (NSPoint)imagePointForEvent:(NSEvent *)event {
    NSPoint locationInView = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint imagePoint = NSMakePoint(locationInView.x / self.zoomScale,
                                     locationInView.y / self.zoomScale);
    if (self.image) {
        NSSize size = self.image.size;
        imagePoint.x = MAX(0.0, MIN(size.width, imagePoint.x));
        imagePoint.y = MAX(0.0, MIN(size.height, imagePoint.y));
    }
    return imagePoint;
}

- (void)eraseAtPoint:(NSPoint)point {
    [self commitActiveTextIfNeeded];

    CGFloat tolerance = 10.0 / self.zoomScale;
    for (NSInteger idx = (NSInteger)self.strokes.count - 1; idx >= 0; idx--) {
        MarkupStroke *stroke = self.strokes[(NSUInteger)idx];
        if ([stroke containsPoint:point tolerance:tolerance]) {
            [self removeStrokeAtIndex:(NSUInteger)idx registeringUndo:YES actionName:@"Erase Stroke"];
            return;
        }
    }

    for (NSInteger idx = (NSInteger)self.texts.count - 1; idx >= 0; idx--) {
        MarkupText *text = self.texts[(NSUInteger)idx];
        if ([text containsPoint:point]) {
            [self removeTextAtIndex:(NSUInteger)idx registeringUndo:YES actionName:@"Delete Text"];
            return;
        }
    }
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.image) {
        return;
    }

    NSPoint imagePoint = [self imagePointForEvent:event];
    NSPoint locationInView = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.activeTool == ScreenshotCanvasToolText) {
        if (self.activeTextView && self.currentTextEntry &&
            NSPointInRect(locationInView, NSInsetRect([self activePointerHandleRectInView], -3.0, -3.0))) {
            // Drag the callout's pointer to its target (#33).
            self.isDraggingPointer = YES;
            [[NSCursor closedHandCursor] set];
            return;
        }
        if (self.activeTextView && self.currentTextEntry) {
            NSRect activeRect = [self activeTextGuideRectInView];
            NSRect handleRect = [self activeTextHandleHitRectInView];
            if (NSPointInRect(locationInView, handleRect)) {
                self.isResizingTextBox = YES;
                self.textResizeStartImagePoint = imagePoint;
                self.textResizeStartBoxSize = self.currentTextEntry.boxSize;
                [self updateSelectionAnimationState];
                return;
            }
            if (NSPointInRect(locationInView, activeRect)) {
                NSWindow *window = self.window;
                if (window) {
                    [window makeFirstResponder:self.activeTextView];
                }
                [super mouseDown:event];
                return;
            }
        }

        if (self.activeTextView) {
            // Clicking away finishes the text; the next click starts a new box.
            [self commitActiveTextIfNeeded];
            self.textClickOnlyCommitted = YES;
            return;
        }

        MarkupText *hitText = [self textOverlayContainingImagePoint:imagePoint];
        if (hitText) {
            [self beginTextEntryWithImageRect:[hitText bounds] existingText:hitText];
            return;
        }

        self.isCreatingTextBox = YES;
        self.textDragStartImagePoint = imagePoint;
        self.pendingTextRect = NSMakeRect(imagePoint.x, imagePoint.y, 1.0f, 1.0f);
        self.isResizingTextBox = NO;
        [self updateSelectionAnimationState];
        [self setNeedsDisplay:YES];
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolSelect) {
        [self commitActiveTextIfNeeded];

        if (self.hasSelectionRect) {
            NSRect handleRect = [self selectionHandleRectInView];
            if (NSPointInRect(locationInView, handleRect)) {
                self.isResizingSelection = YES;
                self.isMovingSelection = NO;
                self.isCreatingSelection = NO;
                self.selectionDragStartImagePoint = imagePoint;
                self.selectionStartRect = self.selectionRect;
                [self updateSelectionAnimationState];
                return;
            }
        }

        // Annotations under the pointer are picked before the region selection (#25).
        BOOL extending = (event.modifierFlags & NSEventModifierFlagShift) != 0;
        id hit = [self annotationAtImagePoint:imagePoint];
        if (hit) {
            if (!extending && event.clickCount >= 2 && [hit isKindOfClass:[MarkupText class]]) {
                [self clearAnnotationSelection];
                [self clearSelection];
                [self beginTextEntryWithImageRect:[(MarkupText *)hit bounds] existingText:(MarkupText *)hit];
                return;
            }
            [self clearSelection];
            [self selectAnnotation:hit extending:extending];
            if ([self isAnnotationSelected:hit]) {
                self.isMovingAnnotations = YES;
                self.annotationsMoved = NO;
                [[NSCursor closedHandCursor] set];
                self.annotationMoveLastPoint = imagePoint;
                self.annotationMoveSnapshot = [self annotationSnapshot];
            }
            return;
        }
        if (!extending) {
            [self clearAnnotationSelection];
        }

        if (self.hasSelectionRect) {
            NSRect selectionViewRect = [self viewRectForImageRect:self.selectionRect];
            if (NSPointInRect(locationInView, selectionViewRect)) {
                self.isMovingSelection = YES;
                self.isResizingSelection = NO;
                self.isCreatingSelection = NO;
                self.selectionDragStartImagePoint = imagePoint;
                self.selectionStartRect = self.selectionRect;
                [self updateSelectionAnimationState];
                return;
            }
        }

        self.isCreatingSelection = YES;
        self.isMovingSelection = NO;
        self.isResizingSelection = NO;
        self.selectionDragStartImagePoint = imagePoint;
        self.selectionRect = NSMakeRect(imagePoint.x, imagePoint.y, 1.0f, 1.0f);
        self.selectionStartRect = self.selectionRect;
        self.hasSelectionRect = YES;
        [self updateSelectionAnimationState];
        [self setNeedsDisplay:YES];
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolEraser) {
        [self eraseAtPoint:imagePoint];
        return;
    }

    MarkupStrokeType strokeType = (self.activeTool == ScreenshotCanvasToolHighlighter)
        ? MarkupStrokeTypeHighlighter
        : MarkupStrokeTypePen;
    if (self.activeTool == ScreenshotCanvasToolArrow) {
        // Arrows share the pen's colour and width.
        strokeType = MarkupStrokeTypeArrow;
    }
    NSColor *strokeColor = (strokeType == MarkupStrokeTypeHighlighter) ? self.highlighterColor : self.penColor;
    CGFloat width = (strokeType == MarkupStrokeTypeHighlighter) ? self.highlighterLineWidth : self.penLineWidth;

    self.currentStroke = [[MarkupStroke alloc] initWithType:strokeType
                                                      color:strokeColor
                                                   lineWidth:width];
    [self.currentStroke addPoint:imagePoint];
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.image) {
        return;
    }

    NSPoint imagePoint = [self imagePointForEvent:event];
    if (self.activeTool == ScreenshotCanvasToolText) {
        if (self.textClickOnlyCommitted) {
            return;
        }
        if (self.isDraggingPointer && self.currentTextEntry) {
            self.currentTextEntry.pointerTarget = imagePoint;
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.isCreatingTextBox) {
            NSRect rect = [self normalizedImageRectFromStart:self.textDragStartImagePoint end:imagePoint];
            if (self.image) {
                NSSize canvas = self.image.size;
                rect.origin.x = MAX(0.0f, MIN(rect.origin.x, canvas.width));
                rect.origin.y = MAX(0.0f, MIN(rect.origin.y, canvas.height));
                rect.size.width = MIN(rect.size.width, MAX(1.0f, canvas.width - rect.origin.x));
                rect.size.height = MIN(rect.size.height, MAX(1.0f, canvas.height - rect.origin.y));
            }
            self.pendingTextRect = rect;
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.isResizingTextBox && self.currentTextEntry) {
            // The handle sets the wrap width; the height always follows the text.
            CGFloat deltaX = imagePoint.x - self.textResizeStartImagePoint.x;
            MarkupText *entry = self.currentTextEntry;
            entry.widthIsFixed = YES;
            entry.boxSize = NSMakeSize(MAX(1.0f, self.textResizeStartBoxSize.width + deltaX), entry.boxSize.height);
            [self updateActiveTextViewFrame];
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.activeTextView) {
            [super mouseDragged:event];
        }
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolSelect) {
        if (self.isMovingAnnotations) {
            NSPoint delta = NSMakePoint(imagePoint.x - self.annotationMoveLastPoint.x,
                                        imagePoint.y - self.annotationMoveLastPoint.y);
            if (fabs(delta.x) > 0.0 || fabs(delta.y) > 0.0) {
                [self translateAnnotations:[self selectedAnnotationObjects] byDelta:delta];
                self.annotationMoveLastPoint = imagePoint;
                self.annotationsMoved = YES;
                [self setNeedsDisplay:YES];
            }
            return;
        }
        if (self.isCreatingSelection) {
            NSRect rect = [self normalizedImageRectFromStart:self.selectionDragStartImagePoint end:imagePoint];
            rect = [self clampedImageRect:rect];
            self.selectionRect = rect;
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.isResizingSelection) {
            CGFloat deltaX = imagePoint.x - self.selectionDragStartImagePoint.x;
            CGFloat deltaY = imagePoint.y - self.selectionDragStartImagePoint.y;
            NSRect rect = self.selectionStartRect;
            rect.size.width = MAX(1.0f, rect.size.width + deltaX);
            rect.size.height = MAX(1.0f, rect.size.height + deltaY);
            rect = [self clampedImageRect:rect];
            self.selectionRect = rect;
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.isMovingSelection) {
            CGFloat deltaX = imagePoint.x - self.selectionDragStartImagePoint.x;
            CGFloat deltaY = imagePoint.y - self.selectionDragStartImagePoint.y;
            NSRect rect = self.selectionStartRect;
            rect.origin.x += deltaX;
            rect.origin.y += deltaY;
            rect = [self clampedImageRect:rect];
            self.selectionRect = rect;
            [self setNeedsDisplay:YES];
            return;
        }
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolEraser) {
        [self eraseAtPoint:imagePoint];
        return;
    }

    if (self.currentStroke.type == MarkupStrokeTypeArrow) {
        [self.currentStroke setEndPoint:[self arrowEndForPoint:imagePoint event:event]];
        [self setNeedsDisplay:YES];
        return;
    }
    [self.currentStroke addPoint:imagePoint];
    [self setNeedsDisplay:YES];
}

/// With Shift held, the arrow snaps to the nearest multiple of 45 degrees.
- (NSPoint)arrowEndForPoint:(NSPoint)point event:(NSEvent *)event {
    NSArray<NSValue *> *points = [self.currentStroke points];
    if (points.count == 0 || (event.modifierFlags & NSEventModifierFlagShift) == 0) {
        return point;
    }
    NSPoint start = points.firstObject.pointValue;
    CGFloat dx = point.x - start.x;
    CGFloat dy = point.y - start.y;
    CGFloat length = hypot(dx, dy);
    CGFloat angle = round(atan2(dy, dx) / (M_PI / 4.0)) * (M_PI / 4.0);
    return NSMakePoint(start.x + cos(angle) * length, start.y + sin(angle) * length);
}

- (void)mouseUp:(NSEvent *)event {
    if (!self.image) {
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolText) {
        if (self.textClickOnlyCommitted) {
            self.textClickOnlyCommitted = NO;
            return;
        }
        if (self.isDraggingPointer) {
            self.isDraggingPointer = NO;
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.isCreatingTextBox) {
            NSRect rect = self.pendingTextRect;
            self.isCreatingTextBox = NO;
            self.pendingTextRect = NSZeroRect;
            // A click starts a box at the click point that grows with the text; a horizontal
            // drag sets the wrap width. Either way the height follows the text.
            BOOL dragged = rect.size.width >= 5.0f;
            if (!dragged) {
                rect = NSMakeRect(self.textDragStartImagePoint.x, self.textDragStartImagePoint.y, 1.0f, 1.0f);
            }
            [self beginTextEntryWithImageRect:rect existingText:nil widthIsFixed:dragged];
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.isResizingTextBox) {
            self.isResizingTextBox = NO;
            if (self.currentTextEntry) {
                [self.currentTextEntry updateMeasuredSize];
                [self updateActiveTextViewFrame];
            }
            [self setNeedsDisplay:YES];
            [self updateSelectionAnimationState];
            return;
        }
        if (self.activeTextView) {
            [super mouseUp:event];
        }
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolSelect) {
        if (self.isMovingAnnotations) {
            self.isMovingAnnotations = NO;
            if (self.annotationsMoved) {
                [self registerAnnotationUndoWithSnapshot:self.annotationMoveSnapshot actionName:@"Move"];
            }
            self.annotationMoveSnapshot = nil;
            self.annotationsMoved = NO;
            return;
        }
        if (self.isCreatingSelection) {
            self.isCreatingSelection = NO;
            self.selectionRect = [self clampedImageRect:self.selectionRect];
            if (self.selectionRect.size.width < 2.0f || self.selectionRect.size.height < 2.0f) {
                [self clearSelection];
            } else {
                self.hasSelectionRect = YES;
                [self setNeedsDisplay:YES];
                [self updateSelectionAnimationState];
            }
            return;
        }
        if (self.isResizingSelection || self.isMovingSelection) {
            self.isResizingSelection = NO;
            self.isMovingSelection = NO;
            self.selectionRect = [self clampedImageRect:self.selectionRect];
            if (self.selectionRect.size.width < 2.0f || self.selectionRect.size.height < 2.0f) {
                [self clearSelection];
            } else {
                self.hasSelectionRect = YES;
                [self setNeedsDisplay:YES];
                [self updateSelectionAnimationState];
            }
            return;
        }
        return;
    }

    if (self.activeTool == ScreenshotCanvasToolEraser) {
        return;
    }

    if (!self.currentStroke) {
        return;
    }

    NSPoint imagePoint = [self imagePointForEvent:event];
    MarkupStroke *finalStroke = self.currentStroke;
    self.currentStroke = nil;
    if (finalStroke.type == MarkupStrokeTypeArrow) {
        [finalStroke setEndPoint:[self arrowEndForStroke:finalStroke point:imagePoint event:event]];
        NSArray<NSValue *> *points = [finalStroke points];
        NSPoint start = points.firstObject.pointValue;
        NSPoint end = points.lastObject.pointValue;
        if (points.count < 2 || hypot(end.x - start.x, end.y - start.y) < 4.0) {
            [self setNeedsDisplay:YES]; // too short to be an arrow; a stray click
            return;
        }
        [self insertStroke:finalStroke atIndex:self.strokes.count registeringUndo:YES actionName:@"Draw Arrow"];
        return;
    }
    [finalStroke addPoint:imagePoint];
    [self insertStroke:finalStroke atIndex:self.strokes.count registeringUndo:YES actionName:@"Draw Stroke"];
}

- (NSPoint)arrowEndForStroke:(MarkupStroke *)stroke point:(NSPoint)point event:(NSEvent *)event {
    MarkupStroke *previous = self.currentStroke;
    self.currentStroke = stroke;
    NSPoint end = [self arrowEndForPoint:point event:event];
    self.currentStroke = previous;
    return end;
}

- (NSImage *)flattenedImageWithinRect:(NSRect)clipRect {
    if (!self.image) {
        return nil;
    }

    [self commitActiveTextIfNeeded];

    NSSize size = self.image.size;
    if (size.width <= 0.0 || size.height <= 0.0) {
        return nil;
    }

    NSRect effectiveClip = clipRect;
    if (!NSIsEmptyRect(effectiveClip)) {
        effectiveClip = [self clampedImageRect:effectiveClip];
        if (effectiveClip.size.width < 1.0f || effectiveClip.size.height < 1.0f) {
            effectiveClip = NSZeroRect;
        }
    }

    NSInteger width = (NSInteger)lrint(size.width);
    NSInteger height = (NSInteger)lrint(size.height);
    if (width <= 0 || height <= 0) {
        return nil;
    }

    NSBitmapImageRep *bitmap = STBitmapImageRepFromImage(self.image, size);
    if (!bitmap) {
        bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                         pixelsWide:width
                                                         pixelsHigh:height
                                                      bitsPerSample:8
                                                    samplesPerPixel:4
                                                           hasAlpha:YES
                                                           isPlanar:NO
                                                     colorSpaceName:NSDeviceRGBColorSpace
                                                        bytesPerRow:0
                                                       bitsPerPixel:0];
        if (!bitmap) {
            return nil;
        }
        [bitmap setSize:size];

        NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        if (ctx) {
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:ctx];
            [[NSColor clearColor] setFill];
            NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
            [self.image drawInRect:NSMakeRect(0.0, 0.0, size.width, size.height)
                          fromRect:NSZeroRect
                         operation:NSCompositeSourceOver
                          fraction:1.0
                    respectFlipped:NO
                             hints:nil];
            [NSGraphicsContext restoreGraphicsState];
        }
    }

    NSGraphicsContext *bitmapContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    if (!bitmapContext) {
        return nil;
    }

    STBitmapBuffer buffer;
    BOOL canRasterizeDirectly = STPrepareBitmapBuffer(bitmap, &buffer);
#if ST_ENABLE_GNUSTEP_WORKAROUNDS
    BOOL rasterizeTextDirectly = canRasterizeDirectly;
#else
    BOOL rasterizeTextDirectly = NO;
#endif
    BOOL needsContextDrawing = !canRasterizeDirectly;
#if !ST_ENABLE_GNUSTEP_WORKAROUNDS
    if (!needsContextDrawing) {
        BOOL hasHighlighter = NO;
        for (MarkupStroke *stroke in self.strokes) {
            if (stroke.type == MarkupStrokeTypeHighlighter) {
                hasHighlighter = YES;
                break;
            }
        }
        if (!hasHighlighter && self.currentStroke && self.currentStroke.type == MarkupStrokeTypeHighlighter) {
            hasHighlighter = YES;
        }
        if (hasHighlighter) {
            needsContextDrawing = YES;
        }
    }
#endif

    if (needsContextDrawing) {
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:bitmapContext];

        for (MarkupStroke *stroke in self.strokes) {
            [stroke renderInContext:bitmapContext canvasSize:size];
        }
        if (self.currentStroke) {
            [self.currentStroke renderInContext:bitmapContext canvasSize:size];
        }
        BOOL isEditingExistingText = (self.activeTextView && self.currentTextEntry && [self.texts containsObject:self.currentTextEntry]);
        for (MarkupText *text in self.texts) {
            if (isEditingExistingText && text == self.currentTextEntry) {
                continue;
            }
            [text renderInContext:bitmapContext canvasSize:size];
        }
        if (self.currentTextEntry && !isEditingExistingText) {
            [self.currentTextEntry renderInContext:bitmapContext canvasSize:size];
        }

        [NSGraphicsContext restoreGraphicsState];
    } else {
        for (MarkupStroke *stroke in self.strokes) {
            STRasterizeStrokeOntoBitmap(stroke, &buffer, size);
        }
        if (self.currentStroke) {
            STRasterizeStrokeOntoBitmap(self.currentStroke, &buffer, size);
        }
        BOOL isEditingExistingText = (self.activeTextView && self.currentTextEntry && [self.texts containsObject:self.currentTextEntry]);
        if (rasterizeTextDirectly) {
            for (MarkupText *text in self.texts) {
                if (isEditingExistingText && text == self.currentTextEntry) {
                    continue;
                }
                STRasterizeTextOntoBitmap(text, &buffer, size);
            }
            if (self.currentTextEntry && !isEditingExistingText) {
                STRasterizeTextOntoBitmap(self.currentTextEntry, &buffer, size);
            }
        } else {
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:bitmapContext];
            for (MarkupText *text in self.texts) {
                if (isEditingExistingText && text == self.currentTextEntry) {
                    continue;
                }
                [text renderInContext:bitmapContext canvasSize:size];
            }
            if (self.currentTextEntry && !isEditingExistingText) {
                [self.currentTextEntry renderInContext:bitmapContext canvasSize:size];
            }
            [NSGraphicsContext restoreGraphicsState];
        }
    }

    NSImage *output = [[NSImage alloc] initWithSize:size];
    if (!output) {
        return nil;
    }
    [output addRepresentation:bitmap];

    if (!NSIsEmptyRect(effectiveClip)) {
        NSBitmapImageRep *cropped = STBitmapImageRepCrop(bitmap, effectiveClip, size);
        if (cropped) {
            NSImage *croppedImage = [[NSImage alloc] initWithSize:cropped.size];
            [croppedImage addRepresentation:cropped];
            return croppedImage;
        }
    }
    return output;
}

- (NSImage *)flattenedImage {
    return [self flattenedImageWithinRect:NSZeroRect];
}

- (NSImage *)flattenedImageForSelection {
    if (!self.hasSelectionRect) {
        return [self flattenedImage];
    }
    NSRect integral = [self integralSelectionRect];
    if (NSIsEmptyRect(integral)) {
        return [self flattenedImage];
    }
    return [self flattenedImageWithinRect:integral];
}

- (NSImage *)croppedBaseImageWithRect:(NSRect)clipRect {
    if (!self.image) {
        return nil;
    }
    NSData *tiffData = [self.image TIFFRepresentation];
    if (!tiffData) {
        return nil;
    }
    NSImageRep *rep = [NSBitmapImageRep imageRepWithData:tiffData];
    if (![rep isKindOfClass:[NSBitmapImageRep class]]) {
        return nil;
    }
    NSBitmapImageRep *source = (NSBitmapImageRep *)rep;
    NSBitmapImageRep *cropped = STBitmapImageRepCrop(source, clipRect, self.image.size);
    if (!cropped) {
        return nil;
    }
    NSImage *output = [[NSImage alloc] initWithSize:cropped.size];
    [output addRepresentation:cropped];
    return output;
}

- (BOOL)cropToActiveSelection {
    if (!self.hasSelectionRect) {
        return NO;
    }
    NSRect clipRect = [self integralSelectionRect];
    if (NSIsEmptyRect(clipRect)) {
        return NO;
    }

    [self commitActiveTextIfNeeded];

    NSDictionary *snapshot = [self snapshotCanvasState];

    NSImage *croppedImage = [self croppedBaseImageWithRect:clipRect];
    if (!croppedImage) {
        return NO;
    }

    NSPoint offset = clipRect.origin;

    // Drop annotations entirely outside the crop; partially covered ones are clipped when drawn.
    NSMutableArray<MarkupStroke *> *updatedStrokes = [[NSMutableArray alloc] initWithCapacity:self.strokes.count];
    for (MarkupStroke *stroke in self.strokes) {
        if (!NSIntersectsRect([stroke bounds], clipRect)) {
            continue;
        }
        [stroke translateByOffset:offset];
        [updatedStrokes addObject:stroke];
    }
    self.strokes = updatedStrokes;

    NSMutableArray<MarkupText *> *updatedTexts = [[NSMutableArray alloc] init];
    for (MarkupText *text in self.texts) {
        if (!NSIntersectsRect([text decoratedBounds], clipRect)) {
            continue;
        }
        [text translateByOffset:offset];
        [updatedTexts addObject:text];
    }
    self.texts = updatedTexts;

    self.image = croppedImage;
    [self clearAnnotationSelection];
    [self clearSelection];

    [self updateFrameSize];
    [self updateForEnclosingBoundsChange];
    [self setNeedsDisplay:YES];

    NSUndoManager *undo = [self undoManager];
    if (STUndoLoggingActive()) {
        NSLog(@"[Undo Debug] crop view=%p window=%p undo=%p", self, self.window, undo);
    }
    if (undo && snapshot) {
        if (STUndoLoggingActive()) {
            NSLog(@"[Undo Debug] register undo manager=%p grouping=%ld", undo, (long)[undo groupingLevel]);
        }
        [undo registerUndoWithTarget:self selector:@selector(restoreSnapshotForUndo:) object:snapshot];
        [undo setActionName:@"Crop"];
        if (STUndoLoggingActive()) {
            NSLog(@"[Undo Debug] canUndo after register=%d", [undo canUndo]);
        }
    }
    return YES;
}

- (void)restoreSnapshotForUndo:(NSDictionary *)snapshot {
    [self restoreCanvasStateFromSnapshot:snapshot registeringUndo:YES];
}

@end

@implementation STCanvasClipView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setDrawsBackground:YES];
        [self setBackgroundColor:STThemeCanvasBackdropColor()];
    }
    return self;
}

- (NSPoint)centeredOrigin:(NSPoint)origin forClipSize:(NSSize)clipSize {
    NSView *documentView = self.documentView;
    if (!documentView) {
        return origin;
    }
    NSRect documentFrame = documentView.frame;
    if (documentFrame.size.width < clipSize.width) {
        origin.x = floor(NSMinX(documentFrame) - ((clipSize.width - documentFrame.size.width) * 0.5));
    }
    if (documentFrame.size.height < clipSize.height) {
        origin.y = floor(NSMinY(documentFrame) - ((clipSize.height - documentFrame.size.height) * 0.5));
    }
    return origin;
}

// GNUstep routes every scroll, resize and document frame change through this.
- (NSPoint)constrainScrollPoint:(NSPoint)proposedNewOrigin {
    NSPoint constrained = [super constrainScrollPoint:proposedNewOrigin];
    return [self centeredOrigin:constrained forClipSize:self.bounds.size];
}

#if !defined(GNUSTEP)
- (NSRect)constrainBoundsRect:(NSRect)proposedBounds {
    NSRect constrained = [super constrainBoundsRect:proposedBounds];
    constrained.origin = [self centeredOrigin:constrained.origin forClipSize:constrained.size];
    return constrained;
}
#endif

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSView *documentView = self.documentView;
    if (!documentView || NSContainsRect(documentView.frame, self.bounds)) {
        return;
    }
    [STThemeCanvasImageBorderColor() setFill];
    NSFrameRectWithWidth(NSInsetRect(documentView.frame, -1.0, -1.0), 1.0);
}

@end
