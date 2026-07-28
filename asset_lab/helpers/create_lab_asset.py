from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

HELPERS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(HELPERS_DIR))
sys.path.insert(0, str(HELPERS_DIR / "providers"))

import asset_processor
import common
import manifest
from common import (
    asset_folder,
    append_trace,
    ANIMATION_GIFS_DIR,
    ensure_asset_dirs,
    file_stamp,
    find_asset_locations,
    load_dotenv,
    next_version,
    ORIGINAL_IMAGES_DIR,
    parse_version_tag,
    relative_to_asset_lab,
    save_base64_image,
    similar_asset_names,
    SPRITE_SHEETS_DIR,
    slugify,
    type_folder,
    version_tag,
    write_json,
    groups_from_asset,
    normalize_groups,
)
import mock
import pixellab
import autosprite
import self_provider


PROVIDERS = {
    "autosprite": autosprite,
    "mock": mock,
    "pixellab": pixellab,
    "self": self_provider,
}


def add_shared_provider_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--provider", choices=sorted(PROVIDERS), required=True)
    parser.add_argument("--name", required=True, help="Human asset name. Slug is used for folders/files.")
    parser.add_argument("--prompt", required=True, help="Provider prompt/action text.")
    parser.add_argument("--width", type=int, default=64)
    parser.add_argument("--height", type=int, default=64)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--with-background", action="store_true")
    parser.add_argument("--mock-image", help="Local PNG used by --provider mock for image generation.")
    parser.add_argument("--mock-frames-dir", help="Local frame_*.png folder used by --provider mock for animation.")
    parser.add_argument("--variation-group-id", help="Optional shared id for sibling variations from one request.")
    parser.add_argument("--group", dest="groups", action="append", default=[], help="Virtual taxonomy path; repeatable, e.g. vehicles/cars/XL.")
    parser.add_argument("--execute", action="store_true", help="Actually call provider API. Default is dry run.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Traceable Asset Lab creator.")
    subparsers = parser.add_subparsers(dest="action", required=True)

    create_new = subparsers.add_parser("create-new", help="Create a new asset folder and image v001.")
    add_shared_provider_args(create_new)
    create_new.add_argument("--type", choices=["character", "prop", "background", "effect"], required=True)

    add_image = subparsers.add_parser("add-image-version", help="Add a new image version to an existing asset.")
    add_shared_provider_args(add_image)
    add_image.add_argument("--type", choices=["character", "prop", "background", "effect"], default="character")
    add_image.add_argument("--mode", choices=["brand_new", "with_reference"], required=True)
    add_image.add_argument("--source-image-version", help="Required when --mode with_reference.")
    add_image.add_argument("--init-image-strength", type=int, default=500, help="Reference image influence, 1-999.")

    create_animation = subparsers.add_parser("create-animation", help="Create a sprite sheet/GIF from an existing image version.")
    add_shared_provider_args(create_animation)
    create_animation.add_argument("--type", choices=["character", "prop", "background", "effect"], default="character")
    create_animation.add_argument("--animation", required=True, help="Free-text animation name, slugified.")
    create_animation.add_argument("--source-image-version", required=True, help="Image version such as v001 or 1.")
    create_animation.add_argument("--frame-count", type=int, default=4)
    create_animation.add_argument("--fps", type=int, default=8)

    check_account = subparsers.add_parser("check-provider-account", help="Check provider account/credit state.")
    check_account.add_argument("--provider", choices=["autosprite"], required=True)
    check_account.add_argument("--name", default="_provider_check")

    prepare_provider_character = subparsers.add_parser("prepare-provider-character", help="Create provider-side character state from a manifest image.")
    prepare_provider_character.add_argument("--provider", choices=["autosprite"], required=True)
    prepare_provider_character.add_argument("--type", choices=["character"], default="character")
    prepare_provider_character.add_argument("--name", required=True)
    prepare_provider_character.add_argument("--source-image-version", required=True)
    prepare_provider_character.add_argument("--description", required=True)
    prepare_provider_character.add_argument("--is-humanoid", action="store_true")
    prepare_provider_character.add_argument("--execute", action="store_true")

    return parser.parse_args()


def base_manifest_record(asset_id: str, asset_type: str, folder: Path, groups: list[str] | None = None) -> dict[str, Any]:
    return {
        "id": asset_id,
        "type": asset_type,
        "folder": relative_to_asset_lab(folder),
        "groups": normalize_groups(groups),
        "images": [],
        "animations": [],
    }


def reject_if_new_name_is_suspicious(asset_id: str, asset_type: str) -> None:
    existing_manifest_asset = manifest.find_asset(asset_id)
    if existing_manifest_asset is not None:
        raise ValueError(f"Asset '{asset_id}' already exists in manifest. Use add-image-version or create-animation.")

    locations = find_asset_locations(asset_id, only_with_asset_files=True)
    if locations:
        where = ", ".join(f"{found_type}:{relative_to_asset_lab(path)}" for found_type, path in locations)
        raise ValueError(f"Asset '{asset_id}' already exists at {where}. Use add-image-version or create-animation.")

    similar = similar_asset_names(asset_id, only_with_asset_files=True)
    if similar:
        raise ValueError(f"Similar asset names already exist: {', '.join(similar)}. Check spelling before creating a new asset.")


def require_existing_asset(asset_id: str, asset_type: str) -> Path:
    folder = asset_folder(asset_type, asset_id)
    locations = find_asset_locations(asset_id)
    wrong_type_locations = [(found_type, path) for found_type, path in locations if found_type != asset_type]
    if wrong_type_locations:
        where = ", ".join(f"{found_type}:{relative_to_asset_lab(path)}" for found_type, path in wrong_type_locations)
        raise ValueError(f"Asset '{asset_id}' exists under another type: {where}.")

    if not folder.exists():
        similar = similar_asset_names(asset_id)
        hint = f" Similar names: {', '.join(similar)}." if similar else ""
        raise ValueError(f"Asset folder does not exist: {relative_to_asset_lab(folder)}.{hint}")

    manifest.require_asset(asset_id, asset_type)
    return folder


def image_paths(args: argparse.Namespace, asset_type: str, folder: Path, *, use_manifest_versions: bool) -> dict[str, Any]:
    asset_id = slugify(args.name)
    provider = slugify(args.provider)
    base_name = f"{asset_id}__{provider}__image"
    if use_manifest_versions:
        existing_versions = manifest.available_image_versions(asset_id, asset_type)
        version = (max(existing_versions) + 1) if existing_versions else 1
    else:
        version = next_version([folder / ORIGINAL_IMAGES_DIR], base_name)
    tag = version_tag(version)
    return {
        "asset_id": asset_id,
        "asset_type": asset_type,
        "folder": folder,
        "provider": provider,
        "version": version,
        "version_tag": tag,
        "trace_path": folder / "trace.jsonl",
        "request_path": folder / f"{base_name}__{tag}__dry_run_{file_stamp()}__request.json",
        "metadata_path": folder / "metadata.json",
        "image_path": folder / ORIGINAL_IMAGES_DIR / f"{base_name}__{tag}.png",
    }


def animation_paths(args: argparse.Namespace, asset_type: str, folder: Path, source_version: int) -> dict[str, Any]:
    asset_id = slugify(args.name)
    provider = slugify(args.provider)
    animation = slugify(args.animation)
    source_tag = version_tag(source_version)
    base_name = f"{asset_id}__{provider}__{animation}_from_image_{source_tag}"
    version = next_version([folder / SPRITE_SHEETS_DIR, folder / ANIMATION_GIFS_DIR], base_name)
    tag = version_tag(version)
    return {
        "asset_id": asset_id,
        "asset_type": asset_type,
        "folder": folder,
        "provider": provider,
        "animation": animation,
        "source_image_version": source_version,
        "version": version,
        "version_tag": tag,
        "trace_path": folder / "trace.jsonl",
        "request_path": folder / f"{base_name}__{tag}__dry_run_{file_stamp()}__request.json",
        "metadata_path": folder / "metadata.json",
        "sheet_path": folder / SPRITE_SHEETS_DIR / f"{base_name}__{tag}.png",
        "gif_path": folder / ANIMATION_GIFS_DIR / f"{base_name}__{tag}.gif",
    }


def write_dry_run(args: argparse.Namespace, paths: dict[str, Any], extra: dict[str, Any]) -> None:
    payload = {
        "dry_run": True,
        "action": args.action,
        "provider": args.provider,
        "type": paths["asset_type"],
        "name": paths["asset_id"],
        "prompt": args.prompt,
        "width": args.width,
        "height": args.height,
        "with_background": args.with_background,
        "mock_image": args.mock_image,
        "mock_frames_dir": args.mock_frames_dir,
        "groups": normalize_groups(args.groups),
        **extra,
        "planned_outputs": {
            key: relative_to_asset_lab(value)
            for key, value in paths.items()
            if key.endswith("_path") and isinstance(value, Path)
        },
    }
    write_json(paths["request_path"], payload)
    append_trace(paths["trace_path"], "dry_run", payload)


def static_provider_options(args: argparse.Namespace) -> dict[str, Any]:
    if args.provider == "mock":
        options: dict[str, Any] = {"mock_image": Path(args.mock_image) if args.mock_image else None}
    else:
        options = {}
    if getattr(args, "mode", "brand_new") == "with_reference":
        options["source_image_path"] = getattr(args, "source_image_path", None)
        options["init_image_strength"] = args.init_image_strength
    return options


def source_image_from_manifest(asset_id: str, asset_type: str, source_image_version: str) -> tuple[int, Path]:
    source_version = parse_version_tag(source_image_version)
    source_image = manifest.find_image_version(asset_id, asset_type, source_version)
    if source_image is None:
        available = manifest.available_image_versions(asset_id, asset_type)
        raise ValueError(f"Image version {version_tag(source_version)} not found. Available image versions: {available}")

    source_image_path = common.ASSET_LAB_DIR / source_image["path"]
    if not source_image_path.exists():
        raise FileNotFoundError(f"Manifest source image path is missing: {source_image['path']}")
    return source_version, source_image_path


def provider_check_trace_path(provider: str, name: str) -> Path:
    folder = common.ASSET_LAB_DIR / "provider_checks" / provider
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"{slugify(name)}__{file_stamp()}__trace.jsonl"


def animation_provider_options(args: argparse.Namespace) -> dict[str, Any]:
    if args.provider == "mock":
        return {"mock_frames_dir": Path(args.mock_frames_dir) if args.mock_frames_dir else None}
    return {}


def variation_group_id(args: argparse.Namespace, paths: dict[str, Any]) -> str:
    given = getattr(args, "variation_group_id", None)
    if given:
        return slugify(given)

    parts = [
        paths["asset_id"],
        paths["provider"],
        args.action,
        getattr(args, "mode", None),
        paths.get("animation"),
        f"from_{version_tag(paths['source_image_version'])}" if paths.get("source_image_version") else None,
        file_stamp(),
    ]
    return slugify("__".join(str(part) for part in parts if part))


def prompt_metadata(args: argparse.Namespace, paths: dict[str, Any], *, source_image_path: Path | None = None) -> dict[str, Any]:
    data: dict[str, Any] = {
        "prompt": args.prompt,
        "asset_id": paths["asset_id"],
        "asset_type": paths["asset_type"],
        "provider": paths["provider"],
        "action": args.action,
        "variation_group_id": variation_group_id(args, paths),
    }
    mode = getattr(args, "mode", None)
    if mode:
        data["mode"] = mode
    if paths.get("animation"):
        data["animation"] = paths["animation"]
    if paths.get("source_image_version"):
        data["source_image_version"] = paths["source_image_version"]
    if source_image_path is not None:
        data["source_image_path"] = relative_to_asset_lab(source_image_path)
    if getattr(args, "source_prompt_snapshot", None):
        data["source_prompt_snapshot"] = args.source_prompt_snapshot
    return data


def execute_image(args: argparse.Namespace, provider: Any, paths: dict[str, Any]) -> None:
    if args.provider == "self":
        execute_self_image(args, paths)
        return

    key = provider.api_key_from_env()
    result = provider.generate_static(
        api_key=key,
        prompt=args.prompt,
        width=args.width,
        height=args.height,
        with_background=args.with_background,
        trace_path=paths["trace_path"],
        **static_provider_options(args),
    )
    save_base64_image(result["image_base64"], paths["image_path"])
    image_meta = asset_processor.image_metadata(paths["image_path"])
    metadata = prompt_metadata(args, paths, source_image_path=getattr(args, "source_image_path", None))
    entry = {
        "id": paths["image_path"].stem,
        "provider": paths["provider"],
        "version": paths["version"],
        "mode": getattr(args, "mode", "brand_new"),
        "path": relative_to_asset_lab(paths["image_path"]),
        "prompt": args.prompt,
        "variation_group_id": metadata["variation_group_id"],
        "prompt_metadata": metadata,
        "width": image_meta["width"],
        "height": image_meta["height"],
    }
    if getattr(args, "mode", "brand_new") == "with_reference":
        entry["source_image_version"] = getattr(args, "source_image_version_number")
        entry["init_image_strength"] = args.init_image_strength
    manifest.add_image(paths["asset_id"], entry, base_manifest_record(paths["asset_id"], paths["asset_type"], paths["folder"], args.groups))
    write_json(paths["metadata_path"], {"last_result": entry})
    print(f"Saved image: {relative_to_asset_lab(paths['image_path'])}")


def print_self_image_instruction(args: argparse.Namespace, paths: dict[str, Any], entry: dict[str, Any]) -> None:
    print("SELF PROVIDER INSTRUCTION")
    print(f"Create one PNG image and save it exactly here: {paths['image_path']}")
    if getattr(args, "mode", "brand_new") == "with_reference":
        print(f"Use reference image: {getattr(args, 'source_image_path')}")
    print(f"Prompt: {args.prompt}")
    print(f"Manifest image entry: {entry['id']} ({entry['status']})")
    print("After saving the file, run: python asset_lab/helpers/validate_lab_assets.py")


def execute_self_image(args: argparse.Namespace, paths: dict[str, Any]) -> None:
    metadata = prompt_metadata(args, paths, source_image_path=getattr(args, "source_image_path", None))
    entry = {
        "id": paths["image_path"].stem,
        "provider": paths["provider"],
        "version": paths["version"],
        "mode": getattr(args, "mode", "brand_new"),
        "path": relative_to_asset_lab(paths["image_path"]),
        "prompt": args.prompt,
        "variation_group_id": metadata["variation_group_id"],
        "prompt_metadata": metadata,
        "status": "pending_self_creation",
    }
    if getattr(args, "mode", "brand_new") == "with_reference":
        entry["source_image_version"] = getattr(args, "source_image_version_number")
        entry["source_image_path"] = relative_to_asset_lab(getattr(args, "source_image_path"))
        entry["init_image_strength"] = args.init_image_strength

    manifest.add_image(paths["asset_id"], entry, base_manifest_record(paths["asset_id"], paths["asset_type"], paths["folder"], args.groups))
    write_json(paths["metadata_path"], {"last_result": entry})
    append_trace(paths["trace_path"], "self_instruction", {"kind": "image", **entry})
    print_self_image_instruction(args, paths, entry)


def execute_animation(args: argparse.Namespace, provider: Any, paths: dict[str, Any], source_image_path: Path | None) -> None:
    if args.provider == "self":
        execute_self_animation(args, paths, source_image_path)
        return

    key = provider.api_key_from_env()
    result = provider.generate_animation(
        api_key=key,
        input_image=source_image_path,
        action=args.prompt,
        frame_count=args.frame_count,
        seed=args.seed,
        trace_path=paths["trace_path"],
        **animation_provider_options(args),
    )
    animation_meta = asset_processor.write_sheet_and_gif(
        frame_images_base64=result["frame_images_base64"],
        sheet_path=paths["sheet_path"],
        gif_path=paths["gif_path"],
        fps=args.fps,
    )
    metadata = prompt_metadata(args, paths, source_image_path=source_image_path)
    entry = {
        "id": paths["gif_path"].stem,
        "provider": paths["provider"],
        "name": paths["animation"],
        "version": paths["version"],
        "source_image_version": paths["source_image_version"],
        "sheet_path": relative_to_asset_lab(paths["sheet_path"]),
        "gif_path": relative_to_asset_lab(paths["gif_path"]),
        "prompt": args.prompt,
        "variation_group_id": metadata["variation_group_id"],
        "prompt_metadata": metadata,
        **animation_meta,
    }
    manifest.add_animation(paths["asset_id"], entry, base_manifest_record(paths["asset_id"], paths["asset_type"], paths["folder"], args.groups))
    write_json(paths["metadata_path"], {"last_result": entry})
    print(f"Saved sprite sheet: {relative_to_asset_lab(paths['sheet_path'])}")
    print(f"Saved animation gif: {relative_to_asset_lab(paths['gif_path'])}")


def print_self_animation_instruction(args: argparse.Namespace, paths: dict[str, Any], source_image_path: Path, entry: dict[str, Any]) -> None:
    print("SELF PROVIDER INSTRUCTION")
    print(f"Use source image: {source_image_path}")
    print(f"Create one sprite sheet PNG and save it exactly here: {paths['sheet_path']}")
    print(f"Create one GIF preview and save it exactly here: {paths['gif_path']}")
    print(f"Animation: {paths['animation']} | frames: {args.frame_count} | fps: {args.fps}")
    print(f"Prompt: {args.prompt}")
    print(f"Manifest animation entry: {entry['id']} ({entry['status']})")
    print("After saving both files, run: python asset_lab/helpers/validate_lab_assets.py")


def execute_self_animation(args: argparse.Namespace, paths: dict[str, Any], source_image_path: Path | None) -> None:
    if source_image_path is None:
        raise ValueError("Self animation requires a source image path.")

    metadata = prompt_metadata(args, paths, source_image_path=source_image_path)
    entry = {
        "id": paths["gif_path"].stem,
        "provider": paths["provider"],
        "name": paths["animation"],
        "version": paths["version"],
        "source_image_version": paths["source_image_version"],
        "source_image_path": relative_to_asset_lab(source_image_path),
        "sheet_path": relative_to_asset_lab(paths["sheet_path"]),
        "gif_path": relative_to_asset_lab(paths["gif_path"]),
        "prompt": args.prompt,
        "variation_group_id": metadata["variation_group_id"],
        "prompt_metadata": metadata,
        "frame_count": args.frame_count,
        "fps": args.fps,
        "status": "pending_self_creation",
    }
    manifest.add_animation(paths["asset_id"], entry, base_manifest_record(paths["asset_id"], paths["asset_type"], paths["folder"], args.groups))
    write_json(paths["metadata_path"], {"last_result": entry})
    append_trace(paths["trace_path"], "self_instruction", {"kind": "animation", **entry})
    print_self_animation_instruction(args, paths, source_image_path, entry)


def handle_create_new(args: argparse.Namespace) -> int:
    asset_type = args.type
    asset_id = slugify(args.name)
    reject_if_new_name_is_suspicious(asset_id, asset_type)
    folder = asset_folder(asset_type, asset_id)
    ensure_asset_dirs(folder)
    paths = image_paths(args, asset_type, folder, use_manifest_versions=False)
    return run_image_action(args, paths, {"image_version": paths["version"]})


def handle_add_image_version(args: argparse.Namespace) -> int:
    asset_type = args.type
    asset_id = slugify(args.name)
    folder = require_existing_asset(asset_id, asset_type)
    ensure_asset_dirs(folder)
    paths = image_paths(args, asset_type, folder, use_manifest_versions=True)
    dry_extra: dict[str, Any] = {"image_version": paths["version"], "mode": args.mode}
    if args.mode == "with_reference":
        if not 1 <= args.init_image_strength <= 999:
            raise ValueError("--init-image-strength must be between 1 and 999.")
        if not args.source_image_version:
            raise ValueError("--source-image-version is required when --mode with_reference.")
        source_version, source_image_path = source_image_from_manifest(asset_id, asset_type, args.source_image_version)
        source_image = manifest.find_image_version(asset_id, asset_type, source_version)
        args.source_image_path = source_image_path
        args.source_image_version_number = source_version
        args.source_prompt_snapshot = source_image.get("prompt") if source_image else None
        dry_extra["source_image_version"] = source_version
        dry_extra["source_image_path"] = relative_to_asset_lab(source_image_path)
        dry_extra["source_prompt_snapshot"] = args.source_prompt_snapshot
        dry_extra["init_image_strength"] = args.init_image_strength
    elif args.source_image_version:
        raise ValueError("--source-image-version is only valid when --mode with_reference.")

    return run_image_action(args, paths, dry_extra)


def handle_create_animation(args: argparse.Namespace) -> int:
    asset_type = args.type
    asset_id = slugify(args.name)
    folder = require_existing_asset(asset_id, asset_type)
    ensure_asset_dirs(folder)

    source_version, source_image_path = source_image_from_manifest(asset_id, asset_type, args.source_image_version)
    source_image = manifest.find_image_version(asset_id, asset_type, source_version)
    args.source_prompt_snapshot = source_image.get("prompt") if source_image else None

    paths = animation_paths(args, asset_type, folder, source_version)
    return run_animation_action(args, paths, source_image_path)


def handle_check_provider_account(args: argparse.Namespace) -> int:
    provider = PROVIDERS[args.provider]
    trace_path = provider_check_trace_path(args.provider, args.name)
    key = provider.api_key_from_env()
    data = provider.check_account(api_key=key, trace_path=trace_path)
    print(f"{args.provider} account check passed.")
    print(f"Wrote trace: {relative_to_asset_lab(trace_path)}")
    if "credits" in data:
        print(f"credits={data['credits']}")
    return 0


def handle_prepare_provider_character(args: argparse.Namespace) -> int:
    asset_id = slugify(args.name)
    folder = require_existing_asset(asset_id, args.type)
    trace_path = folder / "trace.jsonl"
    source_version, source_image_path = source_image_from_manifest(asset_id, args.type, args.source_image_version)
    provider = PROVIDERS[args.provider]

    print(f"Asset Lab: prepare-provider-character | {args.provider} | {asset_id} | source {version_tag(source_version)}")
    if not args.execute:
        request_path = folder / f"{asset_id}__{args.provider}__provider_character_from_image_{version_tag(source_version)}__dry_run_{file_stamp()}__request.json"
        payload = {
            "dry_run": True,
            "action": args.action,
            "provider": args.provider,
            "type": args.type,
            "name": asset_id,
            "source_image_version": source_version,
            "source_image_path": relative_to_asset_lab(source_image_path),
            "description": args.description,
            "is_humanoid": args.is_humanoid,
        }
        write_json(request_path, payload)
        append_trace(trace_path, "dry_run", payload)
        print("Dry run only. No provider call, no manifest update.")
        print(f"Wrote request: {relative_to_asset_lab(request_path)}")
        return 0

    state = provider.create_character_from_image(
        api_key=provider.api_key_from_env(),
        name=asset_id,
        image_path=source_image_path,
        character_description=args.description,
        is_humanoid=args.is_humanoid,
        trace_path=trace_path,
    )
    manifest.set_provider_state(
        asset_id,
        args.type,
        args.provider,
        {
            "character_id": state["id"],
            "source_image_version": source_version,
            "source_image_path": relative_to_asset_lab(source_image_path),
            "is_humanoid": args.is_humanoid,
            "description": args.description,
            "base_image_url": state.get("baseImageUrl"),
            "thumbnail_url": state.get("thumbnailUrl"),
        },
    )
    append_trace(trace_path, "complete", {"action": args.action, "provider": args.provider, "manifest_updated": True})
    print(f"Saved provider character id: {state['id']}")
    print("Manifest updated.")
    return 0


def run_image_action(args: argparse.Namespace, paths: dict[str, Any], dry_extra: dict[str, Any]) -> int:
    provider = PROVIDERS[args.provider]
    print(f"Asset Lab: {args.action} | {args.provider} | {paths['asset_id']} | image {paths['version_tag']}")
    append_trace(paths["trace_path"], "start", {"action": args.action, "provider": args.provider, "execute": args.execute})

    if not args.execute:
        write_dry_run(args, paths, dry_extra)
        print("Dry run only. No provider call, no manifest update.")
        print(f"Wrote trace: {relative_to_asset_lab(paths['trace_path'])}")
        print(f"Wrote request: {relative_to_asset_lab(paths['request_path'])}")
        return 0

    execute_image(args, provider, paths)
    append_trace(paths["trace_path"], "complete", {"action": args.action, "manifest_updated": True})
    print("Manifest updated.")
    return 0


def run_animation_action(args: argparse.Namespace, paths: dict[str, Any], source_image_path: Path) -> int:
    provider = PROVIDERS[args.provider]
    print(
        "Asset Lab: "
        f"{args.action} | {args.provider} | {paths['asset_id']} | "
        f"{paths['animation']} from {version_tag(paths['source_image_version'])} | {paths['version_tag']}"
    )
    append_trace(paths["trace_path"], "start", {"action": args.action, "provider": args.provider, "execute": args.execute})

    if not args.execute:
        write_dry_run(
            args,
            paths,
            {
                "animation": paths["animation"],
                "source_image_version": paths["source_image_version"],
                "source_image_path": relative_to_asset_lab(source_image_path),
            },
        )
        print("Dry run only. No provider call, no manifest update.")
        print(f"Wrote trace: {relative_to_asset_lab(paths['trace_path'])}")
        print(f"Wrote request: {relative_to_asset_lab(paths['request_path'])}")
        return 0

    execute_animation(args, provider, paths, source_image_path)
    append_trace(paths["trace_path"], "complete", {"action": args.action, "manifest_updated": True})
    print("Manifest updated.")
    return 0


def main() -> int:
    args = parse_args()
    load_dotenv()
    try:
        if args.action == "create-new":
            return handle_create_new(args)
        if args.action == "add-image-version":
            return handle_add_image_version(args)
        if args.action == "create-animation":
            return handle_create_animation(args)
        if args.action == "check-provider-account":
            return handle_check_provider_account(args)
        if args.action == "prepare-provider-character":
            return handle_prepare_provider_character(args)
    except Exception as exc:
        print(f"Asset Lab failed: {exc}")
        return 2
    print(f"Asset Lab failed: unsupported action {args.action}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
