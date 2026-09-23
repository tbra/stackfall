# M4 P3–P5 re-cut — Rocket/Bomb, Volcano, Earthquake/Anvil/Propeller/Jumping Bean

Re-cuts `docs/M4_PLAN.md`'s P3/P4/P5 against `docs/SPEC.md` §2.6/2.7/3.5/3.6 as
written today and the P2 interfaces actually landed on `main`@`d5a0ab3`. Supersedes
those three sections; P0–P2 and "Known limitations"/model-routing are unchanged.
Epic: Bontago-1en.

**Landed base:** `SpecialDef.gd`; `SpecialTuning.gd`+`special_tuning.tres`
(`max_chain_depth=4`, `throw_*`); `SpecialEffect.gd` (`physics_tick`/
`wants_early_trigger`/`detonate`, no-op default); `SpecialBehavior.gd` (ages,
arms at `arm_delay`, impact-detects via velocity drop >= `arm_impulse`,
`trigger()`/`trigger_others_in_range()`/chain cap, public `age()`/`is_armed()`/
`is_triggered()`/`chain_depth()` — **no `def()`/`tuning()` getter**);
`MatchPlacement.gd`'s `_attach_pending_special` (binds a behavior to any placed/
thrown special, host-only); `Field.gd`'s `apply_tilt_impulse()`/`tilt_vector()`/
`disk_local_from_world()` (public, read-only here); `Match.gd`'s `field()` getter
(the only way an effect — a `Resource` with no scene-tree handle — reaches `Field`).

## Why this supersedes the old plan

- **Seven types, not five/six**: `SpecialDef.gd`'s header names DaBomb/Bomb,
  Volcano, Earthquake, **Propeller**, Anvil, Rocket, **Jumping Bean**. Old P5
  ("Earthquake, Anvil, Fan") predates spec's tutorial-evidence rewrite — Fan is
  gone (Propeller replaces it, self-lift+tilt not a wind field), Jumping Bean was
  missing entirely.
- **Rocket has no homing** (§2.6) — drop the target-lock query and `team_of()`.
- **Bomb has no proximity trigger** — an ordinary impact/fuse special; landed
  `_check_impact()` already covers activation, `BombEffect` only needs `detonate()`.
- **No team filter on explosions** — see Open question 1.
- **`physics_tick()` never runs again after `trigger()`** (`advance()`'s first line
  is `if _has_triggered or ...: return`), so the old "`detonate()` starts an
  N-second window driven by further `physics_tick()` calls" design (Volcano/
  Earthquake/Fan) cannot work. This re-cut runs each timed effect
  (eruption/shake/lift) **during `physics_tick()`, before triggering** (see the
  pattern below), returning `wants_early_trigger()==true` only once that effect's
  own duration has elapsed; `detonate()` becomes a no-op for every P5 special.
- **No `SpecialBehavior.def()`/`.tuning()` getter needed** — `physics_tick()`'s
  first call is always the arming tick, so "seconds since armed" lives in
  `block.set_meta()/get_meta()`, and `SpecialTuning` is reached the way `Field.gd`
  reaches `PhysicsTuning`: `@export var tuning: SpecialTuning =
  preload("res://config/special_tuning.tres")`. No package below touches
  `SpecialBehavior.gd`/`SpecialEffect.gd`.

## The timed-effect pattern (Volcano, Earthquake, Propeller, Jumping Bean)

```gdscript
func physics_tick(block: Block, behavior: SpecialBehavior, delta: float) -> void:
    if not block.has_meta(&"<key>_start_age"):
        block.set_meta(&"<key>_start_age", behavior.age())
    var elapsed: float = behavior.age() - float(block.get_meta(&"<key>_start_age"))
    # ... this tick's slice of the effect, driven by elapsed, not tick count ...
func wants_early_trigger(block: Block, behavior: SpecialBehavior) -> bool:
    if not block.has_meta(&"<key>_start_age"): return false
    return behavior.age() - float(block.get_meta(&"<key>_start_age")) >= duration_s
```
`<key>` unique per effect type. Driven by simulation time, so results are
frame-rate independent — testable by calling `advance()` N times at a fixed
`delta`, as `test_special_behavior.gd` already does.

---

## Shared-prerequisite packages

### P3-SH — Explosion impulse query helper
**Depends on:** P2 (landed). **Blocks:** Rocket, Bomb, Volcano.
**Owns:** `game/specials/SpecialPhysics.gd` (new), `config/specials/SpecialTuning.gd`
(append one `@export`), `config/special_tuning.tres` (append value),
`tests/unit/test_special_physics.gd` (new). **Reads only:** `game/Block.gd`. **Must
NOT** touch `SpecialBehavior.gd`/`SpecialEffect.gd` — nothing here needs them.

`SpecialTuning.gd` append: `@export var max_explosion_impulse: float = 30.0`
(spec 3.5 names the clamp, gives no number).

```gdscript
class_name SpecialPhysics
extends RefCounted
static func explode(space_state: PhysicsDirectSpaceState3D, center: Vector3,
    radius: float, impulse: float, max_impulse: float,
    exclude: Array[RID] = []) -> Array[RigidBody3D]
```
Spec 3.5's recipe: sphere-query real `RigidBody3D` bodies in range (skip disk/
kill-plane hits and `exclude`'s RIDs), wake each, `apply_impulse` outward from
`center` with `magnitude = clampf(impulse * pow(1.0 - d/radius, 2.0), 0.0,
max_impulse)`. Returns the bodies actually hit.

**Acceptance:** `test_special_physics.gd` (real bodies in the test tree, a physics
smoke test) proves falloff-by-distance, nothing beyond `radius`, clamp caps a huge
impulse; `tools/run_gut.ps1 test_special_physics` passes. **Review:** yes (new
physics primitive, 3 consumers). **Jev:** "Small physics helper — kind=feature."

### P4-SPAWN — Special projectile spawn API
**Depends on:** P2. **Blocks:** Volcano only. **Owns:**
`autoload/match/MatchPlacement.gd` (append one public method), `autoload/Match.gd`
(append one-line forward), `tests/unit/test_match_special_spawn.gd` (new). **Reads
only:** `game/BlockFactory.gd`, `game/Block.gd`, `SpecialDef.gd`. **Conflict:**
P5-HOLE also appends one line to `Match.gd` — **never run P4-SPAWN and P5-HOLE as
parallel writers in the same checkout**; serialize either order, second package
rebases its one-line forward onto the first's commit.

```gdscript
func spawn_special_projectile(shape: BlockShape, world_origin: Vector3, basis: Basis,
    owner_slot: int, initial_velocity: Vector3, orb_def: SpecialDef,
    orb_tuning: SpecialTuning) -> Block
```
Host-only (null off-host, `request_place()`'s own guard); not a player intent, so
no feed consumed and no `PlacementRules`/`ThrowRules` check. Follows
`_spawn_block()`'s exact pipeline (`BlockFactory.build` -> `_blocks_parent.add_child`
-> `Events.block_placed.emit` [allocates `net_id`] -> `replicate_spawn`), binds+arms
a `SpecialBehavior` from `orb_def`/`orb_tuning` exactly as
`_attach_pending_special()` does, sets `linear_velocity` + `continuous_cd` (spec
3.5: >15 m/s -> CCD). `Match.gd` append: one-line forward, same pattern as
`request_place`.

**Acceptance:** `test_match_special_spawn.gd` proves off-host returns null/spawns
nothing, on-host result has a valid `net_id`, a bound `SpecialBehavior`, and
matching `linear_velocity`; `tools/run_gut.ps1
test_match_special_spawn,test_match_throw` passes. **Review:** yes (`autoload/`).
**Jev:** "Two small appends mirroring an existing method — kind=feature."

### P5-HOLE — Local hole-punch API (Jumping Bean prerequisite)
**Depends on:** P2, P0b (landed). **Blocks:** Jumping Bean only. **Owns:**
`core/territory/TerritoryRaster.gd` (append one method),
`autoload/match/MatchTerritory.gd` (append one method), `autoload/Match.gd` (append
one-line forward — see P4-SPAWN's conflict note), `tests/unit/test_territory_raster.gd`
(append), the existing host-side `MatchTerritory` test file (append; confirm exact
name at dispatch). **Reads only:** `config/MatchConfig.gd` (`HoleMode`),
`core/territory/CellGrid.gd`. **Must NOT** touch `update()`/`_fill_legacy()`/
`_argmax()` — only a new entry point reusing the existing `_hole`/`_opened`/
`_closed`/`_contested_time`/`_idle_time` bookkeeping so the existing close-delay
decay in `_advance_timers()` closes a punched hole on its own.

```gdscript
# TerritoryRaster.gd
func force_hole_cell(cx: int, cy: int, hole_open_s: float, permanent_holes: bool) -> void
# MatchTerritory.gd
func punch_special_hole(world_pos: Vector2, radius_m: float, hole_open_s: float) -> void
```
`force_hole_cell()` forces `(cx, cy)` into a hole now, independent of contest
overlap (spec 2.6), seeding `_contested_time`/`_idle_time` so `_advance_timers()`'s
own close-delay decay reopens it `hole_open_s` later (`permanent_holes=true` means
never, matching `HoleMode.PERMANENT`); appends to `_opened` like a natural cell.
`punch_special_hole()` is host-only, a no-op under `HoleMode.OFF` (owner decision
Bontago-z4h, enforced here not trusted to callers), else force-opens every in-disk
cell within `radius_m` of `world_pos`, emits `Events.hole_cells_changed`, then runs
the same `_check_home_flags(opened)` the natural path runs. `Match.gd` append:
one-line forward.

**Acceptance:** appended tests prove `force_hole_cell()` opens immediately and
closes via the existing `hole_close_delay` timer (never under
`permanent_holes=true`), and `punch_special_hole()` is a no-op under `HoleMode.OFF`
but opens the expected cells and eliminates a home flag sitting in one under
TEMPORARY/PERMANENT (reuse the existing `_check_home_flags` fixture);
`tools/run_gut.ps1 test_territory_raster,<match_territory_test>` passes.
**Review:** yes (`core/`+`autoload/`, home-flag-elimination interaction). **Jev:**
"Reuses an existing state machine — kind=feature, review=yes."

---

## Per-special packages

Unless noted, every package's worker is `stackfall-implementer (sonnet)` (matches
M4's own model-routing table); the orchestrator still runs `tools/route_model.py`
per package at dispatch.

### P3-ROCKET — Rocket
**Depends:** P3-SH. **Owns:** `config/specials/rocket.tres`,
`game/specials/RocketEffect.gd`, `tests/unit/test_rocket_effect.gd` (new).
**Reads:** `SpecialEffect.gd`, `SpecialBehavior.gd`, `SpecialPhysics.gd`, `Block.gd`.

`class_name RocketEffect extends SpecialEffect`; tunables `tuning`, `launch_speed`
(18.0), `fuel_duration_s` (1.5, NEW), `explosion_radius`/`explosion_impulse`
(3.0/14.0) — see the tunables table. `physics_tick()`: `block.continuous_cd = true`
and `block.linear_velocity = Vector3.UP * launch_speed` every tick — **# DECISION**:
trajectory is spec-OPEN; continuous thrust makes "fuel exhausted" literal rather
than an arbitrary timer, and does not fight `_check_impact()`'s decel read
(unchanged frame-to-frame absent a real collision). `wants_early_trigger()`: true
once elapsed-since-armed >= `fuel_duration_s` (impact can still trigger it early
via the base `_check_impact()`). `detonate()`: `SpecialPhysics.explode()` at
`explosion_radius`/`explosion_impulse`/`tuning.max_explosion_impulse` (own RID
excluded), then `behavior.trigger_others_in_range(position, explosion_radius,
chain_depth)`.

**Acceptance:** `test_rocket_effect.gd` (stub-`Block` logic tests + a physics
smoke: a nearby real body gains velocity, self untouched); `tools/run_gut.ps1
test_rocket_effect,test_special_physics` passes. **Review:** recommended, not
mandatory. **Jev:** "New effect, concrete spec numbers — kind=feature."

### P3-BOMB — Bomb / DaBomb
**Depends:** P3-SH. **Owns:** `config/specials/bomb.tres`,
`game/specials/BombEffect.gd`, `tests/unit/test_bomb_effect.gd` (new). **Reads:**
same as P3-ROCKET.

`class_name BombEffect extends SpecialEffect`; tunables `tuning`,
`explosion_radius`/`explosion_impulse` (3.5/18.0). No `physics_tick`/
`wants_early_trigger` override — activation is entirely the base impact/fuse
detection ("large explosion on activation," nothing type-specific about *when*).
`detonate()`: the same `SpecialPhysics.explode()` + `trigger_others_in_range()`
pattern as Rocket, Bomb's own numbers.

**Acceptance:** `test_bomb_effect.gd` (same physics-smoke shape as Rocket, plus
self-exclusion); `tools/run_gut.ps1 test_bomb_effect,test_special_physics`
passes. **Review:** not required (trivial, no logic beyond the reviewed helper).
**Jev:** "Smallest possible effect — kind=feature, review likely unnecessary."

### P4-VOLCANO — Volcano
**Depends:** P3-SH, P4-SPAWN. **Owns:** `config/specials/volcano.tres`,
`game/specials/VolcanoEffect.gd`, `VolcanoOrbEffect.gd`,
`tests/unit/test_volcano_effect.gd`, `tests/bench/bench_specials_chain.gd`+`.tscn`
(all new — the milestone's 5-volcano benchmark). **Reads:** `SpecialPhysics.gd`
(via `VolcanoOrbEffect`), `Match.spawn_special_projectile()`, `config/blocks/cube.tres`.

`class_name VolcanoEffect extends SpecialEffect`; tunables `tuning`,
`eruption_duration_s` (3.0), `min_orb_count`/`max_orb_count` (8/14), `orb_impulse`
(6.0), `cone_angle_deg` (35.0), `orb_explosion_radius` (1.5),
`orb_explosion_impulse_fraction` (0.5). `physics_tick()` (timed pattern): on first
call picks `orb_count` in range and caches it in block meta; each tick spawns
however many orbs are "due" by `elapsed / (eruption_duration_s / orb_count)`, so
exactly `orb_count` spawn over the window regardless of frame rate — each built via
`BlockFactory`'s shared `cube` shape, spawned through
`Match.spawn_special_projectile()` with a fresh `SpecialDef`+`VolcanoOrbEffect`
pair (`arm_delay=0`) and an initial velocity inside a `cone_angle_deg` cone around
local up, magnitude `orb_impulse`. `wants_early_trigger()`: true once
`elapsed >= eruption_duration_s`. `detonate()`: no-op (the eruption already ran).
**# DECISION**: orbs get their own tiny `VolcanoOrbEffect` (duplicating
`BombEffect`'s ~5-line shape) instead of depending on P3-BOMB, keeping Volcano
parallel-dispatchable. **# DECISION**: orb radius/impulse are Volcano's own new
tunables — spec 2.6 gives one number set for the whole special.

**Acceptance:** `test_volcano_effect.gd` proves `wants_early_trigger`
false-then-true at `eruption_duration_s` (frame-rate independent), exactly
`orb_count` orbs spawn (real `Match`+`MatchPlacement` fixture), each orb's
velocity is inside the cone, and `VolcanoOrbEffect.detonate()` respects the
chain-depth cap; `tools/run_gut.ps1 test_volcano_effect,test_match_special_spawn`
passes. **`bench_specials_chain.tscn`** (new): five volcanoes close enough that
orb blasts overlap, `bench_tower.gd`'s exact format, covers a full eruption from
each plus chain propagation to `max_chain_depth`, average
`Performance.TIME_PHYSICS_PROCESS`, fails past 16.6 ms/step — same headless-proxy
caveat `bench_rain.gd` documents; a windowed run on real hardware is the owner
manual step that verifies 60 fps. **Review:** recommended (spawns net-replicated
bodies at runtime). **Jev:** "New effect + bench scene — kind=feature, consider
split if the bench scene eats the budget."

### P5-EARTHQUAKE — Earthquake
**Depends:** none beyond landed P0/P2. **Owns:** `config/specials/earthquake.tres`,
`game/specials/EarthquakeEffect.gd`, `tests/unit/test_earthquake_effect.gd` (new).
**Reads:** `Match.gd`'s `field()`, `Field.gd`'s `apply_tilt_impulse()`/
`tilt_vector()` (read-only — do not edit `Field.gd`).

`class_name EarthquakeEffect extends SpecialEffect`; tunables `shake_duration_s`
(4.0), `shake_magnitude` (0.05), `leveling_strength` (0.5). `physics_tick()`
(timed pattern): each tick calls `field.apply_tilt_impulse(random_unit_vector,
shake_magnitude)` (the shake) and, if `field.tilt_vector()` is non-zero,
`apply_tilt_impulse(-tilt.normalized(), leveling_strength * tilt.length())` (spec:
"helps level existing tilt"), via `Match.field()`. `wants_early_trigger()`: true
once elapsed >= `shake_duration_s`. **# DECISION**: spec's "0.25 m / 2.5°" pair is
folded onto the single `shake_magnitude` tunable rather than a literal vertical
bounce — `Field.gd` has no such entry point (Open question 3).

**Acceptance:** `test_earthquake_effect.gd` (real tiny `Field.new()` via
`Match.register_world()`, `test_field_tilt.gd`'s fixture, reset in `after_each`)
proves `apply_tilt_impulse` fires each armed tick, leveling shrinks `tilt_vector()`
toward zero (`shake_magnitude=0` isolated), and impulses stop once triggered;
`tools/run_gut.ps1 test_earthquake_effect,test_field_tilt` passes; manual
windowed check (owner step below). **Review:** not required (effect-only, landed
`Field` API). **Jev:** "Effect-only against a landed public API — kind=feature."

### P5-ANVIL — Anvil
**Depends:** none beyond landed P0/P2. **Owns:** `config/specials/anvil.tres`,
`game/specials/AnvilEffect.gd`, `tests/unit/test_anvil_effect.gd` (new). **Reads:**
same as P5-EARTHQUAKE.

`class_name AnvilEffect extends SpecialEffect`; tunables `mass` (60.0),
`tilt_impulse_per_distance` (0.02). `physics_tick()`: sets `block.mass = mass`
once (idempotent). `wants_early_trigger()`: `block.sleeping` (settled — the
"lands, tilts" family, Godot's own Jolt sleep flag). `detonate()`:
`field.apply_tilt_impulse(disk_local_position.normalized(),
tilt_impulse_per_distance * distance_from_center)` — toward where it landed, via
`Match.field()`+`disk_local_from_world()`. **# DECISION**: mass override happens
on the first armed tick, not at spawn — no pre-arm hook exists, and a mid-fall
mass change doesn't affect trajectory (Godot gravity is mass-independent).
**# DECISION**: `tilt_impulse_per_distance` picked so a max-distance rim landing
alone reaches roughly half of `TiltTuning.max_tilt_deg` — spec's constant is OPEN.

**Acceptance:** `test_anvil_effect.gd` (mass override idempotent/post-arm only,
`wants_early_trigger` on `sleeping`, `detonate()`'s direction/magnitude, same
`Field` fixture as Earthquake); `tools/run_gut.ps1
test_anvil_effect,test_field_tilt` passes; manual windowed check (owner step
below). **Review:** not required. **Jev:** "Smallest tilt effect — kind=feature."

### P5-PROPELLER — Propeller (replaces Fan)
**Depends:** none beyond landed P0/P2. **Owns:** `config/specials/propeller.tres`,
`game/specials/PropellerEffect.gd`, `tests/unit/test_propeller_effect.gd` (new).
**Reads:** same as P5-EARTHQUAKE.

`class_name PropellerEffect extends SpecialEffect`; tunables `lift_speed` (4.0),
`lift_duration_s` (3.0), `tilt_strength` (0.3/s). `physics_tick()`: no-op until
`block.sleeping`; once settled, timed pattern — `block.linear_velocity.y =
lift_speed` every tick, plus `field.apply_tilt_impulse(-disk_local_position.
normalized(), tilt_strength * delta)` (away from itself — **# DECISION**, minor
ambiguity: no special in §2.6's table tilts toward itself except Anvil's landing
weight, a physically different case). `wants_early_trigger()`: true once
elapsed-since-settled >= `lift_duration_s`.

**Acceptance:** `test_propeller_effect.gd` (inert while airborne; lift+tilt run
for exactly `lift_duration_s` once settled, frame-rate independent; tilt away
from its own position, same `Field` fixture); `tools/run_gut.ps1
test_propeller_effect,test_field_tilt` passes; manual windowed check (owner step
below). **Review:** not required. **Jev:** "Effect-only, settle-then-lift state
machine — kind=feature."

### P5-BEAN — Jumping Bean
**Depends:** P5-HOLE. **Owns:** `config/specials/jumping_bean.tres`,
`game/specials/JumpingBeanEffect.gd`, `tests/unit/test_jumping_bean_effect.gd`
(new). **Reads:** `Match.gd`'s `field()`/`punch_special_hole()` (P5-HOLE,
committed), `Field.gd`'s `disk_local_from_world()`.

`class_name JumpingBeanEffect extends SpecialEffect`; tunables `hop_interval_s`
(1.5), `hop_impulse` (6.0), `hop_horizontal_speed` (3.0), `hole_radius_m` (1.0),
`hole_open_s` (2.0), `lifetime_s` (12.0). `physics_tick()`: waits for the first
settle (like Anvil/Propeller), then every `hop_interval_s` calls
`Match.punch_special_hole(disk_local_position, hole_radius_m, hole_open_s)` **at
the position it is about to leave** (a hole "between hops," the spot left behind),
then kicks `linear_velocity` to a random horizontal direction — an impulse, never
a position teleport (would fight `SnapshotSync` interpolation).
`wants_early_trigger()`: true once elapsed-since-first-settle >= `lifetime_s`.
**# DECISION**: hop is an impulse, not a teleport; the hole opens at the pre-hop
position, not the (not-yet-known-clear) landing spot; a Jumping-Bean-punched hole
eliminates a home flag exactly like a natural one (Open question 2).

**Acceptance:** `test_jumping_bean_effect.gd` (inert until settled; hops exactly
every `hop_interval_s`, frame-rate independent; each hop punches once at the
pre-hop position under `HoleMode.TEMPORARY`, never under `OFF`; self-triggers at
`lifetime_s`); `tools/run_gut.ps1 test_jumping_bean_effect,test_territory_raster`
passes; manual windowed check (owner step below). **Review:** recommended — the
only P5 effect with a rules consequence beyond tilt. **Jev:** "New special,
previously missing from the roster — kind=feature, review=yes."

---

## Dispatch order and parallelism

Max two concurrent writers (project default). All packages below P2 are
independent except the dependency arrows below; disjoint files otherwise.

Dependency edges beyond landed P2/P0: P3-SH → Rocket, Bomb, Volcano; P4-SPAWN →
Volcano; P5-HOLE → Jumping Bean; Volcano needs both. Earthquake/Anvil/Propeller
need nothing new. Suggested waves (2 writers each, orchestrator sizes actual
concurrency and runs `tools/route_model.py` per package): (1) Earthquake+Anvil;
(2) Propeller+P3-SH; (3) P4-SPAWN then P5-HOLE — **not concurrent**, both touch
`autoload/Match.gd`; (4) Rocket+Bomb; (5) Volcano+Jumping Bean.

Integration runs the targeted suite per merged batch as usual; every package's
acceptance includes `godot --headless --editor --path . --quit` staying clean.

## Tunables introduced

| Resource | Fields (default) | Status |
|---|---|---|
| `SpecialTuning` | `max_explosion_impulse` (30.0) | NEW, spec 3.5 names it, no number |
| `RocketEffect` | `launch_speed` (18.0), `explosion_radius`/`_impulse` (3.0/14.0) | spec 2.6, provisional |
| | `fuel_duration_s` (1.5) | NEW, spec's fuel duration OPEN |
| `BombEffect` | `explosion_radius`/`_impulse` (3.5/18.0) | spec 2.6, provisional |
| `VolcanoEffect` | `eruption_duration_s` (3.0), `min`/`max_orb_count` (8/14), `orb_impulse`/`cone_angle_deg` (6.0/35.0) | spec 2.6 |
| | `orb_explosion_radius`/`_impulse_fraction` (1.5/0.5) | NEW, orb split of one spec number |
| `EarthquakeEffect` | `shake_duration_s` (4.0) | spec 2.6 |
| | `shake_magnitude`/`leveling_strength` (0.05/0.5) | NEW, amplitude->impulse-space + leveling strength OPEN |
| `AnvilEffect` | `mass` (60.0) | spec 2.6 |
| | `tilt_impulse_per_distance` (0.02) | NEW, spec's constant OPEN |
| `PropellerEffect` | `lift_speed`/`_duration_s`/`tilt_strength` (4.0/3.0/0.3) | NEW, all OPEN in spec |
| `JumpingBeanEffect` | `hop_interval_s`/`_impulse`/`_horizontal_speed` (1.5/6.0/3.0) | NEW, OPEN in spec |
| | `hole_radius_m`/`_open_s`, `lifetime_s` (1.0/2.0, 12.0) | NEW, OPEN in spec |

Every value is `.tres`-editable (or F4-panel-editable where wired), never a
compile-time constant; provisional numbers are starting values, not claims of
original fidelity, matching spec 2.6's own framing.

## Open questions for the owner

1. **Team-agnostic explosions.** Rocket/Bomb/Volcano-orb impulses hit every body
   in range regardless of team, including the thrower's own. Spec 1.7 lists "the
   anvil hurt everyone" as a *problem* with "more targeted specials" part of the
   fix, but spec 2.6 removes Rocket's homing (the old plan's only targeting
   mechanism) and no passage gives a concrete exclusion rule. **Recommendation:**
   team-agnostic for M4 (matches the evidenced effect directly, keeps the shared
   helper simple); "more targeted specials" already addressed by the landed
   throw-arc preview. Not blocking.
2. **Special-punched holes and home-flag elimination.** P5-HOLE's
   `punch_special_hole()` reuses the exact trigger a natural hole already fires,
   so a Jumping Bean hopping near an enemy's home flag can eliminate them —
   consistent with existing precedent ("a hole opening under a home flag is a
   physical event"), but a new way to lose a match a player cannot easily
   predict. **Recommendation:** keep it consistent (yes, it eliminates). Not
   blocking.
3. **Earthquake's vertical bounce.** Spec 2.6 pairs a linear amplitude (0.25 m)
   with an angular one (2.5°); this re-cut folds both onto one tilt-impulse
   tunable rather than a literal Y-offset bounce, since `Field.gd` exposes no
   such entry point and every P5 package here is read-only on it. A literal
   bounce would need its own small, reviewed `Field.gd` addition. Not blocking.

## Orchestrator decisions (2026-09-23, binding)

1. Open question 1: explosions are **team-agnostic** for M4 (spec 1.7's "the anvil hurt
   everyone" is original evidence; targeting is a remake option for later). Decided in place.
2. Open question 2 (a special-punched hole can eliminate a home like a natural hole) is a
   rules matter the spec leaves OPEN: filed as an owner `decision` issue; the consistent
   behaviour ships as the default meanwhile.
3. Open question 3: ship Earthquake without the literal vertical bounce; fold onto
   `shake_magnitude`. Decided in place.
4. The first `.tres` under `config/specials/` makes the roster non-empty, so the gift drawer
   starts drawing real ids and tests that assumed an empty roster must be updated. The first
   per-special package to land (P5-EARTHQUAKE) also owns those test adjustments
   (`tests/unit/test_gift_claim.gd`, `test_match_net.gd`, `test_match_throw.gd`,
   `test_special_def.gd`) — later packages must not need any.
