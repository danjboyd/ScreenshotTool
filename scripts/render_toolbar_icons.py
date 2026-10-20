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

Each icon is drawn on a 24-unit grid, its art inside 3 to 21. Only that middle 18 units is
rendered, so the glyph fills about 85% of the icon, as Fluent's and Adwaita's do. Drawn whole,
the grid left the glyph at about 62%, and 10 px in WinUITheme's 16 px toolbar icon. It's rendered
at every size the toolbar draws it at, so no icon is resampled on screen:
<Stem>-<px>-symbolic.png for 16, 22, 24 and 32 px, and 44, 48 and 64, their 2x. The 24 px
rendering is also <Stem>-symbolic.png, the name older code and packaging look for.

<Stem>-<px>.svg, when there is one, replaces <Stem>.svg at that size: a drawing hinted to that
size's pixels, still on the 24-unit grid.

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

SIZES = (16, 22, 24, 32, 44, 48, 64)
# The part of the 24-unit grid an icon shows: the 18 units in the middle.
MARGIN = 3
SHOWN = 24 - 2 * MARGIN


def render(handle, pixels):
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, pixels, pixels)
    context = cairo.Context(surface)
    context.scale(pixels / SHOWN, pixels / SHOWN)
    context.translate(-MARGIN, -MARGIN)
    viewport = Rsvg.Rectangle()
    viewport.x, viewport.y, viewport.width, viewport.height = 0, 0, 24, 24
    handle.render_document(context, viewport)
    return surface


def main():
    names = sorted(name for name in os.listdir(SOURCES) if name.endswith(".svg"))
    if not names:
        sys.exit("No SVGs in " + SOURCES)
    hinted = {"%s-%d.svg" % (name[:-len(".svg")], pixels) for name in names for pixels in SIZES}
    for name in names:
        if name in hinted:
            continue
        stem = name[:-len(".svg")]
        handle = Rsvg.Handle.new_from_file(os.path.join(SOURCES, name))
        for pixels in SIZES:
            override = os.path.join(SOURCES, "%s-%d.svg" % (stem, pixels))
            source = Rsvg.Handle.new_from_file(override) if os.path.exists(override) else handle
            surface = render(source, pixels)
            surface.write_to_png(os.path.join(OUTPUT, "%s-%d-symbolic.png" % (stem, pixels)))
            if pixels == 24:
                surface.write_to_png(os.path.join(OUTPUT, "%s-symbolic.png" % stem))
        print(stem)


if __name__ == "__main__":
    main()
