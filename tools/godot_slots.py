#!/usr/bin/env python3
"""Machine-wide counting semaphore for Godot launches (Bontago-fca.89).

Too many concurrent Godot processes crashed the owner's PC, so every launcher
(full_gate, bot_h2h, run_gut.ps1, ...) takes one slot first. A slot is a lock
file (slot_<n>.json: owner pid, command label, start time) created atomically
(O_EXCL) in a fixed machine-wide directory, never inside a checkout. A slot whose
owner PID is dead is reclaimed. Waiting polls and prints one
'waiting for Godot slot (n/cap busy)' line.

Env: STACKFALL_GODOT_SLOTS (cap, default 3), STACKFALL_GODOT_SLOTS_DIR (state dir,
default M:/Bontago-tools/locks/godot_slots, else %TEMP%/stackfall_godot_slots),
STACKFALL_GODOT_SLOTS_WAIT (max wait seconds, default 3600).

CLI:
  python tools/godot_slots.py status
  python tools/godot_slots.py acquire [--label L] [--pid P] [--max-wait S]   # prints slot index
  python tools/godot_slots.py release <index>
  python tools/godot_slots.py run [--label L] [--max-wait S] -- <cmd...>     # holds a slot for the child's life, returns its exit code
Exit codes: 75 = timed out waiting for a slot.
API: `with godot_slot("label"): ...`
"""
import argparse
import contextlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

import godot_exe  # Bontago-fca.93: real Godot .exe behind PATH shims

DEFAULT_CAP = 3
DEFAULT_MAX_WAIT_S = 3600.0
POLL_S = 0.5
FRESH_FILE_S = 5.0
TIMEOUT_EXIT = 75
NOT_FOUND_EXIT = 127
SHARED_DIR = "M:/Bontago-tools/locks/godot_slots"
STILL_ACTIVE = 259
PROCESS_QUERY_LIMITED = 0x1000


def cap():
    try:
        return max(1, int(os.environ.get("STACKFALL_GODOT_SLOTS", DEFAULT_CAP)))
    except ValueError:
        return DEFAULT_CAP


def max_wait():
    try:
        return float(os.environ.get("STACKFALL_GODOT_SLOTS_WAIT", DEFAULT_MAX_WAIT_S))
    except ValueError:
        return DEFAULT_MAX_WAIT_S


def slots_dir():
    d = os.environ.get("STACKFALL_GODOT_SLOTS_DIR")
    if not d:
        if os.path.isdir(os.path.dirname(SHARED_DIR)):
            d = SHARED_DIR
        else:
            d = os.path.join(tempfile.gettempdir(), "stackfall_godot_slots")
    os.makedirs(d, exist_ok=True)
    return d


def pid_alive(pid):
    if pid <= 0:
        return False
    if os.name == "nt":
        # os.kill(pid, 0) would TERMINATE the process on Windows; query instead.
        import ctypes
        k32 = ctypes.windll.kernel32
        h = k32.OpenProcess(PROCESS_QUERY_LIMITED, False, pid)
        if not h:
            return False
        try:
            code = ctypes.c_ulong()
            if not k32.GetExitCodeProcess(h, ctypes.byref(code)):
                return True
            return code.value == STILL_ACTIVE
        finally:
            k32.CloseHandle(h)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _path(d, i):
    return os.path.join(d, "slot_%d.json" % i)


def _read(p):
    try:
        with open(p, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def _try_take(d, i, pid, label):
    p = _path(d, i)
    try:
        fd = os.open(p, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        info = _read(p)
        if info is None:
            # Unreadable: being written right now, or corrupt; reclaim only if old.
            try:
                if time.time() - os.path.getmtime(p) < FRESH_FILE_S:
                    return False
            except OSError:
                return False
        elif pid_alive(int(info.get("pid", 0))):
            return False
        # Stale: re-check the owner is unchanged, remove, retry once.
        if _read(p) != info:
            return False
        try:
            os.remove(p)
        except OSError:
            return False
        return _try_take(d, i, pid, label)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump({"pid": pid, "label": label, "start": time.time(), "cmd": " ".join(sys.argv)}, fh)
    return True


def busy_count(d=None):
    d = d or slots_dir()
    n = 0
    for i in range(cap()):
        info = _read(_path(d, i))
        if info is not None and pid_alive(int(info.get("pid", 0))):
            n += 1
    return n


def try_acquire(label="godot", pid=None):
    """One non-blocking, silent attempt: a slot index or None."""
    d = slots_dir()
    for i in range(cap()):
        if _try_take(d, i, pid or os.getpid(), label):
            return i
    return None


def acquire(label="godot", pid=None, wait_s=None):
    """Return a slot index, waiting up to wait_s seconds; raises TimeoutError."""
    d = slots_dir()
    pid = pid or os.getpid()
    wait_s = max_wait() if wait_s is None else wait_s
    deadline = time.time() + wait_s
    announced = False
    while True:
        n = cap()
        for i in range(n):
            if _try_take(d, i, pid, label):
                return i
        if not announced:
            print("waiting for Godot slot (%d/%d busy)" % (busy_count(d), n), file=sys.stderr, flush=True)
            announced = True
        if time.time() >= deadline:
            raise TimeoutError("no Godot slot free after %.0fs (cap %d)" % (wait_s, n))
        time.sleep(POLL_S)


def release(index):
    try:
        os.remove(_path(slots_dir(), index))
    except OSError:
        pass


@contextlib.contextmanager
def godot_slot(label="godot", wait_s=None):
    i = acquire(label, wait_s=wait_s)
    try:
        yield i
    finally:
        release(i)


def status():
    d = slots_dir()
    rows = []
    for i in range(cap()):
        info = _read(_path(d, i))
        if info is None:
            rows.append("slot %d: free" % i)
        else:
            alive = pid_alive(int(info.get("pid", 0)))
            rows.append("slot %d: %s pid=%s label=%s age=%ds" % (
                i, "busy" if alive else "stale", info.get("pid"), info.get("label"),
                int(time.time() - info.get("start", time.time()))))
    return rows


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    child = []
    if "--" in argv:
        k = argv.index("--")
        argv, child = argv[:k], argv[k + 1:]
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", choices=["acquire", "release", "status", "run"])
    ap.add_argument("index", nargs="?", type=int)
    ap.add_argument("--label", default="godot")
    ap.add_argument("--pid", type=int, default=0, help="owner pid for acquire (default: parent process)")
    ap.add_argument("--max-wait", type=float, default=None)
    a = ap.parse_args(argv)
    if a.action == "status":
        print("\n".join(status()))
        return 0
    if a.action == "release":
        if a.index is None:
            ap.error("release needs a slot index")
        release(a.index)
        return 0
    if a.action == "run" and not child:
        ap.error("run needs: -- <cmd...>")
    try:
        if a.action == "acquire":
            print(acquire(a.label, a.pid or os.getppid(), a.max_wait))
            return 0
        i = acquire(a.label, wait_s=a.max_wait)
    except TimeoutError as e:
        print("godot_slots: %s" % e, file=sys.stderr)
        return TIMEOUT_EXIT
    try:
        print("godot slot %d/%d taken (%s)" % (i + 1, cap(), a.label), file=sys.stderr, flush=True)
        if os.path.basename(child[0]).lower().startswith("godot"):
            child[0] = godot_exe.resolve(child[0])  # real .exe, not the godot.cmd shim (Bontago-fca.93)
        return subprocess.call(child)
    except OSError as e:
        print("godot_slots: cannot launch %s: %s" % (child[0], e), file=sys.stderr)
        return NOT_FOUND_EXIT
    finally:
        release(i)


if __name__ == "__main__":
    sys.exit(main())
