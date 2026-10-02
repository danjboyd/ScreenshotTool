#!/usr/bin/env bash
# Build a Cocoa-native ScreenshotTool.app without GNUstep dependencies.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script builds the macOS Cocoa target; run it on macOS." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/cocoa"
OBJ_DIR="${BUILD_DIR}/obj"
APP_DIR="${BUILD_DIR}/ScreenshotTool.app"
APP_MACOS="${APP_DIR}/Contents/MacOS"
APP_RESOURCES="${APP_DIR}/Contents/Resources"
MODULE_CACHE="${BUILD_DIR}/ModuleCache"

mkdir -p "${OBJ_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_MACOS}"
mkdir -p "${APP_RESOURCES}"
mkdir -p "${MODULE_CACHE}"

CFLAGS=(
  -fobjc-arc
  -fmodules
  -fobjc-link-runtime
  -fobjc-weak
  -ObjC
  -Wall -Wextra
  -Wno-deprecated-declarations
  -mmacosx-version-min=11.0
  -fmodules-cache-path=${MODULE_CACHE}
  -ISource
)
LDFLAGS=(
  -mmacosx-version-min=11.0
  -framework AppKit
  -framework Foundation
  -framework CoreGraphics
  -framework CoreText
)

SOURCES=(
  Source/main.m
  Source/AppDelegate.m
  Source/ScreenshotCanvasView.m
  Source/MarkupStroke.m
  Source/MarkupText.m
  Source/STFloatingPopover.m
  Source/STFloatingPopoverWindow.m
  Source/STFloatingPopoverBackgroundView.m
  Source/STHyperlinkButton.m
  Source/ScreenshotToolSettings.m
  Source/ToolSettingsPopoverController.m
  Source/TextToolPopoverController.m
  Source/PreferencesWindowController.m
  Source/STTextOptionsBar.m
  Source/STThemeUtilities.m
)

echo "Compiling ${#SOURCES[@]} Objective-C files..."
for src in "${SOURCES[@]}"; do
  base="$(basename "${src}" .m)"
  clang "${CFLAGS[@]}" -c "${ROOT_DIR}/${src}" -o "${OBJ_DIR}/${base}.o"
done

echo "Linking app executable..."
clang "${OBJ_DIR}"/*.o "${LDFLAGS[@]}" -o "${APP_MACOS}/ScreenshotTool"
chmod +x "${APP_MACOS}/ScreenshotTool"

ICON_SOURCE="${ROOT_DIR}/Resources/ScreenshotToolIcon.png"
ICONSET_DIR="${BUILD_DIR}/ScreenshotToolIcon.iconset"
ICON_OUTPUT="${APP_RESOURCES}/ScreenshotTool.icns"

echo "Generating app icon..."
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"
C_ICON_GENERATOR="${BUILD_DIR}/generate_app_icon.c"
cat > "${C_ICON_GENERATOR}" <<'C_FILE'
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <sys/stat.h>

static void write_icon(CGImageRef source, const char *dest_dir, int size, int scale) {
  size_t pixels = (size_t)size * (size_t)scale;
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(
    NULL, pixels, pixels, 8, pixels * 4, cs,
    kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  if (!ctx) {
    fprintf(stderr, "Failed to allocate bitmap context for %zux%zu\\n", pixels, pixels);
    exit(1);
  }

  CGContextSetRGBFillColor(ctx, 0, 0, 0, 0);
  CGContextFillRect(ctx, CGRectMake(0, 0, pixels, pixels));
  CGContextDrawImage(ctx, CGRectMake(0, 0, pixels, pixels), source);

  CGImageRef scaled = CGBitmapContextCreateImage(ctx);
  if (!scaled) {
    fprintf(stderr, "Failed to create scaled CGImage for %zux%zu\\n", pixels, pixels);
    exit(1);
  }

  char path[PATH_MAX];
  snprintf(path, sizeof(path), "%s/icon_%dx%d%s.png", dest_dir, size, size, scale == 2 ? "@2x" : "");
  CFStringRef pathStr = CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
  CFURLRef url = CFURLCreateWithFileSystemPath(NULL, pathStr, kCFURLPOSIXPathStyle, false);
  CGImageDestinationRef dest = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
  if (!dest) {
    fprintf(stderr, "Failed to open destination %s\\n", path);
    exit(1);
  }
  CGImageDestinationAddImage(dest, scaled, NULL);
  if (!CGImageDestinationFinalize(dest)) {
    fprintf(stderr, "Failed to write %s\\n", path);
    exit(1);
  }

  CFRelease(dest);
  CFRelease(url);
  CFRelease(pathStr);
  CGImageRelease(scaled);
  CGContextRelease(ctx);
  CGColorSpaceRelease(cs);
}

static void write_icns(const char *iconset_dir, const char *out_path) {
  struct entry { const char *type; const char *file; };
  const struct entry entries[] = {
    {"icp4", "icon_16x16.png"},
    {"ic11", "icon_16x16@2x.png"},
    {"icp5", "icon_32x32.png"},
    {"ic12", "icon_32x32@2x.png"},
    {"ic07", "icon_128x128.png"},
    {"ic13", "icon_128x128@2x.png"},
    {"ic08", "icon_256x256.png"},
    {"ic14", "icon_256x256@2x.png"},
    {"ic09", "icon_512x512.png"},
    {"ic10", "icon_512x512@2x.png"},
  };

  size_t total = 8; // header and length
  size_t sizes[sizeof(entries)/sizeof(entries[0])];
  for (size_t i = 0; i < sizeof(entries)/sizeof(entries[0]); i++) {
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/%s", iconset_dir, entries[i].file);
    struct stat st;
    if (stat(path, &st) != 0) {
      fprintf(stderr, "Missing icon file %s\\n", path);
      exit(1);
    }
    sizes[i] = (size_t)st.st_size;
    total += sizes[i] + 8;
  }

  FILE *out = fopen(out_path, "wb");
  if (!out) {
    perror("fopen icns");
    exit(1);
  }

  fwrite("icns", 1, 4, out);
  uint32_t be_total = CFSwapInt32HostToBig((uint32_t)total);
  fwrite(&be_total, sizeof(be_total), 1, out);

  for (size_t i = 0; i < sizeof(entries)/sizeof(entries[0]); i++) {
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/%s", iconset_dir, entries[i].file);
    FILE *in = fopen(path, "rb");
    if (!in) {
      perror("open icon png");
      exit(1);
    }

    fwrite(entries[i].type, 1, 4, out);
    uint32_t be_len = CFSwapInt32HostToBig((uint32_t)(sizes[i] + 8));
    fwrite(&be_len, sizeof(be_len), 1, out);

    char *buf = malloc(sizes[i]);
    if (!buf) {
      fprintf(stderr, "malloc failed\\n");
      exit(1);
    }
    if (fread(buf, 1, sizes[i], in) != sizes[i]) {
      fprintf(stderr, "short read on %s\\n", path);
      exit(1);
    }
    fwrite(buf, 1, sizes[i], out);
    free(buf);
    fclose(in);
  }

  fclose(out);
}

int main(int argc, const char *argv[]) {
  if (argc != 4) {
    fprintf(stderr, "usage: generate_app_icon <source.png> <dest.iconset> <out.icns>\\n");
    return 1;
  }

  const char *source_path = argv[1];
  const char *dest_dir = argv[2];
  const char *icns_out = argv[3];

  CFStringRef srcStr = CFStringCreateWithCString(NULL, source_path, kCFStringEncodingUTF8);
  CFURLRef srcURL = CFURLCreateWithFileSystemPath(NULL, srcStr, kCFURLPOSIXPathStyle, false);
  CGImageSourceRef src = CGImageSourceCreateWithURL(srcURL, NULL);
  if (!src) {
    fprintf(stderr, "Failed to open source image %s\\n", source_path);
    return 1;
  }

  CGImageRef base = CGImageSourceCreateImageAtIndex(src, 0, NULL);
  if (!base) {
    fprintf(stderr, "Failed to decode source image %s\\n", source_path);
    return 1;
  }

  int sizes[] = {16, 32, 128, 256, 512};
  for (size_t i = 0; i < sizeof(sizes)/sizeof(int); i++) {
    write_icon(base, dest_dir, sizes[i], 1);
    write_icon(base, dest_dir, sizes[i], 2);
  }

  write_icns(dest_dir, icns_out);

  CGImageRelease(base);
  CFRelease(src);
  CFRelease(srcURL);
  CFRelease(srcStr);
  return 0;
}
C_FILE

clang "${C_ICON_GENERATOR}" -framework CoreGraphics -framework ImageIO -framework CoreFoundation -o "${BUILD_DIR}/generate_app_icon"
"${BUILD_DIR}/generate_app_icon" "${ICON_SOURCE}" "${ICONSET_DIR}" "${ICON_OUTPUT}"
rm -rf "${ICONSET_DIR}"
rm -f "${C_ICON_GENERATOR}" "${BUILD_DIR}/generate_app_icon"

echo "Copying resources..."
rsync -a "${ROOT_DIR}/Resources/" "${APP_RESOURCES}/"
cp "${ROOT_DIR}/Resources/Info-cocoa.plist" "${APP_DIR}/Contents/Info.plist"

echo "Cocoa build complete: ${APP_DIR}"
echo "Run it with: ${APP_DIR}/Contents/MacOS/ScreenshotTool"
