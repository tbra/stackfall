"""Locate the bd CLI for project tools.

On this machine `bd` is an npm shim (bd.cmd -> node -> bd.exe). The native binary starts
faster, and a subprocess timeout can kill it; killing the shim left its child holding the
pipes, so a 40 s timeout once ran for minutes.
"""
import os
import shutil


def native_or(shim):
    """The native bd.exe installed next to an npm shim path, else the shim itself (or None)."""
    if shim:
        native = os.path.join(os.path.dirname(shim), "node_modules", "@beads", "bd", "bin", "bd.exe")
        if os.path.isfile(native):
            return native
    return shim


def bd_executable():
    """Best bd command for subprocess calls: native binary, then shim, then bare `bd`."""
    return native_or(shutil.which("bd.cmd") or shutil.which("bd")) or "bd"
