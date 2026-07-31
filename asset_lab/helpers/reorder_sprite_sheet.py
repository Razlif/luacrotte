"""Create a horizontal animation from selected cells in a grid sprite sheet."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_cell(value: str, rows: int, columns: int) -> tuple[int, int]:
    raw = value.strip().lower()
    if not (raw.startswith("r") and "c" in raw):
        raise ValueError(f"Invalid cell '{value}'. Use r1c1 notation.")
    row_text, column_text = raw[1:].split("c", 1)
    row, column = int(row_text), int(column_text)
    if not (1 <= row <= rows and 1 <= column <= columns):
        raise ValueError(f"Cell '{value}' is outside the {rows}x{columns} grid.")
    return row, column


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-sheet", type=Path, required=True)
    parser.add_argument("--output-stem", type=Path, required=True)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--columns", type=int, required=True)
    parser.add_argument("--frame-width", type=int, required=True)
    parser.add_argument("--frame-height", type=int, required=True)
    parser.add_argument("--order", nargs="+", required=True)
    parser.add_argument("--fps", type=int, default=8)
    args = parser.parse_args()

    from PIL import Image

    cells = [parse_cell(value, args.rows, args.columns) for value in args.order]
    with Image.open(args.source_sheet) as source:
        expected_size = (args.columns * args.frame_width, args.rows * args.frame_height)
        if source.size != expected_size:
            raise ValueError(f"Source sheet is {source.size}, expected {expected_size}.")
        frames = [
            source.crop(((column - 1) * args.frame_width, (row - 1) * args.frame_height,
                         column * args.frame_width, row * args.frame_height)).convert("RGBA")
            for row, column in cells
        ]

    args.output_stem.parent.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (args.frame_width * len(frames), args.frame_height), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (index * args.frame_width, 0))
    sheet_path = args.output_stem.with_suffix(".png")
    gif_path = args.output_stem.with_suffix(".gif")
    metadata_path = args.output_stem.with_suffix(".json")
    sheet.save(sheet_path)
    frames[0].save(gif_path, save_all=True, append_images=frames[1:],
                   duration=max(1, round(1000 / max(1, args.fps))), loop=0, disposal=2)
    metadata_path.write_text(json.dumps({
        "source_sheet": str(args.source_sheet),
        "source_grid": {"rows": args.rows, "columns": args.columns,
                        "frame_width": args.frame_width, "frame_height": args.frame_height},
        "frame_order": args.order,
        "frame_count": len(frames),
        "fps": args.fps,
        "output_sheet": str(sheet_path),
        "output_gif": str(gif_path),
    }, indent=2), encoding="utf-8")
    print(f"Created {len(frames)} ordered frames: {sheet_path}")
    print(f"Created GIF preview: {gif_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
