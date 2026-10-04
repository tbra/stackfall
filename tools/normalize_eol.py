"""Rewrite CRLF to LF in a checkout's changed text files before staging (Bontago-fca.26).

  python tools/normalize_eol.py [--path <checkout>] [--dry-run] [files...]

.gitattributes already stores every text file as LF, but agents on Windows write CRLF into
the working tree, so each `git add`/`git commit` printed "CRLF will be replaced by LF" for
every touched file. Run this before staging a candidate: it lists modified and untracked
files (or the given files), asks git which ones resolve to `eol=lf` text, and rewrites only
those in place. Files git treats as binary or `eol=crlf` (*.bat, *.cmd) are left alone.
Prints one summary line; exit 0 unless git fails.
"""

import argparse
import os
import subprocess
import sys

GIT_TIMEOUT_S = 60
ATTR_CHUNK = 200


def git(path, *args):
    res = subprocess.run(["git", "-C", path] + list(args), capture_output=True,
                         timeout=GIT_TIMEOUT_S)
    if res.returncode != 0:
        sys.exit("normalize_eol: git %s failed: %s" % (args[0], res.stderr.decode(errors="replace").strip()))
    return res.stdout.decode("utf-8", errors="replace")


def changed_files(path):
    out = git(path, "status", "--porcelain", "-z", "--untracked-files=all", "--no-renames")
    files = []
    for entry in out.split("\0"):
        if len(entry) > 3 and entry[0] != "D" and entry[1] != "D":
            files.append(entry[3:])
    return files


def lf_text_files(path, files):
    """Files whose attributes resolve to eol=lf text (attr text != unset/binary, eol != crlf)."""
    attrs = {}
    for i in range(0, len(files), ATTR_CHUNK):
        out = git(path, "check-attr", "-z", "text", "eol", "--", *files[i:i + ATTR_CHUNK])
        parts = out.split("\0")
        for j in range(0, len(parts) - 2, 3):
            attrs.setdefault(parts[j], {})[parts[j + 1]] = parts[j + 2]
    keep = []
    for f in files:
        a = attrs.get(f, {})
        if a.get("text") in ("unset", "unspecified") or a.get("eol") == "crlf":
            continue
        keep.append(f)
    return keep


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=".", help="checkout to normalise (default: cwd)")
    ap.add_argument("--dry-run", action="store_true", help="report files that would change")
    ap.add_argument("files", nargs="*", help="limit to these checkout-relative files")
    args = ap.parse_args()
    files = args.files or changed_files(args.path)
    fixed = []
    for f in lf_text_files(args.path, files):
        full = os.path.join(args.path, f)
        if not os.path.isfile(full):
            continue
        with open(full, "rb") as fh:
            data = fh.read()
        # text=auto still leaves files git sniffs as binary alone; mirror that with a NUL check.
        if b"\r\n" not in data or b"\0" in data:
            continue
        if not args.dry_run:
            with open(full, "wb") as fh:
                fh.write(data.replace(b"\r\n", b"\n"))
        fixed.append(f)
    verb = "would normalise" if args.dry_run else "normalised"
    print("normalize_eol: %s %d file(s)%s" % (verb, len(fixed), (": " + ", ".join(fixed[:8]) + (" ..." if len(fixed) > 8 else "")) if fixed else ""))


if __name__ == "__main__":
    main()
