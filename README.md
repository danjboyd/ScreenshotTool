# ScreenshotTool Development Notes

## Current Status
- **Toolbar Icons**: Highlighter, Pen, and Copy icons render correctly. Color pickers show the labeled color wells, and the generated eraser icon is present (placeholder art for now).
- **Tool State Feedback**: Active tool buttons swap to their `*-active` variants via `refreshToolButtonIcons`, providing pressed-state visuals.
- **Zoom Control**: Uses an `NSPopUpButton` positioned with a trailing space item; drop-down works and stays inset from the window edge.
- **Copy Workflow**: `copy:` now flattens the screenshot with `lockFocus` and writes PNG/TIFF data to the pasteboard to avoid transparent pastes.

## Outstanding Todos
- **Clipboard Verification**: Paste an annotated image into GIMP/other editors to confirm transparency issues are resolved.
- **Icon Polish**: Replace the auto-generated eraser and pressed-state icons with final artwork when available.
- **Color Picker UX**: Revisit showing picker icons alongside the wells once a livelier presentation is ready.
- **Icon Loader**: Active icon logic currently only affects tool buttons; re-enable for other items once assets exist.

## Handy References
- Debug log: `~/git/ScreenshotTool/screenshottool.log`
- Generated icons: `Resources/*.png` and matching `*.tiff`
- Flattening logic: `Source/ScreenshotCanvasView.m`
- Toolbar behavior: `Source/AppDelegate.m`

Next session: validate copy→GIMP, refine toolbar art, and continue UI polish.
