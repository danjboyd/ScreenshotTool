# macOS Port & Release Plan

1. **Prep tooling** – `scripts/bootstrap_macos.sh` installs Xcode CLTs plus Homebrew utilities if desired; Cocoa builds no longer depend on the GNUstep runtime.
2. **Cocoa build target** – Use `scripts/build_cocoa.sh` to compile a native `build/cocoa/ScreenshotTool.app` with clang/AppKit (no gnustep-make). Keep GNUstep `make` flow for Linux.
3. **Platform fixes** – Linux/BSD assumptions are gated; macOS uses native AppKit behaviour. GNUstep-only workarounds (e.g., FreeType/text flattening) are now disabled on mac.
4. **mac regression pass** – `scripts/smoke_macos_app.sh` launches the Cocoa bundle headlessly for startup validation; GNUstep probes are skipped on mac.
5. **Packaging outputs** – `scripts/package_appimage.sh` (Linux) and `scripts/package_macos_dmg.sh build/cocoa/ScreenshotTool.app` produce AppImage/DMG with optional codesign/notarization.
6. **CI/Release wiring** – GitHub Actions builds AppImage on Ubuntu and DMG on macOS, uploading artifacts.
7. **Docs & workflow** – `README.md` and `docs/Packaging.md` cover Cocoa build/run/DMG; `WORKFLOW.md` references the packaging guide for release steps.
