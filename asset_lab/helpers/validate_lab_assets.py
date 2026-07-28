from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

HELPERS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(HELPERS_DIR))

import manifest
from common import ASSET_LAB_DIR, LAB_ASSETS_DIR, TYPE_FOLDERS, groups_from_asset, normalize_groups, relative_to_asset_lab


ASSET_SUFFIXES = {".png", ".gif"}
PENDING_SELF_STATUS = "pending_self_creation"


def lab_path(path_value: str) -> Path:
    return ASSET_LAB_DIR / path_value


def missing_path_issue(asset_id: str, label: str, path: str, status: str | None = None) -> str:
    if status == PENDING_SELF_STATUS:
        return f"{asset_id}: pending self {label} missing on disk: {path}"
    return f"{asset_id}: {label} missing on disk: {path}"


def collect_manifest_paths(data: dict[str, Any]) -> set[str]:
    paths: set[str] = set()
    for asset in data.get("assets", []):
        folder = asset.get("folder")
        if folder:
            paths.add(folder)
        for image in asset.get("images", []):
            if image.get("path"):
                paths.add(image["path"])
        for animation in asset.get("animations", []):
            if animation.get("sheet_path"):
                paths.add(animation["sheet_path"])
            if animation.get("gif_path"):
                paths.add(animation["gif_path"])
    for orphan in data.get("orphans", []):
        if orphan.get("path"):
            paths.add(orphan["path"])
    return paths


def scan_asset_files() -> set[str]:
    files: set[str] = set()
    if not LAB_ASSETS_DIR.exists():
        return files
    for path in LAB_ASSETS_DIR.rglob("*"):
        if not path.is_file():
            continue
        if path.name == ".gitkeep":
            continue
        if path.suffix.lower() in ASSET_SUFFIXES:
            files.add(relative_to_asset_lab(path))
    return files


def validate_manifest(data: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    seen_ids: dict[str, str] = {}

    for asset in data.get("assets", []):
        asset_id = asset.get("id")
        asset_type = asset.get("type")
        folder = asset.get("folder")

        if not asset_id:
            issues.append("Manifest asset missing id.")
            continue
        if asset_id in seen_ids:
            issues.append(f"Duplicate manifest asset id: {asset_id}")
        seen_ids[asset_id] = folder or ""

        if asset_type not in TYPE_FOLDERS:
            issues.append(f"{asset_id}: unsupported type '{asset_type}'.")
            continue

        expected_folder = f"lab_assets/{TYPE_FOLDERS[asset_type]}/{asset_id}"
        if folder != expected_folder:
            issues.append(f"{asset_id}: folder should be {expected_folder}, got {folder}.")
        if folder and not lab_path(folder).exists():
            issues.append(f"{asset_id}: manifest folder missing on disk: {folder}")

        try:
            groups = normalize_groups(asset.get("groups", [])) if asset.get("groups") else groups_from_asset(asset)
            if asset.get("groups") is not None and groups != asset.get("groups"):
                issues.append(f"{asset_id}: groups must be normalized unique paths: {asset.get('groups')}")
        except ValueError as exc:
            issues.append(f"{asset_id}: invalid groups: {exc}")

        image_versions: set[int] = set()
        for image in asset.get("images", []):
            version = image.get("version")
            path = image.get("path")
            if version in image_versions:
                issues.append(f"{asset_id}: duplicate image version v{int(version):03d}.")
            if isinstance(version, int):
                image_versions.add(version)
            else:
                issues.append(f"{asset_id}: image entry has invalid version: {version}")
            if not path:
                issues.append(f"{asset_id}: image v{version} missing path.")
            elif not lab_path(path).exists():
                issues.append(missing_path_issue(asset_id, "image path", path, image.get("status")))

        for animation in asset.get("animations", []):
            name = animation.get("name", "<unnamed>")
            source_version = animation.get("source_image_version")
            if source_version not in image_versions:
                issues.append(f"{asset_id}: animation '{name}' references missing image version v{int(source_version):03d}.")
            for key in ("sheet_path", "gif_path"):
                path = animation.get(key)
                if not path:
                    issues.append(f"{asset_id}: animation '{name}' missing {key}.")
                elif not lab_path(path).exists():
                    issues.append(missing_path_issue(asset_id, f"animation '{name}' {key}", path, animation.get("status")))

        provider_state = asset.get("provider_state", {})
        autosprite_state = provider_state.get("autosprite")
        if autosprite_state:
            if not autosprite_state.get("character_id"):
                issues.append(f"{asset_id}: autosprite provider_state missing character_id.")
            source_version = autosprite_state.get("source_image_version")
            if not isinstance(source_version, int):
                issues.append(f"{asset_id}: autosprite provider_state has invalid source_image_version: {source_version}")
            elif source_version not in image_versions:
                issues.append(f"{asset_id}: autosprite provider_state references missing image version v{source_version:03d}.")
            source_path = autosprite_state.get("source_image_path")
            if source_path and not lab_path(source_path).exists():
                issues.append(f"{asset_id}: autosprite provider_state source image missing on disk: {source_path}")

    return issues


def validate_orphans(data: dict[str, Any]) -> list[str]:
    manifest_paths = collect_manifest_paths(data)
    asset_files = scan_asset_files()
    return [f"Orphan asset file not in manifest: {path}" for path in sorted(asset_files - manifest_paths)]


def main() -> int:
    data = manifest.load_manifest()
    issues = validate_manifest(data) + validate_orphans(data)

    if not issues:
        print("Asset Lab validation passed.")
        return 0

    print(f"Asset Lab validation found {len(issues)} issue(s):")
    for issue in issues:
        print(f"- {issue}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
