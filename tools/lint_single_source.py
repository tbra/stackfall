"""Single-source ratchet (Bontago-1pi.86.1).

Cross-cutting player-facing concepts (names, slot colours, input glyphs,
mode/map/sky/weather labels, gift names and icons) each have ONE owner; see
docs/SINGLE_SOURCE_PLAN.md section 1. This lint finds the bypasses: code that
re-implements the concept outside its owner. It counts matching lines per
(rule, file) and compares with tools/single_source_baseline.json
({rule: {file: count}}). A file may never exceed its baseline for a rule and a
file absent from a rule's baseline must have zero. When a migration lands, its
baseline entries are deleted so any reappearance fails.

  python tools/lint_single_source.py [--path <checkout>]   # check; exit 1 on growth
  python tools/lint_single_source.py --list [--rule ID]    # every violation with line numbers
  python tools/lint_single_source.py --update              # lower baselines only
  python tools/lint_single_source.py --update --allow-new <RULE:path | path>

Prints SINGLE-SOURCE LINT GREEN|RED as its last line.
"""

import argparse
import json
import os
import sys
from collections import namedtuple
import re

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lint_magic_numbers import strip_line  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE_NAME = "single_source_baseline.json"
# Same skip set as the magic-number lint, but config/ IS scanned: several
# owners (MatchConfig, InputGlyphTable, MapDef) live there and are allow-listed
# per rule. Ui-only rules never match config/ because their scope is ui/.
SKIP_DIRS = {".godot", "addons", ".git", "build", "feedback", ".claude", "tests", "tools", "source_art"}
GD = (".gd",)

# id: rule id from the plan. pattern: line regex. scope: path prefixes the rule
# applies to (None = everywhere not skipped). allowed: owner files the rule
# ignores (an entry ending in "/" is a directory prefix). keep_strings: the
# regex needs string bodies (name formats, asset paths, prompt text); otherwise
# strings and comments are blanked with strip_line so only code matches.
# exts: file types scanned (.tscn only for GLYPH_ASSET).
Rule = namedtuple("Rule", "id pattern scope allowed keep_strings exts message multiline",
                  defaults=(False,))

# Line-level allowances: {rule_id: [(file, source snippet, reason)]}. A hit is waived only
# when its statement contains the snippet. Whole-file allowances are not used for STATE_SET.
LINE_ALLOW = {
    "NET_PREDICATE": [
        ("autoload/Match.gd", "func _is_host", "the injectable net-provider seam over Net.is_host(); ~70 controller/test call sites"),
        ("autoload/match/BreezeEffect.gd", "func _is_host", "test override seam, then Match._is_host(); no own predicate"),
        ("autoload/match/StormEffect.gd", "func _is_host", "test override seam, then Match._is_host(); no own predicate"),
        ("autoload/match/MatchWeather.gd", "func _is_host", "test override seam, then Match._is_host(); no own predicate"),
        ("game/HoleDissolver.gd", "func _is_host", "reads BlockRegistry's cached host-authority flag, not the session"),
    ],
}

ALL_CODE = ("ui/", "game/", "autoload/", "net/", "core/", "vfx/")

RULES = [
    Rule("NAME_FMT",
         r"\b(?:Player|Bot|Team|Spectator)\s*(?:%[ds]|\{)|[\"'](?:Player|Bot|Team) [\"']\s*\+",
         None, ("core/rules/PlayerNames.gd",), True, GD,
         "format player/bot/team names through PlayerNames"),
    Rule("NAME_RAW",
         r"\bslot\w*\.display_name\s+if\b.*\belse\b",
         None, ("core/rules/PlayerNames.gd",), False, GD,
         "no inline display_name fallback; use PlayerNames.label_for_slot"),
    Rule("COLOR_LOOKUP",
         r"\b(?:default_player_colors|player_colors)\s*(?:\[|\.size|\()",
         None, ("config/MatchConfig.gd", "core/rules/SlotColors.gd", "core/rules/LobbySeats.gd",
                "autoload/Match.gd", "game/Field.gd", "ui/Minimap.gd"), False, GD,
         "resolve slot colours through SlotColors / Match.slot_color"),
    Rule("DIAMOND",
         # A diamond identifier (SlotDiamond, the owner's class, is exempt) on a line that
         # builds or draws geometry. Plain `SlotDiamond.create(...)` consumers stay legal.
         r"(?i)^(?=.*(?<!slot)diamond)(?=.*(?:PackedVector2Array|draw_\w+|Polygon2D|polygon|polyline))",
         ("ui/",), ("ui/SlotDiamond.gd",), False, GD,
         "draw the colour diamond through ui/SlotDiamond.gd (SlotDiamond.create / .points)"),
    Rule("GLYPH_EVENTS",
         r"InputMap\.action_get_events|\.as_text\(\)",
         ("ui/", "game/", "vfx/"), ("ui/InputGlyph.gd", "ui/InputPrompt.gd", "autoload/Settings.gd"), False, GD,
         "derive action glyphs through InputGlyph, not InputMap/as_text"),
    Rule("GLYPH_ASSET",
         r"assets/ui/input_glyphs|input_glyph_table",
         None, ("ui/InputGlyph.gd", "config/InputGlyphTable.gd"), True, GD + (".tscn",),
         "glyph textures belong to InputGlyph / InputGlyphTable"),
    Rule("GLYPH_TEXT",
         r"\"[^\"]*\b(?:Press|Hold|Tap|Click)\s+(?:Enter|Space|Esc|[A-Z])\b[^\"]*\"",
         ("ui/", "game/"), ("ui/InputGlyph.gd",), True, GD,
         "no hard-coded key names in prompts; use an InputGlyph"),
    Rule("ENUM_LABEL",
         # Enum receivers start upper-case (MapDef.MapSize.keys()[i]); dictionary variables do not.
         r"\b[A-Z]\w*\.keys\(\)\s*\[",
         ("ui/", "autoload/"), ("core/rules/DisplayNames.gd", "config/MapDef.gd"), False, GD,
         "label enums through DisplayNames, not enum.keys()[i]"),
    Rule("CAPITALIZE_ID",
         r"\.capitalize\(\)",
         ("ui/", "game/", "autoload/"), ("core/rules/DisplayNames.gd", "game/Skybox.gd"), False, GD,
         "label ids through DisplayNames, not capitalize()"),
    Rule("RESULTS_KEY",
         # Results-payload keys that no other payload uses: any ui/ literal-key read is a bypass of
         # core/rules/ResultsPayload.gd (use its KEY_* constants / typed accessors).
         r"(?:\.get\(|\[)\s*\"(?:winner_id|winner_kind|winner_name|match_duration|rows|blocks_placed|blocks_lost|"
         r"gifts_claimed|specials_used|territory_share|eliminated_at|peak_territory|winners)\"",
         ("ui/",), ("core/rules/ResultsPayload.gd",), True, GD,
         "read results-payload keys through ResultsPayload (KEY_* / accessors)"),
    Rule("RESULTS_KEY_SHARED",
         # Keys other payloads also use (lobby seats, mode state), so only the results readers are scanned.
         r"(?:\.get\(|\[)\s*\"(?:slot_id|team_id|name|is_bot|wins|height|mode|mode_id|scores|live|is_winner)\"",
         ("ui/ResultsScreen.gd", "ui/ScoreTable.gd", "ui/ScoreboardOverlay.gd"), ("core/rules/ResultsPayload.gd",), True, GD,
         "read results-payload keys through ResultsPayload (KEY_* / accessors)"),
    Rule("GIFT_ICON",
         r"res://assets/gifts/",
         None, ("config/", "game/GiftCrate.gd", "game/BlockFactory.gd"), True, GD,
         "gift art paths belong to GiftIconTable / GiftModelTable"),
    Rule("STATE_SET",
         # Two or more Match.State members in one statement joined by or/and/a match-arm comma:
         # an ad-hoc "live"/"replicating"/"resetting" set. Multi-line (parenthesised or
         # or/and-continued) statements are joined first. Single-state checks stay legal.
         r"\bState\.(?:LOBBY|LOADING|COUNTDOWN|PLAYING|SUDDEN_DEATH|END)\b.*"
         r"(?:\bor\b|\band\b|,).*\bState\.(?:LOBBY|LOADING|COUNTDOWN|PLAYING|SUDDEN_DEATH|END)\b",
         None, ("autoload/Match.gd",), False, GD,
         "use Match.is_live / is_replicating / is_resetting, not a hand-written state set",
         True),
    Rule("NET_PREDICATE",
         # Bontago-fca.36.5: Net.is_host() / NetFanout.can_send() own "am I the host" and "is
         # there a live peer to send to". A new `func _is_host` / `func _can_send` (or an
         # OfflineMultiplayerPeer test) outside the owners is a copy; call the owners instead.
         r"\bfunc\s+_?(?:is_host|can_send)\s*\(|\bOfflineMultiplayerPeer\b",
         None, ("autoload/Net.gd", "net/NetFanout.gd"), False, GD,
         "use Net.is_host() / NetFanout.can_send(), not a private copy",
         True),
]
RULE_IDS = [r.id for r in RULES]
_COMPILED = {r.id: re.compile(r.pattern) for r in RULES}


def strip_comment(line):
    """Drop only the trailing comment (strip_line also blanks string bodies)."""
    quote = ""
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = ""
        elif c in "\"'":
            quote = c
        elif c == "#":
            return line[:i]
        i += 1
    return line


def applies(rule, rel):
    """True when `rule` covers file `rel` (extension, scope, allow-list)."""
    if not rel.endswith(rule.exts):
        return False
    if rule.scope is not None and not rel.startswith(rule.scope):
        return False
    for entry in rule.allowed:
        if rel == entry or (entry.endswith("/") and rel.startswith(entry)):
            return False
    return True


_CONT = re.compile(r"(?:\bor|\band|,|\\)$")


def logical_lines(text):
    """[(first_line_number, joined_source)]: statements spanning lines (open brackets, a
    trailing or/and/comma/backslash) are joined so multi-line sets are seen whole."""
    out = []
    buf = ""
    start = 0
    depth = 0
    for n, line in enumerate(text.splitlines(), 1):
        code = strip_line(line)
        if not buf:
            start = n
        buf = (buf + " " + code.strip()) if buf else code
        depth += sum(code.count(c) for c in "([{") - sum(code.count(c) for c in ")]}")
        tail = code.rstrip()
        if depth > 0 or _CONT.search(tail):
            continue
        out.append((start, buf))
        buf = ""
        depth = 0
    if buf:
        out.append((start, buf))
    return out


def line_allowed(rule_id, rel, src):
    return any(rel == f and snip in src for f, snip, _reason in LINE_ALLOW.get(rule_id, ()))


def violations_in(rel, text, rules=None):
    """[(rule_id, line_number, source_line)] for one file's text."""
    active = [r for r in (rules or RULES) if applies(r, rel)]
    out = []
    if not active:
        return out
    is_scene = rel.endswith(".tscn")
    for r in active:
        if r.multiline and not is_scene:
            for n, joined in logical_lines(text):
                if _COMPILED[r.id].search(joined) and not line_allowed(r.id, rel, joined):
                    out.append((r.id, n, joined.strip()))
    active = [r for r in active if not r.multiline]
    for n, line in enumerate(text.splitlines(), 1):
        kept = None
        blanked = None
        for r in active:
            if is_scene:
                s = line  # .tscn has no GDScript comments or strings to strip
            elif r.keep_strings:
                if kept is None:
                    kept = strip_comment(line)
                s = kept
            else:
                if blanked is None:
                    blanked = strip_line(line)
                s = blanked
            if _COMPILED[r.id].search(s):
                out.append((r.id, n, line.strip()))
    return out


def walk(path):
    for d, dirs, files in os.walk(path):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
        for f in sorted(files):
            if f.endswith((".gd", ".tscn")):
                full = os.path.join(d, f)
                yield os.path.relpath(full, path).replace(os.sep, "/"), full


def scan(path, rules=None):
    """{rule_id: {file: [(line_number, source_line), ...]}}."""
    found = {}
    for rel, full in walk(path):
        with open(full, encoding="utf-8", errors="ignore") as fh:
            text = fh.read()
        for rule_id, n, src in violations_in(rel, text, rules):
            found.setdefault(rule_id, {}).setdefault(rel, []).append((n, src))
    return found


def counts_of(found):
    return {rid: {f: len(v) for f, v in sorted(files.items())} for rid, files in sorted(found.items())}


def load_baseline(file):
    """None when the file is missing or unreadable (distinct from an empty baseline)."""
    try:
        with open(file, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def check(counts, baseline):
    """One message per (rule, file) that exceeds its baseline."""
    problems = []
    messages = {r.id: r.message for r in RULES}
    for rid, files in sorted(counts.items()):
        base_files = baseline.get(rid) or {}
        for rel, n in sorted(files.items()):
            base = base_files.get(rel)
            if base is None:
                problems.append("%s %s: %d line(s), new (baseline 0); %s" % (rid, rel, n, messages.get(rid, "")))
            elif n > base:
                problems.append("%s %s: %d line(s) > baseline %d; %s" % (rid, rel, n, base, messages.get(rid, "")))
    return problems


def parse_allow_new(items):
    """['RULE:path' | 'path'] -> set of (rule_id or None, path)."""
    out = set()
    for item in items:
        head, sep, tail = item.partition(":")
        if sep and head in RULE_IDS:
            out.add((head, tail))
        else:
            out.add((None, item))
    return out


def updated(counts, baseline, allow_new):
    """Baseline lowered to current counts; new (rule, file) pairs only when allowed."""
    new = {}
    for rid, files in counts.items():
        base_files = baseline.get(rid) or {}
        for rel, n in files.items():
            if rel in base_files:
                new.setdefault(rid, {})[rel] = min(n, base_files[rel])
            elif (rid, rel) in allow_new or (None, rel) in allow_new:
                new.setdefault(rid, {})[rel] = n
    return {rid: dict(sorted(files.items())) for rid, files in sorted(new.items())}


def total(counts):
    return sum(sum(files.values()) for files in counts.values())


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=ROOT)
    ap.add_argument("--baseline", default="")
    ap.add_argument("--update", action="store_true")
    ap.add_argument("--allow-new", action="append", default=[],
                    help="admit a new (rule, file): RULE:path or path (every rule)")
    ap.add_argument("--allow-baseline", action="store_true",
                    help="legacy ratchet mode (tests only): tolerate non-empty baseline entries")
    ap.add_argument("--list", action="store_true", help="print every violation with line numbers")
    ap.add_argument("--rule", action="append", default=[], help="with --list: only these rule ids")
    args = ap.parse_args(argv)
    path = os.path.abspath(args.path)
    bfile = args.baseline or os.path.join(path, "tools", BASELINE_NAME)
    found = scan(path)
    if args.list:
        wanted = set(args.rule) or set(RULE_IDS)
        shown = 0
        for rid in RULE_IDS:
            if rid not in wanted:
                continue
            for rel, hits in sorted(found.get(rid, {}).items()):
                for n, src in hits:
                    print("%s %s:%d: %s" % (rid, rel, n, src))
                    shown += 1
        print("SINGLE-SOURCE LIST: %d violation(s)" % shown)
        return 0
    counts = counts_of(found)
    baseline = load_baseline(bfile)
    if args.update:
        # No baseline file yet: seed it from the current scan. An existing
        # (even empty) baseline only ever lowers.
        new = counts if baseline is None else updated(counts, baseline, parse_allow_new(args.allow_new))
        with open(bfile, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(new, fh, indent=1, sort_keys=True)
            fh.write("\n")
        print("SINGLE-SOURCE LINT baseline written: %d rules, %d violations" % (len(new), total(new)))
        return 0
    baseline = baseline or {}
    problems = check(counts, baseline)
    if not args.allow_baseline:
        # P7: every rule is at zero; the baseline must stay empty, so a violation can
        # never be parked in it. Fix the site (route it through its owner) instead.
        for rid, files in sorted(baseline.items()):
            for rel, b in sorted(files.items()):
                if b:
                    problems.append("%s %s: baseline entry %d; baselines must stay empty (fix the site)"
                                    % (rid, rel, b))
    for p in problems:
        print("SINGLE-SOURCE LINT FAIL " + p)
    if problems:
        print("SINGLE-SOURCE LINT RED: %d (rule, file) pair(s); route through the owner (docs/SINGLE_SOURCE_PLAN.md)"
              % len(problems))
        return 1
    stale = sum(1 for rid, files in baseline.items() for rel, b in files.items()
                if counts.get(rid, {}).get(rel, 0) < b)
    print("SINGLE-SOURCE LINT GREEN: %d rules, %d violations (baseline %d)%s" % (
        len(RULES), total(counts), total(baseline),
        "; %d baseline entr%s can be lowered (--update)" % (stale, "y" if stale == 1 else "ies") if stale else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
