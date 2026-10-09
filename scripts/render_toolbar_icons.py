#!/usr/bin/env python3
#
# render_toolbar_icons.py
# Copyright (C) 2026 Daniel Boyd
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
"""Render the toolbar icons from Resources/Icons/*.svg to the PNGs the app loads.

Each icon is drawn on a 24-unit grid, its art inside 1 to 23. It's rendered at every size the
toolbar draws it at, so no icon is resampled on screen: <Stem>-<px>-symbolic.png for 16, 24 and 32
px (and 48 and 64, their 2x), and 22 and 44 px cut from the 24 and 48 px renderings (the tool
switcher's size, the grid's 1-unit margin left off, so its lines stay on whole pixels). The
24 px rendering is also <Stem>-symbolic.png, the name older code and packaging look for.

Needs librsvg's GObject bindings (gir1.2-rsvg-2.0) and pycairo. Run it after editing an SVG and
commit the PNGs: the build doesn't render them.
"""

import os
import sys

import cairo
import gi

gi.require_version("Rsvg", "2.0")
from gi.repository import Rsvg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "Resources", "Icons")
OUTPUT = os.path.join(ROOT, "Resources")

# Pixel size -> (scale from the 24-unit grid, units cut from each edge).
SIZES = {
    16: (16 / 24, 0),
    22: (1, 1),
    24: (1, 0),
    32: (32 / 24, 0),
    44: (2, 1),
    48: (2, 0),
    64: (64 / 24, 0),
}


def render(handle, pixels, scale, margin):
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, pixels, pixels)
    context = cairo.Context(surface)
    context.scale(scale, scale)
    context.translate(-margin, -margin)
    viewport = Rsvg.Rectangle()
    viewport.x, viewport.y, viewport.width, viewport.height = 0, 0, 24, 24
    handle.render_document(context, viewport)
    return surface


def main():
    names = sorted(name for name in os.listdir(SOURCES) if name.endswith(".svg"))
    if not names:
        sys.exit("No SVGs in " + SOURCES)
    for name in names:
        stem = name[:-len(".svg")]
        handle = Rsvg.Handle.new_from_file(os.path.join(SOURCES, name))
        for pixels, (scale, margin) in SIZES.items():
            surface = render(handle, pixels, scale, margin)
            surface.write_to_png(os.path.join(OUTPUT, "%s-%d-symbolic.png" % (stem, pixels)))
            if pixels == 24:
                surface.write_to_png(os.path.join(OUTPUT, "%s-symbolic.png" % stem))
        print(stem)


if __name__ == "__main__":
    main()
