"""Stage a reviewed legacy font for later Love2D use."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Import a legacy font into Asset Lab staging.")
    parser.add_argument("--mapping", required=True, type=Path)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args(argv)
    mapping = json.loads(args.mapping.resolve().read_text(encoding="utf-8"))
    source_root = (args.mapping.resolve().parent / mapping["source_root"]).resolve()
    source = (source_root / mapping["source_path"]).resolve()
    if not source.is_file() or source.suffix.lower() not in {".otf", ".ttf"}:
        raise SystemExit(f"Missing or unsupported font source: {source}")
    root = Path(__file__).resolve().parents[1]
    destination = root / "font_library" / "imported" / f"{mapping['asset_id']}{source.suffix.lower()}"
    print(f"{'Import' if args.execute else 'Would import'}: {mapping['source_path']} -> {destination.relative_to(root)}")
    if not args.execute:
        return 0
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    metadata = dict(mapping)
    metadata.update({"imported_path": destination.relative_to(root).as_posix(), "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(), "status": "staged"})
    (root / "font_library").mkdir(parents=True, exist_ok=True)
    (root / "font_library" / "catalog.json").write_text(json.dumps({"version": 1, "fonts": [metadata]}, indent=2, ensure_ascii=False), encoding="utf-8")
    print("Legacy font staged.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
