#import "AppDelegate.h"
#include <math.h>
#include <string.h>
#import "ScreenshotCanvasView.h"
#import "STHyperlinkButton.h"
#import "ScreenshotToolSettings.h"
#import "ToolSettingsPopoverController.h"
#import "TextToolPopoverController.h"
#import "ZoomPopoverController.h"
#import "PreferencesWindowController.h"
#import "STThemeUtilities.h"
#import "STSegmentToolTips.h"
#import "STSplitButton.h"
#import "STEmptyStateView.h"
#import "STCustomActions.h"
#import <objc/runtime.h>
#import "STScreenshotCapture.h"
#import "STWindowsIntegration.h"
#import "STHudView.h"
#import "STTextOptionsBar.h"
#import "STSelectionActionBar.h"
#if defined(GNUSTEP) && defined(ST_HAVE_LIBS_SHARING)
// Apple's sharing API as libs-sharing implements it (libs-gui declares only part of it).
#import "GSSharing.h"
#import "GSSharingRclone.h"
#endif
#import <Foundation/NSTask.h>
#import <dispatch/dispatch.h>
#if defined(GNUSTEP)
// The packaged updater (gnustep-packager) serves the Windows and Linux builds.
#import "GPStandardUpdaterController.h"
#import <AppKit/NSSegmentedCell.h>
#import <GNUstepGUI/GSTheme.h>
#elif defined(ST_HAS_SPARKLE)
// Sparkle updates the macOS build; scripts/build_cocoa.sh embeds it (the tests build without).
#import <Sparkle/Sparkle.h>
#define ST_USES_SPARKLE 1
#endif

#ifndef NSAboutPanelOptionApplicationIcon
#define NSAboutPanelOptionApplicationIcon @"ApplicationIcon"
#endif
#ifndef NSAboutPanelOptionApplicationName
#define NSAboutPanelOptionApplicationName @"ApplicationName"
#endif
#ifndef NSAboutPanelOptionApplicationVersion
#define NSAboutPanelOptionApplicationVersion @"ApplicationVersion"
#endif
#ifndef NSAboutPanelOptionVersion
#define NSAboutPanelOptionVersion @"Version"
#endif
#ifndef NSAboutPanelOptionCopyright
#define NSAboutPanelOptionCopyright @"Copyright"
#endif
#ifndef NSAboutPanelOptionCredits
#define NSAboutPanelOptionCredits @"Credits"
#endif
static NSString * const ToolbarItemHighlighter = @"com.screenshottool.toolbar.highlighter";
static NSString * const ToolbarItemPen = @"com.screenshottool.toolbar.pen";
static NSString * const ToolbarItemArrow = @"com.screenshottool.toolbar.arrow";
static NSString * const ToolbarItemRectangle = @"com.screenshottool.toolbar.rectangle";
static NSString * const ToolbarItemStep = @"com.screenshottool.toolbar.step";
static NSString * const ToolbarItemRedact = @"com.screenshottool.toolbar.redact";
/// Select, Highlighter, Pen, Arrow, Text, Eraser.
static const NSInteger STToolbarToolSegmentCount = 9;
static NSString * const ToolbarItemEraser = @"com.screenshottool.toolbar.eraser";
static NSString * const ToolbarItemText = @"com.screenshottool.toolbar.text";
static NSString * const ToolbarItemSelect = @"com.screenshottool.toolbar.select";
static NSString * const ToolbarItemTools = @"com.screenshottool.toolbar.tools";
static NSString * const ToolbarItemZoom = @"com.screenshottool.toolbar.zoom";
static NSString * const ToolbarItemCopy = @"com.screenshottool.toolbar.copy";
static NSString * const ToolbarItemPreferences = @"com.screenshottool.toolbar.preferences";
static NSString * const ToolbarItemUndo = @"com.screenshottool.toolbar.undo";
static NSString * const ToolbarItemRedo = @"com.screenshottool.toolbar.redo";
static NSString * const ToolbarItemColor = @"com.screenshottool.toolbar.color";
static NSString * const ToolbarItemSave = @"com.screenshottool.toolbar.save";
/// A custom action's toolbar item: this, then the action's identifier (its file's name).
static NSString * const ToolbarItemCustomActionPrefix = @"com.screenshottool.toolbar.action.";
#if !defined(GNUSTEP) || defined(ST_HAVE_LIBS_SHARING)
static NSString * const ToolbarItemShare = @"com.screenshottool.toolbar.share";
#endif

/// Which toolbar items go into the overflow menu first when the window is too narrow: Undo and
/// Redo (and Zoom and Preferences, customised in), which are in the menus with shortcuts; then
/// custom actions; then Save and Share. The tools, colour and Copy never do: the window's minimum
/// width keeps them (-resizeWindowToImageSize:). AppKit honours this; on GNUstep the theme does.
static NSInteger STToolbarVisibilityPriorityForIdentifier(NSToolbarItemIdentifier identifier) {
    if ([identifier isEqualToString:ToolbarItemTools] || [identifier isEqualToString:ToolbarItemColor] ||
        [identifier isEqualToString:ToolbarItemCopy]) {
        return NSToolbarItemVisibilityPriorityUser;
    }
    if ([identifier isEqualToString:ToolbarItemSave]) {
        return NSToolbarItemVisibilityPriorityHigh;
    }
#if !defined(GNUSTEP) || defined(ST_HAVE_LIBS_SHARING)
    if ([identifier isEqualToString:ToolbarItemShare]) {
        return NSToolbarItemVisibilityPriorityHigh;
    }
#endif
    if ([identifier isEqualToString:ToolbarItemUndo] || [identifier isEqualToString:ToolbarItemRedo] ||
        [identifier isEqualToString:ToolbarItemZoom] || [identifier isEqualToString:ToolbarItemPreferences]) {
        return NSToolbarItemVisibilityPriorityLow;
    }
    return NSToolbarItemVisibilityPriorityStandard;
}

// Tall enough for a 24pt slider (the zoom slider, #221): WinUITheme draws its slider from 24pt.
static const CGFloat StatusBarHeight = 32.0f;
// Smallest canvas area a window gets, so tiny images still leave room for the title and the
// whole icon-only toolbar: under Adwaita the colour well and Copy overflow below about 640pt.
// macOS measures its own, wider minimum (-resizeWindowToImageSize:). On Windows 600pt, 900px at
// 150%, so a window fits on half of a 1920px screen with room to spare; WinUITheme's minimum
// keeps the tools, colour and Copy where it honours visibility priority.
#if defined(_WIN32)
static const CGFloat STMinimumCanvasWidth = 600.0f;
#else
static const CGFloat STMinimumCanvasWidth = 640.0f;
#endif
static const CGFloat STMinimumCanvasHeight = 240.0f;
static const CGFloat STHudCornerRadius = 10.0f;
static const CGFloat STHudHorizontalPadding = 20.0f;
static const CGFloat STHudVerticalPadding = 12.0f;
static const CGFloat STHudMaxWidth = 360.0f;
static const NSTimeInterval STHudFadeInDuration = 0.12;
static const NSTimeInterval STHudFadeOutDuration = 0.20;
static const CGFloat ToolbarIconDimension = 32.0f;
static const NSUInteger STRecentDocumentLimit = 10;
/// The empty state's Recent row (#221): its label's tag, its cards' first tag and their number.
static const NSInteger STEmptyStateRecentLabelTag = 7;
static const NSInteger STEmptyStateRecentFirstCardTag = 20;
static const NSInteger STEmptyStateRecentCount = 3;
static NSString * const STRecentDocumentsEmptyTitle = @"No Recent Documents";
static NSString * const STRecentDocumentsClearTitle = @"Clear Menu";
#if defined(_WIN32)
// WinUI's segmented icon items, so that at 150% the narrowest window (the tools, colour and Copy
// kept) still fits on half of a 1920px screen. Each one stays a 40px touch target.
static const CGFloat STToolbarToolSegmentWidth = 40.0f;
#else
static const CGFloat STToolbarToolSegmentWidth = 46.0f;
#endif
static const CGFloat STToolbarToolControlHeight = 32.0f;
static const CGFloat STToolbarToolIconSize = 22.0f;
static const CGFloat STToolbarColorControlWidth = 40.0f;
static const CGFloat STToolbarColorControlHeight = 32.0f;
static const CGFloat STToolbarZoomControlHeight = 32.0f;
static const CGFloat STToolbarZoomFontSize = 18.0f;
static const CGFloat STToolbarZoomChevronWidth = 9.0f;
static const CGFloat STToolbarZoomChevronSpacing = 8.0f;
static const CGFloat STToolbarZoomHorizontalPadding = 12.0f;
static NSString * const ToolbarIdentifier = @"com.screenshottool.toolbar";

static id STInfoValueForKey(NSString *key);

static NSString *STStandardizedRecentDocumentPath(NSURL *url) {
    if (!url || !url.isFileURL) {
        return nil;
    }
    NSString *path = [[url path] stringByStandardizingPath];
    if (path.length == 0) {
        return nil;
    }
    return path;
}

static NSString *STInfoStringForKey(NSString *key) {
    if (key.length == 0) {
        return nil;
    }
    NSBundle *bundle = [NSBundle mainBundle];
    id value = [bundle objectForInfoDictionaryKey:key];
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
        return value;
    }
    return nil;
}

static NSImage *STApplicationIcon(void) {
#if defined(GNUSTEP)
    return [NSImage imageNamed:@"ScreenshotToolIcon"];
#else
    // The bundle's .icns, shaped for macOS (no square background).
    return [NSApp applicationIconImage];
#endif
}

static NSString *STHomeDirectory(void) {
    NSString *home = NSHomeDirectory();
    if (home.length > 0) {
        return home;
    }
    NSString *temporaryDirectory = NSTemporaryDirectory();
    if (temporaryDirectory.length > 0) {
        return temporaryDirectory;
    }
    return @".";
}

static NSString *STDefaultLogFilePath(void) {
#if !defined(GNUSTEP)
    return [[STHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/ScreenshotTool"]
            stringByAppendingPathComponent:@"screenshottool.log"];
#else
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    NSString *xdgStateHome = env[@"XDG_STATE_HOME"];
    NSString *baseDirectory = (xdgStateHome.length > 0)
        ? xdgStateHome
        : [STHomeDirectory() stringByAppendingPathComponent:@".local/state"];
    return [[baseDirectory stringByAppendingPathComponent:@"screenshottool"]
            stringByAppendingPathComponent:@"screenshottool.log"];
#endif
}

static NSString *const STPastedImageTitle = @"Pasted Image";

static NSString *STTemporaryClipboardDirectory(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"ScreenshotToolClipboard"];
}

static NSString *STDefaultSaveDirectoryPath(void) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *home = STHomeDirectory();
    NSArray<NSString *> *candidates = @[
        [home stringByAppendingPathComponent:@"Pictures"],
        home
    ];

    for (NSString *candidate in candidates) {
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:candidate isDirectory:&isDirectory] && isDirectory) {
            return candidate;
        }
    }

    return home;
}

/// The picture formats Open offers. Not +[NSImage imageFileTypes]: on GNUstep that can include
/// everything ImageMagick reads (text, HTML, video…), which made Open's file type menu hundreds
/// of entries long.
#if !defined(GNUSTEP)
/// A mask that rounds a view's corners at any size (a stretchable image).
static NSImage *STRoundedMaskImage(CGFloat radius) {
    CGFloat edge = radius * 2.0 + 1.0;
    NSImage *mask = [NSImage imageWithSize:NSMakeSize(edge, edge) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor blackColor] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
        return YES;
    }];
    mask.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
    mask.resizingMode = NSImageResizingModeStretch;
    return mask;
}
#endif

/// Where dragged-out and shared images are written; exports older than STExportMaximumAge are
/// removed at launch.
static NSURL *STExportDirectoryURL(void) {
    return [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
            URLByAppendingPathComponent:@"ScreenshotTool Exports" isDirectory:YES];
}

/// How long an export is kept. A newer one may still be in use: Open With can launch another
/// instance to open it, and another running instance may still be dragging or sharing it (#294).
static const NSTimeInterval STExportMaximumAge = 24 * 60 * 60;

void STRemoveExportsChangedBefore(NSURL *directory, NSDate *cutoff) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *name in [fileManager contentsOfDirectoryAtPath:directory.path error:NULL]) {
        NSString *path = [directory.path stringByAppendingPathComponent:name];
        NSDate *modified = [[fileManager attributesOfItemAtPath:path error:NULL] fileModificationDate];
        if (!modified || [modified compare:cutoff] == NSOrderedAscending) {
            [fileManager removeItemAtPath:path error:NULL];
        }
    }
}

/// YES where there's a share picker: macOS's, and on GNUstep libs-sharing's sheet
/// (third_party/libs-sharing; libs-gui's NSSharingServicePicker alone is a stub).
static BOOL STCanShareImages(void) {
#if !defined(GNUSTEP) || defined(ST_HAVE_LIBS_SHARING)
    return YES;
#else
    return NO;
#endif
}

static NSArray<NSString *> *STOpenableImageFileTypes(void) {
    return @[ @"png", @"jpg", @"jpeg", @"gif", @"bmp", @"tif", @"tiff", @"webp" ];
}

/// Read by the Adwaita theme: YES puts the window's toolbar in its header bar. The theme offers it
/// for all apps (danjboyd/plugins-themes-Adwaita#30); the app only declares it in Info.plist (#52).
static NSString * const STGnomeThemeHeaderBarToolbarKey = @"GnomeThemeHeaderBarToolbar";
/// Set once the value the app's old "Show toolbar in the title bar" checkbox saved is cleared (#58).
static NSString * const STDefaultsClearedHeaderBarToolbarKey = @"ScreenshotToolClearedHeaderBarToolbar";

static NSString * const STProjectFileExtension = @"screenshottool";
/// `ScreenshotTool --capture` takes a screenshot instead of opening an image.
static NSString * const STCaptureLaunchArgument = @"--capture";

/// `stem`-symbolic: GNOME's name for a single-colour icon. Themes that tint template images
/// (Adwaita) recognise it by the name, since GNUstep 0.32 has no -[NSImage setTemplate:] (#57).
static NSString *STSymbolicIconName(NSString *stem) {
    return [stem stringByAppendingString:@"-symbolic"];
}

/// Names a loaded symbolic icon after its file, which is how the theme knows to tint it.
static void STMarkSymbolicIcon(NSImage *image, NSString *name) {
    if (!image || ![name hasSuffix:@"-symbolic"]) {
        return;
    }
#if defined(GNUSTEP)
    if (![[image name] isEqualToString:name]) {
        [image setName:name];
    }
#else
    // A template image: AppKit tints it for light and dark mode and the selected segment.
    [image setTemplate:YES];
#endif
}

#if defined(GNUSTEP)
/// GNUstep's -[NSImage copy] has no name, nor has an image redrawn into a new bitmap, so the
/// theme left a symbolic icon's toolbar copy untinted (dark grey on Adwaita's dark header bar). A
/// registered name can't be given to a second image: the copy for each use gets a name of its
/// own, `stem-use-symbolic`, and is kept, so it's named once and handed out again after.
static NSMutableDictionary<NSString *, NSImage *> *STSymbolicCopies(void) {
    static NSMutableDictionary<NSString *, NSImage *> *copies = nil;
    if (!copies) {
        copies = [[NSMutableDictionary alloc] init];
    }
    return copies;
}

/// `stem-use-symbolic` for a copy of `source` made for `use`, or nil when `source` isn't symbolic.
static NSString *STSymbolicCopyName(NSImage *source, NSString *use) {
    NSString *name = [source name];
    NSString *suffix = @"-symbolic";
    if (![name hasSuffix:suffix]) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@-%@%@", [name substringToIndex:name.length - suffix.length], use, suffix];
}

/// Names `copy` and keeps it, when it can take the name.
static NSImage *STKeepSymbolicCopy(NSImage *copy, NSString *name) {
    if (copy && name && [copy setName:name]) {
        STSymbolicCopies()[name] = copy;
    }
    return copy;
}
#endif

typedef NS_ENUM(NSInteger, STUnsavedChangesChoice) {
    STUnsavedChangesChoiceSave = 0,
    STUnsavedChangesChoiceDiscard = 1,
    STUnsavedChangesChoiceCancel = 2,
};

static BOOL STURLIsProject(NSURL *url) {
    return [[[url pathExtension] lowercaseString] isEqualToString:STProjectFileExtension];
}

static BOOL STPathUsesTIFFExtension(NSString *path) {
    NSString *extension = [[path pathExtension] lowercaseString];
    return [extension isEqualToString:@"tif"] || [extension isEqualToString:@"tiff"];
}

static NSFont *STToolbarZoomFont(void) {
    return [NSFont systemFontOfSize:STToolbarZoomFontSize];
}

static CGFloat STToolbarZoomControlWidthForTitle(NSString *title) {
    NSString *displayTitle = (title.length > 0) ? title : @"Zoom";
    NSDictionary *attributes = @{ NSFontAttributeName: STToolbarZoomFont() };
    NSSize titleSize = [displayTitle sizeWithAttributes:attributes];
    CGFloat contentWidth = titleSize.width + STToolbarZoomChevronSpacing + STToolbarZoomChevronWidth;
    return ceil(contentWidth + (STToolbarZoomHorizontalPadding * 2.0f));
}

static CGFloat STToolbarZoomReservedControlWidth(void) {
    static CGFloat reservedWidth = 0.0f;
    if (reservedWidth <= 0.0f) {
        // Reserve enough width for the widest zoom string so the toolbar item stays stable.
        reservedWidth = MAX(STToolbarZoomControlWidthForTitle(@"Fit"),
                            STToolbarZoomControlWidthForTitle(@"888.8%"));
    }
    return reservedWidth;
}

#if defined(GNUSTEP)
static NSBitmapImageRep *STBitmapRepresentationFromImage(NSImage *image) {
    if (!image) {
        return nil;
    }
    NSSize size = image.size;
    NSInteger width = MAX(1, (NSInteger)ceil(size.width));
    NSInteger height = MAX(1, (NSInteger)ceil(size.height));
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                       pixelsWide:width
                                                                       pixelsHigh:height
                                                                    bitsPerSample:8
                                                                  samplesPerPixel:4
                                                                         hasAlpha:YES
                                                                         isPlanar:NO
                                                                   colorSpaceName:NSCalibratedRGBColorSpace
                                                                      bytesPerRow:0
                                                                     bitsPerPixel:0];
    if (!bitmap) {
        return nil;
    }
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    if (!context) {
        return nil;
    }
    NSGraphicsContext *previousContext = [NSGraphicsContext currentContext];
    [NSGraphicsContext setCurrentContext:context];
    [[NSColor clearColor] setFill];
    NSRect bounds = NSMakeRect(0.0f, 0.0f, width, height);
    NSRectFill(bounds);
    [image drawInRect:bounds
             fromRect:NSZeroRect
            operation:NSCompositeSourceOver
             fraction:1.0f
       respectFlipped:YES
                hints:nil];
    [NSGraphicsContext setCurrentContext:previousContext];
    return bitmap;
}

static NSBitmapImageRep *STDeviceBitmapRepresentationFromBitmapRep(NSBitmapImageRep *sourceRep) {
    if (!sourceRep) {
        return nil;
    }
    NSInteger width = sourceRep.pixelsWide;
    NSInteger height = sourceRep.pixelsHigh;
    if (width <= 0 || height <= 0) {
        return nil;
    }
    NSBitmapImageRep *destRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                         pixelsWide:width
                                                                         pixelsHigh:height
                                                                      bitsPerSample:8
                                                                    samplesPerPixel:4
                                                                           hasAlpha:YES
                                                                           isPlanar:NO
                                                                     colorSpaceName:NSDeviceRGBColorSpace
                                                                        bytesPerRow:0
                                                                       bitsPerPixel:0];
    if (!destRep) {
        return nil;
    }
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            NSColor *pixel = [sourceRep colorAtX:x y:y];
            if (!pixel) {
                pixel = [NSColor clearColor];
            }
            NSColor *devicePixel = [pixel colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: pixel;
            [destRep setColor:devicePixel atX:x y:y];
        }
    }
    [destRep setSize:sourceRep.size];
    return destRep;
}

static NSBitmapImageRep *STDeviceBitmapRepresentationFromImage(NSImage *image) {
    if (!image) {
        return nil;
    }
    for (NSImageRep *representation in image.representations) {
        if (![representation isKindOfClass:[NSBitmapImageRep class]]) {
            continue;
        }
        NSBitmapImageRep *normalized = STDeviceBitmapRepresentationFromBitmapRep((NSBitmapImageRep *)representation);
        if (normalized) {
            return normalized;
        }
    }
    NSBitmapImageRep *fallback = STBitmapRepresentationFromImage(image);
    return STDeviceBitmapRepresentationFromBitmapRep(fallback);
}

static NSImage *STBitmapBackedImageFromBitmapRep(NSBitmapImageRep *bitmap, NSSize logicalSize) {
    if (!bitmap) {
        return nil;
    }
    [bitmap setSize:logicalSize];
    NSData *tiffData = [bitmap TIFFRepresentation];
    NSImage *image = tiffData ? [[NSImage alloc] initWithData:tiffData] : nil;
    if (!image) {
        image = [[NSImage alloc] initWithSize:logicalSize];
        [image addRepresentation:bitmap];
    }
    [image setSize:logicalSize];
    return image;
}

static NSImage *STBitmapBackedImageFromFile(NSString *path, NSSize logicalSize) {
    if (path.length == 0) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        return nil;
    }
    NSBitmapImageRep *sourceRep = [NSBitmapImageRep imageRepWithData:data];
    if (!sourceRep) {
        return nil;
    }
    NSBitmapImageRep *normalized = STDeviceBitmapRepresentationFromBitmapRep(sourceRep);
    if (!normalized) {
        return nil;
    }
    NSSize targetSize = logicalSize;
    if (targetSize.width <= 0.0f || targetSize.height <= 0.0f) {
        targetSize = sourceRep.size;
    }
    return STBitmapBackedImageFromBitmapRep(normalized, targetSize);
}

static BOOL STBitmapRepHasVisiblePixels(NSBitmapImageRep *bitmap) {
    if (!bitmap) {
        return NO;
    }
    NSInteger width = bitmap.pixelsWide;
    NSInteger height = bitmap.pixelsHigh;
    if (width <= 0 || height <= 0) {
        return NO;
    }
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            NSColor *pixel = [bitmap colorAtX:x y:y];
            if (!pixel) {
                continue;
            }
            NSColor *devicePixel = [pixel colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: pixel;
            if ([devicePixel alphaComponent] > 0.05f) {
                return YES;
            }
        }
    }
    return NO;
}

static BOOL STImageHasVisiblePixels(NSImage *image) {
    if (!image) {
        return NO;
    }
    BOOL inspectedRep = NO;
    for (NSImageRep *representation in image.representations) {
        if (![representation isKindOfClass:[NSBitmapImageRep class]]) {
            continue;
        }
        inspectedRep = YES;
        if (STBitmapRepHasVisiblePixels((NSBitmapImageRep *)representation)) {
            return YES;
        }
    }
    if (inspectedRep) {
        return NO;
    }
    NSBitmapImageRep *fallbackRep = STBitmapRepresentationFromImage(image);
    return STBitmapRepHasVisiblePixels(fallbackRep);
}
#endif
#if !defined(GNUSTEP)
static NSImage *STRenderToolbarIcon(NSImage *source) {
    if (!source) {
        return nil;
    }
    NSSize targetSize = NSMakeSize(ToolbarIconDimension, ToolbarIconDimension);
    NSInteger pixelsWide = (NSInteger)ceil(targetSize.width);
    NSInteger pixelsHigh = (NSInteger)ceil(targetSize.height);
    if (pixelsWide <= 0 || pixelsHigh <= 0) {
        return nil;
    }

    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                       pixelsWide:pixelsWide
                                                                       pixelsHigh:pixelsHigh
                                                                    bitsPerSample:8
                                                                  samplesPerPixel:4
                                                                         hasAlpha:YES
                                                                         isPlanar:NO
                                                                   colorSpaceName:NSCalibratedRGBColorSpace
                                                                      bytesPerRow:0
                                                                     bitsPerPixel:0];
    if (!bitmap) {
        return nil;
    }
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    if (!context) {
        return nil;
    }

    NSGraphicsContext *previousContext = [NSGraphicsContext currentContext];
    [NSGraphicsContext setCurrentContext:context];
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0.0f, 0.0f, targetSize.width, targetSize.height));
    [source drawInRect:NSMakeRect(0.0f, 0.0f, targetSize.width, targetSize.height)
             fromRect:NSZeroRect
            operation:NSCompositeSourceOver
             fraction:1.0f
       respectFlipped:YES
                hints:nil];
    [NSGraphicsContext setCurrentContext:previousContext];

    [bitmap setSize:targetSize];
    NSData *tiffData = [bitmap TIFFRepresentation];
    if (!tiffData) {
        return nil;
    }
    NSImage *normalized = [[NSImage alloc] initWithData:tiffData];
    if (!normalized) {
        return nil;
    }
    [normalized setSize:targetSize];
    if (normalized.representations.count == 0) {
        ScreenshotToolAppendLog(@"ScreenshotTool: normalized icon missing representations");
    }
    return normalized;
}
#endif

static NSString *STPathForToolbarResource(NSString *filename, NSString *extension) {
    NSMutableArray<NSString *> *bundleCandidates = [[NSMutableArray alloc] init];
    NSString *mainResource = [[NSBundle mainBundle] resourcePath];
    if (mainResource.length > 0) {
        [bundleCandidates addObject:mainResource];
    }
    NSBundle *classBundle = [NSBundle bundleForClass:[AppDelegate class]];
    NSString *classResource = [classBundle resourcePath];
    if (classResource.length > 0 && ![bundleCandidates containsObject:classResource]) {
        [bundleCandidates addObject:classResource];
    }

    for (NSString *resourcePath in bundleCandidates) {
        NSString *path = [resourcePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", filename, extension]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return path;
        }
    }

    NSMutableArray<NSString *> *fallbackBases = [[NSMutableArray alloc] init];
    NSString *mainBundleBase = [[NSBundle mainBundle] bundlePath];
    if (mainBundleBase.length > 0) {
        [fallbackBases addObject:[mainBundleBase stringByAppendingPathComponent:@"Resources"]];
    }
    NSString *classBundleBase = [classBundle bundlePath];
    if (classBundleBase.length > 0) {
        [fallbackBases addObject:[classBundleBase stringByAppendingPathComponent:@"Resources"]];
        NSString *parent = [classBundleBase stringByDeletingLastPathComponent];
        NSString *grandParent = [parent stringByDeletingLastPathComponent];
        NSString *repoRoot = [grandParent stringByDeletingLastPathComponent];
        if (repoRoot.length > 0) {
            [fallbackBases addObject:[repoRoot stringByAppendingPathComponent:@"Resources"]];
        }
    }
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    if (cwd.length > 0) {
        [fallbackBases addObject:[cwd stringByAppendingPathComponent:@"Resources"]];
    }

    for (NSString *base in fallbackBases) {
        if (base.length == 0) {
            continue;
        }
        NSString *candidate = [base stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", filename, extension]];
        ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: probing resource path %@", candidate]);
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: fallback resource path %@", candidate]);
            return candidate;
        }
    }
    return nil;
}

/// Whether the app ships a toolbar icon named `stem`, in any of its forms. Ask this rather than
/// whether the toolbar's loader returned an image: for a name it can't find, it returns an empty
/// image, which macOS draws as a filled square (#221's Save before its icon landed).
static BOOL STToolbarIconExists(NSString *stem) {
    return STPathForToolbarResource(STSymbolicIconName(stem), @"png") != nil ||
           STPathForToolbarResource(stem, @"png") != nil ||
           STPathForToolbarResource(stem, @"tiff") != nil;
}

/// A file size in decimal units, as Finder and Explorer show it: "980 bytes", "214 KB", "1.2 MB".
static NSString *STFileSizeString(unsigned long long bytes) {
    if (bytes < 1000ULL) {
        return [NSString stringWithFormat:@"%llu bytes", bytes];
    }
    if (bytes < 1000000ULL) {
        return [NSString stringWithFormat:@"%.0f KB", bytes / 1000.0];
    }
    if (bytes < 1000000000ULL) {
        return [NSString stringWithFormat:@"%.1f MB", bytes / 1000000.0];
    }
    return [NSString stringWithFormat:@"%.1f GB", bytes / 1000000000.0];
}

/// The sizes, in points, the toolbar draws its icons at: GNOME's small toolbar, the tool
/// switcher's segments, Adwaita's toolbar items, and other themes' toolbar items.
static const NSInteger STToolbarIconPointSizes[] = {16, 22, 24, 32};

#if defined(GNUSTEP)
/// The pixel size of the shipped icon file to draw at `points` points on GNUstep: the size itself
/// at a scale of 1, else the smallest file (the point sizes and their doubles) that covers the
/// scaled size, so a scaled-up UI (GSScaleFactor, a DPI-aware Windows display above 100%) draws
/// a larger rendering shrunk a little rather than a smaller one blown up. GNUstep picks an image's
/// representation by its size in points, not its pixels, so each point size gets just this one.
static NSInteger STToolbarIconPixelSize(NSInteger points) {
    CGFloat scale = [[NSScreen mainScreen] userSpaceScaleFactor];
    if (scale <= 1.0) {
        return points;
    }
    CGFloat needed = points * scale;
    NSInteger best = 0;
    NSInteger largest = points;
    const size_t count = sizeof(STToolbarIconPointSizes) / sizeof(STToolbarIconPointSizes[0]);
    for (size_t i = 0; i < count * 2; i++) {
        NSInteger pixels = STToolbarIconPointSizes[i % count] * (i < count ? 1 : 2);
        largest = MAX(largest, pixels);
        if (pixels >= needed - 0.01 && (best == 0 || pixels < best)) {
            best = pixels;
        }
    }
    return best > 0 ? best : largest;
}
#endif

/// The toolbar icon `name` (`stem-symbolic`) with a representation for each size the toolbar draws
/// it at, each rendered from its SVG at that size (scripts/render_toolbar_icons.py), so none is
/// resampled on screen: drawn at one, an NSImage picks that one. Doubled-up ones are added for
/// Retina displays on macOS; on GNUstep a scaled-up UI gets larger files instead
/// (STToolbarIconPixelSize). Nil when the sized files aren't there.
static NSImage *STSizedToolbarIcon(NSString *name, NSSize size) {
    NSString *suffix = @"-symbolic";
    if (![name hasSuffix:suffix]) {
        return nil;
    }
    NSString *stem = [name substringToIndex:name.length - suffix.length];
#if defined(GNUSTEP)
    const NSInteger scales[] = {1};
#else
    const NSInteger scales[] = {1, 2};
#endif
    NSImage *image = [[NSImage alloc] initWithSize:size];
    for (size_t i = 0; i < sizeof(STToolbarIconPointSizes) / sizeof(STToolbarIconPointSizes[0]); i++) {
        NSInteger points = STToolbarIconPointSizes[i];
        for (size_t j = 0; j < sizeof(scales) / sizeof(scales[0]); j++) {
#if defined(GNUSTEP)
            NSInteger pixels = STToolbarIconPixelSize(points);
#else
            NSInteger pixels = points * scales[j];
#endif
            NSString *file = [NSString stringWithFormat:@"%@-%ld%@", stem, (long)pixels, suffix];
            NSString *path = STPathForToolbarResource(file, @"png");
            NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
            NSBitmapImageRep *rep = data ? [NSBitmapImageRep imageRepWithData:data] : nil;
#if defined(GNUSTEP)
            rep = rep ? (STDeviceBitmapRepresentationFromBitmapRep(rep) ?: rep) : nil;
#endif
            if (!rep) {
                continue;
            }
            [rep setSize:NSMakeSize(points, points)];
            [image addRepresentation:rep];
        }
    }
    return image.representations.count > 0 ? image : nil;
}

/// Whether the image is one of STSizedToolbarIcon's: copied and given a size, it's drawn as it is,
/// not redrawn into one bitmap, which would resample it.
static BOOL STIsSizedToolbarIcon(NSImage *image) {
    return image.representations.count > 1;
}

@interface STStatusBarBackgroundView : NSView
@property (nonatomic, strong) NSColor *fillColor;
@property (nonatomic, strong) NSColor *topBorderColor;
@end

@implementation STStatusBarBackgroundView

- (void)setFillColor:(NSColor *)fillColor {
    _fillColor = fillColor;
    [self setNeedsDisplay:YES];
}

- (void)setTopBorderColor:(NSColor *)topBorderColor {
    _topBorderColor = topBorderColor;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSColor *fill = self.fillColor ?: [NSColor windowBackgroundColor];
    [fill setFill];
    NSRectFill(dirtyRect);
    if (self.topBorderColor) {
        // Along the top of the bounds, whatever part is being redrawn: placed from the dirty
        // rect, it went missing wherever only part of the bar redrew (#221).
        NSRect border = NSMakeRect(NSMinX(self.bounds),
                                   NSMaxY(self.bounds) - 1.0f,
                                   NSWidth(self.bounds),
                                   1.0f);
        [self.topBorderColor setFill];
        NSRectFill(border);
    }
}

@end



/// The active tool's colour as a standard colour well, drawn by the theme (#57). A click opens the
/// app's tool settings (its action) rather than the system colour panel.
@interface STToolbarColorWellView : NSColorWell
@end

/// The zoom level as a standard button that opens the zoom popover, drawn by the theme (#57).
@interface STToolbarZoomButtonView : NSButton
@end


#if defined(GNUSTEP)
static NSPoint STCenteredToolbarViewOrigin(NSView *view, NSPoint proposedOrigin) {
    if (!view || !view.superview) {
        return proposedOrigin;
    }
    CGFloat centeredY = MAX(0.0f, floor((NSHeight(view.superview.bounds) - NSHeight(view.frame)) * 0.5f));
    proposedOrigin.y = centeredY;
    return proposedOrigin;
}
#endif

@implementation STToolbarColorWellView

- (void)viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
#if defined(GNUSTEP)
    if (self.superview) {
        [super setFrameOrigin:STCenteredToolbarViewOrigin(self, self.frame.origin)];
    }
#endif
}

- (void)setFrameOrigin:(NSPoint)newOrigin {
#if defined(GNUSTEP)
    newOrigin = STCenteredToolbarViewOrigin(self, newOrigin);
#endif
    [super setFrameOrigin:newOrigin];
}

- (void)setColor:(NSColor *)color {
    // No colour (a tool without one): the well shows the window's background, and is disabled.
    [super setColor:color ?: [NSColor windowBackgroundColor]];
}

/// The well's action is the app's tool settings popover; the system colour panel stays closed.
- (void)mouseDown:(NSEvent *)event {
    (void)event;
    if (self.isEnabled) {
        [self sendAction:self.action to:self.target];
    }
}

- (void)activate:(BOOL)exclusive {
    (void)exclusive;
}

@end

@implementation STToolbarZoomButtonView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setButtonType:NSMomentaryPushInButton];
        [self setBezelStyle:NSTexturedRoundedBezelStyle];
        [self setImagePosition:NSNoImage];
    }
    return self;
}

- (void)viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
#if defined(GNUSTEP)
    if (self.superview) {
        [super setFrameOrigin:STCenteredToolbarViewOrigin(self, self.frame.origin)];
    }
#endif
}

- (void)setFrameOrigin:(NSPoint)newOrigin {
#if defined(GNUSTEP)
    newOrigin = STCenteredToolbarViewOrigin(self, newOrigin);
#endif
    [super setFrameOrigin:newOrigin];
}

@end


@interface STToolbarSegmentedControl : NSSegmentedControl
@property (nonatomic, assign) NSInteger clickedSegment;
@property (nonatomic, assign) NSInteger lastClickCount;
@end

@implementation STToolbarSegmentedControl

- (void)viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
#if defined(GNUSTEP)
    if (self.superview) {
        [super setFrameOrigin:STCenteredToolbarViewOrigin(self, self.frame.origin)];
    }
#endif
}

- (void)setFrameOrigin:(NSPoint)newOrigin {
#if defined(GNUSTEP)
    newOrigin = STCenteredToolbarViewOrigin(self, newOrigin);
#endif
    [super setFrameOrigin:newOrigin];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint location = event ? [self convertPoint:event.locationInWindow fromView:nil] : NSZeroPoint;
    NSInteger segmentCount = [self segmentCount];
    CGFloat originX = 0.0f;
    NSInteger hitSegment = -1;
    for (NSInteger segment = 0; segment < segmentCount; segment++) {
        CGFloat segmentWidth = [self widthForSegment:segment];
        if (segmentWidth <= 0.0f) {
            segmentWidth = floor(self.bounds.size.width / MAX((CGFloat)segmentCount, 1.0f));
        }
        NSRect segmentRect = NSMakeRect(originX, 0.0f, segmentWidth, self.bounds.size.height);
        if (NSPointInRect(location, segmentRect)) {
            hitSegment = segment;
            break;
        }
        originX += segmentWidth;
    }
    if (hitSegment < 0) {
        return;
    }
    self.clickedSegment = hitSegment;
    self.lastClickCount = event ? event.clickCount : 0;
    [self setSelectedSegment:hitSegment];
    [self setNeedsDisplay:YES];
    if (self.target && self.action) {
        [NSApp sendAction:self.action to:self.target from:self];
    }
}

@end

/// The Copy toolbar button: a click copies the image; dragging it hands the annotated image (or
/// the selection) to another app as a PNG file. `dragFileProvider` writes the file as a drag
/// starts. On Linux the file goes out as text/uri-list through libs-back's XDND, which needs
/// scripts/patches' XDND fixes to reach other apps.
#if defined(GNUSTEP)
// The classic drag, whose source methods are informal.
@interface STDragExportButton : NSButton
#else
@interface STDragExportButton : NSButton <NSDraggingSource>
#endif
@property (nonatomic, copy, nullable) NSURL * _Nullable (^dragFileProvider)(void);
/// The press a drag or a click is deciding from (GNUstep).
@property (nonatomic, strong, nullable) NSEvent *pressEvent;
@end

@implementation STDragExportButton

- (void)setPressed:(BOOL)pressed {
#if defined(GNUSTEP)
    [self highlight:pressed];
#else
    self.highlighted = pressed;
#endif
}

#if defined(GNUSTEP)
// GNUstep sends the press's drags and release to the view that took the press, so the button
// decides there, as the canvas does, rather than in a loop of its own in -mouseDown:: under the
// Adwaita theme's header bar such a loop never got the release, and a plain click didn't copy.
- (void)mouseDown:(NSEvent *)event {
    if (![self isEnabled] || !self.dragFileProvider) {
        [super mouseDown:event];
        return;
    }
    self.pressEvent = event;
    [self setPressed:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    NSEvent *press = self.pressEvent;
    if (!press) {
        [super mouseDragged:event];
        return;
    }
    NSPoint start = press.locationInWindow;
    NSPoint location = event.locationInWindow;
    [self setPressed:NSPointInRect([self convertPoint:location fromView:nil], self.bounds)];
    if (hypot(location.x - start.x, location.y - start.y) >= 4.0) {
        self.pressEvent = nil;
        [self setPressed:NO];
        [self beginExportDragWithEvent:press];
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (!self.pressEvent) {
        [super mouseUp:event];
        return;
    }
    self.pressEvent = nil;
    [self setPressed:NO];
    if (NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds)) {
        [self sendAction:self.action to:self.target];
    }
}
#else
- (void)mouseDown:(NSEvent *)event {
    if (!self.enabled || !self.dragFileProvider) {
        [super mouseDown:event];
        return;
    }
    NSPoint start = event.locationInWindow;
    [self setPressed:YES];
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        if (next.type == NSEventTypeLeftMouseUp) {
            [self setPressed:NO];
            if (NSPointInRect([self convertPoint:next.locationInWindow fromView:nil], self.bounds)) {
                [self sendAction:self.action to:self.target];
            }
            return;
        }
        NSPoint location = next.locationInWindow;
        if (hypot(location.x - start.x, location.y - start.y) >= 4.0) {
            [self setPressed:NO];
            [self beginExportDragWithEvent:event];
            return;
        }
    }
}
#endif

/// The image, at most 160 points on its long side, to drag.
static NSImage *STDragPreviewImage(NSImage *image) {
    NSSize size = image.size;
    CGFloat scale = MIN(1.0, 160.0 / MAX(MAX(size.width, size.height), 1.0));
    NSSize dragSize = NSMakeSize(MAX(1.0, round(size.width * scale)), MAX(1.0, round(size.height * scale)));
#if defined(GNUSTEP)
    NSImage *preview = [[NSImage alloc] initWithSize:dragSize];
    [preview lockFocus];
    [image drawInRect:NSMakeRect(0.0, 0.0, dragSize.width, dragSize.height)
             fromRect:NSZeroRect
            operation:NSCompositeSourceOver
             fraction:0.85];
    [preview unlockFocus];
    return preview;
#else
    (void)dragSize;
    return image;
#endif
}

- (void)beginExportDragWithEvent:(NSEvent *)event {
    NSURL *url = self.dragFileProvider();
    NSImage *image = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    if (!image) {
        NSBeep();
        return;
    }
    NSImage *preview = STDragPreviewImage(image);
    NSPoint at = [self convertPoint:event.locationInWindow fromView:nil];
#if defined(GNUSTEP)
    // The classic drag: a file list, which the backend offers as text/uri-list (XDND).
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSDragPboard];
    [pasteboard declareTypes:@[NSFilenamesPboardType] owner:nil];
    [pasteboard setPropertyList:@[url.path] forType:NSFilenamesPboardType];
    NSSize size = preview.size;
    NSPoint origin = NSMakePoint(at.x - size.width * 0.5, at.y + (self.isFlipped ? size.height * 0.5 : -size.height * 0.5));
    [self dragImage:preview at:origin offset:NSZeroSize event:event pasteboard:pasteboard source:self slideBack:YES];
#else
    NSSize size = image.size;
    CGFloat scale = MIN(1.0, 160.0 / MAX(MAX(size.width, size.height), 1.0));
    NSSize dragSize = NSMakeSize(size.width * scale, size.height * scale);
    NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter:url];
    [item setDraggingFrame:NSMakeRect(at.x - dragSize.width * 0.5, at.y - dragSize.height * 0.5,
                                      dragSize.width, dragSize.height)
                  contents:preview];
    NSDraggingSession *session = [self beginDraggingSessionWithItems:@[item] event:event source:self];
    session.animatesToStartingPositionsOnCancelOrFail = YES;
#endif
}

#if defined(GNUSTEP)
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal {
    (void)isLocal;
    return NSDragOperationCopy;
}
#else
- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    (void)session;
    (void)context;
    return NSDragOperationCopy;
}
#endif

@end



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
            logPath = STDefaultLogFilePath();
        }
        logPath = [logPath copy];
    }
    return logPath;
}

/// The variable's current value. GNUstep's -[NSProcessInfo environment] is a snapshot taken at
/// launch, so it misses later setenv() calls (#41).
static NSString *STCurrentEnvironmentValue(const char *name) {
    const char *value = getenv(name);
    return value ? [NSString stringWithUTF8String:value] : nil;
}

static BOOL STScreenshotToolIsWaylandSession(void) {
    NSString *waylandDisplay = STCurrentEnvironmentValue("WAYLAND_DISPLAY");
    if (waylandDisplay.length > 0) {
        return YES;
    }
    NSString *sessionType = [STCurrentEnvironmentValue("XDG_SESSION_TYPE") lowercaseString];
    return [sessionType isEqualToString:@"wayland"];
}

static NSString *STExecutablePathInPATH(NSString *executableName) {
    if (executableName.length == 0) {
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([executableName containsString:@"/"]) {
        return [fileManager isExecutableFileAtPath:executableName] ? executableName : nil;
    }

    NSString *pathValue = STCurrentEnvironmentValue("PATH");
    for (NSString *directory in [pathValue componentsSeparatedByString:@":"]) {
        if (directory.length == 0) {
            continue;
        }
        NSString *candidate = [directory stringByAppendingPathComponent:executableName];
        if ([fileManager isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

static BOOL STMirrorPNGDataToWaylandClipboard(NSData *pngData) {
    if (pngData.length == 0 || !STScreenshotToolIsWaylandSession()) {
        return NO;
    }

    NSString *wlCopyPath = STExecutablePathInPATH(@"wl-copy");
    if (wlCopyPath.length == 0) {
        ScreenshotToolAppendLog(@"Wayland clipboard mirror unavailable: wl-copy not found in PATH");
        return NO;
    }

    NSString *inputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"screenshottool-wlcopy-%@.png", [NSUUID UUID].UUIDString]];
    NSError *writeError = nil;
    if (![pngData writeToFile:inputPath options:NSDataWritingAtomic error:&writeError]) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Wayland clipboard mirror could not stage PNG input at %@ (%@)",
                                 inputPath,
                                 writeError.localizedDescription ?: @"unknown error"]);
        return NO;
    }

    @try {
        NSTask *task = [[NSTask alloc] init];
        NSPipe *errorPipe = [NSPipe pipe];
        task.launchPath = @"/bin/sh";
        task.arguments = @[ @"-c", @"exec \"$1\" --type image/png < \"$2\"", @"sh", wlCopyPath, inputPath ];
        task.standardError = errorPipe;
        [task launch];

        [task waitUntilExit];
        if (task.terminationStatus == 0) {
            ScreenshotToolAppendLog(@"Wayland clipboard mirror succeeded via wl-copy");
            [[NSFileManager defaultManager] removeItemAtPath:inputPath error:NULL];
            return YES;
        }

        NSData *stderrData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
        NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Wayland clipboard mirror failed via wl-copy (status=%d%@%@)",
                                 task.terminationStatus,
                                 stderrText.length > 0 ? @": " : @"",
                                 stderrText.length > 0 ? [stderrText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @""]);
    } @catch (NSException *exception) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Wayland clipboard mirror exception (%@ - %@)",
                                 exception.name ?: @"<no name>",
                                 exception.reason ?: @"<no reason>"]);
    }
    [[NSFileManager defaultManager] removeItemAtPath:inputPath error:NULL];

    return NO;
}

/// Runs wl-paste and returns its output, or nil if it doesn't finish within `timeout`. On GNOME,
/// wl-paste has to get keyboard focus to read the clipboard and can otherwise wait for good; the
/// app mustn't wait with it (#90). The output is read on another queue, so a large image can't
/// fill the pipe and stall wl-paste while we wait.
static NSData *STRunWlPaste(NSString *wlPastePath, NSArray<NSString *> *arguments, NSTimeInterval timeout,
                            int *terminationStatus, NSData **stderrData) {
    NSTask *task = [[NSTask alloc] init];
    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    task.launchPath = wlPastePath;
    task.arguments = arguments;
    task.standardOutput = outputPipe;
    task.standardError = errorPipe;
    [task launch];

    __block NSData *output = nil;
    __block NSData *errors = nil;
    dispatch_group_t readers = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_group_async(readers, queue, ^{
        output = [[outputPipe fileHandleForReading] readDataToEndOfFile];
    });
    dispatch_group_async(readers, queue, ^{
        errors = [[errorPipe fileHandleForReading] readDataToEndOfFile];
    });
    if (dispatch_group_wait(readers, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
        [task terminate];
        // The pipes close when wl-paste exits; give the readers a moment to finish with them.
        dispatch_group_wait(readers, dispatch_time(DISPATCH_TIME_NOW, (int64_t)NSEC_PER_SEC));
        ScreenshotToolAppendLog([NSString stringWithFormat:@"wl-paste %@ didn't answer within %.1fs; stopped it",
                                 [arguments componentsJoinedByString:@" "], timeout]);
        return nil;
    }
    [task waitUntilExit];
    if (terminationStatus) {
        *terminationStatus = task.terminationStatus;
    }
    if (stderrData) {
        *stderrData = errors;
    }
    return output;
}

static NSData *STWaylandClipboardDataForMIMEType(NSString *mimeType) {
    if (mimeType.length == 0 || !STScreenshotToolIsWaylandSession()) {
        return nil;
    }

    NSString *wlPastePath = STExecutablePathInPATH(@"wl-paste");
    if (wlPastePath.length == 0) {
        return nil;
    }

    @try {
        int status = -1;
        NSData *stderrData = nil;
        // Paste is asked for, so allow time for a large image.
        NSData *stdoutData = STRunWlPaste(wlPastePath, @[ @"--type", mimeType ], 10.0, &status, &stderrData);
        if (status == 0 && stdoutData.length > 0) {
            return stdoutData;
        }

        NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
        if (stderrText.length > 0) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Wayland clipboard read failed for %@ (status=%d): %@",
                                     mimeType,
                                     status,
                                     [stderrText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]);
        }
    } @catch (NSException *exception) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Wayland clipboard read exception for %@ (%@ - %@)",
                                 mimeType,
                                 exception.name ?: @"<no name>",
                                 exception.reason ?: @"<no reason>"]);
    }

    return nil;
}

void ScreenshotToolAppendLog(NSString *message) {
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

BOOL STWriteDataAtomically(NSData *data, NSURL *url, NSError **error) {
#if defined(GNUSTEP) && defined(_WIN32)
    // GNUstep's atomic write ends by renaming a temporary file over the target. That rename fails
    // while another process has the target open for a moment (Defender, the search indexer, a
    // thumbnail scan of a file just copied there), and the write then returns NO without an
    // NSError (#261). Retry briefly, and say what most likely happened if it still fails.
    for (NSUInteger attempt = 0; attempt < 6; attempt++) {
        if (attempt > 0) {
            [NSThread sleepForTimeInterval:0.1];
        }
        if ([data writeToURL:url options:NSDataWritingAtomic error:error]) {
            return YES;
        }
    }
    ScreenshotToolAppendLog([NSString stringWithFormat:@"Atomic write to %@ failed after retries", url.path]);
    if (error && !*error) {
        NSString *description = [NSString stringWithFormat:
            @"\"%@\" couldn't be written. It may be open in another program; try again.",
            url.lastPathComponent];
        *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSFileWriteUnknownError
                                 userInfo:@{NSLocalizedDescriptionKey: description, NSFilePathErrorKey: url.path ?: @""}];
    }
    return NO;
#else
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
#endif
}

static NSString *STDebugToolName(ScreenshotCanvasTool tool) {
    switch (tool) {
        case ScreenshotCanvasToolHighlighter:
            return @"Highlighter";
        case ScreenshotCanvasToolPen:
            return @"Pen";
        case ScreenshotCanvasToolEraser:
            return @"Eraser";
        case ScreenshotCanvasToolText:
            return @"Text";
        case ScreenshotCanvasToolSelect:
            return @"Select";
        case ScreenshotCanvasToolArrow:
            return @"Arrow";
        case ScreenshotCanvasToolRectangle:
            return @"Rectangle";
        case ScreenshotCanvasToolStep:
            return @"Step";
        case ScreenshotCanvasToolRedact:
            return @"Redact";
    }
    return @"Unknown";
}

static BOOL STToolUsesColor(ScreenshotCanvasTool tool) {
    return (tool == ScreenshotCanvasToolPen ||
            tool == ScreenshotCanvasToolHighlighter ||
            tool == ScreenshotCanvasToolText ||
            tool == ScreenshotCanvasToolArrow ||
            tool == ScreenshotCanvasToolRectangle ||
            tool == ScreenshotCanvasToolStep);
}

/// Whether a double-click on the tool opens a settings popover. Arrows have none: they use the
/// pen's colour and width.
static BOOL STToolHasSettingsPopover(ScreenshotCanvasTool tool) {
    return (tool == ScreenshotCanvasToolPen ||
            tool == ScreenshotCanvasToolHighlighter ||
            tool == ScreenshotCanvasToolText);
}

/// Arrows and rectangles draw with the pen's colour and width, so their settings are the pen's
/// (#33, #221).
static ScreenshotCanvasTool STSettingsToolForTool(ScreenshotCanvasTool tool) {
    return (tool == ScreenshotCanvasToolArrow || tool == ScreenshotCanvasToolRectangle || tool == ScreenshotCanvasToolStep)
        ? ScreenshotCanvasToolPen : tool;
}

static BOOL STEventIsMouseEvent(NSEvent *event) {
    switch (event.type) {
        case NSEventTypeLeftMouseDown:
        case NSEventTypeLeftMouseUp:
        case NSEventTypeRightMouseDown:
        case NSEventTypeRightMouseUp:
        case NSEventTypeOtherMouseDown:
        case NSEventTypeOtherMouseUp:
            return YES;
        default:
            return NO;
    }
}

/// The event's click count, or 0 if it isn't a mouse button event: AppKit throws when asked for
/// another kind's (the current event of an action sent from the keyboard, say).
static NSInteger STEventClickCount(NSEvent *event) {
    return (event && STEventIsMouseEvent(event)) ? event.clickCount : 0;
}

static NSString *STDebugDescriptionForEvent(NSEvent *event) {
    if (!event) {
        return @"<no NSEvent>";
    }
    NSEventType type = event.type;
    NSInteger clickCount = STEventClickCount(event);
    NSInteger buttonNumber = STEventIsMouseEvent(event) ? event.buttonNumber : 0;
    unsigned long modifiers = (unsigned long)event.modifierFlags;
    NSPoint location = event.locationInWindow;
    NSTimeInterval timestamp = event.timestamp;
    return [NSString stringWithFormat:@"type=%ld button=%ld clickCount=%ld modifiers=0x%lx location=(%.1f, %.1f) timestamp=%.3f",
                                      (long)type,
                                      (long)buttonNumber,
                                      (long)clickCount,
                                      modifiers,
                                      location.x,
                                      location.y,
                                      timestamp];
}

static NSString *STDebugDescriptionForSender(id sender) {
    if (!sender) {
        return @"<nil sender>";
    }
    if ([sender isKindOfClass:[NSToolbarItem class]]) {
        NSToolbarItem *item = (NSToolbarItem *)sender;
        NSString *identifier = item.itemIdentifier ?: @"<no identifier>";
        return [NSString stringWithFormat:@"NSToolbarItem(%@)", identifier];
    }
    return NSStringFromClass([sender class]);
}

static void STApplyAccessibilityLabel(id object, NSString *label) {
    if (!object || label.length == 0) {
        return;
    }
    SEL selector = NSSelectorFromString(@"setAccessibilityLabel:");
    if ([object respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [object performSelector:selector withObject:label];
#pragma clang diagnostic pop
    }
}



#if !defined(GNUSTEP)
/// An empty view the share picker points at, for a click inside a larger view. Clicks go through it.
@interface STShareAnchorView : NSView
@end

@implementation STShareAnchorView

- (nullable NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}

@end
#endif

@interface STStatusTextField : NSTextField
@end

@implementation STStatusTextField

- (NSUndoManager *)undoManager {
    return nil;
}

#if defined(GNUSTEP)
/// Asks the opaque view behind the field to redraw too, so the old text is erased (#290). GNUstep
/// forwards a see-through view's invalid rect to that view only when the rect grows. At a
/// fractional scale (150%) the rect isn't always cleared after drawing, because it was rounded to
/// device pixels and back. Then later changes redraw the text alone, over the old one.
- (void)setStringValue:(NSString *)value {
    [super setStringValue:value];
    NSView *opaqueView = [self opaqueAncestor];
    if (opaqueView && opaqueView != self) {
        [opaqueView setNeedsDisplayInRect:[self convertRect:self.bounds toView:opaqueView]];
    }
}
#endif

@end

@interface AppDelegate () <NSToolbarDelegate, ToolSettingsPopoverControllerDelegate, TextToolPopoverControllerDelegate, ZoomPopoverControllerDelegate, PreferencesWindowControllerDelegate,
#if defined(GNUSTEP)
    GPStandardUpdaterControllerDelegate,
#else
    NSSharingServicePickerToolbarItemDelegate, NSMenuDelegate,
#endif
#if !defined(GNUSTEP) || defined(ST_HAVE_LIBS_SHARING)
    NSSharingServicePickerDelegate, NSSharingServiceDelegate,
#endif
    STTextOptionsBarDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSScrollView *scrollView;
/// Shown instead of the canvas while no image is open (#55).
@property (nonatomic, strong) NSView *emptyStateView;
/// Whether the empty state's Recent cards have been filled since the window was made (#221).
@property (nonatomic, assign) BOOL emptyStateRecentsLoaded;
@property (nonatomic, strong) ScreenshotCanvasView *canvasView;
@property (nonatomic, strong) NSToolbar *toolbar;
@property (nonatomic, strong) NSMutableDictionary<NSToolbarItemIdentifier, NSToolbarItem *> *toolbarItemsByIdentifier;
@property (nonatomic, strong) STToolbarSegmentedControl *toolbarToolSegmentedControl;
@property (nonatomic, strong) STToolbarColorWellView *toolbarColorWellView;
@property (nonatomic, strong) STToolbarZoomButtonView *zoomToolbarButtonView;
@property (nonatomic, strong) NSPopUpButton *zoomPopUpButton;
@property (nonatomic, strong) NSView *zoomToolbarContainer;
@property (nonatomic, strong) NSTextField *zoomToolbarLabel;
@property (nonatomic, strong) NSView *statusBarView;
@property (nonatomic, strong) NSTextField *statusTextField;
@property (nonatomic, strong) NSTimer *statusClearTimer;
@property (nonatomic, strong) NSWindow *hudWindow;
@property (nonatomic, strong) STHudView *hudView;
@property (nonatomic, strong) NSTimer *hudDismissTimer;
@property (nonatomic, strong) NSTimer *hudFadeTimer;
@property (nonatomic, copy) void (^hudFadeCompletion)(void);
@property (nonatomic, assign) NSTimeInterval hudFadeStartTime;
@property (nonatomic, assign) NSTimeInterval hudFadeDuration;
@property (nonatomic, assign) CGFloat hudFadeStartAlpha;
@property (nonatomic, assign) CGFloat hudFadeTargetAlpha;
@property (nonatomic, strong) NSView *statusZoomContainer;
@property (nonatomic, strong) NSButton *statusZoomOutButton;
@property (nonatomic, strong) NSSlider *statusZoomSlider;
@property (nonatomic, strong) NSButton *statusZoomInButton;
@property (nonatomic, strong) NSTextField *statusZoomLabel;
@property (nonatomic, strong) NSButton *statusZoomFitButton;
/// The file the status bar's size was read from, and its size as shown (#221).
@property (nonatomic, strong, nullable) NSURL *statusFileSizeURL;
@property (nonatomic, copy, nullable) NSString *statusFileSizeText;
@property (nonatomic, assign) CGFloat penDefaultWidth;
@property (nonatomic, assign) CGFloat highlighterDefaultWidth;
@property (nonatomic, strong) NSColor *penDefaultColor;
@property (nonatomic, strong) NSColor *highlighterDefaultColor;
@property (nonatomic, strong) NSColor *textDefaultColor;
@property (nonatomic, strong) NSFont *textDefaultFont;
@property (nonatomic, assign) MarkupTextStyle textDefaultStyle;
@property (nonatomic, assign) STTextSizePreset textDefaultSizePreset;
@property (nonatomic, assign) NSTextAlignment textDefaultAlignment;
@property (nonatomic, strong) STTextOptionsBar *textOptionsBar;
/// How far showing the text bar scrolled the canvas, which hiding it undoes.
@property (nonatomic, assign) CGFloat textBarScrollDelta;
@property (nonatomic, strong) ToolSettingsPopoverController *penPopoverController;
@property (nonatomic, strong) ToolSettingsPopoverController *highlighterPopoverController;
@property (nonatomic, strong) TextToolPopoverController *textPopoverController;
@property (nonatomic, strong) ZoomPopoverController *zoomPopoverController;
@property (nonatomic, strong) PreferencesWindowController *preferencesWindowController;
@property (nonatomic, assign) ScreenshotCanvasTool lastWidthTool;
@property (nonatomic, copy) NSString *defaultSaveDirectory;
@property (nonatomic, assign) BOOL statusBarVisiblePreference;
@property (nonatomic, assign) BOOL selectionBarPreference;
/// Crop, Copy and Redact next to the region selection, over the canvas.
@property (nonatomic, strong, nullable) STSelectionActionBar *selectionActionBar;
#if !defined(GNUSTEP)
/// Where the open share picker points, when it was opened from a click inside the canvas.
@property (nonatomic, strong, nullable) NSView *shareAnchorView;
#endif
@property (nonatomic, copy) NSString *pendingOpenPath;
@property (nonatomic, strong) NSURL *currentImageURL;
/// The project file this window was opened from or last saved to (#32).
@property (nonatomic, strong, nullable) NSURL *currentProjectURL;
/// The canvas's fingerprint when it was last opened or saved; a different one means unsaved changes.
@property (nonatomic, strong, nullable) NSData *savedAnnotationFingerprint;
/// The annotations as they were when closing the window settled them (saved or discarded), so the
/// quit that can follow the close doesn't ask again.
@property (nonatomic, strong) NSData *closeSettledAnnotationFingerprint;
@property (nonatomic, strong) NSMutableArray<NSString *> *recentDocumentPaths;
@property (nonatomic, strong) NSMenu *openRecentMenu;
#if !defined(GNUSTEP)
/// On the application's delegate: the other document windows' controllers (see Windows below).
@property (nonatomic, strong) NSMutableArray<AppDelegate *> *documentWindows;
/// The target of the menus' document commands, which it hands to the front window's controller.
@property (nonatomic, strong) id documentRouter;
#endif
/// On the application's delegate: the user's custom actions, read at launch, their choices once
/// listed, and the ones running now (#221).
@property (nonatomic, copy, nullable) NSArray<STCustomAction *> *customActions;
@property (nonatomic, strong, nullable) NSMutableDictionary<NSString *, NSArray<NSString *> *> *customActionChoices;
@property (nonatomic, strong, nullable) NSMutableSet<NSString *> *runningCustomActions;
/// What a toolbar control or menu delegate stands for: its custom action.
@property (nonatomic, strong, nullable) NSMapTable<id, STCustomAction *> *customActionsBySender;
@property (nonatomic, strong) NSUndoManager *undoManager;
#if defined(GNUSTEP)
@property (nonatomic, strong) GPStandardUpdaterController *updaterController;
#elif ST_USES_SPARKLE
@property (nonatomic, strong) SPUStandardUpdaterController *sparkleController;
#endif
/// Whether the clipboard held an image when last checked, and when (#76).
@property (nonatomic, assign) BOOL clipboardHadImage;
@property (nonatomic, assign) BOOL validatingUndoToolbarItems;
/// The window is out of the way of the desktop's screenshot tool.
@property (nonatomic, assign) BOOL hiddenForScreenshot;
@property (nonatomic, assign) NSTimeInterval clipboardCheckedAt;
- (NSData *)clipboardPNGDataForPasteAsNewImage;
- (BOOL)clipboardHasImage;
- (void)refreshPasteAvailability;
- (NSURL *)temporaryClipboardImageURLForPNGData:(NSData *)pngData;
- (BOOL)isTemporaryClipboardImageURL:(NSURL *)url;
- (BOOL)launchNewWindowForImageAtURL:(NSURL *)url;
- (void)showTransientFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration;
@end

#if !defined(GNUSTEP)
/// Open… in the empty state: AppKit's split button, whose arrow lists recent files (GNUstep has
/// STSplitButton). NSComboButton has no key equivalent, so this one takes Return itself, as the
/// plain Open… button it replaces did.
API_AVAILABLE(macos(13.0))
@interface STOpenComboButton : NSComboButton
@end

@implementation STOpenComboButton
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSEventModifierFlags modifiers = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption |
                                                            NSEventModifierFlagControl | NSEventModifierFlagShift);
    if (modifiers == 0 && [event.charactersIgnoringModifiers isEqualToString:@"\r"] &&
        self.isEnabled && self.window && !self.isHiddenOrHasHiddenAncestor) {
        [self sendAction:self.action to:self.target];
        return YES;
    }
    return [super performKeyEquivalent:event];
}
@end

/// The controller of the frontmost document window, or the application's delegate if none is
/// showing (its commands are then disabled: it has no image).
static AppDelegate *STFrontDocument(void) {
    for (NSWindow *window in @[NSApp.mainWindow ?: (id)[NSNull null], NSApp.keyWindow ?: (id)[NSNull null]]) {
        if ([window isKindOfClass:[NSWindow class]] && [window.delegate isKindOfClass:[AppDelegate class]]) {
            return (AppDelegate *)window.delegate;
        }
    }
    for (NSWindow *window in [NSApp orderedWindows]) {
        if (window.isVisible && [window.delegate isKindOfClass:[AppDelegate class]]) {
            return (AppDelegate *)window.delegate;
        }
    }
    return [NSApp.delegate isKindOfClass:[AppDelegate class]] ? (AppDelegate *)NSApp.delegate : nil;
}

/// The menus' document commands (Save, Undo, Zoom, ...) go to the front window's controller,
/// validation included. A router rather than the responder chain, so Undo keeps choosing
/// between typing and the canvas itself (-activeUndoManager).
@interface STDocumentRouter : NSObject
@end

@implementation STDocumentRouter

- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [STFrontDocument() respondsToSelector:selector];
}

- (id)forwardingTargetForSelector:(SEL)selector {
    (void)selector;
    return STFrontDocument();
}

@end
#endif

@interface AppDelegate (STCustomActionMenus)
- (void)fillChoicesMenu:(NSMenu *)menu forCustomAction:(STCustomAction *)action;
- (NSString *)toolTipForCustomAction:(STCustomAction *)action;
- (nullable STCustomAction *)customActionForToolbarIdentifier:(NSString *)identifier;
@end

/// Lists a custom action's choices each time its menu opens. (GNUstep's NSMenuDelegate has no
/// optional methods, so it doesn't declare the protocol there.)
#if defined(GNUSTEP)
@interface STCustomActionMenuDelegate : NSObject
#else
@interface STCustomActionMenuDelegate : NSObject <NSMenuDelegate>
#endif
@property (nonatomic, strong) STCustomAction *action;
@property (nonatomic, weak) AppDelegate *controller;
@end

@implementation STCustomActionMenuDelegate

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [self.controller fillChoicesMenu:menu forCustomAction:self.action];
}

@end

@implementation AppDelegate

- (void)applyToolTipToToolbarItem:(NSToolbarItem *)item source:(NSString *)source {
    if (!item) {
        return;
    }
    NSString *identifier = item.itemIdentifier;
    NSString *tip = [self toolTipForIdentifier:identifier];
    BOOL hasCustomTip = (tip.length > 0);

    item.toolTip = hasCustomTip ? tip : nil;
    if (item.view) {
        [item.view setToolTip:(hasCustomTip ? tip : nil)];
    }

    if (hasCustomTip) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"applyToolTip %@ -> %@ (source=%@)", identifier, tip, source ?: @"<nil>"]);
    } else {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"applyToolTip %@ cleared tooltip (source=%@)", identifier, source ?: @"<nil>"]);
    }
}

- (NSString *)toolTipForIdentifier:(NSToolbarItemIdentifier)identifier {
    if ([identifier isEqualToString:ToolbarItemTools]) {
        return nil; // Each tool's segment has its own tip.
    }
    if ([identifier hasPrefix:ToolbarItemCustomActionPrefix]) {
        STCustomAction *action = [self customActionForToolbarIdentifier:identifier];
        return action ? [self toolTipForCustomAction:action] : nil;
    }
    if ([identifier isEqualToString:ToolbarItemHighlighter]) {
        return @"Highlighter Tool — double-click to configure";
    }
    if ([identifier isEqualToString:ToolbarItemPen]) {
        return @"Pen Tool — double-click to configure";
    }
    if ([identifier isEqualToString:ToolbarItemArrow]) {
        return @"Arrow Tool";
    }
    if ([identifier isEqualToString:ToolbarItemRectangle]) {
        return @"Rectangle Tool";
    }
    if ([identifier isEqualToString:ToolbarItemStep]) {
        return @"Numbered Step Tool";
    }
    if ([identifier isEqualToString:ToolbarItemRedact]) {
        return @"Redact Tool";
    }
    if ([identifier isEqualToString:ToolbarItemText]) {
        return @"Text Tool — double-click to configure";
    }
    if ([identifier isEqualToString:ToolbarItemSelect]) {
        return @"Select Tool";
    }
    if ([identifier isEqualToString:ToolbarItemEraser]) {
        return @"Eraser Tool";
    }
    if ([identifier isEqualToString:ToolbarItemCopy]) {
#if defined(GNUSTEP)
        return @"Copy Image";
#else
        return @"Copy Image — or drag it into another app";
#endif
    }
    if ([identifier isEqualToString:ToolbarItemSave]) {
        return @"Save Image As…";
    }
    if ([identifier isEqualToString:ToolbarItemUndo]) {
        return @"Undo";
    }
    if ([identifier isEqualToString:ToolbarItemRedo]) {
        return @"Redo";
    }
    if ([identifier isEqualToString:ToolbarItemPreferences]) {
        return @"Preferences";
    }
    if ([identifier isEqualToString:ToolbarItemColor]) {
        switch (self.canvasView.activeTool) {
            // One control for the tool's style: colour and width (#54).
            case ScreenshotCanvasToolPen:
                return [NSString stringWithFormat:@"Pen color and width (%.0f px) — click to change", [self currentWidthForTool:ScreenshotCanvasToolPen]];
            case ScreenshotCanvasToolArrow:
                return [NSString stringWithFormat:@"Arrow color and width (%.0f px) — click to change", [self currentWidthForTool:ScreenshotCanvasToolArrow]];
            case ScreenshotCanvasToolRectangle:
                return [NSString stringWithFormat:@"Rectangle color and width (%.0f px) — click to change", [self currentWidthForTool:ScreenshotCanvasToolRectangle]];
            case ScreenshotCanvasToolStep:
                return [NSString stringWithFormat:@"Step color and size (%.0f px) — click to change", [self currentWidthForTool:ScreenshotCanvasToolStep]];
            case ScreenshotCanvasToolHighlighter:
                return [NSString stringWithFormat:@"Highlighter color and width (%.0f px) — click to change", [self currentWidthForTool:ScreenshotCanvasToolHighlighter]];
            case ScreenshotCanvasToolText:
                return @"Text color and font — click to change";
            default:
                return @"Current tool has no color settings";
        }
    }
    if ([identifier isEqualToString:ToolbarItemZoom]) {
        if (![self.canvasView hasImage]) {
            return @"Zoom unavailable until an image is loaded";
        }
        NSString *value = self.canvasView.isFitToWindow ? @"Fit to Window" : [self displayStringForScale:self.canvasView.displayZoomScale];
        return [NSString stringWithFormat:@"Zoom: %@ — click to adjust", value];
    }
    return nil;
}

- (void)loadRecentDocumentPathsFromDefaults {
    NSArray *storedPaths = [[NSUserDefaults standardUserDefaults] arrayForKey:STDefaultsRecentDocumentsKey];
    NSMutableArray<NSString *> *paths = [[NSMutableArray alloc] init];
    NSMutableSet<NSString *> *seenPaths = [[NSMutableSet alloc] init];

    for (id candidate in storedPaths) {
        if (![candidate isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *path = [(NSString *)candidate stringByStandardizingPath];
        if (path.length == 0 || [seenPaths containsObject:path]) {
            continue;
        }
        [paths addObject:path];
        [seenPaths addObject:path];
        if (paths.count >= STRecentDocumentLimit) {
            break;
        }
    }

    self.recentDocumentPaths = paths;
}

- (void)ensureRecentDocumentPathsLoaded {
    if (!self.recentDocumentPaths) {
        [self loadRecentDocumentPathsFromDefaults];
    }
}

- (void)persistRecentDocumentPaths {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (self.recentDocumentPaths.count > 0) {
        [defaults setObject:[self.recentDocumentPaths copy] forKey:STDefaultsRecentDocumentsKey];
    } else {
        [defaults removeObjectForKey:STDefaultsRecentDocumentsKey];
    }
    [defaults synchronize];
}

- (NSString *)recentDocumentMenuTitleForPath:(NSString *)path duplicateLeafCounts:(NSDictionary<NSString *, NSNumber *> *)duplicateLeafCounts {
    NSString *leafName = [[NSFileManager defaultManager] displayNameAtPath:path];
    if (leafName.length == 0) {
        leafName = path.lastPathComponent;
    }
    if (leafName.length == 0) {
        leafName = path;
    }

    if ([duplicateLeafCounts[leafName] integerValue] > 1) {
        NSString *directory = [[path stringByDeletingLastPathComponent] stringByAbbreviatingWithTildeInPath];
        if (directory.length > 0) {
            return [NSString stringWithFormat:@"%@ (%@)", leafName, directory];
        }
    }
    return leafName;
}

- (void)rebuildOpenRecentMenu {
#if !defined(GNUSTEP)
    // Each window's empty state lists them too, from Open…'s arrow.
    for (AppDelegate *document in [self allDocumentControllers]) {
        NSMenu *recent = [document emptyStateRecentMenu];
        if (recent) {
            [self fillRecentDocumentsMenu:recent];
        }
        [document refreshEmptyStateRecents];
    }
#else
    [self refreshEmptyStateRecents];
#endif
    if (!self.openRecentMenu) {
        return;
    }
    [self fillRecentDocumentsMenu:self.openRecentMenu];
}

/// File > Open Recent's items; the empty state's Open button shows a menu of its own with them.
- (NSMenu *)newRecentDocumentsMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    [menu setAutoenablesItems:NO];
    [self fillRecentDocumentsMenu:menu];
    return menu;
}

- (void)fillRecentDocumentsMenu:(NSMenu *)menu {
    [self ensureRecentDocumentPathsLoaded];
    [menu removeAllItems];

    if (self.recentDocumentPaths.count == 0) {
        NSMenuItem *emptyItem = [[NSMenuItem alloc] initWithTitle:STRecentDocumentsEmptyTitle
                                                           action:NULL
                                                    keyEquivalent:@""];
        [emptyItem setEnabled:NO];
        [menu addItem:emptyItem];
        return;
    }

    NSMutableDictionary<NSString *, NSNumber *> *duplicateLeafCounts = [[NSMutableDictionary alloc] init];
    for (NSString *path in self.recentDocumentPaths) {
        NSString *leafName = [[NSFileManager defaultManager] displayNameAtPath:path];
        if (leafName.length == 0) {
            leafName = path.lastPathComponent;
        }
        if (leafName.length == 0) {
            leafName = path;
        }
        NSInteger count = [duplicateLeafCounts[leafName] integerValue] + 1;
        duplicateLeafCounts[leafName] = @(count);
    }

    for (NSString *path in self.recentDocumentPaths) {
        NSString *title = [self recentDocumentMenuTitleForPath:path duplicateLeafCounts:duplicateLeafCounts];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(openRecentDocument:)
                                               keyEquivalent:@""];
        [item setTarget:self];
        [item setRepresentedObject:path];
        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *clearItem = [[NSMenuItem alloc] initWithTitle:STRecentDocumentsClearTitle
                                                       action:@selector(clearRecentDocuments:)
                                                keyEquivalent:@""];
    [clearItem setTarget:self];
    [menu addItem:clearItem];
}

- (void)addRecentDocumentURL:(NSURL *)url {
#if !defined(GNUSTEP)
    AppDelegate *application = [self applicationController];
    if (application != self) {
        // The Open Recent menu is the application delegate's.
        [application addRecentDocumentURL:url];
        return;
    }
#endif
    NSString *path = STStandardizedRecentDocumentPath(url);
    if (path.length == 0) {
        return;
    }

    [self ensureRecentDocumentPathsLoaded];
    [self.recentDocumentPaths removeObject:path];
    [self.recentDocumentPaths insertObject:path atIndex:0];
    while (self.recentDocumentPaths.count > STRecentDocumentLimit) {
        [self.recentDocumentPaths removeLastObject];
    }

    [self persistRecentDocumentPaths];
    [self rebuildOpenRecentMenu];
#if !defined(GNUSTEP)
    // The system's list too: the Dock icon's menu and Recent Items.
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:url];
#endif
}

- (void)removeRecentDocumentPath:(NSString *)path {
    NSString *standardizedPath = [path stringByStandardizingPath];
    if (standardizedPath.length == 0) {
        return;
    }

    [self ensureRecentDocumentPathsLoaded];
    NSUInteger index = [self.recentDocumentPaths indexOfObject:standardizedPath];
    if (index == NSNotFound) {
        return;
    }

    [self.recentDocumentPaths removeObjectAtIndex:index];
    [self persistRecentDocumentPaths];
    [self rebuildOpenRecentMenu];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    ScreenshotToolAppendLog(@"ScreenshotTool will finish launching");
    [self setupMenus];
}

#if !defined(GNUSTEP)
#pragma mark - Windows (macOS)

// On macOS each document has a window of its own, with an AppDelegate instance as its
// controller. The application's delegate (made in main.m) is one of them too, and also owns what
// is the application's: the menus, Open Recent, Preferences, the updater, quitting. GNUstep keeps
// one window per process, as its menus and themes expect.

/// The instance that is the application's delegate, which keeps the list of document windows.
- (AppDelegate *)applicationController {
    id delegate = NSApp.delegate;
    return [delegate isKindOfClass:[AppDelegate class]] ? (AppDelegate *)delegate : self;
}

- (NSArray<AppDelegate *> *)allDocumentControllers {
    AppDelegate *application = [self applicationController];
    return [@[application] arrayByAddingObjectsFromArray:application.documentWindows ?: @[]];
}

/// The menu commands that act on a document: they go to the front window's controller.
- (void)routeDocumentCommandsInMenu:(NSMenu *)menu {
    static NSSet<NSString *> *documentCommands = nil;
    if (!documentCommands) {
        documentCommands = [NSSet setWithArray:@[@"saveDocumentAs:", @"saveProject:", @"undo:", @"redo:",
                                                 @"cropImage:", @"zoomFitToWindow:", @"zoomPreset25:",
                                                 @"zoomPreset50:", @"zoomPreset100:", @"zoomPreset200:",
                                                 @"zoomIn:", @"zoomOut:", @"runCustomAction:",
                                                 @"redactSelection:", @"duplicateAnnotations:",
                                                 @"bringAnnotationsToFront:", @"sendAnnotationsToBack:"]];
    }
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action && [documentCommands containsObject:NSStringFromSelector(item.action)]) {
            item.target = self.documentRouter;
        }
        if (item.submenu) {
            [self routeDocumentCommandsInMenu:item.submenu];
        }
    }
}

/// A new, empty document window, cascaded from the front one, not shown yet.
- (AppDelegate *)makeDocumentWindow {
    AppDelegate *document = [[AppDelegate alloc] init];
    [document setupWindowAndContent];
    [document setupToolbar];
    document.lastWidthTool = ScreenshotCanvasToolHighlighter;
    [document loadToolSettingsFromDefaults];
    [document selectTool:ScreenshotCanvasToolHighlighter];
    [document reflectZoomSelection];
    [document refreshPasteAvailability];

    NSWindow *front = STFrontDocument().window;
    if (front.isVisible) {
        NSPoint topLeft = [front cascadeTopLeftFromPoint:NSMakePoint(NSMinX(front.frame), NSMaxY(front.frame))];
        [document.window setFrameTopLeftPoint:topLeft];
    }
    if (!self.documentWindows) {
        self.documentWindows = [[NSMutableArray alloc] init];
    }
    [self.documentWindows addObject:document];
    return document;
}

- (IBAction)newDocumentWindow:(id)sender {
    (void)sender;
    AppDelegate *document = [[self applicationController] makeDocumentWindow];
    [document.window makeKeyAndOrderFront:nil];
}

/// Opens `url` in a window: the one already showing it, an empty one (`preferred` first), or a
/// new one.
- (BOOL)openURLInDocumentWindow:(NSURL *)url preferring:(nullable AppDelegate *)preferred {
    NSString *path = [url.path stringByStandardizingPath];
    for (AppDelegate *document in [self allDocumentControllers]) {
        NSURL *shown = document.currentProjectURL ?: document.currentImageURL;
        if (document.window.isVisible && path.length > 0 && [[shown.path stringByStandardizingPath] isEqualToString:path]) {
            [document.window makeKeyAndOrderFront:nil];
            return YES;
        }
    }

    AppDelegate *target = nil;
    AppDelegate *front = STFrontDocument();
    if (preferred && ![preferred.canvasView hasImage]) {
        target = preferred;
    } else if (front.window.isVisible && ![front.canvasView hasImage]) {
        target = front;
    } else if (!self.window.isVisible) {
        // This window was closed, which settled its annotations: use it again.
        target = self;
    }
    if (target) {
        BOOL opened = [target openImageAtURL:url];
        [target.window makeKeyAndOrderFront:nil];
        return opened;
    }

    AppDelegate *document = [self makeDocumentWindow];
    // Opened before it's shown, so the window appears at the image's size.
    if (![document openImageAtURL:url]) {
        [self.documentWindows removeObject:document];
        return NO;
    }
    [document.window makeKeyAndOrderFront:nil];
    return YES;
}

/// A document window's controller goes when its window closes; the application delegate's stays.
- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object != self.window) {
        return;
    }
    AppDelegate *application = [self applicationController];
    if (application != self && [application.documentWindows containsObject:self]) {
        // Nothing may keep a closed window's controller: its observers, timers and pending calls.
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [NSObject cancelPreviousPerformRequestsWithTarget:self];
        [self.statusClearTimer invalidate];
        [self.hudDismissTimer invalidate];
        [self.hudFadeTimer invalidate];
        [self.canvasView clearSelection];
        // After the close finishes, which still needs this controller.
        [application performSelector:@selector(removeDocumentWindow:) withObject:self afterDelay:0.0];
    }
}

- (void)removeDocumentWindow:(AppDelegate *)document {
    // AppKit holds on to a closed window for a while (macOS 26's scroll edge effects reach
    // across windows); emptied, it doesn't keep the canvas, its layers and the image with it.
    [document.window setToolbar:nil];
    [document.window setContentView:nil];
    [self.documentWindows removeObject:document];
}

#pragma mark - Drag out, share and drop (macOS)

- (NSToolbarItem *)dragExportCopyToolbarItem {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ToolbarItemCopy];
    item.label = @"Copy";
    item.paletteLabel = @"Copy";
    NSImage *image = [self baselineToolbarImageNamed:@"CopyImage" active:NO];
    STDragExportButton *button = [STDragExportButton buttonWithImage:(image ?: [[NSImage alloc] init])
                                                              target:self
                                                              action:@selector(copy:)];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    __weak AppDelegate *weakSelf = self;
    button.dragFileProvider = ^NSURL * {
        return [weakSelf exportAnnotatedImageToTemporaryFile];
    };
    STApplyAccessibilityLabel(button, @"Copy image");
    item.view = button;
    item.toolTip = [self toolTipForIdentifier:ToolbarItemCopy];
    return item;
}

/// AppKit asks for these whenever it validates the toolbar (after each undoable change, typing
/// included), not only when Share is clicked. So hand it a provider that exports the image only
/// when a service asks for it: exporting flattens the image, which would end a label being edited.
- (NSArray *)itemsForSharingServicePickerToolbarItem:(NSSharingServicePickerToolbarItem *)pickerToolbarItem {
    (void)pickerToolbarItem;
    return [self shareItemProviders];
}

/// What every share picker shares: one provider of the PNG a share sends, which exports it only
/// when a service asks for it (exporting flattens the image and ends a label being edited).
- (NSArray *)shareItemProviders {
    if (![self.canvasView hasImage]) {
        return @[];
    }
    NSItemProvider *provider = [[NSItemProvider alloc] init];
    NSString *name = [[(self.currentImageURL ?: self.currentProjectURL) lastPathComponent] stringByDeletingPathExtension];
    provider.suggestedName = name.length > 0 ? name : @"Screenshot";
    __weak AppDelegate *weakSelf = self;
    [provider registerFileRepresentationForTypeIdentifier:@"public.png"
                                              fileOptions:0
                                               visibility:NSItemProviderRepresentationVisibilityAll
                                              loadHandler:^NSProgress *(void (^completionHandler)(NSURL *, BOOL, NSError *)) {
        __block NSURL *url = nil;
        void (^export)(void) = ^{
            url = [weakSelf exportAnnotatedImageToTemporaryFile];
        };
        if ([NSThread isMainThread]) {
            export();
        } else {
            dispatch_sync(dispatch_get_main_queue(), export);
        }
        completionHandler(url, NO, url ? nil : [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil]);
        return nil;
    }];
    return @[provider];
}

/// The Share menu has no key equivalents. Saying so keeps AppKit from calling -menuNeedsUpdate:
/// to look for one on every key command, which would export (and end a label being edited).
- (BOOL)menuHasKeyEquivalent:(NSMenu *)menu forEvent:(NSEvent *)event target:(id *)target action:(SEL *)action {
    (void)menu;
    (void)event;
    (void)target;
    (void)action;
    return NO;
}

/// File > Share lists the services for the annotated image each time it opens.
- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu == [self emptyStateRecentMenu]) {
        // The empty state's recent files, as File > Open Recent lists them.
        [[self applicationController] fillRecentDocumentsMenu:menu];
        return;
    }
    if (![menu.title isEqualToString:@"Share"]) {
        return;
    }
    [menu removeAllItems];
    NSURL *url = [(STFrontDocument() ?: self) exportAnnotatedImageToTemporaryFile];
    if (!url) {
        NSMenuItem *none = [menu addItemWithTitle:@"No Image to Share" action:NULL keyEquivalent:@""];
        none.enabled = NO;
        return;
    }
    for (NSSharingService *service in [NSSharingService sharingServicesForItems:@[url]]) {
        NSMenuItem *item = [menu addItemWithTitle:service.menuItemTitle
                                           action:@selector(shareFromMenuItem:)
                                    keyEquivalent:@""];
        item.image = service.image;
        item.target = self;
        item.representedObject = @[service, url];
    }
    // The custom actions after the system's services, as the share picker lists them.
    AppDelegate *document = STFrontDocument() ?: self;
    NSArray<STCustomAction *> *actions = [document loadedCustomActions];
    if (actions.count > 0) {
        [menu addItem:[NSMenuItem separatorItem]];
    }
    for (STCustomAction *action in actions) {
        NSMenuItem *item = [document menuItemForCustomAction:action];
        item.image = [document shareImageForCustomAction:action];
        [menu addItem:item];
    }
}

/// The menu of the empty state's Open… split button, if it has one.
- (NSMenu *)emptyStateRecentMenu {
    if (@available(macOS 13.0, *)) {
        NSComboButton *open = [self.emptyStateView viewWithTag:4];
        return [open isKindOfClass:[NSComboButton class]] ? open.menu : nil;
    }
    return nil;
}

- (void)shareFromMenuItem:(NSMenuItem *)sender {
    NSArray *payload = sender.representedObject;
    NSSharingService *service = payload.firstObject;
    NSURL *url = payload.lastObject;
    if ([service isKindOfClass:[NSSharingService class]] && [url isKindOfClass:[NSURL class]]) {
        AppDelegate *document = STFrontDocument() ?: self;
        service.delegate = document;
        [document prepareSharingService:service];
        [service performWithItems:@[url]];
    }
}

/// The image file or project a drag carries, if any.
- (nullable NSURL *)openableFileURLFromPasteboard:(NSPasteboard *)pasteboard {
    NSArray<NSURL *> *urls = [pasteboard readObjectsForClasses:@[[NSURL class]]
                                                       options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    for (NSURL *url in urls) {
        NSString *extension = url.pathExtension.lowercaseString;
        if (STURLIsProject(url) || [STOpenableImageFileTypes() containsObject:extension]) {
            return url;
        }
    }
    return nil;
}

- (NSDragOperation)dragOperationForDraggingInfo:(id<NSDraggingInfo>)sender {
    // Not the image being dragged out of this window.
    if ([[sender draggingSource] isKindOfClass:[STDragExportButton class]]) {
        return NSDragOperationNone;
    }
    NSPasteboard *pasteboard = [sender draggingPasteboard];
    if ([self openableFileURLFromPasteboard:pasteboard] || [NSImage canInitWithPasteboard:pasteboard]) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return [self dragOperationForDraggingInfo:sender];
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return [self dragOperationForDraggingInfo:sender];
}

/// A dropped image file or project opens like Open…; a dropped image without a file (from a
/// browser, say) opens untitled, like Paste.
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    if ([self dragOperationForDraggingInfo:sender] == NSDragOperationNone) {
        return NO;
    }
    NSPasteboard *pasteboard = [sender draggingPasteboard];
    NSURL *url = [self openableFileURLFromPasteboard:pasteboard];
    NSData *pngData = nil;
    if (!url) {
        NSImage *image = [[NSImage alloc] initWithPasteboard:pasteboard];
        pngData = image ? [self pngDataForImage:image] : nil;
        if (pngData.length == 0) {
            return NO;
        }
    }
    // After the drop finishes, so an unsaved-changes alert doesn't run inside the drag.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self confirmProceedingWithUnsavedChanges]) {
            return;
        }
        NSURL *target = url ?: [self temporaryClipboardImageURLForPNGData:pngData];
        if (target) {
            [self openImageAtURL:target];
        }
    });
    return YES;
}

- (void)showHelp:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/danjboyd/ScreenshotTool#readme"]];
}
#endif

/// Files dropped from Explorer (Windows): the first image or project among them opens like Open…,
/// after asking about unsaved changes. Other files are ignored.
- (void)openDroppedFilePaths:(NSArray<NSString *> *)paths {
    for (NSString *path in paths) {
        NSURL *url = [NSURL fileURLWithPath:path];
        if (!STURLIsProject(url) && ![STOpenableImageFileTypes() containsObject:url.pathExtension.lowercaseString]) {
            continue;
        }
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Dropped file %@", path]);
        if ([self confirmProceedingWithUnsavedChanges]) {
            [self openImageAtURL:url];
            [self.window makeKeyAndOrderFront:nil];
        }
        return;
    }
    ScreenshotToolAppendLog(@"Dropped files hold no image or project to open");
}

- (void)showAboutPanel:(id)sender {
    (void)sender;
    NSMutableDictionary *options = [[NSMutableDictionary alloc] init];
    NSString *appName = STInfoStringForKey(@"ApplicationName") ?: [[NSProcessInfo processInfo] processName];
    if (appName) {
        options[@"ApplicationName"] = appName;
    }
    NSString *description = STInfoStringForKey(@"ApplicationDescription");
    if (description) {
        options[@"ApplicationDescription"] = description;
    }
    NSString *release = STInfoStringForKey(@"ApplicationRelease") ?: STInfoStringForKey(@"ApplicationVersion");
    if (release) {
        options[@"ApplicationRelease"] = release;
    }
    NSString *fullVersion = STInfoStringForKey(@"FullVersionID") ?: STInfoStringForKey(@"Version") ?: STInfoStringForKey(@"CFBundleVersion");
    if (fullVersion) {
        options[@"FullVersionID"] = fullVersion;
    }
    id authors = STInfoValueForKey(@"Authors");
    if ([authors isKindOfClass:[NSArray class]] && [authors count] > 0) {
        options[@"Authors"] = authors;
    } else if ([authors isKindOfClass:[NSString class]]) {
        options[@"Authors"] = @[ authors ];
    }
    NSString *copyright = STInfoStringForKey(@"Copyright") ?: STInfoStringForKey(@"NSHumanReadableCopyright");
    if (copyright) {
        options[@"Copyright"] = copyright;
    }
    NSString *license = STInfoStringForKey(@"CopyrightDescription") ?: STInfoStringForKey(@"ApplicationLicense");
    if (license) {
        options[@"CopyrightDescription"] = license;
    }
    NSString *url = STInfoStringForKey(@"URL");
    if (url) {
        options[@"URL"] = url;
    }
    NSImage *icon = STApplicationIcon();
    if (icon) {
        options[@"ApplicationIcon"] = icon;
    }

    if (options.count > 0) {
        [NSApp orderFrontStandardAboutPanelWithOptions:options];
    } else {
        [NSApp orderFrontStandardAboutPanel:sender];
    }
}

/// The paths among the launch arguments: GNUstep reads `-Key value` pairs (e.g. `-GSTheme Adwaita`,
/// `-GSBackend libgnustep-back`) into the defaults, so they and their values aren't files (#68).
/// Everything after a `--` is a path.
/// Whether the command line asks for a screenshot (--capture) rather than an image to open.
- (BOOL)launchArgumentsRequestCapture:(NSArray<NSString *> *)arguments {
    for (NSUInteger idx = 1; idx < arguments.count; idx++) {
        if ([arguments[idx] isEqualToString:@"--"]) {
            return NO;
        }
        if ([arguments[idx] isEqualToString:STCaptureLaunchArgument]) {
            return YES;
        }
    }
    return NO;
}

- (NSArray<NSString *> *)imagePathsFromLaunchArguments:(NSArray<NSString *> *)arguments {
    NSMutableArray<NSString *> *paths = [[NSMutableArray alloc] init];
    BOOL onlyPaths = NO;
    for (NSUInteger idx = 1; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if (argument.length == 0) {
            continue;
        }
        if (!onlyPaths && [argument isEqualToString:@"--"]) {
            onlyPaths = YES;
            continue;
        }
        if (!onlyPaths && [argument isEqualToString:STCaptureLaunchArgument]) {
            continue;
        }
        if (!onlyPaths && [argument hasPrefix:@"-"]) {
            // The option's value, if there is one, goes with it.
            if (idx + 1 < arguments.count && ![arguments[idx + 1] hasPrefix:@"-"]) {
                idx++;
            }
            continue;
        }
        [paths addObject:argument];
    }
    return paths;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    ScreenshotToolAppendLog(@"ScreenshotTool launched");
    STRemoveExportsChangedBefore(STExportDirectoryURL(), [NSDate dateWithTimeIntervalSinceNow:-STExportMaximumAge]);
#if defined(GNUSTEP)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidActivate:)
                                                 name:GSThemeDidActivateNotification
                                               object:nil];
#endif
    STWindowsStartClipboardMonitoring();
    [self setupWindowAndContent];
    [self setupToolbar];
    self.lastWidthTool = ScreenshotCanvasToolHighlighter;
    [self loadToolSettingsFromDefaults];
    // Open a launch image before the window is first shown, so it appears at the image's size:
    // resizing a shown window loses its top 39pt under some window managers (#60).
    [self openLaunchImage];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self configureUpdater];

    [self selectTool:ScreenshotCanvasToolHighlighter];
    [self reflectZoomSelection];
    // After the window is up: reading the clipboard can wait for the pasteboard server.
    [self performSelector:@selector(refreshPasteAvailability) withObject:nil afterDelay:0.0];
}

/// The image named by application:openFile: or on the command line, if any.
- (void)openLaunchImage {
    if (self.pendingOpenPath.length > 0) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"applicationDidFinishLaunching: attempting deferred open for %@",
                                 self.pendingOpenPath]);
        [self openImageAtURL:[NSURL fileURLWithPath:self.pendingOpenPath]];
        self.pendingOpenPath = nil;
    } else {
        NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
        ScreenshotToolAppendLog([NSString stringWithFormat:@"applicationDidFinishLaunching: argc=%lu",
                                 (unsigned long)arguments.count]);
        if ([self launchArgumentsRequestCapture:arguments]) {
            // `ScreenshotTool --capture`, for a keyboard shortcut of the desktop's.
            [self performSelector:@selector(takeScreenshot:) withObject:nil afterDelay:0.0];
            return;
        }
        for (NSString *candidate in [self imagePathsFromLaunchArguments:arguments]) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"applicationDidFinishLaunching: CLI path %@", candidate]);
            if ([self openImageAtURL:[NSURL fileURLWithPath:candidate]]) {
                break;
            }
        }
    }
}

- (void)configureUpdater {
#if defined(GNUSTEP)
    NSError *error = nil;
    self.updaterController = [[GPStandardUpdaterController alloc] initWithPackagedConfiguration:&error];
    if (self.updaterController == nil) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Updater disabled: %@",
                                 error.localizedDescription ?: @"unknown error"]);
        return;
    }

    self.updaterController.delegate = self;
    self.updaterController.parentWindow = self.window;
    [self.updaterController start];
    ScreenshotToolAppendLog(@"Updater initialized");
#elif ST_USES_SPARKLE
    // The feed (SUFeedURL) and its signing key (SUPublicEDKey) are in Info.plist; Sparkle asks
    // before it checks automatically.
    self.sparkleController = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES
                                                                           updaterDelegate:nil
                                                                        userDriverDelegate:nil];
    ScreenshotToolAppendLog(@"Sparkle updater initialized");
#endif
}

- (BOOL)hasUpdater {
#if defined(GNUSTEP)
    return (self.updaterController != nil);
#elif ST_USES_SPARKLE
    return self.sparkleController.updater.canCheckForUpdates;
#else
    return NO;
#endif
}

- (IBAction)checkForUpdates:(id)sender {
    if (![self hasUpdater]) {
        ScreenshotToolAppendLog(@"Manual update check requested, but updater is unavailable");
        NSBeep();
        return;
    }

#if defined(GNUSTEP)
    [self.updaterController checkForUpdates:sender];
#elif ST_USES_SPARKLE
    [self.sparkleController checkForUpdates:sender];
#endif
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    ScreenshotToolAppendLog([NSString stringWithFormat:@"application:openFile: received %@", filename ?: @"<nil>"]);
    if (!self.canvasView) {
        self.pendingOpenPath = filename;
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Canvas not ready; deferring open for %@", filename ?: @"<nil>"]);
        return YES;
    }
#if defined(GNUSTEP)
    if (![self confirmProceedingWithUnsavedChanges]) {
        return NO;
    }
    BOOL opened = [self openImageAtURL:[NSURL fileURLWithPath:filename]];
#else
    // From Finder, the Dock or Open With: a window of its own.
    BOOL opened = [self openURLInDocumentWindow:[NSURL fileURLWithPath:filename] preferring:nil];
#endif
    ScreenshotToolAppendLog([NSString stringWithFormat:@"application:openFile: %@ %@", opened ? @"opened" : @"failed",
                             filename ?: @"<nil>"]);
    return opened;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
    if (!flag) {
        [self.window makeKeyAndOrderFront:self];
    }
    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    if (action == @selector(saveDocumentAs:) || action == @selector(saveProject:) || action == @selector(copy:) ||
        action == @selector(zoomIn:) || action == @selector(zoomOut:)) {
        return [self.canvasView hasImage];
    }
    if (action == @selector(cropImage:)) {
        return [self.canvasView hasSelection];
    }
    if (action == @selector(shareImage:) || action == @selector(shareFromFileMenu:)) {
        return STCanShareImages() && [self.canvasView hasImage];
    }
    if (action == @selector(redactSelection:) || action == @selector(duplicateAnnotations:) ||
        action == @selector(bringAnnotationsToFront:) || action == @selector(sendAnnotationsToBack:)) {
        return [self.canvasView validateMenuItem:menuItem];
    }
    if (action == @selector(pasteAsNewImage:)) {
        return [self clipboardHasImage];
    }
    if (action == @selector(takeScreenshot:)) {
        return [STScreenshotCapture isAvailable] && ![STScreenshotCapture isCapturing];
    }
    if (action == @selector(undo:)) {
        NSUndoManager *undo = [self activeUndoManager];
        return (undo && [undo canUndo]);
    }
    if (action == @selector(redo:)) {
        NSUndoManager *undo = [self activeUndoManager];
        return (undo && [undo canRedo]);
    }
    if (action == @selector(zoomFitToWindow:) ||
        action == @selector(zoomPreset25:) ||
        action == @selector(zoomPreset50:) ||
        action == @selector(zoomPreset100:) ||
        action == @selector(zoomPreset200:) ||
        action == @selector(zoomIn:) ||
        action == @selector(zoomOut:)) {
        return [self.canvasView hasImage];
    }
    if (action == @selector(checkForUpdates:)) {
        return [self hasUpdater];
    }
    if (action == @selector(runCustomAction:)) {
        STCustomAction *customAction = [self customActionForSender:menuItem];
        return [self.canvasView hasImage] && customAction && ![self isRunningCustomAction:customAction];
    }
    return YES;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem {
    NSString *identifier = toolbarItem.itemIdentifier;
    // As the Edit menu's items (#101).
    if ([identifier isEqualToString:ToolbarItemUndo]) {
        return [[self activeUndoManager] canUndo];
    }
    if ([identifier isEqualToString:ToolbarItemRedo]) {
        return [[self activeUndoManager] canRedo];
    }
    if ([identifier isEqualToString:ToolbarItemCopy] || [identifier isEqualToString:ToolbarItemSave]) {
        return [self.canvasView hasImage];
    }
    if ([identifier isEqualToString:ToolbarItemColor]) {
        return STToolUsesColor(self.canvasView.activeTool) && [self.canvasView hasImage];
    }
    if ([identifier isEqualToString:ToolbarItemZoom]) {
        return [self.canvasView hasImage];
    }
    // The drawing tools need an image (#221); validation would otherwise enable them again.
    if ([identifier isEqualToString:ToolbarItemTools]) {
        return [self.canvasView hasImage];
    }
    if ([identifier hasPrefix:ToolbarItemCustomActionPrefix]) {
        STCustomAction *action = [self customActionForToolbarIdentifier:identifier];
        return [self.canvasView hasImage] && action && ![self isRunningCustomAction:action];
    }
    return YES;
}

static id STInfoValueForKey(NSString *key) {
    if (key.length == 0) {
        return nil;
    }
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:key];
}

#pragma mark - Setup

- (void)setupMenus {
    NSString *appName = [[NSProcessInfo processInfo] processName];
    // GNUstep's own (NeXTSTEP-style) menus show the main menu's title above it.
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:appName];
    [NSApp setMainMenu:mainMenu];

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
                                                       action:@selector(showAboutPanel:)
                                                keyEquivalent:@""];
    [aboutItem setTarget:self];
    [appMenu addItem:aboutItem];

    NSMenuItem *preferencesItem = [[NSMenuItem alloc] initWithTitle:@"Preferences…"
                                                             action:@selector(showPreferences:)
                                                      keyEquivalent:@","];
    [preferencesItem setTarget:self];
    [preferencesItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [appMenu addItem:preferencesItem];

#if defined(GNUSTEP) || ST_USES_SPARKLE
    NSMenuItem *checkForUpdatesItem = [[NSMenuItem alloc] initWithTitle:@"Check for Updates…"
                                                                 action:@selector(checkForUpdates:)
                                                          keyEquivalent:@""];
    [checkForUpdatesItem setTarget:self];
    [appMenu addItem:checkForUpdatesItem];
#endif

    [appMenu addItem:[NSMenuItem separatorItem]];

#if !defined(GNUSTEP)
    NSMenuItem *servicesItem = [[NSMenuItem alloc] initWithTitle:@"Services" action:NULL keyEquivalent:@""];
    NSMenu *servicesMenu = [[NSMenu alloc] initWithTitle:@"Services"];
    [servicesItem setSubmenu:servicesMenu];
    [appMenu addItem:servicesItem];
    [NSApp setServicesMenu:servicesMenu];
    [appMenu addItem:[NSMenuItem separatorItem]];

    [appMenu addItemWithTitle:[NSString stringWithFormat:@"Hide %@", appName]
                       action:@selector(hide:)
                keyEquivalent:@"h"];
    NSMenuItem *hideOthersItem = [appMenu addItemWithTitle:@"Hide Others"
                                                    action:@selector(hideOtherApplications:)
                                             keyEquivalent:@"h"];
    [hideOthersItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagOption)];
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
#endif

    NSString *quitTitle = [NSString stringWithFormat:@"Quit %@", appName];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:quitTitle
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [quitItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [appMenu addItem:quitItem];

    // File menu
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];

#if !defined(GNUSTEP)
    NSMenuItem *newWindowItem = [fileMenu addItemWithTitle:@"New Window"
                                                    action:@selector(newDocumentWindow:)
                                             keyEquivalent:@"n"];
    [newWindowItem setTarget:self];
#endif

    NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"Open…"
                                                      action:@selector(openDocument:)
                                               keyEquivalent:@"o"];
    [openItem setTarget:self];
    [openItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [fileMenu addItem:openItem];

    NSMenuItem *openRecentItem = [[NSMenuItem alloc] initWithTitle:@"Open Recent"
                                                            action:NULL
                                                     keyEquivalent:@""];
    self.openRecentMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    [self.openRecentMenu setAutoenablesItems:NO];
    [self loadRecentDocumentPathsFromDefaults];
    [self rebuildOpenRecentMenu];
    [fileMenu addItem:openRecentItem];
    [fileMenu setSubmenu:self.openRecentMenu forItem:openRecentItem];

    // With the desktop's own tool: GNOME's screenshot UI through the portal, the Snipping Tool on
    // Windows, screencapture on macOS (until its own capture, macos.md).
    NSMenuItem *takeScreenshotItem = [[NSMenuItem alloc] initWithTitle:@"Take Screenshot…"
                                                                action:@selector(takeScreenshot:)
                                                         keyEquivalent:@"T"];
    [takeScreenshotItem setTarget:self];
    [takeScreenshotItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagShift)];
    [fileMenu addItem:takeScreenshotItem];

    NSMenuItem *saveAsItem = [[NSMenuItem alloc] initWithTitle:@"Save As…"
                                                        action:@selector(saveDocumentAs:)
                                                 keyEquivalent:@"s"];
    [saveAsItem setTarget:self];
    [saveAsItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [fileMenu addItem:saveAsItem];

    // Keeps annotations editable: the original image plus the annotations, reopened as layers (#32).
    NSMenuItem *saveProjectItem = [[NSMenuItem alloc] initWithTitle:@"Save Project…"
                                                             action:@selector(saveProject:)
                                                      keyEquivalent:@"S"];
    [saveProjectItem setTarget:self];
    [saveProjectItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagShift)];
    [fileMenu addItem:saveProjectItem];

    // The user's custom actions, each sending the annotated image to a command of theirs (#221).
    NSArray<STCustomAction *> *customActions = [self loadedCustomActions];
    if (customActions.count > 0) {
        [fileMenu addItem:[NSMenuItem separatorItem]];
        for (STCustomAction *customAction in customActions) {
            [fileMenu addItem:[self menuItemForCustomAction:customAction]];
        }
    }

#if !defined(GNUSTEP)
    [fileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *shareItem = [fileMenu addItemWithTitle:@"Share" action:NULL keyEquivalent:@""];
    NSMenu *shareMenu = [[NSMenu alloc] initWithTitle:@"Share"];
    shareMenu.delegate = self;
    [shareItem setSubmenu:shareMenu];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
#elif defined(ST_HAVE_LIBS_SHARING)
    // libs-sharing's sheet, so Share isn't only on the toolbar (which may fold it into ») and
    // the canvas.
    [fileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *shareItem = [fileMenu addItemWithTitle:@"Share…" action:@selector(shareFromFileMenu:) keyEquivalent:@""];
    [shareItem setTarget:self];
#endif

    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"File" action:NULL keyEquivalent:@""];
    [fileMenuItem setSubmenu:fileMenu];
    [mainMenu addItem:fileMenuItem];

    // Edit menu
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];

    NSMenuItem *undoItem = [[NSMenuItem alloc] initWithTitle:@"Undo"
                                                     action:@selector(undo:)
                                              keyEquivalent:@"z"];
    [undoItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [undoItem setTarget:self];
    [editMenu addItem:undoItem];

    NSMenuItem *redoItem = [[NSMenuItem alloc] initWithTitle:@"Redo"
                                                     action:@selector(redo:)
                                              keyEquivalent:@"Z"];
    [redoItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagShift)];
    [redoItem setTarget:self];
    [editMenu addItem:redoItem];

    [editMenu addItem:[NSMenuItem separatorItem]];
#if !defined(GNUSTEP)
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
#endif
    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy"
                                                      action:@selector(copy:)
                                               keyEquivalent:@"c"];
    [copyItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
#if defined(GNUSTEP)
    [copyItem setTarget:self];
#else
    // Through the responder chain, so a text label being edited copies its text; otherwise the
    // window delegate (self) copies the image.
    [copyItem setTarget:nil];
#endif
    [editMenu addItem:copyItem];
#if !defined(GNUSTEP)
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
#endif

    NSMenuItem *pasteAsNewItem = [[NSMenuItem alloc] initWithTitle:@"Paste as New Image"
                                                            action:@selector(pasteAsNewImage:)
                                                     keyEquivalent:@"V"];
    [pasteAsNewItem setTarget:self];
    // Command like every other shortcut: GNUstep maps the Ctrl key to Command, so a Control mask
    // made the displayed Ctrl+Shift+V unreachable.
    [pasteAsNewItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagShift)];
    [editMenu addItem:pasteAsNewItem];

    NSMenuItem *cropSelectionItem = [[NSMenuItem alloc] initWithTitle:@"Crop to Selection"
                                                               action:@selector(cropImage:)
                                                        keyEquivalent:@"k"];
    [cropSelectionItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [cropSelectionItem setTarget:self];
    [editMenu addItem:cropSelectionItem];

    // The canvas's own commands, also in its right-click menu, which shows these shortcuts.
    NSMenuItem *redactSelectionItem = [[NSMenuItem alloc] initWithTitle:@"Redact Selection"
                                                                 action:@selector(redactSelection:)
                                                          keyEquivalent:@""];
    [redactSelectionItem setTarget:self];
    [editMenu addItem:redactSelectionItem];
    [editMenu addItem:[NSMenuItem separatorItem]];
    // Built with @selector: validation compares selectors with ==, and on GNUstep's runtime one
    // from NSSelectorFromString isn't the same pointer.
    SEL arrangeActions[] = { @selector(duplicateAnnotations:), @selector(bringAnnotationsToFront:),
                             @selector(sendAnnotationsToBack:) };
    NSArray<NSString *> *arrangeTitles = @[@"Duplicate", @"Bring to Front", @"Send to Back"];
    NSArray<NSString *> *arrangeKeys = @[@"d", @"F", @"B"];
    for (NSUInteger i = 0; i < arrangeTitles.count; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:arrangeTitles[i]
                                                      action:arrangeActions[i]
                                               keyEquivalent:arrangeKeys[i]];
        [item setKeyEquivalentModifierMask:(i == 0 ? NSEventModifierFlagCommand
                                                   : (NSEventModifierFlagCommand | NSEventModifierFlagShift))];
        [item setTarget:self];
        [editMenu addItem:item];
    }
#if !defined(GNUSTEP)
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
#endif

    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    [editMenuItem setSubmenu:editMenu];
    [mainMenu addItem:editMenuItem];

    // View menu
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];

    NSMenuItem *fitToWindowItem = [[NSMenuItem alloc] initWithTitle:@"Fit to Window"
                                                            action:@selector(zoomFitToWindow:)
                                                     keyEquivalent:@"0"];
    [fitToWindowItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [fitToWindowItem setTarget:self];
    [viewMenu addItem:fitToWindowItem];

    NSMenuItem *zoom25Item = [[NSMenuItem alloc] initWithTitle:@"25%"
                                                        action:@selector(zoomPreset25:)
                                                 keyEquivalent:@""];
    [zoom25Item setTarget:self];
    [viewMenu addItem:zoom25Item];

    NSMenuItem *zoom50Item = [[NSMenuItem alloc] initWithTitle:@"50%"
                                                        action:@selector(zoomPreset50:)
                                                 keyEquivalent:@""];
    [zoom50Item setTarget:self];
    [viewMenu addItem:zoom50Item];

    NSMenuItem *zoom100Item = [[NSMenuItem alloc] initWithTitle:@"100%"
                                                         action:@selector(zoomPreset100:)
                                                  keyEquivalent:@"1"];
    [zoom100Item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [zoom100Item setTarget:self];
    [viewMenu addItem:zoom100Item];

    NSMenuItem *zoom200Item = [[NSMenuItem alloc] initWithTitle:@"200%"
                                                         action:@selector(zoomPreset200:)
                                                  keyEquivalent:@""];
    [zoom200Item setTarget:self];
    [viewMenu addItem:zoom200Item];

    [viewMenu addItem:[NSMenuItem separatorItem]];

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

    // Zoom and Preferences can go back in the toolbar from here (#53).
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *customizeToolbarItem = [[NSMenuItem alloc] initWithTitle:@"Customize Toolbar…"
                                                                  action:@selector(runToolbarCustomizationPalette:)
                                                           keyEquivalent:@""];
    [viewMenu addItem:customizeToolbarItem];

#if !defined(GNUSTEP)
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *fullScreenItem = [viewMenu addItemWithTitle:@"Enter Full Screen"
                                                     action:@selector(toggleFullScreen:)
                                              keyEquivalent:@"f"];
    [fullScreenItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagControl)];
#endif

    NSMenuItem *viewMenuItem = [[NSMenuItem alloc] initWithTitle:@"View" action:NULL keyEquivalent:@""];
    [viewMenuItem setSubmenu:viewMenu];
    [mainMenu addItem:viewMenuItem];

#if !defined(GNUSTEP)
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:NULL keyEquivalent:@""];
    [windowMenuItem setSubmenu:windowMenu];
    [mainMenu addItem:windowMenuItem];
    [NSApp setWindowsMenu:windowMenu];

    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    NSMenuItem *helpItem = [helpMenu addItemWithTitle:[NSString stringWithFormat:@"%@ Help", appName]
                                               action:@selector(showHelp:)
                                        keyEquivalent:@"?"];
    [helpItem setTarget:self];
    NSMenuItem *helpMenuItem = [[NSMenuItem alloc] initWithTitle:@"Help" action:NULL keyEquivalent:@""];
    [helpMenuItem setSubmenu:helpMenu];
    [mainMenu addItem:helpMenuItem];
    [NSApp setHelpMenu:helpMenu];
#endif

#if !defined(GNUSTEP)
    // Each window has its own controller; the commands that act on a document go to the front one.
    self.documentRouter = [[STDocumentRouter alloc] init];
    [self routeDocumentCommandsInMenu:mainMenu];
#endif
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
    [self.window setBackgroundColor:STThemeWindowBackgroundColor()];
    [self.window center];
    [self.window setDelegate:self];
    // The property owns it (ARC): a window that also released itself on close was over-released,
    // and showing it again (from the Dock, say) crashed.
    [self.window setReleasedWhenClosed:NO];
    [self.window setAcceptsMouseMovedEvents:YES];
#if !defined(GNUSTEP)
    // The window passes drags to its delegate (see Drag and drop below).
    [self.window registerForDraggedTypes:@[NSPasteboardTypeFileURL, NSPasteboardTypePNG, NSPasteboardTypeTIFF]];
#endif
    // Windows: files dropped from Explorer open too; GNUstep's backend takes no drops from other apps.
    __weak AppDelegate *weakSelf = self;
    STWindowsAcceptFileDrops(self.window, ^(NSArray<NSString *> *paths) {
        [weakSelf openDroppedFilePaths:paths];
    });
    self.undoManager = [[NSUndoManager alloc] init];
    self.undoManager.levelsOfUndo = 50;
    // The toolbar's Undo and Redo follow every undo manager: the canvas's and an open text box's (#101).
    // (GNUstep has no did-close-group notification; checkpoints come with group changes.)
    for (NSString *name in @[NSUndoManagerCheckpointNotification, NSUndoManagerDidUndoChangeNotification,
                             NSUndoManagerDidRedoChangeNotification]) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(undoStateDidChange:)
                                                     name:name
                                                   object:nil];
    }
    // Paste follows the clipboard while the window keeps focus too (#202; Windows only).
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(clipboardDidChange:)
                                                 name:STWindowsClipboardDidChangeNotification
                                               object:nil];

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
    STCanvasClipView *clipView = [[STCanvasClipView alloc] initWithFrame:self.scrollView.contentView.frame];
    [self.scrollView setContentView:clipView];

    self.canvasView = [[ScreenshotCanvasView alloc] initWithFrame:self.scrollView.contentView.bounds];
    self.canvasView.hostScrollView = self.scrollView;
    self.canvasView.autoresizingMask = NSViewNotSizable;
    self.canvasView.activeTool = ScreenshotCanvasToolHighlighter;
    self.canvasView.textColor = self.canvasView.penColor;
    self.canvasView.contextMenuProvider = ^NSMenu *(STCanvasContextKind kind) {
        return [weakSelf canvasContextMenuForKind:kind];
    };
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(canvasViewDidRestoreState:)
                                                 name:ScreenshotCanvasViewDidRestoreStateNotification
                                               object:self.canvasView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(canvasViewRequestsTool:)
                                                 name:ScreenshotCanvasViewRequestsToolNotification
                                               object:self.canvasView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(canvasViewSelectionDidChange:)
                                                 name:ScreenshotCanvasViewSelectionDidChangeNotification
                                               object:self.canvasView];
    // A window resize moves the selection on screen without the canvas scrolling.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(canvasViewSelectionDidChange:)
                                                 name:NSViewFrameDidChangeNotification
                                               object:self.scrollView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(canvasViewDidBeginTextEditing:)
                                                 name:ScreenshotCanvasViewDidBeginTextEditingNotification
                                               object:self.canvasView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(canvasViewDidEndTextEditing:)
                                                 name:ScreenshotCanvasViewDidEndTextEditingNotification
                                               object:self.canvasView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(canvasViewRequestsTextFormat:)
                                                 name:ScreenshotCanvasViewRequestsTextFormatNotification
                                               object:self.canvasView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(canvasViewDidChangeZoom:)
                                                 name:ScreenshotCanvasViewDidChangeZoomNotification
                                               object:self.canvasView];

    [self.scrollView setDocumentView:[[STCanvasStageView alloc] initWithCanvasView:self.canvasView]];
    [container addSubview:self.scrollView];
    self.emptyStateView = [self newEmptyStateView];
    [container addSubview:self.emptyStateView];
    [self.window setInitialFirstResponder:self.canvasView];
    [self.window makeFirstResponder:self.canvasView];

#if defined(GNUSTEP)
    STStatusBarBackgroundView *statusBar = [[STStatusBarBackgroundView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, contentBounds.size.width, StatusBarHeight)];
    statusBar.fillColor = STThemeStatusBarBackgroundColor();
    statusBar.topBorderColor = STThemeStatusBarBorderColor();
#else
    NSView *statusBar = [[NSView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, contentBounds.size.width, StatusBarHeight)];
#endif
    [statusBar setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    self.statusBarView = statusBar;
    [container addSubview:statusBar];

    STStatusTextField *statusField = [[STStatusTextField alloc] initWithFrame:NSInsetRect(statusBar.bounds, 8.0f, 4.0f)];
    [statusField setEditable:NO];
    [statusField setBezeled:NO];
    [statusField setBordered:NO];
    [statusField setDrawsBackground:NO];
    [statusField setTextColor:STThemeStatusPrimaryTextColor()];
    [statusField setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [statusField setAlignment:NSTextAlignmentLeft];
    statusField.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    [statusField setStringValue:@""];
    self.statusTextField = statusField;
    STApplyAccessibilityLabel(statusField, @"Status messages");
    [statusBar addSubview:statusField];
    [self setupStatusControls];

    // Hidden until the settings load (-loadToolSettingsFromDefaults), which shows it unless the
    // user turned it off (#221).
    self.statusBarVisiblePreference = NO;

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
    if (!self.toolbarItemsByIdentifier) {
        self.toolbarItemsByIdentifier = [[NSMutableDictionary alloc] init];
    } else {
        [self.toolbarItemsByIdentifier removeAllObjects];
    }
    self.toolbar = [[NSToolbar alloc] initWithIdentifier:ToolbarIdentifier];
    self.toolbar.delegate = self;
    self.toolbar.allowsUserCustomization = YES;
    self.toolbar.autosavesConfiguration = YES;
    self.toolbar.sizeMode = NSToolbarSizeModeRegular;
    // The tool, colour and zoom items have no labels. On GNUstep, libs-gui also reserves label
    // space in icon-and-label mode, which made the toolbar 62px tall for 30px buttons.
    self.toolbar.displayMode = NSToolbarDisplayModeIconOnly;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(toolbarWillAddItemNotification:)
                                             name:NSToolbarWillAddItemNotification
                                           object:self.toolbar];
    [self.window setToolbar:self.toolbar];
    //[self.toolbar setSelectedItemIdentifier:ToolbarItemHighlighter];
    //[self refreshToolButtonIcons];
}

- (NSToolbarItemIdentifier)identifierForTool:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolArrow:
            return ToolbarItemArrow;
        case ScreenshotCanvasToolRectangle:
            return ToolbarItemRectangle;
        case ScreenshotCanvasToolStep:
            return ToolbarItemStep;
        case ScreenshotCanvasToolRedact:
            return ToolbarItemRedact;
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
    if (!identifier) {
        return nil;
    }
    NSToolbarItem *cached = self.toolbarItemsByIdentifier[identifier];
    if (cached) {
        return cached;
    }
    for (NSToolbarItem *item in self.toolbar.items) {
        if ([item.itemIdentifier isEqualToString:identifier]) {
            self.toolbarItemsByIdentifier[identifier] = item;
            return item;
        }
    }
    NSToolbarItem *generated = [self toolbar:self.toolbar
                       itemForItemIdentifier:identifier
                    willBeInsertedIntoToolbar:NO];
    if (generated) {
#if !defined(GNUSTEP)
        self.toolbarItemsByIdentifier[identifier] = generated;
#endif
        return generated;
    }
    return nil;
}

- (NSString *)baseIconStemForToolbarIdentifier:(NSToolbarItemIdentifier)identifier {
    if ([identifier isEqualToString:ToolbarItemHighlighter]) {
        return @"Highligher";
    }
    if ([identifier isEqualToString:ToolbarItemPen]) {
        return @"PenTool";
    }
    if ([identifier isEqualToString:ToolbarItemArrow]) {
        return @"Arrow";
    }
    if ([identifier isEqualToString:ToolbarItemRectangle]) {
        return @"Rectangle";
    }
    if ([identifier isEqualToString:ToolbarItemStep]) {
        return @"NumberedStep";
    }
    if ([identifier isEqualToString:ToolbarItemRedact]) {
        return @"Redact";
    }
    if ([identifier isEqualToString:ToolbarItemEraser]) {
        return @"Eraser";
    }
    if ([identifier isEqualToString:ToolbarItemText]) {
        return @"AddText";
    }
    if ([identifier isEqualToString:ToolbarItemSelect]) {
        return @"MarqueeTool";
    }
    if ([identifier isEqualToString:ToolbarItemCopy]) {
        return @"CopyImage";
    }
    if ([identifier isEqualToString:ToolbarItemSave]) {
        // Drawn with the v0.2.0 icon set (#221). Until it's in the app, no stem: an icon that
        // isn't there would load as an empty placeholder.
        return STToolbarIconExists(@"Save") ? @"Save" : nil;
    }
    if ([identifier isEqualToString:ToolbarItemPreferences]) {
        return @"Preferences";
    }
    if ([identifier isEqualToString:ToolbarItemUndo]) {
        return @"Undo";
    }
    if ([identifier isEqualToString:ToolbarItemRedo]) {
        return @"Redo";
    }
    return nil;
}

- (NSArray<NSString *> *)iconNameCandidatesForToolbarIdentifier:(NSToolbarItemIdentifier)identifier active:(BOOL)active {
    NSString *stem = [self baseIconStemForToolbarIdentifier:identifier];
    if (!stem) {
        return @[];
    }
    // One monochrome set the theme tints (#57): the selected tool shows as a pressed control,
    // and light or dark is the theme's palette, so there are no active or dark variants.
    (void)active;
    return @[STSymbolicIconName(stem), stem];
}


#pragma mark - NSToolbarDelegate


#pragma mark - NSToolbarDelegate

- (NSString *)debugDescriptionForColor:(NSColor *)color {
    if (!color) {
        return @"<nil>";
    }
    NSColor *device = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color;
    return [NSString stringWithFormat:@"(r=%.3f g=%.3f b=%.3f a=%.3f)", device.redComponent, device.greenComponent, device.blueComponent, device.alphaComponent];
}

- (void)refreshToolButtonIcons {
    if (!self.toolbar) {
        ScreenshotToolAppendLog(@"refreshToolButtonIcons: toolbar unavailable");
        return;
    }
    NSToolbarItemIdentifier activeIdentifier = [self identifierForTool:self.canvasView.activeTool];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"refreshToolButtonIcons: active=%@", activeIdentifier]);

    [self refreshToolbarToolsControl];
    NSArray<NSToolbarItemIdentifier> *toolIdentifiers = [@[ToolbarItemUndo, ToolbarItemRedo, ToolbarItemSave, ToolbarItemCopy, ToolbarItemPreferences]
                                                          arrayByAddingObjectsFromArray:[self customActionToolbarIdentifiersInToolbarOnly:NO]];
    for (NSToolbarItemIdentifier identifier in toolIdentifiers) {
        NSToolbarItem *item = [self toolbarItemForIdentifier:identifier];
        if (!item) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ missing", identifier]);
            continue;
        }

        [self applyToolTipToToolbarItem:item source:@"refresh-icons"];
        BOOL isEnabled = YES;
        if ([identifier isEqualToString:ToolbarItemCopy] || [identifier isEqualToString:ToolbarItemSave]) {
            isEnabled = [self.canvasView hasImage];
        } else if ([identifier hasPrefix:ToolbarItemCustomActionPrefix]) {
            isEnabled = [self validateToolbarItem:item];
        } else if ([identifier isEqualToString:ToolbarItemUndo] || [identifier isEqualToString:ToolbarItemRedo]) {
            isEnabled = [self validateToolbarItem:item];
        }
        item.enabled = isEnabled;
        // A labelled button (Copy and Save on GNUstep, #221) is enabled even without an icon.
        if (item.view && [item.view respondsToSelector:@selector(setEnabled:)]) {
            [(NSControl *)item.view setEnabled:isEnabled];
            [self adjustToolbarCustomViewVerticalOffset:item.view];
        }
#if defined(GNUSTEP)
        if ([identifier isEqualToString:ToolbarItemCopy] || [identifier isEqualToString:ToolbarItemSave]) {
            continue;
        }
#endif
        if ([identifier hasPrefix:ToolbarItemCustomActionPrefix]) {
            continue; // Its own button or icon.
        }

        BOOL isActive = (activeIdentifier && [identifier isEqualToString:activeIdentifier]);
        NSImage *icon = [self toolbarImageForIdentifier:identifier active:isActive];
        if (!icon) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ missing icon (active=%@)", identifier, isActive ? @"YES" : @"NO"]);
            continue;
        }

        if (item.view && [item.view respondsToSelector:@selector(setImage:)]) {
            id buttonView = item.view;
            if ([buttonView respondsToSelector:@selector(setImage:)]) {
                [buttonView setImage:icon];
            }
            if ([buttonView respondsToSelector:@selector(setActive:)]) {
                [buttonView setActive:isActive];
            }
            if ([buttonView respondsToSelector:@selector(setEnabled:)]) {
                [buttonView setEnabled:isEnabled];
            }
        }
        item.image = icon;
        NSString *state = isActive ? @"active" : @"inactive";
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ updated (%@)", identifier, state]);
    }
    [self refreshToolbarColorControl];
    [self refreshZoomToolbarControl];
    [self refreshStatusZoomControls];
}

- (void)rebuildToolbarBadges {
    [self refreshToolButtonIcons];
}

- (void)toolbarWillAddItemNotification:(NSNotification *)notification {
    NSToolbarItem *item = notification.userInfo[@"item"];
    [self applyToolTipToToolbarItem:item source:@"willAdd"];
    [self performSelector:@selector(refreshToolButtonIcons)
               withObject:nil
               afterDelay:0.0];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    (void)toolbar;
    NSMutableArray<NSToolbarItemIdentifier> *allowed = [@[ToolbarItemUndo,
                                                          ToolbarItemRedo,
                                                          ToolbarItemTools,
                                                          ToolbarItemColor,
                                                          ToolbarItemSave,
                                                          ToolbarItemCopy,
#if !defined(GNUSTEP) || defined(ST_HAVE_LIBS_SHARING)
                                                          ToolbarItemShare,
#endif
                                                          ToolbarItemPreferences,
                                                          ToolbarItemZoom,
                                                          NSToolbarSpaceItemIdentifier,
                                                          NSToolbarFlexibleSpaceItemIdentifier] mutableCopy];
    [allowed addObjectsFromArray:[self customActionToolbarIdentifiersInToolbarOnly:NO]];
    return allowed;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    (void)toolbar;
    // Zoom and Preferences live in the View and app menus (with shortcuts) and can be added back
    // by customising the toolbar (#53). Undo and Redo lead, where GNOME apps keep them (#101).
    // The commands that finish the job close the row, Copy as the main one (#221). Custom actions
    // with "toolbar" set may never push Copy into the overflow: on macOS they go just before
    // Share and Copy with a lower visibility priority; elsewhere after Copy, as GNUstep's toolbar
    // overflows into » from the row's end (#221).
    NSMutableArray<NSToolbarItemIdentifier> *identifiers = [@[ToolbarItemUndo,
             ToolbarItemRedo,
             ToolbarItemTools,
             ToolbarItemColor,
             NSToolbarFlexibleSpaceItemIdentifier,
             ToolbarItemSave] mutableCopy];
#if !defined(GNUSTEP)
    [identifiers addObjectsFromArray:[self customActionToolbarIdentifiersInToolbarOnly:YES]];
    [identifiers addObject:ToolbarItemShare];
    [identifiers addObject:ToolbarItemCopy];
#else
    [identifiers addObject:ToolbarItemCopy];
#if defined(ST_HAVE_LIBS_SHARING)
    // An icon after Copy, so it goes into » before Copy and Save do.
    [identifiers addObject:ToolbarItemShare];
#endif
    [identifiers addObjectsFromArray:[self customActionToolbarIdentifiersInToolbarOnly:YES]];
#endif
    return identifiers;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
    itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {
    (void)toolbar;
    (void)flag;
    NSToolbarItem *item = [self baselineToolbarItemForIdentifier:itemIdentifier];
    item.visibilityPriority = STToolbarVisibilityPriorityForIdentifier(itemIdentifier);
    return item;
}

- (NSToolbarItem *)baselineToolbarItemForIdentifier:(NSToolbarItemIdentifier)identifier {
    if ([identifier isEqualToString:ToolbarItemTools]) {
        return [self toolbarItemForToolControl];
    }
    if ([identifier hasPrefix:ToolbarItemCustomActionPrefix]) {
        STCustomAction *action = [self customActionForToolbarIdentifier:identifier];
        return action ? [self toolbarItemForCustomAction:action] : nil;
    }
    if ([identifier isEqualToString:ToolbarItemHighlighter]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemHighlighter
                                                 label:@"Highlighter"
                                                action:@selector(activateHighlighter:)
                                             imageName:@"Highligher"];
    }
    if ([identifier isEqualToString:ToolbarItemPen]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemPen
                                                 label:@"Pen"
                                                action:@selector(activatePen:)
                                             imageName:@"PenTool"];
    }
    if ([identifier isEqualToString:ToolbarItemArrow]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemArrow
                                                 label:@"Arrow"
                                                action:@selector(activateArrow:)
                                             imageName:@"Arrow"];
    }
    if ([identifier isEqualToString:ToolbarItemRectangle]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemRectangle
                                                 label:@"Rectangle"
                                                action:@selector(activateRectangle:)
                                             imageName:@"Rectangle"];
    }
    if ([identifier isEqualToString:ToolbarItemStep]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemStep
                                                 label:@"Numbered Step"
                                                action:@selector(activateStep:)
                                             imageName:@"NumberedStep"];
    }
    if ([identifier isEqualToString:ToolbarItemRedact]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemRedact
                                                 label:@"Redact"
                                                action:@selector(activateRedact:)
                                             imageName:@"Redact"];
    }
    if ([identifier isEqualToString:ToolbarItemText]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemText
                                                 label:@"Text"
                                                action:@selector(activateText:)
                                             imageName:@"AddText"];
    }
    if ([identifier isEqualToString:ToolbarItemSelect]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemSelect
                                                 label:@"Select"
                                                action:@selector(activateSelect:)
                                             imageName:@"MarqueeTool"];
    }
    if ([identifier isEqualToString:ToolbarItemEraser]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemEraser
                                                 label:@"Eraser"
                                                action:@selector(activateEraser:)
                                             imageName:@"Eraser"];
    }
    if ([identifier isEqualToString:ToolbarItemUndo]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemUndo
                                                 label:@"Undo"
                                                action:@selector(undo:)
                                             imageName:@"Undo"];
    }
    if ([identifier isEqualToString:ToolbarItemRedo]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemRedo
                                                 label:@"Redo"
                                                action:@selector(redo:)
                                             imageName:@"Redo"];
    }
#if !defined(GNUSTEP)
    if ([identifier isEqualToString:ToolbarItemCopy]) {
        return [self dragExportCopyToolbarItem];
    }
    if ([identifier isEqualToString:ToolbarItemShare]) {
        NSSharingServicePickerToolbarItem *item =
            [[NSSharingServicePickerToolbarItem alloc] initWithItemIdentifier:ToolbarItemShare];
        item.label = @"Share";
        item.paletteLabel = @"Share";
        item.toolTip = @"Share the annotated image";
        item.delegate = self;
        return item;
    }
    if ([identifier isEqualToString:ToolbarItemSave]) {
        BOOL hasIcon = STToolbarIconExists(@"Save");
        NSToolbarItem *item = [self baselineToolbarItemWithIdentifier:ToolbarItemSave
                                                                label:@"Save"
                                                               action:@selector(saveDocumentAs:)
                                                            imageName:(hasIcon ? @"Save" : nil)];
        if (!hasIcon) {
            if (@available(macOS 11.0, *)) {
                item.image = [NSImage imageWithSystemSymbolName:@"square.and.arrow.down"
                                       accessibilityDescription:@"Save"];
            }
        }
        item.toolTip = @"Save the annotated image";
        return item;
    }
#else
    // Copy and Save finish the job, so they're buttons with their names rather than bare icons,
    // and Copy is the accent one, as a WinUI command bar's main command is (#221). Under GNOME
    // too: Adwaita 0.1.0-alpha12 (#240) keeps the header bar's room for the title and folds
    // trailing items into » first, so the labelled buttons no longer cost the title (#224).
    if ([identifier isEqualToString:ToolbarItemSave]) {
        return [self labelledToolbarItemWithIdentifier:ToolbarItemSave
                                                 label:@"Save"
                                               toolTip:@"Save the annotated image"
                                                action:@selector(saveDocumentAs:)
                                                accent:NO];
    }
#if defined(ST_HAVE_LIBS_SHARING)
    if ([identifier isEqualToString:ToolbarItemShare]) {
        // libs-sharing's item: a click opens its sheet for -itemsForSharingServicePickerToolbarItem:.
        NSSharingServicePickerToolbarItem *item =
            [[NSSharingServicePickerToolbarItem alloc] initWithItemIdentifier:ToolbarItemShare];
        item.image = [self baselineToolbarImageNamed:@"Share" active:NO];
        item.label = @"Share";
        item.paletteLabel = @"Share";
        item.toolTip = @"Share the annotated image";
        item.delegate = (id<NSSharingServicePickerToolbarItemDelegate>)self;
        return item;
    }
#endif
    if ([identifier isEqualToString:ToolbarItemCopy]) {
        return [self labelledToolbarItemWithIdentifier:ToolbarItemCopy
                                                 label:@"Copy"
                                               toolTip:@"Copy the annotated image"
                                                action:@selector(copy:)
                                                accent:YES];
    }
#endif
    if ([identifier isEqualToString:ToolbarItemCopy]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemCopy
                                                 label:@"Copy"
                                                action:@selector(copy:)
                                             imageName:@"CopyImage"];
    }
    if ([identifier isEqualToString:ToolbarItemColor]) {
        return [self toolbarItemForColorControl];
    }
    if ([identifier isEqualToString:ToolbarItemPreferences]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemPreferences
                                                 label:@"Preferences"
                                                action:@selector(showPreferences:)
                                             imageName:@"Preferences"];
    }
    if ([identifier isEqualToString:ToolbarItemZoom]) {
        return [self toolbarItemForZoomControl];
    }
    return nil;
}

- (NSToolbarItem *)baselineToolbarItemWithIdentifier:(NSToolbarItemIdentifier)identifier
                                               label:(NSString *)label
                                              action:(SEL)selector
                                           imageName:(NSString *)imageName {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.paletteLabel = label ?: @"";
#if defined(GNUSTEP)
    item.label = @"";
    // Folded into » the item is a menu item titled from its label, which is empty, so it needs
    // its own: Undo and Redo overflow first and showed as blank rows.
    NSMenuItem *menuForm = [[NSMenuItem alloc] initWithTitle:item.paletteLabel action:selector keyEquivalent:@""];
    menuForm.target = self;
    item.menuFormRepresentation = menuForm;
#else
    item.label = item.paletteLabel;
#endif
    item.toolTip = item.paletteLabel;
    item.target = self;
    item.action = selector;

    BOOL isActive = [identifier isEqualToString:[self identifierForTool:self.canvasView.activeTool]];
    NSImage *image = [self baselineToolbarImageNamed:imageName active:isActive];
    // A plain image item: the theme draws it as one of its own toolbar buttons (#57).
    if (image) {
        item.image = image;
    }
    return item;
}

#if defined(GNUSTEP)
/// A toolbar item that's a push button with its name (#221). It has no icon: the toolbar's icons
/// are monochrome ones the theme tints for its own toolbar buttons, and a button's image isn't
/// tinted, so it would stay black on an accent fill or a dark toolbar.
- (NSToolbarItem *)labelledToolbarItemWithIdentifier:(NSToolbarItemIdentifier)identifier
                                               label:(NSString *)label
                                             toolTip:(NSString *)toolTip
                                              action:(SEL)selector
                                              accent:(BOOL)accent {
    // Copy drags the image out too, as on macOS.
    BOOL dragsOut = [identifier isEqualToString:ToolbarItemCopy];
    NSButton *button = [[(dragsOut ? [STDragExportButton class] : [NSButton class]) alloc]
                        initWithFrame:NSMakeRect(0, 0, 64.0f, STToolbarZoomControlHeight)];
    if (dragsOut) {
        __weak AppDelegate *weakSelf = self;
        ((STDragExportButton *)button).dragFileProvider = ^NSURL * {
            return [weakSelf exportAnnotatedImageToTemporaryFile];
        };
    }
    button.title = label;
    [button setBezelStyle:NSRoundedBezelStyle];
    button.target = self;
    button.action = selector;
    button.toolTip = toolTip;
    STApplyAccessibilityLabel(button, label);
    // A theme-neutral way to ask for the theme's accent button. Not a Return key equivalent or
    // the window's default button: Return must not copy, least of all while typing a text
    // annotation (#103).
    if (accent && [button respondsToSelector:@selector(setGSThemeStyle:)]) {
        [button performSelector:@selector(setGSThemeStyle:) withObject:@"accent"];
    }
    [button sizeToFit];
    NSSize size = NSMakeSize(MAX(64.0f, ceil(NSWidth(button.frame)) + 20.0f), STToolbarZoomControlHeight);
    [button setFrameSize:size];

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = @"";
    item.paletteLabel = label;
    item.toolTip = toolTip;
    // The item's action too, so the toolbar's validation (-validateToolbarItem:) enables it,
    // and only with an image open.
    item.target = self;
    item.action = selector;
    item.view = button;
    // Folded into » the item is a menu item, titled from its label unless it has its own; the
    // label is empty so the button's name doesn't show twice.
    NSMenuItem *menuForm = [[NSMenuItem alloc] initWithTitle:label action:selector keyEquivalent:@""];
    menuForm.target = self;
    item.menuFormRepresentation = menuForm;
    button.enabled = [self.canvasView hasImage];
    item.minSize = size;
    item.maxSize = size;
    return item;
}
#endif

- (NSInteger)toolbarSegmentIndexForTool:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolSelect:
            return 0;
        case ScreenshotCanvasToolHighlighter:
            return 1;
        case ScreenshotCanvasToolPen:
            return 2;
        case ScreenshotCanvasToolArrow:
            return 3;
        case ScreenshotCanvasToolRectangle:
            return 4;
        case ScreenshotCanvasToolText:
            return 5;
        case ScreenshotCanvasToolStep:
            return 6;
        case ScreenshotCanvasToolRedact:
            return 7;
        case ScreenshotCanvasToolEraser:
            return 8;
    }
    return 0;
}

- (ScreenshotCanvasTool)toolbarToolForSegmentIndex:(NSInteger)index {
    switch (index) {
        case 1:
            return ScreenshotCanvasToolHighlighter;
        case 2:
            return ScreenshotCanvasToolPen;
        case 3:
            return ScreenshotCanvasToolArrow;
        case 4:
            return ScreenshotCanvasToolRectangle;
        case 5:
            return ScreenshotCanvasToolText;
        case 6:
            return ScreenshotCanvasToolStep;
        case 7:
            return ScreenshotCanvasToolRedact;
        case 8:
            return ScreenshotCanvasToolEraser;
        case 0:
        default:
            return ScreenshotCanvasToolSelect;
    }
}

- (NSString *)toolbarTitleForTool:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolSelect:
            return @"Select";
        case ScreenshotCanvasToolHighlighter:
            return @"Highlighter";
        case ScreenshotCanvasToolPen:
            return @"Pen";
        case ScreenshotCanvasToolText:
            return @"Text";
        case ScreenshotCanvasToolEraser:
            return @"Eraser";
        case ScreenshotCanvasToolArrow:
            return @"Arrow";
        case ScreenshotCanvasToolRectangle:
            return @"Rectangle";
        case ScreenshotCanvasToolStep:
            return @"Numbered Step";
        case ScreenshotCanvasToolRedact:
            return @"Redact";
    }
    return @"Tool";
}

- (NSString *)toolbarShortcutForTool:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolSelect:
            return @"S";
        case ScreenshotCanvasToolHighlighter:
            return @"H";
        case ScreenshotCanvasToolPen:
            return @"P";
        case ScreenshotCanvasToolText:
            return @"T";
        case ScreenshotCanvasToolEraser:
            return @"E";
        case ScreenshotCanvasToolArrow:
            return @"A";
        case ScreenshotCanvasToolRectangle:
            return @"R";
        case ScreenshotCanvasToolStep:
            return @"N";
        case ScreenshotCanvasToolRedact:
            return @"X";
    }
    return @"";
}

- (NSString *)toolbarSegmentToolTipForTool:(ScreenshotCanvasTool)tool {
    NSString *title = [NSString stringWithFormat:@"%@ Tool (%@)", [self toolbarTitleForTool:tool], [self toolbarShortcutForTool:tool]];
    if (STToolHasSettingsPopover(tool)) {
        return [title stringByAppendingString:@" — double-click to configure"];
    }
    return title;
}

- (void)canvasViewDidEndTextEditing:(NSNotification *)notification {
    (void)notification;
    [self hideTextOptionsBar];
}

- (void)canvasViewRequestsTextFormat:(NSNotification *)notification {
    NSString *format = notification.userInfo[ScreenshotCanvasViewTextFormatKey];
    if ([format isEqualToString:@"bold"]) {
        [self toggleTextTrait:NSBoldFontMask];
    } else if ([format isEqualToString:@"italic"]) {
        [self toggleTextTrait:NSItalicFontMask];
    } else if ([format isEqualToString:@"bigger"]) {
        [self stepTextSizeBy:2.0];
    } else if ([format isEqualToString:@"smaller"]) {
        [self stepTextSizeBy:-2.0];
    }
}

#pragma mark - Text options bar (#34)

- (void)showTextOptionsBar {
    NSView *container = self.scrollView.superview;
    if (!container) {
        return;
    }
    BOOL wasShowing = (self.textOptionsBar.superview == container && !self.textOptionsBar.isHidden);
    if (!self.textOptionsBar) {
        self.textOptionsBar = [[STTextOptionsBar alloc] initWithFrame:NSMakeRect(0.0, 0.0, NSWidth(self.scrollView.frame), [STTextOptionsBar preferredHeight])];
        self.textOptionsBar.delegate = self;
        // The bar's font field may take the keyboard without finishing the text box (#103).
        self.canvasView.textEditingCompanion = self.textOptionsBar;
    }
    if (self.textOptionsBar.superview != container) {
        [self.textOptionsBar setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
        [container addSubview:self.textOptionsBar];
    }
    // Keep the image's scale while the row takes its space, and keep it where it is on screen
    // where there's room above it: the row covers what's scrolled past, never the image's top,
    // which it pushes down instead (#221). The label being edited stays on screen.
    self.canvasView.suspendsFitUpdates = YES;
    [self.textOptionsBar setHidden:NO];
    [self layoutContentSubviews];
    if (!wasShowing) {
        NSClipView *clip = self.scrollView.contentView;
        CGFloat before = clip.bounds.origin.y;
        [self scrollCanvasVerticallyBy:MIN([STTextOptionsBar preferredHeight], [self spaceAboveImageInViewport])];
        [self.canvasView scrollActiveTextToVisible];
        self.textBarScrollDelta = clip.bounds.origin.y - before;
    }
    [self logWindowFrame:@"text bar shown"];
    [self refreshTextOptionsBar];
}

/// How far the canvas can scroll down without hiding the image's top: as far as it likes when
/// the top is already scrolled past, else to a small gap below the viewport's top edge.
- (CGFloat)spaceAboveImageInViewport {
    NSClipView *clip = self.scrollView.contentView;
    if (!clip || ![self.canvasView hasImage]) {
        return 0.0f;
    }
    NSRect imageInClip = [clip convertRect:self.canvasView.bounds fromView:self.canvasView];
    CGFloat imageTop = clip.isFlipped ? NSMinY(imageInClip) - NSMinY(clip.bounds)
                                      : NSMaxY(clip.bounds) - NSMaxY(imageInClip);
    if (imageTop < 0.0f) {
        return CGFLOAT_MAX;
    }
    return MAX(0.0f, imageTop - 8.0f);
}

/// Scrolls the canvas by delta points (down for positive), within what the clip view allows.
- (void)scrollCanvasVerticallyBy:(CGFloat)delta {
    NSClipView *clip = self.scrollView.contentView;
    if (!clip || ![self.canvasView hasImage]) {
        return;
    }
    NSPoint origin = clip.bounds.origin;
    origin.y += delta;
    [clip scrollToPoint:[clip constrainScrollPoint:origin]];
    [self.scrollView reflectScrolledClipView:clip];
    // The canvas's cursor covers the part on screen, which just moved.
    [self.window invalidateCursorRectsForView:self.canvasView];
}

- (void)logWindowFrame:(NSString *)reason {
    ScreenshotToolAppendLog([NSString stringWithFormat:@"window frame (%@): %@ content %@", reason,
                             NSStringFromRect(self.window.frame),
                             NSStringFromSize([(NSView *)self.window.contentView frame].size)]);
}

- (void)hideTextOptionsBar {
    if (!self.textOptionsBar || self.textOptionsBar.isHidden) {
        return;
    }
    [self.textOptionsBar setHidden:YES];
    [self layoutContentSubviews];
    [self scrollCanvasVerticallyBy:-self.textBarScrollDelta];
    self.textBarScrollDelta = 0.0f;
    self.canvasView.suspendsFitUpdates = NO;
    [self.canvasView updateForEnclosingBoundsChange];
    [self logWindowFrame:@"text bar hidden"];
}

- (NSFont *)currentTextFont {
    return [self.canvasView activeTextEntry].font ?: [self.canvasView effectiveTextFont];
}

- (void)refreshTextOptionsBar {
    STTextOptionsBar *bar = self.textOptionsBar;
    if (!bar || bar.isHidden) {
        return;
    }
    NSFont *font = [self currentTextFont];
    NSFontManager *fonts = [NSFontManager sharedFontManager];
    NSFont *bold = [fonts convertFont:font toHaveTrait:NSBoldFontMask];
    NSFont *italic = [fonts convertFont:font toHaveTrait:NSItalicFontMask];
    [bar updateWithFont:font
                  color:self.canvasView.textColor ?: STDefaultTextColor()
                  style:self.canvasView.textStyle
             sizePreset:self.canvasView.textSizePreset
              alignment:self.canvasView.textAlignment
          boldAvailable:![bold.fontName isEqualToString:font.fontName]
        italicAvailable:![italic.fontName isEqualToString:font.fontName]];
    MarkupText *entry = [self.canvasView activeTextEntry];
    [bar setPointerOn:entry.hasPointer available:(entry != nil)];
}

- (void)textSettingsChangedFromBar {
    [self refreshTextOptionsBar];
    [self.textPopoverController refresh];
}

- (void)toggleTextTrait:(NSFontTraitMask)trait {
    NSFont *font = [self currentTextFont];
    NSFontManager *fonts = [NSFontManager sharedFontManager];
    BOOL has = ([fonts traitsOfFont:font] & trait) != 0;
    NSFont *converted = has ? [fonts convertFont:font toNotHaveTrait:trait] : [fonts convertFont:font toHaveTrait:trait];
    if (!converted || [converted.fontName isEqualToString:font.fontName]) {
        NSBeep();
        return;
    }
    // Keep the preset: only the face changes, the size still comes from the image.
    [self applyTextFont:converted persist:YES];
    [self textSettingsChangedFromBar];
}

- (void)stepTextSizeBy:(CGFloat)delta {
    NSFont *font = [self currentTextFont];
    CGFloat size = MAX(6.0, MIN(400.0, round(font.pointSize + delta)));
    NSFont *resized = STFontWithSize(font, size);
    // Stepping picks an exact size.
    [self applyTextSizePreset:STTextSizePresetExact persist:YES];
    [self applyTextFont:resized persist:YES];
    [self textSettingsChangedFromBar];
}

- (void)textOptionsBar:(STTextOptionsBar *)bar didPickColor:(NSColor *)color {
    (void)bar;
    [self applyColor:color toTool:ScreenshotCanvasToolText persist:YES];
    [self textSettingsChangedFromBar];
}

- (void)textOptionsBar:(STTextOptionsBar *)bar didPickSizePreset:(STTextSizePreset)preset {
    (void)bar;
    [self applyTextSizePreset:preset persist:YES];
    [self textSettingsChangedFromBar];
}

- (void)textOptionsBar:(STTextOptionsBar *)bar didStepSizeBy:(CGFloat)delta {
    (void)bar;
    [self stepTextSizeBy:delta];
}

- (void)textOptionsBar:(STTextOptionsBar *)bar didPickStyle:(MarkupTextStyle)style {
    (void)bar;
    [self applyTextStyle:style persist:YES];
    [self textSettingsChangedFromBar];
}

- (void)textOptionsBarDidTogglePointer:(STTextOptionsBar *)bar {
    (void)bar;
    MarkupText *entry = [self.canvasView activeTextEntry];
    BOOL wasCallout = entry.hasPointer;
    [self.canvasView toggleActiveTextPointer];
    // A label made a callout becomes a filled box with bold text (v0.2.0, #221), whatever its
    // style was (new labels start in the default, Outline); the bar changes it afterwards. The
    // saved defaults stay as they are.
    if (entry && !wasCallout && entry.hasPointer) {
        [self applyTextStyle:MarkupTextStyleBackground persist:NO];
        NSFont *font = [self currentTextFont];
        NSFont *bold = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSBoldFontMask];
        if (bold && ![bold.fontName isEqualToString:font.fontName]) {
            [self applyTextFont:bold persist:NO];
        }
    }
    [self textSettingsChangedFromBar];
}

- (void)textOptionsBar:(STTextOptionsBar *)bar didPickFontFamily:(NSString *)family {
    (void)bar;
    NSFont *font = [self currentTextFont];
    NSFont *converted = [[NSFontManager sharedFontManager] convertFont:font toFamily:family];
    if (converted) {
        [self applyTextFont:converted persist:YES];
    }
    [self textSettingsChangedFromBar];
}

- (void)textOptionsBarDidFinishFontEntry:(STTextOptionsBar *)bar {
    (void)bar;
    [self.canvasView focusActiveTextView];
}

- (void)textOptionsBarDidToggleBold:(STTextOptionsBar *)bar {
    (void)bar;
    [self toggleTextTrait:NSBoldFontMask];
}

- (void)textOptionsBarDidToggleItalic:(STTextOptionsBar *)bar {
    (void)bar;
    [self toggleTextTrait:NSItalicFontMask];
}

- (void)textOptionsBar:(STTextOptionsBar *)bar didPickAlignment:(NSTextAlignment)alignment {
    (void)bar;
    [self applyTextAlignment:alignment persist:YES];
    [self textSettingsChangedFromBar];
}

- (void)canvasViewDidChangeZoom:(NSNotification *)notification {
    (void)notification;
    [self reflectZoomSelection];
}

- (void)canvasViewRequestsTool:(NSNotification *)notification {
    NSNumber *tool = notification.userInfo[ScreenshotCanvasViewToolKey];
    if (tool) {
        [self selectTool:(ScreenshotCanvasTool)tool.integerValue];
    }
}

- (void)canvasViewDidBeginTextEditing:(NSNotification *)notification {
    (void)notification;
    [self showTextOptionsBar];
    // Once per launch: enough to learn it without nagging on every label.
    static BOOL shownHint = NO;
    if (shownHint) {
        return;
    }
    shownHint = YES;
#if defined(GNUSTEP)
    [self showTransientFeedbackMessage:@"Ctrl+Return or Esc to finish · Return for a new line" duration:3.5];
#else
    [self showTransientFeedbackMessage:@"⌘Return or Esc to finish · Return for a new line" duration:3.5];
#endif
}

- (NSImage *)toolbarSegmentImageForTool:(ScreenshotCanvasTool)tool selected:(BOOL)selected {
    (void)selected;
    NSString *identifier = [self identifierForTool:tool];
    NSString *stem = [self baseIconStemForToolbarIdentifier:identifier];
    NSImage *image = [self baselineToolbarImageNamed:stem active:NO];
    if (!image) {
        return nil;
    }
#if defined(GNUSTEP)
    NSString *symbolicName = STSymbolicCopyName(image, @"segment");
    NSImage *kept = symbolicName ? STSymbolicCopies()[symbolicName] : nil;
    if (kept) {
        return kept;
    }
#endif
    NSImage *copy = [image copy];
    [copy setSize:NSMakeSize(STToolbarToolIconSize, STToolbarToolIconSize)];
#if defined(GNUSTEP)
    copy = STKeepSymbolicCopy(copy, symbolicName);
#endif
    return copy;
}

- (void)adjustToolbarCustomViewVerticalOffset:(NSView *)view {
#if defined(GNUSTEP)
    if (!view || !view.superview) {
        return;
    }
    NSRect frame = view.frame;
    CGFloat adjustedY = MAX(0.0f, floor((NSHeight(view.superview.bounds) - NSHeight(frame)) * 0.5f));
    if (fabs(frame.origin.y - adjustedY) < 0.5f) {
        return;
    }
    frame.origin.y = adjustedY;
    [view setFrame:frame];
#else
    // AppKit centres toolbar item views itself.
    (void)view;
#endif
}

- (NSToolbarItem *)toolbarItemForToolControl {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ToolbarItemTools];
    item.label = @"";
    item.paletteLabel = @"Tools";
    item.toolTip = [self toolTipForIdentifier:ToolbarItemTools];
    item.target = self;
    item.action = @selector(toolbarToolControlAction:);

    if (!self.toolbarToolSegmentedControl) {
        CGFloat toolControlWidth = STToolbarToolSegmentWidth * (CGFloat)STToolbarToolSegmentCount;
        self.toolbarToolSegmentedControl = [[STToolbarSegmentedControl alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, toolControlWidth, STToolbarToolControlHeight)];
        [self.toolbarToolSegmentedControl setSegmentCount:STToolbarToolSegmentCount];
        [self.toolbarToolSegmentedControl setTarget:self];
        [self.toolbarToolSegmentedControl setAction:@selector(toolbarToolControlAction:)];
#ifdef NSSegmentStyleRounded
        [self.toolbarToolSegmentedControl setSegmentStyle:NSSegmentStyleRounded];
#endif
        NSSegmentedCell *cell = (NSSegmentedCell *)[self.toolbarToolSegmentedControl cell];
        [cell setTrackingMode:NSSegmentSwitchTrackingSelectOne];
        for (NSInteger segment = 0; segment < STToolbarToolSegmentCount; segment++) {
            ScreenshotCanvasTool tool = [self toolbarToolForSegmentIndex:segment];
            [self.toolbarToolSegmentedControl setWidth:STToolbarToolSegmentWidth forSegment:segment];
            [self.toolbarToolSegmentedControl setLabel:@"" forSegment:segment];
            [cell setToolTip:[self toolbarSegmentToolTipForTool:tool] forSegment:segment];
        }
        STApplyAccessibilityLabel(self.toolbarToolSegmentedControl, @"Tool switcher");
        STInstallSegmentToolTips(self.toolbarToolSegmentedControl);
    }
    [self refreshToolbarToolsControl];
    item.view = self.toolbarToolSegmentedControl;
    item.minSize = self.toolbarToolSegmentedControl.frame.size;
    item.maxSize = self.toolbarToolSegmentedControl.frame.size;
    return item;
}

- (void)refreshToolbarToolsControl {
    if (!self.toolbarToolSegmentedControl) {
        return;
    }
    NSSegmentedCell *cell = (NSSegmentedCell *)[self.toolbarToolSegmentedControl cell];
    NSInteger selectedSegment = [self toolbarSegmentIndexForTool:self.canvasView.activeTool];
    for (NSInteger segment = 0; segment < STToolbarToolSegmentCount; segment++) {
        ScreenshotCanvasTool tool = [self toolbarToolForSegmentIndex:segment];
        BOOL isSelected = (segment == selectedSegment);
        NSImage *image = [self toolbarSegmentImageForTool:tool selected:isSelected];
        if (image) {
            [self.toolbarToolSegmentedControl setImage:image forSegment:segment];
        }
        [self.toolbarToolSegmentedControl setSelected:isSelected forSegment:segment];
        [cell setToolTip:[self toolbarSegmentToolTipForTool:tool] forSegment:segment];
    }
    [self.toolbarToolSegmentedControl setSelectedSegment:selectedSegment];
    [self updateDrawingToolsForImage:[self.canvasView hasImage]];
    [self.toolbarToolSegmentedControl setNeedsDisplay:YES];
    [self adjustToolbarCustomViewVerticalOffset:self.toolbarToolSegmentedControl];
}

- (void)toolbarToolControlAction:(id)sender {
    if (![sender isKindOfClass:[STToolbarSegmentedControl class]]) {
        return;
    }
    STToolbarSegmentedControl *control = (STToolbarSegmentedControl *)sender;
    NSInteger selectedSegment = control.clickedSegment;
    if (selectedSegment < 0) {
        selectedSegment = [control selectedSegment];
    }
    ScreenshotCanvasTool tool = [self toolbarToolForSegmentIndex:selectedSegment];
    NSEvent *event = [NSApp currentEvent];
    BOOL openPopover = (control.lastClickCount >= 2);
    ScreenshotToolAppendLog([NSString stringWithFormat:@"Segmented tool action tool=%@ clickCount=%ld event=%@",
                             STDebugToolName(tool),
                             (long)control.lastClickCount,
                             STDebugDescriptionForEvent(event)]);
    [self selectTool:tool];
    if (openPopover && STToolHasSettingsPopover(tool)) {
        NSView *anchorView = self.window.contentView;
        if (anchorView) {
            CGFloat segmentWidth = [control widthForSegment:selectedSegment];
            if (segmentWidth <= 0.0f) {
                segmentWidth = floor(control.bounds.size.width / MAX((CGFloat)[control segmentCount], 1.0f));
            }
            CGFloat originX = 0.0f;
            for (NSInteger segment = 0; segment < selectedSegment; segment++) {
                CGFloat width = [control widthForSegment:segment];
                if (width <= 0.0f) {
                    width = segmentWidth;
                }
                originX += width;
            }
            NSRect segmentRect = NSMakeRect(originX, 0.0f, segmentWidth, control.bounds.size.height);
            NSPoint sourcePoint = NSMakePoint(NSMidX(segmentRect), NSMinY(segmentRect) + 2.0f);
            NSPoint windowPoint = [control convertPoint:sourcePoint toView:nil];
            NSPoint anchorPoint = [anchorView convertPoint:windowPoint fromView:nil];
            NSRect anchor = NSMakeRect(anchorPoint.x - 2.0f, anchorPoint.y - 2.0f, 4.0f, 4.0f);
            [self showToolSettingsPopoverForTool:tool anchorRect:anchor ofView:anchorView event:event];
        }
    }
    control.clickedSegment = -1;
}

- (NSToolbarItem *)toolbarItemForColorControl {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ToolbarItemColor];
    item.label = @"";
    item.paletteLabel = @"Color";
    item.toolTip = [self toolTipForIdentifier:ToolbarItemColor];
    item.target = self;
    item.action = @selector(showActiveToolColorSettings:);

    if (!self.toolbarColorWellView) {
        self.toolbarColorWellView = [[STToolbarColorWellView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, STToolbarColorControlWidth, STToolbarColorControlHeight)];
        self.toolbarColorWellView.target = self;
        self.toolbarColorWellView.action = @selector(showActiveToolColorSettings:);
    }
    item.view = self.toolbarColorWellView;
    item.minSize = self.toolbarColorWellView.frame.size;
    item.maxSize = self.toolbarColorWellView.frame.size;
    return item;
}

- (void)refreshBaselineToolbarIcons {
    if (!self.toolbar) {
        return;
    }
    NSToolbarItemIdentifier activeIdentifier = [self identifierForTool:self.canvasView.activeTool];
    for (NSToolbarItem *item in self.toolbar.items) {
        NSString *identifier = item.itemIdentifier;
        if (!identifier || [identifier isEqualToString:ToolbarItemZoom]) {
            continue;
        }
        NSString *stem = [self baseIconStemForToolbarIdentifier:identifier];
        if (stem.length == 0) {
            continue;
        }
        BOOL isActive = activeIdentifier && [identifier isEqualToString:activeIdentifier];
        NSImage *image = [self baselineToolbarImageNamed:stem active:isActive];
        if (image) {
            item.image = image;
        }
    }
}

- (void)refreshToolbarColorControl {
    NSToolbarItem *item = nil;
    for (NSToolbarItem *candidate in self.toolbar.items) {
        if ([candidate.itemIdentifier isEqualToString:ToolbarItemColor]) {
            item = candidate;
            break;
        }
    }
    if (!item || ![item.view isKindOfClass:[STToolbarColorWellView class]]) {
        return;
    }
    STToolbarColorWellView *colorWellView = (STToolbarColorWellView *)item.view;
    ScreenshotCanvasTool activeTool = self.canvasView.activeTool;
    BOOL usesColor = STToolUsesColor(activeTool);
    // Dimmed with no image, as the tools are (#221), but still showing the tool's colour.
    BOOL enabled = usesColor && [self.canvasView hasImage];
    NSColor *color = usesColor ? [self currentColorForTool:activeTool] : nil;
    [colorWellView setEnabled:enabled];
    [colorWellView setColor:color];
    item.enabled = enabled;
    [self applyToolTipToToolbarItem:item source:@"refresh-color"];
    [self adjustToolbarCustomViewVerticalOffset:colorWellView];
    if (usesColor) {
        STApplyAccessibilityLabel(colorWellView, [NSString stringWithFormat:@"%@ color", STDebugToolName(activeTool)]);
    } else {
        STApplyAccessibilityLabel(colorWellView, @"Color settings unavailable for current tool");
    }
}

- (NSImage *)baselineToolbarImageNamed:(NSString *)name active:(BOOL)active {
    if (name.length == 0) {
        return nil;
    }

    static NSMutableDictionary<NSString *, NSImage *> *baselineToolbarCache = nil;
    if (!baselineToolbarCache) {
        baselineToolbarCache = [[NSMutableDictionary alloc] init];
    }

    NSMutableArray<NSString *> *candidates = [[NSMutableArray alloc] init];
    // One monochrome set the theme tints (#57).
    [candidates addObject:STSymbolicIconName(name)];
    [candidates addObject:name];

    for (NSString *candidate in candidates) {
        if (candidate.length == 0) {
            continue;
        }
        NSImage *cached = baselineToolbarCache[candidate];
        if (cached) {
            return cached;
        }
        NSImage *image = STSizedToolbarIcon(candidate, NSMakeSize(ToolbarIconDimension, ToolbarIconDimension));
        if (!image) {
            NSString *path = STPathForToolbarResource(candidate, @"png");
            if (!path) {
                continue;
            }
#if defined(GNUSTEP)
            image = STBitmapBackedImageFromFile(path, NSMakeSize(ToolbarIconDimension, ToolbarIconDimension));
#else
            image = [[NSImage alloc] initWithContentsOfFile:path];
#endif
        }
        if (image) {
            [image setSize:NSMakeSize(ToolbarIconDimension, ToolbarIconDimension)];
            STMarkSymbolicIcon(image, candidate);
            baselineToolbarCache[candidate] = image;
            return image;
        }
    }
    // A new tool before its icon file is in (#221): a plain drawn one. Not named as a symbolic
    // icon: Adwaita tints those from their file, and there's none yet.
    if ([name isEqualToString:@"Rectangle"] || [name isEqualToString:@"NumberedStep"] || [name isEqualToString:@"Redact"]) {
        BOOL ring = [name isEqualToString:@"NumberedStep"];
        BOOL checker = [name isEqualToString:@"Redact"];
        NSString *symbolic = STSymbolicIconName(name);
        NSImage *drawn = baselineToolbarCache[symbolic];
        if (!drawn) {
            // Into a bitmap, which survives the copies the segments make of it.
            NSInteger pixels = (NSInteger)ToolbarIconDimension;
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:pixels pixelsHigh:pixels
                                                                          bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                         colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            // Pixels set directly: no graphics context exists yet at launch on GNUstep. An
            // antialiased rounded-rectangle outline, from its distance to the box's edge.
            unsigned char *data = [rep bitmapData];
            NSInteger stride = [rep bytesPerRow];
            // A rounded rectangle, or a ring for a step.
            CGFloat halfWidth = pixels * (ring ? 0.26 : 0.30), halfHeight = pixels * (ring ? 0.26 : 0.22);
            CGFloat radius = ring ? halfWidth : pixels * 0.09;
            CGFloat stroke = pixels / 12.0;
            for (NSInteger y = 0; y < pixels; y++) {
                for (NSInteger x = 0; x < pixels; x++) {
                    CGFloat qx = fabs((x + 0.5) - pixels * 0.5) - (halfWidth - radius);
                    CGFloat qy = fabs((y + 0.5) - pixels * 0.5) - (halfHeight - radius);
                    CGFloat outside = hypot(MAX(qx, 0.0), MAX(qy, 0.0)) + MIN(MAX(qx, qy), 0.0) - radius;
                    CGFloat alpha = MAX(0.0, MIN(1.0, stroke * 0.5 + 0.5 - fabs(outside)));
                    if (checker && outside < 0.0) {
                        // Redact: the box filled with a checkerboard of cells, every other one solid.
                        NSInteger cell = MAX(1, pixels / 8);
                        if (((x / cell) + (y / cell)) % 2 == 0) {
                            alpha = 1.0;
                        }
                    }
                    unsigned char *pixel = data + (y * stride) + (x * 4);
                    unsigned char value = (unsigned char)lround(alpha * 255.0);
                    // Premultiplied dark grey.
                    pixel[0] = pixel[1] = pixel[2] = (unsigned char)lround(alpha * 51.0);
                    pixel[3] = value;
                }
            }
            drawn = [[NSImage alloc] initWithSize:NSMakeSize(ToolbarIconDimension, ToolbarIconDimension)];
            [drawn addRepresentation:rep];
            baselineToolbarCache[symbolic] = drawn;
        }
        return drawn;
    }
#ifdef NSImageNameAddTemplate
    NSImage *fallback = [NSImage imageNamed:NSImageNameAddTemplate];
    if (fallback) {
        return fallback;
    }
#endif
    return nil;
}

- (NSColor *)badgeColorForToolbarIdentifier:(NSToolbarItemIdentifier)identifier {
    if ([identifier isEqualToString:ToolbarItemPen] || [identifier isEqualToString:ToolbarItemArrow] ||
        [identifier isEqualToString:ToolbarItemRectangle] || [identifier isEqualToString:ToolbarItemStep]) {
        return self.canvasView.penColor;
    }
    if ([identifier isEqualToString:ToolbarItemHighlighter]) {
        return self.canvasView.highlighterColor;
    }
    if ([identifier isEqualToString:ToolbarItemText]) {
        return self.canvasView.textColor;
    }
    return nil;
}

- (NSImage *)toolbarImageForIdentifier:(NSToolbarItemIdentifier)identifier active:(BOOL)active {
    NSImage *baseIcon = [self imageForToolbarIdentifier:identifier active:active];
    if (!baseIcon) {
        return nil;
    }
#if defined(GNUSTEP)
    NSString *symbolicName = STSymbolicCopyName(baseIcon, @"toolbar");
    NSImage *kept = symbolicName ? STSymbolicCopies()[symbolicName] : nil;
    if (kept) {
        return kept;
    }
#endif
    NSImage *rendered = [baseIcon copy];
    NSColor *badgeColor = [self badgeColorForToolbarIdentifier:identifier];
    if (badgeColor) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ color %@", identifier, [self debugDescriptionForColor:badgeColor]]);
    }
    [rendered setSize:NSMakeSize(ToolbarIconDimension, ToolbarIconDimension)];
#if defined(GNUSTEP)
    if (!STIsSizedToolbarIcon(rendered)) {
        rendered = [self bitmapBackedToolbarImageFromImage:rendered];
    }
    if (!STImageHasVisiblePixels(rendered)) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar image %@ still lacks visible pixels after rendering", identifier]);
    }
    rendered = STKeepSymbolicCopy(rendered, symbolicName);
#endif
    return rendered;
}

#if defined(GNUSTEP)
- (NSImage *)bitmapBackedToolbarImageFromImage:(NSImage *)image {
    if (!image) {
        return nil;
    }
    NSBitmapImageRep *bitmap = STDeviceBitmapRepresentationFromImage(image);
    if (!bitmap) {
        return image;
    }
    return STBitmapBackedImageFromBitmapRep(bitmap, image.size);
}
#endif

- (NSToolbarItem *)toolbarItemForZoomControl {
    if (!self.zoomToolbarButtonView) {
        CGFloat initialWidth = STToolbarZoomReservedControlWidth();
        self.zoomToolbarButtonView = [[STToolbarZoomButtonView alloc] initWithFrame:NSMakeRect(0, 0, initialWidth, STToolbarZoomControlHeight)];
        self.zoomToolbarButtonView.target = self;
        self.zoomToolbarButtonView.action = @selector(showZoomPopover:);
        self.zoomToolbarButtonView.title = @"100%";
        STApplyAccessibilityLabel(self.zoomToolbarButtonView, @"Zoom");
    }

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ToolbarItemZoom];
    item.label = @"";
    item.paletteLabel = @"Zoom";
    item.view = self.zoomToolbarButtonView;
    item.minSize = self.zoomToolbarButtonView.frame.size;
    item.maxSize = self.zoomToolbarButtonView.frame.size;
    [self refreshZoomToolbarControl];
    return item;
}

- (void)refreshZoomToolbarControl {
    if (!self.zoomToolbarButtonView) {
        return;
    }

    BOOL hasImage = [self.canvasView hasImage];
    NSString *title = @"100%";
    if (hasImage) {
        title = self.canvasView.isFitToWindow ? @"Fit" : [self displayStringForScale:self.canvasView.displayZoomScale];
    }

    self.zoomToolbarButtonView.title = title;
    self.zoomToolbarButtonView.enabled = hasImage;
    CGFloat targetWidth = STToolbarZoomReservedControlWidth();
    NSRect zoomFrame = self.zoomToolbarButtonView.frame;
    if (fabs(zoomFrame.size.width - targetWidth) >= 0.5f ||
        fabs(zoomFrame.size.height - STToolbarZoomControlHeight) >= 0.5f) {
        zoomFrame.size = NSMakeSize(targetWidth, STToolbarZoomControlHeight);
        [self.zoomToolbarButtonView setFrame:zoomFrame];
    }
    [self.zoomToolbarButtonView setNeedsDisplay:YES];

    NSToolbarItem *item = nil;
    for (NSToolbarItem *candidate in self.toolbar.items) {
        if ([candidate.itemIdentifier isEqualToString:ToolbarItemZoom]) {
            item = candidate;
            break;
        }
    }
    if (item) {
        item.enabled = hasImage;
        item.minSize = NSMakeSize(targetWidth, STToolbarZoomControlHeight);
        item.maxSize = NSMakeSize(targetWidth, STToolbarZoomControlHeight);
        [self applyToolTipToToolbarItem:item source:@"refresh-zoom"];
    }
    [self adjustToolbarCustomViewVerticalOffset:self.zoomToolbarButtonView];
    NSString *accessibility = hasImage ? [NSString stringWithFormat:@"Zoom %@", title] : @"Zoom unavailable";
    STApplyAccessibilityLabel(self.zoomToolbarButtonView, accessibility);
}

#pragma mark - Status Bar

- (void)setupStatusControls {
    if (!self.statusBarView) {
        return;
    }

    // Zoom at the bar's end, as Paint and Photos have it: out, a slider, in, the scale and Fit
    // (#221). The slider is logarithmic, as the zoom popover's is.
    NSView *zoomContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    zoomContainer.autoresizingMask = (NSViewMinXMargin | NSViewHeightSizable);
    self.statusZoomContainer = zoomContainer;
    [self.statusBarView addSubview:zoomContainer];

    self.statusZoomOutButton = [self statusZoomButtonWithTitle:@"−" action:@selector(zoomOut:) label:@"Zoom out"];
    [zoomContainer addSubview:self.statusZoomOutButton];

    NSSlider *zoomSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    [zoomSlider setMinValue:0.0];
    [zoomSlider setMaxValue:1.0];
    [zoomSlider setContinuous:YES];
    [zoomSlider setNumberOfTickMarks:0];
    zoomSlider.target = self;
    zoomSlider.action = @selector(statusZoomSliderChanged:);
    self.statusZoomSlider = zoomSlider;
    STApplyAccessibilityLabel(zoomSlider, @"Zoom");
    [zoomContainer addSubview:zoomSlider];

    self.statusZoomInButton = [self statusZoomButtonWithTitle:@"+" action:@selector(zoomIn:) label:@"Zoom in"];
    [zoomContainer addSubview:self.statusZoomInButton];

    STStatusTextField *zoomLabel = [[STStatusTextField alloc] initWithFrame:NSZeroRect];
    [zoomLabel setEditable:NO];
    [zoomLabel setBezeled:NO];
    [zoomLabel setBordered:NO];
    [zoomLabel setDrawsBackground:NO];
    [zoomLabel setAlignment:NSTextAlignmentRight];
    [zoomLabel setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [zoomLabel setTextColor:STThemeStatusValueTextColor()];
    self.statusZoomLabel = zoomLabel;
    [zoomContainer addSubview:zoomLabel];

    NSButton *fitButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    fitButton.title = @"Fit";
#ifdef NSRoundedBezelStyle
    [fitButton setBezelStyle:NSRoundedBezelStyle];
#endif
    [fitButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    fitButton.target = self;
    fitButton.action = @selector(zoomFitToWindow:);
    fitButton.toolTip = @"Fit to Window";
    STApplyAccessibilityLabel(fitButton, @"Fit to window");
    self.statusZoomFitButton = fitButton;
    [zoomContainer addSubview:fitButton];

    // Hidden with the status bar (the default), so launch doesn't size these controls.
    // refreshStatusZoomControls shows them, with an image, and lays them out.
    zoomContainer.hidden = YES;
    [self refreshStatusZoomControls];
}

- (NSButton *)statusZoomButtonWithTitle:(NSString *)title action:(SEL)action label:(NSString *)label {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.title = title;
    [button setBordered:NO];
    [button setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
    button.target = self;
    button.action = action;
    button.toolTip = label;
    STApplyAccessibilityLabel(button, label);
    return button;
}

- (void)statusZoomSliderChanged:(NSSlider *)sender {
    if (![self.canvasView hasImage]) {
        return;
    }
    [self setZoomScale:STZoomScaleForSliderFraction(sender.doubleValue)];
}

/// The zoom controls and, while no message shows, the image's size and format (#221).
- (void)refreshStatusZoomControls {
    BOOL hasImage = [self.canvasView hasImage];
    if (self.statusZoomContainer) {
        BOOL hidden = !self.statusBarVisiblePreference || !hasImage;
        if (self.statusZoomContainer.isHidden != hidden) {
            self.statusZoomContainer.hidden = hidden;
            [self layoutStatusControls];
        }
    }
    if (hasImage) {
        CGFloat scale = self.canvasView.displayZoomScale;
        self.statusZoomSlider.doubleValue = STZoomSliderFractionForScale(scale);
        self.statusZoomLabel.stringValue = [self displayStringForScale:scale];
    }
    if (self.statusTextField && !self.statusClearTimer) {
        [self.statusTextField setStringValue:[self idleStatusText]];
    }
}

/// "1600 × 1000 px · PNG · 214 KB": the image's pixel size and, with a file, its format and size.
- (NSString *)idleStatusText {
    NSImage *image = self.canvasView.image;
    if (!image) {
        return @"";
    }
    NSSize pixels = image.size;
    for (NSImageRep *rep in image.representations) {
        if (rep.pixelsWide > 0 && rep.pixelsHigh > 0) {
            pixels = NSMakeSize(rep.pixelsWide, rep.pixelsHigh);
            break;
        }
    }
    NSString *text = [NSString stringWithFormat:@"%.0f × %.0f px", pixels.width, pixels.height];
    NSString *extension = self.currentImageURL.pathExtension;
    if (extension.length > 0) {
        text = [text stringByAppendingFormat:@"  ·  %@", extension.uppercaseString];
    }
    NSString *fileSize = [self statusFileSizeForURL:self.currentImageURL];
    if (fileSize.length > 0) {
        text = [text stringByAppendingFormat:@"  ·  %@", fileSize];
    }
    return text;
}

/// The size of the image's file, as Finder and Explorer give it ("214 KB", "1.2 MB"), or nil
/// when the image has no file. Read once per file, not on every refresh.
- (nullable NSString *)statusFileSizeForURL:(nullable NSURL *)url {
    if (!url.isFileURL) {
        return nil;
    }
    if ([url isEqual:self.statusFileSizeURL]) {
        return self.statusFileSizeText;
    }
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:NULL];
    NSNumber *size = attributes[NSFileSize];
    self.statusFileSizeURL = url;
    self.statusFileSizeText = size ? STFileSizeString(size.unsignedLongLongValue) : nil;
    return self.statusFileSizeText;
}

- (void)layoutStatusControls {
    if (!self.statusBarView || !self.statusTextField) {
        return;
    }

    NSRect bounds = self.statusBarView.bounds;
    CGFloat padding = 8.0f;
    CGFloat verticalInset = 4.0f;
    CGFloat availableHeight = MAX(0.0f, bounds.size.height - (verticalInset * 2.0f));

    // The image's size and format on the left, the zoom controls at the end (#221).
    CGFloat rightEdge = bounds.size.width - padding;
    if (self.statusZoomContainer && !self.statusZoomContainer.isHidden) {
        CGFloat zoomWidth = [self layoutStatusZoomControlsWithRightEdge:rightEdge
                                                          verticalInset:verticalInset
                                                                 height:availableHeight];
        rightEdge -= zoomWidth + (padding * 2.0f);
    }

    CGFloat textWidth = MAX(0.0f, rightEdge - padding);
    self.statusTextField.frame = NSMakeRect(padding,
                                            verticalInset,
                                            textWidth,
                                            availableHeight);
}

/// Lays the zoom controls out to end at rightEdge and returns their width.
- (CGFloat)layoutStatusZoomControlsWithRightEdge:(CGFloat)rightEdge
                                   verticalInset:(CGFloat)verticalInset
                                          height:(CGFloat)height {
    CGFloat buttonWidth = 24.0f;
    CGFloat sliderWidth = 120.0f;
    CGFloat labelWidth = 44.0f;
    [self.statusZoomFitButton sizeToFit];
    CGFloat fitWidth = MAX(40.0f, NSWidth(self.statusZoomFitButton.frame));
    CGFloat spacing = 6.0f;
    CGFloat width = buttonWidth + sliderWidth + buttonWidth + labelWidth + fitWidth + (spacing * 4.0f);
    self.statusZoomContainer.frame = NSMakeRect(rightEdge - width, verticalInset, width, height);

    CGFloat controlHeight = MIN(height, 24.0f);
    CGFloat controlY = floor((height - controlHeight) / 2.0f);
    CGFloat labelHeight = MIN(height, 18.0f);
    CGFloat x = 0.0f;
    self.statusZoomOutButton.frame = NSMakeRect(x, controlY, buttonWidth, controlHeight);
    x += buttonWidth + spacing;
    self.statusZoomSlider.frame = NSMakeRect(x, controlY, sliderWidth, controlHeight);
    x += sliderWidth + spacing;
    self.statusZoomInButton.frame = NSMakeRect(x, controlY, buttonWidth, controlHeight);
    x += buttonWidth + spacing;
    self.statusZoomLabel.frame = NSMakeRect(x, floor((height - labelHeight) / 2.0f), labelWidth, labelHeight);
    x += labelWidth + spacing;
    self.statusZoomFitButton.frame = NSMakeRect(x, controlY, fitWidth, controlHeight);
    return width;
}

- (CGFloat)statusBarHeight {
    return self.statusBarVisiblePreference ? StatusBarHeight : 0.0f;
}

- (void)updateStatusBarVisibility {
    BOOL show = self.statusBarVisiblePreference;
    CGFloat previousHeight = (self.statusBarView ? self.statusBarView.frame.size.height : 0.0f);
    CGFloat targetHeight = show ? StatusBarHeight : 0.0f;
    if (self.statusBarView) {
        [self.statusBarView setHidden:!show];
    }
    if (self.statusTextField) {
        [self.statusTextField setHidden:!show];
    }
    [self refreshStatusZoomControls];
    if (!show) {
        [self.statusClearTimer invalidate];
        self.statusClearTimer = nil;
    }
    if (self.window) {
        NSView *contentView = self.window.contentView;
        if (contentView) {
            NSSize contentSize = contentView.frame.size;
            CGFloat delta = targetHeight - previousHeight;
            if (fabs(delta) > 0.5f) {
                // The minimum includes the status bar, so it moves with it.
                NSSize minimumSize = self.window.contentMinSize;
                if (minimumSize.height > 1.0f) {
                    minimumSize.height = MAX(1.0f, minimumSize.height + delta);
                    [self.window setContentMinSize:minimumSize];
                }
                CGFloat newHeight = MAX(1.0f, contentSize.height + delta);
                [self.window setContentSize:NSMakeSize(contentSize.width, newHeight)];
            }
        }
    }
    [self layoutContentSubviews];
}

#if defined(GNUSTEP)
- (void)themeDidActivate:(NSNotification *)notification {
    (void)notification;
    // A newly activated theme brings its own colours.
    [self refreshInterfaceThemeAppearance];
}
#endif

- (void)refreshInterfaceThemeAppearance {
#if defined(GNUSTEP)
    if ([self.statusBarView isKindOfClass:[STStatusBarBackgroundView class]]) {
        STStatusBarBackgroundView *backgroundView = (STStatusBarBackgroundView *)self.statusBarView;
        backgroundView.fillColor = STThemeStatusBarBackgroundColor();
        backgroundView.topBorderColor = STThemeStatusBarBorderColor();
    }
#endif
    if (self.window) {
        [self.window setBackgroundColor:STThemeWindowBackgroundColor()];
    }
    if (self.statusTextField) {
        [self.statusTextField setTextColor:STThemeStatusPrimaryTextColor()];
    }
    if (self.zoomToolbarLabel) {
        [self.zoomToolbarLabel setTextColor:STThemeToolbarLabelColor()];
    }
    if (self.statusZoomLabel) {
        [self.statusZoomLabel setTextColor:STThemeStatusValueTextColor()];
    }
    if (self.statusBarView) {
        [self.statusBarView setNeedsDisplay:YES];
    }
    if (self.canvasView) {
        [self.canvasView setNeedsDisplay:YES];
    }
    if ([self.scrollView.contentView isKindOfClass:[STCanvasClipView class]]) {
        [self.scrollView.contentView setBackgroundColor:STThemeCanvasBackdropColor()];
        [self.scrollView.contentView setNeedsDisplay:YES];
    }
    if (self.window.contentView) {
        [self.window.contentView setNeedsDisplay:YES];
    }
    [self updateHUDAppearance];
    [self refreshToolButtonIcons];
    [self.zoomToolbarButtonView setNeedsDisplay:YES];
    [self.zoomPopoverController refresh];
    [self.preferencesWindowController refresh];
}

- (void)loadToolSettingsFromDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.penDefaultWidth = [self storedWidthForKey:STDefaultsPenDefaultWidthKey
                                          fallback:STPenWidthDefault
                               registerIfMissing:YES];
    self.highlighterDefaultWidth = [self storedWidthForKey:STDefaultsHighlighterDefaultWidthKey
                                                  fallback:STHighlighterWidthDefault
                                       registerIfMissing:YES];

    CGFloat penWidth = [self storedWidthForKey:STDefaultsPenWidthKey
                                      fallback:self.penDefaultWidth
                           registerIfMissing:YES];
    CGFloat highlighterWidth = [self storedWidthForKey:STDefaultsHighlighterWidthKey
                                              fallback:self.highlighterDefaultWidth
                                   registerIfMissing:YES];

    self.canvasView.penLineWidth = penWidth;
    self.canvasView.highlighterLineWidth = highlighterWidth;

    self.penDefaultColor = [self storedColorForKey:STDefaultsPenDefaultColorKey
                                          fallback:STDefaultPenColor()
                               registerIfMissing:YES];
    self.highlighterDefaultColor = [self storedColorForKey:STDefaultsHighlighterDefaultColorKey
                                                  fallback:STDefaultHighlighterColor()
                                       registerIfMissing:YES];
    self.textDefaultColor = [self storedColorForKey:STDefaultsTextDefaultColorKey
                                           fallback:STDefaultTextColor()
                                registerIfMissing:YES];
    self.textDefaultFont = [self storedFontWithNameKey:STDefaultsTextDefaultFontNameKey
                                               sizeKey:STDefaultsTextDefaultFontSizeKey
                                              fallback:STDefaultTextFont()
                                   registerIfMissing:YES];
    self.textDefaultStyle = (MarkupTextStyle)STStoredTextStyle(STDefaultsTextDefaultStyleKey, STDefaultTextStyle());
    self.textDefaultSizePreset = STStoredTextSizePreset(STDefaultsTextDefaultSizePresetKey, STDefaultTextSizePreset());
    self.textDefaultAlignment = STStoredTextAlignment(STDefaultsTextDefaultAlignmentKey, NSTextAlignmentLeft);

    NSColor *penColor = [self storedColorForKey:STDefaultsPenColorKey
                                       fallback:self.penDefaultColor
                            registerIfMissing:YES];
    NSColor *highlighterColor = [self storedColorForKey:STDefaultsHighlighterColorKey
                                              fallback:self.highlighterDefaultColor
                                   registerIfMissing:YES];
    NSColor *textColor = [self storedColorForKey:STDefaultsTextColorKey
                                         fallback:self.textDefaultColor
                              registerIfMissing:YES];
    NSFont *textFont = [self storedFontWithNameKey:STDefaultsTextFontNameKey
                                           sizeKey:STDefaultsTextFontSizeKey
                                          fallback:self.textDefaultFont
                               registerIfMissing:YES];

    self.canvasView.penColor = penColor;
    self.canvasView.highlighterColor = highlighterColor;
    self.canvasView.textColor = textColor;
    self.canvasView.textFont = textFont;
    self.canvasView.textStyle = (MarkupTextStyle)STStoredTextStyle(STDefaultsTextStyleKey, self.textDefaultStyle);
    self.canvasView.textSizePreset = STStoredTextSizePreset(STDefaultsTextSizePresetKey, self.textDefaultSizePreset);
    self.canvasView.textAlignment = STStoredTextAlignment(STDefaultsTextAlignmentKey, self.textDefaultAlignment);
    [self.canvasView refreshCursor];
    [self refreshToolButtonIcons];

    NSString *savedDirectory = [defaults stringForKey:STDefaultsSaveDirectoryKey];
    if (savedDirectory.length == 0) {
        savedDirectory = STDefaultSaveDirectoryPath();
        [defaults setObject:savedDirectory forKey:STDefaultsSaveDirectoryKey];
    }
    self.defaultSaveDirectory = savedDirectory;
    [self ensureDirectoryExistsAtPath:self.defaultSaveDirectory];

    // The app's old "Show toolbar in the title bar" checkbox saved GnomeThemeHeaderBarToolbar here,
    // which outranks the user's choice for all apps in the theme. Clear it once (#58); a value the
    // user sets for this app afterwards is theirs.
    if (![defaults boolForKey:STDefaultsClearedHeaderBarToolbarKey]) {
        [defaults removeObjectForKey:STGnomeThemeHeaderBarToolbarKey];
        [defaults setBool:YES forKey:STDefaultsClearedHeaderBarToolbarKey];
    }

    // Shown unless the user turned it off (#221; it was off by default before, #54). A registered
    // default, so nothing is written until they choose, and a saved "off" stays off.
    [defaults registerDefaults:@{STDefaultsShowStatusBarKey: @YES, STDefaultsShowSelectionBarKey: @YES}];
    self.statusBarVisiblePreference = [defaults boolForKey:STDefaultsShowStatusBarKey];
    [self updateStatusBarVisibility];
    self.selectionBarPreference = [defaults boolForKey:STDefaultsShowSelectionBarKey];
    [self updateSelectionActionBar];

    if (self.preferencesWindowController) {
        [self.preferencesWindowController refresh];
    }
}

- (CGFloat)storedWidthForKey:(NSString *)key
                    fallback:(CGFloat)fallback
         registerIfMissing:(BOOL)registerDefault {
    if (key.length == 0) {
        return fallback;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id value = [defaults objectForKey:key];
    if (!value) {
        if (registerDefault) {
            [defaults setDouble:fallback forKey:key];
        }
        return [self clampedWidth:fallback];
    }
    double number = [value doubleValue];
    if (number <= 0.0) {
        number = fallback;
    }
    return [self clampedWidth:(CGFloat)number];
}

- (NSString *)titleForToolWidth:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolPen:
            return @"Pen Width";
        case ScreenshotCanvasToolArrow:
            return @"Arrow Width";
        case ScreenshotCanvasToolRectangle:
            return @"Rectangle Width";
        case ScreenshotCanvasToolStep:
            return @"Step Size";
        case ScreenshotCanvasToolHighlighter:
            return @"Highlighter Width";
        default:
            break;
    }
    return @"Tool Width";
}

- (CGFloat)currentWidthForTool:(ScreenshotCanvasTool)tool {
    tool = STSettingsToolForTool(tool);
    switch (tool) {
        case ScreenshotCanvasToolPen:
            return [self clampedWidth:self.canvasView.penLineWidth];
        case ScreenshotCanvasToolHighlighter:
            return [self clampedWidth:self.canvasView.highlighterLineWidth];
        default:
            return 0.0f;
    }
}

- (CGFloat)defaultWidthForTool:(ScreenshotCanvasTool)tool {
    tool = STSettingsToolForTool(tool);
    switch (tool) {
        case ScreenshotCanvasToolPen:
            return [self clampedWidth:self.penDefaultWidth];
        case ScreenshotCanvasToolHighlighter:
            return [self clampedWidth:self.highlighterDefaultWidth];
        default:
            return STPenWidthDefault;
    }
}

- (CGFloat)clampedWidth:(CGFloat)value {
    if (value < STToolWidthMin) {
        return STToolWidthMin;
    }
    if (value > STToolWidthMax) {
        return STToolWidthMax;
    }
    return value;
}

- (void)setDefaultWidth:(CGFloat)width forTool:(ScreenshotCanvasTool)tool {
    tool = STSettingsToolForTool(tool);
    CGFloat clamped = [self clampedWidth:width];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    switch (tool) {
        case ScreenshotCanvasToolPen:
            self.penDefaultWidth = clamped;
            [defaults setDouble:clamped forKey:STDefaultsPenDefaultWidthKey];
            break;
        case ScreenshotCanvasToolHighlighter:
            self.highlighterDefaultWidth = clamped;
            [defaults setDouble:clamped forKey:STDefaultsHighlighterDefaultWidthKey];
            break;
        default:
            break;
    }
}

- (void)applyWidth:(CGFloat)width
           toTool:(ScreenshotCanvasTool)tool
          persist:(BOOL)persist {
    tool = STSettingsToolForTool(tool);
    CGFloat clamped = [self clampedWidth:width];
    switch (tool) {
        case ScreenshotCanvasToolPen:
            self.canvasView.penLineWidth = clamped;
            if (persist) {
                [[NSUserDefaults standardUserDefaults] setDouble:clamped forKey:STDefaultsPenWidthKey];
            }
            break;
        case ScreenshotCanvasToolHighlighter:
            self.canvasView.highlighterLineWidth = clamped;
            if (persist) {
                [[NSUserDefaults standardUserDefaults] setDouble:clamped forKey:STDefaultsHighlighterWidthKey];
            }
            break;
        default:
            break;
    }
    [self.canvasView setNeedsDisplay:YES];
    if (self.preferencesWindowController) {
        [self.preferencesWindowController refresh];
    }
}

#pragma mark - Tool Appearance

- (NSColor *)storedColorForKey:(NSString *)key
                       fallback:(NSColor *)fallback
            registerIfMissing:(BOOL)registerDefault {
    if (key.length == 0) {
        return fallback ?: STDefaultPenColor();
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *encoded = [defaults stringForKey:key];
    if (encoded.length == 0) {
        if (registerDefault && fallback) {
            [defaults setObject:STEncodeColor(fallback) forKey:key];
        }
        return fallback ? [fallback copy] : STDefaultPenColor();
    }
    NSColor *decoded = STDecodeColor(encoded, fallback);
    return decoded ?: (fallback ? [fallback copy] : STDefaultPenColor());
}

- (void)persistColor:(NSColor *)color forKey:(NSString *)key {
    if (key.length == 0) {
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (!color) {
        [defaults removeObjectForKey:key];
        return;
    }
    NSString *encoded = STEncodeColor(color);
    if (encoded.length > 0) {
        [defaults setObject:encoded forKey:key];
    }
}

- (NSFont *)storedFontWithNameKey:(NSString *)nameKey
                            sizeKey:(NSString *)sizeKey
                           fallback:(NSFont *)fallback
                registerIfMissing:(BOOL)registerDefault {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *name = nameKey.length > 0 ? [defaults stringForKey:nameKey] : nil;
    double sizeValue = (sizeKey.length > 0) ? [defaults doubleForKey:sizeKey] : 0.0;
    if (name.length == 0 || sizeValue <= 0.0) {
        if (registerDefault && fallback) {
            if (nameKey.length > 0) {
                [defaults setObject:fallback.fontName forKey:nameKey];
            }
            if (sizeKey.length > 0) {
                [defaults setDouble:fallback.pointSize forKey:sizeKey];
            }
        }
        return fallback ?: STDefaultTextFont();
    }
    NSFont *font = STFontNamed(name, (CGFloat)sizeValue);
    if (!font) {
        font = fallback ?: STDefaultTextFont();
    }
    return font;
}

- (void)persistFont:(NSFont *)font nameKey:(NSString *)nameKey sizeKey:(NSString *)sizeKey {
    if (!font) {
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (nameKey.length > 0) {
        [defaults setObject:font.fontName ?: font.familyName ?: @"" forKey:nameKey];
    }
    if (sizeKey.length > 0) {
        [defaults setDouble:font.pointSize forKey:sizeKey];
    }
}

- (NSColor *)currentColorForTool:(ScreenshotCanvasTool)tool {
    tool = STSettingsToolForTool(tool);
    switch (tool) {
        case ScreenshotCanvasToolPen:
            return self.canvasView.penColor;
        case ScreenshotCanvasToolHighlighter:
            return self.canvasView.highlighterColor;
        case ScreenshotCanvasToolText:
            return self.canvasView.textColor;
        default:
            return nil;
    }
}

- (NSColor *)defaultColorForTool:(ScreenshotCanvasTool)tool {
    tool = STSettingsToolForTool(tool);
    switch (tool) {
        case ScreenshotCanvasToolPen:
            return self.penDefaultColor ?: STDefaultPenColor();
        case ScreenshotCanvasToolHighlighter:
            return self.highlighterDefaultColor ?: STDefaultHighlighterColor();
        case ScreenshotCanvasToolText:
            return self.textDefaultColor ?: STDefaultTextColor();
        default:
            return STDefaultPenColor();
    }
}

- (void)setDefaultColor:(NSColor *)color forTool:(ScreenshotCanvasTool)tool {
    tool = STSettingsToolForTool(tool);
    NSColor *resolved = color ?: STDefaultPenColor();
    switch (tool) {
        case ScreenshotCanvasToolPen:
            self.penDefaultColor = resolved;
            [self persistColor:resolved forKey:STDefaultsPenDefaultColorKey];
            break;
        case ScreenshotCanvasToolHighlighter:
            self.highlighterDefaultColor = resolved;
            [self persistColor:resolved forKey:STDefaultsHighlighterDefaultColorKey];
            break;
        case ScreenshotCanvasToolText:
            self.textDefaultColor = resolved;
            [self persistColor:resolved forKey:STDefaultsTextDefaultColorKey];
            break;
        default:
            break;
    }
}

- (void)applyColor:(NSColor *)color toTool:(ScreenshotCanvasTool)tool persist:(BOOL)persist {
    tool = STSettingsToolForTool(tool);
    NSColor *resolved = color ?: [self defaultColorForTool:tool];
    switch (tool) {
        case ScreenshotCanvasToolPen:
            self.canvasView.penColor = resolved;
            if (persist) {
                [self persistColor:resolved forKey:STDefaultsPenColorKey];
            }
            break;
        case ScreenshotCanvasToolHighlighter:
            self.canvasView.highlighterColor = resolved;
            if (persist) {
                [self persistColor:resolved forKey:STDefaultsHighlighterColorKey];
            }
            break;
        case ScreenshotCanvasToolText:
            self.canvasView.textColor = resolved;
            if (persist) {
                [self persistColor:resolved forKey:STDefaultsTextColorKey];
            }
            break;
        default:
            break;
    }
    [self.canvasView refreshCursor];
    [self refreshToolButtonIcons];
    [self.canvasView setNeedsDisplay:YES];
    if (self.preferencesWindowController) {
        [self.preferencesWindowController refresh];
    }
}

- (void)setDefaultTextFont:(NSFont *)font {
    self.textDefaultFont = font ?: STDefaultTextFont();
    [self persistFont:self.textDefaultFont nameKey:STDefaultsTextDefaultFontNameKey sizeKey:STDefaultsTextDefaultFontSizeKey];
}

- (void)applyTextStyle:(MarkupTextStyle)style persist:(BOOL)persist {
    self.canvasView.textStyle = style;
    if (persist) {
        [[NSUserDefaults standardUserDefaults] setInteger:style forKey:STDefaultsTextStyleKey];
    }
    [self.canvasView setNeedsDisplay:YES];
}

- (void)applyTextSizePreset:(STTextSizePreset)preset persist:(BOOL)persist {
    self.canvasView.textSizePreset = preset;
    if (persist) {
        [[NSUserDefaults standardUserDefaults] setInteger:preset forKey:STDefaultsTextSizePresetKey];
    }
    [self.canvasView setNeedsDisplay:YES];
}

- (void)applyTextAlignment:(NSTextAlignment)alignment persist:(BOOL)persist {
    self.canvasView.textAlignment = alignment;
    if (persist) {
        [[NSUserDefaults standardUserDefaults] setInteger:STTextAlignmentCode(alignment) forKey:STDefaultsTextAlignmentKey];
    }
    [self.canvasView setNeedsDisplay:YES];
}

- (void)setDefaultTextAlignment:(NSTextAlignment)alignment {
    self.textDefaultAlignment = alignment;
    [[NSUserDefaults standardUserDefaults] setInteger:STTextAlignmentCode(alignment) forKey:STDefaultsTextDefaultAlignmentKey];
}

- (void)setDefaultTextSizePreset:(STTextSizePreset)preset {
    self.textDefaultSizePreset = preset;
    [[NSUserDefaults standardUserDefaults] setInteger:preset forKey:STDefaultsTextDefaultSizePresetKey];
}

- (void)setDefaultTextStyle:(MarkupTextStyle)style {
    self.textDefaultStyle = style;
    [[NSUserDefaults standardUserDefaults] setInteger:style forKey:STDefaultsTextDefaultStyleKey];
}

- (void)applyTextFont:(NSFont *)font persist:(BOOL)persist {
    NSFont *resolved = font ?: (self.textDefaultFont ?: STDefaultTextFont());
    self.canvasView.textFont = resolved;
    if (persist) {
        [self persistFont:resolved nameKey:STDefaultsTextFontNameKey sizeKey:STDefaultsTextFontSizeKey];
    }
    [self.canvasView setNeedsDisplay:YES];
    if (self.preferencesWindowController) {
        [self.preferencesWindowController refresh];
    }
}

- (void)ensureDirectoryExistsAtPath:(NSString *)path {
    if (path.length == 0) {
        return;
    }
    BOOL isDir = NO;
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:path isDirectory:&isDir] || !isDir) {
        [manager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (void)closeActivePopovers {
    BOOL penWasShown = self.penPopoverController.isShown;
    BOOL highlighterWasShown = self.highlighterPopoverController.isShown;
    BOOL textWasShown = self.textPopoverController.isShown;
    BOOL zoomWasShown = self.zoomPopoverController.isShown;
    ScreenshotToolAppendLog([NSString stringWithFormat:@"closeActivePopovers called (penShown=%@ highlighterShown=%@ textShown=%@ zoomShown=%@)",
                             penWasShown ? @"YES" : @"NO",
                             highlighterWasShown ? @"YES" : @"NO",
                             textWasShown ? @"YES" : @"NO",
                             zoomWasShown ? @"YES" : @"NO"]);
    [self.penPopoverController close];
    [self.highlighterPopoverController close];
    [self.textPopoverController close];
    [self.zoomPopoverController close];
    [self refreshZoomToolbarControl];
}

- (ToolSettingsPopoverController *)popoverControllerForTool:(ScreenshotCanvasTool)tool {
    tool = STSettingsToolForTool(tool);
    switch (tool) {
        case ScreenshotCanvasToolPen:
            if (!self.penPopoverController) {
                self.penPopoverController = [[ToolSettingsPopoverController alloc] initWithTool:ScreenshotCanvasToolPen];
                self.penPopoverController.delegate = self;
                ScreenshotToolAppendLog(@"Created Pen ToolSettingsPopoverController");
            }
            return self.penPopoverController;
        case ScreenshotCanvasToolHighlighter:
            if (!self.highlighterPopoverController) {
                self.highlighterPopoverController = [[ToolSettingsPopoverController alloc] initWithTool:ScreenshotCanvasToolHighlighter];
                self.highlighterPopoverController.delegate = self;
                ScreenshotToolAppendLog(@"Created Highlighter ToolSettingsPopoverController");
            }
            return self.highlighterPopoverController;
        default:
            return nil;
    }
}

- (TextToolPopoverController *)textSettingsPopoverController {
    if (!self.textPopoverController) {
        self.textPopoverController = [[TextToolPopoverController alloc] init];
        self.textPopoverController.delegate = self;
        ScreenshotToolAppendLog(@"Created TextToolPopoverController");
    }
    return self.textPopoverController;
}

- (ZoomPopoverController *)zoomSettingsPopoverController {
    if (!self.zoomPopoverController) {
        self.zoomPopoverController = [[ZoomPopoverController alloc] init];
        self.zoomPopoverController.delegate = self;
        ScreenshotToolAppendLog(@"Created ZoomPopoverController");
    }
    return self.zoomPopoverController;
}

- (NSRect)anchorRectForEvent:(NSEvent *)event inView:(NSView *)view {
    if (!view) {
        return NSZeroRect;
    }
    NSPoint location = event ? [view convertPoint:event.locationInWindow fromView:nil] : NSMakePoint(NSMidX(view.bounds), NSMaxY(view.bounds) - 4.0f);
    location.x = MAX(4.0f, MIN(location.x, view.bounds.size.width - 4.0f));
    location.y = view.bounds.size.height - 2.0f;
    return NSMakeRect(location.x - 2.0f, location.y - 2.0f, 4.0f, 4.0f);
}

- (BOOL)isDoubleClickEvent:(NSEvent *)event {
    if (!event) {
        ScreenshotToolAppendLog(@"isDoubleClickEvent: nil NSEvent encountered");
        return NO;
    }
    NSEventType type = event.type;
    if (type != NSEventTypeLeftMouseDown && type != NSEventTypeLeftMouseUp) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"isDoubleClickEvent: ignored event type %ld (clickCount=%ld)",
                                 (long)type,
                                 (long)STEventClickCount(event)]);
        return NO;
    }
    BOOL result = event.clickCount >= 2;
    if (!result) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"isDoubleClickEvent: clickCount %ld below threshold",
                                 (long)event.clickCount]);
    } else {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"isDoubleClickEvent: detected double-click with clickCount=%ld",
                                 (long)event.clickCount]);
    }
    return result;
}

- (void)showToolSettingsPopoverForTool:(ScreenshotCanvasTool)tool event:(NSEvent *)event {
    NSView *anchorView = self.window.contentView;
    if (!anchorView) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Skipping popover for %@: missing content view",
                                 STDebugToolName(tool)]);
        return;
    }
    NSRect anchor = [self anchorRectForEvent:event inView:anchorView];
    [self showToolSettingsPopoverForTool:tool anchorRect:anchor ofView:anchorView event:event];
}

- (void)showToolSettingsPopoverForTool:(ScreenshotCanvasTool)tool
                            anchorRect:(NSRect)anchor
                                ofView:(NSView *)anchorView
                                 event:(NSEvent *)event {
    if (!anchorView) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Skipping popover for %@: missing anchor view",
                                 STDebugToolName(tool)]);
        return;
    }
    [self.zoomPopoverController close];
    [self refreshZoomToolbarControl];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"Requesting %@ popover (anchorView=%@ rect=%@ event=%@)",
                             STDebugToolName(tool),
                             NSStringFromClass([anchorView class]),
                             NSStringFromRect(anchor),
                             STDebugDescriptionForEvent(event)]);
    if (tool == ScreenshotCanvasToolPen || tool == ScreenshotCanvasToolHighlighter) {
        ToolSettingsPopoverController *controller = [self popoverControllerForTool:tool];
        if (!controller) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Popover controller unavailable for %@",
                                     STDebugToolName(tool)]);
            return;
        }
        BOOL wasShown = controller.isShown;
        [controller showRelativeToRect:anchor ofView:anchorView preferredEdge:NSMaxYEdge];
        ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ popover show invoked (wasShown=%@ nowShown=%@)",
                                 STDebugToolName(tool),
                                 wasShown ? @"YES" : @"NO",
                                 controller.isShown ? @"YES" : @"NO"]);
    } else if (tool == ScreenshotCanvasToolText) {
        TextToolPopoverController *controller = [self textSettingsPopoverController];
        if (!controller) {
            ScreenshotToolAppendLog(@"Popover controller unavailable for Text tool");
            return;
        }
        BOOL wasShown = controller.isShown;
        [controller showRelativeToRect:anchor ofView:anchorView preferredEdge:NSMaxYEdge];
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Text popover show invoked (wasShown=%@ nowShown=%@)",
                                 wasShown ? @"YES" : @"NO",
                                 controller.isShown ? @"YES" : @"NO"]);
    } else {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"No popover registered for %@", STDebugToolName(tool)]);
    }
}

- (NSRect)anchorRectForToolbarSubview:(NSView *)view inView:(NSView *)anchorView {
    if (!view || !anchorView) {
        return NSZeroRect;
    }
    NSPoint sourcePoint = NSMakePoint(NSMidX(view.bounds), NSMinY(view.bounds) + 2.0f);
    NSPoint windowPoint = [view convertPoint:sourcePoint toView:nil];
    NSPoint anchorPoint = [anchorView convertPoint:windowPoint fromView:nil];
    return NSMakeRect(anchorPoint.x - 2.0f, anchorPoint.y - 2.0f, 4.0f, 4.0f);
}

- (void)showActiveToolColorSettings:(id)sender {
    (void)sender;
    ScreenshotCanvasTool activeTool = self.canvasView.activeTool;
    if (!STToolUsesColor(activeTool)) {
        return;
    }
    NSView *anchorView = self.window.contentView;
    if (!anchorView) {
        return;
    }
    NSRect anchor = [self anchorRectForToolbarSubview:self.toolbarColorWellView inView:anchorView];
    [self showToolSettingsPopoverForTool:activeTool anchorRect:anchor ofView:anchorView event:nil];
}

- (void)showZoomPopover:(id)sender {
    (void)sender;
    if (![self.canvasView hasImage]) {
        return;
    }

    ZoomPopoverController *controller = [self zoomSettingsPopoverController];
    BOOL wasShown = controller.isShown;
    [self closeActivePopovers];
    if (wasShown) {
        return;
    }

    NSView *anchorView = self.window.contentView;
    if (!anchorView) {
        return;
    }

    NSRect anchor = [self anchorRectForToolbarSubview:self.zoomToolbarButtonView inView:anchorView];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"Requesting zoom popover (anchorView=%@ rect=%@)",
                             NSStringFromClass([anchorView class]),
                             NSStringFromRect(anchor)]);
    [controller showRelativeToRect:anchor ofView:anchorView preferredEdge:NSMaxYEdge];
    [self refreshZoomToolbarControl];
}

#pragma mark - ZoomPopoverControllerDelegate

- (BOOL)zoomPopoverHasImage:(ZoomPopoverController *)controller {
    (void)controller;
    return [self.canvasView hasImage];
}

- (BOOL)zoomPopoverIsFitToWindow:(ZoomPopoverController *)controller {
    (void)controller;
    return self.canvasView.isFitToWindow;
}

- (CGFloat)zoomPopoverCurrentScale:(ZoomPopoverController *)controller {
    (void)controller;
    return self.canvasView.displayZoomScale;
}

- (void)zoomPopover:(ZoomPopoverController *)controller didChangeScale:(CGFloat)scale {
    (void)controller;
    [self setZoomScale:scale];
}

- (void)zoomPopoverDidRequestFitToWindow:(ZoomPopoverController *)controller {
    (void)controller;
    [self zoomFitToWindow:nil];
}

#pragma mark - ToolSettingsPopoverControllerDelegate

- (CGFloat)toolSettingsPopover:(ToolSettingsPopoverController *)controller currentWidthForTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    return [self currentWidthForTool:tool];
}

- (CGFloat)toolSettingsPopover:(ToolSettingsPopoverController *)controller defaultWidthForTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    return [self defaultWidthForTool:tool];
}

- (void)toolSettingsPopover:(ToolSettingsPopoverController *)controller didChangeWidth:(CGFloat)width forTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    [self applyWidth:width toTool:tool persist:YES];
}

- (NSColor *)toolSettingsPopover:(ToolSettingsPopoverController *)controller currentColorForTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    return [self currentColorForTool:tool];
}

- (NSColor *)toolSettingsPopover:(ToolSettingsPopoverController *)controller defaultColorForTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    return [self defaultColorForTool:tool];
}

- (void)toolSettingsPopover:(ToolSettingsPopoverController *)controller didChangeColor:(NSColor *)color forTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    [self applyColor:color toTool:tool persist:YES];
}

- (void)toolSettingsPopoverDidRequestReset:(ToolSettingsPopoverController *)controller forTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    CGFloat width = [self defaultWidthForTool:tool];
    NSColor *color = [self defaultColorForTool:tool];
    [self applyWidth:width toTool:tool persist:YES];
    [self applyColor:color toTool:tool persist:YES];
    NSString *message = [NSString stringWithFormat:@"%@ reset to defaults", [self titleForToolWidth:tool]];
    [self showStatusMessage:message duration:2.0];
}

- (void)toolSettingsPopoverDidRequestSetDefault:(ToolSettingsPopoverController *)controller forTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    CGFloat width = [self currentWidthForTool:tool];
    NSColor *color = [self currentColorForTool:tool];
    [self setDefaultWidth:width forTool:tool];
    [self setDefaultColor:color forTool:tool];
    NSString *message = [NSString stringWithFormat:@"%@ defaults updated", [self titleForToolWidth:tool]];
    [self showStatusMessage:message duration:2.0];
}

#pragma mark - TextToolPopoverControllerDelegate

- (NSColor *)textToolPopoverCurrentColor:(TextToolPopoverController *)controller {
    (void)controller;
    return self.canvasView.textColor;
}

- (NSColor *)textToolPopoverDefaultColor:(TextToolPopoverController *)controller {
    (void)controller;
    return self.textDefaultColor ?: STDefaultTextColor();
}

- (void)textToolPopover:(TextToolPopoverController *)controller didChangeColor:(NSColor *)color {
    (void)controller;
    [self applyColor:color toTool:ScreenshotCanvasToolText persist:YES];
}

- (NSFont *)textToolPopoverCurrentFont:(TextToolPopoverController *)controller {
    (void)controller;
    // At the preset's size for the current image, so the size field shows what new text gets.
    return [self.canvasView effectiveTextFont] ?: STDefaultTextFont();
}

- (STTextSizePreset)textToolPopoverCurrentSizePreset:(TextToolPopoverController *)controller {
    (void)controller;
    return self.canvasView.textSizePreset;
}

- (STTextSizePreset)textToolPopoverDefaultSizePreset:(TextToolPopoverController *)controller {
    (void)controller;
    return self.textDefaultSizePreset;
}

- (void)textToolPopover:(TextToolPopoverController *)controller didChangeSizePreset:(STTextSizePreset)preset {
    (void)controller;
    [self applyTextSizePreset:preset persist:YES];
    [self refreshTextOptionsBar];
}

- (NSTextAlignment)textToolPopoverCurrentAlignment:(TextToolPopoverController *)controller {
    (void)controller;
    return self.canvasView.textAlignment;
}

- (NSTextAlignment)textToolPopoverDefaultAlignment:(TextToolPopoverController *)controller {
    (void)controller;
    return self.textDefaultAlignment;
}

- (void)textToolPopover:(TextToolPopoverController *)controller didChangeAlignment:(NSTextAlignment)alignment {
    (void)controller;
    [self applyTextAlignment:alignment persist:YES];
    [self refreshTextOptionsBar];
}

- (NSFont *)textToolPopoverDefaultFont:(TextToolPopoverController *)controller {
    (void)controller;
    return self.textDefaultFont ?: STDefaultTextFont();
}

- (void)textToolPopover:(TextToolPopoverController *)controller didChangeFont:(NSFont *)font {
    (void)controller;
    [self applyTextFont:font persist:YES];
}

- (MarkupTextStyle)textToolPopoverCurrentStyle:(TextToolPopoverController *)controller {
    (void)controller;
    return self.canvasView.textStyle;
}

- (MarkupTextStyle)textToolPopoverDefaultStyle:(TextToolPopoverController *)controller {
    (void)controller;
    return self.textDefaultStyle;
}

- (void)textToolPopover:(TextToolPopoverController *)controller didChangeStyle:(MarkupTextStyle)style {
    (void)controller;
    [self applyTextStyle:style persist:YES];
}

- (void)textToolPopoverDidRequestReset:(TextToolPopoverController *)controller {
    (void)controller;
    [self applyColor:self.textDefaultColor toTool:ScreenshotCanvasToolText persist:YES];
    [self applyTextFont:self.textDefaultFont persist:YES];
    [self applyTextStyle:self.textDefaultStyle persist:YES];
    [self applyTextSizePreset:self.textDefaultSizePreset persist:YES];
    [self applyTextAlignment:self.textDefaultAlignment persist:YES];
    [self refreshTextOptionsBar];
    [self showStatusMessage:@"Text defaults restored" duration:2.0];
}

- (void)textToolPopoverDidRequestSetDefault:(TextToolPopoverController *)controller {
    (void)controller;
    NSColor *color = self.canvasView.textColor ?: STDefaultTextColor();
    NSFont *font = self.canvasView.textFont ?: STDefaultTextFont();
    [self setDefaultColor:color forTool:ScreenshotCanvasToolText];
    [self setDefaultTextFont:font];
    [self setDefaultTextStyle:self.canvasView.textStyle];
    [self setDefaultTextSizePreset:self.canvasView.textSizePreset];
    [self setDefaultTextAlignment:self.canvasView.textAlignment];
    [self showStatusMessage:@"Text defaults updated" duration:2.0];
}

#pragma mark - PreferencesWindowControllerDelegate

- (CGFloat)preferencesController:(PreferencesWindowController *)controller defaultWidthForTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    return [self defaultWidthForTool:tool];
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultWidth:(CGFloat)width forTool:(ScreenshotCanvasTool)tool {
    (void)controller;
#if !defined(GNUSTEP)
    for (AppDelegate *document in self.documentWindows) {
        [document preferencesController:controller didChangeDefaultWidth:width forTool:tool];
    }
#endif
    [self setDefaultWidth:width forTool:tool];
    [self applyWidth:width toTool:tool persist:YES];
}

- (NSColor *)preferencesController:(PreferencesWindowController *)controller defaultColorForTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    return [self defaultColorForTool:tool];
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultColor:(NSColor *)color forTool:(ScreenshotCanvasTool)tool {
    (void)controller;
#if !defined(GNUSTEP)
    for (AppDelegate *document in self.documentWindows) {
        [document preferencesController:controller didChangeDefaultColor:color forTool:tool];
    }
#endif
    [self setDefaultColor:color forTool:tool];
    [self applyColor:color toTool:tool persist:YES];
}

- (NSFont *)preferencesControllerDefaultTextFont:(PreferencesWindowController *)controller {
    (void)controller;
    return self.textDefaultFont ?: STDefaultTextFont();
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultTextFont:(NSFont *)font {
    (void)controller;
#if !defined(GNUSTEP)
    for (AppDelegate *document in self.documentWindows) {
        [document preferencesController:controller didChangeDefaultTextFont:font];
    }
#endif
    [self setDefaultTextFont:font];
    [self applyTextFont:font persist:YES];
}

- (NSColor *)preferencesControllerDefaultTextColor:(PreferencesWindowController *)controller {
    (void)controller;
    return self.textDefaultColor ?: STDefaultTextColor();
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultTextColor:(NSColor *)color {
    (void)controller;
#if !defined(GNUSTEP)
    for (AppDelegate *document in self.documentWindows) {
        [document preferencesController:controller didChangeDefaultTextColor:color];
    }
#endif
    [self setDefaultColor:color forTool:ScreenshotCanvasToolText];
    [self applyColor:color toTool:ScreenshotCanvasToolText persist:YES];
}

- (NSString *)preferencesControllerDefaultSaveDirectory:(PreferencesWindowController *)controller {
    (void)controller;
    return self.defaultSaveDirectory ?: @"";
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultSaveDirectory:(NSString *)path {
    (void)controller;
    if (path.length == 0) {
        return;
    }
    NSString *expanded = [path stringByExpandingTildeInPath];
    self.defaultSaveDirectory = expanded;
    [[NSUserDefaults standardUserDefaults] setObject:expanded forKey:STDefaultsSaveDirectoryKey];
    [self ensureDirectoryExistsAtPath:expanded];
    if (self.preferencesWindowController) {
        [self.preferencesWindowController refresh];
    }
}

- (BOOL)preferencesControllerShouldShowStatusBar:(PreferencesWindowController *)controller {
    (void)controller;
    return self.statusBarVisiblePreference;
}

- (void)preferencesController:(PreferencesWindowController *)controller didToggleStatusBar:(BOOL)show {
    (void)controller;
#if !defined(GNUSTEP)
    for (AppDelegate *document in self.documentWindows) {
        [document preferencesController:controller didToggleStatusBar:show];
    }
#endif
    self.statusBarVisiblePreference = show;
    [[NSUserDefaults standardUserDefaults] setBool:show forKey:STDefaultsShowStatusBarKey];
    [self updateStatusBarVisibility];
}

- (BOOL)preferencesControllerShouldShowSelectionBar:(PreferencesWindowController *)controller {
    (void)controller;
    return self.selectionBarPreference;
}

- (void)preferencesController:(PreferencesWindowController *)controller didToggleSelectionBar:(BOOL)show {
#if !defined(GNUSTEP)
    for (AppDelegate *document in self.documentWindows) {
        [document preferencesController:controller didToggleSelectionBar:show];
    }
#endif
    self.selectionBarPreference = show;
    [[NSUserDefaults standardUserDefaults] setBool:show forKey:STDefaultsShowSelectionBarKey];
    [self updateSelectionActionBar];
}

- (void)preferencesControllerRestoreDefaults:(PreferencesWindowController *)controller {
    (void)controller;
#if !defined(GNUSTEP)
    for (AppDelegate *document in self.documentWindows) {
        [document preferencesControllerRestoreDefaults:controller];
    }
#endif
    [self setDefaultWidth:STPenWidthDefault forTool:ScreenshotCanvasToolPen];
    [self applyWidth:STPenWidthDefault toTool:ScreenshotCanvasToolPen persist:YES];
    [self setDefaultWidth:STHighlighterWidthDefault forTool:ScreenshotCanvasToolHighlighter];
    [self applyWidth:STHighlighterWidthDefault toTool:ScreenshotCanvasToolHighlighter persist:YES];

    NSColor *penColor = STDefaultPenColor();
    [self setDefaultColor:penColor forTool:ScreenshotCanvasToolPen];
    [self applyColor:penColor toTool:ScreenshotCanvasToolPen persist:YES];

    NSColor *highlighterColor = STDefaultHighlighterColor();
    [self setDefaultColor:highlighterColor forTool:ScreenshotCanvasToolHighlighter];
    [self applyColor:highlighterColor toTool:ScreenshotCanvasToolHighlighter persist:YES];

    NSColor *textColor = STDefaultTextColor();
    [self setDefaultColor:textColor forTool:ScreenshotCanvasToolText];
    [self applyColor:textColor toTool:ScreenshotCanvasToolText persist:YES];

    NSFont *textFont = STDefaultTextFont();
    [self setDefaultTextFont:textFont];
    [self applyTextFont:textFont persist:YES];

    NSString *fallbackDirectory = STDefaultSaveDirectoryPath();
    self.defaultSaveDirectory = fallbackDirectory;
    [[NSUserDefaults standardUserDefaults] setObject:fallbackDirectory forKey:STDefaultsSaveDirectoryKey];
    [self ensureDirectoryExistsAtPath:fallbackDirectory];

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsShowStatusBarKey];
    self.statusBarVisiblePreference = [[NSUserDefaults standardUserDefaults] boolForKey:STDefaultsShowStatusBarKey];
    [self updateStatusBarVisibility];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsShowSelectionBarKey];
    self.selectionBarPreference = [[NSUserDefaults standardUserDefaults] boolForKey:STDefaultsShowSelectionBarKey];
    [self updateSelectionActionBar];

    [[NSUserDefaults standardUserDefaults] synchronize];
    [self showStatusMessage:@"Preferences restored" duration:2.0];
}

- (void)preferencesControllerDidRequestClose:(PreferencesWindowController *)controller {
    (void)controller;
}

- (void)showStatusMessage:(NSString *)message duration:(NSTimeInterval)duration {
    if (!self.statusTextField) {
        return;
    }
    [self.statusClearTimer invalidate];
    self.statusClearTimer = nil;

    NSString *text = message.length > 0 ? message : @"";

    NSUndoManager *undo = self.undoManager;
    BOOL undoWasEnabled = (undo && undo.isUndoRegistrationEnabled);
    if (undoWasEnabled) {
        [undo disableUndoRegistration];
    }

    [self.statusTextField setStringValue:text];

    if (undoWasEnabled) {
        [undo enableUndoRegistration];
    }

    if (duration > 0.0) {
        self.statusClearTimer = [NSTimer scheduledTimerWithTimeInterval:duration
                                                                 target:self
                                                               selector:@selector(clearStatusMessage)
                                                               userInfo:nil
                                                                repeats:NO];
    }
}

- (void)showTransientFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration {
    if (self.statusBarVisiblePreference) {
        [self showStatusMessage:message duration:duration];
        return;
    }

    NSTimeInterval hudDuration = duration;
    if (hudDuration <= 0.0) {
        hudDuration = 1.5;
    } else if (hudDuration > 2.0) {
        hudDuration = 2.0;
    }
    [self showHUDMessage:message duration:hudDuration];
}

- (void)clearStatusMessage {
    [self.statusClearTimer invalidate];
    self.statusClearTimer = nil;
    if (self.statusTextField) {
        NSUndoManager *undo = self.undoManager;
        BOOL undoWasEnabled = (undo && undo.isUndoRegistrationEnabled);
        if (undoWasEnabled) {
            [undo disableUndoRegistration];
        }

        // Back to the image's size and format (#221).
        [self.statusTextField setStringValue:[self idleStatusText]];

        if (undoWasEnabled) {
            [undo enableUndoRegistration];
        }
    }
}

- (void)showCopyFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration {
    ScreenshotToolAppendLog([NSString stringWithFormat:@"copy feedback message=\"%@\" duration=%.2f statusBarVisible=%@", message ?: @"", duration, self.statusBarVisiblePreference ? @"YES" : @"NO"]);
    [self showTransientFeedbackMessage:message duration:duration];
}

- (void)showHUDMessage:(NSString *)message duration:(NSTimeInterval)duration {
    if (message.length == 0 || !self.window) {
        ScreenshotToolAppendLog(@"showHUDMessage skipped (empty message or missing window)");
        return;
    }
    [self.hudDismissTimer invalidate];
    self.hudDismissTimer = nil;
    [self.hudFadeTimer invalidate];
    self.hudFadeTimer = nil;
    self.hudFadeCompletion = nil;

    [self ensureHUDWindow];
    [self updateHUDAppearance];

    self.hudView.message = message;
    self.hudView.textPadding = NSMakeSize(STHudHorizontalPadding, STHudVerticalPadding);
    self.hudView.cornerRadius = STHudCornerRadius;

    NSDictionary *attributes = @{ NSFontAttributeName: self.hudView.font ?: [NSFont systemFontOfSize:0.0f] };
    NSSize textSize = [message sizeWithAttributes:attributes];
    CGFloat width = MIN(STHudMaxWidth, textSize.width + (STHudHorizontalPadding * 2.0f));
    CGFloat height = textSize.height + (STHudVerticalPadding * 2.0f);
    width = MAX(width, 120.0f);
    height = MAX(height, 36.0f);

#if defined(GNUSTEP)
    NSView *contentView = self.window.contentView;
    if (!contentView) {
        return;
    }
    NSRect contentBounds = contentView.bounds;
    NSRect hudRect = NSMakeRect(NSMidX(contentBounds) - (width / 2.0f),
                                NSMidY(contentBounds) - (height / 2.0f),
                                width,
                                height);
    self.hudView.frame = hudRect;
    if (self.hudView.superview) {
        [self.hudView removeFromSuperview];
    }
    [contentView addSubview:self.hudView];
    self.hudView.hudAlpha = 0.0f;
    self.hudView.hidden = NO;
    [self.hudView setNeedsDisplay:YES];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"showHUDMessage message=\"%@\" hudRect=%@",
                                                       message,
                                                       NSStringFromRect(hudRect)]);
#else
    NSSize contentSize = NSMakeSize(width, height);
    [self.hudWindow setContentSize:contentSize];
    self.hudView.frame = NSMakeRect(0.0f, 0.0f, width, height);

    NSRect windowFrame = self.window.frame;
    NSRect hudFrame = NSMakeRect(NSMidX(windowFrame) - (width / 2.0f),
                                 NSMidY(windowFrame) - (height / 2.0f),
                                 width,
                                 height);
    [self.hudWindow setFrame:hudFrame display:NO];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"showHUDMessage message=\"%@\" windowFrame=%@ hudFrame=%@",
                                                       message,
                                                       NSStringFromRect(windowFrame),
                                                       NSStringFromRect(hudFrame)]);
#endif

#if !defined(GNUSTEP)
    if (self.hudWindow.parentWindow != self.window) {
        [self.window addChildWindow:self.hudWindow ordered:NSWindowAbove];
    }
    self.hudWindow.alphaValue = 0.0f;
    [self.hudWindow orderFront:nil];
    [self startHudFadeToAlpha:1.0f duration:STHudFadeInDuration completion:nil];
#else
    [self startHudFadeToAlpha:1.0f duration:STHudFadeInDuration completion:nil];
#endif

    if (duration > 0.0) {
        self.hudDismissTimer = [NSTimer scheduledTimerWithTimeInterval:duration
                                                                 target:self
                                                               selector:@selector(hideHUDMessage)
                                                               userInfo:nil
                                                                repeats:NO];
    }
}

- (void)hideHUDMessage {
    [self.hudDismissTimer invalidate];
    self.hudDismissTimer = nil;

#if defined(GNUSTEP)
    if (!self.hudView) {
        ScreenshotToolAppendLog(@"hideHUDMessage skipped (no hudView)");
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self startHudFadeToAlpha:0.0f duration:STHudFadeOutDuration completion:^{
        if (weakSelf.hudView) {
            weakSelf.hudView.hidden = YES;
        }
    }];
#else
    if (!self.hudWindow) {
        ScreenshotToolAppendLog(@"hideHUDMessage skipped (no hudWindow)");
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self startHudFadeToAlpha:0.0f duration:STHudFadeOutDuration completion:^{
        if (weakSelf.hudWindow) {
            [weakSelf.hudWindow orderOut:nil];
        }
    }];
#endif
}

- (void)ensureHUDWindow {
#if defined(GNUSTEP)
    if (self.hudView) {
        return;
    }
    NSRect rect = NSMakeRect(0.0f, 0.0f, 160.0f, 44.0f);
    STHudView *hudView = [[STHudView alloc] initWithFrame:rect];
    hudView.cornerRadius = STHudCornerRadius;
    hudView.textPadding = NSMakeSize(STHudHorizontalPadding, STHudVerticalPadding);
    hudView.hidden = YES;
    self.hudView = hudView;
    ScreenshotToolAppendLog(@"HUD view created (GNUstep)");
#else
    if (self.hudWindow) {
        return;
    }
    NSRect rect = NSMakeRect(0.0f, 0.0f, 160.0f, 44.0f);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:rect
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    [window setOpaque:NO];
    [window setHasShadow:YES];
    [window setBackgroundColor:[NSColor clearColor]];
    [window setLevel:NSPopUpMenuWindowLevel];
    [window setIgnoresMouseEvents:YES];
    [window setReleasedWhenClosed:NO];
    [window setCollectionBehavior:NSWindowCollectionBehaviorTransient];

    // The system's translucent material, rounded, under a clear label: like macOS's own notices,
    // in light and dark mode.
    NSVisualEffectView *material = [[NSVisualEffectView alloc] initWithFrame:rect];
    material.material = NSVisualEffectMaterialPopover;
    material.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    material.state = NSVisualEffectStateActive;
    material.maskImage = STRoundedMaskImage(STHudCornerRadius);
    [window setContentView:material];

    STHudView *hudView = [[STHudView alloc] initWithFrame:rect];
    hudView.cornerRadius = STHudCornerRadius;
    hudView.textPadding = NSMakeSize(STHudHorizontalPadding, STHudVerticalPadding);
    hudView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    [material addSubview:hudView];

    self.hudWindow = window;
    self.hudView = hudView;
    ScreenshotToolAppendLog(@"HUD window created");
#endif
}

- (void)updateHUDAppearance {
    if (!self.hudView) {
        return;
    }
    self.hudView.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
#if defined(GNUSTEP)
    self.hudView.fillColor = STThemeHUDBackgroundColor();
    self.hudView.textColor = STThemeHUDTextColor();
#else
    // On the window's material (see -ensureHUDWindow).
    self.hudView.fillColor = [NSColor clearColor];
    self.hudView.textColor = [NSColor labelColor];
#endif
    [self.hudView setNeedsDisplay:YES];
}

- (void)startHudFadeToAlpha:(CGFloat)targetAlpha duration:(NSTimeInterval)duration completion:(void (^)(void))completion {
    if (!self.hudWindow) {
#if defined(GNUSTEP)
        if (!self.hudView) {
            if (completion) {
                completion();
            }
            return;
        }
#else
        if (completion) {
            completion();
        }
        return;
#endif
    }
    [self.hudFadeTimer invalidate];
    self.hudFadeTimer = nil;

    if (duration <= 0.0) {
#if defined(GNUSTEP)
        self.hudView.hudAlpha = targetAlpha;
        [self.hudView setNeedsDisplay:YES];
#else
        self.hudWindow.alphaValue = targetAlpha;
#endif
        if (completion) {
            completion();
        }
        return;
    }

#if defined(GNUSTEP)
    self.hudFadeCompletion = [completion copy];
    self.hudFadeStartAlpha = self.hudView.hudAlpha;
    self.hudFadeTargetAlpha = targetAlpha;
    self.hudFadeDuration = duration;
    self.hudFadeStartTime = [NSDate timeIntervalSinceReferenceDate];
    self.hudFadeTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                                         target:self
                                                       selector:@selector(handleHudFadeTimer:)
                                                       userInfo:nil
                                                        repeats:YES];
#else
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = duration;
        self.hudWindow.animator.alphaValue = targetAlpha;
    } completionHandler:^{
        if (completion) {
            completion();
        }
    }];
#endif
}

- (void)handleHudFadeTimer:(NSTimer *)timer {
    (void)timer;
    if (!self.hudWindow) {
#if defined(GNUSTEP)
        if (!self.hudView) {
            [self.hudFadeTimer invalidate];
            self.hudFadeTimer = nil;
            return;
        }
#else
        [self.hudFadeTimer invalidate];
        self.hudFadeTimer = nil;
        return;
#endif
    }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval elapsed = now - self.hudFadeStartTime;
    CGFloat progress = 1.0f;
    if (self.hudFadeDuration > 0.0) {
        progress = (CGFloat)(elapsed / self.hudFadeDuration);
        if (progress > 1.0f) {
            progress = 1.0f;
        }
    }
    CGFloat alpha = self.hudFadeStartAlpha + ((self.hudFadeTargetAlpha - self.hudFadeStartAlpha) * progress);
#if defined(GNUSTEP)
    self.hudView.hudAlpha = alpha;
    [self.hudView setNeedsDisplay:YES];
#else
    self.hudWindow.alphaValue = alpha;
#endif
    if (progress >= 1.0f) {
        [self.hudFadeTimer invalidate];
        self.hudFadeTimer = nil;
        void (^completion)(void) = self.hudFadeCompletion;
        self.hudFadeCompletion = nil;
        if (completion) {
            completion();
        }
    }
}

- (void)layoutContentSubviews {
    if (!self.window || !self.scrollView || !self.statusBarView) {
        return;
    }
    NSView *contentView = self.window.contentView;
    NSRect bounds = contentView.bounds;
    CGFloat barHeight = [self statusBarHeight];
    NSRect statusFrame = NSMakeRect(0.0f, 0.0f, bounds.size.width, barHeight);
    [self.statusBarView setFrame:statusFrame];
    if (self.statusBarVisiblePreference) {
        [self layoutStatusControls];
    }

    // While editing text, the text toolbar gets its own row above the canvas. GNUstep doesn't
    // redraw overlapping siblings reliably, so it never sits over the canvas.
    BOOL showTextBar = (self.textOptionsBar && !self.textOptionsBar.isHidden);
    CGFloat textBarHeight = showTextBar ? [STTextOptionsBar preferredHeight] : 0.0f;
    CGFloat scrollHeight = MAX(0.0f, bounds.size.height - barHeight - textBarHeight);
    NSRect scrollFrame = NSMakeRect(0.0f, barHeight, bounds.size.width, scrollHeight);
    [self.scrollView setFrame:scrollFrame];
    [self.scrollView.contentView setNeedsDisplay:YES];
    // No image: an empty state in the canvas's place instead of a blank scroll view (#55).
    BOOL hasImage = [self.canvasView hasImage];
    [self.scrollView setHidden:!hasImage];
    BOOL emptyStateWasHidden = self.emptyStateView.isHidden;
    [self.emptyStateView setHidden:hasImage];
    [self updateDrawingToolsForImage:hasImage];
    if (emptyStateWasHidden && !hasImage) {
        // The last image closed: Paste's state and the Recent cards may be out of date.
        [self performSelector:@selector(refreshPasteAvailability) withObject:nil afterDelay:0.0];
        [self performSelector:@selector(refreshEmptyStateRecents) withObject:nil afterDelay:0.0];
    }
    // Return opens a file only from the empty state: GNUstep offers key equivalents to hidden
    // buttons too, so with an image open the Open button took every Return no control consumed,
    // a menu's or the font field's among them, and asked about unsaved changes (#103).
    NSButton *openButton = [self.emptyStateView viewWithTag:4];
    if ([openButton isKindOfClass:[NSButton class]]) {
        [openButton setKeyEquivalent:(hasImage ? @"" : @"\r")];
    }
    if (!hasImage) {
        [self layoutEmptyStateViewInFrame:scrollFrame];
    }
    if (showTextBar) {
        [self.textOptionsBar setFrame:NSMakeRect(0.0f, NSMaxY(scrollFrame), bounds.size.width, textBarHeight)];
        [self.textOptionsBar setNeedsDisplay:YES];
    }
    [self.window invalidateCursorRectsForView:self.canvasView];
}

#pragma mark - Empty state (#55)

/// What the window shows with no image: the app's icon, its name, and Take Screenshot / Open… /
/// Paste (Take Screenshot only where the system has a capture tool, and the accent button, #221).
/// Standard controls on a view that draws only a dashed outline, so the theme styles the rest (as
/// libadwaita's status page). On macOS an image dropped on it opens, as on the canvas.
- (NSView *)newEmptyStateView {
    STEmptyStateView *view = [[STEmptyStateView alloc] initWithFrame:NSZeroRect];
#if !defined(GNUSTEP)
    __weak typeof(self) weakDropSelf = self;
    view.dragOperation = ^NSDragOperation(id<NSDraggingInfo> info) {
        return [weakDropSelf dragOperationForDraggingInfo:info];
    };
    view.performDrop = ^BOOL(id<NSDraggingInfo> info) {
        return [weakDropSelf performDragOperation:info];
    };
#endif

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 80.0, 80.0)];
    // The application icon is already loaded, and small; ScreenshotToolIcon.png is 1024px and took
    // ~75ms to load and scale at launch.
    [icon setImage:[NSApp applicationIconImage] ?: [NSImage imageNamed:@"ScreenshotToolIcon"]];
    [icon setImageScaling:NSImageScaleProportionallyUpOrDown];
    [icon setEditable:NO];
    [icon setTag:1];
    [view addSubview:icon];

    NSTextField *title = [self emptyStateLabel:@"ScreenshotTool"
                                          font:[NSFont boldSystemFontOfSize:round([NSFont systemFontSize] * 2.0)]];
    [title setTag:2];
    [view addSubview:title];

    NSTextField *detail = [self emptyStateLabel:[self emptyStateDetailText]
                                           font:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
    [detail setTextColor:STThemeSecondaryTextColor()];
    // Wraps at the width -layoutEmptyStateViewInFrame: gives it.
    [[detail cell] setWraps:YES];
    [[detail cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [detail setTag:3];
    [view addSubview:detail];

#if defined(GNUSTEP)
    // Open… with a menu of recent files at its right, as libadwaita's split button.
    STSplitButton *open = [[STSplitButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 148.0, 32.0)];
    [open setButtonType:NSMomentaryPushInButton];
    [open setBezelStyle:NSRoundedBezelStyle];
    [open setTitle:@"Open…"];
    [open setTarget:self];
    [open setAction:@selector(openDocument:)];
    [open setToolTip:@"Open a screenshot; the arrow lists recent files"];
    __weak typeof(self) weakSelf = self;
    open.menuProvider = ^NSMenu *{
        return [weakSelf newRecentDocumentsMenu];
    };
    [open setKeyEquivalent:@"\r"];
#else
    NSControl *open = nil;
    if (@available(macOS 13.0, *)) {
        // Filled now and whenever the list changes (-rebuildOpenRecentMenu): AppKit doesn't open
        // an empty menu, so -menuNeedsUpdate: alone would never get to fill it.
        NSMenu *recent = [[NSMenu alloc] initWithTitle:@"Open Recent"];
        [recent setAutoenablesItems:NO];
        [recent setDelegate:self];
        [[self applicationController] fillRecentDocumentsMenu:recent];
        STOpenComboButton *combo = [STOpenComboButton comboButtonWithTitle:@"Open…"
                                                                      menu:recent
                                                                    target:self
                                                                    action:@selector(openDocument:)];
        [combo setToolTip:@"Open a screenshot; the arrow lists recent files"];
        [combo setFrameSize:NSMakeSize(MAX(120.0, combo.fittingSize.width), combo.fittingSize.height)];
        open = combo;
    } else {
        NSButton *button = [self emptyStateButton:@"Open…" action:@selector(openDocument:)];
        [button setKeyEquivalent:@"\r"];
        open = button;
    }
#endif
    [open setTag:4];
    [view addSubview:open];

    NSButton *paste = [self emptyStateButton:@"Paste" action:@selector(pasteAsNewImage:)];
    [paste setTag:5];
    [view addSubview:paste];

    // The accent button, without being the window's default: Return stays with Open… (#103).
#if defined(GNUSTEP)
    NSButton *capture = [self emptyStateButton:@"Take Screenshot" action:@selector(takeScreenshot:)];
    [self showShortcut:[self takeScreenshotShortcutText] onEmptyStateButton:capture];
    // A theme-neutral way to ask for the theme's accent button, as the toolbar's Copy does.
    if ([capture respondsToSelector:@selector(setGSThemeStyle:)]) {
        [capture performSelector:@selector(setGSThemeStyle:) withObject:@"accent"];
    }
#else
    STAccentButton *capture = [[STAccentButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, 32.0)];
    [capture setTitle:@"Take Screenshot"];
    [capture setShortcut:[self takeScreenshotShortcutText]];
    [capture setTarget:self];
    [capture setAction:@selector(takeScreenshot:)];
#endif
    [capture setFrameSize:NSMakeSize(MAX(120.0, ceil([[capture cell] cellSize].width) + 8.0), 32.0)];
    [capture setTag:6];
    [capture setHidden:![STScreenshotCapture isAvailable]];
    [view addSubview:capture];

    // Recent: the last files opened, as cards with thumbnails (#221). Filled by
    // -refreshEmptyStateRecents; hidden while there are none or the window is too short.
    NSTextField *recentLabel = [self emptyStateLabel:@"Recent" font:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
    [recentLabel setAlignment:NSTextAlignmentLeft];
    [recentLabel setTag:STEmptyStateRecentLabelTag];
    [recentLabel setHidden:YES];
    [view addSubview:recentLabel];
    for (NSInteger index = 0; index < STEmptyStateRecentCount; index++) {
        STRecentCard *card = [[STRecentCard alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, [STRecentCard heightForWidth:200.0])];
        [card setTarget:self];
        [card setAction:@selector(openRecentDocument:)];
        [card setTag:STEmptyStateRecentFirstCardTag + index];
        [card setHidden:YES];
        [view addSubview:card];
    }
    return view;
}

/// Up to three recent files that still exist, newest first.
- (NSArray<NSString *> *)emptyStateRecentPaths {
#if defined(GNUSTEP)
    AppDelegate *application = self;
#else
    AppDelegate *application = [self applicationController];
#endif
    [application ensureRecentDocumentPathsLoaded];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *path in application.recentDocumentPaths) {
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory) {
            [paths addObject:path];
        }
        if (paths.count == STEmptyStateRecentCount) {
            break;
        }
    }
    return paths;
}

/// When the file last changed, as "Today at 3:14 PM" (macOS) or a date and time.
- (NSString *)emptyStateRecentDetailForDate:(NSDate *)date {
    if (!date) {
        return @"";
    }
    static NSDateFormatter *formatter = nil;
    if (!formatter) {
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
#if !defined(GNUSTEP)
        formatter.doesRelativeDateFormatting = YES;
#endif
    }
    NSString *text = [formatter stringFromDate:date] ?: @"";
#if defined(GNUSTEP)
    // ICU puts a narrow no-break space before AM/PM, which GNUstep's text drawing has no glyph
    // for (it showed as "?"); plain spaces read the same.
    text = [text stringByReplacingOccurrencesOfString:@"\u202F" withString:@" "];
    text = [text stringByReplacingOccurrencesOfString:@"\u00A0" withString:@" "];
#endif
    return text;
}

/// Thumbnails already made, by path and modification date, so a refresh doesn't decode again.
static NSCache<NSString *, NSImage *> *STEmptyStateThumbnails(void) {
    static NSCache *cache = nil;
    if (!cache) {
        cache = [[NSCache alloc] init];
        cache.countLimit = 12;
    }
    return cache;
}

/// The image at `path` scaled to fit `maximum` pixels on its long side, or nil if it isn't one.
static NSImage *STEmptyStateThumbnailForFile(NSString *path, CGFloat maximum) {
#if defined(GNUSTEP)
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    NSSize size = image.size;
    if (!image || size.width < 1.0 || size.height < 1.0) {
        return nil;
    }
    CGFloat scale = MIN(1.0, maximum / MAX(size.width, size.height));
    NSSize scaled = NSMakeSize(MAX(1.0, floor(size.width * scale)), MAX(1.0, floor(size.height * scale)));
    NSImage *thumbnail = [[NSImage alloc] initWithSize:scaled];
    [thumbnail lockFocus];
    [image drawInRect:NSMakeRect(0.0, 0.0, scaled.width, scaled.height) fromRect:NSZeroRect
            operation:NSCompositeSourceOver fraction:1.0];
    [thumbnail unlockFocus];
    return thumbnail;
#else
    // Off the main thread: decode with the image rep, scale with Core Graphics.
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    NSBitmapImageRep *rep = data ? [NSBitmapImageRep imageRepWithData:data] : nil;
    CGImageRef source = rep.CGImage;
    if (!source) {
        return nil;
    }
    size_t width = CGImageGetWidth(source), height = CGImageGetHeight(source);
    CGFloat scale = MIN(1.0, maximum / (CGFloat)MAX(width, height));
    size_t scaledWidth = MAX((size_t)1, (size_t)floor(width * scale));
    size_t scaledHeight = MAX((size_t)1, (size_t)floor(height * scale));
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, scaledWidth, scaledHeight, 8, 0, space,
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) {
        return nil;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, scaledWidth, scaledHeight), source);
    CGImageRef scaledImage = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!scaledImage) {
        return nil;
    }
    // Points at half the pixels: drawn on a 2x screen at full sharpness.
    NSImage *thumbnail = [[NSImage alloc] initWithCGImage:scaledImage
                                                     size:NSMakeSize(scaledWidth / 2.0, scaledHeight / 2.0)];
    CGImageRelease(scaledImage);
    return thumbnail;
#endif
}

/// Fills the Recent cards from Open Recent's list, and starts any thumbnails not yet made.
- (void)refreshEmptyStateRecents {
    NSView *view = self.emptyStateView;
    if (!view) {
        return;
    }
    self.emptyStateRecentsLoaded = YES;
    NSArray<NSString *> *paths = [self emptyStateRecentPaths];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSInteger index = 0; index < STEmptyStateRecentCount; index++) {
        STRecentCard *card = [view viewWithTag:STEmptyStateRecentFirstCardTag + index];
        if (![card isKindOfClass:[STRecentCard class]]) {
            continue;
        }
        if (index >= (NSInteger)paths.count) {
            card.representedObject = nil;
            card.thumbnail = nil;
            [card setHidden:YES];
            continue;
        }
        NSString *path = paths[index];
        NSDate *modified = [[fileManager attributesOfItemAtPath:path error:NULL] fileModificationDate];
        NSString *name = [fileManager displayNameAtPath:path] ?: path.lastPathComponent;
        [card setTitle:name];
        [card setToolTip:[path stringByAbbreviatingWithTildeInPath]];
        STApplyAccessibilityLabel(card, [NSString stringWithFormat:@"Open %@", name]);
        card.detail = [self emptyStateRecentDetailForDate:modified];
        card.placeholder = [[NSWorkspace sharedWorkspace] iconForFile:path];
        NSString *key = [NSString stringWithFormat:@"%@|%f", path, modified.timeIntervalSinceReferenceDate];
        BOOL samePath = [card.representedObject isEqual:path];
        card.representedObject = path;
        NSImage *cached = [STEmptyStateThumbnails() objectForKey:key];
        if (cached) {
            card.thumbnail = cached;
        } else {
            if (!samePath) {
                card.thumbnail = nil;
            }
            [self loadEmptyStateThumbnailForCard:card path:path key:key];
        }
    }
    [self layoutContentSubviews];
}

#if defined(GNUSTEP)
/// A class method, so the delayed perform keeps no window controller alive until it fires.
+ (void)runEmptyStateThumbnailLoad:(void (^)(void))load {
    load();
}
#endif

- (void)loadEmptyStateThumbnailForCard:(STRecentCard *)card path:(NSString *)path key:(NSString *)key {
    __weak STRecentCard *weakCard = card;
    void (^apply)(NSImage *) = ^(NSImage *thumbnail) {
        if (!thumbnail) {
            return;
        }
        [STEmptyStateThumbnails() setObject:thumbnail forKey:key];
        STRecentCard *strongCard = weakCard;
        // Unless the card has moved on to another file meanwhile.
        if ([strongCard.representedObject isEqual:path]) {
            strongCard.thumbnail = thumbnail;
        }
    };
    // Twice the 2x card's width, so the crop stays sharp.
    CGFloat maximum = 640.0;
#if defined(GNUSTEP)
    // GNUstep's image classes are main-thread only (NSImage reads files through the pasteboard
    // server), and its +[NSOperationQueue mainQueue] runs blocks on a worker thread: so a delayed
    // perform on this thread, one per turn of the run loop, after launch.
    // It holds the card weakly, and does nothing once the card has left its window.
    void (^load)(void) = ^{
        if (!weakCard.window) {
            return;
        }
        apply(STEmptyStateThumbnailForFile(path, maximum));
    };
    [[self class] performSelector:@selector(runEmptyStateThumbnailLoad:) withObject:[load copy] afterDelay:0.0];
#else
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSImage *thumbnail = STEmptyStateThumbnailForFile(path, maximum);
        dispatch_async(dispatch_get_main_queue(), ^{
            apply(thumbnail);
        });
    });
#endif
}

/// The line under the heading: what the window can take, by the shortcuts this platform shows.
- (NSString *)emptyStateDetailText {
#if defined(GNUSTEP)
    NSString *paste = @"Ctrl+V";
#else
    NSString *paste = @"⌘V";
#endif
    NSString *text = [STScreenshotCapture isAvailable]
        ? [NSString stringWithFormat:@"Take a screenshot, open an image, or paste one with %@.", paste]
        : [NSString stringWithFormat:@"Open an image, or paste one with %@.", paste];
#if !defined(GNUSTEP)
    // Only macOS takes drops so far (Drag out, share and drop).
    text = [text stringByAppendingString:@" You can also drop an image anywhere in this window."];
#endif
    return text;
}

/// File > Take Screenshot…'s key equivalent, as the menus show it here.
- (NSString *)takeScreenshotShortcutText {
#if defined(GNUSTEP)
    return @"Ctrl+Shift+T";
#else
    return @"⇧⌘T";
#endif
}

#if defined(GNUSTEP)
/// Shows `shortcut` after the button's title, as the mockup's key hint (#221). GNUstep's themes
/// draw the title in their own colour; an attributed one would lose it. (macOS: STAccentButton.)
- (void)showShortcut:(NSString *)shortcut onEmptyStateButton:(NSButton *)button {
    [button setTitle:[NSString stringWithFormat:@"%@   %@", button.title, shortcut]];
}
#endif

/// The drawing tools work only on an image: with none open they're dimmed and disabled (#221).
- (void)updateDrawingToolsForImage:(BOOL)hasImage {
    NSSegmentedControl *tools = self.toolbarToolSegmentedControl;
    if (!tools) {
        return;
    }
    BOOL changed = (tools.isEnabled != hasImage);
    [tools setEnabled:hasImage];
    // GNUstep's segmented cell draws each segment's own enabled state, not the control's: each
    // segment is disabled too, so the theme dims them.
    for (NSInteger segment = 0; segment < tools.segmentCount; segment++) {
        if ([tools isEnabledForSegment:segment] != hasImage) {
            [tools setEnabled:hasImage forSegment:segment];
            changed = YES;
        }
    }
    if (changed) {
        [tools setNeedsDisplay:YES];
    }
}

- (NSTextField *)emptyStateLabel:(NSString *)text font:(NSFont *)font {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setAlignment:NSTextAlignmentCenter];
    [label setFont:font];
    [label setStringValue:text];
    [label sizeToFit];
    return label;
}

- (NSButton *)emptyStateButton:(NSString *)title action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, 32.0)];
    [button setButtonType:NSMomentaryPushInButton];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setTitle:title];
    [button setTarget:self];
    [button setAction:action];
    return button;
}

/// Centres the icon, labels and buttons in `frame`, stacked top to bottom.
- (void)layoutEmptyStateViewInFrame:(NSRect)frame {
    NSView *view = self.emptyStateView;
    [view setFrame:frame];
    NSView *icon = [view viewWithTag:1];
    NSTextField *title = [view viewWithTag:2];
    NSTextField *detail = [view viewWithTag:3];
    // In a row: Take Screenshot (unless hidden), Open…, Paste.
    NSMutableArray<NSView *> *buttons = [NSMutableArray array];
    for (NSNumber *tag in @[@6, @4, @5]) {
        NSView *button = [view viewWithTag:tag.integerValue];
        if (button && !button.isHidden) {
            [buttons addObject:button];
        }
    }
    [title sizeToFit];
    // At most 480pt wide, inside the outline, on as many lines as it needs.
    CGFloat detailWidth = MIN(480.0, NSWidth(frame) - 4.0 * [STEmptyStateView outlineInset]);
    NSSize detailSize = [[detail cell] cellSizeForBounds:NSMakeRect(0.0, 0.0, MAX(detailWidth, 120.0), 10000.0)];
    [detail setFrameSize:NSMakeSize(ceil(MAX(detailWidth, 120.0)), ceil(detailSize.height))];
    CGFloat gap = 12.0, buttonGap = 8.0;
    CGFloat buttonsWidth = buttonGap * (CGFloat)(buttons.count - 1);
    CGFloat rowHeight = 0.0;
    for (NSView *button in buttons) {
        buttonsWidth += NSWidth(button.frame);
        rowHeight = MAX(rowHeight, NSHeight(button.frame));
    }
    CGFloat total = NSHeight(icon.frame) + gap + NSHeight(title.frame) + 6.0 + NSHeight(detail.frame) + 18.0 + rowHeight;

    // Recent, under the buttons: a row of up to three cards, if the window has room for it.
    if (!self.emptyStateRecentsLoaded) {
        [self refreshEmptyStateRecents];
    }
    NSTextField *recentLabel = [view viewWithTag:STEmptyStateRecentLabelTag];
    NSMutableArray<STRecentCard *> *cards = [NSMutableArray array];
    for (NSInteger index = 0; index < STEmptyStateRecentCount; index++) {
        STRecentCard *card = [view viewWithTag:STEmptyStateRecentFirstCardTag + index];
        if ([card isKindOfClass:[STRecentCard class]] && card.representedObject) {
            [cards addObject:card];
        }
    }
    CGFloat inset = [STEmptyStateView outlineInset];
    CGFloat recentWidth = MIN(672.0, NSWidth(frame) - 4.0 * inset);
    CGFloat cardGap = 16.0;
    CGFloat cardWidth = floor((recentWidth - cardGap * (CGFloat)(STEmptyStateRecentCount - 1)) / (CGFloat)STEmptyStateRecentCount);
    CGFloat cardHeight = [STRecentCard heightForWidth:cardWidth];
    [recentLabel sizeToFit];
    CGFloat recentHeight = 34.0 + NSHeight(recentLabel.frame) + 8.0 + cardHeight;
    BOOL showRecents = cards.count > 0 && cardWidth >= 140.0 &&
        total + recentHeight <= NSHeight(frame) - 2.0 * inset - 24.0;
    if (showRecents) {
        total += recentHeight;
    }
    [recentLabel setHidden:!showRecents];
    for (NSInteger index = 0; index < STEmptyStateRecentCount; index++) {
        NSView *card = [view viewWithTag:STEmptyStateRecentFirstCardTag + index];
        [card setHidden:!(showRecents && [cards containsObject:(STRecentCard *)card])];
    }
    CGFloat midX = floor(NSWidth(frame) / 2.0);
    CGFloat y = floor((NSHeight(frame) + total) / 2.0);
    y -= NSHeight(icon.frame);
    [icon setFrameOrigin:NSMakePoint(midX - floor(NSWidth(icon.frame) / 2.0), y)];
    y -= gap + NSHeight(title.frame);
    [title setFrameOrigin:NSMakePoint(midX - floor(NSWidth(title.frame) / 2.0), y)];
    y -= 6.0 + NSHeight(detail.frame);
    [detail setFrameOrigin:NSMakePoint(midX - floor(NSWidth(detail.frame) / 2.0), y)];
    y -= 18.0 + rowHeight;
    CGFloat x = midX - floor(buttonsWidth / 2.0);
    for (NSView *button in buttons) {
        // Centred on the row: NSComboButton is shorter than the 32pt push buttons.
        [button setFrameOrigin:NSMakePoint(x, y + floor((rowHeight - NSHeight(button.frame)) / 2.0))];
        x += NSWidth(button.frame) + buttonGap;
    }
    if (showRecents) {
        CGFloat left = midX - floor(recentWidth / 2.0);
        y -= 34.0 + NSHeight(recentLabel.frame);
        [recentLabel setFrameOrigin:NSMakePoint(left, y)];
        y -= 8.0 + cardHeight;
        CGFloat cardX = left;
        for (STRecentCard *card in cards) {
            [card setFrame:NSMakeRect(cardX, y, cardWidth, cardHeight)];
            cardX += cardWidth + cardGap;
        }
    }
    [view setNeedsDisplay:YES];
}

#if !defined(GNUSTEP)
/// The narrowest content width, from `from` up to `limit`, at which every toolbar item shows, or
/// with `keptOnly` every item that must never overflow (`limit` if none does). Measured
/// by laying the window out, as the title's width counts too; the window keeps its size. A window
/// not yet on screen lays out all the same.
- (CGFloat)contentWidthShowingToolbarItems:(BOOL)keptOnly atMost:(CGFloat)limit from:(CGFloat)from {
    NSToolbar *toolbar = self.window.toolbar;
    if (!toolbar || !toolbar.isVisible || from >= limit) {
        return from;
    }
    NSMutableSet<NSString *> *wanted = [NSMutableSet set];
    for (NSToolbarItem *item in toolbar.items) {
        if (!keptOnly || item.visibilityPriority >= NSToolbarItemVisibilityPriorityUser) {
            [wanted addObject:item.itemIdentifier];
        }
    }
    NSSize original = self.window.contentView.frame.size;
    NSSize originalMinimum = self.window.contentMinSize;
    [self.window setContentMinSize:NSMakeSize(1.0, originalMinimum.height)];
    BOOL (^fits)(CGFloat) = ^BOOL(CGFloat width) {
        [self.window setContentSize:NSMakeSize(width, original.height)];
        [self.window layoutIfNeeded];
        NSSet *visible = [NSSet setWithArray:[toolbar.visibleItems valueForKey:@"itemIdentifier"]];
        return [wanted isSubsetOfSet:visible];
    };
    CGFloat low = from, high = limit;
    if (fits(low)) {
        high = low;
    } else if (!fits(high)) {
        low = high;
    }
    // To within 8pt, rounded up.
    while (high - low > 8.0) {
        CGFloat middle = floor((low + high) / 2.0);
        if (fits(middle)) {
            high = middle;
        } else {
            low = middle;
        }
    }
    [self.window setContentMinSize:originalMinimum];
    [self.window setContentSize:original];
    return ceil(high);
}
#endif

#if defined(GNUSTEP)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
#pragma clang diagnostic ignored "-Wundeclared-selector"
static const CGFloat STToolbarOverflowButtonWidth = 28.0f; // libs-gui's ClippedItemsViewWidth
static const CGFloat STHeaderBarTitleRoom = 100.0f; // Adwaita's GnomeThemeHeaderBarMinimumTitleWidth
static const CGFloat STToolbarKeptItemsSlack = 4.0f;

/// What an item takes in libs-gui's test for which items fit the row (-_visibleBackViews, which
/// WinUITheme repeats): a view item its minimum width and 10pt each side, a flexible space its
/// minimum, any other item its back view's width.
static CGFloat STToolbarItemMinimumRowWidth(NSToolbarItem *item) {
    NSString *identifier = item.itemIdentifier;
    if ([identifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]) {
        return MAX(0.0f, item.minSize.width);
    }
    if (item.view != nil) {
        return item.minSize.width + 2.0f * 10.0f;
    }
    if ([item respondsToSelector:@selector(_backView)]) {
        NSView *backView = [item performSelector:@selector(_backView)];
        return [backView isKindOfClass:[NSView class]] ? NSWidth(backView.frame) : 0.0f;
    }
    return 0.0f;
}

/// The content width at which every toolbar item shows: the items at their minimum widths, as
/// libs-gui sums them, plus what the window gives the row besides the toolbar view (the "..." menu
/// button where WinUITheme puts the menus there). 0 when there's no toolbar to measure. Worked out
/// from the items rather than by resizing the window, which can leave items in ">>" (#242).
- (CGFloat)contentWidthShowingAllToolbarItems {
    return [self contentWidthShowingToolbarItems:NO];
}

/// Whether the theme sends the toolbar's lowest-priority items into ">>" first (WinUITheme and
/// Adwaita say so), rather than libs-gui's last items. Asked of the theme, so a theme switched
/// away from stops answering.
static BOOL STToolbarThemeHonoursVisibilityPriority(void) {
    GSTheme *theme = [GSTheme theme];
    return [theme respondsToSelector:@selector(toolbarHonoursVisibilityPriority)] &&
           (BOOL)(intptr_t)[theme performSelector:@selector(toolbarHonoursVisibilityPriority)];
}

/// With `keptOnly`, the content width at which the items that must never overflow show (the tools,
/// colour and Copy) where the theme honours visibility priority: those items, the flexible spaces
/// and the ">>" button.
- (CGFloat)contentWidthShowingToolbarItems:(BOOL)keptOnly {
    NSToolbar *toolbar = self.window.toolbar;
    if (!toolbar || !toolbar.isVisible || ![toolbar respondsToSelector:@selector(_toolbarView)]) {
        return 0.0f;
    }
    NSView *toolbarView = [toolbar performSelector:@selector(_toolbarView)];
    if (![toolbarView isKindOfClass:[NSView class]] || NSWidth(toolbarView.frame) < 1.0f) {
        return 0.0f;
    }
    NSArray<NSToolbarItem *> *items = toolbar.items;
    // Adwaita's header bar counts its first flexible space as room for the title.
    NSView *bar = toolbarView.superview;
    BOOL titleInRow = [bar respondsToSelector:@selector(holdsToolbarInBar)] &&
                      (BOOL)(intptr_t)[bar performSelector:@selector(holdsToolbarInBar)];
    BOOL titleCounted = NO;
    BOOL anyOverflows = NO;
    CGFloat itemsWidth = 0.0f;
    for (NSToolbarItem *item in items) {
        BOOL flexible = [item.itemIdentifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier];
        if (keptOnly && !flexible && item.visibilityPriority < NSToolbarItemVisibilityPriorityUser) {
            anyOverflows = YES;
            continue;
        }
        CGFloat width = STToolbarItemMinimumRowWidth(item);
        if (titleInRow && !titleCounted && flexible) {
            width = MAX(width, STHeaderBarTitleRoom);
            titleCounted = YES;
        }
        itemsWidth += width;
    }
    if (anyOverflows) {
        itemsWidth += STToolbarOverflowButtonWidth;
    }
    CGFloat besideToolbar = MAX(0.0f, NSWidth([self.window.contentView frame]) - NSWidth(toolbarView.frame));
    return ceil(itemsWidth + besideToolbar);
}
#pragma clang diagnostic pop
#endif

- (void)resizeWindowToImageSize:(NSSize)imageSize {
    if (imageSize.width <= 0.0f || imageSize.height <= 0.0f || !self.window) {
        return;
    }
    // Sized for the image at actual size, which on a scaled Windows display is fewer points.
    CGFloat pixelsPerPoint = self.canvasView ? self.canvasView.screenPixelsPerPoint : 1.0f;
    imageSize = NSMakeSize(imageSize.width / pixelsPerPoint, imageSize.height / pixelsPerPoint);
    // With room for the stage's margin round it, and for a border the theme draws round the
    // clip view (CI's Adwaita draws 1pt), so the image opens at 100%.
    CGFloat themeBorder = NSMinX(self.scrollView.contentView.frame);
    themeBorder = (themeBorder > 0.0f && themeBorder < 8.0f) ? themeBorder : 0.0f;
    imageSize.width += 2.0f * (STCanvasStageMargin + themeBorder);
    imageSize.height += 2.0f * (STCanvasStageMargin + themeBorder);

    NSScreen *screen = self.window.screen ?: [NSScreen mainScreen];
    NSRect visibleFrame = screen ? screen.visibleFrame : NSMakeRect(0.0f, 0.0f, 1600.0f, 1000.0f);
    CGFloat maxWidth = visibleFrame.size.width * 0.95f;
    CGFloat maxHeight = visibleFrame.size.height * 0.95f;
    CGFloat barHeight = [self statusBarHeight];
    CGFloat maxContentHeight = MAX(100.0f, maxHeight - barHeight);

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

    // Tiny images get a usable window; the canvas centres them on its backdrop.
    CGFloat minimumWidth = MIN(STMinimumCanvasWidth, maxWidth);
    CGFloat minimumHeight = MIN(STMinimumCanvasHeight, maxContentHeight);
#if !defined(GNUSTEP)
    // macOS's toolbar shares its row with the title, so the minimum is too narrow for it. The
    // window can't be made so narrow that the tools, colour or Copy go to the overflow menu, and
    // opens wide enough for the whole toolbar.
    minimumWidth = MAX(minimumWidth, [self contentWidthShowingToolbarItems:YES atMost:maxWidth from:minimumWidth]);
    CGFloat targetWidth = MAX(contentWidth, minimumWidth);
    CGFloat toolbarWidth = [self contentWidthShowingToolbarItems:NO atMost:maxWidth from:targetWidth];
    if (toolbarWidth > targetWidth) {
        // A few points to spare: once the image is in, the toolbar's items can take a point more
        // than they measured with none (#221's 9-tool toolbar was 1pt short).
        toolbarWidth = MIN(maxWidth, toolbarWidth + 8.0);
    }
    targetWidth = MAX(targetWidth, toolbarWidth);
#else
    // Where the theme honours visibility priority, the window can't be made so narrow that the
    // tools, colour or Copy go into ">>". libs-gui keeps the row's first items instead, and keeping
    // Copy would keep everything before it (over 1100pt under Adwaita), so the canvas minimum stands.
    // A few points to spare: at 125% and 150% the theme rounds the items to whole pixels, and at
    // the bare sum Copy went into ">>" 2px short of it.
    if (STToolbarThemeHonoursVisibilityPriority()) {
        CGFloat kept = [self contentWidthShowingToolbarItems:YES];
        if (kept > 0.0f) {
            minimumWidth = MAX(minimumWidth, MIN(maxWidth, kept + STToolbarKeptItemsSlack));
        }
    }
    // Wide enough for the whole toolbar too: GNUstep moves the row's last items into the ">>"
    // menu first, and those are Save and Copy. At 125% and 150% an 860px screenshot's window
    // was narrower than the row and hid them (#221). The same few points to spare as macOS.
    CGFloat targetWidth = MAX(contentWidth, minimumWidth);
    CGFloat toolbarWidth = [self contentWidthShowingAllToolbarItems];
    if (toolbarWidth > targetWidth) {
        targetWidth = MIN(maxWidth, toolbarWidth + 8.0f);
    }
#endif
    CGFloat targetHeight = MAX(contentHeight, minimumHeight) + barHeight;

    [self.window setContentMinSize:NSMakeSize(minimumWidth, minimumHeight + barHeight)];
    [self.window setContentSize:NSMakeSize(targetWidth, targetHeight)];
    [self layoutContentSubviews];
    if (self.canvasView.isFitToWindow) {
        [self.canvasView updateForEnclosingBoundsChange];
    }
    [self.window center];
}

#pragma mark - Actions

- (void)openDocument:(id)sender {
#if defined(GNUSTEP)
    if (![self confirmProceedingWithUnsavedChanges]) {
        return;
    }
#endif
    NSOpenPanel *panel = [NSOpenPanel openPanel];
#if defined(GNUSTEP)
    [panel setAllowsMultipleSelection:NO];
#else
    [panel setAllowsMultipleSelection:YES];
#endif
    [panel setCanChooseDirectories:NO];
    [panel setAllowedFileTypes:[STOpenableImageFileTypes() arrayByAddingObject:STProjectFileExtension]];

    if (self.currentImageURL) {
        [panel setDirectoryURL:self.currentImageURL.URLByDeletingLastPathComponent];
    } else if (self.defaultSaveDirectory.length > 0) {
        NSURL *dirURL = [NSURL fileURLWithPath:self.defaultSaveDirectory];
        if (dirURL) {
            [panel setDirectoryURL:dirURL];
        }
    }

    if ([panel runModal] == NSModalResponseOK) {
        NSURL *selectedURL = panel.URL;
        if (!selectedURL) {
            ScreenshotToolAppendLog(@"Open panel returned OK but no file URL could be resolved");
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Unable to Open Selection";
            alert.informativeText = @"The selected file could not be resolved from the open dialog.";
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
            return;
        }
#if defined(GNUSTEP)
        [self openImageAtURL:selectedURL];
#else
        // Each in a window of its own (this one, if it's empty).
        for (NSURL *url in panel.URLs) {
            [[self applicationController] openURLInDocumentWindow:url preferring:self];
        }
#endif
    }
}

- (void)openRecentDocument:(id)sender {
    NSString *path = nil;
    // A menu item, or the empty state's Recent card (#221).
    if ([sender isKindOfClass:[NSMenuItem class]] || [sender isKindOfClass:[STRecentCard class]]) {
        id representedObject = [sender representedObject];
        if ([representedObject isKindOfClass:[NSString class]]) {
            path = [(NSString *)representedObject stringByStandardizingPath];
        }
    }
    if (path.length == 0) {
        return;
    }
#if defined(GNUSTEP)
    if (![self confirmProceedingWithUnsavedChanges]) {
        return;
    }
#endif

    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) {
        [self removeRecentDocumentPath:path];

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Recent File Not Found";
        alert.informativeText = [NSString stringWithFormat:@"%@ was removed from Open Recent.", path];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

#if defined(GNUSTEP)
    [self openImageAtURL:[NSURL fileURLWithPath:path]];
#else
    [[self applicationController] openURLInDocumentWindow:[NSURL fileURLWithPath:path] preferring:nil];
#endif
}

- (void)clearRecentDocuments:(id)sender {
    (void)sender;
    [self ensureRecentDocumentPathsLoaded];
    [self.recentDocumentPaths removeAllObjects];
    [self persistRecentDocumentPaths];
    [self rebuildOpenRecentMenu];
}

- (void)showPreferences:(id)sender {
    (void)sender;
    if (!self.preferencesWindowController) {
        self.preferencesWindowController = [[PreferencesWindowController alloc] initWithDelegate:self];
    }
    [self.preferencesWindowController showRelativeToWindow:self.window];
}

- (void)saveDocumentAs:(id)sender {
    (void)sender;
    [self saveImageWithPanel];
}

- (BOOL)saveImageWithPanel {
    if (![self.canvasView hasImage]) {
        return NO;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes:@[@"png", @"tif", @"tiff"]];
    [panel setCanCreateDirectories:YES];

    if (self.currentImageURL) {
        [panel setDirectoryURL:self.currentImageURL.URLByDeletingLastPathComponent];
        [panel setNameFieldStringValue:self.currentImageURL.lastPathComponent];
    } else if (self.currentProjectURL) {
        [panel setDirectoryURL:self.currentProjectURL.URLByDeletingLastPathComponent];
        NSString *base = [self.currentProjectURL.lastPathComponent stringByDeletingPathExtension];
        [panel setNameFieldStringValue:[base stringByAppendingPathExtension:@"png"]];
    } else {
        if (self.defaultSaveDirectory.length > 0) {
            NSURL *dirURL = [NSURL fileURLWithPath:self.defaultSaveDirectory];
            if (dirURL) {
                [panel setDirectoryURL:dirURL];
            }
        }
        [panel setNameFieldStringValue:[STPastedImageTitle stringByAppendingPathExtension:@"png"]];
    }

    if ([panel runModal] != NSModalResponseOK) {
        return NO;
    }

    NSURL *destination = panel.URL;
    if (!destination) {
        ScreenshotToolAppendLog(@"Save panel returned OK but no destination URL could be resolved");
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Unable to Save Image";
        alert.informativeText = @"The selected save destination could not be resolved from the save dialog.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return NO;
    }
    NSImage *flattened = [self.canvasView flattenedImage];
    if (!flattened) {
        return NO;
    }

    BOOL useTIFF = STPathUsesTIFFExtension(destination.path);
    NSData *imageData = useTIFF ? [flattened TIFFRepresentation] : [self pngDataForImage:flattened];
    if (!imageData) {
        return NO;
    }

    [self ensureDirectoryExistsAtPath:[destination.path stringByDeletingLastPathComponent]];

    NSError *error = nil;
    if (!STWriteDataAtomically(imageData, destination, &error)) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Unable to Save Image";
        alert.informativeText = error.localizedDescription ?: @"An unknown error occurred.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return NO;
    }

    self.currentImageURL = destination;
    [self addRecentDocumentURL:destination];
    [self.window setTitleWithRepresentedFilename:destination.path];
    [self markAnnotationsSaved];
    return YES;
}

- (void)copy:(id)sender {
    (void)sender;
    if (![self.canvasView hasImage]) {
        [self showCopyFeedbackMessage:@"No image to copy" duration:2.0];
        return;
    }

    NSImage *flattened = [self.canvasView flattenedImageForSelection];
    if (!flattened) {
        [self showCopyFeedbackMessage:@"Copy failed" duration:2.0];
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
        [self showCopyFeedbackMessage:@"Copy failed" duration:2.0];
        return;
    }

    BOOL wrotePasteboard = NO;
    if ([self usesWindowsClipboard]) {
        // Not the pasteboard as well: GNUstep's pasteboard server would then take the Windows
        // clipboard back and offer only text.
        wrotePasteboard = STWindowsClipboardWritePNGData(pngData ?: [self pngDataForImage:flattened]);
        ScreenshotToolAppendLog([NSString stringWithFormat:@"copy action wrote Windows clipboard=%@",
                                 wrotePasteboard ? @"YES" : @"NO"]);
    } else {
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard declareTypes:types owner:nil];
        if (pngData) {
            wrotePasteboard = [pasteboard setData:pngData forType:NSPasteboardTypePNG] || wrotePasteboard;
        }
        if (tiffData) {
            wrotePasteboard = [pasteboard setData:tiffData forType:NSPasteboardTypeTIFF] || wrotePasteboard;
        }
    }
    BOOL mirroredWayland = STMirrorPNGDataToWaylandClipboard(pngData);

    ScreenshotToolAppendLog([NSString stringWithFormat:@"copy action write results pasteboard=%@ waylandMirror=%@",
                             wrotePasteboard ? @"YES" : @"NO",
                             mirroredWayland ? @"YES" : @"NO"]);

    if (!wrotePasteboard && !mirroredWayland) {
        [self showCopyFeedbackMessage:@"Copy failed" duration:2.0];
        return;
    }

    self.clipboardCheckedAt = 0.0;
    BOOL x11OnlyCopy = (STScreenshotToolIsWaylandSession() && !mirroredWayland && wrotePasteboard);
    NSString *status = nil;
    if ([self.canvasView hasSelection]) {
        status = x11OnlyCopy ? @"Copied selection to X11 clipboard" : @"Copied selection to clipboard";
    } else {
        status = x11OnlyCopy ? @"Copied image to X11 clipboard" : @"Copied image to clipboard";
    }
    [self showCopyFeedbackMessage:status duration:3.0];
}

/// The pasteboard Paste as New Image reads (tests substitute a private one).
- (NSPasteboard *)clipboardPasteboard {
    return [NSPasteboard generalPasteboard];
}

/// On Windows images go to and from the Windows clipboard itself, which GNUstep bridges only text
/// to; not when a test has substituted its own pasteboard.
- (BOOL)usesWindowsClipboard {
    return STWindowsClipboardIsNative() && [self clipboardPasteboard] == [NSPasteboard generalPasteboard];
}

- (NSData *)clipboardPNGDataForPasteAsNewImage {
    NSPasteboard *pasteboard = [self clipboardPasteboard];
    NSArray<NSString *> *imageTypes = @[ NSPasteboardTypePNG, NSPasteboardTypeTIFF, NSTIFFPboardType ];
    NSData *windowsPNG = [self usesWindowsClipboard] ? STWindowsClipboardPNGData() : nil;
    if (windowsPNG.length > 0) {
        ScreenshotToolAppendLog(@"pasteAsNewImage: using image data from the Windows clipboard");
        return windowsPNG;
    }
    // On Windows the pasteboard can still hold an image from before the Windows clipboard changed.
    NSString *availableType = [self usesWindowsClipboard] ? nil : [pasteboard availableTypeFromArray:imageTypes];
    if (availableType.length > 0) {
        NSData *data = [pasteboard dataForType:availableType];
        if ([availableType isEqualToString:NSPasteboardTypePNG] && data.length > 0) {
            ScreenshotToolAppendLog(@"pasteAsNewImage: using PNG data from NSPasteboard");
            return data;
        }
        if (data.length > 0) {
            NSImage *image = [[NSImage alloc] initWithData:data];
            NSData *pngData = [self pngDataForImage:image];
            if (pngData.length > 0) {
                ScreenshotToolAppendLog([NSString stringWithFormat:@"pasteAsNewImage: converted %@ data from NSPasteboard to PNG",
                                         availableType]);
                return pngData;
            }
        }
    }

    NSString *imagePath = [self clipboardImageFilePath];
    if (imagePath.length > 0) {
        NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
        NSData *pngData = [self pngDataForImage:image];
        if (pngData.length > 0) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"pasteAsNewImage: using image file %@ from NSPasteboard",
                                     imagePath]);
            return pngData;
        }
    }

    NSData *waylandPNG = STWaylandClipboardDataForMIMEType(@"image/png");
    if (waylandPNG.length > 0) {
        ScreenshotToolAppendLog(@"pasteAsNewImage: using PNG data from Wayland clipboard");
        return waylandPNG;
    }

    NSData *waylandTIFF = STWaylandClipboardDataForMIMEType(@"image/tiff");
    if (waylandTIFF.length > 0) {
        NSImage *image = [[NSImage alloc] initWithData:waylandTIFF];
        NSData *pngData = [self pngDataForImage:image];
        if (pngData.length > 0) {
            ScreenshotToolAppendLog(@"pasteAsNewImage: converted TIFF data from Wayland clipboard to PNG");
            return pngData;
        }
    }

    ScreenshotToolAppendLog(@"pasteAsNewImage: clipboard does not contain supported image data");
    return nil;
}

/// The first image file among the files on the clipboard (as a file manager copies them), or nil.
- (NSString *)clipboardImageFilePath {
    NSPasteboard *pasteboard = [self clipboardPasteboard];
    id paths = nil;
    if ([self usesWindowsClipboard]) {
        paths = STWindowsClipboardFilePaths();
    } else if ([pasteboard availableTypeFromArray:@[ NSFilenamesPboardType ]]) {
        paths = [pasteboard propertyListForType:NSFilenamesPboardType];
    }
    if (![paths isKindOfClass:[NSArray class]]) {
        return nil;
    }
    // Picture formats only: GNUstep's +[NSImage imageFileTypes] can include anything ImageMagick reads,
    // text files among them.
    NSArray<NSString *> *imageTypes = @[ @"png", @"tiff", @"tif", @"jpg", @"jpeg", @"gif", @"bmp", @"webp" ];
    for (id path in paths) {
        if (![path isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *extension = [[path pathExtension] lowercaseString];
        if ([imageTypes containsObject:extension] && [[NSFileManager defaultManager] isReadableFileAtPath:path]) {
            return path;
        }
    }
    return nil;
}

/// Whether Paste as New Image has something to paste: PNG or TIFF data, or an image file, on the
/// clipboard. Menus validate often, so a result is reused for a second.
- (BOOL)clipboardHasImage {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (self.clipboardCheckedAt > 0.0 && now - self.clipboardCheckedAt < 1.0) {
        return self.clipboardHadImage;
    }
    NSPasteboard *pasteboard = [self clipboardPasteboard];
    NSArray<NSString *> *imageTypes = @[ NSPasteboardTypePNG, NSPasteboardTypeTIFF, NSTIFFPboardType ];
    // No wl-paste here: on GNOME it takes keyboard focus to read the clipboard, so the window
    // stopped being key, became key again and re-checked, and its title bar flickered. XWayland
    // mirrors the Wayland clipboard, so the pasteboard already sees an image copied there.
    BOOL hasImage = ([self usesWindowsClipboard] ? STWindowsClipboardHasImage()
                                                  : [pasteboard availableTypeFromArray:imageTypes] != nil)
        || [self clipboardImageFilePath] != nil;
    self.clipboardHadImage = hasImage;
    self.clipboardCheckedAt = now;
    return hasImage;
}

/// Re-checks the clipboard and enables the empty state's Paste button to match (#76). Only while
/// the empty state shows: the first clipboard read starts GNUstep's pasteboard server and waits for
/// it, so launching with an image never reads it. Paste as New Image checks for itself when its
/// menu item is validated.
- (void)refreshPasteAvailability {
    self.clipboardCheckedAt = 0.0;
    if (!self.emptyStateView || self.emptyStateView.isHidden) {
        return;
    }
    BOOL hasImage = [self clipboardHasImage];
    NSButton *paste = [self.emptyStateView viewWithTag:5];
    [paste setEnabled:hasImage];
    [paste setToolTip:hasImage ? nil : @"The clipboard has no image"];
}

- (void)clipboardDidChange:(NSNotification *)notification {
    (void)notification;
    [self refreshPasteAvailability];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    // Another app may have changed the clipboard.
    [self refreshPasteAvailability];
#if !defined(GNUSTEP)
    for (AppDelegate *document in self.documentWindows) {
        [document refreshPasteAvailability];
    }
#endif
}

- (BOOL)isTemporaryClipboardImageURL:(NSURL *)url {
    if (!url.isFileURL) {
        return NO;
    }
    NSString *directory = [[url.path stringByDeletingLastPathComponent] stringByStandardizingPath];
    return [directory isEqualToString:[STTemporaryClipboardDirectory() stringByStandardizingPath]];
}

- (NSURL *)temporaryClipboardImageURLForPNGData:(NSData *)pngData {
    if (pngData.length == 0) {
        return nil;
    }

    NSString *root = STTemporaryClipboardDirectory();
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:root
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&error]) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"pasteAsNewImage: failed to create temp directory %@ (%@)",
                                 root,
                                 error.localizedDescription ?: @"unknown error"]);
        return nil;
    }

    NSString *filename = [NSString stringWithFormat:@"clipboard-%@.png", [NSUUID UUID].UUIDString];
    NSURL *url = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:filename]];
    if (![pngData writeToURL:url options:NSDataWritingAtomic error:&error]) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"pasteAsNewImage: failed to write temp image %@ (%@)",
                                 url.path ?: @"<nil>",
                                 error.localizedDescription ?: @"unknown error"]);
        return nil;
    }
    return url;
}

- (BOOL)launchNewWindowForImageAtURL:(NSURL *)url {
    if (!url.isFileURL || url.path.length == 0) {
        return NO;
    }
#if !defined(GNUSTEP)
    // A window in this process; GNUstep starts another (one window per process there).
    return [[self applicationController] openURLInDocumentWindow:url preferring:self];
#endif
    // As on macOS, an empty window takes the image rather than being left beside a new one.
    if (![self.canvasView hasImage]) {
        return [self openImageAtURL:url];
    }
#if defined(_WIN32)
    // NSTask starts a process hidden on Windows, so its window would never show.
    BOOL launched = STWindowsLaunchProcess([[NSBundle mainBundle] executablePath], @[ url.path ]);
    ScreenshotToolAppendLog([NSString stringWithFormat:@"pasteAsNewImage: %@ new instance for %@",
                             launched ? @"launched" : @"couldn't launch", url.path]);
    return launched;
#endif

    @try {
        NSTask *task = [[NSTask alloc] init];
#if defined(GNUSTEP)
        NSString *openappPath = nil;
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/GNUstep/System/Tools/openapp"]) {
            openappPath = @"/usr/GNUstep/System/Tools/openapp";
        } else {
            openappPath = STExecutablePathInPATH(@"openapp");
        }
        NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
        if (openappPath.length > 0 && bundlePath.length > 0) {
            task.launchPath = openappPath;
            task.arguments = @[ bundlePath, url.path ];
        } else
#endif
        {
            NSString *executablePath = [[NSBundle mainBundle] executablePath];
            if (executablePath.length == 0) {
                ScreenshotToolAppendLog(@"pasteAsNewImage: executable path unavailable");
                return NO;
            }
            task.launchPath = executablePath;
            task.arguments = @[ url.path ];
        }

        [task launch];
        ScreenshotToolAppendLog([NSString stringWithFormat:@"pasteAsNewImage: launched new instance for %@",
                                 url.path ?: @"<nil>"]);
        return YES;
    } @catch (NSException *exception) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"pasteAsNewImage launch exception for %@ (%@ - %@)",
                                 url.path ?: @"<nil>",
                                 exception.name ?: @"<no name>",
                                 exception.reason ?: @"<no reason>"]);
    }
    return NO;
}

#pragma mark - Take Screenshot

/// Takes a screenshot with the desktop's own tool and opens it to annotate: in this window when it
/// has no image, otherwise in a new one, as Paste as New Image does.
- (void)takeScreenshot:(id)sender {
    (void)sender;
    if ([STScreenshotCapture isCapturing]) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    STScreenshotCaptureCompletion completion = ^(STScreenshotCaptureResult result, NSURL *url, NSString *failure) {
        [weakSelf finishScreenshotWithResult:result url:url failure:failure];
    };
#if defined(GNUSTEP) && !defined(_WIN32)
    // GNOME's tool freezes the screen as it opens: this window would be in the way. It comes back
    // when the tool answers, cancelled or not. (The Snipping Tool's cancel can't be seen.)
    if (self.window.isVisible) {
        self.hiddenForScreenshot = YES;
        [self.window orderOut:nil];
        [self performSelector:@selector(startScreenshotCapture:) withObject:completion afterDelay:0.3];
        return;
    }
#endif
    [self startScreenshotCapture:completion];
}

- (void)startScreenshotCapture:(STScreenshotCaptureCompletion)completion {
    [STScreenshotCapture captureForWindow:(self.hiddenForScreenshot ? nil : self.window) completion:completion];
}

- (void)finishScreenshotWithResult:(STScreenshotCaptureResult)result url:(NSURL *)url failure:(NSString *)failure {
    if (self.hiddenForScreenshot) {
        self.hiddenForScreenshot = NO;
        [self.window makeKeyAndOrderFront:nil];
    }
    if (result == STScreenshotCaptureResultClipboard) {
        NSData *pngData = [self clipboardPNGDataForPasteAsNewImage];
        url = pngData.length > 0 ? [self temporaryClipboardImageURLForPNGData:pngData] : nil;
        if (!url) {
            [self showTransientFeedbackMessage:@"The snip couldn't be read from the clipboard" duration:2.5];
            return;
        }
#if !defined(GNUSTEP)
    } else if (result == STScreenshotCaptureResultFile && url) {
        // screencapture's file is a temporary one: kept with the pasted images, it opens untitled
        // as they do, and goes once it's open.
        NSData *pngData = [NSData dataWithContentsOfURL:url];
        [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
        url = pngData.length > 0 ? [self temporaryClipboardImageURLForPNGData:pngData] : nil;
        if (!url) {
            [self showTransientFeedbackMessage:@"The screenshot couldn't be read" duration:2.5];
            return;
        }
#endif
    } else if (result != STScreenshotCaptureResultFile || !url) {
        if (failure.length > 0) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Take Screenshot failed: %@", failure]);
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Unable to Take Screenshot";
            alert.informativeText = failure;
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        }
        return;
    }
#if !defined(GNUSTEP)
    // The front window if it's empty, otherwise a new one.
    if (![[self applicationController] openURLInDocumentWindow:url preferring:nil]) {
        [STFrontDocument() showTransientFeedbackMessage:@"Unable to open the screenshot" duration:2.5];
    }
#else
    if (![self.canvasView hasImage]) {
        [self openImageAtURL:url];
    } else if (![self launchNewWindowForImageAtURL:url]) {
        [self showTransientFeedbackMessage:@"Unable to open the screenshot in a new window" duration:2.5];
    }
#endif
}

- (void)pasteAsNewImage:(id)sender {
    (void)sender;
    NSData *pngData = [self clipboardPNGDataForPasteAsNewImage];
    if (pngData.length == 0) {
        [self showTransientFeedbackMessage:@"Clipboard does not contain an image" duration:2.0];
        return;
    }

    NSURL *temporaryURL = [self temporaryClipboardImageURLForPNGData:pngData];
    if (!temporaryURL) {
        [self showTransientFeedbackMessage:@"Unable to prepare clipboard image" duration:2.0];
        return;
    }

    if (![self launchNewWindowForImageAtURL:temporaryURL]) {
        [self showTransientFeedbackMessage:@"Unable to open clipboard image in a new window" duration:2.0];
    }
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
    [self.window makeFirstResponder:self.canvasView];
    [self showStatusMessage:@"Cropped image" duration:2.0];
}

// The Edit menu's canvas commands, for this window's canvas.
- (void)redactSelection:(id)sender {
    [self.canvasView redactSelection:sender];
}

- (void)duplicateAnnotations:(id)sender {
    [self.canvasView duplicateAnnotations:sender];
}

- (void)bringAnnotationsToFront:(id)sender {
    [self.canvasView bringAnnotationsToFront:sender];
}

- (void)sendAnnotationsToBack:(id)sender {
    [self.canvasView sendAnnotationsToBack:sender];
}

- (void)canvasViewDidRestoreState:(NSNotification *)notification {
    if (notification.object != self.canvasView) {
        return;
    }
    if ([self.canvasView hasImage]) {
        [self resizeWindowToImageSize:self.canvasView.image.size];
    }
    // The image's size changed (an undone crop): the status bar says so, and the zoom it fits at.
    [self refreshStatusZoomControls];
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

    CGFloat current = self.canvasView.displayZoomScale;
    CGFloat next = [self nextZoomScaleAbove:current];
    [self setZoomScale:next];
}

- (void)zoomOut:(id)sender {
    if (![self.canvasView hasImage]) {
        return;
    }
    // From Fit too, the step below the scale shown: a fixed 50% zoomed in when Fit was below it (#307).
    CGFloat current = self.canvasView.displayZoomScale;
    CGFloat next = [self nextZoomScaleBelow:current];
    [self setZoomScale:next];
}

- (void)zoomFitToWindow:(id)sender {
    if (![self.canvasView hasImage]) {
        return;
    }
    self.canvasView.fitToWindow = YES;
    [self.canvasView updateForEnclosingBoundsChange];
    [self reflectZoomSelection];
}

- (void)zoomPreset25:(id)sender {
    if (![self.canvasView hasImage]) {
        return;
    }
    [self setZoomScale:0.25];
}

- (void)zoomPreset50:(id)sender {
    if (![self.canvasView hasImage]) {
        return;
    }
    [self setZoomScale:0.5];
}

- (void)zoomPreset100:(id)sender {
    if (![self.canvasView hasImage]) {
        return;
    }
    [self setZoomScale:1.0];
}

- (void)zoomPreset200:(id)sender {
    if (![self.canvasView hasImage]) {
        return;
    }
    [self setZoomScale:2.0];
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
    // Within what one decimal would show: actual size on a scaled display works out a hair off
    // a whole percent ("100.0%" at 125%).
    if (fabs(percent - rounded) < 0.05f) {
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
    NSEvent *event = [NSApp currentEvent];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ toolbar action fired (sender=%@, event=%@)",
                             STDebugToolName(ScreenshotCanvasToolHighlighter),
                             STDebugDescriptionForSender(sender),
                             STDebugDescriptionForEvent(event)]);
    BOOL openPopover = [self isDoubleClickEvent:event];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ toolbar action doubleClick=%@ (clickCount=%ld)",
                             STDebugToolName(ScreenshotCanvasToolHighlighter),
                             openPopover ? @"YES" : @"NO",
                             (long)STEventClickCount(event)]);
    [self selectTool:ScreenshotCanvasToolHighlighter];
    if (openPopover) {
        ScreenshotToolAppendLog(@"Opening Highlighter popover after double-click toolbar activation");
        [self showToolSettingsPopoverForTool:ScreenshotCanvasToolHighlighter event:event];
    } else {
        ScreenshotToolAppendLog(@"Highlighter popover not opened (no double-click detected)");
    }
}

- (void)activateArrow:(id)sender {
    (void)sender;
    [self selectTool:ScreenshotCanvasToolArrow];
}

- (void)activateRectangle:(id)sender {
    (void)sender;
    [self selectTool:ScreenshotCanvasToolRectangle];
}

- (void)activateStep:(id)sender {
    (void)sender;
    [self selectTool:ScreenshotCanvasToolStep];
}

- (void)activateRedact:(id)sender {
    (void)sender;
    [self selectTool:ScreenshotCanvasToolRedact];
}

- (void)activatePen:(id)sender {
    NSEvent *event = [NSApp currentEvent];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ toolbar action fired (sender=%@, event=%@)",
                             STDebugToolName(ScreenshotCanvasToolPen),
                             STDebugDescriptionForSender(sender),
                             STDebugDescriptionForEvent(event)]);
    BOOL openPopover = [self isDoubleClickEvent:event];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ toolbar action doubleClick=%@ (clickCount=%ld)",
                             STDebugToolName(ScreenshotCanvasToolPen),
                             openPopover ? @"YES" : @"NO",
                             (long)STEventClickCount(event)]);
    [self selectTool:ScreenshotCanvasToolPen];
    if (openPopover) {
        ScreenshotToolAppendLog(@"Opening Pen popover after double-click toolbar activation");
        [self showToolSettingsPopoverForTool:ScreenshotCanvasToolPen event:event];
    } else {
        ScreenshotToolAppendLog(@"Pen popover not opened (no double-click detected)");
    }
}

- (void)activateEraser:(id)sender {
    [self selectTool:ScreenshotCanvasToolEraser];
}

- (void)activateText:(id)sender {
    NSEvent *event = [NSApp currentEvent];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ toolbar action fired (sender=%@, event=%@)",
                             STDebugToolName(ScreenshotCanvasToolText),
                             STDebugDescriptionForSender(sender),
                             STDebugDescriptionForEvent(event)]);
    BOOL openPopover = [self isDoubleClickEvent:event];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"%@ toolbar action doubleClick=%@ (clickCount=%ld)",
                             STDebugToolName(ScreenshotCanvasToolText),
                             openPopover ? @"YES" : @"NO",
                             (long)STEventClickCount(event)]);
    [self selectTool:ScreenshotCanvasToolText];
    if (openPopover) {
        ScreenshotToolAppendLog(@"Opening Text popover after double-click toolbar activation");
        [self showToolSettingsPopoverForTool:ScreenshotCanvasToolText event:event];
    } else {
        ScreenshotToolAppendLog(@"Text popover not opened (no double-click detected)");
    }
}

- (void)activateSelect:(id)sender {
    [self selectTool:ScreenshotCanvasToolSelect];
}

#pragma mark - Helpers

- (NSImage *)imageForToolbarIdentifier:(NSToolbarItemIdentifier)identifier active:(BOOL)active {
    NSArray<NSString *> *candidates = [self iconNameCandidatesForToolbarIdentifier:identifier active:active];
    if (candidates.count == 0) {
        return nil;
    }

    static NSMutableDictionary<NSString *, NSImage *> *toolbarCache = nil;
    if (!toolbarCache) {
        toolbarCache = [[NSMutableDictionary alloc] init];
    }

    for (NSString *candidate in candidates) {
        if (candidate.length == 0) {
            continue;
        }
        NSImage *icon = toolbarCache[candidate];
        if (!icon) {
            NSImage *base = [self imageNamed:candidate];
            if (base) {
#if defined(GNUSTEP)
                icon = [base copy];
                if (icon) {
                    [icon setSize:NSMakeSize(ToolbarIconDimension, ToolbarIconDimension)];
                    STMarkSymbolicIcon(icon, candidate);
                    if ([candidate hasSuffix:@"-symbolic"] && ![[icon name] isEqualToString:candidate]) {
                        // The toolbar's first image already holds the file's name.
                        NSString *stem = [candidate substringToIndex:candidate.length - [@"-symbolic" length]];
                        [icon setName:[stem stringByAppendingString:@"-item-symbolic"]];
                    }
                }
#else
                if (STIsSizedToolbarIcon(base)) {
                    icon = [base copy];
                    [icon setSize:NSMakeSize(ToolbarIconDimension, ToolbarIconDimension)];
                } else {
                    icon = STRenderToolbarIcon(base);
                }
                STMarkSymbolicIcon(icon, candidate);
#endif
                toolbarCache[candidate] = icon;
                ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: loaded toolbar icon %@", candidate]);
            } else {
                ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: toolbar icon %@ missing base image", candidate]);
            }
        }
        if (icon) {
            return icon;
        }
    }
    return nil;
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
    NSImage *sized = STSizedToolbarIcon(filename, NSMakeSize(ToolbarIconDimension, ToolbarIconDimension));
    if (sized) {
        cache[filename] = sized;
        return sized;
    }

    NSArray<NSString *> *extensions = @[@"png", @"tiff", @"tif", @"bmp"];
    NSString *path = nil;
    for (NSString *ext in extensions) {
        path = STPathForToolbarResource(filename, ext);
        if (path.length > 0) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: attempting to load image %@", path]);
            break;
        }
    }
    if (!path) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: missing resource %@", filename]);
        NSImage *placeholder = [[NSImage alloc] initWithSize:NSMakeSize(ToolbarIconDimension, ToolbarIconDimension)];
        if (placeholder) {
            [placeholder lockFocus];
            [[NSColor colorWithCalibratedWhite:0.85f alpha:1.0f] setFill];
            NSRectFill(NSMakeRect(0.0f, 0.0f, ToolbarIconDimension, ToolbarIconDimension));
            [[NSColor colorWithCalibratedWhite:0.35f alpha:1.0f] setStroke];
            NSFrameRectWithWidth(NSMakeRect(0.5f, 0.5f, ToolbarIconDimension - 1.0f, ToolbarIconDimension - 1.0f), 1.0f);
            [placeholder unlockFocus];
            cache[filename] = placeholder;
        }
        return placeholder;
    }

#if defined(GNUSTEP)
    NSImage *image = STBitmapBackedImageFromFile(path, NSMakeSize(ToolbarIconDimension, ToolbarIconDimension));
#else
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
#endif
    if (image) {
        cache[filename] = image;
        ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: loaded image %@", path]);
    } else {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"ScreenshotTool: failed to load image %@", path]);
    }
    return image;
}

- (void)selectTool:(ScreenshotCanvasTool)tool {
    [self closeActivePopovers];
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
        case ScreenshotCanvasToolArrow:
            selectedIdentifier = ToolbarItemArrow;
            break;
        case ScreenshotCanvasToolRectangle:
            selectedIdentifier = ToolbarItemRectangle;
            break;
        case ScreenshotCanvasToolStep:
            selectedIdentifier = ToolbarItemStep;
            break;
        case ScreenshotCanvasToolRedact:
            selectedIdentifier = ToolbarItemRedact;
            break;
    }

    if (tool == ScreenshotCanvasToolPen || tool == ScreenshotCanvasToolHighlighter || tool == ScreenshotCanvasToolArrow ||
        tool == ScreenshotCanvasToolRectangle || tool == ScreenshotCanvasToolStep) {
        self.lastWidthTool = STSettingsToolForTool(tool);
    }

    if (self.toolbar) {
        [self.toolbar setSelectedItemIdentifier:selectedIdentifier];
        [self refreshToolButtonIcons];
    }
}

- (void)setZoomScale:(CGFloat)scale {
    self.canvasView.fitToWindow = NO;
    self.canvasView.displayZoomScale = scale;
    [self.canvasView setNeedsDisplay:YES];
    [self reflectZoomSelection];
}

- (void)reflectZoomSelection {
    [self refreshZoomToolbarControl];
    [self.zoomPopoverController refresh];
    [self refreshStatusZoomControls];
}

- (BOOL)openImageAtURL:(NSURL *)url {
    if (!url) {
        ScreenshotToolAppendLog(@"openImageAtURL invoked with nil URL");
        return NO;
    }
    if (STURLIsProject(url)) {
        return [self openProjectAtURL:url];
    }

    NSImage *image = nil;
    @try {
        image = [[NSImage alloc] initWithContentsOfURL:url];
    } @catch (NSException *exception) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"openImageAtURL exception for %@ (%@ - %@)",
                                 url.path ?: url.absoluteString ?: @"<unknown>",
                                 exception.name ?: @"<no name>",
                                 exception.reason ?: @"<no reason>"]);
        image = nil;
    }
    if (!image) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"openImageAtURL failed to load image at %@",
                                 url.path ?: url.absoluteString ?: @"<unknown>"]);
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Unable to Open Image";
        alert.informativeText = url.path;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return NO;
    }

    NSSize size = image.size;
    NSBitmapImageRep *bitmapRep = nil;
    for (NSImageRep *rep in [image representations]) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            bitmapRep = (NSBitmapImageRep *)rep;
            break;
        }
    }
    if (bitmapRep && bitmapRep.pixelsWide > 0 && bitmapRep.pixelsHigh > 0) {
        // Normalize to 1 image pixel per point to ignore DPI metadata.
        size = NSMakeSize((CGFloat)bitmapRep.pixelsWide, (CGFloat)bitmapRep.pixelsHigh);
        [image setSize:size];
    }
    ScreenshotToolAppendLog([NSString stringWithFormat:@"openImageAtURL loaded %@ (%.0fx%.0f)",
                             url.path ?: url.absoluteString ?: @"<unknown>",
                             size.width,
                             size.height]);
    [self.canvasView loadImage:image];
    self.statusFileSizeURL = nil; // Read the size again, in case the file changed.
    if ([self isTemporaryClipboardImageURL:url]) {
        // Paste as New Image hands us a temp file; present it as an untitled document instead.
        self.currentImageURL = nil;
        [self.window setTitle:STPastedImageTitle];
        [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    } else {
        self.currentImageURL = url;
        [self addRecentDocumentURL:url];
        [self.window setTitleWithRepresentedFilename:url.path];
    }
    [self resizeWindowToImageSize:image.size];
    [self.canvasView updateForEnclosingBoundsChange];
    [self reflectZoomSelection];
    [self refreshToolButtonIcons];
    self.currentProjectURL = nil;
    [self markAnnotationsSaved];
    return YES;
}

#pragma mark - Selection bar

- (void)canvasViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateSelectionActionBar];
}

/// Shows the bar next to a finished region selection that's on screen, and hides it otherwise:
/// while the selection is drawn or dragged, while a label is edited, and when it's turned off.
- (void)updateSelectionActionBar {
    ScreenshotCanvasView *canvas = self.canvasView;
    if (!canvas) {
        return;
    }
    if (!self.selectionActionBar) {
        // On the canvas itself, as the text editor is: GNUstep repaints an opaque view over
        // siblings above it, and the canvas repaints for the selection's moving dashes.
        self.selectionActionBar = [[STSelectionActionBar alloc] initWithTarget:self showsShare:STCanShareImages()];
        self.selectionActionBar.hidden = YES;
        [canvas addSubview:self.selectionActionBar];
        canvas.coveringView = self.selectionActionBar;
    }
    // The part of the canvas the scroll view shows (its visibleRect is empty off screen).
    NSClipView *clip = self.scrollView.contentView;
    NSRect visible = NSIntersectionRect([canvas convertRect:clip.bounds fromView:clip], canvas.bounds);
    NSRect selection = [canvas selectionRectInView];
    BOOL show = self.selectionBarPreference && [canvas hasImage] && [canvas hasSelection] &&
        ![canvas isAdjustingSelection] && ![canvas activeTextEntry] && NSIntersectsRect(selection, visible);
    if (show) {
        [self.selectionActionBar setFrame:[self.selectionActionBar frameForSelection:selection visible:visible]];
    }
    if ([self.selectionActionBar isHidden] == show) {
        self.selectionActionBar.hidden = !show;
        [self.window invalidateCursorRectsForView:self.selectionActionBar];
    }
}

#pragma mark - Sharing

#if !defined(GNUSTEP)
/// The picker closed, with or without a service: the click's anchor goes, and a chosen mail gets
/// its subject.
- (void)sharingServicePicker:(NSSharingServicePicker *)sharingServicePicker didChooseSharingService:(nullable NSSharingService *)service {
    (void)sharingServicePicker;
    [self.shareAnchorView removeFromSuperview];
    self.shareAnchorView = nil;
    if (service) {
        [self prepareSharingService:service];
    }
}
#endif

/// Share… from the canvas's right-click menu or the selection's bar: the picker for what a share
/// sends, next to the click or the button.
- (void)shareImage:(id)sender {
    if ([sender isKindOfClass:[NSView class]]) {
        NSView *view = (NSView *)sender;
        [self presentShareFromView:view rect:view.bounds];
        return;
    }
    NSPoint point = self.canvasView.lastContextMenuPoint;
    [self presentShareFromView:self.canvasView rect:NSMakeRect(point.x, point.y, 1.0, 1.0)];
}

/// File > Share… on GNUstep: the sheet at the top of the window, where libs-sharing's toolbar
/// item puts it when the item has no view of its own (it's folded into », say).
- (void)shareFromFileMenu:(id)sender {
    (void)sender;
    NSView *view = self.window.contentView;
    NSRect bounds = view.bounds;
    CGFloat top = view.isFlipped ? NSMinY(bounds) : NSMaxY(bounds) - 1.0;
    [self presentShareFromView:view rect:NSMakeRect(NSMidX(bounds), top, 1.0, 1.0)];
}

/// The share picker for what a share sends, below `rect` in `view`. Its delegate is this
/// controller, as the toolbar's picker item's is, so both list the same services.
- (void)presentShareFromView:(NSView *)view rect:(NSRect)rect {
#if !defined(GNUSTEP) || defined(ST_HAVE_LIBS_SHARING)
    NSArray *items = [self shareItemProviders];
    if (items.count == 0 || !view.window) {
        return;
    }
    NSSharingServicePicker *picker = [[NSSharingServicePicker alloc] initWithItems:items];
    picker.delegate = (id<NSSharingServicePickerDelegate>)self;
#if defined(GNUSTEP)
    [picker showRelativeToRect:rect ofView:view preferredEdge:NSMinYEdge];
#else
    // macOS 26's picker points at the view's bounds whatever rect it's given, so a click inside
    // the canvas gets a view of its own at the click to point at; it goes when the picker does.
    [self.shareAnchorView removeFromSuperview];
    self.shareAnchorView = nil;
    if (!NSEqualRects(rect, view.bounds)) {
        STShareAnchorView *anchor = [[STShareAnchorView alloc] initWithFrame:rect];
        [view addSubview:anchor];
        self.shareAnchorView = anchor;
        view = anchor;
        rect = anchor.bounds;
    }
    [picker showRelativeToRect:rect ofView:view preferredEdge:NSRectEdgeMinY];
#endif
#else
    (void)view;
    (void)rect;
#endif
}

#if defined(GNUSTEP) && defined(ST_HAVE_LIBS_SHARING)
/// What libs-sharing's sheet shares: the PNG a share sends. Exported when the sheet opens:
/// GNUstep has no NSItemProvider to export it only when a service asks.
- (NSArray *)shareItemProviders {
    NSURL *url = [self exportAnnotatedImageToTemporaryFile];
    return url ? @[url] : @[];
}

- (NSArray *)itemsForSharingServicePickerToolbarItem:(NSSharingServicePickerToolbarItem *)pickerToolbarItem {
    (void)pickerToolbarItem;
    return [self shareItemProviders];
}
#endif

#if !defined(GNUSTEP) || defined(ST_HAVE_LIBS_SHARING)
// Plain NSSharingService API, shared with GNUstep's picker where libs-sharing is built in.

/// Every share picker (the toolbar's, the right-click menu's and the selection bar's) lists the
/// custom actions after the system's services: one per choice, or one for an action without.
- (NSArray<NSSharingService *> *)sharingServicePicker:(NSSharingServicePicker *)sharingServicePicker
                              sharingServicesForItems:(NSArray *)items
                              proposedSharingServices:(NSArray<NSSharingService *> *)proposedServices {
    (void)sharingServicePicker;
    (void)items;
    NSMutableArray<NSSharingService *> *services = [proposedServices mutableCopy];
    [services addObjectsFromArray:[self customActionSharingServices]];
    return services;
}

static char STCustomActionSharingServiceKey;

/// The titles the custom actions' services have had. macOS 26 hands the picker's callbacks copies
/// of a service, without its associated objects, so a copy is known by its title (#280).
static NSMutableSet<NSString *> *STCustomActionSharingTitles(void) {
    static NSMutableSet<NSString *> *titles;
    if (!titles) {
        titles = [[NSMutableSet alloc] init];
    }
    return titles;
}

/// Whether `service` is one of the custom actions, which say how they went themselves. A custom
/// action with a system service's title ("Mail") would silence that service too.
static BOOL STIsCustomActionSharingService(NSSharingService *service) {
    return objc_getAssociatedObject(service, &STCustomActionSharingServiceKey) != nil ||
           (service.title.length > 0 && [STCustomActionSharingTitles() containsObject:service.title]);
}

/// The custom actions as share services. An action with choices offers each ("Send — host");
/// until they're listed, it's one service that runs the first, as its toolbar button does.
- (NSArray<NSSharingService *> *)customActionSharingServices {
    NSMutableArray<NSSharingService *> *services = [[NSMutableArray alloc] init];
    __weak AppDelegate *weakSelf = self;
    for (STCustomAction *action in [self loadedCustomActions]) {
        NSImage *image = [self shareImageForCustomAction:action];
        NSArray<NSString *> *choices = action.choicesCommand ? [self choicesForCustomAction:action] : nil;
        if (choices.count == 0) {
            [services addObject:[[NSSharingService alloc] initWithTitle:action.title
                                                                  image:image
                                                         alternateImage:nil
                                                                handler:^{
                [weakSelf runCustomAction:action choice:nil];
            }]];
            objc_setAssociatedObject(services.lastObject, &STCustomActionSharingServiceKey, action, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [STCustomActionSharingTitles() addObject:services.lastObject.title];
            continue;
        }
        for (NSString *choice in choices) {
            NSString *title = [NSString stringWithFormat:@"%@ — %@", action.title, choice];
            [services addObject:[[NSSharingService alloc] initWithTitle:title
                                                                  image:image
                                                         alternateImage:nil
                                                                handler:^{
                [weakSelf runCustomAction:action choice:choice];
            }]];
            objc_setAssociatedObject(services.lastObject, &STCustomActionSharingServiceKey, action, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [STCustomActionSharingTitles() addObject:services.lastObject.title];
        }
    }
    return services;
}

/// A custom action's picture in the share menus: its own icon, else a terminal symbol.
- (nullable NSImage *)shareImageForCustomAction:(STCustomAction *)action {
    NSImage *image = [self iconForCustomAction:action size:16.0];
#if !defined(GNUSTEP)
    if (!image) {
        if (@available(macOS 11.0, *)) {
            image = [NSImage imageWithSystemSymbolName:@"terminal" accessibilityDescription:action.title];
        }
    }
#endif
    return image;
}

/// A mail starts with the image's name as its subject (macOS's Mail and Outlook read it).
- (void)prepareSharingService:(NSSharingService *)service {
#if !defined(GNUSTEP)
    NSString *name = [[(self.currentImageURL ?: self.currentProjectURL) lastPathComponent] stringByDeletingPathExtension];
    // Each +sharingServiceNamed: is a new object, so it's matched by its title.
    NSString *mail = [NSSharingService sharingServiceNamed:NSSharingServiceNameComposeEmail].title;
    if (mail.length > 0 && [service.title isEqualToString:mail]) {
        service.subject = name.length > 0 ? name : @"Screenshot";
    }
#else
    (void)service;
#endif
}

#if defined(GNUSTEP)
/// Whether `service` is libs-sharing's built-in `name`; each +sharingServiceNamed: is a new object,
/// so it's matched by its title.
static BOOL STIsSharingService(NSSharingService *service, NSSharingServiceName name) {
    NSString *title = [NSSharingService sharingServiceNamed:name].title;
    return title.length > 0 && [service.title isEqualToString:title];
}

/// The rclone remote a libs-sharing upload service sends to, or nil for another service. Its tile
/// says "Link on <remote>" (libs-sharing #13), and its title is a sentence about what it does.
static NSString *STRcloneRemoteOfService(NSSharingService *service) {
    NSString *prefix = @"Link on ";
    NSString *title = service.menuItemTitle;
    return ([title hasPrefix:prefix] && title.length > prefix.length) ? [title substringFromIndex:prefix.length] : nil;
}
#endif

/// The system's services report back here; a custom action says how it went itself.
- (nullable id<NSSharingServiceDelegate>)sharingServicePicker:(NSSharingServicePicker *)sharingServicePicker
                                    delegateForSharingService:(NSSharingService *)sharingService {
    (void)sharingServicePicker;
    return STIsCustomActionSharingService(sharingService) ? nil : self;
}

// On GNUstep libs-sharing reports when a share ends (an upload, once its link is made), not when
// it starts, and a failure or Cancel as such (libs-sharing 07289ba, its #5).

/// "Shared with Mail", as Copy says "Copied".
- (void)sharingService:(NSSharingService *)sharingService didShareItems:(NSArray *)items {
    (void)items;
    // macOS 26 reports a custom action here as it starts, though its delegate is nil (#280).
    if (STIsCustomActionSharingService(sharingService)) {
        return;
    }
#if defined(GNUSTEP)
    if (STIsSharingService(sharingService, GSSharingServiceNameCopy)) {
        // What the Copy button says. The sheet's Copy writes GNUstep's pasteboard only, which
        // under Wayland is the X11 clipboard (the button mirrors to Wayland's too).
        NSString *what = [self.canvasView hasSelection] ? @"selection" : @"image";
        NSString *where = STScreenshotToolIsWaylandSession() ? @"X11 clipboard" : @"clipboard";
        [self showCopyFeedbackMessage:[NSString stringWithFormat:@"Copied %@ to %@", what, where] duration:3.0];
        return;
    }
    if (STIsSharingService(sharingService, GSSharingServiceNameSaveCopy)) {
        [self showCopyFeedbackMessage:@"Saved a copy" duration:2.5];
        return;
    }
    NSString *remote = STRcloneRemoteOfService(sharingService);
    if (remote) {
        [self showCopyFeedbackMessage:[NSString stringWithFormat:@"Uploaded to %@; link copied", remote] duration:3.0];
        return;
    }
    // These hand the image to another app, whose window is the news; libs-sharing reports them
    // when they hand off (Email before its draft opens), so "Shared with" would come too soon.
    if (STIsSharingService(sharingService, NSSharingServiceNameComposeEmail) ||
        STIsSharingService(sharingService, GSSharingServiceNameShowInFolder) ||
        STIsSharingService(sharingService, GSSharingServiceNameOpenWith)) {
        return;
    }
#endif
    NSString *name = sharingService.menuItemTitle.length > 0 ? sharingService.menuItemTitle : sharingService.title;
    [self showCopyFeedbackMessage:[NSString stringWithFormat:@"Shared with %@", name] duration:2.5];
}

/// Why a share failed; a cancelled one says nothing.
- (void)sharingService:(NSSharingService *)sharingService didFailToShareItems:(NSArray *)items error:(NSError *)error {
    (void)items;
    if (STIsCustomActionSharingService(sharingService)) {
        return;
    }
    if ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSUserCancelledError) {
        return;
    }
    NSString *name = sharingService.menuItemTitle.length > 0 ? sharingService.menuItemTitle : sharingService.title;
    NSString *reason = error.localizedDescription.length > 0 ? error.localizedDescription : @"unknown error";
#if defined(GNUSTEP)
    name = STRcloneRemoteOfService(sharingService) ?: name;
    // rclone's own words when libs-sharing has no plainer ones ("quota exceeded", not "rclone
    // couldn't do it.").
    if ([error.domain isEqualToString:GSSharingRcloneErrorDomain] && error.code == GSSharingRcloneErrorFailed &&
        error.localizedFailureReason.length > 0) {
        reason = error.localizedFailureReason;
    }
#endif
    ScreenshotToolAppendLog([NSString stringWithFormat:@"Share with %@ failed: %@", name, error]);
    [self showCopyFeedbackMessage:[NSString stringWithFormat:@"Couldn't share with %@: %@", name, reason] duration:4.0];
}
#endif

/// Writes what a share sends as a PNG named after the document, for a drag, a share or a custom
/// action: the selection when there is one, else the whole annotated image, as Copy copies.
/// Each export gets its own folder, so the file keeps the document's name.
- (nullable NSURL *)exportAnnotatedImageToTemporaryFile {
    if (![self.canvasView hasImage]) {
        return nil;
    }
    NSImage *image = [self.canvasView flattenedImageForSelection];
    NSData *pngData = image ? [self pngDataForImage:image] : nil;
    if (pngData.length == 0) {
        return nil;
    }
    NSString *name = [[(self.currentImageURL ?: self.currentProjectURL) lastPathComponent] stringByDeletingPathExtension];
    if (name.length == 0) {
        name = @"Screenshot";
    }
    NSURL *directory = [STExportDirectoryURL() URLByAppendingPathComponent:[[NSUUID UUID] UUIDString] isDirectory:YES];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Export failed: %@", error.localizedDescription]);
        return nil;
    }
    NSURL *url = [directory URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
    if (![pngData writeToURL:url options:NSDataWritingAtomic error:&error]) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Export failed: %@", error.localizedDescription]);
        return nil;
    }
    return url;
}

#pragma mark - Canvas context menu

/// The canvas's right-click menu: this window's commands, and on the image's menu the custom
/// actions, as the File menu lists them.
- (nullable NSMenu *)canvasContextMenuForKind:(STCanvasContextKind)kind {
    NSMutableArray<NSMenuItem *> *actionItems = [[NSMutableArray alloc] init];
    if (kind == STCanvasContextKindImage) {
        for (STCustomAction *action in [self loadedCustomActions]) {
            [actionItems addObject:[self menuItemForCustomAction:action]];
        }
    }
    return STCanvasContextMenu(kind, [self.canvasView hasSingleTextSelection], STCanShareImages(), self.canvasView, self,
                               actionItems);
}

#pragma mark - Custom actions (#221)

/// Where the custom actions and their state live: the application's delegate, as the menus do.
- (AppDelegate *)customActionsOwner {
#if !defined(GNUSTEP)
    return [self applicationController];
#else
    return self;
#endif
}

/// The user's custom actions, read once a launch from +[STCustomAction actionsDirectory]. Files
/// that aren't actions are skipped, and the log says why.
- (NSArray<STCustomAction *> *)loadedCustomActions {
    AppDelegate *owner = [self customActionsOwner];
    if (!owner.customActions) {
        NSMutableArray<NSString *> *problems = [[NSMutableArray alloc] init];
        NSString *directory = [STCustomAction actionsDirectory];
        owner.customActions = [STCustomAction actionsInDirectory:directory problems:problems];
        owner.customActionChoices = [[NSMutableDictionary alloc] init];
        owner.runningCustomActions = [[NSMutableSet alloc] init];
        for (NSString *problem in problems) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Custom action in %@ skipped: %@", directory, problem]);
        }
        for (STCustomAction *action in owner.customActions) {
            [self refreshChoicesForCustomAction:action];
        }
    }
    return owner.customActions;
}

- (NSArray<NSToolbarItemIdentifier> *)customActionToolbarIdentifiersInToolbarOnly:(BOOL)toolbarOnly {
    NSMutableArray<NSToolbarItemIdentifier> *identifiers = [[NSMutableArray alloc] init];
    for (STCustomAction *action in [self loadedCustomActions]) {
        if (!toolbarOnly || action.showsInToolbar) {
            [identifiers addObject:[ToolbarItemCustomActionPrefix stringByAppendingString:action.identifier]];
        }
    }
    return identifiers;
}

- (nullable STCustomAction *)customActionForToolbarIdentifier:(NSString *)identifier {
    if (![identifier hasPrefix:ToolbarItemCustomActionPrefix]) {
        return nil;
    }
    NSString *actionIdentifier = [identifier substringFromIndex:ToolbarItemCustomActionPrefix.length];
    for (STCustomAction *action in [self loadedCustomActions]) {
        if ([action.identifier isEqualToString:actionIdentifier]) {
            return action;
        }
    }
    return nil;
}

/// The action a menu item, toolbar item or control runs.
- (nullable STCustomAction *)customActionForSender:(id)sender {
    id payload = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
    if ([payload isKindOfClass:[NSDictionary class]]) {
        payload = payload[@"action"];
    }
    if ([payload isKindOfClass:[STCustomAction class]]) {
        return payload;
    }
    if ([sender isKindOfClass:[NSToolbarItem class]]) {
        return [self customActionForToolbarIdentifier:[(NSToolbarItem *)sender itemIdentifier]];
    }
    return sender ? [[self customActionsOwner].customActionsBySender objectForKey:sender] : nil;
}

- (BOOL)isRunningCustomAction:(STCustomAction *)action {
    return [[self customActionsOwner].runningCustomActions containsObject:action.identifier];
}

/// Runs the action's "choices" command in the background and keeps its lines.
- (void)refreshChoicesForCustomAction:(STCustomAction *)action {
    if (!action.choicesCommand) {
        return;
    }
    AppDelegate *owner = [self customActionsOwner];
    NSArray<NSString *> *arguments = [action.choicesCommand copy];
    arguments = [@[[arguments[0] stringByExpandingTildeInPath]] arrayByAddingObjectsFromArray:
                 [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)]];
    [STCustomActionRunner runArguments:arguments timeout:15.0 completion:^(STCustomActionResult *result) {
        if (!result.succeeded) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Custom action %@: listing choices failed: %@",
                                     action.identifier, result.failureSummary]);
            return;
        }
        NSMutableArray<NSString *> *choices = [[NSMutableArray alloc] init];
        for (NSString *line in [result.standardOutput componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            NSString *choice = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (choice.length > 0) {
                [choices addObject:choice];
            }
        }
        owner.customActionChoices[action.identifier] = choices;
    }];
}

- (nullable NSArray<NSString *> *)choicesForCustomAction:(STCustomAction *)action {
    return [self customActionsOwner].customActionChoices[action.identifier];
}

/// A menu of the action's choices, the first (the one its button runs) marked; "Loading…" until
/// they're listed. It lists them again for next time.
- (NSMenu *)choicesMenuForCustomAction:(STCustomAction *)action {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:action.title];
    [self fillChoicesMenu:menu forCustomAction:action];
    return menu;
}

- (void)fillChoicesMenu:(NSMenu *)menu forCustomAction:(STCustomAction *)action {
    // On GNUstep, adding items updates the menu, which asks its delegate to fill it again.
    static NSHashTable<NSMenu *> *filling = nil;
    if (!filling) {
        filling = [NSHashTable weakObjectsHashTable];
    }
    if ([filling containsObject:menu]) {
        return;
    }
    [filling addObject:menu];
    [self fillChoicesMenuNow:menu forCustomAction:action];
    [filling removeObject:menu];
}

- (void)fillChoicesMenuNow:(NSMenu *)menu forCustomAction:(STCustomAction *)action {
    [menu removeAllItems];
    NSArray<NSString *> *choices = [self choicesForCustomAction:action];
    if (!choices) {
        NSMenuItem *loading = (NSMenuItem *)[menu addItemWithTitle:@"Loading…" action:NULL keyEquivalent:@""];
        loading.enabled = NO;
    } else if (choices.count == 0) {
        NSMenuItem *none = (NSMenuItem *)[menu addItemWithTitle:@"Nothing to Choose" action:NULL keyEquivalent:@""];
        none.enabled = NO;
    }
    id target = self;
#if !defined(GNUSTEP)
    target = [self customActionsOwner].documentRouter ?: self;
#endif
    for (NSString *choice in choices) {
        NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:choice action:@selector(runCustomAction:) keyEquivalent:@""];
        item.target = target;
        item.representedObject = @{ @"action": action, @"choice": choice };
        if (choice == choices.firstObject) {
            item.state = NSControlStateValueOn;
        }
    }
    [self refreshChoicesForCustomAction:action];
}

- (NSMenuItem *)menuItemForCustomAction:(STCustomAction *)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:action.title action:@selector(runCustomAction:) keyEquivalent:@""];
    item.target = self;
    item.representedObject = action;
    if (action.choicesCommand) {
        // A submenu of its choices, listed fresh each time it opens.
        item.action = NULL;
        NSMenu *submenu = [[NSMenu alloc] initWithTitle:action.title];
        STCustomActionMenuDelegate *delegate = [[STCustomActionMenuDelegate alloc] init];
        delegate.action = action;
        delegate.controller = self;
        [self setCustomActionMenuDelegate:delegate forMenu:submenu];
        [self fillChoicesMenu:submenu forCustomAction:action];
        item.submenu = submenu;
    }
    return item;
}

/// A menu doesn't keep its delegate (GNUstep's doesn't even zero it when it goes), so the menu
/// keeps this one for as long as it lives.
- (void)setCustomActionMenuDelegate:(STCustomActionMenuDelegate *)delegate forMenu:(NSMenu *)menu {
    static char STCustomActionMenuDelegateKey;
    objc_setAssociatedObject(menu, &STCustomActionMenuDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    menu.delegate = (id)delegate;
}

- (NSToolbarItem *)toolbarItemForCustomAction:(STCustomAction *)action {
    NSToolbarItemIdentifier identifier = [ToolbarItemCustomActionPrefix stringByAppendingString:action.identifier];
    AppDelegate *owner = [self customActionsOwner];
    if (!owner.customActionsBySender) {
        owner.customActionsBySender = [NSMapTable strongToStrongObjectsMapTable];
    }
#if defined(GNUSTEP)
    // A button with its name, as Save and Copy are; with choices, a split button whose arrow
    // lists them.
    NSButton *button = nil;
    if (action.choicesCommand) {
        STSplitButton *split = [[STSplitButton alloc] initWithFrame:NSMakeRect(0, 0, 64.0f, STToolbarZoomControlHeight)];
        __weak AppDelegate *weakSelf = self;
        split.menuProvider = ^NSMenu *{
            return [weakSelf choicesMenuForCustomAction:action];
        };
        button = split;
    } else {
        button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 64.0f, STToolbarZoomControlHeight)];
    }
    [button setBezelStyle:NSRoundedBezelStyle];
    button.target = self;
    button.action = @selector(runCustomAction:);
    button.toolTip = [self toolTipForCustomAction:action];
    STApplyAccessibilityLabel(button, action.title);
    CGFloat arrow = [button isKindOfClass:[STSplitButton class]] ? NSWidth([(STSplitButton *)button arrowRect]) : 0.0f;
    NSImage *icon = [self iconForCustomAction:action size:20.0f];
#if !defined(_WIN32)
    BOOL iconOnly = (icon != nil);
#else
    BOOL iconOnly = NO; // Labelled, as a WinUI command bar's commands are (#224).
#endif
    NSSize size;
    if (iconOnly) {
        // Under GNOME's header bar, an icon as the others are, so the title keeps its room.
        button.title = @"";
        button.image = icon;
        button.imagePosition = NSImageOnly;
        size = NSMakeSize(34.0f + arrow, STToolbarZoomControlHeight);
    } else {
        button.title = action.title;
        [button sizeToFit];
        size = NSMakeSize(MAX(64.0f, ceil(NSWidth(button.frame)) + 20.0f + arrow), STToolbarZoomControlHeight);
    }
    [button setFrameSize:size];
    [owner.customActionsBySender setObject:action forKey:button];

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = @"";
    item.paletteLabel = action.title;
    item.toolTip = button.toolTip;
    item.target = self;
    item.action = @selector(runCustomAction:);
    item.view = button;
    if (iconOnly) {
        // GNUstep 0.32's toolbar gives a custom view the item's image when it lays it out
        // (libs-gui#952): the item has the same one, so the icon stays.
        item.image = icon;
    }
    button.enabled = [self.canvasView hasImage];
    item.minSize = size;
    item.maxSize = size;
    return item;
#else
    NSToolbarItem *item = nil;
    if (action.choicesCommand) {
        // Its button runs the first choice; its menu lists them all.
        NSMenuToolbarItem *menuItem = [[NSMenuToolbarItem alloc] initWithItemIdentifier:identifier];
        STCustomActionMenuDelegate *delegate = [[STCustomActionMenuDelegate alloc] init];
        delegate.action = action;
        delegate.controller = self;
        NSMenu *menu = [self choicesMenuForCustomAction:action];
        [self setCustomActionMenuDelegate:delegate forMenu:menu];
        menuItem.menu = menu;
        menuItem.showsIndicator = YES;
        item = menuItem;
    } else {
        item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    }
    item.label = action.title;
    item.paletteLabel = action.title;
    item.toolTip = [self toolTipForCustomAction:action];
    item.image = [self iconForCustomAction:action size:18.0f]
        ?: [NSImage imageWithSystemSymbolName:@"paperplane" accessibilityDescription:action.title];
    item.target = self;
    item.action = @selector(runCustomAction:);
    return item;
#endif
}

/// The action's "icon", `size` points square, or nil.
- (nullable NSImage *)iconForCustomAction:(STCustomAction *)action size:(CGFloat)size {
    if (action.iconPath.length == 0) {
        return nil;
    }
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:action.iconPath];
    if (!image || image.size.width <= 0.0 || image.size.height <= 0.0) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Custom action %@: icon %@ can't be read", action.identifier, action.iconPath]);
        return nil;
    }
    [image setSize:NSMakeSize(size, size)];
    return image;
}

- (NSString *)toolTipForCustomAction:(STCustomAction *)action {
    if (action.choicesCommand) {
        return [NSString stringWithFormat:@"%@ (the arrow chooses where)", action.title];
    }
    return action.title;
}

/// Runs the custom action the sender stands for, with the choice it carries, if any.
- (void)runCustomAction:(id)sender {
    id payload = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
    NSString *choice = [payload isKindOfClass:[NSDictionary class]] ? payload[@"choice"] : nil;
    [self runCustomAction:[self customActionForSender:sender] choice:choice];
}

/// Saves the annotated image (the selection, if there is one) as a PNG in a folder of its own,
/// runs the action's command on it, and, by the action's "output", copies what it prints. With
/// no choice, it takes the first.
- (void)runCustomAction:(nullable STCustomAction *)action choice:(nullable NSString *)choice {
    if (!action || ![self.canvasView hasImage]) {
        return;
    }
    AppDelegate *owner = [self customActionsOwner];
    if ([self isRunningCustomAction:action]) {
        [self showCopyFeedbackMessage:[NSString stringWithFormat:@"%@ is still running", action.title] duration:2.0];
        return;
    }
    if (choice.length == 0 && action.choicesCommand) {
        choice = [self choicesForCustomAction:action].firstObject;
        if (choice.length == 0) {
            [self refreshChoicesForCustomAction:action];
            [self showCopyFeedbackMessage:[NSString stringWithFormat:@"%@: its choices aren't listed yet", action.title] duration:2.5];
            return;
        }
    }

    // What every share sends: the selection when there is one, as Copy copies.
    NSImage *flattened = [self.canvasView flattenedImageForSelection];
    NSData *png = flattened ? [self pngDataForImage:flattened] : nil;
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"screenshottool-%@", [[NSProcessInfo processInfo] globallyUniqueString]]];
    NSString *stem = [[self.currentImageURL lastPathComponent] stringByDeletingPathExtension];
    NSString *file = [folder stringByAppendingPathComponent:[(stem.length > 0 ? stem : @"Screenshot") stringByAppendingPathExtension:@"png"]];
#if defined(_WIN32)
    // The command gets a Windows path: many tools, cmd's own commands among them, take no "/".
    NSString *commandFile = [file stringByReplacingOccurrencesOfString:@"/" withString:@"\\"];
#else
    NSString *commandFile = file;
#endif
    if (!png || ![[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL] ||
        ![png writeToFile:file atomically:YES]) {
        [self showCopyFeedbackMessage:[NSString stringWithFormat:@"%@ failed: the image couldn't be saved", action.title] duration:3.0];
        [[NSFileManager defaultManager] removeItemAtPath:folder error:NULL];
        return;
    }
    NSString *problem = nil;
    NSArray<NSString *> *arguments = [action argumentsForFile:commandFile choice:choice problem:&problem];
    if (!arguments) {
        [[NSFileManager defaultManager] removeItemAtPath:folder error:NULL];
        [self reportCustomAction:action failure:problem details:nil];
        return;
    }

    [owner.runningCustomActions addObject:action.identifier];
    [self refreshToolButtonIcons];
    NSString *running = choice.length > 0 ? [NSString stringWithFormat:@"%@ (%@)…", action.title, choice]
                                          : [NSString stringWithFormat:@"%@…", action.title];
    [self showCopyFeedbackMessage:running duration:MIN(action.timeout, 30.0)];
    ScreenshotToolAppendLog([NSString stringWithFormat:@"Custom action %@: running %@", action.identifier,
                             [arguments componentsJoinedByString:@" "]]);

    __weak AppDelegate *weakSelf = self;
    [STCustomActionRunner runArguments:arguments timeout:action.timeout completion:^(STCustomActionResult *result) {
        [owner.runningCustomActions removeObject:action.identifier];
        [[NSFileManager defaultManager] removeItemAtPath:folder error:NULL];
        AppDelegate *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf refreshToolButtonIcons];
        if (!result.succeeded) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Custom action %@ failed (status %d%@): %@",
                                     action.identifier, result.status, result.timedOut ? @", timed out" : @"",
                                     result.standardError]);
            [strongSelf reportCustomAction:action failure:result.failureSummary details:result.standardError];
            return;
        }
        if (action.output == STCustomActionOutputClipboard) {
            NSString *text = [result.standardOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (text.length == 0) {
                [strongSelf showCopyFeedbackMessage:[NSString stringWithFormat:@"%@: done, nothing to copy", action.title] duration:2.5];
                return;
            }
            [strongSelf copyCustomActionText:text];
            NSString *shown = text.length > 60 ? [[text substringToIndex:59] stringByAppendingString:@"…"] : text;
            [strongSelf showCopyFeedbackMessage:[NSString stringWithFormat:@"Copied %@", shown] duration:3.0];
        } else {
            [strongSelf showCopyFeedbackMessage:[NSString stringWithFormat:@"%@: done", action.title] duration:2.0];
        }
    }];
}

- (void)copyCustomActionText:(NSString *)text {
    if ([self usesWindowsClipboard]) {
        // Straight to the Windows clipboard, as Copy's image is: through GNUstep's pasteboard
        // server the text never reached it (ScreenshotTool Windows's check of #234).
        STWindowsClipboardWriteText(text);
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
#if defined(GNUSTEP)
    [pasteboard declareTypes:@[NSStringPboardType] owner:nil];
    [pasteboard setString:text forType:NSStringPboardType];
#else
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
#endif
}

- (void)reportCustomAction:(STCustomAction *)action failure:(NSString *)summary details:(nullable NSString *)details {
    [self showCopyFeedbackMessage:[NSString stringWithFormat:@"%@ failed", action.title] duration:2.0];
    // The alert opens on a turn of the run loop of its own, not inside the completion.
    NSDictionary *report = @{ @"title": action.title ?: @"", @"summary": summary ?: @"", @"details": details ?: @"" };
    [self performSelector:@selector(showCustomActionFailure:) withObject:report afterDelay:0.0];
}

- (void)showCustomActionFailure:(NSDictionary *)report {
    NSString *summary = report[@"summary"];
    NSString *details = report[@"details"];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"%@ Failed", report[@"title"]];
    NSString *trimmed = [details stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length > 1200) {
        trimmed = [@"…" stringByAppendingString:[trimmed substringFromIndex:trimmed.length - 1200]];
    }
    alert.informativeText = (trimmed.length > 0 && ![trimmed hasSuffix:summary ?: @""])
        ? [NSString stringWithFormat:@"%@\n\n%@", summary ?: @"", trimmed]
        : (summary ?: @"");
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
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

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
    (void)window;
    return self.undoManager;
}

/// While a text box is open, Undo/Redo act on its typing; otherwise on the canvas (#28).
- (NSUndoManager *)activeUndoManager {
    return [self.canvasView activeTextUndoManager] ?: self.undoManager;
}

- (void)undoStateDidChange:(NSNotification *)notification {
#if !defined(GNUSTEP)
    // Only this window's: the canvas's, or its text box's. With several windows, every other
    // undo manager's checkpoints would keep each one revalidating, and a closed one alive.
    id manager = notification.object;
    if (manager != self.undoManager && manager != [self.canvasView activeTextUndoManager]) {
        return;
    }
#else
    (void)notification;
#endif
    // -canRedo posts a checkpoint: validating mustn't schedule another validation, or the app
    // never idles and redraws the toolbar on every turn of the run loop.
    if (self.validatingUndoToolbarItems) {
        return;
    }
    // Once per turn of the run loop, after the group being closed has closed: checkpoints are frequent.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(validateUndoToolbarItems) object:nil];
    [self performSelector:@selector(validateUndoToolbarItems) withObject:nil afterDelay:0.0];
}

- (void)validateUndoToolbarItems {
    self.validatingUndoToolbarItems = YES;
    [self.toolbar validateVisibleItems];
    [self updateDocumentEditedState];
    self.validatingUndoToolbarItems = NO;
}

/// macOS marks a window with unsaved changes with a dot in its close button.
- (void)updateDocumentEditedState {
#if !defined(GNUSTEP)
    [self.window setDocumentEdited:[self hasUnsavedChanges]];
#endif
}

- (void)undo:(id)sender {
    (void)sender;
    NSUndoManager *undo = [self activeUndoManager];
    if ([undo canUndo]) {
        [undo undo];
    }
}

- (void)redo:(id)sender {
    (void)sender;
    NSUndoManager *undo = [self activeUndoManager];
    if ([undo canRedo]) {
        [undo redo];
    }
}

#pragma mark - Cleanup

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - NSWindowDelegate

- (BOOL)windowShouldClose:(id)sender {
    (void)sender;
    BOOL proceed = [self confirmProceedingWithUnsavedChanges];
    self.closeSettledAnnotationFingerprint = proceed ? [self.canvasView annotationFingerprint] : nil;
    return proceed;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
#if !defined(GNUSTEP)
    // Every open document window, minimized ones too (closed ones have left the list).
    for (AppDelegate *document in [self.documentWindows copy]) {
        if ([document hasUnsavedChanges]) {
            [document.window makeKeyAndOrderFront:nil];
            if (![document confirmProceedingWithUnsavedChanges]) {
                return NSTerminateCancel;
            }
        }
    }
#endif
    // GNUstep quits when the last window closes under some menu styles (in-window menus); the
    // close has just asked, so don't ask again about the same annotations.
    NSData *settled = self.closeSettledAnnotationFingerprint;
    if (settled && [settled isEqualToData:[self.canvasView annotationFingerprint]]) {
        return NSTerminateNow;
    }
    return [self confirmProceedingWithUnsavedChanges] ? NSTerminateNow : NSTerminateCancel;
}

#pragma mark - Unsaved changes (#32)

- (BOOL)hasUnsavedChanges {
    if (![self.canvasView hasImage]) {
        return NO;
    }
    NSData *current = [self.canvasView annotationFingerprint];
    return self.savedAnnotationFingerprint ? ![current isEqualToData:self.savedAnnotationFingerprint] : NO;
}

- (void)markAnnotationsSaved {
    self.savedAnnotationFingerprint = [self.canvasView annotationFingerprint];
    [self updateDocumentEditedState];
}

/// Save… / Don't Save / Cancel. Separate so tests can answer without a modal alert.
- (STUnsavedChangesChoice)askAboutUnsavedChanges {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Save your annotations?";
    alert.informativeText = @"Your changes will be lost if you don't save them. To keep annotations editable, choose Save Project… in the File menu; Save… flattens them into an image.";
    [alert addButtonWithTitle:@"Save…"];
    [alert addButtonWithTitle:@"Don't Save"];
    [alert addButtonWithTitle:@"Cancel"];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        return STUnsavedChangesChoiceSave;
    }
    if (response == NSAlertSecondButtonReturn) {
        return STUnsavedChangesChoiceDiscard;
    }
    return STUnsavedChangesChoiceCancel;
}

/// YES when it's fine to replace or close the current image: nothing unsaved, the user saved, or
/// chose not to.
- (BOOL)confirmProceedingWithUnsavedChanges {
    if (![self hasUnsavedChanges]) {
        return YES;
    }
    switch ([self askAboutUnsavedChanges]) {
        case STUnsavedChangesChoiceSave:
            return self.currentProjectURL ? [self writeProjectToURL:self.currentProjectURL] : [self saveImageWithPanel];
        case STUnsavedChangesChoiceDiscard:
            return YES;
        case STUnsavedChangesChoiceCancel:
        default:
            return NO;
    }
}

#pragma mark - Projects (#32)

- (void)saveProject:(id)sender {
    (void)sender;
    [self saveProjectWithPanel];
}

- (BOOL)saveProjectWithPanel {
    if (![self.canvasView hasImage]) {
        return NO;
    }
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes:@[STProjectFileExtension]];
    [panel setCanCreateDirectories:YES];
    NSURL *nameSource = self.currentProjectURL ?: self.currentImageURL;
    if (nameSource) {
        [panel setDirectoryURL:nameSource.URLByDeletingLastPathComponent];
        NSString *base = [nameSource.lastPathComponent stringByDeletingPathExtension];
        [panel setNameFieldStringValue:[base stringByAppendingPathExtension:STProjectFileExtension]];
    } else {
        if (self.defaultSaveDirectory.length > 0) {
            [panel setDirectoryURL:[NSURL fileURLWithPath:self.defaultSaveDirectory]];
        }
        [panel setNameFieldStringValue:[STPastedImageTitle stringByAppendingPathExtension:STProjectFileExtension]];
    }
    if ([panel runModal] != NSModalResponseOK || !panel.URL) {
        return NO;
    }
    NSURL *destination = panel.URL;
    if (!STURLIsProject(destination)) {
        destination = [destination URLByAppendingPathExtension:STProjectFileExtension];
    }
    return [self writeProjectToURL:destination];
}

- (BOOL)writeProjectToURL:(NSURL *)url {
    NSError *error = nil;
    NSData *data = [self.canvasView projectDataWithError:&error];
    [self ensureDirectoryExistsAtPath:[url.path stringByDeletingLastPathComponent]];
    if (!data || !STWriteDataAtomically(data, url, &error)) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Unable to Save Project";
        alert.informativeText = error.localizedDescription ?: @"An unknown error occurred.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return NO;
    }
    self.currentProjectURL = url;
    [self addRecentDocumentURL:url];
    [self.window setTitleWithRepresentedFilename:url.path];
    [self markAnnotationsSaved];
    return YES;
}

- (BOOL)openProjectAtURL:(NSURL *)url {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (![self.canvasView loadProjectData:data error:&error]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Unable to Open Project";
        alert.informativeText = error.localizedDescription ?: url.path;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return NO;
    }
    self.currentImageURL = nil;
    self.currentProjectURL = url;
    [self addRecentDocumentURL:url];
    [self.window setTitleWithRepresentedFilename:url.path];
    [self resizeWindowToImageSize:self.canvasView.image.size];
    [self.canvasView updateForEnclosingBoundsChange];
    [self reflectZoomSelection];
    [self refreshToolButtonIcons];
    [self markAnnotationsSaved];
    return YES;
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    if (notification.object == self.window) {
        [self refreshPasteAvailability];
        [self giveCanvasTheKeyboardUnlessEditing];
    }
}

/// Tool shortcuts are the canvas's, so it takes the keyboard back from the window or a toolbar
/// control (after a popover closes, say), but never from text being edited (#80).
- (void)giveCanvasTheKeyboardUnlessEditing {
    NSResponder *responder = self.window.firstResponder;
    if (responder == self.canvasView || [responder isKindOfClass:[NSText class]] || ![self.canvasView hasImage]) {
        return;
    }
    [self.window makeFirstResponder:self.canvasView];
}

- (void)windowDidResize:(NSNotification *)notification {
    [self logWindowFrame:@"resized"];
    [self layoutContentSubviews];
    [self.canvasView updateForEnclosingBoundsChange];
}

@end
