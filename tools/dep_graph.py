#!/usr/bin/env python
"""Static dependency graph of a Godot project: files, functions and their callers.

Bontago-fca.52. Stdlib only, Python 3.8 compatible. Never imports the project
into Godot; everything is text analysis, so it is best-effort:

* File edges: res:// and uid:// strings, ext_resource lines, preload/load,
  class_name usage, extends, autoload names, project.godot / export presets,
  string-built paths ("dynamic" edges, targets are only *possibly* used).
* Function nodes for every GDScript ``func``; call edges: self/inherited calls,
  ``ClassName.f()``, ``Autoload.f()``, preload aliases, typed variables,
  unique-name fallback (``unique``) and ambiguous-name fallback (``ambiguous``),
  Callable/connect/call string references, bare callable references, scene
  ``[connection]`` handlers and virtual dispatch (``override`` edges).
* Signals: declared, emitted and listened-to by name.

Usage:
    python tools/dep_graph.py [--root DIR] [--out DIR]       # write outputs
    python tools/dep_graph.py --callers SYMBOL               # query, no files
    python tools/dep_graph.py --refs PATH                    # query, no files

Outputs in --out: graph.json, mindmap.html, unused.md.
Known blind spots (see unused.md header): member variables/constants/enums are
not tracked individually; dynamic function names (``call("on_" + x)``) are not
resolved; res:// paths assembled from non-constant pieces cannot be resolved.
"""
from __future__ import print_function

import argparse
import bisect
import io
import json
import os
import re
import sys
import time

DEFAULT_ROOT = "M:/Bontago"
DEFAULT_OUT = "M:/Bontago-tools/scratch/depgraph/"

# Top-level directories that are not game content. docs/ files are added on
# demand when something in the game references them (res://docs/...).
EXCLUDED_TOP = frozenset([
    "addons", ".godot", ".git", "feedback", "build", ".claude", "Claude outputs",
    "docs", ".beads", ".agents", ".codex", ".cursor", "tmp", "node_modules", ".vscode", ".idea", "__pycache__",
])
EXCLUDED_ANY = frozenset([".godot", ".git", "__pycache__"])

KIND_BY_EXT = {
    ".gd": "script", ".tscn": "scene", ".scn": "scene",
    ".tres": "resource", ".res": "resource", ".material": "resource", ".theme": "resource",
    ".gdshader": "shader", ".gdshaderinc": "shader",
    ".png": "texture", ".jpg": "texture", ".jpeg": "texture", ".webp": "texture",
    ".svg": "texture", ".exr": "texture", ".hdr": "texture", ".bmp": "texture", ".tga": "texture",
    ".wav": "audio", ".ogg": "audio", ".mp3": "audio",
    ".glb": "model", ".gltf": "model", ".obj": "model", ".fbx": "model", ".dae": "model",
    ".ttf": "font", ".otf": "font", ".woff": "font", ".woff2": "font",
    ".json": "data", ".cfg": "data", ".txt": "data", ".csv": "data", ".ini": "data",
}
ASSET_KINDS = frozenset(["texture", "audio", "model", "font"])
SCAN_EXTS = frozenset([".gd", ".tscn", ".scn", ".tres", ".res", ".material", ".theme",
                       ".gdshader", ".gdshaderinc", ".json", ".cfg", ".txt", ".csv", ".ini",
                       ".gltf"])
MAX_SCAN_BYTES = 3 * 1024 * 1024

# Functions the engine (or GUT) calls; never reported as unused.
ENGINE_ROOTS = frozenset([
    "_ready", "_process", "_physics_process", "_input", "_unhandled_input",
    "_unhandled_key_input", "_shortcut_input", "_gui_input", "_draw", "_notification",
    "_init", "_static_init", "_enter_tree", "_exit_tree", "_get", "_set",
    "_get_property_list", "_property_can_revert", "_property_get_revert",
    "_validate_property", "_to_string", "_get_configuration_warnings",
    "_can_drop_data", "_drop_data", "_get_drag_data", "_integrate_forces", "_run",
    "_initialize", "_finalize", "_build", "_make_custom_tooltip", "_has_point",
    "_get_minimum_size", "_input_event", "_iter_init", "_iter_next", "_iter_get",
    "_unhandled_input_event", "_process_material", "_cleanup", "_parse_args",
    "before_all", "after_all", "before_each", "after_each", "_mouse_enter",
    "_mouse_exit", "_on_mouse_entered", "_on_mouse_exited", "_physics_interpolation",
    "_validate_property", "_get_tooltip", "_save_external_data", "_setup_local_to_scene",
    "_get_rid", "_get_audio_stream", "_instantiate_playback", "_mix", "_get_length",
    "_get_playback_type", "_get_stream_name", "_is_monophonic", "_get_beat_count",
])
ROOT_PREFIXES = ("_get_", "_set_")
CALLISH = ("call", "callable", "connect", "rpc", "has_method", "deferred", "group",
           "tween", "invoke", "method", "handler", "callback", "bind", "timeout", "emit")
SKIP_MEMBER_NAMES = frozenset(["emit", "connect", "disconnect", "new", "is_connected"])

IDENT_RE = re.compile(r"[A-Za-z_]\w*")
CALL_RE = re.compile(r"(?<![\w$%&^@])([A-Za-z_]\w*)\s*\(")
QREF_RE = re.compile(r"(?<![\w$%&^@.])([A-Za-z_]\w*)\s*\.\s*([A-Za-z_]\w*)\b(?!\s*\()")
BREF_RE = re.compile(r"(?<![\w$%&^@])(?:self\s*\.\s*)?([A-Za-z_]\w*)\b(?!\s*[\w(])")
FUNC_RE = re.compile(r"^(\s*)(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(")
CLASS_INNER_RE = re.compile(r"^(\s*)class\s+([A-Za-z_]\w*)")
CLASS_NAME_RE = re.compile(r"^\s*class_name\s+([A-Za-z_]\w*)", re.M)
EXTENDS_RE = re.compile(r"\bextends\s+([A-Za-z_]\w*(?:\.\w+)*|\"\")")
SIGNAL_RE = re.compile(r"^\s*signal\s+([A-Za-z_]\w*)", re.M)
EMIT_RE = re.compile(r"([A-Za-z_]\w*)\s*\.\s*emit\s*\(")
CONNECT_RE = re.compile(r"([A-Za-z_]\w*)\s*\.\s*connect\s*\(")
AWAIT_RE = re.compile(r"\bawait\s+(?:\w+\s*\.\s*)*([A-Za-z_]\w*)\s*(?!\()")
ALIAS_RE = re.compile(
    r"^\s*(?:static\s+)?(?:const|var)\s+(\w+)\s*(?::\s*\w+)?\s*:?=\s*(?:preload|load)\s*\(\s*[\"'](res://[^\"']+)[\"']",
    re.M)
TYPED_RE = re.compile(r"\b([a-z_]\w*)\s*:\s*([A-Z]\w*)\b(?!\s*\[)")
TYPED_NEW_RE = re.compile(r"\b([a-z_]\w*)\s*:?=\s*([A-Z]\w*)\s*\.\s*new\s*\(")
TSCN_CONN_RE = re.compile(
    r'^\[connection\s+signal="([^"]+)"\s+from="([^"]*)"\s+to="([^"]*)"\s+method="([^"]+)"', re.M)
EXT_RES_RE = re.compile(r"^\[ext_resource\b([^\]]*)\]", re.M)
EXT_ATTR_RE = re.compile(r'\b(type|path|uid|id)="([^"]*)"')
HEADER_UID_RE = re.compile(r'^\[gd_(?:scene|resource)\b[^\]]*\buid="(uid://[^"]+)"', re.M)
RES_STR_RE = re.compile(r"(?:res|uid)://[^\"'\s]*")
FMT_SPLIT_RE = re.compile(r"%[-+# 0-9.*]*[sdfxXobeEgGcv]|\{[^}]*\}")
QUOTE_RE = re.compile(r"\"\"\"|'''|\"|'|#")
DQ_RE = re.compile(r"\"(?:[^\"\\\n]|\\.)*\"?", re.S)
SQ_RE = re.compile(r"'(?:[^'\\\n]|\\.)*'?", re.S)
BLANK_RE = re.compile(r"[^\n]")
PLUS_IDENT_RE = re.compile(r"\s*\+\s*([A-Za-z_]\w*)\b")


# --------------------------------------------------------------------------
# Lexing
# --------------------------------------------------------------------------

def lex_gdscript(text):
    """Return (stripped_text, strings). Comments are blanked and string contents
    are blanked (quotes kept), preserving offsets and line numbers.
    strings: list of dicts {line, value, start, end}."""
    out = []
    strings = []
    n = len(text)
    line_starts = [0]
    idx = text.find("\n")
    while idx != -1:
        line_starts.append(idx + 1)
        idx = text.find("\n", idx + 1)
    pos = 0
    last = 0
    while True:
        m = QUOTE_RE.search(text, pos)
        if not m:
            break
        tok = m.group()
        s = m.start()
        if tok == "#":
            e = text.find("\n", s)
            if e < 0:
                e = n
            out.append(text[last:s])
            out.append(" " * (e - s))
            last = e
            pos = e
            continue
        if len(tok) == 3:
            e = text.find(tok, s + 3)
            end = n if e < 0 else e + 3
        else:
            mm = (DQ_RE if tok == '"' else SQ_RE).match(text, s)
            end = mm.end()
        raw = text[s:end]
        closed = len(raw) >= 2 * len(tok) and raw.endswith(tok)
        content = raw[len(tok):-len(tok)] if closed else raw[len(tok):]
        strings.append({"line": bisect.bisect_right(line_starts, s), "value": content,
                        "start": s, "end": end})
        out.append(text[last:s])
        out.append(tok + BLANK_RE.sub(" ", content) + (tok if closed else ""))
        last = end
        pos = end
    out.append(text[last:])
    return "".join(out), strings


def _indent(line):
    return len(line) - len(line.lstrip())


def parse_functions(path, stripped):
    """Return (funcs, owner) where owner[line_no] -> func index (1-based lines)."""
    lines = stripped.split("\n")
    funcs = []
    class_stack = []  # (indent, name)
    nlines = len(lines)
    owner = [None] * (nlines + 2)
    i = 0
    while i < nlines:
        raw = lines[i]
        body = raw.strip()
        if not body:
            i += 1
            continue
        ind = _indent(raw.expandtabs(4))
        cm = CLASS_INNER_RE.match(raw.expandtabs(4))
        if cm:
            while class_stack and class_stack[-1][0] >= ind:
                class_stack.pop()
            class_stack.append((ind, cm.group(2)))
            i += 1
            continue
        fm = FUNC_RE.match(raw.expandtabs(4))
        if not fm:
            while class_stack and class_stack[-1][0] >= ind and not body.startswith((")", "]", "}")):
                class_stack.pop()
            i += 1
            continue
        while class_stack and class_stack[-1][0] >= ind:
            class_stack.pop()
        name = fm.group(2)
        is_static = bool(re.match(r"^\s*static\s+func\b", raw))
        # Header paren balance
        depth = 0
        j = i
        while j < nlines:
            depth += sum(lines[j].count(c) for c in "([{") - sum(lines[j].count(c) for c in ")]}")
            if depth <= 0:
                break
            j += 1
        end = j
        k = j + 1
        while k < nlines:
            lb = lines[k]
            if lb.strip():
                if _indent(lb.expandtabs(4)) <= ind and not lb.strip().startswith(")"):
                    break
                end = k
            k += 1
        prev = ""
        p = i - 1
        while p >= 0 and not lines[p].strip():
            p -= 1
        if p >= 0:
            prev = lines[p].strip()
        is_rpc = "@rpc" in raw or prev.startswith("@rpc")
        cls = ".".join(c[1] for c in class_stack)
        fid = path + ":" + (cls + "." if cls else "") + name
        funcs.append({"id": fid, "file": path, "name": name, "line": i + 1, "end": end + 1,
                      "static": is_static, "cls": cls, "rpc": is_rpc, "root": None})
        for ln in range(i + 1, end + 2):
            owner[ln] = len(funcs) - 1
        i = end + 1
    # Duplicate ids (e.g. same name repeated) get the line appended.
    seen = {}
    for f in funcs:
        if f["id"] in seen:
            f["id"] = "%s#%d" % (f["id"], f["line"])
        seen[f["id"]] = True
    return funcs, owner


def category(path):
    top = path.split("/", 1)[0]
    if top == "tests":
        return "test"
    if top == "tools":
        return "tool"
    if top == "source_art":
        return "source"
    return "game"


# --------------------------------------------------------------------------
# Graph building
# --------------------------------------------------------------------------

class Builder(object):
    def __init__(self, root):
        self.root = os.path.abspath(root)
        self.files = {}        # path -> node dict
        self.texts = {}
        self.fe = {}           # (src,dst,kind) -> edge dict
        self.ce = {}           # (src,dst,kind) -> edge dict
        self.funcs = {}        # id -> func dict
        self.file_funcs = {}   # path -> {name: [ids]}
        self.script = {}       # path -> script analysis
        self.uids = {}
        self.classes = {}      # class_name -> path
        self.inner_classes = {}  # inner name -> [(path, cls)]
        self.autoloads = {}    # name -> path (singletons only)
        self.autoload_all = {}
        self.sidecars = []
        self.broken = []
        self.dynamic = []
        self.external = {}
        self.signals = {}
        self.skipped_ext = {}
        self.funcs_by_name = {}

    # ---- helpers -------------------------------------------------------
    def abs(self, rel):
        return os.path.join(self.root, rel.replace("/", os.sep))

    def add_fe(self, src, dst, kind, line=0, pattern=None):
        if src == dst:
            return
        key = (src, dst, kind)
        e = self.fe.get(key)
        if e is None:
            e = {"src": src, "dst": dst, "kind": kind, "line": line, "count": 0}
            if pattern:
                e["pattern"] = pattern
            self.fe[key] = e
        e["count"] += 1

    def add_ce(self, src, dst, kind, line=0, amb=False):
        if src == dst:
            return
        key = (src, dst, kind)
        e = self.ce.get(key)
        if e is None:
            self.ce[key] = {"src": src, "dst": dst, "kind": kind, "line": line, "amb": amb}

    # ---- pass 0: walk --------------------------------------------------
    def walk(self):
        for dirpath, dirnames, filenames in os.walk(self.root):
            rel_dir = os.path.relpath(dirpath, self.root).replace("\\", "/")
            top = "" if rel_dir == "." else rel_dir.split("/")[0]
            if rel_dir == ".":
                dirnames[:] = [d for d in dirnames if d not in EXCLUDED_TOP]
            else:
                dirnames[:] = [d for d in dirnames if d not in EXCLUDED_ANY]
            for fn in filenames:
                rel = fn if rel_dir == "." else rel_dir + "/" + fn
                self.consider(rel)

    def consider(self, rel):
        ext = os.path.splitext(rel)[1].lower()
        if rel.endswith(".import") or rel.endswith(".uid"):
            src = rel[:rel.rfind(".")]
            self.sidecars.append({"path": rel, "source": src,
                                  "kind": "import" if rel.endswith(".import") else "uid",
                                  "orphan": not os.path.exists(self.abs(src))})
            return
        name = os.path.basename(rel)
        if rel in ("project.godot", "export_presets.cfg", "override.cfg"):
            kind = "config"
        elif ext in KIND_BY_EXT:
            kind = KIND_BY_EXT[ext]
        else:
            self.skipped_ext[ext or name] = self.skipped_ext.get(ext or name, 0) + 1
            return
        try:
            size = os.path.getsize(self.abs(rel))
        except OSError:
            size = 0
        self.files[rel] = {"path": rel, "kind": kind, "cat": category(rel), "size": size,
                           "class_name": None, "extends": None, "uid": None, "loc": 0}

    # ---- pass 1: read, uids, classes, functions -----------------------
    def read_text(self, rel):
        ext = os.path.splitext(rel)[1].lower()
        if ext not in SCAN_EXTS and rel not in ("project.godot", "export_presets.cfg", "override.cfg"):
            return None
        try:
            if os.path.getsize(self.abs(rel)) > MAX_SCAN_BYTES:
                return None
            with open(self.abs(rel), "rb") as fh:
                data = fh.read()
        except OSError:
            return None
        return data.decode("utf-8", "replace") if ext not in (".res", ".scn") else data.decode("latin-1")

    def load_uids(self):
        for sc in self.sidecars:
            if sc["orphan"]:
                continue
            try:
                with open(self.abs(sc["path"]), "r", encoding="utf-8", errors="replace") as fh:
                    head = fh.read(4096)
            except OSError:
                continue
            if sc["kind"] == "uid":
                m = re.search(r"uid://\S+", head)
            else:
                m = re.search(r'^uid="(uid://[^"]+)"', head, re.M)
                if m:
                    self.uids[m.group(1)] = sc["source"]
                    continue
                m = None
            if m:
                self.uids[m.group().strip()] = sc["source"]

    def pass1(self):
        for rel in sorted(self.files):
            text = self.read_text(rel)
            if text is None:
                continue
            node = self.files[rel]
            node["loc"] = text.count("\n") + 1
            if rel.endswith((".tscn", ".tres")):
                m = HEADER_UID_RE.search(text)
                if m:
                    self.uids.setdefault(m.group(1), rel)
                    node["uid"] = m.group(1)
            if node["kind"] == "script":
                self.analyze_script(rel, text)
            else:
                self.texts[rel] = text
        for rel in self.files:
            for u, p in self.uids.items():
                pass
            break
        for u, p in self.uids.items():
            if p in self.files and not self.files[p]["uid"]:
                self.files[p]["uid"] = u

    def analyze_script(self, rel, text):
        stripped, strings = lex_gdscript(text)
        funcs, owner = parse_functions(rel, stripped)
        node = self.files[rel]
        cm = CLASS_NAME_RE.search(stripped)
        if cm:
            node["class_name"] = cm.group(1)
            self.classes[cm.group(1)] = rel
        ext_val = None
        em = EXTENDS_RE.search(stripped)
        if em:
            ext_val = em.group(1)
            if ext_val == '""':
                ln = stripped.count("\n", 0, em.start()) + 1
                for s in strings:
                    if s["line"] == ln and s["value"].startswith("res://"):
                        ext_val = s["value"]
                        break
        node["extends"] = ext_val
        sl = stripped.split("\n")
        data = {"text": text, "stripped": stripped, "lines": sl, "strings": strings,
                "funcs": funcs, "owner": owner, "aliases": {}, "typed": {}, "inner": set()}
        for f in funcs:
            self.funcs[f["id"]] = f
            self.file_funcs.setdefault(rel, {}).setdefault(f["name"], []).append(f["id"])
            self.funcs_by_name.setdefault(f["name"], []).append(f["id"])
            if f["cls"]:
                data["inner"].add(f["cls"].split(".")[-1])
        for i, line in enumerate(sl):
            cm2 = CLASS_INNER_RE.match(line)
            if cm2:
                data["inner"].add(cm2.group(2))
        for nm in data["inner"]:
            self.inner_classes.setdefault(nm, []).append(rel)
        for m in ALIAS_RE.finditer(text):
            data["aliases"][m.group(1)] = m.group(2)[len("res://"):]
        for m in SIGNAL_RE.finditer(stripped):
            ln = stripped.count("\n", 0, m.start()) + 1
            sg = self.signals.setdefault(m.group(1), {"decl": [], "emit": [], "listen": []})
            sg["decl"].append("%s:%d" % (rel, ln))
        self.script[rel] = data

    # ---- autoloads / project ------------------------------------------
    def parse_project(self):
        text = self.texts.get("project.godot")
        if text is None:
            return
        section = None
        for raw in text.split("\n"):
            line = raw.strip()
            if line.startswith("["):
                section = line.strip("[]")
                continue
            if section == "autoload" and "=" in line:
                name, val = line.split("=", 1)
                val = val.strip().strip('"')
                star = val.startswith("*")
                val = val.lstrip("*")
                tgt = self.resolve_ref(val)
                if tgt:
                    self.autoload_all[name.strip()] = tgt
                    if star:
                        self.autoloads[name.strip()] = tgt

    # ---- reference resolution ------------------------------------------
    def resolve_ref(self, ref):
        """Return a node path for a res:// or uid:// string, or None."""
        ref = ref.split("::")[0]
        if ref.startswith("uid://"):
            return self.uids.get(ref)
        if ref.startswith("res://"):
            rel = ref[len("res://"):]
            if rel in self.files:
                return rel
        return None

    def note_ref(self, src, ref, kind, line):
        """Resolve a literal reference and add an edge or record why not."""
        ref = ref.strip().split("::")[0]
        tgt = self.resolve_ref(ref)
        if tgt:
            self.add_fe(src, tgt, kind, line)
            return
        if ref.startswith("uid://"):
            self.broken.append({"src": src, "ref": ref, "line": line, "why": "unknown uid"})
            return
        rel = ref[len("res://"):]
        if not rel:
            return
        ap = self.abs(rel)
        top = rel.split("/")[0]
        if rel.endswith("/") or os.path.isdir(ap):
            self.dynamic_dir(src, rel.rstrip("/"), line, ref)
        elif top in ("addons", ".godot", "feedback", "build", ".claude"):
            self.external[ref] = self.external.get(ref, 0) + 1
        elif os.path.isfile(ap) and top == "docs":
            self.adopt_external(rel)
            self.add_fe(src, rel, kind, line)
        elif os.path.isfile(ap):
            ext = os.path.splitext(rel)[1].lower()
            if ext in KIND_BY_EXT or rel.endswith((".import", ".uid")):
                # known type but skipped/sidecar (e.g. direct .import ref)
                self.external[ref] = self.external.get(ref, 0) + 1
            else:
                self.external[ref] = self.external.get(ref, 0) + 1
        else:
            self.broken.append({"src": src, "ref": ref, "line": line, "why": "missing file"})

    def adopt_external(self, rel):
        if rel in self.files:
            return
        ext = os.path.splitext(rel)[1].lower()
        self.files[rel] = {"path": rel, "kind": KIND_BY_EXT.get(ext, "other"), "cat": "game",
                           "size": 0, "class_name": None, "extends": None, "uid": None, "loc": 0}
        self.sidecars.append({"path": rel + ".import", "source": rel, "kind": "import",
                              "orphan": False}) if os.path.exists(self.abs(rel + ".import")) else None

    def dynamic_dir(self, src, rel_dir, line, ref):
        prefix = rel_dir + "/"
        targets = [p for p in self.files if p.startswith(prefix)]
        self.dynamic.append({"src": src, "pattern": ref, "line": line, "kind": "dir",
                             "targets": len(targets)})
        for t in targets:
            self.add_fe(src, t, "dynamic", line, ref)

    def dynamic_pattern(self, src, content, trailing, line):
        pat = content
        if FMT_SPLIT_RE.search(content):
            parts = FMT_SPLIT_RE.split(content)
            rx = ".*".join(re.escape(p) for p in parts)
            if trailing:
                rx += ".*"
        else:
            rx = re.escape(content) + ".*"
        rel_prefix = FMT_SPLIT_RE.split(content)[0][len("res://"):]
        try:
            cre = re.compile("^" + rx.replace(re.escape("res://"), "", 1) + "$")
        except re.error:
            return
        targets = []
        if rel_prefix:
            for p in self.files:
                if p.startswith(rel_prefix) and cre.match(p):
                    targets.append(p)
        self.dynamic.append({"src": src, "pattern": pat, "line": line,
                             "kind": "concat" if trailing else "format", "targets": len(targets)})
        for t in targets:
            self.add_fe(src, t, "dynamic", line, pat)

    # ---- pass 2: file edges -------------------------------------------
    def file_edges(self):
        for rel, text in self.texts.items():
            if rel.endswith(".gltf"):
                self.gltf_edges(rel, text)
                continue
            if rel.endswith(".import"):
                continue
            seen_ext_paths = set()
            if rel.endswith((".tscn", ".tres")):
                for m in EXT_RES_RE.finditer(text):
                    attrs = dict(EXT_ATTR_RE.findall(m.group(1)))
                    line = text.count("\n", 0, m.start()) + 1
                    tgt = None
                    if attrs.get("uid"):
                        tgt = self.uids.get(attrs["uid"])
                    if tgt is None and attrs.get("path"):
                        tgt = self.resolve_ref(attrs["path"])
                        if tgt is None:
                            self.note_ref(rel, attrs["path"], "ext_resource", line)
                    if tgt:
                        self.add_fe(rel, tgt, "ext_resource", line)
                    elif attrs.get("uid") and not attrs.get("path"):
                        self.broken.append({"src": rel, "ref": attrs["uid"], "line": line,
                                            "why": "unknown uid"})
                    if attrs.get("path"):
                        seen_ext_paths.add(attrs["path"])
                    if attrs.get("uid"):
                        seen_ext_paths.add(attrs["uid"])
            for m in RES_STR_RE.finditer(text):
                ref = m.group()
                if ref in seen_ext_paths:
                    continue
                line = text.count("\n", 0, m.start()) + 1
                kind = "path"
                if rel == "project.godot":
                    kind = "project"
                elif rel == "export_presets.cfg":
                    kind = "export"
                self.note_ref(rel, ref, kind, line)
            if rel == "project.godot":
                for name, tgt in self.autoload_all.items():
                    self.add_fe(rel, tgt, "autoload", 0)
            if rel.endswith(".gdshader") or rel.endswith(".gdshaderinc"):
                for m in re.finditer(r'#include\s+"([^"]+)"', text):
                    inc = m.group(1)
                    if not inc.startswith("res://"):
                        cand = os.path.normpath(os.path.join(os.path.dirname(rel), inc)).replace("\\", "/")
                        if cand in self.files:
                            self.add_fe(rel, cand, "path", text.count("\n", 0, m.start()) + 1)

    def gltf_edges(self, rel, text):
        try:
            data = json.loads(text)
        except ValueError:
            return
        base = os.path.dirname(rel)
        for key in ("images", "buffers"):
            for ent in data.get(key, []):
                uri = ent.get("uri")
                if uri and not uri.startswith("data:"):
                    cand = os.path.normpath(os.path.join(base, uri)).replace("\\", "/")
                    if cand in self.files:
                        self.add_fe(rel, cand, "path", 0)

    def script_file_edges(self):
        class_names = set(self.classes)
        auto_names = set(self.autoloads)
        for rel, d in self.script.items():
            # string literals
            strings = d["strings"]
            stripped = d["stripped"]
            for s in strings:
                v = s["value"]
                if not v.startswith(("res://", "uid://")):
                    continue
                v = v.strip()
                trailing = bool(re.match(r"\s*\+", stripped[s["end"]:s["end"] + 4])) if s["end"] < len(stripped) else False
                if v == "res://" and trailing:
                    pm = PLUS_IDENT_RE.match(stripped, s["end"])
                    if pm:
                        cm = re.search(r"const\s+%s\s*(?::\s*\w+)?\s*:?=\s*\"([^\"]*)\"" % re.escape(pm.group(1)),
                                       d["text"])
                        if cm:
                            v = "res://" + cm.group(1)
                if FMT_SPLIT_RE.search(v) or (trailing and v.startswith("res://")):
                    if v == "res://":
                        self.dynamic.append({"src": rel, "pattern": v, "line": s["line"],
                                             "kind": "unresolved", "targets": 0})
                    else:
                        self.dynamic_pattern(rel, v, trailing, s["line"])
                else:
                    pre = re.search(r"\bpreload\s*\(\s*$", stripped[max(0, s["start"] - 40):s["start"]])
                    self.note_ref(rel, v, "preload" if pre else "path", s["line"])
            # class_name / autoload usage and extends
            first = {}
            for i, line in enumerate(d["lines"], 1):
                if not line.strip():
                    continue
                for ident in IDENT_RE.findall(line):
                    if (ident in class_names or ident in auto_names) and ident not in first:
                        first[ident] = i
            own = self.files[rel]["class_name"]
            for ident, ln in first.items():
                if ident == own:
                    continue
                if ident in auto_names:
                    self.add_fe(rel, self.autoloads[ident], "autoload_use", ln)
                else:
                    self.add_fe(rel, self.classes[ident], "class", ln)
            parent = self.parent_of(rel)
            if parent:
                self.add_fe(rel, parent, "extends", 1)

    def parent_of(self, rel):
        ext = self.files[rel].get("extends")
        if not ext:
            return None
        if ext.startswith("res://"):
            return self.resolve_ref(ext)
        head = ext.split(".")[0]
        p = self.classes.get(head)
        return p if p != rel else None

    def chain(self, rel):
        out = []
        cur = rel
        seen = set()
        while cur and cur not in seen:
            seen.add(cur)
            out.append(cur)
            cur = self.parent_of(cur) if cur in self.files else None
        return out

    # ---- pass 3: functions / calls -------------------------------------
    def mark_roots(self):
        for f in self.funcs.values():
            n = f["name"]
            cat = category(f["file"])
            if f["rpc"]:
                f["root"] = "rpc"
            elif n in ENGINE_ROOTS or n.startswith(ROOT_PREFIXES):
                f["root"] = "engine"
            elif cat == "test" and n.startswith("test_"):
                f["root"] = "test"

    def lookup(self, rel, name, cls=None):
        """Find funcs called name in rel's inheritance chain."""
        for c in self.chain(rel):
            ids = self.file_funcs.get(c, {}).get(name)
            if ids:
                if cls is not None:
                    pick = [i for i in ids if self.funcs[i]["cls"] == cls]
                    if pick:
                        return pick
                return ids[:1] if len(ids) > 1 and False else ids
        return []

    def typed_vars(self, rel, d):
        stripped = d["stripped"]
        found = {}
        for rx in (TYPED_RE, TYPED_NEW_RE):
            for m in rx.finditer(stripped):
                var, cls = m.group(1), m.group(2)
                if cls in self.classes or cls in d["aliases"] or cls in d["inner"]:
                    if var in found and found[var] != cls:
                        found[var] = None
                    elif var not in found:
                        found[var] = cls
        return dict((k, v) for k, v in found.items() if v)

    def target_file_of_name(self, rel, d, name):
        if name in d["aliases"]:
            return d["aliases"][name] if d["aliases"][name] in self.files else None
        if name in self.autoloads:
            return self.autoloads[name]
        if name in self.classes:
            return self.classes[name]
        return None

    def resolve_member(self, rel, d, recv, name, caller_cls, typed):
        """Return (list of dst ids, kind, ambiguous)."""
        if recv == "self":
            ids = self.lookup(rel, name)
            return ids, "self", False
        if recv == "super":
            par = self.parent_of(rel)
            return (self.lookup(par, name) if par else []), "self", False
        tgt = self.target_file_of_name(rel, d, recv)
        if tgt:
            kind = "autoload" if recv in self.autoloads else "class"
            return self.lookup(tgt, name), kind, False
        if recv in d["inner"]:
            ids = [i for i in self.file_funcs.get(rel, {}).get(name, [])
                   if self.funcs[i]["cls"].split(".")[-1:] == [recv]]
            return ids, "class", False
        if recv in typed:
            cls = typed[recv]
            tgt = self.target_file_of_name(rel, d, cls)
            if tgt:
                return self.lookup(tgt, name), "typed", False
            if cls in d["inner"]:
                ids = [i for i in self.file_funcs.get(rel, {}).get(name, [])
                       if self.funcs[i]["cls"].split(".")[-1:] == [cls]]
                return ids, "typed", False
        cands = self.funcs_by_name.get(name, [])
        # Instance calls never target static-only helper duplicates differently; keep all.
        if len(cands) == 1:
            return cands, "unique", False
        if len(cands) > 1:
            return cands, "ambiguous", True
        return [], "none", False

    def analyze_calls(self):
        func_name_set = set(self.funcs_by_name)
        signal_names = set(self.signals)
        for rel, d in self.script.items():
            typed = self.typed_vars(rel, d)
            funcs = d["funcs"]
            owner = d["owner"]
            lines = d["lines"]
            chain_names = set()
            for c in self.chain(rel):
                chain_names.update(self.file_funcs.get(c, {}).keys())
            for ln, line in enumerate(lines, 1):
                if not line.strip():
                    continue
                oi = owner[ln] if ln < len(owner) else None
                src = funcs[oi]["id"] if oi is not None else rel
                caller_cls = funcs[oi]["cls"] if oi is not None else ""
                caller_name = funcs[oi]["name"] if oi is not None else ""
                is_def = FUNC_RE.match(line.expandtabs(4)) is not None
                for m in CALL_RE.finditer(line):
                    name = m.group(1)
                    start = m.start(1)
                    prefix = line[:start].rstrip()
                    if prefix.endswith("func") and re.search(r"\bfunc$", prefix):
                        continue
                    if prefix.endswith("."):
                        rm = re.search(r"([A-Za-z_]\w*)$", prefix[:-1].rstrip())
                        recv = rm.group(1) if rm else None
                        if name in SKIP_MEMBER_NAMES and (recv in signal_names or name in ("emit", "new", "connect", "disconnect")):
                            continue
                        if name not in func_name_set and recv not in ("super",):
                            continue
                        ids, kind, amb = self.resolve_member(rel, d, recv, name, caller_cls, typed)
                        for i in ids:
                            self.add_ce(src, i, kind, ln, amb)
                    else:
                        if name == "super":
                            par = self.parent_of(rel)
                            for i in (self.lookup(par, caller_name) if par else []):
                                self.add_ce(src, i, "self", ln)
                            continue
                        if name not in func_name_set:
                            continue
                        ids = self.lookup(rel, name, caller_cls)
                        for i in ids:
                            self.add_ce(src, i, "self", ln)
                if is_def:
                    continue
                # callable references without parentheses
                for m in QREF_RE.finditer(line):
                    recv, name = m.group(1), m.group(2)
                    if name not in func_name_set or name in SKIP_MEMBER_NAMES:
                        continue
                    if recv == "self":
                        ids = self.lookup(rel, name)
                    else:
                        tgt = self.target_file_of_name(rel, d, recv)
                        if not tgt and recv in typed:
                            tgt = self.target_file_of_name(rel, d, typed[recv])
                        if not tgt:
                            continue
                        ids = self.lookup(tgt, name)
                    for i in ids:
                        self.add_ce(src, i, "ref", ln)
                for m in BREF_RE.finditer(line):
                    name = m.group(1)
                    if name in chain_names:
                        # skip when this identifier is a plain property access (preceded by '.')
                        for i in self.lookup(rel, name, caller_cls):
                            if i != src:
                                self.add_ce(src, i, "ref", ln)
            # string references
            for s in d["strings"]:
                v = s["value"]
                if not v or not IDENT_RE.fullmatch(v):
                    continue
                if v in signal_names and v not in func_name_set:
                    continue
                ln = s["line"]
                low = d["text"].split("\n")[ln - 1].lower() if ln - 1 < len(lines) else ""
                if not any(k in low for k in CALLISH):
                    continue
                if v in func_name_set:
                    oi = owner[ln] if ln < len(owner) else None
                    src = funcs[oi]["id"] if oi is not None else rel
                    ids = self.lookup(rel, v)
                    amb = False
                    if not ids:
                        ids = self.funcs_by_name.get(v, [])
                        amb = len(ids) > 1
                    for i in ids:
                        self.add_ce(src, i, "string", ln, amb)
            self.collect_signals(rel, d)
        self.scene_connections()
        self.override_edges()

    def collect_signals(self, rel, d):
        names = set(self.signals)
        owner = d["owner"]
        funcs = d["funcs"]

        def src_of(ln):
            oi = owner[ln] if ln < len(owner) else None
            return funcs[oi]["id"] if oi is not None else rel
        for ln, line in enumerate(d["lines"], 1):
            if not line.strip():
                continue
            for m in EMIT_RE.finditer(line):
                if m.group(1) in names:
                    self.signals[m.group(1)]["emit"].append(src_of(ln))
            for m in CONNECT_RE.finditer(line):
                if m.group(1) in names:
                    self.signals[m.group(1)]["listen"].append(src_of(ln))
            for m in AWAIT_RE.finditer(line):
                if m.group(1) in names:
                    self.signals[m.group(1)]["listen"].append(src_of(ln))
        text_lines = d["text"].split("\n")
        for s in d["strings"]:
            if s["value"] in names and s["line"] - 1 < len(text_lines):
                low = text_lines[s["line"] - 1]
                if "emit_signal" in low:
                    self.signals[s["value"]]["emit"].append(src_of(s["line"]))
                elif ".connect(" in low or "is_connected" in low:
                    self.signals[s["value"]]["listen"].append(src_of(s["line"]))

    def scene_connections(self):
        for rel, text in self.texts.items():
            if not rel.endswith(".tscn"):
                continue
            scripts = []
            for m in EXT_RES_RE.finditer(text):
                attrs = dict(EXT_ATTR_RE.findall(m.group(1)))
                if attrs.get("type") == "Script":
                    tgt = self.uids.get(attrs.get("uid", "")) or self.resolve_ref(attrs.get("path", ""))
                    if tgt:
                        scripts.append(tgt)
            for m in TSCN_CONN_RE.finditer(text):
                sig, _frm, _to, method = m.groups()
                line = text.count("\n", 0, m.start()) + 1
                if sig in self.signals:
                    self.signals[sig]["listen"].append(rel)
                ids = []
                for sc in scripts:
                    ids = self.lookup(sc, method)
                    if ids:
                        break
                amb = False
                if not ids:
                    ids = self.funcs_by_name.get(method, [])
                    amb = len(ids) > 1
                for i in ids:
                    self.add_ce(rel, i, "scene", line, amb)

    def override_edges(self):
        for rel in self.script:
            chain = self.chain(rel)
            if len(chain) < 2:
                continue
            for name, ids in self.file_funcs.get(rel, {}).items():
                for anc in chain[1:]:
                    for aid in self.file_funcs.get(anc, {}).get(name, []):
                        for i in ids:
                            self.add_ce(aid, i, "override", 0)

    # ---- driver ---------------------------------------------------------
    def build(self):
        self.walk()
        self.load_uids()
        self.pass1()
        self.parse_project()
        self.mark_roots()
        self.file_edges()
        self.script_file_edges()
        self.analyze_calls()
        return self.finish()

    def finish(self):
        for rel in list(self.files):
            self.files[rel]["funcs"] = [f["id"] for f in self.script.get(rel, {}).get("funcs", [])]
        status = compute_status(self.files, list(self.fe.values()))
        for p, st in status.items():
            self.files[p]["status"] = st
        graph = {
            "meta": {"root": self.root, "files": len(self.files), "funcs": len(self.funcs),
                     "file_edges": len(self.fe), "call_edges": len(self.ce),
                     "skipped_ext": self.skipped_ext, "generated": time.strftime("%Y-%m-%d %H:%M:%S")},
            "files": self.files,
            "funcs": self.funcs,
            "file_edges": list(self.fe.values()),
            "call_edges": list(self.ce.values()),
            "signals": self.signals,
            "autoloads": self.autoload_all,
            "classes": self.classes,
            "uids": self.uids,
            "sidecars": self.sidecars,
            "broken": self.broken,
            "dynamic": self.dynamic,
            "external": self.external,
        }
        graph["core_scene_tree"] = core_scene_tree_violations(self.files, self.classes, self.script)
        return graph


def _bfs(starts, adj):
    seen = set(starts)
    stack = list(starts)
    while stack:
        cur = stack.pop()
        for nxt in adj.get(cur, ()):
            if nxt not in seen:
                seen.add(nxt)
                stack.append(nxt)
    return seen


def compute_status(files, file_edges):
    """Status per file: root / live / dynamic-only / test-tool-only / unreachable."""
    strict = {}
    loose = {}
    for e in file_edges:
        loose.setdefault(e["src"], []).append(e["dst"])
        if e["kind"] != "dynamic":
            strict.setdefault(e["src"], []).append(e["dst"])
    roots = [p for p, n in files.items() if n["kind"] == "config"]
    live_strict = _bfs(roots, strict)
    live_loose = _bfs(roots, loose)
    tool_roots = [p for p, n in files.items() if n["cat"] in ("test", "tool", "source")]
    tool_reach = _bfs(tool_roots, loose)
    status = {}
    for p, n in files.items():
        if n["kind"] == "config":
            status[p] = "root"
        elif p in live_strict:
            status[p] = "live"
        elif p in live_loose:
            status[p] = "dynamic-only"
        elif n["cat"] in ("test", "tool", "source"):
            status[p] = "test-tool-root"
        elif p in tool_reach:
            status[p] = "test-tool-only"
        else:
            status[p] = "unreachable"
    return status


def build_graph(root):
    return Builder(root).build()


# --------------------------------------------------------------------------
# Function liveness and the unused report
# --------------------------------------------------------------------------

def func_liveness(graph):
    """Return dict func id -> 'live' | 'ambiguous-only' | 'test-tool-only' | 'dead'."""
    funcs = graph["funcs"]
    files = graph["files"]
    adj_strict = {}
    adj_loose = {}
    for e in graph["call_edges"]:
        adj_loose.setdefault(e["src"], []).append(e["dst"])
        if not e["amb"]:
            adj_strict.setdefault(e["src"], []).append(e["dst"])

    def seeds(cats, statuses=None):
        out = []
        for fid, f in funcs.items():
            fn = files.get(f["file"])
            if fn is None or fn["cat"] not in cats:
                continue
            if statuses and fn["status"] not in statuses:
                continue
            if f["root"]:
                out.append(fid)
        # file-level sources (scene connections, module-level code)
        for e in graph["call_edges"]:
            if e["src"] in files and files[e["src"]]["cat"] in cats:
                if not statuses or files[e["src"]]["status"] in statuses:
                    out.append(e["dst"])
        for p, n in files.items():
            if n["cat"] in cats and (not statuses or n["status"] in statuses):
                for e in ():
                    pass
        return out

    live_ok = ("root", "live", "dynamic-only")
    game_seeds = seeds(("game",), live_ok)
    # weak roots: _on_* handlers in live game files
    for fid, f in funcs.items():
        if f["name"].startswith("_on_") and files[f["file"]]["cat"] == "game" \
                and files[f["file"]]["status"] in live_ok:
            game_seeds.append(fid)
    # Calls made from module-level code of live game files.
    module_seeds = []
    for e in graph["call_edges"]:
        if e["src"] in files and files[e["src"]]["cat"] == "game" and files[e["src"]]["status"] in live_ok:
            module_seeds.append(e["dst"])
    strict = _bfs(game_seeds + module_seeds, adj_strict)
    loose = _bfs(game_seeds + module_seeds, adj_loose)
    other_seeds = seeds(("test", "tool", "source"))
    other = _bfs(other_seeds, adj_loose)
    res = {}
    for fid in funcs:
        if fid in strict:
            res[fid] = "live"
        elif fid in loose:
            res[fid] = "ambiguous-only"
        elif fid in other:
            res[fid] = "test-tool-only"
        else:
            res[fid] = "dead"
    return res


def analyze(graph):
    files = graph["files"]
    funcs = graph["funcs"]
    out = {}
    out["broken"] = graph["broken"]
    out["orphan_sidecars"] = [s for s in graph["sidecars"] if s["orphan"]]
    inbound = {}
    for e in graph["file_edges"]:
        inbound.setdefault(e["dst"], []).append(e)
    sections = {"unreachable": [], "dynamic-only": [], "test-tool-only": []}
    no_inbound = []
    for p, n in sorted(files.items()):
        st = n["status"]
        if st in sections and n["cat"] == "game":
            sections[st].append(p)
        if n["cat"] == "game" and n["kind"] != "config" and not inbound.get(p):
            no_inbound.append(p)
    out["files"] = sections
    out["no_inbound"] = no_inbound
    live = func_liveness(graph)
    callers = {}
    for e in graph["call_edges"]:
        callers.setdefault(e["dst"], []).append(e)
    fsec = {"zero_callers": [], "dead_chain": [], "ambiguous_only": [], "test_tool_only": [],
            "weak_on": [], "dead_files": 0}
    for fid, f in sorted(funcs.items()):
        fn = files[f["file"]]
        if fn["cat"] != "game" or f["root"]:
            continue
        if fn["status"] not in ("root", "live", "dynamic-only"):
            fsec["dead_files"] += 1
            continue
        state = live[fid]
        cs = [c for c in callers.get(fid, []) if c["src"] != fid and c["kind"] != "override"]
        has_override_parent = any(c["kind"] == "override" for c in callers.get(fid, []))
        if f["name"].startswith("_on_"):
            if not cs:
                fsec["weak_on"].append(fid)
            continue
        if state == "live":
            continue
        if state == "ambiguous-only":
            fsec["ambiguous_only"].append(fid)
        elif state == "test-tool-only":
            fsec["test_tool_only"].append(fid)
        else:
            if not cs and not has_override_parent:
                fsec["zero_callers"].append(fid)
            else:
                fsec["dead_chain"].append(fid)
    out["funcs"] = fsec
    sig_unused = {"never_emitted": [], "never_listened": []}
    for name, s in sorted(graph["signals"].items()):
        if not s["decl"]:
            continue
        if not s["emit"]:
            sig_unused["never_emitted"].append(name)
        elif not s["listen"]:
            sig_unused["never_listened"].append(name)
    out["signals"] = sig_unused
    return out


def render_unused_md(graph, an):
    files = graph["files"]
    meta = graph["meta"]
    L = []
    L.append("# Unused / dead-code report")
    L.append("")
    L.append("Generated by tools/dep_graph.py from `%s` at %s. Static analysis, best effort:" %
             (meta["root"], meta["generated"]))
    L.append("treat every entry as a candidate to verify with grep, not a deletion order.")
    L.append("")
    L.append("Blind spots: member vars/consts/enums are not tracked; dynamic call names "
             "(`call(\"on_\" + x)`) and non-constant res:// concatenations are not resolved; "
             "assets referenced only from binary resources are invisible. Engine callbacks, "
             "@rpc funcs and test_* funcs are roots; `_on_*` handlers are weak roots.")
    L.append("Roots: project.godot (main scene, autoloads, icon), export_presets.cfg, "
             "override.cfg. tests/, tools/ and source_art/ are reported separately.")
    L.append("")
    cnt = {}
    for n in files.values():
        cnt[n["status"]] = cnt.get(n["status"], 0) + 1
    L.append("## Summary")
    L.append("")
    L.append("- Files: %d, functions: %d, file edges: %d, call edges: %d" %
             (meta["files"], meta["funcs"], meta["file_edges"], meta["call_edges"]))
    L.append("- File status counts: " + ", ".join("%s=%d" % kv for kv in sorted(cnt.items())))
    fs = an["funcs"]
    L.append("- Game files with no inbound edge at all: %d" % len(an["no_inbound"]))
    L.append("- Game files unreachable from live roots: %d; reachable only via dynamic paths: %d; "
             "reachable only from tests/tools: %d" %
             (len(an["files"]["unreachable"]), len(an["files"]["dynamic-only"]),
              len(an["files"]["test-tool-only"])))
    L.append("- Functions: zero callers %d, only dead callers %d, only ambiguous-name callers %d, "
             "only tests/tools callers %d, unconnected `_on_*` %d (functions in dead files skipped: %d)" %
             (len(fs["zero_callers"]), len(fs["dead_chain"]), len(fs["ambiguous_only"]),
              len(fs["test_tool_only"]), len(fs["weak_on"]), fs["dead_files"]))
    L.append("- Signals never emitted: %d, never listened to: %d" %
             (len(an["signals"]["never_emitted"]), len(an["signals"]["never_listened"])))
    L.append("- Broken references: %d, orphan sidecars: %d, dynamic path sites: %d" %
             (len(an["broken"]), len(an["orphan_sidecars"]), len(graph["dynamic"])))
    L.append("")

    def file_list(title, paths, note=""):
        L.append("## " + title)
        L.append("")
        if note:
            L.append(note)
            L.append("")
        if not paths:
            L.append("_none_")
            L.append("")
            return
        by_kind = {}
        for p in paths:
            by_kind.setdefault(files[p]["kind"], []).append(p)
        for kind in sorted(by_kind):
            L.append("### %s (%d)" % (kind, len(by_kind[kind])))
            L.append("")
            for p in by_kind[kind]:
                L.append("- `%s` (%d B)" % (p, files[p]["size"]))
            L.append("")

    file_list("Files unreachable from any live root", an["files"]["unreachable"],
              "No chain of references from project.godot/export presets/autoloads reaches these, "
              "and tests/tools do not reference them either.")
    file_list("Files reachable only from tests/tools", an["files"]["test-tool-only"],
              "Not used by the shipped game, but a test or tool references them.")
    file_list("Files reachable only through dynamic (string-built) paths", an["files"]["dynamic-only"],
              "Possibly used: a res:// pattern with a format or concatenation matches them. "
              "Verify the runtime id list before deleting.")
    L.append("## Game files with no inbound edge")
    L.append("")
    L.append("Includes entry-point scenes/scripts only a human opens. Subset of the unreachable list "
             "plus files referenced only by other dead files.")
    L.append("")
    for p in an["no_inbound"]:
        L.append("- `%s` [%s]" % (p, files[p]["status"]))
    L.append("")

    def func_list(title, ids, note=""):
        L.append("## " + title)
        L.append("")
        if note:
            L.append(note)
            L.append("")
        if not ids:
            L.append("_none_")
            L.append("")
            return
        cur = None
        for fid in ids:
            f = graph["funcs"][fid]
            if f["file"] != cur:
                cur = f["file"]
                L.append("- `%s`" % cur)
            L.append("  - `%s` (line %d%s)" % (
                (f["cls"] + "." if f["cls"] else "") + f["name"], f["line"],
                ", static" if f["static"] else ""))
        L.append("")

    func_list("Functions with zero callers", fs["zero_callers"],
              "Game code, not an engine callback/rpc/test root, no call edge of any kind.")
    func_list("Functions only reachable from dead callers", fs["dead_chain"],
              "Callers exist but none is reachable from a live root (dead cycles / dead helper chains).")
    func_list("Functions whose only callers are ambiguous name matches", fs["ambiguous_only"],
              "Called as `obj.name()` on an untyped receiver; a same-named function elsewhere may be "
              "the real target. Likely used unless every candidate is dead.")
    func_list("Functions only reachable from tests/tools", fs["test_tool_only"])
    func_list("`_on_*` handlers with no connection found", fs["weak_on"],
              "Weak roots: treated as live. Either connected in the editor UI / by a pattern this "
              "scanner cannot see, or dead.")

    L.append("## Signals")
    L.append("")
    L.append("Never emitted: " + (", ".join("`%s`" % s for s in an["signals"]["never_emitted"]) or "_none_"))
    L.append("")
    L.append("Emitted but never connected/awaited: " +
             (", ".join("`%s`" % s for s in an["signals"]["never_listened"]) or "_none_"))
    L.append("")
    L.append("## Broken references")
    L.append("")
    for b in an["broken"][:300]:
        L.append("- `%s:%s` -> `%s` (%s)" % (b["src"], b["line"], b["ref"], b["why"]))
    if not an["broken"]:
        L.append("_none_")
    L.append("")
    L.append("## Orphan sidecars (.import/.uid without source)")
    L.append("")
    for s in an["orphan_sidecars"]:
        L.append("- `%s` (source `%s` missing)" % (s["path"], s["source"]))
    if not an["orphan_sidecars"]:
        L.append("_none_")
    L.append("")
    L.append("## Dynamic path sites (targets only *possibly* used)")
    L.append("")
    for d in graph["dynamic"]:
        L.append("- `%s:%s` `%s` [%s] -> %d file(s)" % (d["src"], d["line"], d["pattern"],
                                                         d["kind"], d["targets"]))
    if not graph["dynamic"]:
        L.append("_none_")
    L.append("")
    return "\n".join(L)


# --------------------------------------------------------------------------
# Cycles and layer rules
# --------------------------------------------------------------------------

def tarjan_scc(adj):
    """Iterative Tarjan. adj: node -> iterable of nodes. Returns list of SCCs (sorted lists)."""
    nodes = set(adj)
    for vs in list(adj.values()):
        nodes.update(vs)
    index = {}
    low = {}
    on = set()
    stack = []
    out = []
    counter = [0]
    for start in sorted(nodes):
        if start in index:
            continue
        work = [(start, iter(sorted(adj.get(start, ()))))]
        index[start] = low[start] = counter[0]
        counter[0] += 1
        stack.append(start)
        on.add(start)
        while work:
            v, it = work[-1]
            advanced = False
            for w in it:
                if w not in index:
                    index[w] = low[w] = counter[0]
                    counter[0] += 1
                    stack.append(w)
                    on.add(w)
                    work.append((w, iter(sorted(adj.get(w, ())))))
                    advanced = True
                    break
                if w in on:
                    low[v] = min(low[v], index[w])
            if advanced:
                continue
            work.pop()
            if work:
                u = work[-1][0]
                low[u] = min(low[u], low[v])
            if low[v] == index[v]:
                comp = []
                while True:
                    w = stack.pop()
                    on.discard(w)
                    comp.append(w)
                    if w == v:
                        break
                out.append(sorted(comp))
    return out


def cycle_through(adj, members, start):
    """Shortest cycle through `start` inside `members`: [start, ..., start] or None."""
    mem = set(members)
    prev = {}
    queue = [start]
    seen = set([start])
    qi = 0
    while qi < len(queue):
        cur = queue[qi]
        qi += 1
        for nxt in sorted(adj.get(cur, ())):
            if nxt not in mem:
                continue
            if nxt == start:
                path = [cur]
                while path[-1] != start:
                    path.append(prev[path[-1]])
                path.reverse()
                return path + [start]
            if nxt not in seen:
                seen.add(nxt)
                prev[nxt] = cur
                queue.append(nxt)
    return None


NODE_BASES = frozenset(["RefCounted", "Resource", "Object", "", "None"])
SCENE_TREE_RE = re.compile(r"(?<![\w.])(?:get_tree|get_node|get_node_or_null|add_child|get_parent|queue_free)\s*\(")
FORBIDDEN_FOR_CORE = ("game", "ui", "net", "autoload")
FORBIDDEN_FOR_CONFIG = ("game", "ui", "net")


def layer_violations(graph):
    """Edges that break CLAUDE.md layering. Returns list of {rule, src, dst, kind, line}."""
    files = graph["files"]
    autoload_files = set(graph["autoloads"].values())
    out = []
    for e in graph["file_edges"]:
        if e["kind"] == "dynamic":
            continue
        s, d = e["src"], e["dst"]
        st, dt = s.split("/", 1)[0], d.split("/", 1)[0]
        if st == "core" and (dt in FORBIDDEN_FOR_CORE or d in autoload_files):
            out.append({"rule": "core must not depend on game/ui/net/autoloads", "src": s, "dst": d,
                        "kind": e["kind"], "line": e["line"]})
        elif st == "config" and dt in FORBIDDEN_FOR_CONFIG and files[s]["kind"] == "script":
            out.append({"rule": "config Resource classes must not depend on game/ui/net", "src": s,
                        "dst": d, "kind": e["kind"], "line": e["line"]})
    return out


def core_scene_tree_violations(files, classes, scripts):
    """core/ scripts that extend scene-tree classes or call scene-tree APIs."""
    out = []
    for p, n in sorted(files.items()):
        if not p.startswith("core/") or n["kind"] != "script":
            continue
        ext = (n.get("extends") or "").split(".")[0]
        if ext and ext not in NODE_BASES and not ext.startswith("res://") and ext not in classes:
            out.append({"rule": "core script extends scene-tree class %s" % ext, "src": p, "dst": ext,
                        "kind": "extends", "line": 1})
        d = scripts.get(p)
        if d:
            for i, line in enumerate(d["lines"], 1):
                if SCENE_TREE_RE.search(line):
                    out.append({"rule": "core script calls scene-tree API", "src": p,
                                "dst": line.strip()[:60], "kind": "api", "line": i})
    return out


def analyze_cycles(graph, liveness):
    files = graph["files"]
    funcs = graph["funcs"]
    fadj = {}
    padj = {}
    for e in graph["file_edges"]:
        if e["kind"] == "dynamic" or e["src"] not in files or e["dst"] not in files:
            continue
        fadj.setdefault(e["src"], set()).add(e["dst"])
        if e["kind"] == "preload" and files[e["dst"]]["kind"] in ("script", "scene"):
            padj.setdefault(e["src"], set()).add(e["dst"])
    cadj = {}
    for e in graph["call_edges"]:
        if e["amb"] or e["kind"] == "override" or e["src"] not in funcs or e["dst"] not in funcs:
            continue
        cadj.setdefault(e["src"], set()).add(e["dst"])
    autoload_files = set(graph["autoloads"].values())
    autoload_by_file = dict((v, k) for k, v in graph["autoloads"].items())

    def file_class(members):
        sts = set(files[m]["status"] for m in members)
        if sts & set(["root", "live", "dynamic-only"]):
            return "live"
        if sts <= set(["test-tool-only", "test-tool-root"]):
            return "test-tool-only"
        return "dead-island"

    def func_class(members):
        sts = set(liveness.get(m, "dead") for m in members)
        if "live" in sts:
            return "live"
        if sts <= set(["dead"]):
            return "dead-island"
        if "ambiguous-only" in sts:
            return "ambiguous-only"
        return "test-tool-only"

    def build(adj, classify, is_file):
        res = []
        for comp in tarjan_scc(adj):
            if len(comp) < 2:
                continue
            entry = {"size": len(comp), "members": comp, "class": classify(comp),
                     "example": cycle_through(adj, comp, comp[0]), "autoloads": [],
                     "autoload_cycles": {}}
            if is_file:
                for m in comp:
                    if m in autoload_files:
                        entry["autoloads"].append(autoload_by_file[m])
                        entry["autoload_cycles"][autoload_by_file[m]] = cycle_through(adj, comp, m)
            res.append(entry)
        res.sort(key=lambda c: (-c["size"], c["members"][0]))
        return res

    file_sccs = build(fadj, file_class, True)
    preload_sccs = build(padj, file_class, True)
    func_sccs = build(cadj, func_class, False)
    viol = layer_violations(graph) + list(graph.get("core_scene_tree", []))
    for n in files.values():
        n["flags"] = []
    for f in funcs.values():
        f["flags"] = []
    for c in file_sccs:
        for m in c["members"]:
            files[m]["flags"].append("cycle")
    for c in preload_sccs:
        for m in c["members"]:
            files[m]["flags"].append("preload-cycle")
    for c in func_sccs:
        for m in c["members"]:
            funcs[m]["flags"].append("cycle")
    for v in viol:
        if v["src"] in files and "layer" not in files[v["src"]]["flags"]:
            files[v["src"]]["flags"].append("layer")
    for n in files.values():
        if n["status"] == "unreachable":
            n["flags"].append("dead")
    for fid, st in liveness.items():
        if st == "dead":
            funcs[fid]["flags"].append("dead")
    return {"file_sccs": file_sccs, "preload_sccs": preload_sccs, "func_sccs": func_sccs,
            "layer_violations": viol}


def render_cycles_md(graph, cy):
    L = ["# Circular dependencies and layer violations", "",
         "Generated by tools/dep_graph.py from `%s`." % graph["meta"]["root"], "",
         "SCC = strongly connected component (every member reaches every other). Class: "
         "`live` (a member is reachable from a live root), `dead-island` (the whole cluster "
         "is unreachable: delete candidate), `test-tool-only`, `ambiguous-only` (functions kept alive "
         "only by name-ambiguous calls). The file graph uses every static edge kind except dynamic "
         "paths; the function graph uses non-ambiguous call edges (override edges excluded). "
         "class_name/type-hint edges create many benign cycles in GDScript; preload cycles and "
         "autoload cycles are the hazardous ones.", ""]
    L.append("## Summary")
    L.append("")
    for key, title in (("file_sccs", "File cycles"),
                       ("preload_sccs", "Preload cycles (preload()/const loads only)"),
                       ("func_sccs", "Function call cycles")):
        sccs = cy[key]
        by = {}
        for c in sccs:
            by[c["class"]] = by.get(c["class"], 0) + 1
        L.append("- %s: %d SCCs (%s); largest %d" % (
            title, len(sccs), ", ".join("%s=%d" % kv for kv in sorted(by.items())) or "none",
            sccs[0]["size"] if sccs else 0))
    L.append("- Layer violations: %d" % len(cy["layer_violations"]))
    L.append("")

    def scc_block(title, sccs, limit_members=60):
        L.append("## " + title)
        L.append("")
        if not sccs:
            L.append("_none_")
            L.append("")
            return
        for i, c in enumerate(sccs, 1):
            extra = (" autoloads: " + ", ".join(c["autoloads"])) if c["autoloads"] else ""
            L.append("### #%d size %d [%s]%s" % (i, c["size"], c["class"], extra))
            L.append("")
            mem = c["members"]
            shown = mem[:limit_members]
            more = (" ... (+%d more, see graph.json cycles)" % (len(mem) - len(shown))
                    if len(mem) > len(shown) else "")
            L.append("Members: " + ", ".join("`%s`" % m for m in shown) + more)
            if c["example"]:
                L.append("")
                L.append("Example cycle: " + " -> ".join("`%s`" % m for m in c["example"]))
            for a, path in sorted(c["autoload_cycles"].items()):
                if path:
                    L.append("")
                    L.append("Autoload `%s` cycle: %s" % (a, " -> ".join("`%s`" % m for m in path)))
            L.append("")

    scc_block("Preload cycles (hazard: loading can fail or deadlock)", cy["preload_sccs"])
    scc_block("File cycles", cy["file_sccs"])
    scc_block("Function call cycles", cy["func_sccs"], 30)
    L.append("## Layer violations")
    L.append("")
    L.append("Rules (CLAUDE.md): core/ must not depend on the scene tree, game/, ui/, net/ or autoloads; "
             "config/ Resource classes must not depend on game/ or ui/ (net/ also flagged).")
    L.append("")
    if not cy["layer_violations"]:
        L.append("_none_")
    for v in cy["layer_violations"]:
        L.append("- `%s:%s` -> `%s` [%s]: %s" % (v["src"], v["line"], v["dst"], v["kind"], v["rule"]))
    L.append("")
    return "\n".join(L)


# --------------------------------------------------------------------------
# Queries
# --------------------------------------------------------------------------

def find_funcs(graph, symbol):
    funcs = graph["funcs"]
    if symbol in funcs:
        return [symbol]
    res = []
    if ":" in symbol:
        path, name = symbol.split(":", 1)
        for fid, f in funcs.items():
            if f["file"] == path and f["name"] == name:
                res.append(fid)
        return res
    if "." in symbol and not symbol.endswith((".gd",)):
        cls, name = symbol.rsplit(".", 1)
        path = graph["classes"].get(cls) or graph["autoloads"].get(cls)
        for fid, f in funcs.items():
            if f["name"] == name and ((path and f["file"] == path) or f["cls"].split(".")[-1:] == [cls]):
                res.append(fid)
        return res
    for fid, f in funcs.items():
        if f["name"] == symbol:
            res.append(fid)
    return res


def callers_of(graph, symbol):
    """Return list of (target func id, [edge dicts])."""
    out = []
    for fid in find_funcs(graph, symbol):
        es = [e for e in graph["call_edges"] if e["dst"] == fid]
        out.append((fid, es))
    return out


def refs_of(graph, path):
    inb = [e for e in graph["file_edges"] if e["dst"] == path]
    outb = [e for e in graph["file_edges"] if e["src"] == path]
    return inb, outb


def format_callers(graph, symbol):
    res = callers_of(graph, symbol)
    if not res:
        return "no function matches %r" % symbol
    lines = []
    for fid, es in res:
        f = graph["funcs"][fid]
        lines.append("%s (line %d)  callers: %d" % (fid, f["line"], len(es)))
        for e in sorted(es, key=lambda x: (x["src"], x["line"])):
            lines.append("  <- %s:%s [%s%s]" % (e["src"], e["line"], e["kind"],
                                                  ", ambiguous" if e["amb"] else ""))
        callees = [e for e in graph["call_edges"] if e["src"] == fid]
        for e in sorted(callees, key=lambda x: (x["dst"], x["line"])):
            lines.append("  -> %s:%s [%s]" % (e["dst"], e["line"], e["kind"]))
    return "\n".join(lines)


def format_refs(graph, path):
    if path not in graph["files"]:
        return "no file %r in graph" % path
    inb, outb = refs_of(graph, path)
    n = graph["files"][path]
    lines = ["%s [%s, %s]" % (path, n["kind"], n["status"]), "inbound (%d):" % len(inb)]
    for e in sorted(inb, key=lambda x: (x["src"], x["kind"])):
        lines.append("  <- %s:%s [%s]" % (e["src"], e["line"], e["kind"]))
    lines.append("outbound (%d):" % len(outb))
    for e in sorted(outb, key=lambda x: (x["dst"], x["kind"])):
        lines.append("  -> %s [%s]" % (e["dst"], e["kind"]))
    return "\n".join(lines)


# --------------------------------------------------------------------------
# HTML mind map (self-contained)
# --------------------------------------------------------------------------

HTML_TEMPLATE = r"""<!doctype html>
<html><head><meta charset="utf-8"><title>Stackfall dependency mind map</title>
<style>
body{font:13px/1.35 Segoe UI,Arial,sans-serif;margin:0;display:flex;height:100vh;background:#1e1e24;color:#ddd}
#left{width:46%;overflow:auto;padding:8px;border-right:1px solid #444}
#right{flex:1;overflow:auto;padding:8px 14px}
input{width:70%;padding:5px;background:#2a2a33;color:#eee;border:1px solid #555}
details{margin-left:14px}summary{cursor:pointer;padding:1px 0}
.f{cursor:pointer;color:#9cd}.fn{cursor:pointer;color:#dc9;margin-left:28px;display:block}
.dead{color:#f77}.live{color:#9d9}.dyn{color:#fc6}.tt{color:#aaf}.root{color:#fff}
.cyc{border-bottom:2px solid #f90}.tag{font-size:11px;opacity:.75;margin-left:6px}
h3{margin:8px 0 4px}a{color:#8cf;cursor:pointer;text-decoration:underline}
li{margin:1px 0}.meta{color:#999}
</style></head><body>
<div id="left"><input id="q" placeholder="search files / functions..." autofocus>
<select id="flt"><option value="">filter: none</option><option value="dead">dead (unreachable)</option>
<option value="cycle">in a cycle</option><option value="preload-cycle">preload cycle</option>
<option value="layer">layer violation</option></select>
<button onclick="showSccs()">list cycles</button>
<div id="res"></div><div id="tree"></div></div>
<div id="right"><div id="info"><h3>Stackfall dependency mind map</h3>
<p class="meta" id="stats"></p>
<p>Expand folders on the left; click a file or function for callers/callees and file references.
Status colours: <span class="live">live</span>, <span class="dyn">dynamic-only</span>,
<span class="tt">test/tool-only</span>, <span class="dead">unreachable</span>, <span class="root">root</span>.</p></div></div>
<script id="data" type="application/json">__DATA__</script>
<script>
var D=JSON.parse(document.getElementById('data').textContent);
var FK=D.kinds, files=D.files, funcs=D.funcs;
var fIn=[],fOut=[],cIn=[],cOut=[],fcOutFile=[];
for(var i=0;i<files.length;i++){fIn.push([]);fOut.push([]);fcOutFile.push([]);}
for(var i=0;i<funcs.length;i++){cIn.push([]);cOut.push([]);}
D.fe.forEach(function(e){fOut[e[0]].push(e);fIn[e[1]].push(e);});
D.ce.forEach(function(e){ // [srcType,srcIdx,dst,kind,line,amb]
  cIn[e[2]].push(e); if(e[0]==0)cOut[e[1]].push(e); else fcOutFile[e[1]].push(e);});
var fnByFile=[];for(var i=0;i<files.length;i++)fnByFile.push([]);
funcs.forEach(function(f,i){fnByFile[f[0]].push(i);});
var STC={'live':'live','root':'root','dynamic-only':'dyn','test-tool-only':'tt','test-tool-root':'tt','unreachable':'dead'};
function esc(s){return String(s).replace(/[&<>]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;'}[c]});}
function hasFlag(fl,f){return fl&&fl.indexOf(f)>=0;}
function showSccs(){var h='<h3>File cycles ('+D.scc.length+')</h3>';
 D.scc.forEach(function(c,i){h+='<details><summary>#'+(i+1)+' size '+c[1].length+' ['+c[0]+']'+(c[2]?' (preload)':'')+'</summary><ul>';
  c[1].slice(0,200).forEach(function(m){h+='<li>'+fl(m)+'</li>';});h+='</ul></details>';});
 h+='<h3>Function cycles ('+D.fscc.length+')</h3>';
 D.fscc.forEach(function(c,i){h+='<details><summary>#'+(i+1)+' size '+c[1].length+' ['+c[0]+']</summary><ul>';
  c[1].slice(0,200).forEach(function(m){h+='<li>'+fnl(m)+'</li>';});h+='</ul></details>';});
 document.getElementById('info').innerHTML=h;}
function applyFilter(){var f=document.getElementById('flt').value,r=document.getElementById('res');r.innerHTML='';if(!f)return;
 var h='',n=0;for(var i=0;i<files.length&&n<400;i++){if(hasFlag(files[i][5],f)){h+='<div>'+fl(i)+'</div>';n++;}}
 for(var j=0;j<funcs.length&&n<800;j++){if(hasFlag(funcs[j][6],f)){h+='<div>'+fnl(j)+'</div>';n++;}}
 r.innerHTML='<div class="meta">'+n+' shown (cap 800)</div>'+h+'<hr>';}
document.getElementById('flt').addEventListener('change',applyFilter);
function fname(i){return files[i][0];}
function funcLabel(i){var f=funcs[i];return (f[4]?f[4]+'.':'')+f[1];}
function fl(i){return '<a onclick="showFile('+i+')">'+esc(fname(i))+'</a>';}
function fnl(i){return '<a onclick="showFunc('+i+')">'+esc(fname(funcs[i][0])+':'+funcLabel(i))+'</a>';}
function srcLink(e){return e[0]==0?fnl(e[1]):fl(e[1]);}
document.getElementById('stats').textContent=files.length+' files, '+funcs.length+' functions, '+D.fe.length+' file edges, '+D.ce.length+' call edges';
function showFile(i){var f=files[i],h='<h3>'+esc(f[0])+'</h3><p class="meta">'+f[1]+' | '+f[2]+' | status: <span class="'+(STC[f[3]]||'')+'">'+f[3]+'</span> | '+f[4]+' lines</p>';
 h+='<h3>Inbound file references ('+fIn[i].length+')</h3><ul>';
 fIn[i].forEach(function(e){h+='<li>'+fl(e[0])+' <span class="tag">'+FK[e[2]]+(e[3]?':'+e[3]:'')+'</span></li>';});
 h+='</ul><h3>Outbound file references ('+fOut[i].length+')</h3><ul>';
 fOut[i].forEach(function(e){h+='<li>'+fl(e[1])+' <span class="tag">'+FK[e[2]]+'</span></li>';});
 h+='</ul>';
 if(fcOutFile[i].length){h+='<h3>Scene handler connections</h3><ul>';fcOutFile[i].forEach(function(e){h+='<li>'+fnl(e[2])+'</li>';});h+='</ul>';}
 h+='<h3>Functions ('+fnByFile[i].length+')</h3><ul>';
 fnByFile[i].forEach(function(j){h+='<li>'+fnl(j)+' <span class="tag">'+cIn[j].length+' callers</span></li>';});
 document.getElementById('info').innerHTML=h+'</ul>';}
function showFunc(j){var f=funcs[j],h='<h3>'+esc(funcLabel(j))+'</h3><p class="meta">'+fl(f[0])+' line '+f[2]+(f[3]?' | static':'')+(f[5]?' | root: '+f[5]:'')+'</p>';
 h+='<h3>Callers ('+cIn[j].length+')</h3><ul>';
 cIn[j].forEach(function(e){h+='<li>'+srcLink(e)+' <span class="tag">'+D.ckinds[e[3]]+(e[5]?' (ambiguous)':'')+' line '+e[4]+'</span></li>';});
 h+='</ul><h3>Callees ('+cOut[j].length+')</h3><ul>';
 cOut[j].forEach(function(e){h+='<li>'+fnl(e[2])+' <span class="tag">'+D.ckinds[e[3]]+(e[5]?' (ambiguous)':'')+' line '+e[4]+'</span></li>';});
 document.getElementById('info').innerHTML=h+'</ul>';}
// tree
var root={ch:{},files:[]};
files.forEach(function(f,i){var parts=f[0].split('/'),n=root;for(var k=0;k<parts.length-1;k++){n=n.ch[parts[k]]=n.ch[parts[k]]||{ch:{},files:[]};}n.files.push(i);});
function renderNode(n,name,parent){
 var d=document.createElement('details');var s=document.createElement('summary');
 var cnt=0;(function c(x){cnt+=x.files.length;Object.keys(x.ch).forEach(function(k){c(x.ch[k]);});})(n);
 s.textContent=name+'/ ('+cnt+')';d.appendChild(s);parent.appendChild(d);
 var done=false;d.addEventListener('toggle',function(){if(done||!d.open)return;done=true;
  Object.keys(n.ch).sort().forEach(function(k){renderNode(n.ch[k],k,d);});
  n.files.forEach(function(i){renderFile(i,d);});});}
function renderFile(i,parent){var d=document.createElement('details');var s=document.createElement('summary');
 var f=files[i];s.innerHTML='<span class="f '+(STC[f[3]]||'')+(hasFlag(f[5],'cycle')?' cyc':'')+'" onclick="showFile('+i+')">'+esc(f[0].split('/').pop())+'</span><span class="tag">'+f[1]+(fnByFile[i].length?' '+fnByFile[i].length+' fn':'')+'</span>';
 d.appendChild(s);parent.appendChild(d);var done=false;
 d.addEventListener('toggle',function(){if(done||!d.open)return;done=true;
  fnByFile[i].forEach(function(j){var a=document.createElement('span');a.className='fn';
   a.className+=hasFlag(funcs[j][6],'cycle')?' cyc':'';a.innerHTML=esc(funcLabel(j))+'<span class="tag">'+cIn[j].length+' callers / '+cOut[j].length+' callees</span>';
   a.onclick=function(){showFunc(j);};d.appendChild(a);});
  fOut[i].slice(0,0);});}
var tree=document.getElementById('tree');
Object.keys(root.ch).sort().forEach(function(k){renderNode(root.ch[k],k,tree);});
root.files.forEach(function(i){renderFile(i,tree);});
document.getElementById('q').addEventListener('input',function(){
 var q=this.value.toLowerCase(),r=document.getElementById('res');r.innerHTML='';if(!q)return;
 var n=0,h='';
 for(var i=0;i<files.length&&n<60;i++){if(files[i][0].toLowerCase().indexOf(q)>=0){h+='<div>'+fl(i)+'</div>';n++;}}
 for(var j=0;j<funcs.length&&n<120;j++){if(funcs[j][1].toLowerCase().indexOf(q)>=0){h+='<div>'+fnl(j)+'</div>';n++;}}
 r.innerHTML=h+'<hr>';});
</script></body></html>
"""


def render_html(graph):
    paths = sorted(graph["files"])
    pidx = dict((p, i) for i, p in enumerate(paths))
    fkinds = []
    ckinds = []

    def code(lst, v):
        if v not in lst:
            lst.append(v)
        return lst.index(v)
    files = [[p, graph["files"][p]["kind"], graph["files"][p]["cat"], graph["files"][p]["status"],
              graph["files"][p]["loc"], graph["files"][p].get("flags", [])] for p in paths]
    fids = sorted(graph["funcs"], key=lambda k: (pidx.get(graph["funcs"][k]["file"], 0),
                                                 graph["funcs"][k]["line"]))
    fidx = dict((f, i) for i, f in enumerate(fids))
    funcs = []
    for fid in fids:
        f = graph["funcs"][fid]
        funcs.append([pidx[f["file"]], f["name"], f["line"], 1 if f["static"] else 0, f["cls"],
                      f["root"] or "", f.get("flags", [])])
    fe = [[pidx[e["src"]], pidx[e["dst"]], code(fkinds, e["kind"]), e["line"]]
          for e in graph["file_edges"] if e["src"] in pidx and e["dst"] in pidx]
    ce = []
    for e in graph["call_edges"]:
        if e["dst"] not in fidx:
            continue
        if e["src"] in fidx:
            ce.append([0, fidx[e["src"]], fidx[e["dst"]], code(ckinds, e["kind"]), e["line"],
                       1 if e["amb"] else 0])
        elif e["src"] in pidx:
            ce.append([1, pidx[e["src"]], fidx[e["dst"]], code(ckinds, e["kind"]), e["line"],
                       1 if e["amb"] else 0])
    cyc = graph.get("cycles", {})
    scc = []
    for c in cyc.get("file_sccs", []):
        scc.append([c["class"], [pidx[m] for m in c["members"]], 0])
    for c in cyc.get("preload_sccs", []):
        scc.append([c["class"], [pidx[m] for m in c["members"]], 1])
    fscc = [[c["class"], [fidx[m] for m in c["members"] if m in fidx]] for c in cyc.get("func_sccs", [])]
    data = json.dumps({"files": files, "funcs": funcs, "fe": fe, "ce": ce, "kinds": fkinds,
                       "ckinds": ckinds, "scc": scc, "fscc": fscc}, separators=(",", ":"))
    data = data.replace("</", "<\\/")
    return HTML_TEMPLATE.replace("__DATA__", data)


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def write_outputs(graph, out_dir):
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir)
    an = analyze(graph)
    cy = analyze_cycles(graph, func_liveness(graph))
    graph["cycles"] = cy
    with io.open(os.path.join(out_dir, "cycles.md"), "w", encoding="utf-8") as fh:
        fh.write(render_cycles_md(graph, cy))
    with open(os.path.join(out_dir, "graph.json"), "w", encoding="utf-8") as fh:
        json.dump(graph, fh, separators=(",", ":"))
    with open(os.path.join(out_dir, "mindmap.html"), "w", encoding="utf-8") as fh:
        fh.write(render_html(graph))
    with open(os.path.join(out_dir, "unused.md"), "w", encoding="utf-8") as fh:
        fh.write(render_unused_md(graph, an))
    an["cycles"] = cy
    return an


def main(argv=None):
    ap = argparse.ArgumentParser(description="Godot project dependency graph (Bontago-fca.52)")
    ap.add_argument("--root", default=DEFAULT_ROOT)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--callers", help="query: callers/callees of SYMBOL (File.gd:func, Class.func or func)")
    ap.add_argument("--refs", help="query: inbound/outbound references of a file path (relative)")
    args = ap.parse_args(argv)
    t0 = time.time()
    graph = build_graph(args.root)
    if args.callers:
        print(format_callers(graph, args.callers))
        return 0
    if args.refs:
        print(format_refs(graph, args.refs.replace("res://", "")))
        return 0
    an = write_outputs(graph, args.out)
    fs = an["funcs"]
    print("files=%d funcs=%d file_edges=%d call_edges=%d time=%.1fs" % (
        graph["meta"]["files"], graph["meta"]["funcs"], graph["meta"]["file_edges"],
        graph["meta"]["call_edges"], time.time() - t0))
    print("unused: files unreachable=%d dynamic-only=%d test/tool-only=%d no-inbound=%d" % (
        len(an["files"]["unreachable"]), len(an["files"]["dynamic-only"]),
        len(an["files"]["test-tool-only"]), len(an["no_inbound"])))
    print("funcs: zero=%d dead-chain=%d ambiguous-only=%d test/tool-only=%d weak_on=%d" % (
        len(fs["zero_callers"]), len(fs["dead_chain"]), len(fs["ambiguous_only"]),
        len(fs["test_tool_only"]), len(fs["weak_on"])))
    cy = an["cycles"]
    print("cycles: file_sccs=%d (dead-island=%d) preload_sccs=%d func_sccs=%d (dead-island=%d) layer_violations=%d" % (
        len(cy["file_sccs"]), len([c for c in cy["file_sccs"] if c["class"] == "dead-island"]),
        len(cy["preload_sccs"]), len(cy["func_sccs"]),
        len([c for c in cy["func_sccs"] if c["class"] == "dead-island"]), len(cy["layer_violations"])))
    print("outputs: %s" % args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
