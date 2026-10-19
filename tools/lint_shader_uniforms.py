"""Shader-uniform liveness guard: uniforms that cost nothing to declare but nothing to keep either.

Usage: python tools/lint_shader_uniforms.py [--path <checkout>] [--report] [--update-baseline]

Scans every .gdshader / .gdshaderinc outside addons/, tests/ and scratch folders. A shader and the files it
`#include`s form one unit: a uniform declared in any of them counts as read when any of them reads it. Two
checks, one finding per line as `path:line: id: message`:

  uniform-unread  a uniform that is declared and never read (its declaration statement is the only use).
  uniform-gated   a uniform whose every read sits in the body of an `if (cond)` that is constantly false (or
                  in the `else` of a constantly true one) once the gate uniforms in `cond` are replaced by
                  their constant value. A gate uniform is constant when the shader default and every
                  `shader_parameter/<name>` in every .tres/.tscn material using that shader are the same
                  0 / 0.0 / false, and no game .gd names it (a `set_shader_parameter("<name>", ...)` string,
                  `shader_parameter/<name>` or `instance_shader_parameters/<name>` text writes it at runtime,
                  so it is not constant). Short-circuit `&&` / `||` is honoured; a condition the evaluator
                  cannot read counts as unknown, never as constant.

tools/shader_uniform_baseline.json holds today's findings per check (`checks`) and reviewed exceptions
(`allow`: [{"id","entry","reason"}], reasons plain text). Only findings outside both fail the run (exit 1);
baseline entries that no longer occur are reported as stale so the baseline only shrinks
(`--update-baseline` rewrites it, keeping `allow` entries that still match). Entries are `path:uniform`.
`--report` prints counts per check and folder.
"""
import argparse
import collections
import json
import os
import re
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
BASELINE_NAME = "shader_uniform_baseline.json"
CHECKS = ("uniform-unread", "uniform-gated")
SKIP_DIRS = (".godot", ".git", "addons", "tests", "scratch", "node_modules", "__pycache__", "worktrees", "source_art")
SHADER_EXTS = (".gdshader", ".gdshaderinc")
SCALAR_TYPES = ("float", "int", "uint", "bool")
UNKNOWN = None

COMMENT_RE = re.compile(r'"[^"\n]*"|/\*.*?\*/|//[^\n]*', re.S)
INCLUDE_RE = re.compile(r'#include\s+"([^"]+)"')
DECL_RE = re.compile(
    r"\b(?:global\s+|instance\s+)?uniform\s+(?:(?:lowp|mediump|highp)\s+)?(\w+)\s+(\w+)\s*(?:\[[^\]]*\])?\s*"
    r"(?::\s*[^=;]*)?(?:=\s*([^;]*))?;")
IF_RE = re.compile(r"\bif\s*\(")
HEADER_ATTR_RE = re.compile(r'(\w+)="([^"]*)"')
SECTION_RE = re.compile(r"^\[(\w+)\s*(.*)\]\s*$")
PARAM_RE = re.compile(r"^shader_parameter/(\w+)\s*=\s*(.*)$")
INSTANCE_PARAM_RE = re.compile(r"instance_shader_parameters/(\w+)")
EXT_ID_RE = re.compile(r'ExtResource\(\s*"([^"]+)"\s*\)')
CMP_RE = re.compile(r"^(.+?)(<=|>=|==|!=|<|>)(.+)$")
NUM_RE = re.compile(r"^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?[fF]?$")


def rd(root, rel):
    try:
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def walk(root, exts):
    """Relative paths (forward slashes) of files with one of `exts`, skipping non-game folders."""
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        rel_dir = os.path.relpath(dirpath, root).replace("\\", "/")
        for n in filenames:
            if n.endswith(exts):
                out.append(n if rel_dir == "." else rel_dir + "/" + n)
    return sorted(out)


def strip_comments(text):
    """Comments blanked (newlines kept) so offsets and line numbers still match the source."""
    return COMMENT_RE.sub(lambda m: m.group(0) if m.group(0)[0] == '"' else re.sub(r"[^\n]", " ", m.group(0)), text)


# ---- shader parsing -------------------------------------------------------

def parse_shader(root, rel):
    """(stripped text, [(type, name, default text or None, line)], [included rel paths])."""
    text = strip_comments(rd(root, rel))
    decls = []
    for m in DECL_RE.finditer(text):
        decls.append((m.group(1), m.group(2), None if m.group(3) is None else m.group(3).strip(),
                      text.count("\n", 0, m.start()) + 1))
    incs = []
    for m in INCLUDE_RE.finditer(text):
        target = m.group(1)
        if target.startswith("res://"):
            incs.append(target[len("res://"):])
        else:
            incs.append(os.path.normpath(os.path.join(os.path.dirname(rel), target)).replace("\\", "/"))
    return text, decls, incs


def units(root, shaders):
    """{root shader: [files in its include closure, root first]}; an include nobody includes is its own root."""
    parsed = {rel: parse_shader(root, rel) for rel in shaders}
    included = set(i for _, _, incs in parsed.values() for i in incs)
    roots = [r for r in shaders if r not in included or r.endswith(".gdshader")]
    out = {}
    for r in roots:
        seen, stack = [], [r]
        while stack:
            f = stack.pop(0)
            if f in seen or f not in parsed:
                continue
            seen.append(f)
            stack.extend(parsed[f][2])
        out[r] = seen
    return parsed, out


# ---- materials and runtime writes ----------------------------------------

def scan_materials(root):
    """{shader rel path: {param: [raw value text, ...]}} from every ShaderMaterial in .tres/.tscn files."""
    out = collections.defaultdict(lambda: collections.defaultdict(list))
    for rel in walk(root, (".tres", ".tscn")):
        shaders = {}
        res_type = rd_header_type(root, rel)
        mats = []  # (shader ref, {param: value}); one per ShaderMaterial section
        cur = None
        for line in rd(root, rel).split("\n"):
            m = SECTION_RE.match(line.strip())
            if m:
                attrs = dict(HEADER_ATTR_RE.findall(m.group(2)))
                kind = m.group(1)
                cur = None
                if kind == "ext_resource" and attrs.get("path", "").endswith(".gdshader"):
                    shaders[attrs.get("id", "")] = attrs["path"][len("res://"):]
                elif (kind == "sub_resource" and attrs.get("type") == "ShaderMaterial") or \
                        (kind == "resource" and res_type == "ShaderMaterial"):
                    cur = {"shader": None, "params": {}}
                    mats.append(cur)
                continue
            if cur is None:
                continue
            if line.startswith("shader = "):
                e = EXT_ID_RE.search(line)
                cur["shader"] = e.group(1) if e else None
                continue
            p = PARAM_RE.match(line)
            if p:
                cur["params"][p.group(1)] = p.group(2).strip()
        for mat in mats:
            sh = shaders.get(mat["shader"] or "")
            if sh:
                for k, v in mat["params"].items():
                    out[sh][k].append(v)
                out[sh]["\0material"].append("")
    return out


def rd_header_type(root, rel):
    first = rd(root, rel).split("\n", 1)[0]
    return dict(HEADER_ATTR_RE.findall(first)).get("type", "")


def runtime_written_names(root):
    """Text of every game .gd (and scene/resource instance-parameter lines), searched by name later."""
    chunks = [rd(root, rel) for rel in walk(root, (".gd",))]
    for rel in walk(root, (".tscn", ".tres")):
        chunks.extend(m.group(0) for m in INSTANCE_PARAM_RE.finditer(rd(root, rel)))
    return "\n".join(chunks)


def written_at_runtime(name, gd_text):
    pat = r"[\"'&]%s[\"']|shader_parameter/%s\b|instance_shader_parameters/%s\b" % ((re.escape(name),) * 3)
    return re.search(pat, gd_text) is not None


def falsy_value(raw):
    """True when `raw` is a scalar default/material value that reads as false or 0, else False."""
    r = (raw or "").strip()
    if r in ("false", "0", "0.0", "0.", ".0"):
        return True
    if NUM_RE.match(r) and float(r.rstrip("fF")) == 0.0:
        return True
    return False


# ---- condition evaluation ---------------------------------------------------

def split_top(s, op):
    """Split `s` on `op` at paren depth 0."""
    parts, depth, cur, i = [], 0, "", 0
    while i < len(s):
        c = s[i]
        if c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        if depth == 0 and s.startswith(op, i):
            parts.append(cur)
            cur, i = "", i + len(op)
            continue
        cur += c
        i += 1
    parts.append(cur)
    return parts


def atom_value(s, consts):
    s = s.strip()
    if s in ("true", "false"):
        return s == "true"
    if NUM_RE.match(s):
        return float(s.rstrip("fF"))
    if s in consts:
        return consts[s]
    return UNKNOWN


def evaluate(cond, consts):
    """True / False / UNKNOWN for a shader condition under `consts` (name -> constant); three-valued."""
    s = cond.strip()
    if not s:
        return UNKNOWN
    parts = split_top(s, "||")
    if len(parts) > 1:
        vals = [evaluate(p, consts) for p in parts]
        if any(v is True for v in vals):
            return True
        return False if all(v is False for v in vals) else UNKNOWN
    parts = split_top(s, "&&")
    if len(parts) > 1:
        vals = [evaluate(p, consts) for p in parts]
        if any(v is False for v in vals):
            return False
        return True if all(v is True for v in vals) else UNKNOWN
    if s.startswith("!") and not s.startswith("!="):
        v = evaluate(s[1:], consts)
        return UNKNOWN if v is UNKNOWN else (not v)
    if s.startswith("(") and match_close(s, 0, "(", ")") == len(s):
        return evaluate(s[1:-1], consts)
    m = CMP_RE.match(s) if depth_zero_cmp(s) else None
    if m:
        a, b = atom_value(m.group(1), consts), atom_value(m.group(3), consts)
        if a is UNKNOWN or b is UNKNOWN:
            return UNKNOWN
        op = m.group(2)
        return {"<": a < b, ">": a > b, "<=": a <= b, ">=": a >= b, "==": a == b, "!=": a != b}[op]
    v = atom_value(s, consts)
    return UNKNOWN if v is UNKNOWN else bool(v)


def depth_zero_cmp(s):
    """True when `s` holds no parenthesis or call, so the comparison regex splits it at the real operator."""
    return not any(c in s for c in "()[]?:")


# ---- if/else region scanner -------------------------------------------------

def match_close(text, i, open_c, close_c):
    """Index just after the bracket that closes the one opened at text[i]."""
    depth = 0
    for j in range(i, len(text)):
        if text[j] == open_c:
            depth += 1
        elif text[j] == close_c:
            depth -= 1
            if depth == 0:
                return j + 1
    return len(text)


def skip_ws(text, i):
    while i < len(text) and text[i].isspace():
        i += 1
    return i


def stmt_end(text, i):
    """Index just after the statement starting at text[i]: a block, an if/else chain, or up to `;`."""
    i = skip_ws(text, i)
    if i >= len(text):
        return len(text)
    if text[i] == "{":
        return match_close(text, i, "{", "}")
    m = IF_RE.match(text, i)
    if m:
        after_cond = match_close(text, m.end() - 1, "(", ")")
        end = stmt_end(text, after_cond)
        j = skip_ws(text, end)
        if text.startswith("else", j) and not text[j + 4:j + 5].isalnum():
            return stmt_end(text, j + 4)
        return end
    k = text.find(";", i)
    return len(text) if k < 0 else k + 1


def dead_regions(text, consts):
    """[(start, end, why)] spans that never run under `consts`."""
    out = []
    for m in IF_RE.finditer(text):
        close = match_close(text, m.end() - 1, "(", ")")
        cond = text[m.end():close - 1]
        verdict = evaluate(cond, consts)
        if verdict is UNKNOWN:
            continue
        body_end = stmt_end(text, close)
        if verdict is False:
            out.append((close, body_end, " ".join(cond.split())))
            continue
        j = skip_ws(text, body_end)
        if text.startswith("else", j) and not text[j + 4:j + 5].isalnum():
            out.append((j + 4, stmt_end(text, j + 4), "else of " + " ".join(cond.split())))
    return out


# ---- driver ----------------------------------------------------------------

def collect(root):
    """All findings: (path, line, id, message, key)."""
    shaders = walk(root, SHADER_EXTS)
    parsed, unit_files = units(root, shaders)
    materials = scan_materials(root)
    gd_text = runtime_written_names(root)
    unread_per_unit = collections.defaultdict(list)  # key -> [True/False per unit containing it]
    gated = {}  # key -> (path, line, name, why) when gated in every unit holding it
    gated_votes = collections.defaultdict(list)
    where = {}
    for shader, files in unit_files.items():
        decls = {}
        for f in files:
            for typ, name, default, line in parsed[f][1]:
                decls.setdefault(name, (typ, default, f, line))
        body = "\n".join(DECL_RE.sub(lambda m: " " * len(m.group(0)), parsed[f][0]) for f in files)
        mats = materials.get(shader, {})
        consts = {}
        for name, (typ, default, f, line) in decls.items():
            if typ not in SCALAR_TYPES or (default is not None and not falsy_value(default)):
                continue
            vals = mats.get(name, [])
            if all(falsy_value(v) for v in vals) and not written_at_runtime(name, gd_text):
                consts[name] = False if typ == "bool" else 0.0
        for name, (typ, default, f, line) in decls.items():
            key = f + ":" + name
            where[key] = (f, line, name)
            reads = [m.start() for m in re.finditer(r"\b%s\b" % re.escape(name), body)]
            unread_per_unit[key].append(not reads)
            if not reads:
                gated_votes[key].append(None)
                continue
            regions = dead_regions(body, {k: v for k, v in consts.items() if k != name})
            whys = []
            for pos in reads:
                hit = next((r for r in regions if r[0] <= pos < r[1]), None)
                if hit is None:
                    whys = None
                    break
                whys.append(hit[2])
            gated_votes[key].append(None if whys is None else sorted(set(whys))[0])
    out = []
    for key, flags in unread_per_unit.items():
        f, line, name = where[key]
        if all(flags):
            out.append((f, line, "uniform-unread", "%s is declared but never read" % name, key))
        elif all(v is not None for v in gated_votes[key]):
            why = gated_votes[key][0]
            out.append((f, line, "uniform-gated", "%s is read only inside a constantly dead branch (%s)" % (name, why), key))
    return sorted(out, key=lambda f: (f[0], f[1], f[2]))


def load_baseline(root):
    try:
        with open(os.path.join(root, "tools", BASELINE_NAME), encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        data = {}
    return {c: list(data.get("checks", {}).get(c, [])) for c in CHECKS}, list(data.get("allow", []))


def classify(findings, baseline, allow):
    """(new findings, baselined count, stale baseline entries (id, entry), stale allow entries)."""
    base = {c: set(v) for c, v in baseline.items()}
    allowed = set((a.get("id"), a.get("entry")) for a in allow)
    new, seen_base, seen_allow = [], set(), set()
    for f in findings:
        cid, key = f[2], f[4]
        if (cid, key) in allowed:
            seen_allow.add((cid, key))
        elif key in base.get(cid, ()):
            seen_base.add((cid, key))
        else:
            new.append(f)
    stale = sorted((c, k) for c, ks in base.items() for k in ks if (c, k) not in seen_base)
    stale_allow = sorted(a for a in allowed if a not in seen_allow)
    return new, len(seen_base), stale, stale_allow


def write_baseline(root, findings, allow):
    grouped = {c: sorted(set(f[4] for f in findings if f[2] == c)) for c in CHECKS}
    now = set((f[2], f[4]) for f in findings)
    keep = {(a["id"], a["entry"]): a for a in allow if (a.get("id"), a.get("entry")) in now}
    for cid, key in keep:
        grouped[cid] = [k for k in grouped[cid] if k != key]
    data = {"checks": grouped, "allow": sorted(keep.values(), key=lambda a: (a["id"], a["entry"]))}
    with open(os.path.join(root, "tools", BASELINE_NAME), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent=1)
        fh.write("\n")


def print_report(findings):
    for cid in CHECKS:
        sub = [f for f in findings if f[2] == cid]
        by = collections.Counter((f[0].split("/")[0] if "/" in f[0] else ".") for f in sub)
        print("%-15s %5d  %s" % (cid, len(sub), ", ".join("%s=%d" % kv for kv in by.most_common())))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=os.path.dirname(TOOLS))
    ap.add_argument("--report", action="store_true", help="print counts per check and folder")
    ap.add_argument("--update-baseline", action="store_true")
    args = ap.parse_args(argv)
    root = os.path.abspath(args.path).replace("\\", "/")
    findings = collect(root)
    baseline, allow = load_baseline(root)
    if args.update_baseline:
        write_baseline(root, findings, allow)
        print("lint_shader_uniforms: baseline rewritten (%d findings)" % len(findings))
        return 0
    if args.report:
        print_report(findings)
    new, n_base, stale, stale_allow = classify(findings, baseline, allow)
    for f in new:
        print("%s:%d: %s: %s" % (f[0], f[1], f[2], f[3]))
    for cid, key in stale:
        print("stale baseline entry (no longer found, run --update-baseline): %s %s" % (cid, key))
    for cid, key in stale_allow:
        print("stale allow entry (no longer found, delete it): %s %s" % (cid, key))
    if new:
        print("LINT SHADER UNIFORMS RED: %d new finding(s) (%d baselined, %d stale)" % (len(new), n_base, len(stale) + len(stale_allow)))
        return 1
    print("LINT SHADER UNIFORMS GREEN: %d baselined, %d stale" % (n_base, len(stale) + len(stale_allow)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
