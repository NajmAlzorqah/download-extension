#!/usr/bin/env python3
"""Generate the Najm Downloader toolbar/extension icons as PNGs.

Dependency-free: draws a rounded terracotta square (matching the popup
accent `#b5562f`) with a white download arrow into a 128px RGBA grid
(4x supersampled) and writes PNGs by hand.
"""
import struct
import zlib
import pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "extension" / "icons"

S = 128
ACCENT = (181, 86, 47)
CORNER = 26


def rounded(rx, ry, r):
    if r <= rx <= S - r or r <= ry <= S - r:
        return True
    for cx, cy in ((r, r), (S - r, r), (r, S - r), (S - r, S - r)):
        if (rx - cx) ** 2 + (ry - cy) ** 2 <= r * r:
            return True
    return False


def arrow(rx, ry):
    # Shaft
    if 52 <= rx <= 76 and 40 <= ry <= 64:
        return True
    # Triangular head from y=56 widening down to y=96
    if ry < 56:
        return False
    t = (ry - 56) / 40.0
    half = 8 + t * 40
    return abs(rx - 64) <= half


def sample(x, y):
    """Supersample 4x4; return (white:bool, alpha:float)."""
    white = 0
    blue = 0
    for oy in (0.125, 0.375, 0.625, 0.875):
        for ox in (0.125, 0.375, 0.625, 0.875):
            sx, sy = x + ox, y + oy
            if arrow(sx, sy):
                white += 1
            elif rounded(sx, sy, CORNER):
                blue += 1
    return white > 0, (white + blue) / 16.0


def png(size: int) -> bytes:
    # Draw at 128 and scale down by integer nearest-neighbour for simplicity.
    grid = [[(False, 0.0)] * S for _ in range(S)]
    for y in range(S):
        for x in range(S):
            grid[y][x] = sample(x, y)

    rgba = bytearray()
    for cy in range(size):
        for cx in range(size):
            sx = int(cx * S / size)
            sy = int(cy * S / size)
            white, a = grid[sy][sx]
            rgb = (255, 255, 255) if white else ACCENT
            rgba += bytes((int(rgb[0] * a), int(rgb[1] * a), int(rgb[2] * a), int(a * 255)))

    rows = b"".join(b"\x00" + bytes(rgba[y * size * 4:(y * size + size) * 4]) for y in range(size))

    def chunk(tag, data):
        c = tag + data
        return (struct.pack(">I", len(data)) + c
                + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(rows, 9))
            + chunk(b"IEND", b""))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for s in (16, 48, 128):
        data = png(s)
        path = OUT / f"icon-{s}.png"
        path.write_bytes(data)
        print(f"wrote {path} ({len(data)} bytes)")


if __name__ == "__main__":
    main()