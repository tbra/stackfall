"""Run every gate lint and print one summary line.

Usage: python tools/lint_all.py [--path <checkout>] [-v]

Runs lint_magic_numbers, lint_single_source, lint_ui_components, lint_layers, lint_dead,
lint_shader_uniforms, lint_flag_dead, lint_instructions, lint_public and lint_shortcuts against the checkout (each with --path), prints each lint's last line, then `LINT ALL GREEN|RED: ...`.
Exit 0 only when every lint exits 0 and prints no RED. Name this command in briefs and handbacks
instead of "lints GREEN".
The whole run holds one machine-wide lint slot (godot_slots mechanics, own state dir; never a Godot slot): env
STACKFALL_LINT_SLOTS (cap, default 2), STACKFALL_LINT_SLOTS_DIR, wait limit STACKFALL_GODOT_SLOTS_WAIT; a timeout is RED.
"""
import argparse
import os
import subprocess
import sys
import tempfile
import time

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import godot_slots  # noqa: E402

DEFAULT_LINT_SLOTS = 2
LINT_TIMEOUT_S = 300
LINTS = ("lint_magic_numbers", "lint_single_source", "lint_ui_components", "lint_layers", "lint_dead",
         "lint_shader_uniforms", "lint_flag_dead", "lint_instructions", "lint_public", "lint_shortcuts")


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


def lint_slots_dir():
    d = os.environ.get("STACKFALL_LINT_SLOTS_DIR")
    if not d:
        shared = os.path.join(os.path.dirname(godot_slots.SHARED_DIR), "lint_slots")
        d = shared if os.path.isdir(os.path.dirname(shared)) else os.path.join(tempfile.gettempdir(), "stackfall_lint_slots")
    os.makedirs(d, exist_ok=True)
    return d


def lint_cap():
    try:
        return max(1, int(os.environ.get("STACKFALL_LINT_SLOTS", DEFAULT_LINT_SLOTS)))
    except ValueError:
        return DEFAULT_LINT_SLOTS


def acquire_lint_slot(wait_s=None, pid=None):
    """Index of a free lint slot, waiting up to wait_s; raises TimeoutError. No Godot gate, load or process checks."""
    d, n, pid = lint_slots_dir(), lint_cap(), pid or os.getpid()
    wait_s = godot_slots.max_wait() if wait_s is None else wait_s
    deadline = time.time() + wait_s
    announced = False
    while True:
        for i in range(n):
            if godot_slots._try_take(d, i, pid, "lint_all"):
                return i
        if not announced:
            busy = sum(1 for i in range(n) if (info := godot_slots._read(godot_slots._path(d, i))) is not None
                       and godot_slots.pid_alive(int(info.get("pid", 0))))
            print("waiting for lint slot (%d/%d busy)" % (busy, n), flush=True)
            announced = True
        if time.time() >= deadline:
            raise TimeoutError("no lint slot free after %.0fs (cap %d)" % (wait_s, n))
        time.sleep(godot_slots.POLL_S)


def release_lint_slot(index):
    godot_slots._drop_slot(lint_slots_dir(), index)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=None, help="checkout (default: the checkout holding this script)")
    ap.add_argument("-v", "--verbose", action="store_true", help="print full output of RED lints")
    args = ap.parse_args(argv)
    repo = os.path.abspath(args.path or os.path.dirname(TOOLS)).replace("\\", "/")
    try:
        slot = acquire_lint_slot()
    except TimeoutError as e:
        print("LINT ALL RED: lint slot timeout: %s" % e)
        return 1
    try:
        return run_all(repo, args.verbose)
    finally:
        release_lint_slot(slot)


def run_all(repo, verbose):
    red = []
    for name in LINTS:
        ok, last, out = run_lint(name, repo)
        print("%s: %s" % (name, last))
        if not ok:
            red.append(name)
            if verbose:
                print(out)
    if red:
        print("LINT ALL RED: %s" % ", ".join(red))
        return 1
    print("LINT ALL GREEN: %d lints" % len(LINTS))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
