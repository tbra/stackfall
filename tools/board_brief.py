"""Print a bounded Beads board overview for the orchestrator's main context."""

import argparse
import json
import shutil
import subprocess
import sys


def read_issues(*args):
    result = subprocess.run(
        [shutil.which("bd.cmd") or shutil.which("bd") or "bd", *args, "--json"],
        capture_output=True, text=True, check=True
    )
    data = json.loads(result.stdout)
    return data if isinstance(data, list) else data.get("issues", [])


def brief(issue):
    title = " ".join(issue.get("title", "").split())
    if len(title) > 85:
        title = title[:82] + "..."
    assignee = issue.get("assignee") or "unassigned"
    return f"{issue['id']} P{issue.get('priority', '?')} {title} [{assignee}]"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, default=5, help="items per section (max 10)")
    args = parser.parse_args()
    limit = max(1, min(args.limit, 10))
    for label, command in (("ready", ("ready",)), ("in progress", ("list", "--status=in_progress"))):
        issues = read_issues(*command)
        print(f"{label}: {len(issues)}")
        for issue in issues[:limit]:
            print("  " + brief(issue))
        if len(issues) > limit:
            print(f"  ... {len(issues) - limit} more; query a specific bead if needed")


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError, KeyError) as exc:
        print(f"board_brief: {exc}", file=sys.stderr)
        sys.exit(1)
