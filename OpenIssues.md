# Open Issues

- Toolbar icons (PNG) are not drawing in GNUstep dark theme; toolbar labels render black on dark background.  
  **Investigations so far:** Replaced toolbar views with `STToolbarItemContainer`, generated light/dark PNG sets, and added a new regression probe (`ToolbarIconThemeProbe`). Icons load correctly when fetched directly, but once the GNUstep toolbar hosts them the `NSImage` objects lose bitmap reps and the labels fall back to the theme’s default (black).  
  **Theory of the case:** GNUstep is rebuilding toolbar items with theme-provided containers, discarding our button image data and overriding label colours. We likely need to (a) render the icons into bitmap-backed images that survive GNUstep’s copy, and/or (b) inject our container later in the toolbar lifecycle so the framework doesn’t replace it. Once the container survives, we can enforce the white label colour via `STThemeToolbarLabelColor()`.
