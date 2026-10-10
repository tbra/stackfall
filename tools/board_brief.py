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
    parent_hygiene(limit)
    stale_blocked(limit)
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


def parent_hygiene(limit):
    """Non-epic issues with open/in_progress status where all children are closed
    should either be closed or have remaining work filed as a separate child issue."""
    import owner_replies
    rows = owner_replies._export()
    # Build a map: parent_id -> (open_child_count, total_child_count)
    parent_info = {}
    for row in rows:
        for dep in row.get("dependencies") or []:
            if (dep.get("type") or dep.get("dependency_type")) == "parent-child":
                parent = dep.get("depends_on_id")
                if parent not in parent_info:
                    parent_info[parent] = [0, 0]
                parent_info[parent][1] += 1  # increment total children count
                if row.get("status") != "closed":
                    parent_info[parent][0] += 1  # increment open children count
    # Find non-epic, open/in_progress issues with children, all of which are closed
    problems = []
    for row in rows:
        row_id = row["id"]
        if row.get("issue_type") == "epic" or row.get("status") == "closed":
            continue
        if row.get("status") not in ("open", "in_progress"):
            continue
        if row_id not in parent_info:
            continue
        open_count, total_count = parent_info[row_id]
        if total_count > 0 and open_count == 0:
            problems.append((row_id, row.get("status", "?"), total_count))
    if not problems:
        return
    print(f"parent hygiene: {len(problems)}")
    for row_id, status, child_count in problems[:limit]:
        print(f"  {row_id} {status} all {child_count} children closed - close or file remaining work")


def find_stale_blocked(rows):
    """Pure classifier: status=blocked issues whose every 'blocks' dependency is
    closed (parent-child links ignored). Issues with no blocks deps are skipped:
    they were blocked by hand, not by a dependency."""
    status = {row["id"]: row.get("status") for row in rows}
    stale = []
    for row in rows:
        if row.get("status") != "blocked":
            continue
        blockers = [dep.get("depends_on_id") for dep in row.get("dependencies") or []
                    if (dep.get("type") or dep.get("dependency_type")) == "blocks"]
        if blockers and all(status.get(b) == "closed" for b in blockers):
            stale.append(row)
    return stale


def stale_blocked(limit):
    """One bd export call; prints a count and at most `limit` lines."""
    import owner_replies
    stale = find_stale_blocked(owner_replies._export())
    if not stale:
        return
    print(f"stale blocked (all blockers closed): {len(stale)}")
    for row in stale[:limit]:
        print("  " + brief(row))
    if len(stale) > limit:
        print(f"  ... {len(stale) - limit} more")


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError, KeyError) as exc:
        print(f"board_brief: {exc}", file=sys.stderr)
        sys.exit(1)
