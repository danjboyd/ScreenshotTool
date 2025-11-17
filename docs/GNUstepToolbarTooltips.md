# GNUstep Toolbar Tooltip Workflow

Date: 2025‑11‑17  
Owners: Codex / Daniel

## Problem
GNUstep kept resurfacing its native yellow tooltips even though we disable `GSShowToolTips` and register our custom `STToolbarTooltipController`. When we switched to the DateTracker-style toolbar (to fix the dark-theme rendering bug), `NSToolbarItem` stopped providing custom container views, so our tooltip controller no longer had stable views to hook onto.

## Final Fix
1. **Keep the DateTracker baseline** – we do *not* replace `NSToolbarItem.view` with custom buttons. The GNUstep toolbar continues to draw our 24 px assets using the stock container so the icons stay visible.
2. **Discover toolbar views at runtime**
   - Added `tooltipController` + `tooltipViewMap` properties on `AppDelegate` (GNUstep-only).
   - Whenever a toolbar item is inserted or refreshed, we grab `item.view`, scrub any native tooltips up the view hierarchy, and register that view with `STToolbarTooltipController`.
   - If `item.view` is still nil, we defer registration on the next run loop tick until the DateTracker container finishes constructing the view.
   - A `tooltipMaintenanceTimer` now runs every second to re-scrub the toolbar hierarchy and call `updateTooltip:forView:` so GNUstep can't reattach native capsules after layout churn.
3. **Expose snapshots for tests**
   - `registeredToolbarTooltipsSnapshot` and `registeredTrackingIdentifiersSnapshot` translate controller state back into toolbar identifiers so `TooltipsSuppressedProbe` can assert that each identifier has exactly one tooltip/ tracking rect.
4. **Resource lookups for probes**
   - `baselineToolbarImageNamed` now uses `STPathForToolbarResource`, so tests that run outside the app bundle can still load the GNUstep PNGs.

## Verification
- `Tools/run_tests.sh` passes, including the revived `TooltipsSuppressedProbe` (no SKIP) and `ToolbarIconThemeProbe`.
- Manual QA: hover Select/Pen/Highlighter/Text/Eraser on GNUstep – native bubbles stay suppressed and the custom rounded tooltip window appears with the expected strings.

## Key Files
- `Source/AppDelegate.m` – tooltip controller wiring + resource lookup changes.
- `Tests/TooltipsSuppressedProbe.m` – updated to synthesize views when necessary and to consume the new identifier-based snapshots.
- `Tests/ToolbarIconThemeProbe.m` – relaxed visible-pixel check to match the runtime alpha-only logic.
