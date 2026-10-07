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
- The packaged updater is GNUstep's, so the macOS build leaves it out; Check for Updates is
  hidden there.

## Phase 2: signing and updates (needs an Apple Developer account)

- Developer ID signing with the hardened runtime, notarization and stapling in the release job.
  `scripts/package_macos_dmg.sh` already does this given `CODESIGN_IDENTITY` and notarization
  credentials; the job needs the certificate imported into a keychain from repository secrets.
- Sparkle 2 for updates, with an appcast published to Pages next to the Windows and Linux feeds.

## Phase 3: native polish

- `NSDocument`: autosave, Versions, the edited dot, the title bar's document menu, the system's
  Open Recent.
- `NSPopover` in place of `STFloatingPopover` on macOS; a Settings window that looks native.
- Trackpad pinch to zoom and two-finger panning; drag the annotated image out to other apps;
  the Share menu; window restoration.
- Smaller resources: the bundle carries large TIFFs the macOS build doesn't need.
- An Icon Composer icon for the macOS 26 look.

## Phase 4: capture

- Region, window and full-screen capture with ScreenCaptureKit, a global shortcut and a menu
  bar item. Needs the Screen Recording permission, which keeps working across updates only
  with a stable (Developer ID) signature.
