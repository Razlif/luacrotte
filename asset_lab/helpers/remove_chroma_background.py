"""Remove a connected flat chroma background from pixel-art PNG/GIF files."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path


def remove_connected_color(image, target=(128, 128, 128), tolerance=10):
    image = image.convert("RGBA")
    pixels = image.load()
    width, height = image.size

    def matches(x, y):
        r, g, b, _ = pixels[x, y]
        return max(abs(r - target[0]), abs(g - target[1]), abs(b - target[2])) <= tolerance

    queue = deque()
    visited = set()
    for x in range(width):
        queue.extend(((x, 0), (x, height - 1)))
    for y in range(height):
        queue.extend(((0, y), (width - 1, y)))

    while queue:
        x, y = queue.popleft()
        if (x, y) in visited or not (0 <= x < width and 0 <= y < height) or not matches(x, y):
            continue
        visited.add((x, y))
        r, g, b, _ = pixels[x, y]
        pixels[x, y] = (r, g, b, 0)
        queue.extend(((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)))
    return image


def process(path: Path, tolerance: int) -> None:
    from PIL import Image

    with Image.open(path) as source:
        frames = []
        try:
            while True:
                frames.append(remove_connected_color(source.copy(), tolerance=tolerance))
                source.seek(source.tell() + 1)
        except EOFError:
            pass
        if not frames:
            frames = [remove_connected_color(source, tolerance=tolerance)]
        if path.suffix.lower() == ".gif":
            duration = source.info.get("duration", 125)
            frames[0].save(path, save_all=True, append_images=frames[1:], duration=duration,
                            loop=0, disposal=2)
        else:
            frames[0].save(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--tolerance", type=int, default=10)
    args = parser.parse_args()
    for path in args.paths:
        process(path, args.tolerance)
        print(f"Removed connected chroma background: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
