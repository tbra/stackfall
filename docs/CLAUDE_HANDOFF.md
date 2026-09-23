# Handoff to the next Claude orchestrator

Prepared 2026-09-18 from Git, Beads, project files and the interrupted local Claude
session. This is a restart snapshot. Refresh live state; keep task progress in Beads.

## Update 2026-09-23 (late evening) — resume here

**Git:** `main` 03850cb pushed; full suite 1173/1173 at 99b2995 (physics merge after it verified
with 92/92 targeted + idle benches). Owner granted merge/push mid-session; a new session's
classifier may deny `git merge`/`git push` again — ask once. Owner also lifted the two-writer
cap (`bd memories writer-cap`) and requires agent windowed runs off-screen
(`--position 10000,10000`; rule is in every worker profile).

**Shipped today (all closed in Beads):** every M4 special + throw input/arc + special_consumed
replication + tilt wiring + client disk-tilt mirroring + F9 force-special + impact_triggers hook;
all M3 code children (mv0.1.10/.13/.12, mv0.4, mv0.31/.32) — only the owner two-PC Steam match
(`mv0.2`) keeps M3 open; owner feel rounds 6 and 7 (xtq.9–11, xtq.13–17, mv0.29/.30/.33/.34,
1en.25); m2_acceptance 9/9 again (p0a); MatchTestReset fixture (bmh). M3 4-peer lag/loss +
throw harness PASS; Steam probe status 0; bench_tower ×3 presets PASS; bench_specials_chain
PASS 7.1 ms/step; bench_rain is environmentally noisy on this machine (`bd memories bench-noise`).

**In flight:** `M:/Bontago-worktrees/mirror` (`wt/disc-mirror`, xtq.12 step 2: SSR then a planar
mirror so the disc reflects blocks like `docs/original_hover-preview.png`; step 1 ReflectionProbe
is merged but visually weak — xtq.12 stays OPEN until the owner sees block reflections).

**Owner questions open (`bd human list`):** Bontago-b6l (volcano orbs persist as owner blocks?),
Bontago-6op (may Earthquake/Volcano start mid-air?), 4nz, 3td. **Owner manual pass wanted:**
play copy `M:/Bontago-worktrees/play` (detached at main 03850cb, cache warmed): F9 cycles
specials; LMB drag throws with arc; F4 Physics preset dropdown; two-instance check that the
client's disc tilts under an Anvil. Notes go in `feedback/playtest.md` (round 7 items all filed).

**Then:** M4 epic close (needs the owner's LAN/manual pass + xtq.12 verdict), then M5 AI bots
(`docs/SPEC.md` Part 4: BotController, 3 difficulties, 8-bot headless match) — start with
`stackfall-planner` writing `docs/M5_PLAN.md`. Backlog: `Bontago-ogd` (trimesh rebuild bench).

## Update 2026-09-23 (afternoon session, in progress) — resume here

**Git:** `main` at 6c21ed4 or later (see `git log`), NOT pushed: `git push origin main` is
denied by the permission classifier in this session; the owner runs `git -C M:/Bontago push
origin main` or adds a Bash allow-rule. The same classifier blocked `git merge` until the owner
said "permission granted"; expect to ask again in a new session.

**Merged today (all accepted, closed in Beads):** the three end-of-day branches (p2c-wire
`1en.17`, Earthquake `1en.4`, Anvil `1en.5`; gate ff263b5 974/974), the owner's fourth-test
feel-6 items (`xtq.9/.10` ghost prism+emissive column+near-white footprint, `xtq.11` opaque
mirror disc incl. SPEC §2.10 text + `glass_alpha`/`tint_opacity_boost` removed, `mv0.29`
camera frozen during MMB, `mv0.30` next ghost spawns above the placed block), M4 wave 2+
(`1en.6` Propeller, `1en.18` P3-SH `SpecialPhysics.explode()` with per-body de-dup, `1en.2`
Bomb, `1en.1` Rocket, `1en.19` P4-SPAWN `Match.spawn_special_projectile()` +
`SpecialTuning.ccd_speed_threshold_mps`). Gate on 35fef30: 1007/1007; later merges verified
with targeted sets — run the full suite once more after the current wave merges.

**In flight (worktrees, uncommitted until accepted):** `M:/Bontago-worktrees/p5hole`
(`wt/sp-p5hole`, `1en.20` P5-HOLE, Jev review=yes) and `M:/Bontago-worktrees/volcano`
(`wt/sp-volcano`, `1en.3` Volcano + `bench_specials_chain`, Jev review=yes). Then Jumping Bean
`1en.8` (needs P5-HOLE), P2d throw input `1en.14`, P2e arc preview `1en.15`, `1en.21` client
pending-count decrement. Owner's play copy `M:/Bontago-worktrees/play` is detached at 35fef30;
move it with `git -C M:/Bontago-worktrees/play checkout --detach main` and run the open-editor
pass there once (class cache — see Beads memory `stackfall-class-cache`).

**Process notes today:** two headless Godot processes running `Temp/cast_test.gd` (PIDs
29820/24028) belong to someone else — leave them. Workers' `.import` files for
`docs/original_*.png` are now tracked (came in with the ghost branch). Jev override on Rocket
(review skipped: contract transcription, helper reviewed) is logged in `1en.1`.

## Update 2026-09-23 (end of day) — resume here

**Git:** `main` clean and pushed at the commit carrying this note. Owner's play copy
`M:/Bontago-worktrees/play` (detached; move it with `git -C M:/Bontago-worktrees/play checkout
--detach main`, then run `godot --headless --editor --path M:/Bontago-worktrees/play --quit`
once so the class cache picks up new `class_name`s — a stale cache produced "Could not find
type SpecialDef" script errors today). Owner feedback lives in the gitignored `feedback/`
folder (F12 / pad MISC1 saves screenshots there; the owner also writes notes there):
**check both `M:/Bontago/feedback/` and `M:/Bontago-worktrees/play/feedback/` on every
worker return.** Reference screenshots of the original stay in `docs/original_*.png`.

**Shipped today (all merged to main, full suite 945/945 at d5a0ab3, later commits are docs):**
`Bontago-xtq.5` block mesh winding (every face was inverted), `mv0.28` camera follows the
rotated centre + centre-corrected ghost collision sweep, `xtq.6` thin matte disk (0.2 m),
`xtq.7` ghost as one clean solid + whole-shape projection prism + single hull footprint,
`xtq.8` skybox faces drive the Environment sky (reflections/ambient), `02u` screenshot key,
M4 P2a special interfaces (`config/specials/`, `game/specials/`), P2b pending-special FIFO
queue with claim-time drawn id replicated on the wire (`Bontago-csc`), P2b-ii HUD queue
indicator, P2c-i host-side `request_throw` + `ThrowRules` + spawn-time `SpecialBehavior`
attachment (burned auto-drops keep the special queued). Owner answered z4h(b) mvl(a) 4fa(a)
59u(b); SPEC §2.5/§2.6 updated. Design contracts: `docs/M4_P2_PACKAGES.md` (+ orchestrator
amendments), `docs/M4_SPECIALS_PACKAGES.md` (ten packages for the seven specials; Beads
1en.1-.8 + helpers 1en.18/.19/.20).

**Finished after the owner stopped work (committed on their branches, NOT merged — merge order: p2cw, eq, anvil; then one full-suite gate, then push):**
- `M:/Bontago-worktrees/p2cw` (`wt/p2c-wire`, committed c39130b after the stop) — `Bontago-1en.17`
  P2c-ii throw intent over the wire + `special_triggered` replication, review fixes applied,
  116/116 targeted, `run_m3a_local.ps1 -Peers 2 -ThrowPass` PASS twice with lag, `-Peers 4`
  regression PASS. Ready to merge; then close. Gap it surfaced: `Bontago-1en.21` (client
  pending-special count never decrements; needs a consumed-special replication).
- `M:/Bontago-worktrees/eq` (`wt/sp-earthquake`, committed after the stop) — `Bontago-1en.4`
  Earthquake effect + the roster-nonempty test adjustments, 128/128 targeted, open-editor
  clean; ready to merge. Must merge BEFORE the Anvil. It also corrected the tilt-leveling
  pseudocode (decision 5 in `docs/M4_SPECIALS_PACKAGES.md`).
- `M:/Bontago-worktrees/anvil` (`wt/sp-anvil`, committed 755a419) — `Bontago-1en.5` Anvil,
  done (40/40); merge after Earthquake, then run the full suite once for the batch.

**Owner's fourth test (2026-09-23, after d5a0ab3) — start here, all P1, unassigned:**
`Bontago-xtq.9` ghost more opaque + prism encloses the whole angled ghost (extrude from its
top); `xtq.10` surfaces inside the projection glow (emissive) and the disc footprint is
near-white; `xtq.11` disc is an opaque mirror-like surface, not glass; `mv0.29` camera locked
in place while MMB is held; `mv0.30` QoL: the next ghost spawns clear of the just-placed block.
Briefs are in the Beads descriptions; references `docs/original_single-block.png`,
`docs/original_stacked-tower.png`, `docs/original_in-game.png`. xtq.9/xtq.10 share
`GhostPreview.gd` (one worker, sequential); xtq.11 and mv0.29 are independent.

**Open owner questions (`bd human list`):** `Bontago-4nz` (queued special when the held piece
auto-drops and burns; default: stays queued), `Bontago-3td` (special-punched hole eliminating a
home; default: yes, consistent).

**Then:** M4 specials per `docs/M4_SPECIALS_PACKAGES.md` dispatch order (Propeller and P3-SH
next, then P4-SPAWN/P5-HOLE serialized, Rocket+Bomb, Volcano+Bean), P2d throw input (LMB
flick, `Bontago-1en.14`, needs 1en.17), P2e arc preview (`1en.15`). Process notes learned
today: fresh worktrees need `godot --headless --editor --path <wt> --quit` twice before GUT;
`Match` is a singleton across a GUT run — tests that duplicate a config must restore it in
`after_each`; blocks spawned in a test must be freed synchronously in `after_each` or GUT
reports unfreed children; `--sandbox` windows the owner runs are visible in `tasklist`, never
kill them. Untouched owner files: `tools/start_scotty.ps1` (modified), `Scotty.cmd`.

## Update 2026-09-22 (end of day) — resume here

**Git:** `main` clean and pushed at the commit carrying this note. Only worktree:
`M:/Bontago-worktrees/play` (owner's copy at `f2e1927`; rebuild from main, copy
`addons/godotsteam`, run `tools/install_original_assets.ps1 -Path M:/Bontago-worktrees/play`).
No workers running; nothing uncommitted anywhere.

**Owner's third test of the original (2026-09-22 evening) — fixed:** reject kick 75% smaller
(`reject_arc_sideways` 0.3, `reject_arc_height` 0.375, commit `a058af4`).

**Owner's third test — open, start here (P1, unassigned, briefs in the Beads descriptions):**
1. `Bontago-xtq.5` — placed blocks render with missing faces (`docs/solid-blocks-issue.png`):
   `core/blocks/BlockMeshBuilder.gd` winds some faces clockwise so back-face culling hides
   them; the translucent ghost masked it. Fix the tangent/index table; add a test that every
   triangle's geometric normal matches its vertex normal and points away from the cell (must
   fail on current code first); screenshot L4/T4/bar4/slab6 from a low side angle.
   Jev: sonnet 0.56, review=yes.
2. `Bontago-mv0.28` — "when rotating the block the camera adjusts; lock the camera to the
   centre of the box without messing up the bottom-centre fixes": camera follow anchor = the
   rotated shape's geometric centre; MMB rotation pivots about that centre so the block spins
   in place; cursor/raycast/footprint/spawn origin keep the bottom-centre of the rotated
   bounds (`GhostPreview._rotated_bottom_offset`, `MatchPlacement._spawn_block` parity test).
   Jev: sonnet 0.56.
   Both were dispatched then stopped before any edit; re-dispatch from the descriptions.

**Owner retest still requested:** cursor stopping at the screen edge could not be reproduced
(capture is on in every mode; Esc and F4 release it by design).

**Open owner questions (`bd human list`):** `Bontago-z4h`, `Bontago-4fa`, `Bontago-59u`,
`Bontago-mvl` (throw binding; blocks M4 P2's throw half).

**Then:** M4 P2 without throw, P3–P5 (see the late brief below), backlog unchanged.

## Update 2026-09-22 (late)

**Git:** `main` clean and pushed at the commit carrying this note. Only worktree:
`M:/Bontago-worktrees/play` (owner's copy; rebuild from main, copy `addons/godotsteam`, run
`tools/install_original_assets.ps1 -Path M:/Bontago-worktrees/play`).

**Shipped since the night brief (owner's second test of the original):** MMB drag is full
3-DOF (yaw about world up, pitch about the camera's right axis); the footprint is the XZ hull
of the rotated cells; the ghost casts no shadow and has no shadow blob; the reject kick is a
world-space offset; the ghost is grey whenever it cannot be dropped; `CameraTuning.fov_deg`
slider; blocks render as one solid mesh per shape (`core/blocks/BlockMeshBuilder.gd`, collision
unchanged); the disc is glass (`glass_alpha`, `tint_opacity_boost`); camera jitter root-caused
to process order (CameraRig now `process_priority` 1, regression test in `test_camera_rig`).
Full suite 850+ green.

**Owner retest asked for:** the "cursor stops at the screen edge" report could not be
reproduced from code (capture is enabled in every mode); retest in a standalone window and
remember Esc and F4 release capture by design.

**Open owner questions (`bd human list`):** `Bontago-z4h`, `Bontago-4fa`, `Bontago-59u`,
`Bontago-mvl` (throw binding; blocks M4 P2's throw half).

**Next exact actions:** M4 P2 without throw (special framework, arming/trigger on impact,
chain cap, `Match.held_special` consumption in `_spawn_block()`), then P3–P5. Backlog
unchanged (see the night brief below), plus: a dedicated physics layer for placed blocks.

## Update 2026-09-22 (night)

**Git:** `main` clean and pushed at the commit carrying this note. Only worktree:
`M:/Bontago-worktrees/play` (owner's copy; recreate from main, copy `addons/godotsteam` in,
run `tools/install_original_assets.ps1 -Path M:/Bontago-worktrees/play`).

**Shipped tonight (all reviewed/merged, full suite green):** M4 P0b tilt controller
(`Field.apply_tilt_impulse`, off until `set_tilt_enabled(true)`; P5 wires it from
`MatchConfig.tilt_mode`), M4 P1a+P1b gift crates (`autoload/match/MatchGifts.gd`,
`game/GiftCrate.tscn`, one spawn roll per placement window, claim on territory tick,
`Match.held_special(slot)` for P2), feel round 3 from the owner's test of the original:
MMB-drag rotates the ghost (continuous yaw), RMB-drag orbits + wheel zooms while held,
ghost collides with placed blocks without pushing them, out-of-zone drops are refused
(piece stays held), expiry relocation jumps cursor+camera; tuning panel rows show
"(default X)" + description (every new tunable needs an entry in
`config/tuning_panel_hints.tres`, `test_tuning_panel` enforces it); owner defaults
follow_lag 0 / pitch -35 / sensitivity 0.015. Placeholder assets from the original
install: `tools/install_original_assets.ps1` → gitignored `assets/original/` (+ `.gdignore`),
`autoload/Sfx.gd` (music, thuds via velocity-drop detector, UI clicks, refusal),
`game/Skybox.gd` (per-map sets, seam table derived by `tools/skybox_seam_probe.gd`).
Third-party files never enter the repo.

**Process rules (owner, tonight):** `bd` writes use `--actor stackfall-orchestrator`;
dispatched issues get `--assignee "<profile> (<model>)"`, unstarted issues stay
unassigned; owner questions are `decision` issues with `--label human --assignee Tony`
(answer with `bd human respond`), never interactive prompts; never `taskkill //IM`.

**Open owner questions (`bd human list`):** Bontago-z4h Jumping Bean under hole-mode Off;
Bontago-4fa gift spawn rule (defaults shipped); Bontago-59u pending-special replacement
(default shipped); Bontago-mvl throw binding (RMB now orbits) — blocks M4 P2's throw.

**Next exact actions:**
1. Owner manual checks in `--sandbox --players=2`: controls (MMB/RMB), ghost collision,
   refused drop, expiry relocation, F4 labels, audio, skybox; two-PC Steam test (M3b).
2. M4 P2 (special framework, arming/trigger, chain cap) can start without the throw
   half; throw + arc preview waits for Bontago-mvl. Then P3–P5 per `docs/M4_PLAN.md`
   (P5 wires tilt; Propeller replaces Fan; Jumping Bean is `Bontago-1en.8`).
3. Backlog: `Bontago-ogd` (trimesh rebuild-cost bench), a dedicated physics layer for
   placed blocks (ghost sweep filters by `is RigidBody3D` today), `mv0.1.10`, `mv0.1.13`,
   `mv0.4`, `mv0.1.12`, `Bontago-2mi`, `Bontago-mjk`, `Bontago-pjj`.

**Untouched files not from this session:** `tools/start_scotty.ps1` (modified), `Scotty.cmd` (new).

## Update 2026-09-22 (evening) 

**Git:** `main` clean and pushed at the commit carrying this note. Only worktree:
`M:/Bontago-worktrees/play` (owner's copy, stale at `a03be82`; recreate from main and copy
`addons/godotsteam` in before the owner plays). Commit + push authority per Beads memory
`stackfall-git-authority`.

**Shipped this evening:** Bontago-mv0.20 (lobby gravity reaches physics; camera follow
distance/pitch and disk mesh segments are live in the F4 panel). **Bontago-ruw closed:** the
disk is now one rebuildable `ConcavePolygonShape3D` trimesh in `game/Field.gd`; a lone hole
swallows a block. **Bontago-ddz closed (root cause of every "marginal tower"):** Jolt's
body-pair contact cache reused stale contacts inside a creeping 40-block column, so
tower results depended on body creation order; `body_pair_contact_cache_distance_threshold`
is now 0.0001 (`tools/bootstrap_project.gd`). `bench_tower` was also broken since the
bottom-centre pivot (Bontago-r2v) and now takes `--offset=x,z`; it PASSES at 0/0,
0.25/0.25, 0.5/0 with 0.016 m drift, asleep at 0.52 s. Full suite 764/764 (~70 s).

**Process rules added today (owner):** every `bd` write passes `--actor stackfall-orchestrator`;
every dispatched issue gets `--assignee "<worker profile> (<model>)"`; never close an
unassigned issue. Workers check Godot processes with `tasklist | grep -i godot` (findstr is
broken in Git Bash) and never `taskkill //IM` (a worker killed another agent's benchmark).

**Next exact actions:**
1. Owner manual checks: `--sandbox --players=2` — controls/F4 sliders (camera follow
   distance/pitch now live), drop a cube over a single isolated hole (falls through), stack
   10+ blocks on a cell centre (no rocking). Two-PC Steam test (M3b, `Bontago-mv0.2`).
2. **Owner decision before M4 P1 starts:** `docs/M4_PLAN.md` builds gift crates as stationary
   `Area3D` pickups; `docs/SPEC.md` §2.6 says reconcile that before implementing. Ask.
3. M4 per `docs/M4_PLAN.md` (P0b tilt controller is next: owns `game/Field.gd`; P0a is
   done). Route every package via `tools/route_model.py`. Epic children fixed today:
   `Bontago-1en.6` is Propeller (was Fan), `Bontago-1en.8` Jumping Bean added.
4. Backlog: `Bontago-ogd` (trimesh rebuild-cost benchmark, Sonnet), `mv0.1.10`, `mv0.1.13`,
   `mv0.4`, `mv0.1.12`, `Bontago-2mi`, `Bontago-mjk`, `Bontago-pjj`.

**Untouched working-tree files not from this session:** `tools/start_scotty.ps1` (modified)
and `Scotty.cmd` (new) appeared at 20:56 on 2026-09-22; left for their author.

## Update 2026-09-22 (midday)

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
