"""Check a package plan for shared owned files.

Usage: python tools/check_packages.py <packages.json> [--path <checkout>]

Accepted JSON: a list of [name, [files]] pairs, or a list of objects
{"name", "files", optional "after": [names], optional "wave": any}.
Two packages conflict when they share an owned file, sit in the same wave
(no wave counts as one shared wave) and neither transitively comes "after"
the other. Prints `SHARED <file>: <a>, <b>` per conflict and a final
`PACKAGES DISJOINT|SHARED (<n> conflicts)` line; exit 1 on any conflict.
With --path, owned files that do not exist there are listed as `MISSING`
notes (new files are legitimate, so they never fail the check).
"""
import argparse
import json
import os
import sys
from typing import Dict, List, Optional, Set, Tuple

Package = Dict[str, object]


def load(path: str) -> List[Package]:
    with open(path, encoding="utf-8-sig") as fh:
        data = json.load(fh)
    pkgs = []  # type: List[Package]
    for item in data:
        if isinstance(item, dict):
            pkgs.append({"name": str(item["name"]), "files": list(item.get("files", [])),
                         "after": list(item.get("after", [])), "wave": item.get("wave")})
        else:
            pkgs.append({"name": str(item[0]), "files": list(item[1]), "after": [], "wave": None})
    return pkgs


def _norm(f: str) -> str:
    f = f.replace("\\", "/")
    return f[2:] if f.startswith("./") else f


def ancestors(pkgs: List[Package]) -> Dict[str, Set[str]]:
    direct = {str(p["name"]): set(str(a) for a in p["after"]) for p in pkgs}  # type: ignore
    result = {}  # type: Dict[str, Set[str]]
    for name in direct:
        seen = set()  # type: Set[str]
        stack = list(direct[name])
        while stack:
            cur = stack.pop()
            if cur in seen:
                continue
            seen.add(cur)
            stack.extend(direct.get(cur, ()))
        result[name] = seen
    return result


def find_conflicts(pkgs: List[Package]) -> List[Tuple[str, str, str]]:
    anc = ancestors(pkgs)
    out = []  # type: List[Tuple[str, str, str]]
    for i, a in enumerate(pkgs):
        for b in pkgs[i + 1:]:
            an, bn = str(a["name"]), str(b["name"])
            if a["wave"] != b["wave"] or an in anc.get(bn, ()) or bn in anc.get(an, ()):
                continue
            shared = set(_norm(f) for f in a["files"]) & set(_norm(f) for f in b["files"])  # type: ignore
            for f in sorted(shared):
                out.append((f, an, bn))
    return out


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("packages")
    ap.add_argument("--path", default=None, help="checkout used to note missing files")
    args = ap.parse_args(argv)
    pkgs = load(args.packages)
    if args.path:
        for p in pkgs:
            for f in p["files"]:  # type: ignore
                if not os.path.exists(os.path.join(args.path, _norm(f))):
                    print("MISSING %s: %s" % (f, p["name"]))
    conflicts = find_conflicts(pkgs)
    for f, a, b in conflicts:
        print("SHARED %s: %s, %s" % (f, a, b))
    print("PACKAGES %s (%d conflicts)" % ("SHARED" if conflicts else "DISJOINT", len(conflicts)))
    return 1 if conflicts else 0


if __name__ == "__main__":
    sys.exit(main())
