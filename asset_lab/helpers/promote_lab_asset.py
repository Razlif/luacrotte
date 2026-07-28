"""Promote selected Asset Lab files into the current Love2D runtime set."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
import sys
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

HELPERS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(HELPERS_DIR))

from common import TYPE_FOLDERS, groups_from_asset, read_json, slugify, type_folder, write_json


PROMOTED_STATE_RELATIVE = Path("game_data") / "promoted_assets.json"
RUNTIME_MANIFEST_RELATIVE = Path("game_data") / "asset_manifest.lua"
MEDIA_ASSETS_RELATIVE = Path("media_assets")


class PromotionError(ValueError):
    """An expected, actionable promotion failure."""


def now_stamp() -> str:
    return datetime.now().isoformat(timespec="seconds")


def project_paths(project_root: Path) -> tuple[Path, Path, Path, Path]:
    root = project_root.resolve()
    return (
        root / "asset_lab" / "manifest.json",
        root / PROMOTED_STATE_RELATIVE,
        root / RUNTIME_MANIFEST_RELATIVE,
        root / MEDIA_ASSETS_RELATIVE,
    )


def load_source_manifest(project_root: Path) -> dict[str, Any]:
    source_path, _, _, _ = project_paths(project_root)
    data = read_json(source_path, {})
    if not isinstance(data, dict) or not isinstance(data.get("assets"), list):
        raise PromotionError(f"Invalid Asset Lab manifest: {source_path}")
    return data


def load_promoted_state(project_root: Path) -> dict[str, Any]:
    _, state_path, _, _ = project_paths(project_root)
    data = read_json(state_path, {"version": 1, "assets": {}})
    if not isinstance(data, dict) or not isinstance(data.get("assets"), dict):
        raise PromotionError(f"Invalid promotion state: {state_path}")
    data.setdefault("version", 1)
    return data


def safe_relative_path(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError as exc:
        raise PromotionError(f"Path escapes project root: {path}") from exc


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def png_dimensions(path: Path) -> tuple[int, int]:
    """Read PNG dimensions without requiring an image-processing dependency."""
    with path.open("rb") as handle:
        if handle.read(8) != b"\x89PNG\r\n\x1a\n":
            raise PromotionError(f"Expected a PNG file: {path}")
        length = struct.unpack(">I", handle.read(4))[0]
        chunk_type = handle.read(4)
        if chunk_type != b"IHDR" or length < 8:
            raise PromotionError(f"PNG is missing an IHDR header: {path}")
        width, height = struct.unpack(">II", handle.read(8))
        if width <= 0 or height <= 0:
            raise PromotionError(f"PNG has invalid dimensions: {path}")
        return width, height


def find_source_asset(manifest: dict[str, Any], asset_id: str, asset_type: str) -> dict[str, Any]:
    for asset in manifest["assets"]:
        if asset.get("id") == asset_id:
            if asset.get("type") != asset_type:
                raise PromotionError(
                    f"Asset '{asset_id}' exists as type '{asset.get('type')}', not '{asset_type}'."
                )
            return asset
    raise PromotionError(f"Asset '{asset_id}' is not registered in Asset Lab manifest.")


def find_image(asset: dict[str, Any], version: int) -> dict[str, Any]:
    for image in asset.get("images", []):
        if int(image.get("version", -1)) == version:
            return image
    available = [image.get("version") for image in asset.get("images", [])]
    raise PromotionError(f"Image version v{version:03d} not found. Available versions: {available}")


def parse_animation_specs(values: list[str], versions: list[str]) -> list[tuple[str, int | None]]:
    if len(versions) > 1 and len(values) != len(versions):
        raise PromotionError("Use one --animation-version per --animation, or use name=version syntax.")
    parsed: list[tuple[str, int | None]] = []
    for index, raw in enumerate(values):
        name, separator, inline_version = raw.partition("=")
        name = slugify(name)
        version_value = inline_version if separator else (versions[index] if versions else None)
        version = int(version_value.lstrip("v")) if version_value else None
        parsed.append((name, version))
    return parsed


def find_animation(asset: dict[str, Any], name: str, version: int | None) -> dict[str, Any]:
    matches = [animation for animation in asset.get("animations", []) if slugify(animation.get("name", "")) == name]
    if version is not None:
        matches = [animation for animation in matches if int(animation.get("version", -1)) == version]
    if not matches:
        available = [f"{item.get('name')} v{item.get('version', 0):03d}" for item in asset.get("animations", [])]
        raise PromotionError(f"Animation '{name}' was not found. Available animations: {available}")
    return sorted(matches, key=lambda item: int(item.get("version", 0)))[-1]


def source_path(project_root: Path, relative_path: str) -> Path:
    path = (project_root / "asset_lab" / relative_path).resolve()
    if not path.is_file():
        raise PromotionError(f"Asset Lab source file is missing: {relative_path}")
    safe_relative_path((project_root / "asset_lab").resolve(), path)
    return path


def runtime_path(project_root: Path, asset_type: str, asset_id: str, category: str, filename: str) -> Path:
    path = (project_root / MEDIA_ASSETS_RELATIVE / type_folder(asset_type) / asset_id / category / filename).resolve()
    safe_relative_path(project_root, path)
    return path


def source_image_record(image: dict[str, Any], source: Path, source_relative: str, runtime_relative: str) -> dict[str, Any]:
    width, height = png_dimensions(source)
    return {
        "path": runtime_relative,
        "source_path": source_relative,
        "version": int(image["version"]),
        "width": image.get("width") or width,
        "height": image.get("height") or height,
        "provider": image.get("provider"),
        "prompt": image.get("prompt"),
    }


def source_animation_record(animation: dict[str, Any], source: Path, source_relative: str, runtime_relative: str) -> dict[str, Any]:
    sheet_width, sheet_height = png_dimensions(source)
    frame_count = int(animation.get("frame_count") or 1)
    frame_width = animation.get("frame_width") or sheet_width // frame_count
    frame_height = animation.get("frame_height") or sheet_height
    if frame_width * frame_count > sheet_width or frame_height > sheet_height:
        raise PromotionError(f"Animation metadata does not fit sprite sheet: {source_relative}")
    return {
        "name": slugify(animation["name"]),
        "sheet_path": runtime_relative,
        "source_sheet_path": source_relative,
        "version": int(animation["version"]),
        "frame_width": frame_width,
        "frame_height": frame_height,
        "frame_count": frame_count,
        "fps": animation.get("fps"),
        "loop": bool(animation.get("loop", False)),
        "provider": animation.get("provider"),
        "prompt": animation.get("prompt"),
        "source_image_version": animation.get("source_image_version"),
    }


def build_plan(
    project_root: Path,
    operation: str,
    asset_type: str,
    asset_id: str,
    image_version: int | None,
    animation_specs: list[tuple[str, int | None]],
) -> dict[str, Any]:
    asset_id = slugify(asset_id)
    manifest = load_source_manifest(project_root)
    state = load_promoted_state(project_root)
    source_asset = find_source_asset(manifest, asset_id, asset_type)
    existing = state["assets"].get(asset_id)

    if operation == "promote-new" and existing is not None:
        raise PromotionError(f"Asset '{asset_id}' is already promoted. Use promote-update.")
    if operation == "promote-update" and existing is None:
        raise PromotionError(f"Asset '{asset_id}' is not promoted yet. Use promote-new.")
    if operation == "promote-new" and image_version is None:
        raise PromotionError("promote-new requires --image-version.")
    if image_version is None and not animation_specs:
        raise PromotionError("Provide --image-version and/or --animation.")

    changes: dict[str, Any] = {"image": None, "animations": []}
    if image_version is not None:
        image = find_image(source_asset, image_version)
        source_relative = image["path"]
        source = source_path(project_root, source_relative)
        destination = runtime_path(project_root, asset_type, asset_id, "original_images", source.name)
        changes["image"] = {
            "source": source,
            "source_relative": source_relative,
            "destination": destination,
            "record": source_image_record(image, source, source_relative, safe_relative_path(project_root, destination)),
            "old_path": existing.get("image", {}).get("path") if existing else None,
        }

    for name, version in animation_specs:
        animation = find_animation(source_asset, name, version)
        source_relative = animation["sheet_path"]
        source = source_path(project_root, source_relative)
        destination = runtime_path(project_root, asset_type, asset_id, "sprite_sheets", source.name)
        old_animation = (existing or {}).get("animations", {}).get(name, {})
        changes["animations"].append({
            "name": name,
            "source": source,
            "source_relative": source_relative,
            "destination": destination,
            "record": source_animation_record(animation, source, source_relative, safe_relative_path(project_root, destination)),
            "old_path": old_animation.get("sheet_path"),
        })

    if changes["animations"] and existing:
        current_image_version = (existing.get("image") or {}).get("version")
        for change in changes["animations"]:
            source_version = change["record"].get("source_image_version")
            if source_version != current_image_version and changes["image"] is None:
                raise PromotionError(
                    f"Animation '{change['name']}' uses image v{source_version:03d}; "
                    "include that version with --image-version."
                )

    return {
        "operation": operation,
        "asset_id": asset_id,
        "asset_type": asset_type,
        "source_asset": source_asset,
        "existing": existing,
        "changes": changes,
        "state": state,
    }


def merge_state(plan: dict[str, Any]) -> dict[str, Any]:
    state = plan["state"]
    asset_id = plan["asset_id"]
    existing = dict(plan["existing"] or {})
    existing.setdefault("id", asset_id)
    existing["type"] = plan["asset_type"]
    existing["groups"] = groups_from_asset(plan["source_asset"])
    existing.setdefault("animations", {})
    if plan["changes"]["image"]:
        existing["image"] = plan["changes"]["image"]["record"]
    for change in plan["changes"]["animations"]:
        existing["animations"][change["name"]] = change["record"]
    existing.setdefault("created_at", now_stamp())
    existing["updated_at"] = now_stamp()
    state["assets"][asset_id] = existing
    state["updated_at"] = now_stamp()
    return state


def lua_literal(value: Any, indent: int = 0) -> str:
    if isinstance(value, dict):
        if not value:
            return "{}"
        lines = ["{"]
        for key in sorted(value):
            lua_key = key if key.isidentifier() else f"[{json.dumps(key)}]"
            lines.append(" " * (indent + 2) + f"{lua_key} = {lua_literal(value[key], indent + 2)},")
        lines.append(" " * indent + "}")
        return "\n".join(lines)
    if isinstance(value, list):
        return "{" + ", ".join(lua_literal(item, indent) for item in value) + "}"
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "nil"
    if isinstance(value, (int, float)):
        return str(value)
    return json.dumps(str(value), ensure_ascii=False)


def runtime_manifest_data(state: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for asset_id, asset in sorted(state["assets"].items()):
        asset_type = asset["type"]
        group = type_folder(asset_type)
        result.setdefault(group, {})[asset_id] = {
            "id": asset_id,
            "groups": asset.get("groups", []),
            "image": asset.get("image"),
            "animations": asset.get("animations", {}),
        }
    audio_state = state.get("audio", {})
    result["audio"] = {
        "sounds": audio_state.get("sounds", {}),
        "music": audio_state.get("music", {}),
    }
    return result


def write_runtime_manifest(path: Path, state: dict[str, Any]) -> None:
    data = runtime_manifest_data(state)
    output = "-- Generated by promote_lab_asset.py. Do not edit by hand.\nreturn "
    output += lua_literal(data)
    output += "\n"
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    temporary.write_text(output, encoding="utf-8")
    temporary.replace(path)


def print_plan(plan: dict[str, Any]) -> None:
    print(f"Asset promotion: {plan['operation']} | {plan['asset_type']} | {plan['asset_id']}")
    changes = plan["changes"]
    if changes["image"]:
        item = changes["image"]
        print(f"Image: {item['source_relative']} -> {item['destination']}")
    for item in changes["animations"]:
        print(f"Animation {item['name']}: {item['source_relative']} -> {item['destination']}")
    if plan["existing"]:
        print("Existing runtime asset will be updated; unrelated slots remain unchanged.")
    print("GIF previews are not promoted.")


def append_promotion_trace(project_root: Path, plan: dict[str, Any], state: dict[str, Any]) -> None:
    path = project_root / "asset_lab" / "lab_assets" / type_folder(plan["asset_type"]) / plan["asset_id"] / "promotion_trace.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "ts": now_stamp(),
        "event": "promoted",
        "operation": plan["operation"],
        "asset_id": plan["asset_id"],
        "asset_type": plan["asset_type"],
        "state": state["assets"][plan["asset_id"]],
    }
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")


def execute_plan(project_root: Path, plan: dict[str, Any]) -> None:
    _, state_path, runtime_manifest_path, _ = project_paths(project_root)
    staged: list[tuple[Path, Path]] = []
    try:
        for change in [plan["changes"]["image"]] + plan["changes"]["animations"]:
            if not change:
                continue
            destination = change["destination"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(f".{destination.name}.{uuid.uuid4().hex}.tmp")
            shutil.copy2(change["source"], temporary)
            if sha256(change["source"]) != sha256(temporary):
                raise PromotionError(f"Copied file failed verification: {destination}")
            staged.append((temporary, destination))

        state = merge_state(plan)
        for temporary, destination in staged:
            temporary.replace(destination)
        state_path.parent.mkdir(parents=True, exist_ok=True)
        write_json(state_path, state)
        write_runtime_manifest(runtime_manifest_path, state)

        old_paths = []
        if plan["changes"]["image"] and plan["changes"]["image"]["old_path"]:
            old_paths.append(plan["changes"]["image"]["old_path"])
        old_paths.extend(change["old_path"] for change in plan["changes"]["animations"] if change["old_path"])
        referenced = {asset_path for asset in state["assets"].values() for asset_path in [
            (asset.get("image") or {}).get("path"),
            *[item.get("sheet_path") for item in (asset.get("animations") or {}).values()],
        ]}
        for old_path in old_paths:
            if old_path and old_path not in referenced:
                old_file = project_root / old_path
                if old_file.exists():
                    old_file.unlink()
        append_promotion_trace(project_root, plan, state)
        print("Promotion complete. Runtime registry updated.")
    except Exception:
        for temporary, _ in staged:
            temporary.unlink(missing_ok=True)
        raise


def create_character_scaffold(project_root: Path, plan: dict[str, Any]) -> None:
    if plan["asset_type"] != "character":
        return
    path = project_root / "game_data" / "characters" / f"{plan['asset_id']}.lua"
    if path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    image = plan["changes"]["image"]["record"] if plan["changes"]["image"] else {}
    width = image.get("width") or 0
    height = image.get("height") or 0
    path.write_text(
        "-- Gameplay configuration scaffold generated during promotion.\n"
        "return {\n"
        f"  asset_id = {json.dumps(plan['asset_id'])},\n"
        "  position = { x = 0, ground_y = 0, z = 0 },\n"
        "  scale = 1,\n"
        f"  anchor = {{ x = {width // 2}, y = {height} }},\n"
        "  default_animation = nil,\n"
        "  collision = { enabled = false, auto_sensor = true, sensors = {} }\n"
        "}\n",
        encoding="utf-8",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Promote exact Asset Lab versions into media_assets and game_data.")
    parser.add_argument("--operation", choices=("promote-new", "promote-update"), required=True)
    parser.add_argument("--type", dest="asset_type", choices=sorted(TYPE_FOLDERS), required=True)
    parser.add_argument("--asset-id", required=True)
    parser.add_argument("--image-version", type=int)
    parser.add_argument("--animation", action="append", default=[], help="Animation name or name=version; repeatable.")
    parser.add_argument("--animation-version", action="append", default=[], help="Version for one animation; repeatable.")
    parser.add_argument("--project-root", type=Path, default=HELPERS_DIR.parents[1])
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        animation_specs = parse_animation_specs(args.animation, args.animation_version)
        plan = build_plan(args.project_root.resolve(), args.operation, args.asset_type, args.asset_id, args.image_version, animation_specs)
        print_plan(plan)
        if args.dry_run:
            print("Dry run only. No files or registry entries changed.")
            return 0
        execute_plan(args.project_root.resolve(), plan)
        create_character_scaffold(args.project_root.resolve(), plan)
        return 0
    except (PromotionError, ValueError, OSError) as exc:
        print(f"Asset promotion failed: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
