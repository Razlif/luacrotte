"""Generate every deterministic eight-direction variant from a reviewed grid."""

from __future__ import annotations

import argparse
import itertools
import json
from pathlib import Path
from typing import Any


CANONICAL_DIRECTIONS = [
    "front", "down_right", "right", "up_right",
    "back", "up_left", "left", "down_left",
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-sheet", type=Path, required=True)
    parser.add_argument("--review", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--asset-id-prefix", default="luacrotte_hero_motorcycle_direction_set")
    parser.add_argument("--group", default="characters/hero/motorcycle_direction_sets")
    parser.add_argument("--fps", type=int, default=8)
    args = parser.parse_args()

    from PIL import Image

    review: dict[str, Any] = json.loads(args.review.read_text(encoding="utf-8"))
    grid = review["grid"]
    source = Image.open(args.source_sheet).convert("RGBA")
    frame_width = int(grid["frame_width"])
    frame_height = int(grid["frame_height"])
    rows = int(grid["rows"])
    columns = int(grid["columns"])
    if source.size != (columns * frame_width, rows * frame_height):
        raise ValueError(f"Source sheet is {source.size}, expected {(columns * frame_width, rows * frame_height)}.")

    choices = {direction: review["summary"]["diagonal"][direction] for direction in
               ("down_right", "up_right", "up_left", "down_left")}
    fixed = {direction: review["summary"]["cardinal"][direction][0] for direction in
             ("front", "right", "back", "left")}
    variation_rows = []
    for number, selected_diagonals in enumerate(itertools.product(
        choices["down_right"], choices["up_right"], choices["up_left"], choices["down_left"]
    ), start=1):
        selected = dict(fixed)
        selected.update(dict(zip(("down_right", "up_right", "up_left", "down_left"), selected_diagonals)))
        frame_order = [selected[direction] for direction in CANONICAL_DIRECTIONS]
        asset_id = f"{args.asset_id_prefix}_v{number:03d}"
        variation_dir = args.output_root / asset_id
        variation_dir.mkdir(parents=True, exist_ok=True)
        stem = variation_dir / asset_id
        frames = []
        for cell in frame_order:
            row, column = int(cell[1]), int(cell.split("c", 1)[1])
            frames.append(source.crop(((column - 1) * frame_width, (row - 1) * frame_height,
                                       column * frame_width, row * frame_height)))
        sheet = Image.new("RGBA", (frame_width * len(frames), frame_height), (0, 0, 0, 0))
        for index, frame in enumerate(frames):
            sheet.alpha_composite(frame, (index * frame_width, 0))
        sheet_path = stem.with_suffix(".png")
        gif_path = stem.with_suffix(".gif")
        metadata_path = stem.with_suffix(".json")
        sheet.save(sheet_path)
        frames[0].save(gif_path, save_all=True, append_images=frames[1:],
                       duration=max(1, round(1000 / max(1, args.fps))), loop=0, disposal=2)
        metadata = {
            "asset_id": asset_id,
            "source_sheet": str(args.source_sheet),
            "source_review": str(args.review),
            "group": args.group,
            "directions": CANONICAL_DIRECTIONS,
            "frame_order": frame_order,
            "selected_by_direction": selected,
            "frame_count": len(frame_order),
            "frame_width": frame_width,
            "frame_height": frame_height,
            "fps": args.fps,
        }
        metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
        variation_rows.append({"asset_id": asset_id, "variation": number, "frame_order": frame_order,
                               "selected_by_direction": selected})

    index_path = args.output_root / "index.json"
    index_path.write_text(json.dumps({
        "source_sheet": str(args.source_sheet),
        "source_review": str(args.review),
        "group": args.group,
        "directions": CANONICAL_DIRECTIONS,
        "variation_count": len(variation_rows),
        "variations": variation_rows,
    }, indent=2), encoding="utf-8")

    # Register each variation as its own browser asset.
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import manifest
    data = manifest.load_manifest()
    assets = data.setdefault("assets", [])
    for row in variation_rows:
        asset_id = row["asset_id"]
        variation = row["variation"]
        folder = args.output_root / asset_id
        relative_folder = folder.as_posix().replace("asset_lab/", "")
        relative_base = (folder / asset_id).as_posix().replace("asset_lab/", "")
        entry = {
            "id": asset_id + "__animation",
            "provider": "asset_lab_reorder",
            "name": "motorcycle_direction_set",
            "version": 1,
            "source_image_version": 3,
            "sheet_path": relative_base + ".png",
            "gif_path": relative_base + ".gif",
            "provider_metadata_path": relative_base + ".json",
            "frame_order": row["frame_order"],
            "frame_labels": CANONICAL_DIRECTIONS,
            "frame_count": 8,
            "frame_width": frame_width,
            "frame_height": frame_height,
            "sheet_width": frame_width * 8,
            "sheet_height": frame_height,
            "fps": args.fps,
            "loop": True,
            "status": "created_on_disk",
        }
        source_image = {
            "id": asset_id + "__source__image__v003",
            "provider": "derived_source",
            "version": 3,
            "path": "lab_assets/characters/luacrotte_hero_omni/original_images/luacrotte_hero_omni__self__image__v003.png",
            "width": 400,
            "height": 400,
            "source_asset_id": "luacrotte_hero_omni",
            "status": "created_on_disk",
        }
        record = next((asset for asset in assets if asset.get("id") == asset_id), None)
        if record is None:
            record = {"id": asset_id, "type": "character", "folder": relative_folder,
                      "groups": [args.group], "images": [source_image], "animations": [],
                      "created_at": manifest.now_stamp()}
            assets.append(record)
        record["folder"] = relative_folder
        record["groups"] = [args.group]
        record["images"] = [source_image]
        record["animations"] = [entry]
        record["updated_at"] = manifest.now_stamp()
    manifest.save_manifest(data)
    print(f"Generated and registered {len(variation_rows)} deterministic direction sets.")
    print(f"Index: {index_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
