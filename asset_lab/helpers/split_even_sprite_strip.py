"""Turn an evenly spaced transparent source strip into inspectable uniform frames.

The helper is deliberately deterministic: it divides the source width into equal
slots, crops each slot to its alpha content, centers that content on a fixed
canvas, and records a conventional Asset Lab sheet and GIF preview.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

HELPERS = Path(__file__).resolve().parent
sys.path.insert(0, str(HELPERS))

import manifest
from common import ANIMATION_GIFS_DIR, SPRITE_SHEETS_DIR, asset_folder, relative_to_asset_lab, version_tag


def alpha_box(image: Image.Image) -> tuple[int, int, int, int] | None:
    return image.getchannel("A").getbbox()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--type", default="effect", choices=("character", "prop", "background", "effect"))
    parser.add_argument("--source-image-version", type=int, default=1)
    parser.add_argument("--frame-count", type=int, required=True)
    parser.add_argument("--frame-size", type=int, default=128)
    parser.add_argument("--padding", type=int, default=8)
    parser.add_argument("--fps", type=int, default=8)
    parser.add_argument("--animation", default="variants")
    args = parser.parse_args()

    asset = manifest.find_asset(args.name)
    if asset is None or asset.get("type") != args.type:
        raise SystemExit(f"Asset not found: {args.type}/{args.name}")
    source = manifest.find_image_version(args.name, args.type, args.source_image_version)
    if source is None:
        raise SystemExit(f"Source image version not found: {args.source_image_version}")
    source_path = HELPERS.parent / source["path"]
    if not source_path.is_file():
        raise SystemExit(f"Source image is missing: {source_path}")

    folder = asset_folder(args.type, args.name)
    sheets = folder / SPRITE_SHEETS_DIR
    gifs = folder / ANIMATION_GIFS_DIR
    sheets.mkdir(parents=True, exist_ok=True)
    gifs.mkdir(parents=True, exist_ok=True)
    animation = args.animation.replace(" ", "_").lower()
    base = f"{args.name}__asset_lab_split__{animation}_from_image_{version_tag(args.source_image_version)}"
    sheet_path = sheets / f"{base}__v001.png"
    gif_path = gifs / f"{base}__v001.gif"

    with Image.open(source_path) as source_image:
        source_image = source_image.convert("RGBA")
        frames: list[Image.Image] = []
        frame_files: list[str] = []
        for index in range(args.frame_count):
            left = round(index * source_image.width / args.frame_count)
            right = round((index + 1) * source_image.width / args.frame_count)
            slot = source_image.crop((left, 0, right, source_image.height))
            box = alpha_box(slot)
            if box is None:
                raise SystemExit(f"Frame {index + 1} contains no visible pixels")
            content = slot.crop(box)
            maximum = args.frame_size - args.padding * 2
            scale = min(1, maximum / content.width, maximum / content.height)
            if scale < 1:
                content = content.resize((round(content.width * scale), round(content.height * scale)), Image.Resampling.LANCZOS)
            frame = Image.new("RGBA", (args.frame_size, args.frame_size), (0, 0, 0, 0))
            frame.alpha_composite(content, ((args.frame_size - content.width) // 2, (args.frame_size - content.height) // 2))
            frame_path = sheets / f"{base}__frame_{index + 1:03d}.png"
            frame.save(frame_path)
            frames.append(frame)
            frame_files.append(relative_to_asset_lab(frame_path))

    sheet = Image.new("RGBA", (args.frame_size * args.frame_count, args.frame_size), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (index * args.frame_size, 0))
    sheet.save(sheet_path)
    frames[0].save(gif_path, save_all=True, append_images=frames[1:], duration=max(1, round(1000 / args.fps)), loop=0, disposal=2)

    entry = {
        "id": gif_path.stem,
        "provider": "asset_lab_split",
        "name": animation,
        "version": 1,
        "source_image_version": args.source_image_version,
        "source_image_path": source["path"],
        "sheet_path": relative_to_asset_lab(sheet_path),
        "gif_path": relative_to_asset_lab(gif_path),
        "frame_files": frame_files,
        "frame_count": args.frame_count,
        "frame_width": args.frame_size,
        "frame_height": args.frame_size,
        "sheet_width": sheet.width,
        "sheet_height": sheet.height,
        "fps": args.fps,
        "status": "created_on_disk",
    }
    manifest.add_animation(args.name, entry, asset)
    print(f"Wrote {args.frame_count} frames: {relative_to_asset_lab(sheets)}")
    print(f"Wrote sprite sheet: {relative_to_asset_lab(sheet_path)}")
    print(f"Wrote GIF preview: {relative_to_asset_lab(gif_path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
