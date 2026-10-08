# macOS

The macOS app is built natively with AppKit from the same sources as the GNUstep builds;
`#if defined(GNUSTEP)` separates what differs. Build, run and packaging steps are in `README.md`
and `docs/Packaging.md`.

## Phase 1: a Mac build in every release (done)

- `scripts/build_cocoa.sh` builds a universal app from the sources and resources `GNUmakefile`
  lists, stamps the version and signs it ad hoc.
- The toolbar is the GNUstep build's: tool switcher, colour well, undo/redo, copy. Its symbolic
  icons are template images, so macOS tints them for light and dark mode.
- Standard menus: Services, Hide, Close, Cut/Copy/Paste/Select All (to the first responder, so
  they edit a text label), Enter Full Screen, Window and Help.
- `Info-cocoa.plist` declares the `.screenshottool` project type and offers the app for images
  (Open With, drops on the Dock icon) without taking over from Preview.
- The app icon is shaped for macOS (`scripts/make_macos_icon.swift`).
- CI builds, smoke-tests and packages the app on `macos-26`; releases include the DMG.

## Phase 2: updates (done) and signing (needs an Apple Developer account)

- Sparkle 2 updates the macOS app (Check for Updates…, and automatic checks once you allow
  them). The release job signs each DMG with an EdDSA key and publishes an appcast to Pages as
  `updates/macos/stable.xml` or `prerelease.xml`, next to the Windows and Linux feeds; a
  prerelease build follows the prerelease feed. Sparkle doesn't need a Developer ID. The build
  number (`CFBundleVersion`, the commit count) is what Sparkle compares: it ignores a version's
  `-rc8` suffix.
- Still to do with the account: Developer ID signing with the hardened runtime, notarization and
  stapling in the release job. `scripts/package_macos_dmg.sh` already does this given
  `CODESIGN_IDENTITY` and notarization credentials (`scripts/codesign_macos_app.sh` signs
  Sparkle's helpers first); the job needs the certificate imported into a keychain from
  repository secrets.

## Phase 3: native polish (done)

- Popovers are AppKit's `NSPopover` (`STFloatingPopover` wraps it on macOS).
- Pinch zooms around the pointer, a two-finger double tap toggles 100% and Fit, Command-scroll
  zooms; two-finger scrolling pans.
- Dragging the Copy toolbar button hands the annotated image (or the selection) to another app
  as a PNG; Share in the toolbar and File > Share offer the system's services; dropping an
  image or project on the window opens it.
- The close button shows the edited dot while annotations are unsaved; opened files go on the
  system's recent documents (the Dock menu, Recent Items).
- The bundle carries only the symbolic icons and cursors: 3.6 MB, a 2.2 MB DMG.
- `Tools/run_tests_macos.sh` runs the test suite with Apple's XCTest, in CI too.

## Multiple windows (done)

On macOS each image gets a window of its own, with an `AppDelegate` instance as its controller;
the one `main.m` makes is also the application's delegate, and keeps what is the application's
(menus, Open Recent, Preferences, the updater, quitting). GNUstep keeps one window per process,
as its in-window menus and themes expect.

- Open (several files at once), Open Recent, opening from Finder or the Dock, and Paste as New
  Image open a window each, filling an empty front window first; an image that's open already
  just comes to the front. File > New Window (Cmd+N) opens an empty one. Windows tab together
  when the system asks for tabs.
- The menus' document commands (Save, Undo, Crop, Zoom, Share) go to the front window through
  `STDocumentRouter`; Preferences apply to every window; quitting asks about each window's
  unsaved annotations.
- A closed window's controller lets go of its observers, timers and pending calls, so it and its
  canvas are freed. Known issue: about 5 MB per image window opened stays allocated after the
  window closes, below anything of ours (every controller, canvas and image is freed; empty
  windows don't do it). Measured in `MultiWindowProbe` work, not yet traced to its owner.

Still open: autosave and Versions (`NSDocument`), window restoration, a Settings window that
looks native, and an Icon Composer icon for the macOS 26 look.

## Phase 4: capture

- Region, window and full-screen capture with ScreenCaptureKit, a global shortcut and a menu
  bar item. Needs the Screen Recording permission, which keeps working across updates only
  with a stable (Developer ID) signature.
