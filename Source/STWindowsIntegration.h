#import <Foundation/Foundation.h>

@class NSWindow;

NS_ASSUME_NONNULL_BEGIN

/// Windows services the app uses directly, where GNUstep's own fall short. Everything here is
/// NO or nil off Windows.

/// The Windows clipboard, read and written directly. GNUstep's pasteboard server bridges only
/// text to it, so an image copied in the app never reached other apps, and one copied in them
/// (a snip among them) never reached the app.

/// Whether the app uses the Windows clipboard for images rather than the general pasteboard.
BOOL STWindowsClipboardIsNative(void);

/// Whether the clipboard holds an image: PNG or a bitmap.
BOOL STWindowsClipboardHasImage(void);

/// Puts `pngData` on the clipboard as PNG, for apps that keep transparency, and as a 32-bit
/// bitmap, for the rest.
BOOL STWindowsClipboardWritePNGData(NSData *pngData);

/// Puts `text` on the clipboard as Unicode text (a custom action's output, #221).
BOOL STWindowsClipboardWriteText(NSString *text);

/// The clipboard's image as PNG data: its PNG if it has one, else its bitmap, converted.
NSData * _Nullable STWindowsClipboardPNGData(void);

/// The files on the clipboard, as Explorer copies them.
NSArray<NSString *> * _Nullable STWindowsClipboardFilePaths(void);

/// Posted on the main thread whenever the clipboard changes, once monitoring has started.
extern NSString *const STWindowsClipboardDidChangeNotification;

/// Turns cairo's hinted glyph metrics off by default when the display is scaled (125%, 150%), as
/// the backend does itself under GSScaleFactor. Hinted advances are rounded at the font's own
/// size, so scaled text was spaced unevenly ("px ·PNG", #306). A GSFontHinting the user set still
/// wins. Call before the app starts.
void STWindowsRegisterScaledTextDefaults(void);

/// Starts watching the clipboard, so a change shows even while the app keeps focus: a snip or
/// PrtScn with the app in front didn't enable Paste until it was activated again (#202).
void STWindowsStartClipboardMonitoring(void);

/// Files dropped on `window` from Explorer: `handler` gets their paths on the main thread, after
/// the drop has finished. GNUstep's Windows backend takes no drops from other apps itself.
void STWindowsAcceptFileDrops(NSWindow *window, void (^handler)(NSArray<NSString *> *paths));

/// Drags the file at `path` out of `window` into other apps (#276), with the shell's own data
/// object and drag image, as Explorer drags a file. Returns once the drop or cancel is over; NO if
/// the drag couldn't start, so the caller can fall back. GNUstep's Windows backend starts no OLE
/// drag itself.
BOOL STWindowsDragFileOut(NSWindow *window, NSString *path);

/// Starts `executablePath` with `arguments`, its windows shown. NSTask starts a process hidden
/// there, so another instance of the app never showed its window.
BOOL STWindowsLaunchProcess(NSString *executablePath, NSArray<NSString *> *arguments);

/// What the above are made of, for tests.

/// A packed 32-bit bottom-up CF_DIB of `pngData`'s image, alpha in the fourth byte.
NSData * _Nullable STWindowsDIBDataForPNGData(NSData *pngData);

/// PNG data of a packed DIB (a CF_DIB block's contents).
NSData * _Nullable STWindowsPNGDataForDIBData(NSData *dibData);

/// `argument` quoted for a command line, as CommandLineToArgvW and the C runtime read it back.
NSString *STWindowsQuotedCommandLineArgument(NSString *argument);

NS_ASSUME_NONNULL_END
