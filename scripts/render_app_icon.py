#!/usr/bin/env python3
#
# render_app_icon.py
# Copyright (C) 2026 Daniel Boyd
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
"""Render the app icon from Resources/AppIcon/*.svg to the files the builds use.

- ScreenshotToolIcon.png (1024 px) and ScreenshotToolIcon.tiff (256 px), from ScreenshotToolIcon.svg:
  the GNUstep app icon, the AppImage and desktop icon, and the source of nothing else.
- ScreenshotToolIcon-macOS.png (1024 px), from ScreenshotToolIcon-macOS.svg: the art on Apple's icon
  grid. build_cocoa.sh makes the .icns from it, and stage_release.ps1 the Windows .ico.

Needs librsvg's GObject bindings (gir1.2-rsvg-2.0), pycairo and ImageMagick's `magick` (for the
TIFF). Run it after editing an SVG and commit the outputs: the build doesn't render them.
"""

import os
import subprocess

import cairo
import gi

gi.require_version("Rsvg", "2.0")
from gi.repository import Rsvg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "Resources", "AppIcon")
OUTPUT = os.path.join(ROOT, "Resources")


def render(svg, pixels, png):
    handle = Rsvg.Handle.new_from_file(os.path.join(SOURCES, svg))
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, pixels, pixels)
    viewport = Rsvg.Rectangle()
    viewport.x, viewport.y, viewport.width, viewport.height = 0, 0, pixels, pixels
    handle.render_document(cairo.Context(surface), viewport)
    surface.write_to_png(os.path.join(OUTPUT, png))
    print(png)


def main():
    render("ScreenshotToolIcon.svg", 1024, "ScreenshotToolIcon.png")
    render("ScreenshotToolIcon-macOS.svg", 1024, "ScreenshotToolIcon-macOS.png")
    tiff = os.path.join(OUTPUT, "ScreenshotToolIcon.tiff")
    subprocess.run(["magick", os.path.join(OUTPUT, "ScreenshotToolIcon.png"), "-resize", "256x256",
                    "-strip", "-compress", "lzw", tiff], check=True)
    print("ScreenshotToolIcon.tiff")


if __name__ == "__main__":
    main()
