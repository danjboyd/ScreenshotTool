# Toolbar Icons on GNUstep

This guide documents everything we have learned about getting toolbar icons looking correct on GNUstep, including the asset pipeline, script support, and the runtime code that selects the proper PNG for active vs. inactive state.

## 1. Asset Requirements

1. **Source Artwork**
   - Start from 32 × 32 PNGs (`Resources/<Stem>-dark.png`, `…-light.png`).
   - PNGs must be 8-bit RGBA without embedded ICC profiles. Run `scripts/normalize_toolbar_icons.sh` after any manual edits to re-encode everything with `-strip -type TrueColorAlpha -depth 8`.
   - Icons intended for Sombre should already include the desired colors (no runtime recoloring). GNUstep does not re-tint themed icons reliably.

2. **Active Variants**
   - Generate glow/outline versions with `scripts/generate_active_icons.sh`. This script takes each `<Stem>-dark.png`/`…-light.png`, adds the aqua outline + subtle fill, and writes `<Stem>-dark-active.png`, etc.
   - The script also regenerates the GNUstep-specific assets (see next section) via `scripts/generate_toolbar_icons.sh`.

3. **GNUstep-Sized Variants**
   - Run `scripts/generate_toolbar_icons.sh` whenever base or active PNGs change. It produces `<Stem>-<variant>-gnustep.png` at 24 × 24 with the same 8-bit encoding.
   - Variants handled: `dark`, `light`, `dark-active`, `light-active`.

## 2. Runtime Loading Logic

Toolbar icon selection happens in `Source/AppDelegate.m`.

```objc
static const BOOL STUseDateTrackerToolbarBaseline = YES;

- (NSArray<NSString *> *)iconNameCandidatesForToolbarIdentifier:(NSToolbarItemIdentifier)identifier
                                                        active:(BOOL)active {
    …
#if defined(GNUSTEP)
    if (self.usesDarkTheme) {
        if (active) appendUnique([stem stringByAppendingString:@"-dark-active-gnustep"]);
        appendUnique([stem stringByAppendingString:@"-dark-gnustep"]);
    } else {
        if (active) appendUnique([stem stringByAppendingString:@"-light-active-gnustep"]);
        appendUnique([stem stringByAppendingString:@"-light-gnustep"]);
    }
#endif
    if (self.usesDarkTheme) {
        if (active) appendUnique([stem stringByAppendingString:@"-dark-active"]);
        appendUnique([stem stringByAppendingString:@"-dark"]);
    } else {
        if (active) appendUnique([stem stringByAppendingString:@"-light-active"]);
        appendUnique([stem stringByAppendingString:@"-light"]);
    }
    …
}
```

- GNUstep always tries the `…-gnustep` assets first.
- Active tools request the `-active` variant before falling back to legacy `*-active` PNGs.

### Disabling GNUstep Dark-Theme Filter

Older builds applied a `darkThemeToolbarImageFromImage` filter to every GNUstep icon, which destroys full-color PNGs. This flag is now disabled on GNUstep:

```objc
BOOL shouldApplyDarkFilter =
#if defined(GNUSTEP)
    NO;
#else
    (self.usesDarkTheme || STThemeIsDark());
#endif
```

### Baseline Toolbar Refresh

Even when `STUseDateTrackerToolbarBaseline` is `YES`, `refreshToolButtonIcons` still runs so GNUstep items update when active state changes:

```objc
- (void)refreshToolButtonIcons {
    if (!self.toolbar) return;
    NSToolbarItemIdentifier activeIdentifier = [self identifierForTool:self.canvasView.activeTool];
    …
    NSImage *icon = [self toolbarImageForIdentifier:identifier active:isActive];
    …
}
```

## 3. Visibility Check (GNUstep)

GNUstep historically dropped icons it thought had “no visible pixels”. We relaxed the test to accept any pixel with alpha > 0.05, regardless of brightness:

```objc
static BOOL STBitmapRepHasVisiblePixels(NSBitmapImageRep *bitmap) {
    …
            if ([devicePixel alphaComponent] > 0.05f) {
                return YES;
            }
    …
}
```

Without this change, dark-themed PNGs were considered empty and GNUstep painted random memory.

## 4. Common Failure Modes & Fixes

| Symptom | Root Cause | Fix |
|---------|------------|-----|
| Toolbar icons appear as random stripes/squares | PNG encoded as 16-bit/has ICC profile → GNUstep misreads | Run `scripts/normalize_toolbar_icons.sh`, regenerate GNUstep variants, rebuild. |
| No visual difference between active/inactive tools | Active assets missing or loader only uses base PNGs | Ensure `scripts/generate_active_icons.sh` was run and `iconNameCandidates…` includes `-active` entries (see Section 2). |
| Icons vanish (GNUstep logs “nz=0”) | `STBitmapRepHasVisiblePixels` rejected dark pixels | Keep the relaxed alpha-only check in place. |
| Colors washed out or glow mangled | GNUstep `darkThemeToolbarImageFromImage` applied | Ensure the `shouldApplyDarkFilter` flag is `NO` for GNUstep builds. |
| Toolbar icons disappear entirely | Replacing the DateTracker-provided `NSToolbarItem` views with custom buttons (e.g. while experimenting with tooltip fixes) prevents GNUstep from drawing the cached `NSImage`s; the stock toolbar simply paints the empty custom view. | **Do not replace the toolbar item views.** Keep DateTracker’s baseline container and overlay behaviour intact, and layer tooltip changes on top of the existing items. |

## 5. Workflow Summary

1. **Generate/Update Base Art**
   - Produce 32 × 32 PNGs per theme (`Resources/<Stem>-dark.png`, `…-light.png`). Use `scripts/generate_ai_icons.py` if needed.

2. **Normalize**
   - `scripts/normalize_toolbar_icons.sh`

3. **Create Active Variants**
   - `scripts/generate_active_icons.sh`

4. **Generate GNUstep Cuts**
   - `scripts/generate_toolbar_icons.sh` (automatically invoked by the active script, but run manually after manual edits).

5. **Rebuild**
   - `PATH=/usr/GNUstep/System/Tools:$PATH LD_LIBRARY_PATH=/usr/GNUstep/System/Library/Libraries:$LD_LIBRARY_PATH make -j$(nproc)`

6. **Verify**
   - Launch with `SCREENSHOT_TOOL_LOG_PATH=./debug.log openapp ./ScreenshotTool.app`
   - Inspect `debug.log` for `[ToolbarDebug] … nz=` (should be > 0) and confirm active glow toggles correctly.

Following this process keeps GNUstep’s toolbar in lockstep with the PNGs you see in `Resources/`, including accurate active-state rendering.
