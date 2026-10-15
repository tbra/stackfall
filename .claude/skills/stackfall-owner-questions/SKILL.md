---
name: stackfall-owner-questions
description: Ask the Stackfall owner a question through a Beads decision (format, body file, gating) and act on the owner's reply when new owner replies appear. Use whenever work needs an owner decision or the session brief or board_brief.py shows a reply.
---

# Owner questions

The owner answers through Beads, never through interactive prompts. Only the orchestrator files decisions; a worker reports the ambiguity to the orchestrator instead.

## Ask

1. File a `decision` issue under the epic of the work it gates, with `--label human --assignee Tony`. Keep it short and plain:
   - Title: the question, ending in `?` (<= 90 chars, no `Decision:` prefix, ids or paths).
   - Body: `Issue:` (1-2 sentences), `Options:` 2-6 lines `a) ...` (one line each), `Recommend:` a letter with one short reason, and at most one `Details:` line.
   - Several sub-questions become one decision whose Issue lists the defaults, with options `a) accept all defaults` / `b) change some`.
2. Write the body to a file under `M:/Bontago-tools/scratch/` (not `/tmp`) and create the issue with `--body-file` in a direct `bd` command: the `bd.cmd` shim truncates `--description` at the first newline, and in the owner's checkout the human-desk mod refuses a decision that breaks the format above (a script calling bd through Python bypasses that check).
3. Block the dependent work with `bd gate create --type human --blocks <work-id> --reason "<one plain line, <= 160 chars>"` or a dependency. Where a tunable default can ship meanwhile, say so in the issue and continue.

## Act on a reply

Replies arrive through `tools/owner_replies.py`, which the SessionStart hook and the end of `python tools/board_brief.py` run; `bd human list` shows decisions still waiting. A new reply is an owner decision, so handle it before choosing other work:

1. Record the decision on the gated work bead (`bd comments add <work-id> ...`).
2. `bd human respond` already closed the decision; close it yourself if it is still open. Resolve its gate with `bd gate resolve <gate-id>` (or remove the dependency) so the work is unblocked.
3. Continue the unblocked work, or re-plan it if the answer changed its scope.

During long unattended runs, run `python tools/board_brief.py` at each batch boundary so replies are not missed.
