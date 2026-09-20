# M4 — Gifts & specials: parallel build plan

Spec: §1.3 [ORIGINAL] (gifts/specials, chains, throwing), §1.5, §1.7, §2.2, §2.4, §2.5
(throwing, arc preview), §2.6 (gifts & specials table), §2.7 (SPECIALS_ONLY tilt),
§3.2, §3.3, §3.4 (reliable channel: "special trigger events", `request_throw`), §3.5
(tilt physics, continuous CD), §3.6 (`SpecialDef`), §3.7, Part 4 M4. Base: `main` @
`93d7c39`, clean. Prerequisite bug: Bontago-ruw (single-cell hole). Epic: Bontago-1en.

Two independent tracks. **Track A (P0)** rebuilds the disk's collision so a lone hole
cell behaves correctly and adds the SPECIALS_ONLY tilt controller — it touches only
`game/Field.gd` and is the riskiest, most physics-sensitive package in the milestone.
**Track B** is a dependency chain — P1 (gifts) → P2 (special framework, throw, arc
preview — the interface-stub package) → {P3 rocket/bomb, P4 volcano, P5 disk-affecting
specials} — because P1 and P2 both extend `autoload/Match.gd`'s feed machinery and must
not edit it concurrently, and P3–P5 all consume P2's `SpecialDef`/`SpecialEffect`
contract, which does not exist yet anywhere in the tree (`config/specials/` and
`game/specials/` are both empty placeholder directories today — confirmed by listing
them). P5 additionally needs Track A's tilt API, so it is the one place the two tracks
join before final integration. Track A can run fully in parallel with P1 and P2, since
neither touches `game/Field.gd`.

**Acceptance (Part 4 M4):** every special works in single-player and over LAN; a
5-volcano chain stays ≥60 fps on the host (headless timing is a proxy for this — see
P4's acceptance note, the same caveat `tests/bench/bench_rain.gd` already carries).

## Questions for the owner

1. **Are gift crates and thrown/exploded specials true chaos-physics rigid bodies, or
   stationary pickups/props once they land?** Spec 2.6 says "Crates are physics
   bodies" and 1.3's chain-reaction flavor text says a special's effect "can knock
   blocks into other crates or specials and set them off" — blocks get knocked into
   crates, not the reverse, so the spec never actually requires a crate itself to go
   flying. Spec 1.6 also praises the original's "chaos: tilting boards, volcano chains,
   and towers collapsing" as core to the fun, which leans the other way. The plan
   below builds crates as **`Area3D` pickups that never move once spawned** (P1) — a
   host-authoritative claim/pop position, replicated once via
   `MatchNet.replicate_match_event` (spawn) and once more (claim or expiry), with zero
   ongoing position traffic — because it is far cheaper to implement and verify, and
   because nothing in §2.6's own claim rule ("when a crate is inside your territory, it
   pops") needs the crate to move. If you want crates that can be shoved around and
   knocked off the map by an explosion the same as a block, say so before P1 starts:
   it changes GiftCrate from an `Area3D` to a `RigidBody3D`/`Block`-adjacent body that
   needs `net_id` allocation and 30 Hz snapshot sync like a placed block, which is a
   materially bigger P1 (and every other package that reads "is a crate at this cell"
   would need to read a moving position instead of a fixed one).
2. **None of the six specials in scope this milestone are [ORIGINAL]-tagged rule
   changes** — §1.3's table names all six and §2.6 gives concrete numbers for each, so
   nothing here is a guess that needs your sign-off before it lands. Flagged only so
   you know I looked: the spec's own §3.6 `SpecialDef` sketch has a loose
   `params: Dictionary`; the plan instead gives each special's effect script typed
   `@export` fields (CLAUDE.md's "untyped declarations are compile errors" reads on a
   `Dictionary` field the same as anywhere else), which is a closer fit for the same
   intent, not a rule change. No answer needed unless you disagree with dropping
   `params: Dictionary` from the resource shape spec sketches.

No M4 work changes an [ORIGINAL]-tagged rule. §2.1's tilt (`tilt_mode = SPECIALS_ONLY`)
and §1.3's "smash to activate" are both [ORIGINAL] and this milestone builds them
exactly as specified, not around them.

## P0 — Disk surface (Bontago-ruw) + SPECIALS_ONLY tilt controller — **opus**
(the single highest-risk package: a Jolt collision-shape redesign under a benchmark
history of getting subtler versions of this exact tradeoff wrong — `config/MapDef.gd`'s
own `cell_overlap` DECISION records 0.1 m *collapsing the tower outright* where 0.2 m
worked, so a plausible-looking fix that isn't actually re-benchmarked is a real risk of
a silent regression across every future milestone's physics)

**Owns:** `game/Field.gd`, `tests/unit/test_field_cells.gd`, `tests/unit/test_field.gd`
(read the tower/tilt-adjacent assertions before touching), new
`config/TiltTuning.gd` + `config/tilt_tuning.tres`, new `tests/unit/test_field_tilt.gd`.
**Reads only:** `config/MapDef.gd`, `config/PhysicsTuning.gd`, `config/TerritoryTuning.gd`,
`core/territory/CellGrid.gd`, `core/territory/TerritoryRaster.gd`, `autoload/Events.gd`,
`tests/bench/bench_tower.gd`, `tests/bench/bench_rain.gd` (run these, do not edit them).

### P0a — the lone-hole fix

**Root cause, read from the code, not asserted:** `MapDef.cell_overlap = 0.2` exists for
two reasons that the current single-box-per-cell design conflates. (1) Jolt rounds every
convex shape's edges by `collision_margin_fraction` (0.08) of its extent, so a *plain*
1.0 m cell box is flat only across its middle ~0.84 m — narrower than a 0.98 m block's own
footprint, so even a block sitting dead-center on a solid cell straddles the box's own
rounded rim. Growing the box to 1.2 m clears this (flat middle ≈1.008 m). (2) Growing every
cell's box also makes it *physically overhang into its neighbours* by `cell_overlap / 2`
on every side, which is irrelevant for a multi-cell hole patch (interior cells have no
solid neighbour left to overhang) but leaves a lone hole cell only
`cell_size − cell_overlap` = 0.8 m of clear opening — narrower than the 1.0 m block that
is supposed to fall through it. `MapDef`'s own DECISION comment and `CellGrid`'s document
(1) in detail (measured: 0.0 m and 0.1 m of overlap both regress `bench_tower`, 0.2 m
restores the M1 single-cylinder numbers); the bug (Bontago-ruw) and
`test_field_cells.gd::test_a_block_over_a_lone_hole_cell_falls_through` (currently
`pending()`) document (2).

**Chosen approach — a rebuildable trimesh top surface (`ConcavePolygonShape3D`), one
per-disk shape instead of one `BoxShape3D` per cell.** Evaluated against the two other
options the assignment named:
- *Per-cell shapes without overlap plus a thin rim collider disabled around holes*
  (shrink each cell to a bare 1.0 m core plus small directional "flap" shapes bridging
  the margin gap into each solid neighbour, disabled whenever the neighbour they reach
  into is a hole). Rejected: it only fixes problem (2) above. A bare 1.0 m core box still
  has only an ~0.84 m flat middle from its own margin, so a block centered on ANY solid
  cell — not just one near a hole — would still catch on its own rim; the flaps would
  have to bridge every cell to every solid neighbour just to restore today's stability,
  which is 4–8 extra shape owners per cell (edges and corners), a much larger shape-owner
  count than today for a fix that is strictly local geometry surgery with real corner
  cases (a cell adjacent to two holes on perpendicular sides), and it still leaves
  `test_one_enabled_shape_owner_per_in_disk_cell`'s "exactly one shape owner per cell"
  invariant broken (now more than one), for no simplification in return.
- *Shrinking only the neighbours of a hole* is the same idea as the rim option above,
  described from the hole's side instead of the cell's; same rejection.
- **Trimesh (chosen).** Jolt does not apply the same proportional convex-radius rounding
  to a concave/mesh shape's *interior* edges the way it does to a standalone convex
  box's perimeter — a mesh's shared internal edges are exact, not rounded — which is
  exactly why the M1 single-cylinder disk (one shape, no per-cell seams at all) slept in
  half a second with 0.02 m of drift, the number `cell_overlap`'s own comment measures
  the *current* per-cell-box design against as the target it is trying to recover. A
  single continuous surface removes the seam problem at its root instead of covering it
  with growable boxes, and a hole becomes an exact, correctly-sized opening (whatever
  shape the raster says — one cell or a thousand-cell contested crater) by simply
  omitting that cell's two triangles from the mesh, with no overhang in any direction.
  It is also the fix the bug ticket itself already names as "the proper fix," and it
  removes `cell_overlap` as a load-bearing tuning knob entirely rather than trading one
  narrow case of it for another.

**Design, concretely.** Field keeps its entire *public* hole-state contract unchanged —
`cell_owner_id(index)`, `is_hole_cell(index)`, `pending_toggle_count()`,
`set_hole_cells(opened, closed)`, the `_hole_wanted`/`_hole_applied`/backlog bookkeeping —
because `core/territory/TerritoryRaster.gd`, `game/BlockRegistry.gd`'s
`bodies_over_cells()` and every existing test that calls these keep working against the
same *logical* per-cell hole state. What changes is what backs it physically:
`_build_cells()` builds one `ConcavePolygonShape3D` on one shape owner for the whole
disk (two triangles per non-hole in-disk cell, generated from `CellGrid.index_center()`
exactly as today's box centers are, so raycasts and the wake query need no changes) instead
of one `BoxShape3D` shape owner per cell. `set_hole_cells()` still enqueues into the same
backlog and `_drain_toggles()` still applies at most
`TerritoryTuning.max_cell_toggles_per_frame` per physics frame — but "applying" a toggle
now means flipping `_hole_applied[cell]` and marking the mesh dirty, not calling
`shape_owner_set_disabled`. The mesh itself is rebuilt **at most once per physics frame**
(only when at least one toggle was newly applied that frame, in `_drain_toggles()`'s own
call), by walking every in-disk cell and appending its quad's two triangles unless
`_hole_applied[cell] == 1`. This keeps the existing "batch to bound frame cost" intent —
a burst of 500 simultaneously-opening cells still costs one rebuild per frame, not 500
shape-owner toggles — but changes what the bound is protecting: previously it capped how
many individual Jolt shape updates happen; now it caps how often the whole-disk trimesh
rebuilds, which must be **measured**, not assumed cheap:
- Rebuild cost is `O(in_disk_cell_count)` regardless of how many cells actually changed
  (`ConcavePolygonShape3D.set_faces()` takes the whole face array; there is no partial
  update). On the largest map (`round_large.tres`, field_radius 60) that is ≈11 300
  cells, ≈22 600 triangles, rebuilt at most once per physics tick while any hole is
  actively opening or closing.
- **Required before this is considered done:** add a timing print to
  `_drain_toggles()`'s rebuild path behind the same kind of `--trace=` flag
  `bench_tower.gd` already uses, and run `bench_tower` (must still pass unchanged — it
  never opens a hole, so this only proves the *static* trimesh is as stable as the old
  boxes) **and** a new scripted scenario that opens and closes a moving strip of holes
  across a Large map every solve tick for 10 s while `bench_rain`-style timing is
  recorded, to get a real number for worst-case rebuild cost. If it is not comfortably
  inside a fraction of the physics frame budget, the fallback (not built now, flagged
  as a follow-up if triggered) is rebuilding only a local sub-mesh for the region that
  changed rather than the whole disk — do not silently accept a slow number and ship it.
- `test_one_enabled_shape_owner_per_in_disk_cell` (`tests/unit/test_field_cells.gd`)
  asserts today that `field.get_shape_owners().size() == expected` (one owner per
  in-disk cell) — this assertion's very premise is the box-per-cell architecture being
  replaced, so it **must be rewritten**, not silently left failing. Replace it with an
  assertion that `field.get_shape_owners().size() == 1` and that a physics query
  directly above every in-disk cell reports a hit exactly when `is_hole_cell()` is
  false for that cell (the thing the old test was really protecting). Every other test
  in the file (waking, falling through an opened cell, backlog batching, coordinate
  round-trips) is written against the logical API and should need no changes; run them
  first before touching anything to confirm that.
- Un-pend `test_a_block_over_a_lone_hole_cell_falls_through` once it passes for real.
- `AnimatableBody3D` (P0b, tilt) supports concave shapes; Jolt's restriction is on
  *dynamic* `RigidBody3D` only. Confirm this against the actual Jolt/Godot 4.7.2 docs
  before relying on it, since it is asserted here from documented behaviour, not
  re-verified against this exact build.
- `PhysicsMaterial` friction (`Field.tuning.disk_friction`) applies to the body
  regardless of shape type; no change needed there.

### P0b — SPECIALS_ONLY tilt controller (spec 2.1, 2.7, 3.5)

Scope check against the epic text: Bontago-1en says "`Field.disk_local_from_world`/
`world_from_disk_local` are the only functions that change" when tilt lands. Read
literally against spec 3.5 ("the disk is an `AnimatableBody3D` with `sync_to_physics =
true`... blocks resting on it are carried along correctly") that cannot be literally true
— carrying resting blocks along needs a real physical rotation, which needs Field to
become an `AnimatableBody3D` and gain a spring-damper update loop, which is new state and
a new `_physics_process` responsibility, not a change to an existing function. The
plan reads the epic's sentence as "the only *existing* functions whose contract changes"
(coordinate conversion still takes a world point and returns disk-local, just now through
the disk's live orientation) rather than "the only thing that changes in Field.gd" —
worth recording explicitly since it is the only place this plan's understanding of scope
diverges from a literal reading of the epic's own summary; not a pause-worthy conflict
(it touches no [ORIGINAL] rule and no player-facing behaviour beyond what §2.1/§2.7/§3.5
already specify), just a documented scope clarification.

**Work:** Field becomes an `AnimatableBody3D` (only when
`MatchConfig.tilt_mode == SPECIALS_ONLY`; `PHYSICAL_BALANCE` stays out of scope for M4,
per Part 4's build order — it is listed under M6). A `TiltTuning` resource
(`max_tilt_deg = 12.0`, `return_time_constant_s = 4.0`, plus a spring
stiffness/damping pair the implementer derives to hit that time constant critically
damped — `# DECISION`, record the derivation) drives a 2-axis tilt vector that eases back
toward level. `Field.apply_tilt_impulse(direction: Vector2, magnitude: float) -> void` is
the one new public entry point specials call (Anvil, Fan, Earthquake in P5) — `direction`
is a disk-local XZ unit vector, `magnitude` an impulse into the spring model, clamped so
`max_tilt_deg` cannot be exceeded by any single hit. `disk_local_from_world()` /
`world_from_disk_local()` change to go through the live tilt+position transform (already
just `to_local`/`to_global` on this `Node3D`, so once the body's own `global_transform`
reflects the tilt, these two functions need no code change at all beyond what
`Node3D.to_local`/`to_global` already do — confirming the epic's claim is *exactly* right
for these two, once the AnimatableBody3D conversion is in place).
Earthquake's shake (P5) rides the same tilt vector plus a small independent Y-offset
oscillation, both parameters (`earthquake_amplitude_m`, `earthquake_amplitude_deg`)
living on `TiltTuning` since they are disk-motion numbers, not per-special ones.

**Tests:** `test_field_tilt.gd` — `apply_tilt_impulse` moves the tilt vector and it decays
back toward level over `~return_time_constant_s`; tilt is clamped at `max_tilt_deg`
regardless of impulse magnitude or how many impulses land in one frame;
`disk_local_from_world`/`world_from_disk_local` round-trip correctly at a non-zero tilt
(a synthetic tilt set directly, not by waiting out the spring); a block resting on the
disk at a fixed disk-local point stays at that point (within a small numeric tolerance)
across several frames of a slow tilt change, proving `sync_to_physics` actually carries it.

**Acceptance:** `bench_tower` passes unchanged (no tilt applied during that scene, so
this proves the trimesh alone did not regress); the new hole-churn timing scenario above
records real numbers; `test_field_tilt.gd` passes; `godot --headless --editor --path .
--quit` stays clean.

## P1 — Gift crates, claiming, special feed integration — **sonnet**

**Owns:** `game/GiftCrate.gd` + `.tscn` (new, `Area3D`), `core/gifts/GiftSpawner.gd` (new,
pure logic — picks a random uncontested spawn point, computes the next spawn interval
from `special_frequency`), `config/GiftConfig.gd` + `config/gift_config.tres` (new),
`autoload/Match.gd` (append: `_tick_gifts(delta)`, `claim_or_expire_gifts()`, a new
`_held_specials: Array[StringName]` parallel array alongside `_held_shapes`, and the two
small read accessors `held_special(slot_id) -> StringName` /
`_clear_held_special(slot_id)` that P2 reads), `autoload/Events.gd` (append:
`gift_spawned(gift_id: int, position: Vector2)`, `gift_claimed(gift_id: int, slot_id:
int)`, `gift_expired(gift_id: int)`), `net/MatchNet.gd` (append: `EVENT_GIFT_SPAWNED`,
`EVENT_GIFT_CLAIMED`, `EVENT_GIFT_EXPIRED` constants and their `_on_gift_*` →
`replicate_match_event` wiring, following the exact pattern `_on_player_eliminated` /
`_on_match_won` already use), `tests/unit/test_gift_spawner.gd`,
`tests/unit/test_gift_claim.gd`.
**Reads only:** `core/territory/TerritoryRaster.gd`, `core/territory/CellGrid.gd`,
`config/MatchConfig.gd`, `config/TerritoryTuning.gd`, `game/Field.gd` (P0's committed
interface — read `disk_local_from_world`/`world_from_disk_local`, do not touch the file).

**Work.** `GiftSpawner.pick_spawn_point(raster, grid, rng, config) -> Vector2` samples up
to `GiftConfig.spawn_max_attempts` random in-disk points, accepting the first whose cell
is not contested and not a hole (spec 2.6: "at a random uncontested point"); returns
`PlacementRules.NO_ORIGIN`-style sentinel on total failure, and the caller just waits for
the next tick rather than treating that as an error. `GiftSpawner.next_interval(config,
special_frequency, rng) -> float` linearly interpolates `GiftConfig`'s two named points
(`special_frequency=20 → 45 s`, `special_frequency=100 → 6 s`, per spec 2.6's own worked
example) and applies `±interval_jitter_fraction` (0.40). `Match._tick_gifts(delta)` (host
only, gated the same way `_tick_feed`/`_tick_territory` already are behind
`Net.is_host()`) runs only when `config.gifts_enabled`, spawns a `GiftCrate` from
`_blocks_parent`'s sibling container when its timer elapses, and calls
`Events.gift_spawned` + `MatchNet`'s replication. `claim_or_expire_gifts()` runs once per
territory solve tick (hooked into the existing `_run_territory_step()`, right after the
raster updates, so it reads the freshest `team_at()`): for each live, unclaimed crate,
if `raster.team_at(cell) >= 0` (owned, uncontested — teammates never contest each other,
so this is unambiguous even inside one team's merged area), the crate is claimed by that
team id. **DECISION (autoload/Match.gd):** M4 ships with `MatchConfig.team_count() ==
player_count` (free-for-all only — `TeamMode` is still unwired per
`docs/M2_PLAN.md`'s own Known Limitations), so `team_id == slot_id` here and the claim
directly sets `_held_specials[team_id]`. This is a real simplification that will need
revisiting once M6 wires real teams (which specific teammate's next block becomes the
special is genuinely ambiguous then — nearest circle's `owner_slot`, round-robin, or
every teammate — not decided here, flagged as a known limitation below). A crate that
lives past `GiftConfig.life_s` (60 s, spec 2.6) without being claimed is freed and
`Events.gift_expired` fires instead.

`GiftCrate` itself: an `Area3D` with a simple collision shape for visual/gameplay
presence (a block or a thrown special can be seen to strike it, matching the chain-
reaction flavor text, even though nothing here currently *reacts* to that contact —
P3/P4/P5's specials do not need to know about crates at all this milestone, only about
each other, so `GiftCrate.body_entered` is wired to nothing yet and is a documented,
harmless no-op hook for a later milestone). A client never claims anything itself (owner
question 1's `Area3D` design means a client's crate is pure visual, matching how a
client already never solves territory) — it only ever reacts to the three replicated
events by instancing/freeing the visual.

**Tests first:** `GiftSpawner.pick_spawn_point` never returns a contested or hole cell
across many seeded draws, and returns the failure sentinel when the whole raster is
contested; `next_interval` hits the two named spec examples within the jitter band and
is monotonically decreasing in `special_frequency`; `claim_or_expire_gifts` claims a
crate the instant its cell becomes uncontested-and-owned and expires one whose age
exceeds `life_s`; `_tick_gifts` does nothing when `gifts_enabled` is false or on a
client. **Acceptance:** a scripted single-player match with `special_frequency = 100`
and a short `life_s` sees at least one crate spawn, get claimed, and hand the claiming
slot a special on its next `feed_block_issued` (asserted via `held_special()`).

## P2 — Special framework, throw intent, arc preview, arming/triggering, chain cap — **sonnet** (`stackfall-netcode` for the Match/MatchNet/rules half; the arc-preview visuals are ordinary presentation work any implementer can do in the same package to avoid a third serialized hop)

**This is the interface-stub package** — `config/specials/SpecialDef.gd` and
`game/specials/SpecialEffect.gd` do not exist anywhere in the tree yet (`config/specials/`
and `game/specials/` are both empty placeholder directories today), and P3/P4/P5 cannot
start until both are committed. **Must land before P3, P4 and P5 begin.**

**Owns:** `config/specials/SpecialDef.gd` (new), `config/specials/SpecialTuning.gd` +
`config/special_tuning.tres` (new), `game/specials/SpecialEffect.gd` (new, base
`Resource`), `game/specials/SpecialBehavior.gd` (new, the `Node` attached to a special's
`Block`), `core/rules/ThrowRules.gd` (new, mirrors `PlacementRules`' `Result`/`REASON_*`/
`reason_for()` shape for the one throw-specific check), `autoload/Match.gd` (append:
`request_throw(...)`, and the `_spawn_block()` extension that reads P1's
`held_special(slot_id)` and attaches `SpecialBehavior`), `net/MatchNet.gd` (append:
`submit_throw`, `net_request_throw` RPC mirroring `net_request_place`,
`EVENT_SPECIAL_TRIGGERED` + its `replicate_match_event` wiring), `game/PlayerController.gd`
(append: throw-aim input state machine), `game/GhostPreview.gd` (append: a
`show_throw_hint()`/tint variant, minimal — most of the new visual is the arc, not the
ghost), `game/ThrowArcPreview.gd` + `.tscn` (new), `game/CameraRig.gd` (one-line append:
gate the right-stick orbit read the same way `rotate_free_hold` already does, for
`throw_aim`), `tests/unit/test_special_def.gd`, `tests/unit/test_special_behavior.gd`
(chain-cap unit test — logic only, no physics), `tests/unit/test_throw_rules.gd`,
`tests/unit/test_match_throw.gd`.
**Reads only:** `core/rules/PlacementRules.gd`, `core/territory/TerritoryRaster.gd`,
`config/NetConfig.gd`, `game/BlockFactory.gd`, `game/Block.gd`, `game/BlockRegistry.gd`,
P1's committed `held_special()`/`Events.gift_*`.
**Must NOT:** touch `net/SnapshotSync.gd` or `game/BlockRegistry.gd`'s net_id allocation —
a special, once spawned as a `Block` (below), rides the existing 30 Hz snapshot pipeline
with zero changes there, which is the entire point of building it this way.

**Interfaces it exposes** (typed; consumed by P3/P4/P5):

```gdscript
# config/specials/SpecialDef.gd
class_name SpecialDef
extends Resource
@export var id: StringName
@export var scene: PackedScene = null       # optional custom visual override; null -> default cube mesh, tinted
@export var weight: float = 1.0             # gift-pool draw weight
@export var enabled_by_default: bool = true
@export var arm_delay: float = 0.4          # spec 2.6
@export var arm_impulse: float = 6.0        # spec 2.6 default; each special's own .tres overrides per its table row
@export var fuse_timeout_s: float = 8.0     # spec 2.6 prose ("no hit within 8 s triggers automatically");
                                             # not in spec 3.6's illustrative snippet -- # DECISION, filling a gap
                                             # the resource sketch left open, not a rule change
@export var effect: SpecialEffect = null    # the per-special script instance (spec 2.6's "plus a script")

# game/specials/SpecialEffect.gd — one concrete Resource subclass per special
# (RocketEffect.gd, BombEffect.gd, ...), each declaring its OWN typed @export
# tunables (speed, radius, impulse, ...) instead of spec 3.6's untyped
# `params: Dictionary` -- # DECISION, see "Questions for the owner" 2.
class_name SpecialEffect
extends Resource
func physics_tick(_block: Block, _behavior: SpecialBehavior, _delta: float) -> void:
    pass
func wants_early_trigger(_block: Block, _behavior: SpecialBehavior) -> bool:
    return false
func detonate(_block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
    pass

# game/specials/SpecialBehavior.gd
class_name SpecialBehavior
extends Node
@export var def: SpecialDef
@export var tuning: SpecialTuning
var armed: bool = false
var triggered: bool = false
var chain_depth: int = 0
func trigger(incoming_chain_depth: int) -> void            # idempotent; calls def.effect.detonate()
func trigger_others_in_range(center: Vector3, radius: float, chain_depth: int) -> void
```

**Arming/triggering (spec 2.6), concretely.** `SpecialBehavior._physics_process`: ages
from spawn; once `age >= def.arm_delay`, `armed = true` and `contact_monitor`/
`max_contacts_reported` turn on for the parent `Block` so an impact above `def.arm_impulse`
calls `trigger(0)` (a player-caused hit). Each frame after arming, `def.effect.physics_tick()`
runs first (Rocket's homing, Volcano's countdown, Fan's push, Earthquake's shake — Bomb
and Anvil are no-ops here), then `def.effect.wants_early_trigger()` is checked (Volcano:
true immediately once armed; Anvil/Fan/Earthquake: true once the block has settled —
reuses `PhysicsTuning.sleep_linear_threshold`/`sleep_angular_threshold`, not a new
number; Rocket/Bomb: false, they only trigger via impact or the fuse) — and independently
of both, `age >= def.arm_delay + def.fuse_timeout_s` always force-triggers (spec 2.6's
universal fallback). **`# DECISION` (game/specials/SpecialBehavior.gd):** a special that
would be the 5th link in a chain (`incoming_chain_depth >= SpecialTuning.max_chain_depth`)
still detonates — `trigger()` always calls `detonate()` — but `trigger_others_in_range()`
becomes a no-op past the cap, so the *chain stops extending* rather than the capped
special silently fizzling. Spec 2.6 only says the cap exists "to keep frame rate stable,"
not which side of the boundary it falls on; this reading keeps every individual special's
own effect always visible (no special that a player sees land ever silently does
nothing), which matches "gifts felt too random" being one of the things spec 1.7 lists
as needing a remake fix — a special that sometimes just doesn't go off would reintroduce
exactly that complaint at the chain boundary.

**Throwing (spec 2.5, 3.4).** `ThrowRules.validate(origin: Vector2, raster:
TerritoryRaster, team_id: int) -> Result` is the one new check: the release point must be
inside the thrower's own territory (`raster.team_at()`/`is_contested()` at that single
point — not a footprint, since a throw's landing spot is deliberately *not* pre-
validated; spec 2.5: "the release point has to be inside your own territory," 1.3:
"can be thrown outward, even beyond your own territory, to hit other players").
`Match.request_throw(slot_id, origin, orientation_index, free_quat, velocity, feed_seq:
int = -1) -> StringName` mirrors `request_place`'s shape and idempotency guard exactly
(same `feed_seq` replay defence), adds: refuse with a new `ThrowRules.REASON_NOT_A_SPECIAL`
unless `held_special(slot_id)` is non-empty (spec: "In normal games only specials can be
thrown" — sandbox mode, where ordinary blocks can be thrown too, is M6 scope and out of
this milestone); refuse `ThrowRules.REASON_OUTSIDE_TERRITORY` if the release point check
fails; otherwise clamp `velocity.length()` to `SpecialTuning.throw_max_speed` (25 m/s,
spec 2.5/3.4 — clamped, never refused, per §3.4's own wording: "the host clamps velocity
to `throw_max_speed`") and spawn exactly as `_spawn_block()` already does for a placement,
except the resulting `Block` gets `linear_velocity = clamped_velocity` and a
`SpecialBehavior` attached immediately (armed timer starts at release either way, thrown
or placed — spec 2.6 doesn't distinguish). `net/MatchNet.gd`'s `submit_throw`/
`net_request_throw` are `net_request_place`'s RPC pattern with one extra `Vector3`
argument; the host-side pose-sanity guard (`is_pose_well_formed`, already on `Match`) is
reused unchanged.

**Arc preview & input (spec 1.3, 2.5).** `throw_aim` **already exists** in the Input Map
(`tools/bootstrap_project.gd`: `a["throw_aim"] = [_mouse(MOUSE_BUTTON_RIGHT),
_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)]`, confirmed present and currently unread by any
script) — **no new Input Map action is needed**, and `tools/bootstrap_project.gd` is not
touched by this package. `PlayerController._unhandled_input` gains a branch mirroring
the existing `camera_orbit_hold` press/release pattern: on `throw_aim` press (only while
`held_special(_acting_slot()) != &""`), start accumulating a drag vector from mouse
motion (mirroring `rotate_free_hold`'s existing motion-delta read) or, on gamepad, from
`camera_look_*`'s axis strengths reinterpreted as aim input while `throw_aim` is held —
which needs `CameraRig._process`'s existing `if not
Input.is_action_pressed(&"rotate_free_hold")` gate extended to `and not
Input.is_action_pressed(&"throw_aim")`, the one line this package appends there, exactly
mirroring the precedent that gate already sets for `rotate_free_hold`. `ThrowArcPreview`
draws a simple ballistic curve (`position(t) = origin + velocity·t + ½·gravity·t²`,
`gravity` read from `PhysicsTuning.gravity_multiplier`-scaled project gravity) from the
ghost's current position along the accumulated drag, capped at `throw_max_speed`; on
`throw_aim` release, `PlayerController` calls `submit_throw`/`request_throw` with the
final velocity and clears the aim state. Releasing outside the player's own territory
still sends the intent (spec 2.5's edge-clarity requirement is a UI nicety, not a
client-side gate — the host is the one authority, exactly like placement's red-tint-but-
still-sendable pattern `GhostPreview.apply_validity` already establishes); the arc/ghost
tints red near the territory edge using the existing `ThrowRules.validate` dry-run,
mirroring `preview_placement`.

**Tests first:** `test_special_def.gd` — `SpecialDef` resources load with a non-null
`effect`; `test_special_behavior.gd` — arms exactly at `arm_delay`, an impulse below
`arm_impulse` before arming does not trigger, one at or above it after arming does;
`trigger()` is idempotent (a second call does nothing); `trigger_others_in_range` reaches
specials within radius and refuses once `chain_depth >= max_chain_depth` (pure logic,
manufactured `SpecialBehavior` instances, no physics); the fuse always fires by
`arm_delay + fuse_timeout_s` regardless of `wants_early_trigger`. `test_throw_rules.gd` —
`validate()` matches `PlacementRules`' territory logic at a single point. `test_match_throw.gd`
— `request_throw` refuses a non-special hold, refuses outside-territory release, clamps
an over-`throw_max_speed` velocity rather than refusing, and shares `request_place`'s
`feed_seq` idempotency guard (a doubled throw intent spawns one block, not two).
**Acceptance:** the four unit-test files above pass; `godot --headless --editor --path .
--quit` stays clean; a manual windowed check (owner steps below) that dragging the mouse
while holding a claimed special shows the arc and throws on release.

## P3 — Rocket + Bomb — **sonnet**

**Depends on P2 committed.** **Owns:** `config/specials/rocket.tres`,
`game/specials/RocketEffect.gd`, `config/specials/bomb.tres`, `game/specials/BombEffect.gd`,
`tests/unit/test_rocket_effect.gd`, `tests/unit/test_bomb_effect.gd`.
**Reads only:** `game/specials/SpecialEffect.gd`, `game/specials/SpecialBehavior.gd`
(P2's committed interface), `autoload/Match.gd` (`team_of()`, read-only), `game/Block.gd`.

**Rocket** (spec 2.6: speed 18, radius 3, impulse 14, 25 m homing range). `RocketEffect`
overrides `physics_tick()`: on its first tick after arming, queries
`get_world_3d().direct_space_state.intersect_shape()` (a 25 m sphere centered on the
rocket's own position) for `Block` bodies whose `owner_slot`'s `Match.team_of()` differs
from the rocket's own `owner_slot`'s team, picks the nearest, and every tick thereafter
sets `linear_velocity` toward that target's *current* position at `speed` (a moving
lock, not a one-shot aim) with `continuous_cd = true` set once at spawn (spec 3.5: "any
body moving faster than 15 m/s uses continuous_cd" — 18 m/s always qualifies, so this is
set unconditionally rather than checked). No target found within range: falls back to
`wants_early_trigger() -> true` after one tick, so it still detonates in place rather
than flying forever. `detonate()` does a `radius`-sphere impulse query
(`SpecialBehavior`'s helper, `apply_impulse` per body with `(1 - d/r)^2` falloff per spec
3.5, clamped to `SpecialTuning.max_explosion_impulse` — a new small addition to
`SpecialTuning`, since spec 3.5 names this clamp but no milestone has needed it yet) and
calls `trigger_others_in_range(position, radius, chain_depth + 1)`.

**Bomb** (spec 2.6: radius 3.5, impulse 18, 1.5 m proximity). `BombEffect.physics_tick()`
checks a 1.5 m sphere query each frame once armed for an enemy `Block`; if found, calls
`behavior.trigger(behavior.chain_depth)` itself (a proximity trigger is functionally the
same as an impact trigger here, just detected by distance instead of contact force).
`detonate()` is the same impulse-query-and-chain pattern as Rocket's, parameterized by
Bomb's own radius/impulse.

**Tests first:** Rocket locks onto the nearest enemy block within range and not a
same-team one; with no enemy in range it self-triggers rather than idling; explosion
impulse falls off with distance and is clamped. Bomb triggers when an enemy block enters
1.5 m even without a direct hit; does not trigger on a same-team block at any distance.
Both are physics-adjacent but written against a manufactured `PhysicsDirectSpaceState3D`-
free scenario where feasible (spy on `trigger()` calls) — the acceptance benchmark scene
below is the physics-accurate check.
**Acceptance:** a small scripted scene (owned by this package,
`tests/bench/bench_rocket_bomb.tscn`, timing not graded — a correctness smoke test, not
a benchmark) drops one of each near a two-team block cluster and asserts a detonation
and a resulting velocity change on the enemy blocks, none on the friendly ones.

## P4 — Volcano — **sonnet**

**Depends on P2 committed.** **Owns:** `config/specials/volcano.tres`,
`game/specials/VolcanoEffect.gd`, `tests/unit/test_volcano_effect.gd`,
`tests/bench/bench_specials_chain.gd` + `.tscn` (new — the milestone's named
5-volcano-chain benchmark).
**Reads only:** same P2 interfaces as P3, plus P3's committed `RocketEffect`/`BombEffect`
only if useful as a chain-target reference (not required — chaining works against any
`SpecialBehavior`, regardless of which concrete effect it wraps, so Volcano does not
need to depend on P3 at all; both can run in parallel once P2 lands).

**Volcano** (spec 2.6: erupts 3 s, 8–14 orbs, orb impulse 6, cone 35°).
`VolcanoEffect.wants_early_trigger()` returns true the instant it arms (it does not wait
for an impact — it is a timed self-eruption). `detonate()` starts a 3 s eruption: each
`physics_tick()` during that window, on a cadence derived from `orb_count` (picked once,
8–14, per spec's range) spread over 3 s, spawns one orb — a minimal single-cube `Block`
built via `BlockFactory.build()` on the shared `cube` `BlockShape` (reusing the existing
factory rather than inventing a second one, per "extend it, don't rewrite"), given
`owner_slot` = the volcano's own, a `SpecialBehavior` of its own (so an orb can itself be
chained into, and itself explodes on impact — spec: "each orb explodes on impact and can
set off other specials"), `continuous_cd = true`, and an initial velocity inside a
`cone_angle` cone around the disk's local up vector, magnitude `orb_impulse`. Each orb is
its own net-replicated `Block` exactly like a rocket, at zero extra wire cost beyond what
SnapshotSync already does for any awake body. An orb's own `detonate()` is the standard
impulse-query-and-chain, at the orb's own (smaller) radius/impulse — **`# DECISION`
(game/specials/VolcanoEffect.gd):** since spec 2.6 gives volcano an eruption but not an
orb-specific radius/impulse pair distinct from the whole-volcano numbers, orbs reuse
`orb_impulse` as both their launch impulse and (scaled down by
`SpecialTuning.orb_explosion_impulse_fraction`, a new small tunable) their own detonation
impulse — a reasonable reading, not a gameplay-defining one, of a spec row that names one
set of numbers for the whole special.

**Tests first:** `wants_early_trigger` is true immediately on arming; over the 3 s
eruption window exactly `orb_count` orbs spawn (no more, no fewer, regardless of frame
rate — driven by simulation time, not tick count) and each lands inside the specified
cone (asserted on each orb's initial velocity direction, not its landing spot, which
depends on physics); an orb's own `detonate()` respects the incoming `chain_depth` cap
the same way P2's generic test already proves for `SpecialBehavior`.

**`bench_specials_chain.tscn` — the milestone's graded benchmark.** Five volcanoes
placed close enough that their orbs' explosion radii overlap, following
`bench_tower.gd`'s format exactly (one `BENCH_SPECIALS_CHAIN` result line, `PASS`/`FAIL`,
`get_tree().quit()`): runs for a fixed sim duration covering at least one full 3 s
eruption from each volcano plus enough chain propagation to reach `max_chain_depth`
somewhere in the scene, records average `Performance.TIME_PHYSICS_PROCESS` exactly as
`bench_rain.gd` already does, and fails if average step time exceeds the 60 fps budget
(16.6 ms). **Same caveat `bench_rain.gd` already documents, copied verbatim into this
scene's header comment: headless timing has no rendering/vsync and is a relative
regression proxy, not proof of 60 fps in the shipped game** — do not report this
benchmark passing as equivalent to a verified in-game frame rate; that needs a windowed
run on real hardware, listed under manual owner steps below.

## P5 — Disk-affecting specials: Earthquake, Anvil, Fan — **sonnet**

**Depends on P2 committed and P0b's tilt API committed** (`Field.apply_tilt_impulse`) —
the one place Track A and Track B join before final integration. If P0 is not yet
merged when P2 finishes, serialize P5 behind it rather than starting early against an
uncommitted interface (`docs/AGENT_WORKFLOW.md`: "a new worktree cannot see uncommitted
changes").
**Owns:** `config/specials/earthquake.tres`, `game/specials/EarthquakeEffect.gd`,
`config/specials/anvil.tres`, `game/specials/AnvilEffect.gd`, `config/specials/fan.tres`,
`game/specials/FanEffect.gd`, `tests/unit/test_earthquake_effect.gd`,
`tests/unit/test_anvil_effect.gd`, `tests/unit/test_fan_effect.gd`.
**Reads only:** P2's committed interfaces, `game/Field.gd`'s committed
`apply_tilt_impulse` (P0, read-only — do not edit `Field.gd`), `config/TiltTuning.gd`.

**Earthquake** (spec 2.6: shakes 4 s, amplitude 0.25 m / 2.5°). `wants_early_trigger()`
true on arming (self-triggers, no impact needed, matching Volcano's pattern).
`detonate()` starts a 4 s window; each `physics_tick()` during it calls
`Field.apply_tilt_impulse()` with a small random direction and magnitude drawn from
`TiltTuning.earthquake_amplitude_deg`, plus an independent vertical Y-offset oscillation
on the disk body itself at `earthquake_amplitude_m` (owned by P0b's tilt update loop,
read here via the same `apply_tilt_impulse`-adjacent call — if a second entry point
proves necessary for the Y-offset specifically, that is a one-line addition to P0's
committed `Field.gd` API surface that this package requests rather than makes itself,
consistent with not editing `Field.gd`). "Blocks near the impact point get extra
shaking" (spec 2.6): a direct small random impulse applied to every `Block` within a
radius of the earthquake's own position, on top of the disk-wide shake — this package's
own physics query, not Field's.

**Anvil** (spec 2.6: mass 60, tilt impulse ∝ distance from center). `wants_early_trigger()`
true once settled (lands, tilts, matches Fan/Earthquake's "self-triggers on landing"
family rather than Rocket/Bomb's "triggers on hitting something" family). `detonate()`
calls `Field.apply_tilt_impulse()` once, direction = the anvil's own disk-local position
normalized (tilting the disk *toward* where it landed, per spec), magnitude =
`anvil_tilt_impulse_per_distance * distance_from_center` — **`# DECISION`
(game/specials/AnvilEffect.gd): the proportionality constant is not given in spec 2.6's
table** (only "tilt impulse ∝ distance from center" as a relationship, no number); picked
so a maximum-distance landing (near the rim) alone reaches roughly half of
`TiltTuning.max_tilt_deg`, leaving room for a second hit or another special to tip it
further, and recorded here for retuning during playtesting rather than treated as final.
The anvil `Block` itself needs `mass = 60` set directly (not through the usual
`BlockFactory.build()`'s `cube_mass * cube_count` path, since an anvil is not built from
a multi-cube `BlockShape` scaling its own weight that way) — this package sets `.mass`
on the spawned `Block` after `BlockFactory.build()` returns, the same override pattern
`BlockFactory.build_visual_only()` already demonstrates is fine to layer after the
factory call.

**Fan** (spec 2.6: force 10, range 12, blows 5 s, tilts away from itself; behavior
RECONSTRUCTED per spec's own table, so exact feel is minor-ambiguity implementation
detail, not an owner question). `wants_early_trigger()` true once settled.
`detonate()` starts a 5 s window; each `physics_tick()` applies a small outward
`apply_central_impulse` to every `Block` within `range` (excluding its own team's blocks
or not — spec doesn't say the fan discriminates by owner, unlike Rocket/Bomb which
explicitly target enemies, so this pushes everyone in range, own blocks included,
matching "the anvil hurt everyone" being listed in spec 1.7 as a known original quirk the
remake keeps rather than removes for Fan specifically) and calls
`Field.apply_tilt_impulse()` once at `detonate()` time, direction = away from the fan's
own position (tilting the disk away from itself, per spec), magnitude =
`TiltTuning`'s new `fan_tilt_strength` — **`# DECISION`, same reasoning as Anvil's
constant**, not given a number by the spec table.

**Tests first (all three):** each effect's `wants_early_trigger()` fires only once
settled, not on first arming while still airborne/falling; each calls
`Field.apply_tilt_impulse` with the correct direction sign (toward self for Anvil, away
for Fan, random for Earthquake) — verified against a fake/spy `Field`-shaped object
exposing `apply_tilt_impulse`, not a real physics `Field`, so these stay fast unit tests;
Earthquake's and Fan's timed windows run for their full spec'd duration and then stop
(no impulses after the window closes).
**Acceptance:** the three unit-test files pass; a manual windowed check (owner steps
below) that dropping each near the disk edge visibly tilts it in the right direction.

## Integration order

1. **P0 and P1 start in parallel** — disjoint files (`game/Field.gd` vs.
   `autoload/Match.gd`/new gift files), neither depends on the other.
2. **P2 starts once P1 is committed** (P2 reads P1's `held_special()`/gift `Events`) —
   serialize in one checkout if a second worktree is not ready, per
   `docs/AGENT_WORKFLOW.md`. P2 does not need P0 committed yet (throw/arc/arming touch
   no tilt code).
3. **P3 and P4 start once P2 is committed** — fully parallel with each other and with
   P0b if P0a is already merged (neither touches `game/Field.gd`).
4. **P5 starts once both P2 and P0 (specifically P0b's `apply_tilt_impulse`) are
   committed** — the one hard join point between the two tracks.
5. Each merge passes `godot --headless --editor --path . --quit` (no errors, no new
   warnings) and the full GUT suite before the next package lands, same gate M3a/M3b
   used. `autoload/Events.gd` and `net/MatchNet.gd` are the two files more than one
   package appends to (P1 and P2 both append distinct `EVENT_*` consts/signals) — every
   side only appends, so keep both blocks exactly as M3a's Events.gd convention already
   establishes.
6. **Integrator** wires nothing new into `game/Main.gd`/`Main.tscn` structurally (unlike
   M3a/M3b, M4 adds no new top-level scene — gifts and specials are children of the
   existing match world) but does need to: confirm `game/Main.gd` passes
   `MatchConfig.tilt_mode` through to `Field` before `_ready()` bakes its body type (a
   one-line check, not an edit if P0 already reads `map_def`/`config` the same way
   `Field` already does per Bontago-keo.2's existing note about `Field` baking from its
   own `map_def` rather than `Match.config`'s — **flag, not fix:** Bontago-keo.2 is a
   separate open M6 bug about `Field`'s `map_def` specifically; this plan's P0 does not
   touch that bug, but the tilt-mode wiring above has the identical shape (`Field` needs
   a value from `Match.config` before its own `_ready()` runs) and P0/the integrator
   should not silently reintroduce the same class of bug for `tilt_mode` while fixing
   holes — worth a deliberate look, not a silent copy of the existing gap); run the full
   suite once combined; run `tools/run_m3a_local.ps1 -Peers 4` (existing M3a harness,
   unmodified) as an M4 regression check that gifts/specials replication doesn't break
   ordinary placement traffic; extend it or run a second scripted pass exercising at
   least one claim, one throw and one trigger across peers for LAN parity, since no
   package above builds a dedicated M4 network harness of its own — the M3a harness
   already proves placements are never duplicated or lost, and this milestone's
   replication additions (`replicate_match_event` for gifts/specials) ride the same
   proven reliable-RPC path, not a new one, so a full new multiplayer test harness would
   be redundant with what M3a already validates end-to-end.

## Where every tunable lives — no magic numbers (CLAUDE.md)

| Resource | Owner | Holds |
|---|---|---|
| `tilt_tuning.tres` | P0b | `max_tilt_deg` 12, `return_time_constant_s` 4, spring stiffness/damping (derived), `earthquake_amplitude_m` 0.25, `earthquake_amplitude_deg` 2.5, `fan_tilt_strength` (undocumented by spec, P5 picks and records), `anvil_tilt_impulse_per_distance` (undocumented by spec, P5 picks and records) |
| `gift_config.tres` | P1 | `life_s` 60, `interval_at_freq_20_s` 45, `interval_at_freq_100_s` 6, `interval_jitter_fraction` 0.40, `spawn_max_attempts` 20 |
| `special_tuning.tres` | P2 | `max_chain_depth` 4, `throw_max_speed` 25, `max_explosion_impulse` (spec 3.5 names the clamp, no milestone has set it yet), `orb_explosion_impulse_fraction` (P4's decision) |
| `config/specials/rocket.tres` | P3 | `speed` 18, `radius` 3, `impulse` 14, homing range 25 m (typed fields on `RocketEffect`, not `SpecialDef.params`) |
| `config/specials/bomb.tres` | P3 | `radius` 3.5, `impulse` 18, proximity 1.5 m |
| `config/specials/volcano.tres` | P4 | `orb_impulse` 6, `cone_angle_deg` 35, `orb_count_min/max` 8/14, `eruption_duration_s` 3 |
| `config/specials/earthquake.tres` | P5 | `duration_s` 4 (amplitude numbers live on `TiltTuning`, shared with the disk-motion system, not duplicated here) |
| `config/specials/anvil.tres` | P5 | `mass` 60 |
| `config/specials/fan.tres` | P5 | `force` 10, `range` 12, `duration_s` 5 |
| script `const` | P2 | `SpecialDef.arm_delay`/`arm_impulse`/`fuse_timeout_s` defaults live on the resource itself per spec 3.6, not as consts — they are meant to vary per special, unlike `SnapshotSync.SNAPSHOT_CHANNEL`-style wire architecture |

## Testing without a second PC, without real hardware for fps

Same posture M3a/M3b already established: GUT unit tests for every rule (arming,
chaining, throw validation, gift claim/expiry, tilt math) run headless and fast;
`tests/bench/bench_specials_chain.tscn` gives a repeatable regression number for the
5-volcano acceptance but is explicitly a proxy, not a verified fps claim (see P4); LAN
parity reuses `tools/run_m3a_local.ps1 -Peers 4`, extended with a scripted claim/throw/
trigger sequence per the integration order above rather than a new dedicated harness.
Gamepad throw aiming (right stick reinterpreted while `throw_aim`/LT is held) is proven
with synthetic `InputEventJoypad*` events through `Input.parse_input_event` in
`test_match_throw.gd`-adjacent coverage, same pattern the existing M1/M2 gamepad tests
already use; a real gamepad's actual feel still needs the manual owner steps below.

## Manual owner steps

- Launch `godot --path .`, claim a gift (set `special_frequency` high and `gifts_enabled`
  on in a quick sandbox-style single-player match), confirm the next block shown in the
  HUD preview looks/behaves like a special.
- Hold the special, drag the right mouse button back, confirm the arc preview appears
  and release throws it with visibly scaled strength; repeat with a gamepad (hold LT,
  aim with the right stick — confirm camera orbit is suppressed while aiming, per the
  `CameraRig` gate P2 adds).
- Drop each of the six specials near an opposing player's tower and confirm its table
  row's behavior (rocket homes, bomb waits for proximity, volcano erupts for ~3 s, the
  disk visibly tilts for anvil/fan/earthquake in the documented direction).
  Chain two specials into each other (e.g. a volcano orb landing on a placed bomb) and
  confirm the second one detonates too.
- Drop a single ordinary block dead-center on a lone contested cell that has just become
  a hole and confirm it falls straight through (the P0 acceptance criterion, verified in
  the running game as the bug's own acceptance criteria require, not just in a test).
- Run a windowed (not headless) 5-volcano chain and watch the frame counter, since
  `bench_specials_chain`'s headless number is a proxy only.

## Model routing

Sonnet for every package except P0, which is Opus: it is the one package whose failure
mode is silent and broad (a subtly wrong collision-margin/mesh tradeoff regresses every
future milestone's physics, the way `cell_overlap` itself was tuned by trial and error
against exactly this kind of regression before), and where the assignment gives explicit
license to escalate for "bounded genuinely hard reasoning." Every other package is normal
implementation/netcode work against a spec that gives concrete numbers, following
established patterns (`request_place`/`submit_place`, `replicate_match_event`,
`PlacementRules`) closely enough that Sonnet is the right default, matching M3a's own
routing table.

## Known limitations (planned, M4)

- **Gift claiming assumes free-for-all** (`team_id == slot_id`, since `TeamMode` is still
  unwired per `docs/M2_PLAN.md`'s Known Limitations). Revisit which teammate's next block
  becomes the special once M6 wires real teams.
- **Crates never move once spawned** (owner question 1's default answer) — a special's
  explosion can knock a *block* into a crate, per spec 1.3's flavor text, but the crate
  itself does not physically react. If the owner answers question 1 the other way, this
  becomes a P1 rework, not a P2–P5 one (the crate's own body type is entirely P1's file).
- **PHYSICAL_BALANCE tilt mode stays unimplemented** — out of scope per spec Part 4 (M6),
  same as `hole_mode`/`enabled_specials` already being present-but-partially-wired lobby
  settings elsewhere in the codebase today.
- **`bench_specials_chain`'s ≥60 fps result is a headless timing proxy**, exactly like
  `bench_rain.gd` already is — a windowed run on real hardware is the only way to
  actually verify the acceptance criterion's fps claim, and is listed under manual owner
  steps rather than claimed as automatically proven.
- **P0's trimesh rebuild cost is unmeasured until the P0 package actually runs its
  required hole-churn timing scenario** — the plan's own acceptance criteria make that
  mandatory before P0 is considered done, but it is called out here too since it is the
  one number in this whole milestone that could force a design change (the local-submesh
  fallback) after packages downstream of P0 have already started.
- **Magnet, Freeze, Glue and Gravity Well are M8**, not this milestone (spec 2.6's own
  table already marks them NEW/M8-scope; Part 4 lists them explicitly under M8).
