#!/usr/bin/env python3
"""生成设置面板图标（纯标准库，无需 Pillow）。

输出：
    SplitJumpPrefs/Resources/icon.png     29x29
    SplitJumpPrefs/Resources/icon@2x.png  58x58
"""

import os
import struct
import zlib

BG = (83, 74, 183)      # #534AB7
FG = (255, 255, 255)
DOT = (250, 199, 117)   # #FAC775

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "SplitJumpPrefs", "Resources")


def write_png(path, w, h, pixels):
    """pixels: list of rows, each row list of (r,g,b,a)"""
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter type 0
        for (r, g, b, a) in row:
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")

    with open(path, "wb") as f:
        f.write(png)


def render(size):
    """在 size x size 画布上画：圆角底 + 三条列表项 + 一个分支点"""
    s = float(size)
    radius = s * 0.22
    px = [[(0, 0, 0, 0) for _ in range(size)] for _ in range(size)]

    def in_round_rect(x, y):
        cx = min(max(x, radius), s - radius)
        cy = min(max(y, radius), s - radius)
        dx, dy = x - cx, y - cy
        return dx * dx + dy * dy <= radius * radius

    for y in range(size):
        for x in range(size):
            if in_round_rect(x + 0.5, y + 0.5):
                px[y][x] = BG + (255,)

    def rect(x0, y0, x1, y1, color):
        for y in range(max(0, int(y0)), min(size, int(round(y1)))):
            for x in range(max(0, int(x0)), min(size, int(round(x1)))):
                px[y][x] = color + (255,)

    def dot(cx, cy, r, color):
        for y in range(size):
            for x in range(size):
                if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                    if px[y][x][3] == 255:
                        px[y][x] = color + (255,)

    bar_h = max(1.6, s * 0.075)
    rows = [0.30, 0.50, 0.70]
    for i, ry in enumerate(rows):
        y = s * ry
        # 左侧圆点 + 右侧长条，模拟「可选项列表」
        dot(s * 0.30, y, max(1.4, s * 0.062), DOT if i == 0 else FG)
        rect(s * 0.42, y - bar_h / 2.0, s * 0.76, y + bar_h / 2.0, FG)

    # 右上角分支箭头（跳转语义）
    rect(s * 0.62, s * 0.16, s * 0.80, s * 0.16 + bar_h, FG)
    rect(s * 0.76, s * 0.16, s * 0.80, s * 0.30, FG)

    return px


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, size in (("icon.png", 29), ("icon@2x.png", 58)):
        path = os.path.join(OUT_DIR, name)
        write_png(path, size, size, render(size))
        print("wrote", path, os.path.getsize(path), "bytes")


if __name__ == "__main__":
    main()
