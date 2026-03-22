# libs-OpenSave Bug Report: `NSOpenPanel.URL` is `nil` After Successful GTK Open

## Summary

When `libs-OpenSave` is linked into a GNUstep app and running in GTK mode,
accepting an `NSOpenPanel` selection can return `NSFileHandlingPanelOKButton`
while `panel.URL` is still `nil`.

This breaks normal relink-only integrations that use the modern `URL` API.
In our app, the open action completed the dialog successfully but then failed
to open the selected file because the resolved URL was missing.

## Why This Looks Upstream

`libs-OpenSave` explicitly aims to preserve `NSOpenPanel` / `NSSavePanel` API
behavior when used as a relink-only replacement, including `-URL`, `-URLs`,
`-filename`, and `-filenames`.

Relevant upstream code paths:

- `Source/GSOpenSaveGtk.m`
  `GSOpenSaveGtkRunOpenPanel(...)` calls `[panel setFilenames:filenames]` on
  success.
- `Source/OpenSavePanels.m`
  `-setFilenames:` stores both `GSOpenSaveOpenFilenamesKey` and derived
  `GSOpenSaveOpenURLsKey`.
- `Source/OpenSavePanels.m`
  `-gs_URL` for `NSOpenPanel` should return the first URL from
  `GSOpenSaveOpenURLsKey`.

Given that flow, a successful GTK open should leave `panel.URL` populated.

## Environment

- Host app: ScreenshotTool
- Integration model: relink-only `NSOpenPanel` / `NSSavePanel` replacement
- `libs-OpenSave` commit:
  `4292973a2dc0a9c1187247ff701791a0def624da`
- Dialog mode at runtime: GTK
- Platform:
  `Linux iep-daniel-t14 6.12.73+deb13-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.12.73-1 (2026-02-17) x86_64 GNU/Linux`
- GTK 4 version: `4.18.6`

## Expected Behavior

After the user selects a file in the GTK-backed `NSOpenPanel` and confirms the
dialog:

- `runModal` should return `NSFileHandlingPanelOKButton`
- `panel.URL` should be a non-`nil` file URL for the selected file
- `panel.URLs`, `panel.filename`, and `panel.filenames` should remain logically
  consistent with that same selection

## Actual Behavior

The dialog returns success in GTK mode, but `panel.URL` is `nil`.

In ScreenshotTool, that caused the app to attempt to open a `nil` URL and do
nothing.

## Reproduction Steps

1. Build `libs-OpenSave` and link it into a GNUstep GUI app that uses the
   standard `NSOpenPanel` API.
2. Ensure the runtime mode is GTK.
3. Launch the app.
4. Trigger a normal "Open..." action.
5. Select any local image file.
6. Accept the dialog.
7. Immediately inspect `panel.URL`.

## Observed Evidence

From the app log:

```text
OpenSave mode: GTK
openImageAtURL invoked with nil URL
```

In the failing app path, `openImageAtURL:` was only called after the open panel
returned success, so the `nil` came from reading `panel.URL` after an accepted
selection.

## Impact

- Breaks drop-in compatibility for apps using the URL-based open-panel API
- Causes "Open..." actions to silently fail unless the app adds defensive
  fallbacks
- Undercuts the main value proposition of relink-only adoption

This is high impact for adopters because `panel.URL` is the normal accessor
many modern GNUstep/Cocoa-style code paths use first.

## App-Side Workaround Implemented

ScreenshotTool now resolves the selection defensively in this order:

1. `panel.URL`
2. `panel.URLs`
3. `panel.filename`
4. `panel.filenames`

That workaround is documented inline in:

- `Source/AppDelegate.m`
- `Source/PreferencesWindowController.m`

The workaround prevents the app from being blocked, but it should not be
required for a correct `libs-OpenSave` integration.

## Suspected Root Cause

This section is a hypothesis, not a confirmed diagnosis.

`Source/OpenSavePanels.m` swizzles `URL` and `filename` in both:

- `NSOpenPanel (GSOpenSave)`
- `NSSavePanel (GSOpenSave)`

Because `NSOpenPanel` inherits from `NSSavePanel`, double-swizzling inherited
accessors may be leaving `NSOpenPanel.URL` routed through the save-panel path
instead of the open-panel path.

That would explain the observed behavior:

- open selection state exists
- `panel.URL` is `nil`
- fallback accessors can still recover the chosen path

In particular, the open-panel accessor should read from
`GSOpenSaveOpenURLsKey`, while the save-panel accessor reads from
`GSOpenSaveSaveFilenameKey`. If the wrong implementation wins after swizzling,
`URL` could be `nil` even though the open selection was captured.

## Suggested Upstream Validation

Please add a regression test that covers successful GTK open-panel selection and
asserts all accessors stay in sync:

- `panel.URL != nil`
- `panel.URLs.count > 0`
- `panel.filename != nil`
- `panel.filenames.count > 0`
- `panel.URL.path == panel.filename`
- `panel.URL.path == [panel.URLs[0] path]`
- `panel.filename == panel.filenames[0]`

If the swizzle hypothesis is correct, the fix may involve avoiding overlapping
`URL` / `filename` swizzles between `NSOpenPanel` and `NSSavePanel`, or making
the inherited-method case explicit instead of exchanging implementations twice.

## Requested Fix

Please make successful GTK-backed `NSOpenPanel` selections preserve accessor
parity so that `panel.URL`, `panel.URLs`, `panel.filename`, and
`panel.filenames` all reflect the selected file immediately after `runModal`
returns `NSFileHandlingPanelOKButton`.
