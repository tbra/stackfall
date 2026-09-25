"""Read the checked-out versions of Stackfall's Claude skills."""

import argparse
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
SKILLS = ("stackfall-session-resume", "stackfall-auto-run", "stackfall-session-close")
VERSION = re.compile(r"^Version: (\d+\.\d+\.\d+)$", re.MULTILINE)


def read_version(name, root=ROOT):
    if name not in SKILLS:
        raise ValueError("unknown project skill: " + name)
    path = root / ".claude" / "skills" / name / "SKILL.md"
    match = VERSION.search(path.read_text(encoding="utf-8"))
    if not match:
        raise ValueError("missing Version line: " + str(path))
    return match.group(1)


def list_versions(root=ROOT):
    return " ".join(name + "@" + read_version(name, root) for name in SKILLS)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", nargs=2, metavar=("SKILL", "LOADED_VERSION"))
    args = parser.parse_args(argv)
    try:
        if args.check:
            name, loaded = args.check
            current = read_version(name)
            if current != loaded:
                print("STALE %s: loaded %s; disk %s" % (name, loaded, current))
                return 2
            print("Using %s@%s (disk verified)" % (name, current))
        else:
            print(list_versions())
    except (OSError, ValueError) as exc:
        print("Skill version check failed: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
