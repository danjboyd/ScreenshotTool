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
#import "STHudView.h"
#import "STTextOptionsBar.h"
#import "GPStandardUpdaterController.h"
#if defined(ST_USE_OPENSAVE)
#import <GSOpenSave.h>
#endif
#import <Foundation/NSTask.h>
#if defined(GNUSTEP)
#import <AppKit/NSSegmentedCell.h>
#import <GNUstepGUI/GSTheme.h>
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
/// Select, Highlighter, Pen, Arrow, Text, Eraser.
static const NSInteger STToolbarToolSegmentCount = 6;
static NSString * const ToolbarItemEraser = @"com.screenshottool.toolbar.eraser";
static NSString * const ToolbarItemText = @"com.screenshottool.toolbar.text";
static NSString * const ToolbarItemSelect = @"com.screenshottool.toolbar.select";
static NSString * const ToolbarItemTools = @"com.screenshottool.toolbar.tools";
static NSString * const ToolbarItemZoom = @"com.screenshottool.toolbar.zoom";
static NSString * const ToolbarItemCopy = @"com.screenshottool.toolbar.copy";
static NSString * const ToolbarItemPreferences = @"com.screenshottool.toolbar.preferences";
static NSString * const ToolbarItemColor = @"com.screenshottool.toolbar.color";
static const CGFloat StatusBarHeight = 24.0f;
// Smallest canvas area a window gets, so tiny images still leave room for the title and the
// whole icon-only toolbar (it overflows below about 556pt with the Adwaita theme).
static const CGFloat STMinimumCanvasWidth = 576.0f;
static const CGFloat STMinimumCanvasHeight = 240.0f;
static const CGFloat STHudCornerRadius = 10.0f;
static const CGFloat STHudHorizontalPadding = 20.0f;
static const CGFloat STHudVerticalPadding = 12.0f;
static const CGFloat STHudMaxWidth = 360.0f;
static const NSTimeInterval STHudFadeInDuration = 0.12;
static const NSTimeInterval STHudFadeOutDuration = 0.20;
static const CGFloat ToolbarIconDimension = 32.0f;
static const NSUInteger STRecentDocumentLimit = 10;
static NSString * const STRecentDocumentsEmptyTitle = @"No Recent Documents";
static NSString * const STRecentDocumentsClearTitle = @"Clear Menu";
#if defined(GNUSTEP)
static const CGFloat STToolbarToolSegmentWidth = 46.0f;
static const CGFloat STToolbarToolControlHeight = 32.0f;
static const CGFloat STToolbarToolIconSize = 22.0f;
static const CGFloat STToolbarColorControlWidth = 40.0f;
static const CGFloat STToolbarColorControlHeight = 32.0f;
static const CGFloat STToolbarZoomControlHeight = 32.0f;
static const CGFloat STToolbarZoomFontSize = 18.0f;
static const CGFloat STToolbarZoomChevronWidth = 9.0f;
static const CGFloat STToolbarZoomChevronSpacing = 8.0f;
static const CGFloat STToolbarZoomHorizontalPadding = 12.0f;
#endif
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

static NSArray<NSString *> *STOpenableImageFileTypes(void) {
    NSArray<NSString *> *fileTypes = [NSImage imageFileTypes];
    if (fileTypes.count > 0) {
        return fileTypes;
    }
    return @[ @"png", @"jpg", @"jpeg", @"gif", @"bmp", @"tif", @"tiff", @"webp" ];
}

/// Read by the Adwaita theme: YES puts the window's toolbar in its header bar.
static NSString * const STGnomeThemeHeaderBarToolbarKey = @"GnomeThemeHeaderBarToolbar";

static BOOL STAdwaitaThemeIsActive(void) {
#if defined(GNUSTEP)
    NSString *name = [[GSTheme theme] name];
    return name != nil && [name caseInsensitiveCompare:@"Adwaita"] == NSOrderedSame;
#else
    return NO;
#endif
}

/// Whether windows get the Adwaita theme's header bar: it draws the title bar itself (the user
/// set GSX11HandlesWindowDecorations NO, or the theme's own defaults did).
static BOOL STAdwaitaHeaderBarIsActive(void) {
#if defined(GNUSTEP)
    if (!STAdwaitaThemeIsActive()) {
        return NO;
    }
    Class headerBar = NSClassFromString(@"GnomeThemeHeaderBarDecorationView");
    id decorator = [[GSTheme theme] windowDecorator];
    return headerBar != Nil && [decorator respondsToSelector:@selector(isSubclassOfClass:)] &&
           [(Class)decorator isSubclassOfClass:headerBar];
#else
    return NO;
#endif
}

/// The value the theme will use: the user's default, else the app's Info.plist, else NO.
static BOOL STToolbarInTitleBarEnabled(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:STGnomeThemeHeaderBarToolbarKey] != nil) {
        return [defaults boolForKey:STGnomeThemeHeaderBarToolbarKey];
    }
    id declared = [[NSBundle mainBundle] infoDictionary][STGnomeThemeHeaderBarToolbarKey];
    return [declared respondsToSelector:@selector(boolValue)] && [declared boolValue];
}

static NSString * const STProjectFileExtension = @"screenshottool";

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

#if defined(GNUSTEP)
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
#endif

#if !defined(GNUSTEP)
static NSImage *STRasterizeImage(NSSize size, void (^drawingBlock)(NSRect bounds)) {
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
    NSRect bounds = NSMakeRect(0.0f, 0.0f, width, height);
    [[NSColor clearColor] setFill];
    NSRectFill(bounds);
    if (drawingBlock) {
        drawingBlock(bounds);
    }
    [NSGraphicsContext setCurrentContext:previousContext];

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [image addRepresentation:bitmap];
    return image;
}
#endif

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
#else
static NSBitmapImageRep *STBitmapRepresentationFromImage(NSImage *image) {
    if (!image) {
        return nil;
    }
    NSData *tiffData = [image TIFFRepresentation];
    if (!tiffData) {
        return nil;
    }
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiffData];
    if (bitmap) {
        [bitmap setSize:image.size];
    }
    return bitmap;
}
#endif

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

#if defined(GNUSTEP)
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
        NSRect border = NSMakeRect(dirtyRect.origin.x,
                                   dirtyRect.size.height - 1.0f,
                                   dirtyRect.size.width,
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



#endif
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

static NSData *STWaylandClipboardDataForMIMEType(NSString *mimeType) {
    if (mimeType.length == 0 || !STScreenshotToolIsWaylandSession()) {
        return nil;
    }

    NSString *wlPastePath = STExecutablePathInPATH(@"wl-paste");
    if (wlPastePath.length == 0) {
        return nil;
    }

    @try {
        NSTask *task = [[NSTask alloc] init];
        NSPipe *outputPipe = [NSPipe pipe];
        NSPipe *errorPipe = [NSPipe pipe];
        task.launchPath = wlPastePath;
        task.arguments = @[ @"--type", mimeType ];
        task.standardOutput = outputPipe;
        task.standardError = errorPipe;
        [task launch];

        NSData *stdoutData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
        NSData *stderrData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];

        if (task.terminationStatus == 0 && stdoutData.length > 0) {
            return stdoutData;
        }

        NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
        if (stderrText.length > 0) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Wayland clipboard read failed for %@ (status=%d): %@",
                                     mimeType,
                                     task.terminationStatus,
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

#if defined(ST_USE_OPENSAVE)
static void STConfigureOpenSaveModeFromEnvironment(void) {
    NSString *rawMode = [[NSProcessInfo processInfo] environment][@"SCREENSHOT_TOOL_OPENSAVE_MODE"];
    NSString *mode = [rawMode lowercaseString];
    if (mode.length == 0 || [mode isEqualToString:@"gtk"]) {
        GSOpenSaveSetMode(GSOpenSaveModeGtk);
        ScreenshotToolAppendLog(@"OpenSave mode: GTK");
        return;
    }
    if ([mode isEqualToString:@"gnustep"] || [mode isEqualToString:@"gnu"]) {
        GSOpenSaveSetMode(GSOpenSaveModeGNUstep);
        ScreenshotToolAppendLog(@"OpenSave mode: GNUstep");
        return;
    }
    GSOpenSaveSetMode(GSOpenSaveModeGtk);
    ScreenshotToolAppendLog([NSString stringWithFormat:@"OpenSave mode: unknown value \"%@\"; defaulting to GTK",
                             rawMode ?: @"<nil>"]);
}
#endif

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
    }
    return @"Unknown";
}

static BOOL STToolUsesColor(ScreenshotCanvasTool tool) {
    return (tool == ScreenshotCanvasToolPen ||
            tool == ScreenshotCanvasToolHighlighter ||
            tool == ScreenshotCanvasToolText ||
            tool == ScreenshotCanvasToolArrow);
}

/// Arrows draw with the pen's colour and width, so their settings are the pen's (#33).
static ScreenshotCanvasTool STSettingsToolForTool(ScreenshotCanvasTool tool) {
    return (tool == ScreenshotCanvasToolArrow) ? ScreenshotCanvasToolPen : tool;
}

static NSString *STDebugDescriptionForEvent(NSEvent *event) {
    if (!event) {
        return @"<no NSEvent>";
    }
    NSEventType type = event.type;
    NSInteger clickCount = event.clickCount;
    NSInteger buttonNumber = event.buttonNumber;
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



@interface STStatusTextField : NSTextField
@end

@implementation STStatusTextField

- (NSUndoManager *)undoManager {
    return nil;
}

@end

@interface AppDelegate () <NSToolbarDelegate, ToolSettingsPopoverControllerDelegate, TextToolPopoverControllerDelegate, ZoomPopoverControllerDelegate, PreferencesWindowControllerDelegate, GPStandardUpdaterControllerDelegate, STTextOptionsBarDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) ScreenshotCanvasView *canvasView;
@property (nonatomic, strong) NSToolbar *toolbar;
@property (nonatomic, strong) NSMutableDictionary<NSToolbarItemIdentifier, NSToolbarItem *> *toolbarItemsByIdentifier;
#if defined(GNUSTEP)
@property (nonatomic, strong) STToolbarSegmentedControl *toolbarToolSegmentedControl;
@property (nonatomic, strong) STToolbarColorWellView *toolbarColorWellView;
@property (nonatomic, strong) STToolbarZoomButtonView *zoomToolbarButtonView;
#endif
@property (nonatomic, strong) NSPopUpButton *zoomPopUpButton;
@property (nonatomic, strong) NSView *zoomToolbarContainer;
@property (nonatomic, strong) NSTextField *zoomToolbarLabel;
@property (nonatomic, strong) NSView *statusBarView;
@property (nonatomic, strong) NSTextField *statusTextField;
@property (nonatomic, strong) NSTimer *statusClearTimer;
@property (nonatomic, strong) NSView *statusControlsContainer;
@property (nonatomic, strong) NSWindow *hudWindow;
@property (nonatomic, strong) STHudView *hudView;
@property (nonatomic, strong) NSTimer *hudDismissTimer;
@property (nonatomic, strong) NSTimer *hudFadeTimer;
@property (nonatomic, copy) void (^hudFadeCompletion)(void);
@property (nonatomic, assign) NSTimeInterval hudFadeStartTime;
@property (nonatomic, assign) NSTimeInterval hudFadeDuration;
@property (nonatomic, assign) CGFloat hudFadeStartAlpha;
@property (nonatomic, assign) CGFloat hudFadeTargetAlpha;
@property (nonatomic, strong) NSTextField *toolWidthTitleLabel;
@property (nonatomic, strong) NSSlider *toolWidthSlider;
@property (nonatomic, strong) NSTextField *toolWidthValueLabel;
@property (nonatomic, strong) NSButton *toolWidthOptionsButton;
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
@property (nonatomic, strong) ToolSettingsPopoverController *penPopoverController;
@property (nonatomic, strong) ToolSettingsPopoverController *highlighterPopoverController;
@property (nonatomic, strong) TextToolPopoverController *textPopoverController;
@property (nonatomic, strong) ZoomPopoverController *zoomPopoverController;
@property (nonatomic, strong) PreferencesWindowController *preferencesWindowController;
@property (nonatomic, assign) ScreenshotCanvasTool lastWidthTool;
@property (nonatomic, copy) NSString *defaultSaveDirectory;
@property (nonatomic, assign) BOOL statusBarVisiblePreference;
@property (nonatomic, copy) NSString *pendingOpenPath;
@property (nonatomic, strong) NSURL *currentImageURL;
/// The project file this window was opened from or last saved to (#32).
@property (nonatomic, strong, nullable) NSURL *currentProjectURL;
/// The canvas's fingerprint when it was last opened or saved; a different one means unsaved changes.
@property (nonatomic, strong, nullable) NSData *savedAnnotationFingerprint;
@property (nonatomic, strong) NSMutableArray<NSString *> *recentDocumentPaths;
@property (nonatomic, strong) NSMenu *openRecentMenu;
@property (nonatomic, strong) NSUndoManager *undoManager;
@property (nonatomic, assign) BOOL usesDarkTheme;
@property (nonatomic, assign) BOOL toolWidthMenuCanReset;
@property (nonatomic, strong) GPStandardUpdaterController *updaterController;
- (NSData *)clipboardPNGDataForPasteAsNewImage;
- (NSURL *)temporaryClipboardImageURLForPNGData:(NSData *)pngData;
- (BOOL)isTemporaryClipboardImageURL:(NSURL *)url;
- (BOOL)launchNewWindowForImageAtURL:(NSURL *)url;
- (void)showTransientFeedbackMessage:(NSString *)message duration:(NSTimeInterval)duration;
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
        return @"Tools";
    }
    if ([identifier isEqualToString:ToolbarItemHighlighter]) {
        return @"Highlighter Tool — double-click to configure";
    }
    if ([identifier isEqualToString:ToolbarItemPen]) {
        return @"Pen Tool — double-click to configure";
    }
    if ([identifier isEqualToString:ToolbarItemArrow]) {
        return @"Arrow Tool — double-click to configure";
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
        return @"Copy Image";
    }
    if ([identifier isEqualToString:ToolbarItemPreferences]) {
        return @"Preferences";
    }
    if ([identifier isEqualToString:ToolbarItemColor]) {
        switch (self.canvasView.activeTool) {
            case ScreenshotCanvasToolPen:
                return @"Pen Color — click to configure";
            case ScreenshotCanvasToolHighlighter:
                return @"Highlighter Color — click to configure";
            case ScreenshotCanvasToolText:
                return @"Text Color and Font — click to configure";
            default:
                return @"Current tool has no color settings";
        }
    }
    if ([identifier isEqualToString:ToolbarItemZoom]) {
        if (![self.canvasView hasImage]) {
            return @"Zoom unavailable until an image is loaded";
        }
        NSString *value = self.canvasView.isFitToWindow ? @"Fit to Window" : [self displayStringForScale:self.canvasView.zoomScale];
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
    if (!self.openRecentMenu) {
        return;
    }

    [self ensureRecentDocumentPathsLoaded];
    [self.openRecentMenu removeAllItems];

    if (self.recentDocumentPaths.count == 0) {
        NSMenuItem *emptyItem = [[NSMenuItem alloc] initWithTitle:STRecentDocumentsEmptyTitle
                                                           action:NULL
                                                    keyEquivalent:@""];
        [emptyItem setEnabled:NO];
        [self.openRecentMenu addItem:emptyItem];
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
        [self.openRecentMenu addItem:item];
    }

    [self.openRecentMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *clearItem = [[NSMenuItem alloc] initWithTitle:STRecentDocumentsClearTitle
                                                       action:@selector(clearRecentDocuments:)
                                                keyEquivalent:@""];
    [clearItem setTarget:self];
    [self.openRecentMenu addItem:clearItem];
}

- (void)addRecentDocumentURL:(NSURL *)url {
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
    NSImage *icon = [NSImage imageNamed:@"ScreenshotToolIcon"];
    if (icon) {
        options[@"ApplicationIcon"] = icon;
    }

    if (options.count > 0) {
        [NSApp orderFrontStandardAboutPanelWithOptions:options];
    } else {
        [NSApp orderFrontStandardAboutPanel:sender];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    ScreenshotToolAppendLog(@"ScreenshotTool launched");
#if defined(ST_USE_OPENSAVE)
    STConfigureOpenSaveModeFromEnvironment();
#endif
    self.usesDarkTheme = STThemeIsDark();
#if defined(GNUSTEP)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidActivate:)
                                                 name:GSThemeDidActivateNotification
                                               object:nil];
#endif
    [self setupWindowAndContent];
    [self setupToolbar];
    self.lastWidthTool = ScreenshotCanvasToolHighlighter;
    [self loadToolSettingsFromDefaults];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self configureUpdater];

    [self selectTool:ScreenshotCanvasToolHighlighter];
    [self reflectZoomSelection];


    if (self.pendingOpenPath.length > 0) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"applicationDidFinishLaunching: attempting deferred open for %@",
                                 self.pendingOpenPath]);
        [self openImageAtURL:[NSURL fileURLWithPath:self.pendingOpenPath]];
        self.pendingOpenPath = nil;
    } else {
        NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
        ScreenshotToolAppendLog([NSString stringWithFormat:@"applicationDidFinishLaunching: argc=%lu",
                                 (unsigned long)arguments.count]);
        if (arguments.count > 1) {
            for (NSUInteger idx = 1; idx < arguments.count; idx++) {
                NSString *candidate = arguments[idx];
                ScreenshotToolAppendLog([NSString stringWithFormat:@"applicationDidFinishLaunching: CLI arg[%lu]=%@",
                                         (unsigned long)idx,
                                         candidate]);
                if ([self openImageAtURL:[NSURL fileURLWithPath:candidate]]) {
                    ScreenshotToolAppendLog([NSString stringWithFormat:@"applicationDidFinishLaunching: opened CLI arg[%lu]",
                                             (unsigned long)idx]);
                    break;
                } else {
                    ScreenshotToolAppendLog([NSString stringWithFormat:@"applicationDidFinishLaunching: failed to open CLI arg[%lu]",
                                             (unsigned long)idx]);
                }
            }
        }
    }

}

- (void)configureUpdater {
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
}

- (IBAction)checkForUpdates:(id)sender {
    if (self.updaterController == nil) {
        ScreenshotToolAppendLog(@"Manual update check requested, but updater is unavailable");
        NSBeep();
        return;
    }

    [self.updaterController checkForUpdates:sender];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    ScreenshotToolAppendLog([NSString stringWithFormat:@"application:openFile: received %@", filename ?: @"<nil>"]);
    if (!self.canvasView) {
        self.pendingOpenPath = filename;
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Canvas not ready; deferring open for %@", filename ?: @"<nil>"]);
        return YES;
    }
    if (![self confirmProceedingWithUnsavedChanges]) {
        return NO;
    }
    BOOL opened = [self openImageAtURL:[NSURL fileURLWithPath:filename]];
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
    if (action == @selector(pasteAsNewImage:)) {
        return YES;
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
        return (self.updaterController != nil);
    }
    return YES;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem {
    NSString *identifier = toolbarItem.itemIdentifier;
    if ([identifier isEqualToString:ToolbarItemCopy]) {
        return [self.canvasView hasImage];
    }
    if ([identifier isEqualToString:ToolbarItemZoom]) {
        return [self.canvasView hasImage];
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
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"GSMainMenu"];
    [NSApp setMainMenu:mainMenu];

    NSString *appName = [[NSProcessInfo processInfo] processName];
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

    NSMenuItem *checkForUpdatesItem = [[NSMenuItem alloc] initWithTitle:@"Check for Updates…"
                                                                 action:@selector(checkForUpdates:)
                                                          keyEquivalent:@""];
    [checkForUpdatesItem setTarget:self];
    [appMenu addItem:checkForUpdatesItem];

    [appMenu addItem:[NSMenuItem separatorItem]];

    NSString *quitTitle = [NSString stringWithFormat:@"Quit %@", appName];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:quitTitle
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [quitItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [appMenu addItem:quitItem];

    // File menu
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];

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
    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy"
                                                      action:@selector(copy:)
                                               keyEquivalent:@"c"];
    [copyItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [copyItem setTarget:self];
    [editMenu addItem:copyItem];

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

    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    [editMenuItem setSubmenu:editMenu];
    [mainMenu addItem:editMenuItem];

    // View menu
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];

    NSMenuItem *fitToWindowItem = [[NSMenuItem alloc] initWithTitle:@"Fit to Window"
                                                            action:@selector(zoomFitToWindow:)
                                                     keyEquivalent:@""];
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
                                                  keyEquivalent:@""];
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

    NSMenuItem *viewMenuItem = [[NSMenuItem alloc] initWithTitle:@"View" action:NULL keyEquivalent:@""];
    [viewMenuItem setSubmenu:viewMenu];
    [mainMenu addItem:viewMenuItem];

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
    [self.window setAcceptsMouseMovedEvents:YES];
    self.undoManager = [[NSUndoManager alloc] init];
    self.undoManager.levelsOfUndo = 50;

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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(canvasViewDidRestoreState:)
                                                 name:ScreenshotCanvasViewDidRestoreStateNotification
                                               object:self.canvasView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(canvasViewRequestsTool:)
                                                 name:ScreenshotCanvasViewRequestsToolNotification
                                               object:self.canvasView];
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

    [self.scrollView setDocumentView:self.canvasView];
    [container addSubview:self.scrollView];
    [self.window setInitialFirstResponder:self.canvasView];
    [self.window makeFirstResponder:self.canvasView];

#if defined(GNUSTEP)
    STStatusBarBackgroundView *statusBar = [[STStatusBarBackgroundView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, contentBounds.size.width, StatusBarHeight)];
    statusBar.fillColor = STThemeStatusBarBackgroundColorForTheme(self.usesDarkTheme);
    statusBar.topBorderColor = STThemeStatusBarBorderColorForTheme(self.usesDarkTheme);
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
    [statusField setFont:[NSFont systemFontOfSize:12.0f]];
    [statusField setAlignment:NSTextAlignmentLeft];
    statusField.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    [statusField setStringValue:@""];
    self.statusTextField = statusField;
    STApplyAccessibilityLabel(statusField, @"Status messages");
    [statusBar addSubview:statusField];
    [self setupStatusControls];

    self.statusBarVisiblePreference = YES;

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
    self.toolbar.allowsUserCustomization = NO;
    self.toolbar.autosavesConfiguration = NO;
    self.toolbar.sizeMode = NSToolbarSizeModeRegular;
#if defined(GNUSTEP)
    // Items have no labels on GNUstep, and libs-gui reserves label space in icon-and-label mode,
    // which made the toolbar 62px tall for 30px buttons.
    self.toolbar.displayMode = NSToolbarDisplayModeIconOnly;
#else
    self.toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
#endif

    [[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(toolbarWillAddItemNotification:)
                                             name:NSToolbarWillAddItemNotification
                                           object:self.toolbar];
    [self.window setToolbar:self.toolbar];
    //[self.toolbar setSelectedItemIdentifier:ToolbarItemHighlighter];
    //[self refreshToolButtonIcons];
    (void)[self imageNamed:@"CopyImage-active"];
}

- (NSToolbarItemIdentifier)identifierForTool:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolArrow:
            return ToolbarItemArrow;
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
    if ([identifier isEqualToString:ToolbarItemPreferences]) {
        return @"Preferences";
    }
    return nil;
}

- (NSString *)legacyActiveIconNameForIdentifier:(NSToolbarItemIdentifier)identifier {
    if ([identifier isEqualToString:ToolbarItemHighlighter]) {
        return @"Highligher-active";
    }
    if ([identifier isEqualToString:ToolbarItemPen]) {
        return @"PenTool-active";
    }
    if ([identifier isEqualToString:ToolbarItemEraser]) {
        return @"Eraser-active";
    }
    if ([identifier isEqualToString:ToolbarItemText]) {
        return @"AddText-active";
    }
    if ([identifier isEqualToString:ToolbarItemSelect]) {
        return @"MarqueeTool-active";
    }
    return nil;
}

- (NSArray<NSString *> *)iconNameCandidatesForToolbarIdentifier:(NSToolbarItemIdentifier)identifier active:(BOOL)active {
    NSString *stem = [self baseIconStemForToolbarIdentifier:identifier];
    if (!stem) {
        return @[];
    }

    NSMutableArray<NSString *> *ordered = [[NSMutableArray alloc] init];
    void (^appendUnique)(NSString *) = ^(NSString *candidate) {
        if (candidate.length == 0) {
            return;
        }
        if (![ordered containsObject:candidate]) {
            [ordered addObject:candidate];
        }
    };
    BOOL darkTheme = self.usesDarkTheme;
    ScreenshotToolAppendLog([NSString stringWithFormat:@"icon candidates %@ dark=%@ active=%@",
                             identifier,
                             darkTheme ? @"YES" : @"NO",
                             active ? @"YES" : @"NO"]);
#if defined(GNUSTEP)
    if (darkTheme) {
        if (active) {
            appendUnique([stem stringByAppendingString:@"-dark-active-gnustep"]);
        }
        appendUnique([stem stringByAppendingString:@"-dark-gnustep"]);
    } else {
        if (active) {
            appendUnique([stem stringByAppendingString:@"-light-active-gnustep"]);
        }
        appendUnique([stem stringByAppendingString:@"-light-gnustep"]);
    }
#endif
    if (darkTheme) {
        if (active) {
            appendUnique([stem stringByAppendingString:@"-dark-active"]);
        }
        appendUnique([stem stringByAppendingString:@"-dark"]);
    } else {
        if (active) {
            appendUnique([stem stringByAppendingString:@"-light-active"]);
        }
        appendUnique([stem stringByAppendingString:@"-light"]);
    }

    if (active) {
        NSString *legacyActive = [self legacyActiveIconNameForIdentifier:identifier];
        if (legacyActive.length > 0) {
            appendUnique(legacyActive);
        }
    }

    appendUnique(stem);

    return [ordered copy];
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

#if defined(GNUSTEP)
    [self refreshToolbarToolsControl];
    NSArray<NSToolbarItemIdentifier> *toolIdentifiers = @[ToolbarItemCopy, ToolbarItemPreferences];
#else
    NSArray<NSToolbarItemIdentifier> *toolIdentifiers = @[
        ToolbarItemSelect,
        ToolbarItemHighlighter,
        ToolbarItemPen,
        ToolbarItemArrow,
        ToolbarItemEraser,
        ToolbarItemText,
        ToolbarItemCopy
        ,ToolbarItemPreferences
    ];
#endif
    for (NSToolbarItemIdentifier identifier in toolIdentifiers) {
        NSToolbarItem *item = [self toolbarItemForIdentifier:identifier];
        if (!item) {
            ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ missing", identifier]);
            continue;
        }

        [self applyToolTipToToolbarItem:item source:@"refresh-icons"];
        BOOL isEnabled = YES;
        if ([identifier isEqualToString:ToolbarItemCopy]) {
            isEnabled = [self.canvasView hasImage];
        }
        item.enabled = isEnabled;

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
#if defined(GNUSTEP)
    (void)toolbar;
    return @[ToolbarItemTools,
             ToolbarItemColor,
             ToolbarItemCopy,
             ToolbarItemPreferences,
             ToolbarItemZoom,
             NSToolbarSpaceItemIdentifier,
             NSToolbarFlexibleSpaceItemIdentifier];
#else
    return @[ToolbarItemSelect,
             ToolbarItemHighlighter,
             ToolbarItemPen,
             ToolbarItemArrow,
             ToolbarItemText,
             ToolbarItemEraser,
             ToolbarItemCopy,
             ToolbarItemPreferences,
             ToolbarItemZoom,
             NSToolbarSpaceItemIdentifier,
             NSToolbarFlexibleSpaceItemIdentifier];
#endif
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
#if defined(GNUSTEP)
    (void)toolbar;
    return @[ToolbarItemTools,
             ToolbarItemColor,
             NSToolbarFlexibleSpaceItemIdentifier,
             ToolbarItemCopy,
             ToolbarItemPreferences,
             ToolbarItemZoom];
#else
    return @[ToolbarItemSelect,
             ToolbarItemHighlighter,
             ToolbarItemPen,
             ToolbarItemArrow,
             ToolbarItemText,
             ToolbarItemEraser,
             ToolbarItemCopy,
             ToolbarItemPreferences,
             NSToolbarFlexibleSpaceItemIdentifier,
             ToolbarItemZoom,
             NSToolbarSpaceItemIdentifier];
#endif
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
    itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {
    (void)toolbar;
    (void)flag;
    return [self baselineToolbarItemForIdentifier:itemIdentifier];
}

- (NSToolbarItem *)baselineToolbarItemForIdentifier:(NSToolbarItemIdentifier)identifier {
#if defined(GNUSTEP)
    if ([identifier isEqualToString:ToolbarItemTools]) {
        return [self toolbarItemForToolControl];
    }
#endif
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
    if ([identifier isEqualToString:ToolbarItemCopy]) {
        return [self baselineToolbarItemWithIdentifier:ToolbarItemCopy
                                                 label:@"Copy"
                                                action:@selector(copy:)
                                             imageName:@"CopyImage"];
    }
#if defined(GNUSTEP)
    if ([identifier isEqualToString:ToolbarItemColor]) {
        return [self toolbarItemForColorControl];
    }
#endif
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
        case ScreenshotCanvasToolText:
            return 4;
        case ScreenshotCanvasToolEraser:
            return 5;
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
            return ScreenshotCanvasToolText;
        case 5:
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
    }
    return @"";
}

- (NSString *)toolbarSegmentToolTipForTool:(ScreenshotCanvasTool)tool {
    NSString *title = [NSString stringWithFormat:@"%@ Tool (%@)", [self toolbarTitleForTool:tool], [self toolbarShortcutForTool:tool]];
    if (STToolUsesColor(tool)) {
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
    if (!self.textOptionsBar) {
        self.textOptionsBar = [[STTextOptionsBar alloc] initWithFrame:NSMakeRect(0.0, 0.0, NSWidth(self.scrollView.frame), [STTextOptionsBar preferredHeight])];
        self.textOptionsBar.delegate = self;
    }
    if (self.textOptionsBar.superview != container) {
        [self.textOptionsBar setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
        [container addSubview:self.textOptionsBar];
    }
    // Keep the image's scale while the row takes its space; the canvas slides down instead.
    self.canvasView.suspendsFitUpdates = YES;
    [self.textOptionsBar setHidden:NO];
    [self layoutContentSubviews];
    [self refreshTextOptionsBar];
}

- (void)hideTextOptionsBar {
    if (!self.textOptionsBar || self.textOptionsBar.isHidden) {
        return;
    }
    [self.textOptionsBar setHidden:YES];
    [self layoutContentSubviews];
    self.canvasView.suspendsFitUpdates = NO;
    [self.canvasView updateForEnclosingBoundsChange];
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
    NSFont *resized = [NSFont fontWithName:font.fontName size:size] ?: font;
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
    [self.canvasView toggleActiveTextPointer];
    [self refreshTextOptionsBar];
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
    [self showTransientFeedbackMessage:@"Ctrl+Return or Esc to finish · Return for a new line" duration:3.5];
}

- (NSImage *)toolbarSegmentImageForTool:(ScreenshotCanvasTool)tool selected:(BOOL)selected {
    (void)selected;
    NSString *identifier = [self identifierForTool:tool];
    NSString *stem = [self baseIconStemForToolbarIdentifier:identifier];
    NSImage *image = [self baselineToolbarImageNamed:stem active:NO];
    if (!image) {
        return nil;
    }
    NSImage *copy = [image copy];
    [copy setSize:NSMakeSize(STToolbarToolIconSize, STToolbarToolIconSize)];
    return copy;
}

#if defined(GNUSTEP)
- (void)adjustToolbarCustomViewVerticalOffset:(NSView *)view {
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
}
#endif

- (NSToolbarItem *)toolbarItemForToolControl {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ToolbarItemTools];
    item.label = @"";
    item.paletteLabel = @"Tools";
    item.toolTip = [self toolTipForIdentifier:ToolbarItemTools];
    item.target = self;
    item.action = @selector(toolbarToolControlAction:);

#if defined(GNUSTEP)
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
    }
    [self refreshToolbarToolsControl];
    item.view = self.toolbarToolSegmentedControl;
    item.minSize = self.toolbarToolSegmentedControl.frame.size;
    item.maxSize = self.toolbarToolSegmentedControl.frame.size;
#endif
    return item;
}

- (void)refreshToolbarToolsControl {
#if defined(GNUSTEP)
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
    [self.toolbarToolSegmentedControl setNeedsDisplay:YES];
    [self adjustToolbarCustomViewVerticalOffset:self.toolbarToolSegmentedControl];
#endif
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
    if (openPopover && STToolUsesColor(tool)) {
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

#if defined(GNUSTEP)
    if (!self.toolbarColorWellView) {
        self.toolbarColorWellView = [[STToolbarColorWellView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, STToolbarColorControlWidth, STToolbarColorControlHeight)];
        self.toolbarColorWellView.target = self;
        self.toolbarColorWellView.action = @selector(showActiveToolColorSettings:);
    }
    item.view = self.toolbarColorWellView;
    item.minSize = self.toolbarColorWellView.frame.size;
    item.maxSize = self.toolbarColorWellView.frame.size;
#endif
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
#if defined(GNUSTEP)
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
    BOOL enabled = STToolUsesColor(activeTool);
    NSColor *color = enabled ? [self currentColorForTool:activeTool] : nil;
    [colorWellView setEnabled:enabled];
    [colorWellView setColor:color];
    item.enabled = enabled;
    [self applyToolTipToToolbarItem:item source:@"refresh-color"];
    [self adjustToolbarCustomViewVerticalOffset:colorWellView];
    if (enabled) {
        STApplyAccessibilityLabel(colorWellView, [NSString stringWithFormat:@"%@ color", STDebugToolName(activeTool)]);
    } else {
        STApplyAccessibilityLabel(colorWellView, @"Color settings unavailable for current tool");
    }
#endif
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
#if defined(GNUSTEP)
    if (self.usesDarkTheme) {
        if (active) {
            [candidates addObject:[name stringByAppendingString:@"-dark-active-gnustep"]];
        }
        [candidates addObject:[name stringByAppendingString:@"-dark-gnustep"]];
    } else {
        if (active) {
            [candidates addObject:[name stringByAppendingString:@"-light-active-gnustep"]];
        }
        [candidates addObject:[name stringByAppendingString:@"-light-gnustep"]];
    }
#endif
    if (self.usesDarkTheme) {
        if (active) {
            [candidates addObject:[name stringByAppendingString:@"-dark-active"]];
        }
        [candidates addObject:[name stringByAppendingString:@"-dark"]];
    } else {
        if (active) {
            [candidates addObject:[name stringByAppendingString:@"-light-active"]];
        }
        [candidates addObject:[name stringByAppendingString:@"-light"]];
    }
    [candidates addObject:name];

    for (NSString *candidate in candidates) {
        if (candidate.length == 0) {
            continue;
        }
        NSImage *cached = baselineToolbarCache[candidate];
        if (cached) {
            return cached;
        }
        NSString *path = STPathForToolbarResource(candidate, @"png");
        if (!path) {
            continue;
        }
#if defined(GNUSTEP)
        NSImage *image = STBitmapBackedImageFromFile(path, NSMakeSize(ToolbarIconDimension, ToolbarIconDimension));
#else
        NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
#endif
        if (image) {
            [image setSize:NSMakeSize(ToolbarIconDimension, ToolbarIconDimension)];
            baselineToolbarCache[candidate] = image;
            return image;
        }
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
    if ([identifier isEqualToString:ToolbarItemPen] || [identifier isEqualToString:ToolbarItemArrow]) {
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
    BOOL shouldApplyDarkFilter =
#if defined(GNUSTEP)
        NO;
#else
        (self.usesDarkTheme || STThemeIsDark());
#endif
    if (shouldApplyDarkFilter) {
        baseIcon = [self darkThemeToolbarImageFromImage:baseIcon active:active];
    }
    NSImage *rendered = [baseIcon copy];
    NSColor *badgeColor = [self badgeColorForToolbarIdentifier:identifier];
    if (badgeColor) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar item %@ color %@", identifier, [self debugDescriptionForColor:badgeColor]]);
    }
#if !defined(GNUSTEP)
    if (badgeColor && !active) {
        rendered = [self imageByAddingColorBadgeToImage:rendered color:badgeColor];
    }
#endif
    [rendered setSize:NSMakeSize(ToolbarIconDimension, ToolbarIconDimension)];
#if defined(GNUSTEP)
    rendered = [self bitmapBackedToolbarImageFromImage:rendered];
    if (!STImageHasVisiblePixels(rendered)) {
        ScreenshotToolAppendLog([NSString stringWithFormat:@"Toolbar image %@ still lacks visible pixels after rendering", identifier]);
    }
#endif
    return rendered;
}

#if defined(GNUSTEP)
- (NSImage *)darkThemeToolbarImageFromImage:(NSImage *)image active:(BOOL)active {
    if (!image) {
        return nil;
    }
    NSBitmapImageRep *sourceRep = nil;
    for (NSImageRep *representation in image.representations) {
        if (![representation isKindOfClass:[NSBitmapImageRep class]]) {
            continue;
        }
        sourceRep = [(NSBitmapImageRep *)representation copy];
        break;
    }
    if (!sourceRep) {
        sourceRep = STBitmapRepresentationFromImage(image);
    }
    if (!sourceRep) {
        return image;
    }
    [sourceRep setSize:image.size];
    NSInteger width = sourceRep.pixelsWide;
    NSInteger height = sourceRep.pixelsHigh;
    if (width <= 0 || height <= 0) {
        return image;
    }
    unsigned char *pixels = [sourceRep bitmapData];
    NSInteger bytesPerRow = [sourceRep bytesPerRow];
    unsigned char lightValue = active ? 255 : 220;
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            unsigned char *pixel = pixels + y * bytesPerRow + x * 4;
            if (pixel[3] > 0) {
                pixel[0] = lightValue;
                pixel[1] = lightValue;
                pixel[2] = lightValue;
                if (!active) {
                    pixel[3] = 200;
                }
            }
        }
    }
    NSImage *result = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [result addRepresentation:sourceRep];
    return result;
}

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
#else
- (NSImage *)darkThemeToolbarImageFromImage:(NSImage *)image active:(BOOL)active {
    if (!image) {
        return nil;
    }
    NSSize size = image.size;
    if (size.width <= 0.0f || size.height <= 0.0f) {
        return image;
    }
    NSImage *composed = STRasterizeImage(size, ^(NSRect rect) {
        NSBezierPath *backgroundPath = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 0.5f, 0.5f)
                                                                       xRadius:6.0f
                                                                       yRadius:6.0f];
        [[STThemeToolbarBackgroundColor(active) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] setFill];
        [backgroundPath fill];

        NSRect imageRect = NSInsetRect(rect, 4.0f, 4.0f);
        CGFloat fraction = STThemeToolbarIconFraction(active);
        [image drawInRect:imageRect
                 fromRect:NSZeroRect
                operation:NSCompositeSourceOver
                 fraction:fraction
           respectFlipped:YES
                    hints:nil];

        NSColor *strokeColor = STThemeToolbarBorderColor(active);
        if (strokeColor) {
            [[strokeColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] setStroke];
            [backgroundPath setLineWidth:1.0f];
            [backgroundPath stroke];
        }
    });
    return composed ?: image;
}

- (NSImage *)bitmapBackedToolbarImageFromImage:(NSImage *)image {
    if (!image) {
        return nil;
    }
    NSSize logicalSize = image.size;
    if (logicalSize.width <= 0.0f || logicalSize.height <= 0.0f) {
        return image;
    }
    NSImage *bitmapImage = STRasterizeImage(logicalSize, ^(NSRect rect) {
        [image drawInRect:rect
                 fromRect:NSZeroRect
                operation:NSCompositeSourceOver
                 fraction:1.0f
           respectFlipped:YES
                    hints:nil];
    });
    return bitmapImage ?: image;
}
#endif

- (NSToolbarItem *)toolbarItemForZoomControl {
#if defined(GNUSTEP)
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
#else
    if (!self.zoomPopUpButton) {
        self.zoomPopUpButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 160.0, 28.0) pullsDown:NO];
        [self.zoomPopUpButton setAutoenablesItems:NO];
        NSArray *titles = @[@"Fit to Window", @"25%", @"50%", @"100%", @"200%"];
        [self.zoomPopUpButton removeAllItems];
        [self.zoomPopUpButton addItemsWithTitles:titles];
        [self.zoomPopUpButton setTarget:self];
        [self.zoomPopUpButton setAction:@selector(zoomPopUpAction:)];
        [self.zoomPopUpButton selectItemAtIndex:0];
        [self.zoomPopUpButton setFont:[NSFont systemFontOfSize:12.0f]];
    }

    if (!self.zoomToolbarLabel) {
        NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
        [label setEditable:NO];
        [label setBezeled:NO];
        [label setBordered:NO];
        [label setDrawsBackground:NO];
        [label setAlignment:NSTextAlignmentCenter];
        [label setFont:[NSFont boldSystemFontOfSize:11.0f]];
        [label setTextColor:STThemeToolbarLabelColor()];
        [label setStringValue:@"Zoom"];
        self.zoomToolbarLabel = label;
    }

    if (!self.zoomToolbarContainer) {
        NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 160.0, 32.0)];
        [container setAutoresizesSubviews:YES];

        // Label sits at the top; pop-up sits directly beneath within the 32px slot GNUstep allocates.
        CGFloat labelHeight = 12.0f;
        [self.zoomToolbarLabel setFrame:NSMakeRect(0, 0, container.frame.size.width, labelHeight)];
        self.zoomToolbarLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        [container addSubview:self.zoomToolbarLabel];

        CGFloat popUpHeight = 20.0f;
        [self.zoomPopUpButton setFrame:NSMakeRect(0, labelHeight, container.frame.size.width, popUpHeight)];
        self.zoomPopUpButton.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [container addSubview:self.zoomPopUpButton];

        self.zoomToolbarContainer = container;
    }

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ToolbarItemZoom];
    item.label = @"";
    item.paletteLabel = @"Zoom";
    item.view = self.zoomToolbarContainer;
    item.minSize = NSMakeSize(160.0, 32.0);
    item.maxSize = NSMakeSize(180.0, 32.0);
    return item;
#endif
}

- (void)refreshZoomToolbarControl {
#if defined(GNUSTEP)
    if (!self.zoomToolbarButtonView) {
        return;
    }

    BOOL hasImage = [self.canvasView hasImage];
    NSString *title = @"100%";
    if (hasImage) {
        title = self.canvasView.isFitToWindow ? @"Fit" : [self displayStringForScale:self.canvasView.zoomScale];
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
#endif
}

#pragma mark - Status Bar

- (void)setupStatusControls {
    if (!self.statusBarView) {
        return;
    }

    NSView *container = [[NSView alloc] initWithFrame:NSZeroRect];
    container.autoresizingMask = (NSViewMinXMargin | NSViewHeightSizable);
    self.statusControlsContainer = container;
    [self.statusBarView addSubview:container];

    NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [titleLabel setEditable:NO];
    [titleLabel setBezeled:NO];
    [titleLabel setBordered:NO];
    [titleLabel setDrawsBackground:NO];
    [titleLabel setAlignment:NSTextAlignmentRight];
    [titleLabel setFont:[NSFont boldSystemFontOfSize:12.0f]];
    [titleLabel setTextColor:STThemeStatusValueTextColor()];
    self.toolWidthTitleLabel = titleLabel;
    [container addSubview:titleLabel];

    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    [slider setMinValue:STToolWidthMin];
    [slider setMaxValue:STToolWidthMax];
    [slider setDoubleValue:STHighlighterWidthDefault];
    [slider setContinuous:YES];
    [slider setNumberOfTickMarks:0];
    [slider setAltIncrementValue:1.0];
    slider.target = self;
    slider.action = @selector(toolWidthSliderChanged:);
    self.toolWidthSlider = slider;
    STApplyAccessibilityLabel(slider, @"Adjust tool width");
    [container addSubview:slider];

    NSTextField *valueLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [valueLabel setEditable:NO];
    [valueLabel setBezeled:NO];
    [valueLabel setBordered:NO];
    [valueLabel setDrawsBackground:YES];
    [valueLabel setBackgroundColor:STThemeStatusValueBackgroundColor()];
    [valueLabel setAlignment:NSTextAlignmentRight];
    [valueLabel setFont:[NSFont systemFontOfSize:12.0f]];
    [valueLabel setTextColor:STThemeStatusValueTextColor()];
    [valueLabel setStringValue:@"0 px"];
    self.toolWidthValueLabel = valueLabel;
    STApplyAccessibilityLabel(valueLabel, @"Current tool width");
    [container addSubview:valueLabel];

    NSButton *optionsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    optionsButton.title = @"⋯";
#ifdef NSRoundedBezelStyle
    [optionsButton setBezelStyle:NSRoundedBezelStyle];
#else
    [optionsButton setBezelStyle:NSRecessedBezelStyle];
#endif
#ifdef NSFontWeightSemibold
    optionsButton.font = [NSFont systemFontOfSize:13.0f weight:NSFontWeightSemibold];
#else
    optionsButton.font = [NSFont boldSystemFontOfSize:13.0f];
#endif
    optionsButton.target = self;
    optionsButton.action = @selector(toolWidthOptionsButtonClicked:);
    optionsButton.toolTip = @"More width options";
    self.toolWidthOptionsButton = optionsButton;
    STApplyAccessibilityLabel(optionsButton, @"Tool width options");
    [container addSubview:optionsButton];

    container.hidden = NO;
    [self updateToolWidthControls];
}

- (void)layoutStatusControls {
    if (!self.statusBarView || !self.statusTextField) {
        return;
    }

    NSRect bounds = self.statusBarView.bounds;
    CGFloat padding = 8.0f;
    CGFloat verticalInset = 4.0f;
    CGFloat availableHeight = MAX(0.0f, bounds.size.height - (verticalInset * 2.0f));

    CGFloat controlsWidth = 0.0f;
    if (self.statusControlsContainer && !self.statusControlsContainer.isHidden) {
        NSSize titleSize = self.toolWidthTitleLabel ? [[self.toolWidthTitleLabel cell] cellSize] : NSZeroSize;
        NSSize valueSize = self.toolWidthValueLabel ? [[self.toolWidthValueLabel cell] cellSize] : NSZeroSize;
        if (self.toolWidthOptionsButton) {
            [self.toolWidthOptionsButton sizeToFit];
        }

        CGFloat labelWidth = MAX(120.0f, titleSize.width + 10.0f);
        CGFloat valueWidth = MAX(60.0f, valueSize.width + 14.0f);
        CGFloat sliderWidth = MIN(320.0f, MAX(220.0f, bounds.size.width * 0.32f));
        CGFloat optionsWidth = self.toolWidthOptionsButton ? MAX(28.0f, self.toolWidthOptionsButton.frame.size.width) : 0.0f;
        CGFloat spacing = 6.0f;
        controlsWidth = labelWidth + sliderWidth + valueWidth + optionsWidth + (spacing * 3.0f);

        CGFloat maxControlsWidth = bounds.size.width - (padding * 2.0f);
        if (controlsWidth > maxControlsWidth) {
            sliderWidth = MAX(160.0f, maxControlsWidth - (labelWidth + valueWidth + optionsWidth + (spacing * 3.0f)));
            controlsWidth = labelWidth + sliderWidth + valueWidth + optionsWidth + (spacing * 3.0f);
        }

        CGFloat containerX = bounds.size.width - padding - controlsWidth;
        if (containerX < padding) {
            containerX = padding;
        }

        NSRect containerFrame = NSMakeRect(containerX,
                                           verticalInset,
                                           controlsWidth,
                                           availableHeight);
        [self.statusControlsContainer setFrame:containerFrame];

        CGFloat controlHeight = MIN(availableHeight, 18.0f);
        CGFloat centerY = (containerFrame.size.height - controlHeight) / 2.0f;
        CGFloat x = 0.0f;

        if (self.toolWidthTitleLabel) {
            self.toolWidthTitleLabel.frame = NSMakeRect(x, centerY, labelWidth, controlHeight);
        }
        x += labelWidth + spacing;

        if (self.toolWidthSlider) {
            CGFloat sliderHeight = MIN(16.0f, availableHeight);
            self.toolWidthSlider.frame = NSMakeRect(x,
                                                    (containerFrame.size.height - sliderHeight) / 2.0f,
                                                    sliderWidth,
                                                    sliderHeight);
        }
        x += sliderWidth + spacing;

        if (self.toolWidthValueLabel) {
            self.toolWidthValueLabel.frame = NSMakeRect(x, centerY, valueWidth, controlHeight);
        }
        x += valueWidth + spacing;

        if (self.toolWidthOptionsButton) {
            CGFloat buttonHeight = MIN(controlHeight + 2.0f, self.toolWidthOptionsButton.frame.size.height);
            self.toolWidthOptionsButton.frame = NSMakeRect(x,
                                                           (containerFrame.size.height - buttonHeight) / 2.0f,
                                                           optionsWidth,
                                                           buttonHeight);
        }
    } else if (self.statusControlsContainer) {
        self.statusControlsContainer.frame = NSMakeRect(bounds.size.width - padding,
                                                        verticalInset,
                                                        0.0f,
                                                        availableHeight);
    }

    CGFloat textWidth = MAX(0.0f, bounds.size.width - (padding * 2.0f));
    if (self.statusControlsContainer && !self.statusControlsContainer.isHidden) {
        CGFloat limit = self.statusControlsContainer.frame.origin.x - padding;
        textWidth = MAX(0.0f, limit - padding);
    }
    self.statusTextField.frame = NSMakeRect(padding,
                                            verticalInset,
                                            textWidth,
                                            availableHeight);
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
    if (self.statusControlsContainer) {
        [self.statusControlsContainer setHidden:!show];
    }
    if (self.statusTextField) {
        [self.statusTextField setHidden:!show];
    }
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

- (NSString *)currentInterfaceThemePreferenceValue {
    NSString *preference = [[[NSUserDefaults standardUserDefaults] stringForKey:STDefaultsInterfaceThemeKey] lowercaseString];
    if ([preference isEqualToString:STInterfaceThemePreferenceLightValue] ||
        [preference isEqualToString:STInterfaceThemePreferenceDarkValue] ||
        [preference isEqualToString:STInterfaceThemePreferenceAutoValue]) {
        return preference;
    }
    return STInterfaceThemePreferenceAutoValue;
}

- (void)updateInterfaceThemePreference:(NSString *)preference persist:(BOOL)persist {
    NSString *normalizedPreference = [preference lowercaseString];
    if (![normalizedPreference isEqualToString:STInterfaceThemePreferenceLightValue] &&
        ![normalizedPreference isEqualToString:STInterfaceThemePreferenceDarkValue] &&
        ![normalizedPreference isEqualToString:STInterfaceThemePreferenceAutoValue]) {
        normalizedPreference = STInterfaceThemePreferenceAutoValue;
    }
    if (persist) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([normalizedPreference isEqualToString:STInterfaceThemePreferenceAutoValue]) {
            [defaults removeObjectForKey:STDefaultsInterfaceThemeKey];
        } else {
            [defaults setObject:normalizedPreference forKey:STDefaultsInterfaceThemeKey];
        }
    }
    self.usesDarkTheme = STThemeIsDark();
    [self refreshInterfaceThemeAppearance];
}

#if defined(GNUSTEP)
- (void)themeDidActivate:(NSNotification *)notification {
    // A newly activated theme can change whether Auto resolves to the light or dark icons.
    BOOL dark = STThemeIsDark();
    if (dark != self.usesDarkTheme) {
        self.usesDarkTheme = dark;
        [self refreshInterfaceThemeAppearance];
    }
}
#endif

- (void)resetInterfaceThemePreferenceToDefault {
    [self updateInterfaceThemePreference:STInterfaceThemePreferenceAutoValue persist:YES];
}

- (void)refreshInterfaceThemeAppearance {
#if defined(GNUSTEP)
    if ([self.statusBarView isKindOfClass:[STStatusBarBackgroundView class]]) {
        STStatusBarBackgroundView *backgroundView = (STStatusBarBackgroundView *)self.statusBarView;
        backgroundView.fillColor = STThemeStatusBarBackgroundColorForTheme(self.usesDarkTheme);
        backgroundView.topBorderColor = STThemeStatusBarBorderColorForTheme(self.usesDarkTheme);
    }
#endif
    if (self.window) {
        [self.window setBackgroundColor:STThemeWindowBackgroundColor()];
    }
    if (self.statusTextField) {
        [self.statusTextField setTextColor:STThemeStatusPrimaryTextColor()];
    }
    if (self.toolWidthTitleLabel) {
        [self.toolWidthTitleLabel setTextColor:STThemeStatusValueTextColor()];
    }
    if (self.toolWidthValueLabel) {
        [self.toolWidthValueLabel setBackgroundColor:STThemeStatusValueBackgroundColor()];
        [self.toolWidthValueLabel setTextColor:STThemeStatusValueTextColor()];
    }
    if (self.zoomToolbarLabel) {
        [self.zoomToolbarLabel setTextColor:STThemeToolbarLabelColor()];
    }
    [self updateToolWidthControls];
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
#if defined(GNUSTEP)
    [self.zoomToolbarButtonView setNeedsDisplay:YES];
#endif
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
    [self updateToolWidthControls];

    NSString *savedDirectory = [defaults stringForKey:STDefaultsSaveDirectoryKey];
    if (savedDirectory.length == 0) {
        savedDirectory = STDefaultSaveDirectoryPath();
        [defaults setObject:savedDirectory forKey:STDefaultsSaveDirectoryKey];
    }
    self.defaultSaveDirectory = savedDirectory;
    [self ensureDirectoryExistsAtPath:self.defaultSaveDirectory];

    if ([defaults objectForKey:STDefaultsShowStatusBarKey] == nil) {
        [defaults setBool:YES forKey:STDefaultsShowStatusBarKey];
    }
    self.statusBarVisiblePreference = [defaults boolForKey:STDefaultsShowStatusBarKey];
    [self updateStatusBarVisibility];

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

- (void)updateToolWidthControls {
    if (!self.toolWidthSlider || !self.toolWidthTitleLabel) {
        return;
    }
    ScreenshotCanvasTool tool = [self widthTargetTool];
    CGFloat currentWidth = [self currentWidthForTool:tool];
    CGFloat defaultWidth = [self defaultWidthForTool:tool];
    NSString *title = [self titleForToolWidth:tool];
    [self.toolWidthTitleLabel setStringValue:title];
    [self.toolWidthSlider setMinValue:STToolWidthMin];
    [self.toolWidthSlider setMaxValue:STToolWidthMax];
    [self.toolWidthSlider setDoubleValue:currentWidth];
    [self updateToolWidthValueLabelWithWidth:currentWidth];
    BOOL canReset = fabs(currentWidth - defaultWidth) > 0.01f;
    self.toolWidthMenuCanReset = canReset;
    if (self.toolWidthOptionsButton) {
        [self.toolWidthOptionsButton setEnabled:YES];
    }
    if (self.toolWidthValueLabel) {
        [self.toolWidthValueLabel setBackgroundColor:STThemeStatusValueBackgroundColor()];
        [self.toolWidthValueLabel setTextColor:STThemeStatusValueTextColor()];
    }
    [self layoutStatusControls];
}

- (void)toolWidthOptionsButtonClicked:(id)sender {
    NSMenu *menu = [self toolWidthOptionsMenu];
    if (!menu) {
        return;
    }
    NSButton *button = self.toolWidthOptionsButton;
    if (!button) {
        return;
    }
    NSPoint location = NSMakePoint(0.0f, NSHeight(button.bounds));
    [menu popUpMenuPositioningItem:nil atLocation:location inView:button];
}

- (NSMenu *)toolWidthOptionsMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Width Options"];
    NSMenuItem *resetItem = [[NSMenuItem alloc] initWithTitle:@"Reset Width"
                                                       action:@selector(resetActiveToolWidth:)
                                                keyEquivalent:@""];
    [resetItem setTarget:self];
    [resetItem setEnabled:self.toolWidthMenuCanReset];
    [menu addItem:resetItem];

    NSMenuItem *defaultItem = [[NSMenuItem alloc] initWithTitle:@"Set as Default"
                                                         action:@selector(setActiveToolWidthAsDefault:)
                                                  keyEquivalent:@""];
    [defaultItem setTarget:self];
    [defaultItem setEnabled:self.toolWidthMenuCanReset];
    [menu addItem:defaultItem];
    return menu;
}

- (ScreenshotCanvasTool)widthTargetTool {
    ScreenshotCanvasTool tool = self.canvasView.activeTool;
    if (tool == ScreenshotCanvasToolPen || tool == ScreenshotCanvasToolHighlighter) {
        self.lastWidthTool = tool;
        return tool;
    }
    if (self.lastWidthTool == ScreenshotCanvasToolPen || self.lastWidthTool == ScreenshotCanvasToolHighlighter) {
        return self.lastWidthTool;
    }
    self.lastWidthTool = ScreenshotCanvasToolHighlighter;
    return self.lastWidthTool;
}

- (NSString *)titleForToolWidth:(ScreenshotCanvasTool)tool {
    switch (tool) {
        case ScreenshotCanvasToolPen:
            return @"Pen Width";
        case ScreenshotCanvasToolArrow:
            return @"Arrow Width";
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

- (void)updateToolWidthValueLabelWithWidth:(CGFloat)width {
    if (!self.toolWidthValueLabel) {
        return;
    }
    NSString *value = [NSString stringWithFormat:@"%.0f px", roundf(width)];
    [self.toolWidthValueLabel setStringValue:value];
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

- (void)toolWidthSliderChanged:(NSSlider *)slider {
    ScreenshotCanvasTool tool = [self widthTargetTool];
    CGFloat rawValue = slider.doubleValue;
    CGFloat rounded = roundf(rawValue);
    CGFloat clamped = [self clampedWidth:rounded];
    if (fabs(clamped - rawValue) > 0.01f) {
        [slider setDoubleValue:clamped];
    }
    [self applyWidth:clamped toTool:tool persist:YES];
}

- (void)resetActiveToolWidth:(id)sender {
    ScreenshotCanvasTool tool = [self widthTargetTool];
    CGFloat defaultWidth = [self defaultWidthForTool:tool];
    [self applyWidth:defaultWidth toTool:tool persist:YES];
    NSString *message = [NSString stringWithFormat:@"%@ reset to %.0f px",
                         [self titleForToolWidth:tool],
                         roundf(defaultWidth)];
    [self showStatusMessage:message duration:2.0];
}

- (void)setActiveToolWidthAsDefault:(id)sender {
    ScreenshotCanvasTool tool = [self widthTargetTool];
    CGFloat width = [self currentWidthForTool:tool];
    [self setDefaultWidth:width forTool:tool];
    NSString *message = [NSString stringWithFormat:@"%@ default set to %.0f px",
                         [self titleForToolWidth:tool],
                         roundf(width)];
    [self showStatusMessage:message duration:2.0];
    [self updateToolWidthControls];
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
    ScreenshotCanvasTool displayedTool = [self widthTargetTool];
    if (displayedTool == tool) {
        [self.toolWidthSlider setDoubleValue:clamped];
        [self updateToolWidthValueLabelWithWidth:clamped];
    }
    [self.canvasView setNeedsDisplay:YES];
    [self updateToolWidthControls];
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
    NSFont *font = [NSFont fontWithName:name size:(CGFloat)sizeValue];
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
                                 (long)event.clickCount]);
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
#if defined(GNUSTEP)
    NSRect anchor = [self anchorRectForToolbarSubview:self.toolbarColorWellView inView:anchorView];
#else
    NSRect anchor = NSZeroRect;
#endif
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

#if defined(GNUSTEP)
    NSRect anchor = [self anchorRectForToolbarSubview:self.zoomToolbarButtonView inView:anchorView];
#else
    NSRect anchor = NSZeroRect;
#endif
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
    return self.canvasView.zoomScale;
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
    [self updateToolWidthControls];
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
    [self setDefaultWidth:width forTool:tool];
    [self applyWidth:width toTool:tool persist:YES];
}

- (NSColor *)preferencesController:(PreferencesWindowController *)controller defaultColorForTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    return [self defaultColorForTool:tool];
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultColor:(NSColor *)color forTool:(ScreenshotCanvasTool)tool {
    (void)controller;
    [self setDefaultColor:color forTool:tool];
    [self applyColor:color toTool:tool persist:YES];
}

- (NSFont *)preferencesControllerDefaultTextFont:(PreferencesWindowController *)controller {
    (void)controller;
    return self.textDefaultFont ?: STDefaultTextFont();
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultTextFont:(NSFont *)font {
    (void)controller;
    [self setDefaultTextFont:font];
    [self applyTextFont:font persist:YES];
}

- (NSColor *)preferencesControllerDefaultTextColor:(PreferencesWindowController *)controller {
    (void)controller;
    return self.textDefaultColor ?: STDefaultTextColor();
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeDefaultTextColor:(NSColor *)color {
    (void)controller;
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
    self.statusBarVisiblePreference = show;
    [[NSUserDefaults standardUserDefaults] setBool:show forKey:STDefaultsShowStatusBarKey];
    [self updateStatusBarVisibility];
}

- (BOOL)preferencesControllerOffersToolbarInTitleBar:(PreferencesWindowController *)controller {
    (void)controller;
    return STAdwaitaThemeIsActive();
}

- (BOOL)preferencesControllerCanShowToolbarInTitleBar:(PreferencesWindowController *)controller {
    (void)controller;
    return STAdwaitaHeaderBarIsActive();
}

- (BOOL)preferencesControllerShowsToolbarInTitleBar:(PreferencesWindowController *)controller {
    (void)controller;
    return STToolbarInTitleBarEnabled();
}

- (void)preferencesController:(PreferencesWindowController *)controller didToggleToolbarInTitleBar:(BOOL)show {
    (void)controller;
    [[NSUserDefaults standardUserDefaults] setBool:show forKey:STGnomeThemeHeaderBarToolbarKey];
    [self reattachToolbarForTitleBarPlacement];
}

/// The theme reads GnomeThemeHeaderBarToolbar when a toolbar is added to a window, so setting the
/// toolbar again moves it into or out of the header bar without a restart.
- (void)reattachToolbarForTitleBarPlacement {
    NSToolbar *toolbar = self.window.toolbar;
    if (!toolbar || !toolbar.isVisible) {
        return;
    }
    // Keep the window where and as big as it is: the canvas takes or gives up the toolbar's row.
    NSRect frame = self.window.frame;
    [self.window setToolbar:nil];
    [self.window setToolbar:toolbar];
    [self.window setFrame:frame display:YES];
    [self layoutContentSubviews];
    [self.canvasView updateForEnclosingBoundsChange];
}

- (NSString *)preferencesControllerInterfaceThemePreference:(PreferencesWindowController *)controller {
    (void)controller;
    return [self currentInterfaceThemePreferenceValue];
}

- (void)preferencesController:(PreferencesWindowController *)controller didChangeInterfaceThemePreference:(NSString *)preference {
    (void)controller;
    [self updateInterfaceThemePreference:preference persist:YES];
}

- (void)preferencesControllerRestoreDefaults:(PreferencesWindowController *)controller {
    (void)controller;
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

    self.statusBarVisiblePreference = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:STDefaultsShowStatusBarKey];
    [self updateStatusBarVisibility];

    [self resetInterfaceThemePreferenceToDefault];

    if ([[NSUserDefaults standardUserDefaults] objectForKey:STGnomeThemeHeaderBarToolbarKey] != nil) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:STGnomeThemeHeaderBarToolbarKey];
        [self reattachToolbarForTitleBarPlacement];
    }

    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateToolWidthControls];
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

        [self.statusTextField setStringValue:@""];

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

    NSDictionary *attributes = @{ NSFontAttributeName: self.hudView.font ?: [NSFont systemFontOfSize:13.0f] };
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

    STHudView *hudView = [[STHudView alloc] initWithFrame:rect];
    hudView.cornerRadius = STHudCornerRadius;
    hudView.textPadding = NSMakeSize(STHudHorizontalPadding, STHudVerticalPadding);
    [window setContentView:hudView];

    self.hudWindow = window;
    self.hudView = hudView;
    ScreenshotToolAppendLog(@"HUD window created");
#endif
}

- (void)updateHUDAppearance {
    if (!self.hudView) {
        return;
    }
    self.hudView.font = [NSFont boldSystemFontOfSize:13.0f];
    self.hudView.fillColor = STThemeHUDBackgroundColor();
    self.hudView.textColor = STThemeHUDTextColor();
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
    if (showTextBar) {
        [self.textOptionsBar setFrame:NSMakeRect(0.0f, NSMaxY(scrollFrame), bounds.size.width, textBarHeight)];
        [self.textOptionsBar setNeedsDisplay:YES];
    }
}

- (void)resizeWindowToImageSize:(NSSize)imageSize {
    if (imageSize.width <= 0.0f || imageSize.height <= 0.0f || !self.window) {
        return;
    }

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
    CGFloat targetWidth = MAX(contentWidth, minimumWidth);
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
    if (![self confirmProceedingWithUnsavedChanges]) {
        return;
    }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
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
        [self openImageAtURL:selectedURL];
    }
}

- (void)openRecentDocument:(id)sender {
    NSString *path = nil;
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        id representedObject = [(NSMenuItem *)sender representedObject];
        if ([representedObject isKindOfClass:[NSString class]]) {
            path = [(NSString *)representedObject stringByStandardizingPath];
        }
    }
    if (path.length == 0) {
        return;
    }
    if (![self confirmProceedingWithUnsavedChanges]) {
        return;
    }

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

    [self openImageAtURL:[NSURL fileURLWithPath:path]];
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
    if (![imageData writeToURL:destination options:NSDataWritingAtomic error:&error]) {
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

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:types owner:nil];
    BOOL wrotePasteboard = NO;
    if (pngData) {
        wrotePasteboard = [pasteboard setData:pngData forType:NSPasteboardTypePNG] || wrotePasteboard;
    }
    if (tiffData) {
        wrotePasteboard = [pasteboard setData:tiffData forType:NSPasteboardTypeTIFF] || wrotePasteboard;
    }
    BOOL mirroredWayland = STMirrorPNGDataToWaylandClipboard(pngData);

    ScreenshotToolAppendLog([NSString stringWithFormat:@"copy action write results pasteboard=%@ waylandMirror=%@",
                             wrotePasteboard ? @"YES" : @"NO",
                             mirroredWayland ? @"YES" : @"NO"]);

    if (!wrotePasteboard && !mirroredWayland) {
        [self showCopyFeedbackMessage:@"Copy failed" duration:2.0];
        return;
    }

    BOOL x11OnlyCopy = (STScreenshotToolIsWaylandSession() && !mirroredWayland && wrotePasteboard);
    NSString *status = nil;
    if ([self.canvasView hasSelection]) {
        status = x11OnlyCopy ? @"Copied selection to X11 clipboard" : @"Copied selection to clipboard";
    } else {
        status = x11OnlyCopy ? @"Copied image to X11 clipboard" : @"Copied image to clipboard";
    }
    [self showCopyFeedbackMessage:status duration:3.0];
}

- (NSData *)clipboardPNGDataForPasteAsNewImage {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSArray<NSString *> *imageTypes = @[ NSPasteboardTypePNG, NSPasteboardTypeTIFF, NSTIFFPboardType ];
    NSString *availableType = [pasteboard availableTypeFromArray:imageTypes];
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

- (void)canvasViewDidRestoreState:(NSNotification *)notification {
    if (notification.object != self.canvasView) {
        return;
    }
    if ([self.canvasView hasImage]) {
        [self resizeWindowToImageSize:self.canvasView.image.size];
    }
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

    CGFloat current = self.canvasView.zoomScale;
    CGFloat next = [self nextZoomScaleAbove:current];
    [self setZoomScale:next];
}

- (void)zoomOut:(id)sender {
    if (![self.canvasView hasImage]) {
        return;
    }
    if (self.canvasView.isFitToWindow) {
        [self setZoomScale:0.5];
        return;
    }

    CGFloat current = self.canvasView.zoomScale;
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
    if (fabs(percent - rounded) < 0.01f) {
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
                             (long)(event ? event.clickCount : 0)]);
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
                             (long)(event ? event.clickCount : 0)]);
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
                             (long)(event ? event.clickCount : 0)]);
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
                }
#else
                icon = STRenderToolbarIcon(base);
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

- (NSImage *)imageByAddingColorBadgeToImage:(NSImage *)image color:(NSColor *)color {
    if (!image || !color) {
        return image;
    }
    NSColor *deviceColor = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: color;
    NSSize baseSize = image.size;
    if (baseSize.width <= 0.0f || baseSize.height <= 0.0f) {
        baseSize = NSMakeSize(ToolbarIconDimension, ToolbarIconDimension);
    }
#if defined(GNUSTEP)
    NSData *tiffData = [image TIFFRepresentation];
    NSBitmapImageRep *sourceRep = tiffData ? [NSBitmapImageRep imageRepWithData:tiffData] : nil;
    if (!sourceRep) {
        return image;
    }
    NSInteger width = sourceRep.pixelsWide;
    NSInteger height = sourceRep.pixelsHigh;
    if (width <= 0 || height <= 0) {
        return image;
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
        return image;
    }
    memcpy([destRep bitmapData], [sourceRep bitmapData], MIN([destRep bytesPerRow], [sourceRep bytesPerRow]) * height);
    unsigned char *pixels = [destRep bitmapData];
    NSInteger bytesPerRow = [destRep bytesPerRow];
    CGFloat badgeSize = 10.0f;
    CGFloat centerX = width - badgeSize - 2.0f + badgeSize * 0.5f;
    // NSBitmapImageRep coordinates originate at the top-left on GNUstep, so flip Y to target bottom-right.
    CGFloat centerY = height - badgeSize - 2.0f + badgeSize * 0.5f;
    CGFloat radius = badgeSize * 0.5f;
    CGFloat borderRadius = radius - 0.5f;
    CGFloat r = deviceColor.redComponent;
    CGFloat g = deviceColor.greenComponent;
    CGFloat b = deviceColor.blueComponent;
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            CGFloat dx = (CGFloat)x - centerX;
            CGFloat dy = (CGFloat)y - centerY;
            CGFloat distance = sqrtf(dx * dx + dy * dy);
            if (distance <= radius) {
                unsigned char *pixel = pixels + y * bytesPerRow + x * 4;
                pixel[0] = (unsigned char)lroundf(r * 255.0f);
                pixel[1] = (unsigned char)lroundf(g * 255.0f);
                pixel[2] = (unsigned char)lroundf(b * 255.0f);
                pixel[3] = 255;
                if (distance >= borderRadius) {
                    pixel[0] = (unsigned char)lroundf(0.0f * 255.0f);
                    pixel[1] = (unsigned char)lroundf(0.0f * 255.0f);
                    pixel[2] = (unsigned char)lroundf(0.0f * 255.0f);
                    pixel[3] = 160;
                }
            }
        }
    }
    NSImage *result = [[NSImage alloc] initWithSize:baseSize];
    [result addRepresentation:destRep];
    return result;
#else
    NSImage *composed = [[NSImage alloc] initWithSize:baseSize];
    [composed lockFocus];
    [image drawInRect:NSMakeRect(0.0f, 0.0f, baseSize.width, baseSize.height)
             fromRect:NSZeroRect
            operation:NSCompositeSourceOver
             fraction:1.0f
       respectFlipped:YES
               hints:nil];
    CGFloat badgeSize = 10.0f;
    NSRect badgeRect = NSMakeRect(baseSize.width - badgeSize - 2.0f,
                                  2.0f,
                                  badgeSize,
                                  badgeSize);
    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:badgeRect];
    [deviceColor setFill];
    [path fill];
    [[NSColor colorWithCalibratedWhite:0.0f alpha:0.25f] setStroke];
    [path setLineWidth:1.0f];
    [path stroke];
    [composed unlockFocus];
    return composed;
#endif
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
    }

    if (tool == ScreenshotCanvasToolPen || tool == ScreenshotCanvasToolHighlighter || tool == ScreenshotCanvasToolArrow) {
        self.lastWidthTool = STSettingsToolForTool(tool);
    }
    [self updateToolWidthControls];

    if (self.toolbar) {
        [self.toolbar setSelectedItemIdentifier:selectedIdentifier];
        [self refreshToolButtonIcons];
    }
}

- (void)setZoomScale:(CGFloat)scale {
    self.canvasView.fitToWindow = NO;
    self.canvasView.zoomScale = scale;
    [self.canvasView setNeedsDisplay:YES];
    [self reflectZoomSelection];
}

- (void)reflectZoomSelection {
#if defined(GNUSTEP)
    [self refreshZoomToolbarControl];
    [self.zoomPopoverController refresh];
#else
    if (!self.zoomPopUpButton) {
        return;
    }

    if (self.canvasView.isFitToWindow) {
        [self.zoomPopUpButton selectItemAtIndex:0];
        return;
    }

    CGFloat scale = self.canvasView.zoomScale;
    NSString *value = [self displayStringForScale:scale];
    if (fabs(scale - 0.25) < 0.001) {
        [self.zoomPopUpButton selectItemAtIndex:1];
    } else if (fabs(scale - 0.5) < 0.001) {
        [self.zoomPopUpButton selectItemAtIndex:2];
    } else if (fabs(scale - 1.0) < 0.001) {
        [self.zoomPopUpButton selectItemAtIndex:3];
    } else if (fabs(scale - 2.0) < 0.001) {
        [self.zoomPopUpButton selectItemAtIndex:4];
    } else {
        NSInteger existingIndex = [self.zoomPopUpButton indexOfItemWithTitle:value];
        if (existingIndex == -1) {
            [self.zoomPopUpButton addItemWithTitle:value];
            existingIndex = [self.zoomPopUpButton indexOfItemWithTitle:value];
        }
        if (existingIndex >= 0) {
            [self.zoomPopUpButton selectItemAtIndex:existingIndex];
        }
    }
#endif
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
    return [self confirmProceedingWithUnsavedChanges];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
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
}

/// Save… / Don't Save / Cancel. Separate so tests can answer without a modal alert.
- (STUnsavedChangesChoice)askAboutUnsavedChanges {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Save your annotations?";
    alert.informativeText = @"Your changes will be lost if you don't save them. To keep annotations editable, use File ▸ Save Project…; Save… flattens them into an image.";
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
    if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
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

- (void)windowDidResize:(NSNotification *)notification {
    [self layoutContentSubviews];
    [self.canvasView updateForEnclosingBoundsChange];
}

@end
