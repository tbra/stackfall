"""Run every gate lint and print one summary line (Bontago-fca.94).

Usage: python tools/lint_all.py [--path <checkout>] [-v]

Runs lint_magic_numbers, lint_single_source, lint_ui_components and lint_layers against the
checkout (each with --path), prints each lint's last line, then `LINT ALL GREEN|RED: ...`.
Exit 0 only when every lint exits 0 and prints no RED. Name this command in briefs and handbacks
instead of "lints GREEN".
"""
import argparse
import os
import subprocess
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
LINT_TIMEOUT_S = 300
LINTS = ("lint_magic_numbers", "lint_single_source", "lint_ui_components", "lint_layers")


def run_lint(name, repo):
    """(ok, last_line, full_output) for one lint run against `repo`."""
    script = os.path.join(TOOLS, name + ".py")
    try:
        p = subprocess.run([sys.executable, script, "--path", repo], capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=LINT_TIMEOUT_S)
    except (OSError, subprocess.SubprocessError) as e:
        return False, "did not run: %s" % e, ""
    out = (p.stdout or "") + (p.stderr or "")
    lines = [ln for ln in out.splitlines() if ln.strip()]
    last = lines[-1].strip() if lines else "no output"
    ok = p.returncode == 0 and "RED" not in last
    return ok, last, out


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=None, help="checkout (default: the checkout holding this script)")
    ap.add_argument("-v", "--verbose", action="store_true", help="print full output of RED lints")
    args = ap.parse_args(argv)
    repo = os.path.abspath(args.path or os.path.dirname(TOOLS)).replace("\\", "/")
    red = []
    for name in LINTS:
        ok, last, out = run_lint(name, repo)
        print("%s: %s" % (name, last))
        if not ok:
            red.append(name)
            if args.verbose:
                print(out)
    if red:
        print("LINT ALL RED: %s" % ", ".join(red))
        return 1
    print("LINT ALL GREEN: %d lints" % len(LINTS))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
