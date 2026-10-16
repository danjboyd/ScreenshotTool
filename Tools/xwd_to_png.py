"""xwd_to_png.py <in.xwd> <out.png> [left right top bottom]: a 32-bit (ARGB) window's own pixels as
an RGBA PNG, its alpha unpremultiplied, cropped by the given insets (a theme's shadow)."""
import struct
import sys
import zlib


def read_xwd(path):
    data = open(path, "rb").read()
    fields = struct.unpack(">25I", data[:100])
    (header_size, _version, _format, depth, width, height, _xoff, byte_order, _unit, _bit_order,
     _pad, bits_per_pixel, bytes_per_line, _class, red_mask, green_mask, blue_mask, _bits_rgb,
     _cmap, ncolors) = fields[:20]
    if depth != 32 or bits_per_pixel != 32:
        sys.exit(f"xwd2png: not a 32-bit window (depth {depth}, {bits_per_pixel} bpp)")
    offset = header_size + ncolors * 12
    endian = "<" if byte_order == 0 else ">"
    shifts = {mask: (mask & -mask).bit_length() - 1 for mask in (red_mask, green_mask, blue_mask)}
    alpha_mask = 0xFFFFFFFF & ~(red_mask | green_mask | blue_mask)
    alpha_shift = (alpha_mask & -alpha_mask).bit_length() - 1
    rows = []
    for y in range(height):
        start = offset + y * bytes_per_line
        pixels = struct.unpack(f"{endian}{width}I", data[start:start + width * 4])
        row = bytearray()
        for p in pixels:
            a = (p & alpha_mask) >> alpha_shift
            r, g, b = ((p & m) >> shifts[m] for m in (red_mask, green_mask, blue_mask))
            if a == 0:
                row += bytes((0, 0, 0, 0))
            else:
                # X's ARGB visuals are premultiplied.
                row += bytes((min(255, r * 255 // a), min(255, g * 255 // a), min(255, b * 255 // a), a))
        rows.append(row)
    return width, height, rows


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def main():
    width, height, rows = read_xwd(sys.argv[1])
    left, right, top, bottom = (int(v) for v in (sys.argv[3:7] if len(sys.argv) >= 7 else (0, 0, 0, 0)))
    rows = [row[left * 4:(width - right) * 4] for row in rows[top:height - bottom]]
    write_png(sys.argv[2], width - left - right, height - top - bottom, rows)


if __name__ == "__main__":
    main()
