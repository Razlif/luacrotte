"""Deterministically stitch a source background into a rectangular tile grid."""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--columns", type=int, default=2)
    parser.add_argument("--rows", type=int, default=2)
    parser.add_argument("--trim-alpha", action="store_true")
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGBA")
    if args.trim_alpha:
        alpha = source.getchannel("A")
        bbox = alpha.getbbox()
        if bbox:
            source = source.crop(bbox)
    if args.columns < 1 or args.rows < 1:
        raise ValueError("rows and columns must be positive")

    output = Image.new(
        "RGBA",
        (source.width * args.columns, source.height * args.rows),
        (0, 0, 0, 0),
    )
    for row in range(args.rows):
        for column in range(args.columns):
            output.alpha_composite(source, (column * source.width, row * source.height))

    destination = Path(args.output)
    destination.parent.mkdir(parents=True, exist_ok=True)
    output.save(destination, "PNG")
    print(f"Saved {destination} ({output.width}x{output.height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
