"""Sync or verify the minimal storm-cell Godot review project."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import shutil
import sys


FILES = (
    Path("vfx/weather/horizon_storm_cell_v1/storm_cell.gd"),
    Path("vfx/weather/horizon_storm_cell_v1/rain.gdshader"),
    Path("vfx/weather/horizon_storm_cell_v1/storm_cell.tscn"),
    Path("vfx/weather/horizon_storm_cell_v1/storm_cell_preview.tscn"),
    Path("tools/screenshot_horizon_storm_cell.gd"),
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify copies without writing")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    review_root = root / "source_art/horizon_storm_cell_v1"
    mismatches: list[str] = []
    for relative in FILES:
        source = root / relative
        target = review_root / relative
        if not source.is_file():
            mismatches.append(f"missing source: {relative.as_posix()}")
            continue
        if args.check:
            if not target.is_file() or sha256(source) != sha256(target):
                mismatches.append(f"stale review copy: {relative.as_posix()}")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    if mismatches:
        print("\n".join(mismatches), file=sys.stderr)
        return 1
    print("Storm-cell review source copies: PASS" if args.check else "Storm-cell review sources synced")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
