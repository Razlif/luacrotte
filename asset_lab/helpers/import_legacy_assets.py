"""Import explicitly reviewed legacy assets into Asset Lab.

Supports static PNGs and explicitly reviewed groups of separate PNG animation
frames. Original source paths remain in the manifest, metadata, and trace log.
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image

HELPERS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(HELPERS_DIR))

import manifest
from common import ASSET_LAB_DIR, LAB_ASSETS_DIR, asset_folder, ensure_asset_dirs, groups_from_asset, relative_to_asset_lab, write_json


PROVIDER = "legacy_motocrotte"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import reviewed legacy assets into Asset Lab."
    )
    parser.add_argument(
        "--mapping",
        required=True,
        type=Path,
        help="Path to a legacy mapping index.json.",
    )
    parser.add_argument(
        "--asset-id",
        help="Import one mapped asset.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the planned import without changing files or manifests.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Allow replacing an existing imported file and manifest record.",
    )
    return parser.parse_args()


def load_mapping(index_path: Path) -> tuple[dict[str, Any], list[dict[str, Any]], Path]:
    index_path = index_path.resolve()
    index = json.loads(index_path.read_text(encoding="utf-8"))
    if not isinstance(index, dict):
        raise ValueError("Mapping index must contain a JSON object.")

    source_root_value = index.get("source_root")
    if not source_root_value:
        raise ValueError("Mapping index is missing source_root.")
    source_root = (index_path.parent / source_root_value).resolve()
    if not source_root.is_dir():
        raise ValueError(f"Mapping source_root does not exist: {source_root}")

    assets: list[dict[str, Any]] = []
    for mapping_name in index.get("mapping_files", []):
        mapping_path = (index_path.parent / mapping_name).resolve()
        data = json.loads(mapping_path.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or not isinstance(data.get("assets"), list):
            raise ValueError(f"Mapping file must contain an assets list: {mapping_path}")
        assets.extend(data["assets"])
        for template in data.get("generated_assets", []):
            if not isinstance(template, dict):
                raise ValueError(f"Generated asset template must be an object: {mapping_path}")
            variants = template.get("variant_values", [])
            frames = template.get("frame_values", [])
            if not variants or not frames:
                raise ValueError(f"Generated asset template needs variant_values and frame_values: {mapping_path}")
            for variant in variants:
                asset = {key: value for key, value in template.items()
                         if key not in {"variant_values", "frame_values", "asset_id_template", "source_template"}}
                asset["asset_id"] = str(template["asset_id_template"]).format(variant=variant)
                asset["source_paths"] = [str(template["source_template"]).format(variant=variant, frame=frame)
                                          for frame in frames]
                assets.append(asset)

    return index, assets, source_root


def select_asset(assets: list[dict[str, Any]], asset_id: str | None) -> dict[str, Any]:
    if not asset_id:
        raise ValueError("The static-only importer requires --asset-id.")
    matches = [asset for asset in assets if asset.get("asset_id") == asset_id]
    if not matches:
        available = ", ".join(sorted(str(asset.get("asset_id")) for asset in assets))
        raise ValueError(f"Asset '{asset_id}' was not found in the mapping. Available: {available}")
    if len(matches) > 1:
        raise ValueError(f"Asset '{asset_id}' appears more than once in the mapping.")
    return matches[0]


def resolve_static_source(asset: dict[str, Any], source_root: Path) -> tuple[Path, str]:
    kind = asset.get("kind")
    if kind != "static":
        raise ValueError(
            f"Asset '{asset.get('asset_id')}' has kind '{kind}'. "
            "Use kind 'static' for a single PNG asset."
        )
    source_paths = asset.get("source_paths")
    if not isinstance(source_paths, list) or len(source_paths) != 1:
        raise ValueError("A static asset must have exactly one source_paths entry.")
    source_relative = str(source_paths[0])
    source = (source_root / source_relative).resolve()
    if not source.is_file():
        raise ValueError(f"Source file does not exist: {source}")
    if source.suffix.lower() != ".png":
        raise ValueError(f"Static legacy importer currently expects PNG files: {source}")
    return source, source_relative


def resolve_animation_sources(asset: dict[str, Any], source_root: Path) -> list[tuple[Path, str]]:
    if asset.get("kind") != "animation_frames":
        raise ValueError(
            f"Asset '{asset.get('asset_id')}' has kind '{asset.get('kind')}'. "
            "Use kind 'animation_frames' for separate PNG frames."
        )
    source_paths = asset.get("source_paths")
    if not isinstance(source_paths, list) or len(source_paths) < 2:
        raise ValueError("An animation_frames asset must have at least two source_paths entries.")

    resolved: list[tuple[Path, str]] = []
    size: tuple[int, int] | None = None
    for raw_path in source_paths:
        source_relative = str(raw_path)
        source = (source_root / source_relative).resolve()
        if not source.is_file():
            raise ValueError(f"Source file does not exist: {source}")
        if source.suffix.lower() != ".png":
            raise ValueError(f"Animation frame importer currently expects PNG files: {source}")
        with Image.open(source) as image:
            current_size = image.size
        if size is None:
            size = current_size
        elif current_size != size and not asset.get("target_frame_width"):
            raise ValueError(f"Animation frames must share dimensions: {source} is {current_size}, expected {size}")
        resolved.append((source, source_relative))
    return resolved


def resolve_sprite_sheet(asset: dict[str, Any], source_root: Path) -> tuple[Path, str, int, int, int]:
    if asset.get("kind") != "sprite_sheet":
        raise ValueError("A sprite sheet asset must have kind 'sprite_sheet'.")
    source_paths = asset.get("source_paths")
    frame_count = int(asset.get("frame_count", 0))
    if not isinstance(source_paths, list) or len(source_paths) != 1 or frame_count < 2:
        raise ValueError("A sprite_sheet asset needs one source path and frame_count >= 2.")
    source_relative = str(source_paths[0])
    source = (source_root / source_relative).resolve()
    if not source.is_file() or source.suffix.lower() != ".png":
        raise ValueError(f"Sprite sheet source must be an existing PNG: {source}")
    with Image.open(source) as image:
        frame_width = int(asset.get("frame_width") or math.ceil(image.width / frame_count))
        if frame_width * (frame_count - 1) >= image.width:
            raise ValueError(f"Sprite sheet frame_width {frame_width} does not fit {frame_count} frames: {source}")
        return source, source_relative, frame_count, frame_width, image.height


def build_import_plan(asset: dict[str, Any], source_root: Path) -> dict[str, Any]:
    asset_id = str(asset.get("asset_id", ""))
    asset_type = str(asset.get("type", ""))
    if not asset_id:
        raise ValueError("Mapped asset is missing asset_id.")
    if asset_type not in {"character", "prop", "background", "effect"}:
        raise ValueError(f"Unsupported Asset Lab type for '{asset_id}': {asset_type}")

    destination_folder = asset_folder(asset_type, asset_id)
    if asset.get("kind") == "static":
        source, source_relative = resolve_static_source(asset, source_root)
        destination_name = f"{asset_id}__{PROVIDER}__image__v001{source.suffix.lower()}"
        destination = destination_folder / "original_images" / destination_name
        with Image.open(source) as image:
            width, height = image.size
        return {"asset": asset, "asset_id": asset_id, "asset_type": asset_type, "source": source,
                "source_relative": source_relative, "destination_folder": destination_folder,
                "destination": destination, "width": width, "height": height, "kind": "static"}

    if asset.get("kind") == "sprite_sheet":
        source, source_relative, frame_count, frame_width, frame_height = resolve_sprite_sheet(asset, source_root)
        destination = destination_folder / "original_images" / f"{asset_id}__{PROVIDER}__sheet__v001.png"
        animation_name = str(asset.get("animation_name", "legacy_sheet"))
        with Image.open(source) as sheet:
            sheet_width = sheet.width
        return {"asset": asset, "asset_id": asset_id, "asset_type": asset_type, "source": source,
                "source_relative": source_relative, "destination_folder": destination_folder,
                "destination": destination, "width": sheet_width,
                "height": frame_height, "frame_count": frame_count, "frame_width": frame_width,
                "frame_height": frame_height, "animation_name": animation_name, "kind": "sprite_sheet",
                "gif_destination": destination_folder / "animation_gifs" /
                f"{asset_id}__{PROVIDER}__{animation_name}__v001.gif"}

    frames = resolve_animation_sources(asset, source_root)
    with Image.open(frames[0][0]) as image:
        width = int(asset.get("target_frame_width") or image.width)
        height = int(asset.get("target_frame_height") or image.height)
    animation_name = str(asset.get("animation_name", "legacy_cycle"))
    return {"asset": asset, "asset_id": asset_id, "asset_type": asset_type,
            "destination_folder": destination_folder, "frame_paths": frames,
            "frame_destinations": [destination_folder / "original_images" /
                                   f"{asset_id}__{PROVIDER}__frame_{i:03d}__{source.name}"
                                   for i, (source, _) in enumerate(frames, 1)],
            "sheet_destination": destination_folder / "sprite_sheets" /
            f"{asset_id}__{PROVIDER}__{animation_name}__v001.png",
            "gif_destination": destination_folder / "animation_gifs" /
            f"{asset_id}__{PROVIDER}__{animation_name}__v001.gif",
            "animation_name": animation_name, "width": width, "height": height,
            "kind": "animation_frames"}


def print_plan(plan: dict[str, Any], *, dry_run: bool) -> None:
    action = "Would import" if dry_run else "Importing"
    print(f"{action}: {plan['asset_id']}")
    print(f"  type:       {plan['asset_type']}")
    if plan["kind"] in {"static", "sprite_sheet"}:
        print(f"  source:     {plan['source_relative']}")
    else:
        print(f"  frames:     {len(plan['frame_paths'])}")
        print("  sources:    " + ", ".join(source_relative for _, source_relative in plan["frame_paths"]))
    print(f"  dimensions: {plan['width']}x{plan['height']}")
    if plan["kind"] == "static":
        print(f"  destination: {relative_to_asset_lab(plan['destination'])}")
    elif plan["kind"] == "sprite_sheet":
        print(f"  frames:     {plan['frame_count']} ({plan['frame_width']}x{plan['frame_height']} each)")
        print(f"  gif:        {relative_to_asset_lab(plan['gif_destination'])}")
    else:
        print(f"  sheet:      {relative_to_asset_lab(plan['sheet_destination'])}")
        print(f"  gif:        {relative_to_asset_lab(plan['gif_destination'])}")


def write_import(plan: dict[str, Any], *, force: bool) -> None:
    destination_folder: Path = plan["destination_folder"]
    existing_record = manifest.find_asset(plan["asset_id"], plan["asset_type"])
    destinations = ([plan["destination"], plan["gif_destination"]] if plan["kind"] == "sprite_sheet" else
                    [plan["destination"]] if plan["kind"] == "static" else
                    plan["frame_destinations"] + [plan["sheet_destination"], plan["gif_destination"]])
    if (any(path.exists() for path in destinations) or existing_record is not None) and not force:
        raise ValueError(
            f"Asset '{plan['asset_id']}' is already imported or partially present. "
            "Use --force only after inspecting it."
        )

    ensure_asset_dirs(destination_folder)
    now = datetime.now(timezone.utc).isoformat()
    images = []
    animations = []
    if plan["kind"] in {"static", "sprite_sheet"}:
        shutil.copy2(plan["source"], plan["destination"])
        images.append({"id": f"{plan['asset_id']}__{PROVIDER}__image__v001", "provider": PROVIDER,
                       "version": 1, "path": relative_to_asset_lab(plan["destination"]),
                       "width": plan["width"], "height": plan["height"], "source_project": "motorcrotte",
                       "source_path": plan["source_relative"], "source_role": plan["asset"].get("source_role"),
                       "source_references": plan["asset"].get("source_references", [])})
        if plan["kind"] == "sprite_sheet":
            with Image.open(plan["destination"]) as sheet:
                frames = []
                for i in range(plan["frame_count"]):
                    left = i * plan["frame_width"]
                    right = min(left + plan["frame_width"], sheet.width)
                    frame = sheet.crop((left, 0, right, plan["frame_height"])).convert("RGBA")
                    if frame.width != plan["frame_width"]:
                        padded = Image.new("RGBA", (plan["frame_width"], plan["frame_height"]), (0, 0, 0, 0))
                        padded.alpha_composite(frame, (0, 0))
                        frame = padded
                    frames.append(frame)
            frames[0].save(plan["gif_destination"], save_all=True, append_images=frames[1:],
                           duration=int(plan["asset"].get("frame_duration_ms", 80)), loop=0, disposal=2)
            animations.append({"id": f"{plan['asset_id']}__{PROVIDER}__{plan['animation_name']}__v001",
                               "provider": PROVIDER, "name": plan["animation_name"], "version": 1,
                               "source_image_version": 1, "sheet_path": relative_to_asset_lab(plan["destination"]),
                               "gif_path": relative_to_asset_lab(plan["gif_destination"]),
                               "frame_count": plan["frame_count"], "frame_width": plan["frame_width"],
                               "frame_height": plan["frame_height"], "sheet_width": plan["width"],
                               "sheet_height": plan["height"], "fps": round(1000 / int(plan["asset"].get("frame_duration_ms", 80)), 2),
                               "frame_duration_ms": int(plan["asset"].get("frame_duration_ms", 80)),
                               "source_paths": plan["asset"].get("source_paths", []),
                               "source_references": plan["asset"].get("source_references", [])})
    else:
        frame_images = []
        for index, ((source, source_relative), destination) in enumerate(zip(plan["frame_paths"], plan["frame_destinations"]), 1):
            shutil.copy2(source, destination)
            with Image.open(source) as image:
                frame = image.convert("RGBA")
                target_size = (int(plan["asset"].get("target_frame_width", plan["width"])),
                               int(plan["asset"].get("target_frame_height", plan["height"])))
                if frame.size != target_size:
                    padded = Image.new("RGBA", target_size, (0, 0, 0, 0))
                    padded.alpha_composite(frame, (0, 0))
                    frame = padded
                frame_images.append(frame)
            images.append({"id": f"{plan['asset_id']}__{PROVIDER}__frame_{index:03d}", "provider": PROVIDER,
                           "version": index, "frame_index": index, "path": relative_to_asset_lab(destination),
                           "width": plan["width"], "height": plan["height"], "source_project": "motorcrotte",
                           "source_path": source_relative, "source_role": plan["asset"].get("source_role"),
                           "source_references": plan["asset"].get("source_references", []),
                           "source_frame_count": len(plan["frame_paths"])})
        sheet = Image.new("RGBA", (plan["width"] * len(frame_images), plan["height"]), (0, 0, 0, 0))
        for index, frame in enumerate(frame_images):
            sheet.alpha_composite(frame, (index * plan["width"], 0))
        sheet.save(plan["sheet_destination"])
        duration_ms = int(plan["asset"].get("frame_duration_ms", 80))
        frame_images[0].save(plan["gif_destination"], save_all=True, append_images=frame_images[1:],
                             duration=duration_ms, loop=0, disposal=2)
        animations.append({"id": f"{plan['asset_id']}__{PROVIDER}__{plan['animation_name']}__v001",
                           "provider": PROVIDER, "name": plan["animation_name"], "version": 1,
                           "source_image_version": 1,
                           "sheet_path": relative_to_asset_lab(plan["sheet_destination"]),
                           "gif_path": relative_to_asset_lab(plan["gif_destination"]),
                           "frame_count": len(frame_images), "frame_width": plan["width"],
                           "frame_height": plan["height"], "sheet_width": sheet.width,
                           "sheet_height": sheet.height, "fps": round(1000 / duration_ms, 2),
                           "frame_duration_ms": duration_ms, "source_paths": plan["asset"].get("source_paths", []),
                           "source_references": plan["asset"].get("source_references", [])})
    record = {
        "id": plan["asset_id"],
        "type": plan["asset_type"],
        "domain": plan["asset"].get("domain"),
        "subcategory": plan["asset"].get("subcategory"),
        "size_class": plan["asset"].get("size_class"),
        "groups": groups_from_asset(plan["asset"]),
        "folder": relative_to_asset_lab(destination_folder),
        "images": images,
        "animations": animations,
        "source_project": "motorcrotte",
        "source_paths": plan["asset"].get("source_paths", []),
        "status": plan["asset"].get("status", "unclassified"),
        "imported_at": now,
    }
    manifest.upsert_asset_record(record)

    metadata = {
        "asset_id": plan["asset_id"],
        "type": plan["asset_type"],
        "provider": PROVIDER,
        "source_project": "motorcrotte",
        "domain": plan["asset"].get("domain"),
        "subcategory": plan["asset"].get("subcategory"),
        "size_class": plan["asset"].get("size_class"),
        "groups": groups_from_asset(plan["asset"]),
        "source_paths": plan["asset"].get("source_paths", []),
        "status": plan["asset"].get("status", "unclassified"),
        "source_role": plan["asset"].get("source_role"),
        "source_references": plan["asset"].get("source_references", []),
    }
    write_json(destination_folder / "metadata.json", metadata)
    trace_path = destination_folder / "trace.jsonl"
    trace_path.parent.mkdir(parents=True, exist_ok=True)
    with trace_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"ts": now, "event": "legacy_import", **metadata}, ensure_ascii=False) + "\n")


def main() -> int:
    args = parse_args()
    try:
        _, assets, source_root = load_mapping(args.mapping)
        asset = select_asset(assets, args.asset_id)
        plan = build_import_plan(asset, source_root)
        print_plan(plan, dry_run=args.dry_run)
        if not args.dry_run:
            write_import(plan, force=args.force)
            print("Import complete.")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"Import failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
