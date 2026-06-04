#!/usr/bin/env python3
"""Generate SD-WAN app icons without external image dependencies."""

from __future__ import annotations

import json
import math
import os
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MASTER_SIZE = 1024


def blend(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def put_pixel(buf: bytearray, size: int, x: int, y: int, color: tuple[int, int, int, int]) -> None:
    if x < 0 or y < 0 or x >= size or y >= size:
        return
    i = (y * size + x) * 4
    alpha = color[3] / 255.0
    inv = 1.0 - alpha
    buf[i] = round(color[0] * alpha + buf[i] * inv)
    buf[i + 1] = round(color[1] * alpha + buf[i + 1] * inv)
    buf[i + 2] = round(color[2] * alpha + buf[i + 2] * inv)
    buf[i + 3] = 255


def point_in_polygon(x: float, y: float, points: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(points) - 1
    for i, point in enumerate(points):
        xi, yi = point
        xj, yj = points[j]
        if (yi > y) != (yj > y):
            cross_x = (xj - xi) * (y - yi) / (yj - yi + 1e-9) + xi
            if x < cross_x:
                inside = not inside
        j = i
    return inside


def fill_polygon(
    buf: bytearray,
    size: int,
    points: list[tuple[float, float]],
    color: tuple[int, int, int, int],
) -> None:
    scaled = [(x * size, y * size) for x, y in points]
    min_x = max(0, math.floor(min(x for x, _ in scaled)))
    max_x = min(size - 1, math.ceil(max(x for x, _ in scaled)))
    min_y = max(0, math.floor(min(y for _, y in scaled)))
    max_y = min(size - 1, math.ceil(max(y for _, y in scaled)))
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            if point_in_polygon(x + 0.5, y + 0.5, scaled):
                put_pixel(buf, size, x, y, color)


def distance_to_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx = bx - ax
    dy = by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def draw_line(
    buf: bytearray,
    size: int,
    start: tuple[float, float],
    end: tuple[float, float],
    radius: float,
    color: tuple[int, int, int, int],
) -> None:
    ax, ay = start[0] * size, start[1] * size
    bx, by = end[0] * size, end[1] * size
    r = radius * size
    min_x = max(0, math.floor(min(ax, bx) - r - 1))
    max_x = min(size - 1, math.ceil(max(ax, bx) + r + 1))
    min_y = max(0, math.floor(min(ay, by) - r - 1))
    max_y = min(size - 1, math.ceil(max(ay, by) + r + 1))
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            d = distance_to_segment(x + 0.5, y + 0.5, ax, ay, bx, by)
            if d <= r:
                edge = max(0.0, min(1.0, r - d))
                put_pixel(buf, size, x, y, (color[0], color[1], color[2], round(color[3] * edge)))


def draw_circle(
    buf: bytearray,
    size: int,
    center: tuple[float, float],
    radius: float,
    color: tuple[int, int, int, int],
) -> None:
    cx, cy = center[0] * size, center[1] * size
    r = radius * size
    min_x = max(0, math.floor(cx - r - 1))
    max_x = min(size - 1, math.ceil(cx + r + 1))
    min_y = max(0, math.floor(cy - r - 1))
    max_y = min(size - 1, math.ceil(cy + r + 1))
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            d = math.hypot((x + 0.5) - cx, (y + 0.5) - cy)
            if d <= r:
                edge = max(0.0, min(1.0, r - d))
                put_pixel(buf, size, x, y, (color[0], color[1], color[2], round(color[3] * edge)))


def make_master(size: int = MASTER_SIZE) -> bytearray:
    buf = bytearray(size * size * 4)
    top = (31, 102, 238)
    bottom = (19, 184, 166)
    for y in range(size):
        t = y / (size - 1)
        for x in range(size):
            radial = max(0.0, 1.0 - math.hypot((x / size) - 0.24, (y / size) - 0.2) / 0.72)
            i = (y * size + x) * 4
            buf[i] = min(255, blend(top[0], bottom[0], t) + round(30 * radial))
            buf[i + 1] = min(255, blend(top[1], bottom[1], t) + round(34 * radial))
            buf[i + 2] = min(255, blend(top[2], bottom[2], t) + round(18 * radial))
            buf[i + 3] = 255

    shadow = [(0.5, 0.20), (0.74, 0.31), (0.69, 0.64), (0.5, 0.82), (0.31, 0.64), (0.26, 0.31)]
    fill_polygon(buf, size, [(x + 0.018, y + 0.026) for x, y in shadow], (11, 31, 68, 54))
    fill_polygon(buf, size, shadow, (244, 249, 255, 255))
    inner = [(0.5, 0.30), (0.65, 0.37), (0.62, 0.58), (0.5, 0.70), (0.38, 0.58), (0.35, 0.37)]
    fill_polygon(buf, size, inner, (33, 101, 237, 255))

    draw_line(buf, size, (0.42, 0.47), (0.56, 0.42), 0.018, (219, 252, 243, 255))
    draw_line(buf, size, (0.56, 0.42), (0.61, 0.56), 0.018, (219, 252, 243, 255))
    draw_circle(buf, size, (0.42, 0.47), 0.043, (255, 255, 255, 255))
    draw_circle(buf, size, (0.56, 0.42), 0.043, (255, 255, 255, 255))
    draw_circle(buf, size, (0.61, 0.56), 0.043, (255, 255, 255, 255))
    draw_circle(buf, size, (0.42, 0.47), 0.022, (20, 184, 166, 255))
    draw_circle(buf, size, (0.56, 0.42), 0.022, (37, 99, 235, 255))
    draw_circle(buf, size, (0.61, 0.56), 0.022, (20, 184, 166, 255))
    return buf


def resize_bilinear(src: bytearray, src_size: int, dst_size: int) -> bytearray:
    if src_size == dst_size:
        return bytearray(src)
    dst = bytearray(dst_size * dst_size * 4)
    scale = src_size / dst_size
    for y in range(dst_size):
        sy = (y + 0.5) * scale - 0.5
        y0 = max(0, min(src_size - 1, math.floor(sy)))
        y1 = max(0, min(src_size - 1, y0 + 1))
        ty = sy - y0
        for x in range(dst_size):
            sx = (x + 0.5) * scale - 0.5
            x0 = max(0, min(src_size - 1, math.floor(sx)))
            x1 = max(0, min(src_size - 1, x0 + 1))
            tx = sx - x0
            out = (y * dst_size + x) * 4
            for c in range(4):
                p00 = src[(y0 * src_size + x0) * 4 + c]
                p10 = src[(y0 * src_size + x1) * 4 + c]
                p01 = src[(y1 * src_size + x0) * 4 + c]
                p11 = src[(y1 * src_size + x1) * 4 + c]
                top = p00 * (1 - tx) + p10 * tx
                bottom = p01 * (1 - tx) + p11 * tx
                dst[out + c] = round(top * (1 - ty) + bottom * ty)
    return dst


def png_bytes(width: int, height: int, rgba: bytearray) -> bytes:
    def chunk(name: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data) & 0xFFFFFFFF)

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(rgba[y * stride : (y + 1) * stride])
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def write_png(path: Path, size: int, rgba: bytearray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png_bytes(size, size, rgba))


def write_icon(path: Path, images: list[tuple[int, bytes]]) -> None:
    header = struct.pack("<HHH", 0, 1, len(images))
    entries = bytearray()
    payload = bytearray()
    offset = 6 + len(images) * 16
    for size, data in images:
        entries.extend(
            struct.pack(
                "<BBBBHHII",
                0 if size == 256 else size,
                0 if size == 256 else size,
                0,
                0,
                1,
                32,
                len(data),
                offset,
            )
        )
        payload.extend(data)
        offset += len(data)
    path.write_bytes(header + bytes(entries) + bytes(payload))


def icon_size(image: dict[str, str]) -> int:
    logical = float(image["size"].split("x", 1)[0])
    scale = int(image["scale"].removesuffix("x"))
    return round(logical * scale)


def main() -> None:
    master = make_master()
    cache: dict[int, bytearray] = {}

    def image(size: int) -> bytearray:
        if size not in cache:
            cache[size] = resize_bilinear(master, MASTER_SIZE, size)
        return cache[size]

    def generate_appicon_set(path: Path) -> None:
        contents = json.loads((path / "Contents.json").read_text())
        for item in contents["images"]:
            filename = item.get("filename")
            if not filename:
                continue
            size = icon_size(item)
            write_png(path / filename, size, image(size))

    generate_appicon_set(ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset")
    generate_appicon_set(ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset")

    for directory, size in {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }.items():
        write_png(ROOT / f"android/app/src/main/res/{directory}/ic_launcher.png", size, image(size))

    for path, size in {
        "web/favicon.png": 16,
        "web/icons/Icon-192.png": 192,
        "web/icons/Icon-maskable-192.png": 192,
        "web/icons/Icon-512.png": 512,
        "web/icons/Icon-maskable-512.png": 512,
    }.items():
        write_png(ROOT / path, size, image(size))

    ico_images = []
    for size in [16, 24, 32, 48, 64, 128, 256]:
        ico_images.append((size, png_bytes(size, size, image(size))))
    write_icon(ROOT / "windows/runner/resources/app_icon.ico", ico_images)


if __name__ == "__main__":
    os.chdir(ROOT)
    main()
