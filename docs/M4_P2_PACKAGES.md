# M4 P2 — dispatchable packages (re-cut against current code, 2026-09-23)

Re-cuts `docs/M4_PLAN.md`'s P2 section against `main` @ `cde6359` (clean
except `docs/SPEC.md`'s uncommitted 2026-09-22 owner-decision diff, already
read into this plan). P0/P1 are done: `game/Field.gd`, `config/TiltTuning.gd`,
`autoload/match/MatchGifts.gd`, `game/GiftCrate.gd` exist and pass
`test_gift_claim.gd`/`test_gift_spawner.gd`. `config/specials/` and
`game/specials/` are still empty — the interface-stub gap is still real.
`autoload/Match.gd` is a thin forward over `autoload/match/{MatchFeed,
MatchPlacement,MatchTerritory,MatchLifecycle,MatchGifts}.gd`; every package
below edits the owning controller file plus a one-line forward on `Match.gd`.

**Owner decisions folded in** (SPEC.md diff, closed in Beads):
- **Bontago-mvl (a):** throw = hold **left** mouse on the held special, drag,
  flick-release; RMB stays camera orbit. `throw_aim`'s mouse binding moves
  RMB → LMB (`tools/bootstrap_project.gd`, gamepad LT unchanged); resolved
  against ordinary `ghost_place` (also LMB) by drag-distance/speed
  thresholds (P2d).
- **Bontago-59u / Bontago-csc:** pending specials are a per-player FIFO
  queue capped at `max_pending_specials` (default 3), not the shipped
  latest-wins scalar `MatchGifts._held_specials`. Package P2b.
- **Bontago-4fa:** gift spawn defaults accepted as shipped; unchanged here.
- **Bontago-z4h:** Jumping Bean punches no hole under `HoleMode.OFF` — P5
  scope only, noted for the record.

**Hard external dependency for P2d/P2e:** another worker is currently
editing `game/GhostPreview.gd`, `game/PlayerController.gd`,
`game/CameraRig.gd` (Bontago-mv0.28). P2d/P2e touch the same three files and
**must not start until that lands** — verify via `git log`/Beads before
dispatch; all line citations below are against `cde6359`, re-diff after.

## Decisions this re-cut makes (implementation detail, not asked of the owner)

1. **Special type is drawn at spawn time, not claim time.** The FIFO queue
   (Bontago-59u) holds generic placeholder tokens (count only); `_spawn_
   block()` weighted-draws a real `SpecialDef` each time it pops one. Keeps
   the claim-side wire shape (`Events.gift_claimed`) unchanged — no [P2a]/
   [P2b] file-overlap risk.
2. **`ThrowRules.validate()` delegates to `PlacementRules.validate_point()`**
   (`core/rules/PlacementRules.gd:268-283`) instead of re-deriving
   `raster.team_at()`/`is_contested()` — one source of truth.
3. **Arming impact detection reuses `Block`'s own velocity-drop pattern**
   (`game/Block.gd:61-75`): `SpecialBehavior` samples its parent's
   `linear_velocity` itself each tick; `mass * (prev_speed - now_speed)`
   crossing `def.arm_impulse` is the trigger. No `game/Block.gd` edit, no
   `contact_monitor` wiring.
4. **A remote client's mirrored copy of another player's special shows no
   tint this milestone** — `net_block_spawned`'s wire shape is unchanged
   (brief's own "zero changes" instruction); a client never calls
   `_spawn_block()` so it never gets a `SpecialBehavior`. Host simulation
   and outcomes are unaffected. Known limitation, listed below.
5. **A claim landing while a slot's queue is already full still pops the
   crate** (`Events.gift_claimed` fires) but grants nothing — simplest
   option that can't let a crate sit forever in owned territory.

## Packages

### P2a — Special interfaces, arming/triggering, chain cap (the stub package)

**Outcome:** `SpecialDef`/`SpecialEffect`/`SpecialBehavior`/`SpecialTuning`
exist and compile; a `SpecialBehavior` arms, detects an impact, triggers
once, chains within radius, respects the depth cap, and force-fires at the
fuse timeout — provable without physics. **Must land before P3/P4/P5.**

**Owned (new unless noted):**
- `config/specials/SpecialDef.gd` — old plan's fields (`id`, `scene`,
  `weight`, `enabled_by_default`, `arm_delay`, `arm_impulse`,
  `fuse_timeout_s`, `effect: SpecialEffect`) plus
  `static func load_all_specials() -> Array[SpecialDef]` mirroring
  `config/blocks/BlockShape.gd:100`'s `load_all_shapes()` exactly (scan
  `res://config/specials/`, sort by id) and `static func pick_weighted
  (candidates: Array[SpecialDef], rng: RandomNumberGenerator) -> SpecialDef`
  (roulette pick over `.weight`; `null` on an empty array — P2c is the
  actual consumer, kept here since it's the resource's own concern).
- `config/specials/SpecialTuning.gd` + `.tres` — `max_chain_depth` 4,
  `throw_max_speed` 25.0, `throw_drag_min_distance_m` 0.15,
  `throw_drag_min_speed_mps` 1.0, `throw_speed_per_meter` 12.0.
  *(Deviates from the old plan: `max_explosion_impulse` etc. are not
  pre-declared — nothing in P2 reads them; P3/P4 add what they need later.)*
- `game/specials/SpecialEffect.gd` — base `Resource`, old plan's signatures
  (`physics_tick`, `wants_early_trigger`, `detonate`).
- `game/specials/SpecialBehavior.gd` — `Node`. `bind(block: Block, def:
  SpecialDef, tuning: SpecialTuning) -> void` is the entry point (avoids an
  `@export`-then-`add_child()` ordering race). Ages from bind; arms at
  `age >= def.arm_delay`; each armed tick runs `def.effect.physics_tick()`
  then `wants_early_trigger()`; force-triggers at `arm_delay +
  fuse_timeout_s` regardless. `trigger(incoming_chain_depth)` idempotent,
  calls `def.effect.detonate(...)`, emits new signal
  `Events.special_triggered(net_id, def.id, position, resulting_depth)`
  (appended to `autoload/Events.gd` by this package — P2c only reads it).
  `trigger_others_in_range(center, radius, chain_depth)` scans
  `get_tree().get_nodes_in_group(GROUP)` through a private pure
  `_filter_in_range(candidates, center, radius, chain_depth) ->
  Array[SpecialBehavior]` the unit test calls directly with a manufactured
  array. Past `chain_depth >= tuning.max_chain_depth`, `trigger()` still
  detonates but `trigger_others_in_range()` is a no-op (chain stops
  extending; the hit special is always visible).
- `tests/unit/test_special_def.gd`, `tests/unit/test_special_behavior.gd`.

**Reads only:** `game/Block.gd` (public RigidBody3D fields, no edits).
**Depends on:** nothing new. **Runs in parallel with P2b** (disjoint files).

**Acceptance:**
`powershell -NoProfile -File tools/run_gut.ps1 test_special_def,test_special_behavior`;
`godot --headless --editor --path . --quit` clean.
**Review:** not literally `core/`/`net/`/`autoload/`/physics/rules, but this
is the shared foundation for P3-P5 and implements rule-bearing chain logic —
**recommend review** (run `tools/route_model.py`, record its verdict,
override only with a stated reason).
**Worker:** stackfall-implementer. **Jev brief:** "Special interfaces +
arm/trigger/chain-cap logic (M4 P2a)" — kind `feature`.

### P2b — Pending-special FIFO queue + HUD indicator (Bontago-59u/csc)

**Outcome:** claiming a crate queues a token capped at `GiftConfig.
max_pending_specials`; the HUD shows how many a slot has queued. No file
overlap with P2a.

**Owned:**
- `autoload/match/MatchGifts.gd` — `_held_specials: Array[StringName]`
  becomes `_pending_queues: Array[Array[StringName]]` (per-slot FIFO, same
  `_ensure_capacity()` lazy growth). `held_special(slot_id)` becomes a
  **peek** at `queue[0]` (unchanged return contract). New
  `pop_pending_special(slot_id) -> StringName` dequeues (P2c's only
  mutator). `_claim_gift()` pushes only if `queue.size() <
  _gift_config.max_pending_specials` (decision 5); `Events.gift_claimed`'s
  2-arg shape unchanged. Remove the unconditional `_clear_held_special()`
  call in `on_feed_block_issued()` (`autoload/match/MatchGifts.gd:110`) —
  the queue now advances only by an explicit pop. Update the stale "latest
  wins" doc comments at lines 71-79 and 221-225. `apply_replicated_claim()`/
  `reset()` updated for the new shape (same cap check, client mirror).
- `config/GiftConfig.gd` + `.tres` — append `max_pending_specials: int = 3`.
- `autoload/Match.gd` — append `pop_pending_special(slot_id) -> StringName`,
  `pending_special_count(slot_id) -> int` (one-line forwards each).
- `ui/HUD.gd` — small queued-count indicator near the existing next-shape
  preview (`ui/HUD.gd:77-113`), reading `Match.pending_special_count
  (_acting_slot)`.
- `tests/unit/test_gift_claim.gd` — rewrite `test_second_claim_replaces_
  the_pending_special` (lines 115-124) into a queue-cap test: three claims
  with `max_pending_specials = 2` leave exactly 2 queued, the third still
  fires `gift_claimed` and adds nothing.
- `tests/unit/test_hud.gd` — one test for the indicator tracking
  `Match.pending_special_count()`.

**Reads only:** nothing from P2a (decision 1 — never loads `SpecialDef`).
**Depends on:** nothing new. **Runs in parallel with P2a.**

**Acceptance:** `powershell -NoProfile -File tools/run_gut.ps1 test_gift_claim,test_hud`;
no ENet harness needed (no `net/` file touched); `godot --headless --editor
--path . --quit` clean.
**Review:** yes (`autoload/` — `MatchGifts.gd`, `Match.gd`).
**Worker:** stackfall-implementer (mechanical queue rework + a HUD row).
**Jev brief:** "Pending-special FIFO queue + HUD indicator (M4 P2b,
Bontago-59u/csc)" — kind `feature`.

### P2c — Throw request + spawn-time special attachment (Match/MatchNet)

**Outcome:** `request_throw()` works end to end (host inline, client RPC); a
spawned `Block` — placed or thrown — gets a real `SpecialBehavior` exactly
when its slot had a pending token; `Events.special_triggered` replicates.
**Depends on P2a and P2b both committed.**

**Owned:**
- `core/rules/ThrowRules.gd` (new): `REASON_OK`/`REASON_NOT_A_SPECIAL`/
  `REASON_OUTSIDE_TERRITORY`, `validate_release_point(point, raster,
  team_id) -> PlacementRules.Result` (delegates to `PlacementRules.
  validate_point`, decision 2), `reason_for(result) -> StringName`
  (collapses every non-VALID result to `REASON_OUTSIDE_TERRITORY`, matching
  spec 2.5's single "outside your own territory" wording).
- `autoload/match/MatchPlacement.gd` (append):
  `request_throw(slot_id, origin, orientation_index, free_quat, velocity,
  feed_seq: int = -1) -> StringName` mirrors `request_place()`
  (`autoload/match/MatchPlacement.gd:93-230`) check-for-check (host-only,
  state/slot/feed_seq/home-flag/hot-seat-turn/`is_release_locked` guards
  identical); refuses `REASON_NOT_A_SPECIAL` if `_match.held_special
  (slot_id) == &""`; raycasts down from `origin` exactly like
  `request_place`, refuses `REASON_OUTSIDE_TERRITORY` via `ThrowRules`;
  clamps (never refuses) `velocity.limit_length(SpecialTuning.
  throw_max_speed)`; calls the shared `_spawn_block()` then sets
  `spawned.linear_velocity`; consumes via the same `_consume_and_refeed()`/
  `advance_turn()` tail as `request_place`. `_spawn_block()` extension
  (`autoload/match/MatchPlacement.gd:312-325`, block-build itself
  unchanged): after building, `var special_id := _match.pop_pending_
  special(slot_id)`; if non-empty, weighted-draw via `SpecialDef.
  pick_weighted()` over `SpecialDef.load_all_specials()` filtered to
  `config.enabled_specials.is_empty() or config.enabled_specials.has(def.id)`,
  using a small own RNG seeded `config.rng_seed + <distinct odd offset>`
  (mirrors `MatchGifts._ensure_rng()`'s convention); attach via
  `SpecialBehavior.new()` + `add_child()` + `bind(block, def,
  special_tuning)`. An empty roster (P3/P4/P5 not landed) means no draw, no
  behavior — block spawns exactly as ordinary (safe default).
- `autoload/Match.gd` — append one forward: `request_throw(...)`.
- `net/MatchNet.gd` — append `submit_throw(...)` (mirrors `submit_place`,
  `net/MatchNet.gd:217-251`, one extra `Vector3`), `net_request_throw`
  `@rpc` + `_handle_throw_intent()` (mirrors `net_request_place`/
  `_handle_place_intent`, `net/MatchNet.gd:540-584`, `velocity.is_finite()`
  added to the pose check), `EVENT_SPECIAL_TRIGGERED` + `_on_special_
  triggered()` → `replicate_match_event` (mirrors `_on_gift_spawned`,
  `net/MatchNet.gd:817-819`) + the `net_match_event` dispatch arm that
  re-emits `Events.special_triggered` on a client (mirrors
  `EVENT_GIFT_SPAWNED`, `net/MatchNet.gd:1048-1054`).
- `tests/unit/test_throw_rules.gd`, `tests/unit/test_match_throw.gd` (same
  fixture style as `tests/unit/test_gift_claim.gd`).

**Reads only:** `core/rules/PlacementRules.gd`, `game/BlockFactory.gd`,
`config/NetConfig.gd`, P2a's types, P2b's `pop_pending_special`.
**Must NOT touch:** `net/SnapshotSync.gd`, `game/BlockRegistry.gd`'s net_id
allocation, `net_block_spawned`'s wire shape (decision 4).

**Acceptance:**
`powershell -NoProfile -File tools/run_gut.ps1 test_throw_rules,test_match_throw,test_special_def,test_special_behavior`;
ENet: `./tools/run_m3a_local.ps1 -Peers 4` (placement traffic regression)
plus a scripted claim/place-special/throw pass across two peers;
`godot --headless --editor --path . --quit` clean.
**Review:** yes (`core/rules/`, `autoload/`, `net/`).
**Worker:** stackfall-netcode (the "Match/MatchNet/rules half").
**Jev brief:** "Throw request + spawn-time special attachment (M4 P2c)" —
kind `feature`.

### P2d — Throw input: LMB aim/drag/release state machine

**Outcome:** holding LMB on a held special and dragging past threshold aims
and throws on release with drag-scaled velocity; a negligible-drag release
places normally; an ordinary (non-special) block is unaffected. **Depends
on P2c and on Bontago-mv0.28 landing.**

**Owned:**
- `tools/bootstrap_project.gd` — `a["throw_aim"]`
  (`tools/bootstrap_project.gd:234`) changes from `[_mouse(MOUSE_BUTTON_
  RIGHT), _axis(...)]` to `[_mouse(MOUSE_BUTTON_LEFT), _axis(...)]`; update
  the stale RMB-overlap comment at lines 247-258. Re-run `godot --headless
  --path . -s tools/bootstrap_project.gd` and commit the regenerated
  `project.godot` `[input]` section.
- `game/PlayerController.gd` (append): on `ghost_place`/`throw_aim` press
  (same LMB event fires both actions) — gate on `_match.held_special
  (_acting_slot()) != &""` — start accumulating world-space drag from mouse
  motion (mirrors the existing drag branch at `game/PlayerController.gd:
  259-262`) or, on gamepad, `camera_look_*` axis strengths while `throw_aim`
  (LT) is held. **Do not place on press while holding a special** — decide
  on release: drag distance `< throw_drag_min_distance_m` or speed `<
  throw_drag_min_speed_mps` → ordinary `_request_place(false)` unchanged;
  otherwise velocity `= direction * min(distance * throw_speed_per_meter,
  throw_max_speed)` → new `_request_throw()` (mirrors `_request_place()`,
  `game/PlayerController.gd:431-447`, via `submit_throw`). Holding an
  ordinary block is unaffected — `ghost_place` still places on press.
  Append two read-only getters P2e needs: `is_aiming_throw() -> bool`,
  `current_throw_drag() -> Vector3`.
- `tests/unit/test_playercontroller_throw.gd` (new, fixture family of
  `test_playercontroller_mouse.gd`/`test_playercontroller_gamepad.gd`):
  synthetic drag sequences prove a tiny drag still places, a real drag
  throws with the expected clamped velocity, and an ordinary block is
  unaffected by the rebound LMB action.

**Reads only:** `config/specials/SpecialTuning.gd` (thresholds), `game/
GhostPreview.gd` (position/orientation, read only).

**Acceptance:**
`powershell -NoProfile -File tools/run_gut.ps1 test_playercontroller_throw,test_playercontroller_mouse,test_playercontroller_gamepad,test_project_setup`;
`godot --headless --editor --path . --quit` clean; manual step below.
**Review:** no (not `core/`/`net/`/`autoload/`/physics/rules; calls only
already-reviewed P2c entry points).
**Worker:** stackfall-implementer. **Jev brief:** "Throw-aim LMB drag/
release input (M4 P2d, Bontago-mvl)" — kind `feature`.

### P2e — Arc preview visual + camera gate + ghost hint

**Outcome:** while aiming, a ballistic arc is visible along the drag; the
gamepad's right-stick camera orbit is suppressed while `throw_aim` (LT) is
held. Pure presentation. **Depends on P2d (reads its aiming state) and on
Bontago-mv0.28 landing.**

**Owned:**
- `game/ThrowArcPreview.gd` + `.tscn` (new) — draws `position(t) = origin +
  velocity·t + 0.5·gravity·t²`, `gravity = Vector3.DOWN * ProjectSettings.
  get_setting("physics/3d/default_gravity") * physics_tuning.
  gravity_multiplier` (matches `game/BlockFactory.gd:75`); hidden unless
  `PlayerController.is_aiming_throw()` is true.
- `game/GhostPreview.gd` (append): `show_throw_hint(active: bool) -> void`
  tints via new `GhostTuning.throw_aim_tint_color`, reusing
  `_refresh_materials()`'s existing dispatch (`game/GhostPreview.gd:
  458-461`).
- `game/CameraRig.gd` (one-line append): extend the gamepad look gate in
  `_process()` (`game/CameraRig.gd:145-150`, currently unconditional) to
  skip the right-stick orbit read while `Input.is_action_pressed
  (&"throw_aim")`. Mouse orbit (RMB) needs no change — no overlap with the
  LMB throw gesture after P2d's rebind.
- `config/GhostTuning.gd` + `.tres` — append `throw_aim_tint_color: Color`.
- `config/tuning_panel_hints.tres` — one `descriptions` entry for it
  (GhostTuning is F4-visible; `test_tuning_panel.gd` fails without it).
- `game/HotSeat.tscn`, `game/Sandbox.tscn` — instance `ThrowArcPreview.tscn`
  as a sibling of the existing `GhostPreview` instance
  (`game/HotSeat.tscn:12`); add `@export var arc_preview_path: NodePath` on
  `PlayerController` (same pattern as `ghost_path`/`camera_rig_path`,
  `game/PlayerController.gd:35-36`).

**Reads only:** `game/PlayerController.gd`'s P2d-added getters (no edit
needed here).

**Acceptance:** no new automated test (view-only over P2d's already-tested
state); manual windowed check is the real acceptance criterion (CLAUDE.md:
frame-rate/visual acceptance is not provable headless). `godot --headless
--editor --path . --quit` clean (scenes open, compiles).
**Review:** no (presentation-only).
**Worker:** stackfall-implementer. **Jev brief:** "Throw arc preview +
camera/ghost hint (M4 P2e)" — kind `feature`.

## Dependency graph / dispatch order

```
P2a ─┐
     ├─> P2c ─> P2d ─> P2e
P2b ─┘
```

- **P2a and P2b run in parallel** (two writers, fully disjoint files).
- **P2c** starts once both P2a and P2b are committed.
- **P2d** starts once P2c is committed **and** Bontago-mv0.28 has landed.
- **P2e** starts once P2d is committed; same Bontago-mv0.28 gate.
- No package here needs P0 (tilt) committed; P5 remains the sole join point
  between Track A and Track B, unchanged from the old plan.
- `autoload/Events.gd`: only P2a appends (`special_triggered`) — single
  owner. `net/MatchNet.gd`: only P2c appends — single owner. (The P1×P2
  shared-file risk the old plan flagged is avoided here by keeping the
  gift-claim wire shape unchanged — decision 1.)

## New tunables (no magic numbers)

| Resource | Owner | Fields | F4-visible? |
|---|---|---|---|
| `config/special_tuning.tres` (`SpecialTuning`) | P2a | `max_chain_depth` 4, `throw_max_speed` 25.0, `throw_drag_min_distance_m` 0.15, `throw_drag_min_speed_mps` 1.0, `throw_speed_per_meter` 12.0 | No — not one of the six panel resources, no hints entry needed |
| `config/gift_config.tres` (`GiftConfig`) | P2b | append `max_pending_specials` 3 | No |
| `config/ghost_tuning.tres` (`GhostTuning`) | P2e | append `throw_aim_tint_color` | **Yes** — P2e adds the `tuning_panel_hints.tres` description itself |

## Open questions

None rise to genuine rule/game-feel ambiguity. Every judgment call above
(decisions 1-5) is an implementation detail with no [ORIGINAL]-tagged rule
or player-visible gameplay-outcome change, resolved in place per CLAUDE.md;
implementing workers restate each as a `# DECISION` comment at the cited
spot.

## Known limitations (carried forward or newly introduced)

- **A remote client's in-flight special (thrown or placed by another
  player) shows no tint and runs no arm/trigger visuals locally** (decision
  4). Host simulation/outcomes unaffected; revisit by extending
  `net_block_spawned`'s wire shape if the owner wants remote visual parity.
- **Special type is decided at spawn, not at claim** (decision 1) — a
  player cannot see *which* special is queued, only that one is (P2b's HUD
  count). Revisit if the owner wants a visible/predictable type per slot.
- Carried from the milestone doc, unchanged: gift claiming still assumes
  free-for-all (`team_id == slot_id`); crates never move once spawned;
  `PHYSICAL_BALANCE` tilt stays unimplemented; Magnet/Freeze/Glue/Gravity
  Well are M8.

## Orchestrator amendments (2026-09-23, binding over the sections above)

1. **Decision 1 reversed: the special type is drawn at CLAIM time on the host, not at
   spawn.** Spec 2.6 awards "a special as the next piece"; the player (and later the
   ghost/HUD) must know what they hold while aiming. P2b's queue therefore stores the
   drawn `StringName` special id per entry, `Events.gift_claimed` becomes
   `(gift_id: int, slot_id: int, special_id: StringName)`, and `net/MatchNet.gd`
   replicates the third argument (wire check: non-empty, `length() <= 32`; P2c
   tightens it to roster membership once `SpecialDef.load_all_specials()` exists).
   To keep P2a ∥ P2b, `MatchGifts` draws through an injectable
   `set_special_drawer(drawer: Callable)`; the default drawer returns
   `PENDING_SPECIAL_ID`, and P2c installs the real weighted `SpecialDef` pick.
   P2b's ownership grows by `autoload/Events.gd` (that signature only) and the
   `gift_claimed` wire in `net/MatchNet.gd` (`_on_gift_claimed`, the dispatch case,
   the wire check); its acceptance adds the ENet harness test that already covers
   gift replication. `held_special(slot_id)` peeks the head id.
2. **P2a does not touch `autoload/Events.gd`.** `SpecialBehavior` emits its own
   `signal triggered(def_id: StringName, position: Vector3, chain_depth: int)`;
   P2c appends `Events.special_triggered` and forwards/replicates it.
3. **Decision 5 reversed: a claim while the slot's queue is full does NOT consume
   the crate.** The crate stays for other players and still expires by
   `GiftConfig.life_s`, so nothing sits forever. `gift_claimed` does not fire.
4. Beads: P2a = Bontago-1en.12, P2b = Bontago-csc, P2c = Bontago-1en.13,
   P2d = Bontago-1en.14, P2e = Bontago-1en.15.
