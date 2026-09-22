# Handoff to the next Claude orchestrator

Prepared 2026-09-18 from Git, Beads, project files and the interrupted local Claude
session. This is a restart snapshot. Refresh live state; keep task progress in Beads.

## Update 2026-09-22 — resume here

**Git:** `main` clean and pushed at the commit that carries this note (see `git log -1`).
Only worktree: `M:/Bontago-worktrees/play` (owner's playable copy, detached; recreate
freely). Commit + push authority granted by the owner (Beads memory `stackfall-git-authority`).

**Shipped today:** in-game tuning panel (F4 / Start+X; `ui/TuningPanel.gd`), per-player
HUD (held/next preview, interval ring, LOCKED), `autoload/Match.gd` split into
`autoload/match/{MatchFeed,MatchPlacement,MatchTerritory,MatchLifecycle}.gd` (pure
refactor), test fixtures on a tiny map so the **full suite runs in ~2 min** (754 tests,
753 pass, 1 known pending), `tools/run_gut.ps1` now fails properly, worker profiles carry
the week's operating notes, and **model routing via Jev**: run
`python tools/route_model.py --title ... --files ... --kind ... < brief` before every
dispatch and log its verdict (model / review / split) in the Beads dispatch comment.

**Policy (owner):** one outcome per package (≤ ~10 files, ~30 min), short report template,
targeted tests only for workers, full suite once per merged batch, reviewer only for
`core/`/`net/`/`autoload/`/physics/rules. See `docs/AGENT_WORKFLOW.md`.

**Next exact actions:**
1. Owner manual checks on the current build (`godot --path M:/Bontago-worktrees/play -- --sandbox --players=2`):
   controls feel (tune via F4), HUD, footprint, camera start; two-PC Steam test (M3b, `Bontago-mv0.2`).
2. `Bontago-mv0.20` wire the lobby gravity setting into physics; make camera follow
   distance/pitch and disk mesh segments live for the tuning panel.
3. M4 (`docs/M4_PLAN.md`, read its amendment header and `docs/SPEC.md` §2.6 first). Route
   each package through `tools/route_model.py`; specials roster per the original.
4. Backlog: `Bontago-ruw` (lone hole, needs the trimesh floor — Jev says Opus), `mv0.1.10`,
   `mv0.1.13`, `mv0.4`, `mv0.1.12`, `Bontago-2mi` (Dolt push).

## Update 2026-09-21 (end of day) — resume here

**Git:** `main` is clean and pushed (`6badb77` + this handoff commit). No worktrees other
than `M:/Bontago-worktrees/play` (the owner's playable copy; detached, safe to delete and
recreate with `git worktree add --detach M:/Bontago-worktrees/play <sha>` then copy
`addons/godotsteam` into it). Commit authority: the owner granted "commit when it's done,
you don't need my approval" on 2026-09-20 (Beads memory `stackfall-git-authority`); pushes
were also authorized. `bd dolt push` is broken on this machine (`Bontago-2mi`); the local
Beads DB is authoritative and `.beads/issues.jsonl` is exported with the repo.

**What shipped since the 09-19 update (all on main):** M3b Steam transport + menu/lobby UI
(`5f948a6`), Windows export for a Steam-addable build (`tools/export_windows.ps1`), lobby
ready/phantom-slot/hot-seat fixes, sandbox mode (`--sandbox`), the evidence-backed spec
audit (`docs/SPEC.md` "Decisions made — current target"; `docs/ORIGINAL_INSTALL_EVIDENCE.md`,
`docs/ORIGINAL_BONTAGO_NOTES.md`), territory rules per that audit (overlap holes default,
goal no-build zones, one-raycast placement, continuous solve, optional argmax mode),
original fixed-window cadence, owner-coloured blocks, bottom-centre pivot, original-style
block-locked camera and controls (README has the tables), wheel-only height, footprint
projection, smooth circle-derived territory rendering with a rim, and a rewritten
`tests/bench/m2_acceptance.gd` (9 criteria, ~117 s).

**Gate policy (owner, 09-21):** workers run targeted tests only (`tools/run_gut.ps1`);
the full suite runs once per merged batch in the background. Last full run on `a1538a3`:
678/677/1 known pending; later merges were validated with targeted sets, the ENet harness
and `m2_acceptance`. A background full run on `6badb77` is the first thing to start.

**Next exact actions (in order):**
1. `Bontago-mv0.18` in-game tuning panel (F4; sliders by reflection over the tuning
   resources; live physics apply; save to `user://`). The brief is in the issue; a worker was
   dispatched and stopped before writing anything — start fresh on `main`.
2. `Bontago-mv0.3` shorten the slow test scripts (ranking in the issue comments:
   `test_match_flow`, `test_match_lifecycle`, `test_block_registry`, `test_tower_placement`
   dominate); `Bontago-mv0.13` make `tools/run_gut.ps1` exit non-zero on failures.
3. `Bontago-mv0.9` HUD "Player N's turn" banner → per-player status.
4. Owner manual steps outstanding: two-PC Steam match (M3b acceptance, `Bontago-mv0.2`),
   real gamepad feel, `--sandbox` hotkeys by hand.
5. Then M4 per `docs/M4_PLAN.md` (read its amendment header and SPEC §2.6 first; the
   original's specials roster is DaBomb, Volcano, Earthquake, Propeller, Anvil, Rocket,
   Jumping Bean).

**Open [OPEN] rule items decided in place (revisit only if the owner objects):** overlap-mode
home elimination = hole under the flag; timer phase per player; goal zones block placement
only; auto-drop relocation kept.

## Update 2026-09-19 — M3a repair candidate accepted, awaiting the Git gate

The six review findings `Bontago-mv0.1.4`–`.9` are fixed, integrated, reviewed
(stackfall-reviewer and Codex) and closed. The candidate is **uncommitted** in
`M:/Bontago` on `main` at `081ae21`: 19 modified files plus new
`tests/unit/test_remote_intent_validation.gd` and `tests/unit/test_match_lifecycle.gd`.
Evidence, log paths and the `git add` list are in the `Bontago-mv0.1` comments and
notes. Worktree `M:/Bontago-worktrees/m3a-ids` (branch `m3a-review-ids`) holds a
superseded copy of the `.7`/`.8` edits; remove it after the commit
(`git worktree remove M:/Bontago-worktrees/m3a-ids && git branch -D m3a-review-ids`).
Wire `net_id` is now u24 (spec §3.4 says u16; technical deviation, DECISION in
`core/net/Quantize.gd`). Owner question `Bontago-mv0.1.11` and follow-ups `.10`,
`.12`, `.13` are open and non-blocking. After the commit: close `Bontago-mv0.1`
and start M3b at `Bontago-mv0.2.1` (see below). The section that follows is the
original 2026-09-18 brief.

## Start the replacement chat

From PowerShell:

```powershell
Set-Location M:/Bontago
claude --agent stackfall-orchestrator
```

Paste this as the first message (it also works in a normal Claude Code chat):

> Continue as Stackfall's orchestrator. Read CLAUDE.md, AGENTS.md,
> docs/AGENT_WORKFLOW.md and docs/CLAUDE_HANDOFF.md; run bd prime and inspect
> current Git/Beads state. Recover the interrupted M3a review. Use the saved
> stackfall workers to reproduce and fix Bontago-mv0.1.4 through .9, run the
> relevant integrated validation and independent review, then continue the
> milestone pipeline. Preserve ownership and checkpoint every worker in Beads.
> Follow the conservative Git policy and the existing spec pause points.

A new chat can recover project context but does not reset the account usage limit.
Agent definitions persist on disk; working state persists through Beads and the
preserved checkout. These instructions do not claim a Claude worker is running.

## Where the previous session stopped

The recovered substantive session was
`6721ea0a-5554-4b64-91f4-131b3c5fb181` under
`C:/Users/tonyf/.claude/projects/M--Bontago/`.
Its final exchange received an independent Codex netcode review, then the
orchestrator said it was spot-checking the most serious findings. It hit the
session limit before completing that verification or fixing them. The M3b planning
worker also failed with a rate-limit error before producing a plan. Do not treat
its partial design discussion as implemented work.

At the start of this handoff audit, `main` was clean at `081ae21` (merge of log
triage tooling). Cached `origin/main` matched; no remote fetch was performed.
Only the main checkout and branch were registered, with no active merge conflict.
This handoff then added instruction/profile changes, left uncommitted under the
active conservative policy. Inspect `git status` for their current state.

## Milestone state and recovered findings

M0, M1 and M2 are closed in Beads; M2 is `Bontago-26v`. M3 (`Bontago-mv0`) and
M3a (`Bontago-mv0.1`) remain in progress. M3a's code is merged, including P4
`44f2957`, router/autoload integration `b871576`, harness fixes `7b56939` and
menu/lobby screenshot tool `586cbe1`. The former issue note about an unresolved
`FakeNet.gd` merge was stale, not an instruction to resume a merge.

The following six issues preserve the interrupted review. A separate source
inspection during this handoff supported each code-level gap at `081ae21`;
runtime reproduction and fixes remain outstanding. Line numbers below refer to
that revision and will drift. Full reproduction/acceptance briefs are in Beads.

| Issue | Finding | Starting point |
| --- | --- | --- |
| `Bontago-mv0.1.4` | Negative remote `feed_seq` can skip sequence validation | `autoload/Match.gd:443`, `net/MatchNet.gd:481` |
| `Bontago-mv0.1.5` | Unchecked orientation index reaches placement and cursor auto-drop | `core/blocks/BlockOrientations.gd:30`, `net/MatchNet.gd:767` |
| `Bontago-mv0.1.6` | Remote pose/quaternion lack finite/range checks; submitted height is retained | `autoload/Match.gd:454` and `:478` |
| `Bontago-mv0.1.7` | Monotonic body IDs exceed the 16-bit snapshot encoding | `game/BlockRegistry.gd:105`, `core/net/Quantize.gd:287` |
| `Bontago-mv0.1.8` | Handshake accepts connections after match start | `autoload/Net.gd:571` |
| `Bontago-mv0.1.9` | Teardown/rehost and match-start ordering can leave stale world/raster state | `game/Main.gd:156` and `:178`, `autoload/Match.gd:166` |

For `.9`, also test the first network start: Match emits LOADING before creating
the new raster, while Main's synchronous handler reads the raster. Distinguish
this from the repeated-start failure instead of assuming a single reproduction.

Start a `stackfall-netcode` worker on `.4`–`.6` in sequence: they share
`Match.gd`/`MatchNet.gd` and must not have competing writers. Other workers may
inspect `.7`–`.9` read-only while ownership is established. The planner can
package independent fixes; do not assume the ID allocator or lifecycle paths are
disjoint merely because their issue titles differ. Close M3a only after these
findings are resolved or disproved with evidence, then validated and reviewed.

## Evidence already available, and what to rerun

Commit `7b56939` reports repeated four-peer ENet acceptance passes with 100 ms lag
and 2% loss after fixing the expected peer count and pre-match counter race. This
is historical author-reported evidence, not a rerun by this handoff. The old
session also reported 14 passing log-triage tests and idle-machine bench_rain
timings of 5.21 ms on main versus 5.09 ms on M2; its earlier slow reading was
attributed to concurrent workloads. Re-measure relevant gates after code changes.

Have `stackfall-integrator` run open-project import, GUT, the four-peer acceptance
harness and relevant regression/benchmark scenarios from README.md and
docs/AGENT_WORKFLOW.md. Retain exact candidate identity, exit results, per-peer
logs and pending tests. Run performance checks serially. Do not carry historical
passes forward to untested fixes. A `stackfall-reviewer` needs the candidate diff
and those results; use the Codex bridge for a further independent review if useful.

The old session mentioned hung Godot processes. Process IDs in that transcript
are historical: verify current identity and ownership, never copy its kill command
into a new session blindly.

## Established decisions and subsequent work

Do not re-ask already answered M3a questions: concurrent player timers
(`Bontago-mv0.1.1`), 10-second disconnect grace then elimination (`.2`), and hidden
`--hot-seat` (`.3`) are recorded in closed issues. The old question sections in
M3a_PLAN.md and SPEC.md have not all been reconciled. If the exact implementation
would conflict with a rule tagged ORIGINAL, follow the existing owner pause rule.
`START_HERE.md` still describes M0 and is historical, not current progress.

After M3a acceptance, M3b is `Bontago-mv0.2`. Read `docs/M3b_RESEARCH.md` and begin
with `Bontago-mv0.2.1`, the GodotSteam extension-load/missing-library spike. No
M3b plan or GodotSteam addon existed at handoff. Verify live upstream details
before downloading; research conclusions are dated. Preserve the decision to
keep Valve redistributables out of the public repository. The current `.gitignore`
does not yet contain the promised DLL/SO/dylib exclusions: add and verify them
before staging/installing those artifacts. A fresh clone/worktree must handle
missing native libraries deliberately, not crash the normal import gate.

Other existing issues include lone-hole collision `Bontago-ruw`, physical LAN
verification `Bontago-bw8`, gamepad feel `Bontago-3nk`, physics headroom
`Bontago-mjk`, territory cost `Bontago-pjj`, and M6 team/map configuration
`Bontago-keo.1` / `.2`. Do not recreate these. Match rules remain in the spec;
Beads owns status, and milestone plans own package design.

## What this handoff changed

`Bontago-koz` tracks this coordination work: updated CLAUDE.md and matching
AGENTS.md guidance; added the orchestrator and five worker profiles; updated the
existing Codex bridge; added this brief and the shared worker protocol; preserved
the six findings in Beads. No game code was changed or repaired. Profile/tool
configuration was checked statically against local CLI capabilities and current
official documentation; no Claude inference run or game test was performed for
these documentation changes. Commits, pushes and remote Beads sync were not run.
