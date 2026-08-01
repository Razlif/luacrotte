"""Validate snapshots from the modular movement QA scenario."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def load(run_dir: Path, prefix: str) -> dict:
    files = sorted((run_dir / "snapshots").glob(f"{prefix}_frame_*.json"))
    if not files:
        raise AssertionError(f"missing snapshot: {prefix}")
    return json.loads(files[-1].read_text(encoding="utf-8"))


def motion(snapshot: dict) -> dict:
    return snapshot["visible_entities"][0]["motion"]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_modular_run.py RUN_DIRECTORY", file=sys.stderr)
        return 2
    run_dir = Path(sys.argv[1])
    accelerated = motion(load(run_dir, "modular_accelerated"))
    coast = motion(load(run_dir, "modular_coast"))
    turning = motion(load(run_dir, "modular_drift_turning"))
    holding = motion(load(run_dir, "modular_drift_holding"))
    exiting = motion(load(run_dir, "modular_drift_exiting"))
    finished = motion(load(run_dir, "modular_drift_exit"))

    assert accelerated["speed"] > 1, "movement did not accelerate"
    assert 0 < coast["speed"] < accelerated["speed"], "movement did not coast"
    assert turning["drift_active"], "drift did not activate"
    assert turning["turning_radius"] > 0, "turning radius was not calculated"
    assert holding["drift_phase"] == "holding", "drift did not reach holding state"
    assert holding["drift_spin_phase"] != turning["drift_spin_phase"], "drift phase did not advance"
    variant = holding.get("drift_variant_index")
    assert variant is None or 1 <= variant <= 48, "invalid drift variant"
    assert exiting["drift_phase"] == "exiting", "drift did not enter exit state"
    assert exiting["speed"] > 0, "drift exit lost momentum"
    assert finished["drift_phase"] == "normal" and not finished["drift_active"], "drift did not finish exiting"
    assert finished["speed"] > 0, "movement stopped at drift exit"
    print("Modular movement QA passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
