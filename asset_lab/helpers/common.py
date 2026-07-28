from __future__ import annotations

import base64
import difflib
import json
import os
import re
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any


HELPERS_DIR = Path(__file__).resolve().parent
ASSET_LAB_DIR = HELPERS_DIR.parent
PROJECT_ROOT = ASSET_LAB_DIR.parent
LAB_ASSETS_DIR = ASSET_LAB_DIR / "lab_assets"
MANIFEST_PATH = ASSET_LAB_DIR / "manifest.json"

ORIGINAL_IMAGES_DIR = "original_images"
SPRITE_SHEETS_DIR = "sprite_sheets"
ANIMATION_GIFS_DIR = "animation_gifs"

TYPE_FOLDERS = {
    "character": "characters",
    "prop": "props",
    "background": "backgrounds",
    "effect": "effects",
}


def load_dotenv(path: Path | None = None) -> None:
    env_path = path or PROJECT_ROOT / ".env"
    if not env_path.exists():
        return

    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "_", value.strip().lower())
    slug = re.sub(r"_+", "_", slug).strip("_")
    if not slug:
        raise ValueError("Name becomes empty after slug cleanup.")
    return slug


def normalize_group_path(value: str) -> str:
    """Return a safe, canonical virtual taxonomy path such as vehicles/cars/xl."""
    raw = str(value).strip().replace("\\", "/")
    if not raw or raw.startswith("/") or raw.endswith("/"):
        raise ValueError(f"Invalid asset group path: {value!r}")
    segments = raw.split("/")
    if any(segment in {"", ".", ".."} for segment in segments):
        raise ValueError(f"Invalid asset group path: {value!r}")
    return "/".join(slugify(segment) for segment in segments)


def normalize_groups(values: Any = None) -> list[str]:
    if values is None:
        return []
    if isinstance(values, str):
        values = [values]
    if not isinstance(values, (list, tuple)):
        raise ValueError("Asset groups must be a string or list of strings.")
    return sorted({normalize_group_path(value) for value in values})


def groups_from_asset(asset: dict[str, Any]) -> list[str]:
    """Read canonical groups, with compatibility for the original taxonomy fields."""
    if asset.get("groups"):
        return normalize_groups(asset["groups"])
    legacy = [asset.get("domain"), asset.get("subcategory"), asset.get("size_class")]
    legacy = [str(value) for value in legacy if value]
    return normalize_groups(["/".join(legacy)]) if legacy else []


def type_folder(asset_type: str) -> str:
    try:
        return TYPE_FOLDERS[asset_type]
    except KeyError as exc:
        valid = ", ".join(sorted(TYPE_FOLDERS))
        raise ValueError(f"Unsupported asset type '{asset_type}'. Use one of: {valid}") from exc


def asset_folder(asset_type: str, name: str) -> Path:
    return LAB_ASSETS_DIR / type_folder(asset_type) / slugify(name)


def has_asset_files(path: Path) -> bool:
    return any(child.is_file() and child.suffix.lower() in {".png", ".gif"} for child in path.rglob("*"))


def list_asset_folders(*, only_with_asset_files: bool = False) -> list[tuple[str, str, Path]]:
    found: list[tuple[str, str, Path]] = []
    for asset_type, folder_name in TYPE_FOLDERS.items():
        root = LAB_ASSETS_DIR / folder_name
        if not root.exists():
            continue
        for path in root.iterdir():
            if path.is_dir() and (not only_with_asset_files or has_asset_files(path)):
                found.append((asset_type, path.name, path))
    return found


def find_asset_locations(name: str, *, only_with_asset_files: bool = False) -> list[tuple[str, Path]]:
    asset_id = slugify(name)
    return [
        (asset_type, path)
        for asset_type, folder_name, path in list_asset_folders(only_with_asset_files=only_with_asset_files)
        if folder_name == asset_id
    ]


def similar_asset_names(name: str, *, cutoff: float = 0.82, only_with_asset_files: bool = False) -> list[str]:
    asset_id = slugify(name)
    names = sorted({folder_name for _, folder_name, _ in list_asset_folders(only_with_asset_files=only_with_asset_files)})
    return difflib.get_close_matches(asset_id, names, n=5, cutoff=cutoff)


def ensure_asset_dirs(folder: Path) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    for child in (ORIGINAL_IMAGES_DIR, SPRITE_SHEETS_DIR, ANIMATION_GIFS_DIR):
        (folder / child).mkdir(exist_ok=True)


def now_stamp() -> str:
    return datetime.now().isoformat(timespec="seconds")


def file_stamp() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S-%f")


def relative_to_asset_lab(path: Path) -> str:
    return path.resolve().relative_to(ASSET_LAB_DIR.resolve()).as_posix()


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8-sig"))


def append_trace(path: Path, event: str, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    entry = {"ts": now_stamp(), "event": event, **data}
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")


def redact(value: str | None) -> str:
    if not value:
        return ""
    if len(value) <= 8:
        return "***"
    return f"{value[:4]}...{value[-4:]}"


def request_json(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    payload: dict[str, Any] | None = None,
    timeout: int = 90,
) -> tuple[int, dict[str, Any]]:
    body = None
    request_headers = dict(headers or {})
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        request_headers.setdefault("Content-Type", "application/json")

    req = urllib.request.Request(url, data=body, headers=request_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            data = {"raw": raw}
        return exc.code, data


def decode_base64_image(data_url_or_b64: str) -> bytes:
    data = data_url_or_b64
    if "," in data and data.startswith("data:"):
        data = data.split(",", 1)[1]
    return base64.b64decode(data)


def save_base64_image(data_url_or_b64: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(decode_base64_image(data_url_or_b64))


def next_version(paths: list[Path], base_name: str) -> int:
    pattern = re.compile(rf"^{re.escape(base_name)}(?:_sheet)?__v(\d{{3}})")
    highest = 0
    for folder in paths:
        if not folder.exists():
            continue
        for path in folder.iterdir():
            match = pattern.match(path.stem)
            if match:
                highest = max(highest, int(match.group(1)))
    return highest + 1


def version_tag(version: int) -> str:
    return f"v{version:03d}"


def parse_version_tag(value: str) -> int:
    match = re.fullmatch(r"v?(\d+)", value.strip().lower())
    if not match:
        raise ValueError(f"Version must look like v001 or 1, got: {value}")
    return int(match.group(1))
