"""Resolve the Godot executable for the Python launchers (Bontago-fca.93).

A PATH shim such as C:/Users/<you>/bin/godot.cmd cannot be exec'd by subprocess
without cmd.exe in between, and a timeout kill then orphans the real Godot. This
resolver returns the real .exe the shim points at.

    resolve(name="godot") -> str
      1. env GODOT, if set and it exists.
      2. shutil.which(name) (or name + ".exe"). A .cmd/.bat hit is read and its first
         double-quoted *.exe path (with %VAR% expanded) is returned if it exists.
      3. Otherwise the which() hit, or the bare name.
"""

from __future__ import annotations

import os
import re
import shutil
from typing import Optional

SHIM_SUFFIXES = (".cmd", ".bat")
QUOTED_EXE = re.compile(r'"([^"]*\.exe)"', re.IGNORECASE)


def _exe_from_shim(shim: str) -> Optional[str]:
    try:
        with open(shim, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return None
    for m in QUOTED_EXE.finditer(text):
        candidate = os.path.expandvars(m.group(1))
        if os.path.exists(candidate):
            return candidate
    return None


def resolve(name: str = "godot") -> str:
    env_path = os.environ.get("GODOT")
    if env_path and os.path.exists(env_path):
        return env_path
    found = shutil.which(name) or shutil.which(name + ".exe")
    if found and found.lower().endswith(SHIM_SUFFIXES):
        exe = _exe_from_shim(found)
        if exe is not None:
            return exe
    return found or name
