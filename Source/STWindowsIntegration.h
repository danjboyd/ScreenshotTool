#import <Foundation/Foundation.h>

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

/// The clipboard's image as PNG data: its PNG if it has one, else its bitmap, converted.
NSData * _Nullable STWindowsClipboardPNGData(void);

/// The files on the clipboard, as Explorer copies them.
NSArray<NSString *> * _Nullable STWindowsClipboardFilePaths(void);

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
