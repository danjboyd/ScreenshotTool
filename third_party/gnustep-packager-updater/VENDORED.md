# Vendored gnustep-packager updater

`objc/` is a copy of `updater/objc` from
[danjboyd/gnustep-packager](https://github.com/danjboyd/gnustep-packager), with no local changes.

- Source commit: `f358b6085f55f134759c304585ce63e6593226f2` (gnustep-packager main, 2026-10-13)
- Synced in: ScreenshotTool's `vendor-updater-sync` branch

ScreenshotTool builds GPUpdaterCore, GPUpdaterUI and gp-update-helper from this copy (the top-level
`GNUmakefile`'s `updater-*` targets), not from the packager checkout that packages the release. A
fix merged in gnustep-packager therefore reaches ScreenshotTool only when this copy is synced.

To sync, from a checkout of both repositories:

```sh
rm -rf third_party/gnustep-packager-updater/objc
git -C ../gnustep-packager -c core.autocrlf=false archive <commit> updater/objc | tar -x -C /tmp
cp -r /tmp/updater/objc third_party/gnustep-packager-updater/objc
```

Then update the source commit above. `-c core.autocrlf=false` keeps the files' LF line endings on
Windows.
