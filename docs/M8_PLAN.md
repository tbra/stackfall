# M8 Plan: Extra Specials & Hardening

Epic bead: `Bontago-8or`. Spec: `docs/SPEC.md` §2.6/2.7 (specials table), §3.5
(physics/body-limit tuning), §3.6 (networking), Part 4 M8 acceptance criteria.
Base checkout: `M:/Bontago-worktrees/m8-plan` @ `63265f9` on `wt/m8-plan`
(matches `main`). No M8 game code has landed yet. This plan is the design
contract for the packages below (P0, P1-P8); it does not decide the two
owner questions in "Owner decisions needed before dispatch" below.

Every package obeys `CLAUDE.md` unchanged: static typing everywhere, no magic
numbers (new tunables go in a `res://config` `Resource`), pure rule logic
stays in `res://core/`, new signals go through `Events`, all new input goes
through the Input Map, no new addons, host is authoritative for physics.

## Current-state audit

- **The four new specials do not exist at all.** `config/specials/` holds only
  `SpecialDef.gd`, `SpecialTuning.gd`, and seven `.tres` (anvil, bomb,
  earthquake, jumping_bean, propeller, rocket, volcano — `ls` confirmed).
  `game/specials/` holds the shared driver (`SpecialBehavior.gd`,
  `SpecialEffect.gd`, `SpecialPhysics.gd`) plus one script per existing
  special. No Magnet/Freeze/Glue/GravityWell script or `.tres` exists.
- **Spec gives exact numbers for all four** (`docs/SPEC.md` lines 252-255),
  none tagged `[ORIGINAL]` (all four rows say `NEW`): Magnet pulls enemy
  blocks within 8 m toward itself for 3 s; Freeze makes your own blocks
  within 6 m static for 20 s; Glue joins touching blocks of yours within 4 m
  with breakable joints, break force 40; Gravity well flips gravity to 30%
  within 10 m for 5 s. No radius/duration/force numbers are OPEN — unlike
  Propeller/Jumping Bean's still-open lift/hop tunables, there is no owner
  question about *what* these four specials do, only about a few
  implementation mechanics (below).
- **`game/specials/SpecialPhysics.gd`** (128 lines, read in full) has exactly
  one static helper, `explode()`: sphere-queries real bodies, dedupes by
  instance id (a multi-cell `Block` has one `CollisionShape3D` per cell —
  its own comment lines 58-69), applies an *outward, team-agnostic* impulse
  with a distance falloff, and calls `Block.mark_script_kick()` so
  `Block._integrate_forces()` doesn't double-damp it. It has **no
  ownership/team filter** (explicit "orchestrator decision 2026-09-23 item 1:
  explosions are team-agnostic... nothing in this project sets a
  distinguishing physics layer") and **no pull-toward, no freeze, no joint
  creation** — none of the four new specials can reuse `explode()` unchanged,
  but its sphere-query-and-dedupe body (lines 37-83) is the right template for
  a new query-only helper the four specials share (P0 below).
- **`game/specials/SpecialEffect.gd`/`SpecialBehavior.gd`** (61 and 208 lines,
  both read in full) need **no changes** for the four new specials — every
  hook a new effect needs (`physics_tick`, `impact_triggers`,
  `wants_early_trigger`, `detonate`, `trigger_others_in_range`) already
  exists and is exercised by existing effects (Bomb = pure impact/fuse,
  Anvil = settle-triggered via `wants_early_trigger() -> block.sleeping`,
  reads `Match.field()`). Not a hotspot.
- **Stable-block freezing and body cap are 100% greenfield.** Repo-wide grep
  for `max_active_blocks|dissolve|freeze_mode|FREEZE_MODE` found no hits
  outside comments (JumpingBeanEffect's "off-disk punch" comment,
  `PlacementRules.REASON_OFF_DISK`). `game/Block.gd` (331 lines, read in
  full) has no freeze/STATIC logic and no "seconds asleep" tracking; sleep
  state is read via the plain built-in `sleeping` property, and the existing
  "contributing to territory influence" glow already has the exact
  host/client dual-path this milestone should mirror: host drives it off the
  real `sleeping_state_changed` signal, client drives it off `SnapshotSync`'s
  wire `sleeping` flag (`Block.gd` lines 292-319).
- **`game/BlockRegistry.gd`** (grepped in full for function names, key
  regions read) already tracks every live `Block`: `tracked_block_count()`
  (line 248), `influence_circles()` (line 172), `bodies_over_cells(cells)`
  (line 219), and the despawn hook `_on_block_removed(block, _reason)`
  (lines 138-144, registry bookkeeping only — erases the entry and the
  `net_id` map, no visual, no RPC). `net/MatchNet.gd:418`
  `replicate_despawn(net_id, reason)` is the existing wire path a host uses
  to tell clients a block is gone. **Body-cap removal should call whatever
  existing code path already free()s a block for another reason (e.g. a
  kill-plane fall) and add a dissolve visual there, not invent a second
  despawn path** — the implementer must locate that call site (grep
  `queue_free|replicate_despawn` from `Field.gd`/`Match.gd`) before writing
  new removal code.
- **Late join / reconnect: the raster keyframe path is wired, block replay is
  not.** `docs/M3a_PLAN.md` lines 282-297 ("Known limitations") is the
  authoritative scope statement: "the raster's full-keyframe path... [is]
  not built" for a mid-match joiner. Concretely:
  - `autoload/Net.gd`'s `_rpc_handshake()` (lines ~1155-1173) refuses any
    peer with `JoinError.MATCH_IN_PROGRESS` whenever
    `set_accepting_joins(false)` is in effect. That flag's own doc comment
    (lines 1294-1319) and its live call site, **`game/Main.gd:836`**
    (`Net.set_accepting_joins(to_state == Match.State.LOBBY)`), are the
    single seam a "mid-match join" setting must extend.
  - `net/MatchNet.gd`'s `_on_net_peer_joined()` (lines 1122-1126) **already**
    sets `_force_full_raster = true` and calls
    `_authority().on_peer_rejoined(slot_id)` on every join, gated on nothing
    but the join itself — so once a peer is allowed in, the territory side
    is already handled. **What's actually missing is block replay**:
    `replicate_spawn(block, net_id)` (line 398, read in full) fires only at
    spawn time (`rpc(&"net_block_spawned", net_id, block.shape_id,
    block.owner_slot, block.global_position, basis.get_rotation_quaternion())`);
    a peer that connects after blocks already exist gets none of them. This
    is the concrete gap the bead's "raster... designed for it but not built"
    line refers to, once block state is separated from territory state.
  - `autoload/match/MatchLifecycle.gd`'s `on_peer_left()`/`on_peer_rejoined()`
    (lines 555-575) already implement disconnect-grace bookkeeping for a
    peer reconnecting to **their own existing slot** (a timer,
    `_net_config.disconnect_grace`, defaults 10 s per `config/NetConfig.gd`
    line 45) — this is distinct from, and already partly solves, "reconnect"
    as opposed to "late join" (a slot that was never seated before). Both
    still need the same missing piece: resending existing block state.
  - `config/MatchConfig.gd` (lines 1-90, read in full) has no mid-match-join
    setting; spec's "Mid-match joins can be enabled in settings" needs a new
    `@export var allow_mid_match_join: bool = false`.
- **Exports: only one preset exists.** `export_presets.cfg` has exactly one
  `[preset.N]` block (`preset.0`, "Windows Desktop"). Linux and macOS presets
  are net-new configuration, not a "verify it still works" task. The owner's
  machine is Windows-only (per the assignment), so Linux/macOS crash-free
  verification itself is an owner/CI manual step; only "the export completes
  without engine error via the headless export CLI" is verifiable in-session.
- **Soak harness already exists.** `game/Main.gd` already wires
  `--headless-host --bots=<n> --seconds=<n>`, with a documented literal
  acceptance command `--headless-host --bots=8 --seconds=60` in its own
  comments, plus a fail-fast check when the host never binds. `tools/
  triage_log.py` (CLAUDE.md's own log-triage tool) exists and is what M8's
  2-hour soak should run over the resulting log, per CLAUDE.md's "Use it on
  the M5 bot matches and the M8 soak." No new harness needed, only a longer
  run plus a triage pass and a memory/frame-time sample.

## Shared-file hotspots (serialize — do not parallelize these files)

- **`game/specials/SpecialPhysics.gd`**: P0 (below) adds a new static
  query-only helper here; no other M8 package should touch this file. Land
  P0 first, commit, then dispatch P1/P3/P4 (Magnet/Glue/Gravity well) against
  the updated base.
- **`game/Block.gd`**: P5 (stable-block freeze) adds the freeze-reason API
  here (see P5's Interfaces). P2 (Freeze special) is a *consumer*, not a
  co-editor — dispatch P5 before P2, land it, then P2 calls the new methods
  without re-touching this file's freeze logic itself.
- **`config/MatchConfig.gd`**: only P6 (late join) adds a field here
  (`allow_mid_match_join`). No other M8 package edits it.
- **`export_presets.cfg`**: only P7 (exports) touches it.
- **`autoload/Net.gd` / `net/MatchNet.gd` / `autoload/match/MatchLifecycle.gd`**:
  all owned solely by P6 (late join/reconnect); no other package reads or
  writes these three files this milestone.

## Interface stubs (establish before consumers)

1. **P0 establishes** `SpecialPhysics.query_bodies_in_range(space_state,
   center, radius, exclude, owner_filter: Callable = Callable()) ->
   Array[RigidBody3D]` — a query-only sibling to `explode()` (same
   sphere-query + instance-id dedupe, no impulse, no wake), with an optional
   `Callable(RigidBody3D) -> bool` filter so a caller can restrict to
   `body.owner_slot != mover.owner_slot` (Magnet) or `== mover.owner_slot`
   (Freeze/Glue) without `SpecialPhysics.gd` itself knowing about ownership
   semantics. **Consumed by P1 (Magnet), P3 (Glue), P4 (Gravity well).**
   Verified present for consumers: `Block.owner_slot` already exists
   (`game/Block.gd:14`), so the filter Callable is trivial to write in each
   consumer.
2. **P5 establishes** on `game/Block.gd`: `request_freeze_static(reason:
   StringName) -> void`, `release_freeze_static(reason: StringName) ->
   void`, `is_freeze_static() -> bool`, backed by a small internal
   `Dictionary` of active reasons (freezes to `FREEZE_MODE_STATIC` while
   non-empty, restores `FREEZE_MODE_RIGID` when empty) — so the stable-block
   auto-freeze and the Freeze special can each hold an independent freeze
   claim on the same block without one releasing the other's freeze early.
   Also establishes `wake_for_impulse() -> void` (releases the `&"stable"`
   reason and clears `freeze = false` before an impulse would otherwise be a
   no-op on a static body) for any impulse-applying code to call first.
   **Consumed by P2 (Freeze special)** and by **P0's `explode()`/new helper**,
   which must call `wake_for_impulse()` on a hit `Block` before applying an
   impulse (a one-line addition to `SpecialPhysics.gd`, owned by P5 since it
   depends on the freeze API existing — dispatch order P0 -> P5 -> P1-4).
   Verified present for consumers: `Block.gd` already has the identical
   idempotent-reason-tracking precedent in `_contributing_visual_set`
   (lines 89-95) and `mark_script_kick()`/`_script_kick_pending`, so this is
   an established pattern in the same file, not a new one.

## Package split

### P0 — Special range-query helper (model: Sonnet)
Owned files: `game/specials/SpecialPhysics.gd` (edit, additive method only),
`tests/unit/test_special_physics.gd` (extend).
Interfaces added: `query_bodies_in_range()` (see Interface stubs above).
Dependencies: none. Dispatch first, before P1/P3/P4.
Acceptance: targeted GUT run (`test_special_physics`) covering the dedupe
(multi-cell block counted once), the optional filter Callable excluding/
including as expected, and radius=0/negative returning empty. No windowed
run needed.

### P1 — Magnet special (model: Sonnet)
Owned files: `game/specials/MagnetEffect.gd`, `config/specials/magnet.tres`,
`tests/unit/test_magnet_effect.gd`.
Interfaces added: `MagnetEffect extends SpecialEffect`, timed-effect pattern
(overrides `impact_triggers() -> false` like Propeller/Volcano, so its own
landing impact can't short-circuit the pull window), `physics_tick()` calls
`SpecialPhysics.query_bodies_in_range()` each armed tick with an
enemy-only filter (`body.owner_slot != _block.owner_slot`, `_block` being
the Magnet's own body) within 8 m, and pulls each toward the Magnet's
position (an inward `apply_central_force`/`apply_impulse` scaled by
`delta`, direction `(magnet.global_position - body.global_position)
.normalized()`) for 3 s total, ended via `wants_early_trigger()` returning
true once `_age since arm >= 3.0`. Reads `SpecialTuning` the way
`BombEffect.gd:18` does (`preload("res://config/special_tuning.tres")`).
Dependencies: P0 (query helper) must land first.
Acceptance: targeted GUT (`test_magnet_effect`) — a stub `Block` at a known
offset with a known `owner_slot`, assert force direction, assert an
own-owner block at the same distance is excluded, assert the pull stops
after 3 s. No windowed run needed (pure logic + stub Block, no real
physics/scene needed — mirrors `test_special_behavior.gd`'s own approach of
driving `advance()`/`physics_tick()` directly).
Model: Sonnet. Review: `stackfall-reviewer`.

### P2 — Freeze special (model: Sonnet)
Owned files: `game/specials/FreezeEffect.gd`, `config/specials/freeze.tres`,
`tests/unit/test_freeze_effect.gd`.
Interfaces added: `FreezeEffect extends SpecialEffect`, ordinary impact/fuse
pattern (like `BombEffect.gd` — no `physics_tick`/`wants_early_trigger`
override needed). `detonate()` queries own-owner blocks within 6 m via
`SpecialPhysics.query_bodies_in_range()` with an own-owner filter
(`body.owner_slot == _block.owner_slot`), calls
`block.request_freeze_static(&"freeze_special")` on each hit `Block`, and
schedules a release 20 s later. **# DECISION** (record in code): the release
timer is a per-block `Timer` node added as a child of each frozen block
(one-shot, `timeout` -> `release_freeze_static(&"freeze_special")`,
`queue_free()` itself after) rather than a new tick-driven scheduler,
because `SpecialEffect` instances are shared `Resource`s (one per `.tres`,
not per-instance state) and cannot hold per-activation timers themselves —
mirrors how `AnvilEffect.gd` avoids per-instance state via `set_meta()` on
the affected body instead. Fixed 20 s duration, no early wake on impulse —
spec's plain reading ("makes your own blocks static for 20 s") describes a
fixed window; `Block.request_freeze_static()` is reason-keyed specifically
so this doesn't fight the stable-block optimization's own freeze/wake.
Dependencies: **P5 must land first** (needs `request_freeze_static`/
`release_freeze_static` on `Block.gd`).
Acceptance: targeted GUT (`test_freeze_effect`) — stub `Block`s, assert only
own-owner blocks within radius get frozen, assert the Timer fires and calls
release. No windowed run needed for the freeze mechanic; **one** windowed
screenshot is acceptable only if the implementer wants to visually confirm
a frozen block actually stops moving under gravity in a running scene — not
required for acceptance, name it explicitly if used (probe budget: 1 of 3).
Model: Sonnet. Review: `stackfall-reviewer`.

### P3 — Glue special (model: Sonnet)
Owned files: `game/specials/GlueEffect.gd`, `config/specials/glue.tres`,
`tests/unit/test_glue_effect.gd`.
Interfaces added: `GlueEffect extends SpecialEffect`, ordinary impact/fuse
pattern. `detonate()` queries own-owner blocks within 4 m via
`SpecialPhysics.query_bodies_in_range()`, filters to pairs that are actually
touching (AABB overlap or `global_position` distance below a small
"touching" epsilon — **# DECISION**: use each block's own collision-shape
half-extent sum plus `PhysicsTuning.cube_margin` as the touching test,
mirroring `BlockFactory`'s own placement-adjacency convention rather than
inventing a new epsilon), and creates a `Generic6DOFJoint3D` between each
touching pair. **# DECISION**: Godot's `Joint3D` types have no built-in
"break force"; breakability is implemented by sampling
`PhysicsServer3D.generic_6dof_joint_get_param()` reaction is not directly
exposed either, so the effect tracks each joint's two connected bodies'
*relative linear acceleration times combined mass* each physics tick (a
Node the joint owns, `_physics_process`) and calls `joint.queue_free()`
once that exceeds the spec's "break force 40" — the simplest reasonable
approximation of a stress test, noted in code. This per-joint tick node is
a new small owned file `game/specials/GlueJoint.gd` (still P3's ownership,
not a new package — under the 10-file cap).
Dependencies: P0 must land first.
Acceptance: targeted GUT (`test_glue_effect`) — stub touching/non-touching
`Block` pairs, assert a joint is only created for touching own-owner pairs,
assert the joint frees itself once a synthetic relative-acceleration sample
exceeds 40. No windowed run needed (joint creation is inspectable via
`get_children()`/node type, no rendering required).
Model: Sonnet. Review: `stackfall-reviewer`.

### P4 — Gravity well special (model: Sonnet)
Owned files: `game/specials/GravityWellEffect.gd`,
`config/specials/gravity_well.tres`, `tests/unit/test_gravity_well_effect.gd`.
Interfaces added: `GravityWellEffect extends SpecialEffect`, timed-effect
pattern (`impact_triggers() -> false`). `detonate()` snapshots every body
within 10 m via `SpecialPhysics.query_bodies_in_range()` (no ownership
filter — spec doesn't say "enemy" or "own" for this one, and Bomb/Rocket's
own explosions are already team-agnostic by the standing orchestrator
decision; **note this is a genuine ambiguity, see Owner decisions below**),
records each body's original `gravity_scale` via `set_meta()` (the
`AnvilEffect.gd` idempotent-`set_meta()` idiom, lines ~40-50 of that file),
sets `gravity_scale = 0.3` for 5 s, then restores the recorded value.
Dependencies: P0 must land first.
Acceptance: targeted GUT (`test_gravity_well_effect`) — stub `Block`s inside
and outside 10 m, assert only in-range bodies get `gravity_scale` changed,
assert restoration to the original (non-default) value after 5 s, not a
hardcoded 1.0. No windowed run needed.
Model: Sonnet. Review: `stackfall-reviewer`.

### P5 — Stable-block freezing + Block.gd freeze API (model: Sonnet)
Owned files: `game/Block.gd` (edit: freeze-reason API, see Interface stubs),
`game/StableBlockManager.gd` (new — host-only periodic scan), `config/
PhysicsTuning.gd` (edit: add `@export var stable_freeze_delay_s: float =
20.0` — **# DECISION**: no spec number exists for "old" beyond the fidelity
table's prose ("freeze old stable blocks as static"); 20 s matches Freeze
special's own number for consistency, is simplest, and is a single named
tunable an owner can retune later), `tests/unit/test_stable_block_manager.gd`,
`tests/unit/test_block_freeze_api.gd`.
Interfaces added: see "Interface stubs" above.
**# DECISION**: "not touching any awake body" (spec §3.5, adjacent to
"freeze old stable blocks") is satisfied by relying on Jolt's own island-sleep
semantics rather than a manual per-tick contact check — a rigid body only
reports `sleeping == true` once its entire contact-connected island is at
rest, so "asleep continuously for `stable_freeze_delay_s`" already implies
"not touching an awake body" for free. A manual touching-check would either
duplicate the physics engine's own island detection or need
`contact_monitor`, which `game/Block.gd`'s own comment says cost 5-7 ms/step
at 300 blocks and was removed — this avoids reintroducing that cost.
`StableBlockManager` runs `_physics_process` at a low rate (e.g. every 0.5 s,
a new `PhysicsTuning` field is unnecessary — reuse a simple internal
accumulator), iterates `BlockRegistry`'s tracked blocks (needs a new
`BlockRegistry.all_blocks() -> Array[Block]` accessor — **owned by P5 since
it's additive and this package is the only consumer this milestone**;
verify `BlockRegistry.gd`'s `_entries` dictionary already holds every live
block, confirmed lines 107-110), and calls `request_freeze_static(&"stable")`
once a block's continuous-asleep timer clears `stable_freeze_delay_s`, or
`release_freeze_static(&"stable")` the instant it wakes (hook
`sleeping_state_changed`, the same signal `Block.gd` already listens to for
the territory-influence glow).
Dependencies: none (lands before P0's small follow-up and before P2).
Dispatch order: **P5 lands before P2**; P5 may land in parallel with
P0/P1/P3/P4 since it touches a disjoint file set, but P0's tiny
`wake_for_impulse()` call-site addition to `SpecialPhysics.gd` must be
added *after* P5 lands (a second, small, P5-owned follow-up edit to
`SpecialPhysics.gd` — call this out at dispatch as "P5b").
Acceptance: targeted GUT (`test_stable_block_manager`, `test_block_freeze_api`)
— assert a block asleep past the threshold gets frozen, assert waking
releases it, assert two independent freeze reasons on the same block both
need releasing before it unfreezes. No windowed run needed for the logic;
one windowed run is acceptable only to visually confirm a frozen pile stops
consuming a bounce/rebound-damping tick (probe budget: 1 of 3, name it if
used).
Model: Sonnet. Review: `stackfall-reviewer`.

### P6 — Late join, reconnect, and body cap/removal (model: Sonnet, with a
named Opus-override candidate for the networking half — see below)
Owned files: `autoload/Net.gd` (edit: extend `set_accepting_joins()`'s
condition), `game/Main.gd` (edit: line 836's call site), `config/
MatchConfig.gd` (edit: add `allow_mid_match_join: bool`), `net/MatchNet.gd`
(edit: add a "replay existing blocks to one newly joined peer" RPC path,
e.g. `_replay_blocks_to(peer_id)` called from `_on_net_peer_joined()` when
the joiner has no prior slot history, using the same wire shape
`replicate_spawn()` already sends but via `rpc_id()` to just that peer),
`game/BlockCapEnforcer.gd` (new — host-only, checks
`BlockRegistry.tracked_block_count()` against a new `PhysicsTuning.
max_active_blocks: int = 600`, and when over cap, removes the
lowest-influence off-disk-or-fully-buried blocks first with a visible
dissolve), `tests/unit/test_late_join.gd`, `tests/unit/test_block_cap_enforcer.gd`.
**Split rationale**: both halves are host/network-authoritative "hardening"
work with no shared file overlap (late-join touches `Net.gd`/`Main.gd`/
`MatchNet.gd`/`MatchConfig.gd`; body-cap touches only new files plus reading
— not writing — `BlockRegistry.gd`/`PhysicsTuning.gd`), but late-join alone
is already close to the ~30-minute/10-file budget with real protocol-design
risk (ordering of replay vs. snapshot vs. roster, per `docs/M3a_PLAN.md`'s
own "chunked world-state transfer" framing) — **if the orchestrator judges
either half alone exceeds ~30 minutes at dispatch time, split into P6a
(late join/reconnect) and P6b (body cap/removal); they do not share files
and can run in parallel worktrees if split.**
Interfaces added: `Net.set_accepting_joins()`'s existing signature is
unchanged, only its call-site condition at `Main.gd:836` grows an `or
match_config.allow_mid_match_join`. `BlockRegistry.gd` needs one new
read-only accessor for body-cap: **verify at dispatch** whether
`influence_circles()` (line 172) already returns enough per-block data to
rank "lowest influence" or whether a new accessor is needed — full read of
that function's signature was not completed this session; the implementer
must read it before finalizing the removal scoring formula. **# DECISION
candidate for the implementer**: score = territory-cell count contributed
(reuse whatever `influence_circles()` already computes) with off-disk/
fully-buried blocks (reuse `PlacementRules.REASON_OFF_DISK` and a "buried"
test via `bodies_over_cells()`) sorted first — pick the simplest scoring
that satisfies "lowest-influence... off the disk or fully buried... removed
first" and note it as a `# DECISION`, this is implementation detail, not a
gameplay ambiguity.
Dependencies: none from other M8 packages; independent of P0-P5.
Acceptance: targeted GUT (`test_late_join`, `test_block_cap_enforcer`) plus
one ENet-based ad hoc test per CLAUDE.md's "works for a client over ENet
with simulated lag" (mirrors M3a's own late-join-adjacent tests if any
exist — check `tests/unit/test_net_session.gd` for the pattern); a second
peer connects mid-match, receives existing block spawns, and the territory
raster full-keyframe still applies. No windowed run required (headless
ENet, matches the existing `tools/run_gut.ps1` targeted pattern).
Model: **Opus override candidate** for the networking half only (P6/P6a) —
protocol ordering (replay vs. snapshot vs. disconnect-grace interaction) is
the single hardest reasoning task in this milestone and a bug here is a
silent desync, not a crash; justify the escalation in the dispatch brief,
return to Sonnet for P6b (body cap) which is ordinary bounded logic.
Consult `python tools/route_model.py` before overriding, per CLAUDE.md.
Review: `stackfall-reviewer`, plus consider a Codex second-opinion review
specifically on the replay-ordering race (per CLAUDE.md's "isolated
implementation package" guidance for the bridge) given the "hard bug"
profile — orchestrator's call, not binding here.

### P7 — Cross-platform export presets (model: Sonnet, integrator-run gate)
Owned files: `export_presets.cfg` (edit: add Linux/macOS `[preset.N]`
blocks mirroring the existing Windows one's structure).
Dependencies: none; can run any time, independent of P0-P6.
Acceptance: **integrator-run**, not a worker package with GUT tests — this
is `godot --headless --export-release "Linux/X11" build/linux/Stackfall.x86_64`
and the macOS equivalent completing without a CLI error. Actual crash-free
running of the Linux/macOS binaries is an **owner-manual step** (the
project's own machine is Windows-only per this assignment) — record that
limitation explicitly rather than claiming verification that didn't happen.
Model: Sonnet (config-only edit). Review: `stackfall-reviewer` checks the
preset diff only (no code to review).

### P8 — 2-hour bot soak + log triage (integrator-run gate, not a worker package)
No new owned files (`game/Main.gd`'s `--headless-host --bots=<n>
--seconds=<n>` already exists per the audit above). Run:
`godot --headless --path . -- --headless-host --bots=8 --seconds=7200`
on an otherwise-idle machine (CLAUDE.md's own note on bench/timing runs),
capture the log, then `python tools/triage_log.py <log>` (needs
`TYPESAFE_API_KEY`; degrades to deterministic grouping without one, per
CLAUDE.md). Acceptance: the run completes 7200 s without the engine
crashing or `triage_log.py` exiting non-zero on a confident likely-bug.
This gate should run **after** P0-P6 land (it exercises specials, freeze,
cap, and — if a client bot joins mid-run — late join), so schedule it last.

## Dispatch order and parallelism

1. **P0** (SpecialPhysics query helper) — solo, lands first.
2. **P5** (stable-block freeze + Block.gd API) — parallel with P0 (disjoint
   files); land before P2.
3. After P0 lands: **P1, P3, P4** (Magnet, Glue, Gravity well) — parallel
   with each other (disjoint new files each), and parallel with P5/P2 once
   P5 has landed (all four consume P0's helper, none share a file with P5/P2).
4. After P5 lands: **P5b** (P5's own tiny `SpecialPhysics.gd` follow-up,
   `wake_for_impulse()` call in `explode()`) then **P2** (Freeze special).
5. **P6** (late join/reconnect/body cap, or split P6a/P6b) — fully
   independent of the specials/freeze work; may run in parallel with steps
   1-4 in its own worktree from the start.
6. **P7** (exports) — independent, any time.
7. **P8** (2-hour soak) — last, after P0-P6 are integrated, run by the
   integrator on an idle machine.

## Owner decisions needed before dispatch

None of the four new specials' own numbers are ambiguous (spec gives exact
radius/duration/force for all four, tagged `NEW` not `[ORIGINAL]`). Two
points below are genuine gameplay-feel ambiguities the spec doesn't settle,
not implementation detail — flagging rather than deciding:

1. **Gravity well's ownership scope.** Magnet is explicitly "enemy blocks"
   and Freeze/Glue are explicitly "your own blocks," but Gravity well's spec
   row (`docs/SPEC.md` line 255) says only "flips gravity... within 10 m,"
   naming no owner restriction. P4 above defaults to **team-agnostic**
   (matching the standing Bomb/Rocket/explosion precedent — "the anvil hurt
   everyone" — orchestrator decision 2026-09-23 item 1), but a well that
   also yanks the thrower's own stack down is a materially different feel
   from one that only punishes opponents. Needs a `decision` bead
   (`--label human --assignee Tony`) only if the owner wants it scoped
   differently than the explosion precedent; otherwise P4 proceeds
   team-agnostic as the simplest consistent default.
2. **Mid-match join's effect on the match clock.** `docs/SPEC.md`'s M8 line
   doesn't say whether match time pauses while a new peer joins (unlike
   §2.8's documented sudden-death pause behavior for other events). P6's
   plan above does not add a pause — a late joiner simply starts receiving
   state — but if the owner wants match time to pause during the join
   handshake (fairness: a joining player shouldn't lose match time to
   loading), that changes `MatchLifecycle`'s state machine, which is a
   feel/scope decision, not an implementation detail. Flag via a `decision`
   bead before dispatching P6 if this matters to the owner; otherwise P6
   proceeds with no pause as the simplest default.

## Package-specific tests (summary)

`test_special_physics.gd` (P0), `test_magnet_effect.gd` (P1),
`test_freeze_effect.gd` (P2), `test_glue_effect.gd` (P3),
`test_gravity_well_effect.gd` (P4), `test_stable_block_manager.gd` +
`test_block_freeze_api.gd` (P5), `test_late_join.gd` +
`test_block_cap_enforcer.gd` (P6) — all targeted GUT runs via
`tools/run_gut.ps1 <name>,<name>,...`, no windowed runs required for any
worker package. P7/P8 are integrator-run CLI gates, not GUT tests.
