"""Run-folder and incremental JSONL helpers for QA sessions."""

from __future__ import annotations

import json
import os
import random
import string
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1


def new_run_dir(root: Path, run_id: str | None = None) -> Path:
    if not run_id:
        run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")[:-3]
    else:
        candidate = Path(run_id)
        if run_id in {".", ".."} or candidate.name != run_id or any(part in run_id for part in ("/", "\\")):
            raise ValueError("run_id must be a single directory name")
    run_dir = root / run_id
    while run_dir.exists():
        suffix = "".join(random.choices(string.ascii_lowercase + string.digits, k=4))
        run_dir = root / f"{run_id}-{suffix}"
    for child in ("snapshots", "screenshots", "video", "video/frames"):
        (run_dir / child).mkdir(parents=True, exist_ok=False)
    return run_dir


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_json_atomic(path: Path, value: Any) -> None:
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    write_json(temporary, value)
    temporary.replace(path)


def run_id_for(run_dir: Path) -> str:
    return run_dir.name


def finalize_run(run_dir: Path, report: dict[str, Any]) -> dict[str, Any]:
    """Write a final report and advance latest.json atomically."""

    report = {"schema_version": SCHEMA_VERSION, "run_id": run_id_for(run_dir), **report}
    write_json_atomic(run_dir / "final_report.json", report)
    latest = {"schema_version": SCHEMA_VERSION, "run_id": report["run_id"], "path": str(run_dir)}
    write_json_atomic(run_dir.parent / "latest.json", latest)
    return report


def read_latest(root: Path) -> dict[str, Any] | None:
    path = root / "latest.json"
    if not path.exists():
        return None
    with path.open(encoding="utf-8") as handle:
        latest = json.load(handle)
    run_dir = root / str(latest.get("run_id", ""))
    if not run_dir.is_dir():
        return None
    return latest


def list_run_dirs(root: Path) -> list[Path]:
    return sorted(
        (path for path in root.iterdir() if path.is_dir() and path.name != "__pycache__"),
        key=lambda path: path.name,
        reverse=True,
    ) if root.is_dir() else []


def append_jsonl(path: Path, value: Any) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(value, separators=(",", ":")) + "\n")


class JsonlCursor:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.offset = 0

    def read_new(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        records: list[dict[str, Any]] = []
        with self.path.open("r", encoding="utf-8") as handle:
            handle.seek(self.offset)
            while True:
                line = handle.readline()
                if not line:
                    break
                self.offset = handle.tell()
                if line.strip():
                    records.append(json.loads(line))
        return records
