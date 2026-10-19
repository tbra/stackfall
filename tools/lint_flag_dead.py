"""Constant-flag guard: an `_enabled` switch that every resource leaves the same is dead weight or undocumented.

Usage: python tools/lint_flag_dead.py [--path <checkout>] [--report]

Scans every `@export var <name>_enabled: bool` declared in a script under config/ whose `extends` chain
reaches Resource. For each flag it collects the declared default plus the value of the flag in every
.tres/.tscn resource instance of that script or of a script extending it (an unset property counts as the
default; tests, addons and scratch folders are not scanned). One distinct value in that set means the
switch can never change anything through data, so it is a finding, one per line as
`path:line: flag-constant: message`.

tools/flag_dead_allow.json holds the reviewed exceptions: {"allow": [{"entry": "path:flag", "reason": "..."}]}.
Entries are `<script path>:<flag name>`; the reason is plain prose saying why a constant flag is kept (for
example that code or a debug panel flips it at runtime). An entry without a reason does not exempt anything.
Findings outside the allow-list fail the run (exit 1); allow entries that no longer match a finding are
reported as stale (delete them) without failing. `--report` prints the values seen for every flag.
"""
import argparse
import collections
import json
import os
import re
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ALLOW_NAME = "flag_dead_allow.json"
CHECK_ID = "flag-constant"
SKIP_DIRS = (".godot", ".git", "addons", "tests", "scratch", "node_modules", "__pycache__", "worktrees", "source_art")
FLAG_RE = re.compile(r"^@export\s+var\s+(\w+_enabled)\s*(?::\s*bool\s*)?(?::?=\s*(true|false))?\s*(?:#.*)?$")
CLASS_NAME_RE = re.compile(r"^class_name\s+(\w+)", re.M)
EXTENDS_RE = re.compile(r"^extends\s+(\"[^\"]+\"|[\w.]+)", re.M)
SECTION_RE = re.compile(r"^\[(\w+)\s*(.*)\]\s*$")
ATTR_RE = re.compile(r'(\w+)="([^"]*)"')
BOOL_LINE_RE = re.compile(r"^(\w+)\s*=\s*(true|false)\s*$")
EXT_ID_RE = re.compile(r'ExtResource\(\s*"([^"]+)"\s*\)')


def rd(root, rel):
    try:
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def walk(root, exts, top=""):
    out = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(root, top)):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        rel_dir = os.path.relpath(dirpath, root).replace("\\", "/")
        for n in filenames:
            if n.endswith(exts):
                out.append(n if rel_dir == "." else rel_dir + "/" + n)
    return sorted(out)


def parse_scripts(root):
    """{script rel path: {"class": name or None, "extends": text or None, "flags": [(name, default, line)]}}."""
    out = {}
    for rel in walk(root, (".gd",), "config"):
        text = rd(root, rel)
        cm, em = CLASS_NAME_RE.search(text), EXTENDS_RE.search(text)
        flags = []
        for i, line in enumerate(text.split("\n"), 1):
            m = FLAG_RE.match(line.strip())
            if m:
                flags.append((m.group(1), m.group(2) == "true", i))
        out[rel] = {"class": cm.group(1) if cm else None, "extends": em.group(1).strip('"') if em else None,
                    "flags": flags}
    return out


def resolve_parent(scripts, rel):
    ext = scripts[rel]["extends"] or ""
    if ext.startswith("res://"):
        return ext[len("res://"):]
    for p, n in scripts.items():
        if n["class"] and n["class"] == ext.split(".")[0]:
            return p
    return None


def is_resource(scripts, rel):
    """True when the extends chain of `rel` ends at the built-in Resource."""
    seen = set()
    while rel not in seen:
        seen.add(rel)
        parent = resolve_parent(scripts, rel)
        if parent is None:
            return (scripts[rel]["extends"] or "") == "Resource"
        rel = parent
    return False


def family(scripts, base):
    """`base` plus every script below it through `extends`."""
    out = {base}
    grew = True
    while grew:
        grew = False
        for p in scripts:
            if p not in out and resolve_parent(scripts, p) in out:
                out.add(p)
                grew = True
    return out


def scan_instances(root, script_paths):
    """[(resource file, script rel path, {prop: bool})] for every resource section that sets a script."""
    wanted = set(script_paths)
    out = []
    for rel in walk(root, (".tres", ".tscn")):
        ids, sections, cur = {}, [], None
        res_script = None
        for line in rd(root, rel).split("\n"):
            m = SECTION_RE.match(line.strip())
            if m:
                attrs = dict(ATTR_RE.findall(m.group(2)))
                cur = None
                if m.group(1) == "ext_resource" and attrs.get("path", "").startswith("res://"):
                    ids[attrs.get("id", "")] = attrs["path"][len("res://"):]
                elif m.group(1) in ("resource", "sub_resource"):
                    cur = {"script": None, "props": {}}
                    sections.append(cur)
                continue
            if cur is None:
                continue
            if line.startswith("script = "):
                e = EXT_ID_RE.search(line)
                cur["script"] = e.group(1) if e else None
                continue
            b = BOOL_LINE_RE.match(line.strip())
            if b:
                cur["props"][b.group(1)] = b.group(2) == "true"
        for sec in sections:
            path = ids.get(sec["script"] or "")
            if path in wanted:
                out.append((rel, path, sec["props"]))
    return out


def collect(root):
    """(findings [(path, line, id, message, key)], details {key: (default, [values per instance])})."""
    scripts = parse_scripts(root)
    flagged = [p for p, n in scripts.items() if n["flags"] and is_resource(scripts, p)]
    families = {p: family(scripts, p) for p in flagged}
    instances = scan_instances(root, set().union(*families.values()) if families else set())
    findings, details = [], {}
    for p in flagged:
        for name, default, line in scripts[p]["flags"]:
            seen = [props.get(name, default) for _, path, props in instances if path in families[p]]
            values = set(seen) | {default}
            key = "%s:%s" % (p, name)
            details[key] = (default, seen)
            if len(values) == 1:
                msg = "%s is always %s (default plus %d resource instance(s)); remove it or add an allow-list reason" % (
                    name, str(default).lower(), len(seen))
                findings.append((p, line, CHECK_ID, msg, key))
    return findings, details


def load_allow(root):
    try:
        with open(os.path.join(root, "tools", ALLOW_NAME), encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        data = {}
    return [a for a in data.get("allow", []) if isinstance(a, dict)]


def classify(findings, allow):
    """(new findings, allowed count, stale allow entries). An entry without a reason exempts nothing."""
    reasoned = set(a.get("entry") for a in allow if str(a.get("reason", "")).strip())
    new, used = [], set()
    for f in findings:
        if f[4] in reasoned:
            used.add(f[4])
        else:
            new.append(f)
    return new, len(used), sorted(reasoned - used)


def print_report(details):
    for key, (default, seen) in sorted(details.items()):
        print("%-70s default=%-5s instances=%s" % (key, str(default).lower(),
                                                  dict(collections.Counter(str(v).lower() for v in seen)) or "none"))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=os.path.dirname(TOOLS))
    ap.add_argument("--report", action="store_true", help="print the values seen for every flag")
    args = ap.parse_args(argv)
    root = os.path.abspath(args.path).replace("\\", "/")
    findings, details = collect(root)
    if args.report:
        print_report(details)
    new, n_allowed, stale = classify(findings, load_allow(root))
    for f in new:
        print("%s:%d: %s: %s" % (f[0], f[1], f[2], f[3]))
    for key in stale:
        print("stale allow entry (no longer found, delete it): %s" % key)
    if new:
        print("LINT FLAG DEAD RED: %d new finding(s) (%d allowed, %d stale)" % (len(new), n_allowed, len(stale)))
        return 1
    print("LINT FLAG DEAD GREEN: %d allowed, %d stale" % (n_allowed, len(stale)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
