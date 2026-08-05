"""Stage reviewed legacy MotoCrotte audio with explicit unknown provenance."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path


def load_assets(mapping: Path) -> tuple[list[dict], Path]:
    index = json.loads(mapping.resolve().read_text(encoding="utf-8"))
    root = (mapping.resolve().parent / index["source_root"]).resolve()
    assets: list[dict] = []
    for name in index["mapping_files"]:
        assets.extend(json.loads((mapping.resolve().parent / name).read_text(encoding="utf-8"))["assets"])
    return assets, root


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Import reviewed legacy audio into Asset Lab.")
    parser.add_argument("--mapping", required=True, type=Path)
    parser.add_argument("--asset-id", required=True)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args(argv)
    assets, source_root = load_assets(args.mapping)
    matches = [asset for asset in assets if asset["asset_id"] == args.asset_id]
    if len(matches) != 1:
        raise SystemExit(f"Expected one mapping for {args.asset_id}; found {len(matches)}")
    asset = matches[0]
    source_relative = asset["source_paths"][0]
    source = (source_root / source_relative).resolve()
    if not source.is_file():
        raise SystemExit(f"Missing legacy audio source: {source}")
    root = Path(__file__).resolve().parents[1]
    kind = asset["kind"]
    destination = root / "audio_library" / "imported" / kind / f"{asset['asset_id']}{source.suffix.lower()}"
    print(f"{'Import' if args.execute else 'Would import'}: {source_relative} -> {destination.relative_to(root)}")
    if not args.execute:
        return 0
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    catalog_path = root / "audio_library" / "catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8")) if catalog_path.exists() else {"version": 1, "candidates": []}
    candidates = [candidate for candidate in catalog.get("candidates", []) if candidate.get("candidate_id") != f"legacy_{asset['asset_id']}"]
    candidates.append({
        "candidate_id": f"legacy_{asset['asset_id']}", "asset_id": asset["asset_id"], "kind": kind,
        "source": "legacy_motocrotte", "source_project": "motorcrotte", "source_path": source_relative,
        "groups": asset.get("groups", []), "license": "unknown", "status": "imported",
        "imported_path": destination.relative_to(root).as_posix(),
        # Imported legacy files are safe to audition in Asset Lab, even though
        # their provenance is explicitly unknown and therefore blocks promotion.
        "local_preview": destination.relative_to(root).as_posix(), "sha256": digest
    })
    catalog["version"] = 1
    catalog["candidates"] = sorted(candidates, key=lambda item: item["candidate_id"])
    catalog_path.parent.mkdir(parents=True, exist_ok=True)
    catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False), encoding="utf-8")
    print("Legacy audio imported.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
