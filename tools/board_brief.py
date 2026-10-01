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
    epic_hygiene()
    # Owner 2026-10-01: surface new owner replies on Beads at every board scan.
    import owner_replies
    owner_replies.main([])


def epic_hygiene():
    """Owner 2026-10-02: epics stay high-level; an open epic with no open
    child means it is done (close it) or its remaining reason needs a bead;
    no dated per-round epics (e.g. 'Playtest feedback <date>')."""
    import re
    import owner_replies
    rows = owner_replies._export()
    open_children = {}
    for row in rows:
        for dep in row.get("dependencies") or []:
            if (dep.get("type") or dep.get("dependency_type")) == "parent-child":
                parent = dep.get("depends_on_id")
                open_children.setdefault(parent, 0)
                if row.get("status") != "closed":
                    open_children[parent] += 1
    problems = []
    for row in rows:
        if row.get("issue_type") != "epic" or row.get("status") == "closed":
            continue
        if open_children.get(row["id"], 0) == 0:
            problems.append(f"{row['id']} open with no open child: close it or file the remaining bead")
        if re.search(r"20\d\d-\d\d-\d\d|round \d+", row.get("title", ""), re.IGNORECASE):
            problems.append(f"{row['id']} is a dated/round epic: move children to the subject epic and close it")
    if problems:
        print("EPIC HYGIENE (fix before new work):")
        for line in problems:
            print("  " + line)


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError, KeyError) as exc:
        print(f"board_brief: {exc}", file=sys.stderr)
        sys.exit(1)
