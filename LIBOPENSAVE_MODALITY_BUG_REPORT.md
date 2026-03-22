# libs-OpenSave Bug Report: GTK Dialogs Are Not Truly App-Modal in GNUstep Hosts

## Status

Fixed on 2026-03-22 in `libs-OpenSave`.

The Linux backend now threads GNUstep parent windows into the native dialog
path and prefers `org.freedesktop.portal.FileChooser` with a real
`x11:<xid>` parent identifier derived from `NSWindow.windowRef` on GNUstep
X11 hosts. That gives the compositor/window manager an actual parent
relationship instead of the previous best-effort AppKit-side block.

The legacy `GtkFileDialog` path remains as a fallback when no native parent
identifier is available.

## Summary

When `libs-OpenSave` is used from a GNUstep app, the GTK-backed open/save
dialogs are not truly modal relative to the app's main window.

With the dialog open, the user can still click the GNUstep window frame/title
bar, the app window comes to the front, and the GTK dialog falls behind it.

This means the current GTK backend does not actually match the behavior of a
GNUstep modal `NSOpenPanel` / `NSSavePanel`.

## Affected Version

- `libs-OpenSave` commit:
  `d67d17ac9bf6a792fe6349871d1e53917f68f708`
  (`Improve GTK dialog app modality`)
- Relevant file:
  `third_party/libs-OpenSave/Source/GSOpenSaveGtk.m`

## Environment

- Host app: ScreenshotTool
- Platform:
  `Linux iep-daniel-t14 6.12.73+deb13-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.12.73-1 (2026-02-17) x86_64 GNU/Linux`
- GTK 4 version: `4.18.6`
- Host toolkit: GNUstep AppKit

## Reproduction

1. Build ScreenshotTool against the current `libs-OpenSave` `main`.
2. Launch ScreenshotTool.
3. Trigger File > Open or File > Save As.
4. Wait for the GTK native file dialog to appear.
5. Click back onto the ScreenshotTool main window frame/title bar.

## Frequency

- Reproduces consistently in ScreenshotTool on this setup.

## Expected Behavior

The file dialog should stay above the ScreenshotTool window and the app window
should remain blocked, matching GNUstep modal panel behavior.

## Actual Behavior

The ScreenshotTool window can be brought in front of the GTK dialog, leaving
the file dialog in the background.

## Root Cause

This is not just a missing event filter. The current implementation does not
create a real native parent/transient relationship between the GTK dialog and
the GNUstep window.

Current code path in `Source/GSOpenSaveGtk.m`:

- `GSOpenSaveBeginAppModalWindowBlock()` marks ordered GNUstep windows as
  `ignoresMouseEvents=YES`:
  `third_party/libs-OpenSave/Source/GSOpenSaveGtk.m:115`
- `GSOpenSaveSpinMainLoops()` filters AppKit event dispatch while the GTK
  dialog is running:
  `third_party/libs-OpenSave/Source/GSOpenSaveGtk.m:193`
- `gtk_file_dialog_set_modal(dialog, TRUE)` is set for open/save dialogs:
  `third_party/libs-OpenSave/Source/GSOpenSaveGtk.m:417`
  `third_party/libs-OpenSave/Source/GSOpenSaveGtk.m:476`
- But the actual async calls still pass `NULL` as the `GtkWindow *parent`:
  - `gtk_file_dialog_open_multiple(dialog, NULL, NULL, ...)`
    `third_party/libs-OpenSave/Source/GSOpenSaveGtk.m:241`
  - `gtk_file_dialog_open(dialog, NULL, NULL, ...)`
    `third_party/libs-OpenSave/Source/GSOpenSaveGtk.m:243`
  - `gtk_file_dialog_select_folder(dialog, NULL, NULL, ...)`
    `third_party/libs-OpenSave/Source/GSOpenSaveGtk.m:301`
  - `gtk_file_dialog_select_multiple_folders(dialog, NULL, NULL, ...)`
    `third_party/libs-OpenSave/Source/GSOpenSaveGtk.m:336`
  - `gtk_file_dialog_save(dialog, NULL, NULL, ...)`
    `third_party/libs-OpenSave/Source/GSOpenSaveGtk.m:376`

That AppKit-side block is only a best-effort approximation. It does not stop
the window manager from reordering a top-level GNUstep window when the user
clicks its frame/title bar, because that interaction is outside normal AppKit
content event delivery.

## Impact

- The dialog can fall behind the app window, making the UI feel broken or
  hung.
- This does not match the contract implied by a modal `NSOpenPanel` /
  `NSSavePanel`.
- It undermines the goal of relink-only native dialog replacement for GNUstep
  apps.

## Why the Current Approach Cannot Fully Work

According to the official GTK docs:

- `GtkFileDialog` modal behavior is defined relative to the parent window
  passed to the dialog methods.
- `GtkFileDialog.open()` and related methods accept a `GtkWindow *parent`.
- GTK4 removed supported foreign-subwindow APIs, so a non-GTK host window
  cannot be wrapped as a real `GtkWindow` parent through the normal toolkit
  interfaces.

That means `gtk_file_dialog_set_modal(TRUE)` plus a `NULL` parent cannot make
the dialog truly modal to a GNUstep `NSWindow`.

## Why This Matches the Observed Symptom

The current code blocks most in-app interaction, so the patch appears to help
partially. But because there is no real transient parent:

- the GTK dialog is not natively attached to the GNUstep window
- the window manager is free to restack the GNUstep toplevel independently
- clicking the app window frame/title bar can still bring it in front

That is exactly the behavior observed in ScreenshotTool.

## Requested Fix

Please make GTK-backed dialogs actually preserve modal behavior relative to the
GNUstep host window, or explicitly downgrade/document the current behavior as
best-effort only until a real parented solution exists.

## Suggested Upstream Direction

Short term:

- Document the current GTK path as best-effort app-modal only, not true modal
  parity with GNUstep panels.

Real fix options:

1. Add a Linux backend path that can supply a real parent-window identifier to
   the native dialog layer, likely through `xdg-desktop-portal`.
2. Investigate explicit backend-specific integration for X11 and/or Wayland
   using GNUstep's native window handle APIs.
3. Avoid claiming true app-modal behavior for GTK dialogs until one of the
   above exists.

## GNUstep APIs Potentially Relevant

GNUstep does expose native window hooks such as:

- `NSWindow -windowRef`
- `NSWindow -windowHandle`
- `NSApplication -beginModalSessionForWindow:`
- `NSApplication -runModalSession:`

Those may help with future backend-specific work, but they do not by
themselves create a valid `GtkWindow *parent` for `GtkFileDialog`.

## Primary Sources

- GTK `GtkFileDialog` class docs:
  https://docs.gtk.org/gtk4/class.FileDialog.html
- GTK `GtkFileDialog.open()` docs:
  https://docs.gtk.org/gtk4/method.FileDialog.open.html
- GTK 3 to 4 migration guide, foreign-subwindow removal:
  https://docs.gtk.org/gtk4/migrating-3to4.html
