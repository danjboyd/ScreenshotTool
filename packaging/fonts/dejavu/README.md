# DejaVu fonts (AppImage only)

DejaVu 2.37, unmodified, from the upstream release
(https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.tar.bz2,
SHA-256 fa9ca4d13871dd122f61258a80d01751d603b4d3ee14095d65453b4e846e17d7). LICENSE is the
release's license file.

gnustep-back falls back to DejaVu Sans (and DejaVu Sans Mono for fixed pitch) when a font it asks
for isn't installed. Fedora installs Cantarell and Noto, not DejaVu, so without these the AppImage
draws no text and maps no window there outside GNOME. The packager bundles them
(`backends.appimage.fonts.bundle` in `../../package.manifest.json`) behind the host's own
fontconfig setup, so hosts that have their own fonts are unaffected.
