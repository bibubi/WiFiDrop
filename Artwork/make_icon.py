"""生成 1024x1024 的 App 图标（纯标准库，无第三方依赖）。

用法: python3 Artwork/make_icon.py <输出路径.png>
"""

import math
import struct
import sys
import zlib

SIZE = 1024
CENTER_X = SIZE // 2
CENTER_Y = 730
ARCS = [(390, 74), (262, 72), (136, 70)]
DOT_RADIUS = 58
COLOR_START = (10, 110, 255)
COLOR_END = (0, 55, 170)


def png_chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def make_rows():
    inner_outer = [((r - w / 2.0) ** 2, (r + w / 2.0) ** 2) for r, w in ARCS]
    dot_limit = DOT_RADIUS * DOT_RADIUS
    rows = []

    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            t = (x * 0.35 + y * 0.65) / (SIZE - 1)
            red = int(COLOR_START[0] + (COLOR_END[0] - COLOR_START[0]) * t)
            green = int(COLOR_START[1] + (COLOR_END[1] - COLOR_START[1]) * t)
            blue = int(COLOR_START[2] + (COLOR_END[2] - COLOR_START[2]) * t)

            dx = x - CENTER_X
            dy = y - CENTER_Y
            distance_squared = dx * dx + dy * dy
            white = distance_squared <= dot_limit

            if not white and dy <= 0:
                for inner, outer in inner_outer:
                    if inner <= distance_squared <= outer:
                        angle = math.degrees(math.atan2(dy, dx))
                        if angle < 0:
                            angle += 360
                        white = 205 <= angle <= 335
                        break

            if white:
                row += b"\xff\xff\xff"
            else:
                row += bytes((red, green, blue))
        rows.append(row)
    return rows


def write_png(path):
    rows = make_rows()
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(raw, 9))
        + png_chunk(b"IEND", b"")
    )
    with open(path, "wb") as handle:
        handle.write(png)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: python3 Artwork/make_icon.py <output.png>")
        sys.exit(1)
    write_png(sys.argv[1])
    print("icon written:", sys.argv[1])
