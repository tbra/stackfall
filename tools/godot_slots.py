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
  python tools/godot_slots.py run --exclusive [--wait-timeout S] -- <cmd...> # runs the child ALONE (benches, timing)
Exit codes: 75 = timed out waiting for a slot / for exclusivity.
API: `with godot_slot("label"): ...`, `with godot_exclusive("label", wait_s=...): ...`

Exclusive mode (Bontago-fca.95): a single gate file exclusive.json (O_EXCL, owner pid,
state waiting|running, same PID-liveness stale reclaim as slots). While a live gate exists
no other process takes a slot (writer preference: a queued exclusive cannot starve); the
exclusive owner waits for current holders to drain, runs, then deletes the gate. Normal
acquirers re-check the gate after taking a slot and back off if it appeared meanwhile.
Re-entrant: the exclusive owner exports STACKFALL_GODOT_EXCLUSIVE_OWNER=<token> (also in
its own process); an acquire whose env token matches the live gate token is granted at once
(normal: index -1, no slot; exclusive: returns False = not owner). Stale/unknown tokens are
ignored. Several exclusive requests serialize on the gate. Nothing is ever killed.
"""
import argparse
import contextlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import uuid
import time

import godot_exe  # Bontago-fca.93: real Godot .exe behind PATH shims

DEFAULT_CAP = 3
DEFAULT_MAX_WAIT_S = 3600.0
POLL_S = 0.5
FRESH_FILE_S = 5.0
TIMEOUT_EXIT = 75
NOT_FOUND_EXIT = 127
SHARED_DIR = "M:/Bontago-tools/locks/godot_slots"
OWNER_ENV = "STACKFALL_GODOT_EXCLUSIVE_OWNER"
REENTRANT = -1  # slot index returned to a process nested under a live exclusive run
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


def _gate_path(d):
    return os.path.join(d, "exclusive.json")


def _drop(p, info):
    if _read(p) == info:
        try:
            os.remove(p)
        except OSError:
            pass
    return None


def _gate_info(d):
    """Live gate owner info (dict), or None when absent/stale (stale file removed)."""
    p = _gate_path(d)
    info = _read(p)
    if info is None:
        try:
            fresh = time.time() - os.path.getmtime(p) < FRESH_FILE_S
        except OSError:
            return None
        return {"pid": 0, "state": "unknown"} if fresh else _drop(p, None)
    if pid_alive(int(info.get("pid", 0))):
        return info
    return _drop(p, info)


def _nested(d):
    tok = os.environ.get(OWNER_ENV)
    if not tok:
        return False
    g = _gate_info(d)
    return g is not None and g.get("token") == tok


def _gate_blocks(d, pid):
    g = _gate_info(d)
    return g is not None and int(g.get("pid", 0)) != pid


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
    pid = pid or os.getpid()
    if _nested(d):
        return REENTRANT
    if _gate_blocks(d, pid):
        return None
    for i in range(cap()):
        if _try_take(d, i, pid, label):
            if _gate_blocks(d, pid):  # exclusive appeared meanwhile: back off
                _drop_slot(d, i)
                return None
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
        i = try_acquire(label, pid)
        if i is not None:
            return i
        if not announced:
            g = _gate_info(d)
            why = ("exclusive run by pid %s pending" % g.get("pid")) if g else ("%d/%d busy" % (busy_count(d), n))
            print("waiting for Godot slot (%s)" % why, file=sys.stderr, flush=True)
            announced = True
        if time.time() >= deadline:
            raise TimeoutError("no Godot slot free after %.0fs (cap %d)" % (wait_s, n))
        time.sleep(POLL_S)


def _drop_slot(d, index):
    try:
        os.remove(_path(d, index))
    except OSError:
        pass


def _gate_json(pid, label, state, token):
    return {"pid": pid, "label": label, "state": state, "token": token, "start": time.time(), "cmd": " ".join(sys.argv)}


def _take_gate(d, pid, label, token=""):
    if _gate_info(d) is not None:
        return False
    try:
        fd = os.open(_gate_path(d), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        return False
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(_gate_json(pid, label, "waiting", token), fh)
    return True


def acquire_exclusive(label="exclusive", pid=None, wait_s=None):
    """Take the gate, then wait until no slot holder is alive. Returns True when this call
    owns the gate (pair with release_exclusive(pid)); False when nested under a live exclusive
    run (nothing to release). Raises TimeoutError (gate released) if not alone within wait_s."""
    d = slots_dir()
    if _nested(d):
        return False
    token = uuid.uuid4().hex
    pid = pid or os.getpid()
    wait_s = max_wait() if wait_s is None else wait_s
    deadline = time.time() + wait_s
    announced = False
    held = False
    try:
        while True:
            if not held:
                held = _take_gate(d, pid, label, token)
            if held and busy_count(d) == 0:
                tmp = "%s.%d.tmp" % (_gate_path(d), os.getpid())
                with open(tmp, "w", encoding="utf-8") as fh:
                    json.dump(_gate_json(pid, label, "running", token), fh)
                os.replace(tmp, _gate_path(d))
                os.environ[OWNER_ENV] = token  # inherited by the child process tree
                return True
            if not announced:
                print("waiting for exclusive Godot access (%s)" % (
                    "%d slot(s) busy" % busy_count(d) if held else "another exclusive run has the gate"),
                    file=sys.stderr, flush=True)
                announced = True
            if time.time() >= deadline:
                raise TimeoutError("could not run exclusively after %.0fs (%s)" % (
                    wait_s, "holders still running" if held else "another exclusive run has the gate"))
            time.sleep(POLL_S)
    except BaseException:
        if held:
            release_exclusive(pid)
        raise


def release_exclusive(pid=None):
    p = _gate_path(slots_dir())
    info = _read(p)
    if info is None or int(info.get("pid", 0)) == (pid or os.getpid()):
        if info is not None and os.environ.get(OWNER_ENV) == info.get("token"):
            os.environ.pop(OWNER_ENV, None)
        try:
            os.remove(p)
        except OSError:
            pass


@contextlib.contextmanager
def godot_exclusive(label="exclusive", wait_s=None):
    owner = acquire_exclusive(label, wait_s=wait_s)
    try:
        yield
    finally:
        if owner:
            release_exclusive()


def release(index):
    if index == REENTRANT:
        return
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
    g = _gate_info(d)
    if g is None:
        rows.append("exclusive: none")
    else:
        rows.append("exclusive: %s pid=%s label=%s age=%ds" % (
            "RUNNING" if g.get("state") == "running" else "WAITING (new slots blocked)",
            g.get("pid"), g.get("label"), int(time.time() - g.get("start", time.time()))))
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
    ap.add_argument("--max-wait", "--wait-timeout", dest="max_wait", type=float, default=None)
    ap.add_argument("--exclusive", action="store_true", help="run: wait for all holders, then run the command alone")
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
        if a.exclusive:
            if a.action != "run":
                ap.error("--exclusive applies to run")
            i = None if acquire_exclusive(a.label if a.label != "godot" else "exclusive", wait_s=a.max_wait) else REENTRANT
        else:
            i = acquire(a.label, wait_s=a.max_wait)
    except TimeoutError as e:
        print("godot_slots: %s" % e, file=sys.stderr)
        return TIMEOUT_EXIT
    try:
        if i == REENTRANT:
            print("godot_slots: nested under a live exclusive run; no slot taken", file=sys.stderr, flush=True)
        elif i is None:
            print("godot exclusive access granted (%s)" % a.label, file=sys.stderr, flush=True)
        else:
            print("godot slot %d/%d taken (%s)" % (i + 1, cap(), a.label), file=sys.stderr, flush=True)
        if os.path.basename(child[0]).lower().startswith("godot"):
            child[0] = godot_exe.resolve(child[0])  # real .exe, not the godot.cmd shim (Bontago-fca.93)
        return subprocess.call(child)
    except OSError as e:
        print("godot_slots: cannot launch %s: %s" % (child[0], e), file=sys.stderr)
        return NOT_FOUND_EXIT
    finally:
        if i is None:
            release_exclusive()
        else:
            release(i)  # no-op for REENTRANT


if __name__ == "__main__":
    sys.exit(main())
