# Vendored gnustep-packager updater

`objc/` is a copy of `updater/objc` from
[danjboyd/gnustep-packager](https://github.com/danjboyd/gnustep-packager), with one local change:

- `OBJCFLAGS += -DHAVE_MODE_T` in the three `Makefile`s (first added in 098c24d). The release
  build's Windows toolchain (gnustep-cli-new) otherwise defines `mode_t` twice, in libdispatch's
  `os/generic_win_base.h` and in the CRT. Re-apply it after a sync until the packager has it.

- Source commit: `23f17080e37ef73e786aed9d34f65abd07eeb97e` (gnustep-packager v0.1.1)
- Synced in: ScreenshotTool's `packager-v0.1.1` branch

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
