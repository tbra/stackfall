# M2 — Rules & territory (hot-seat, 2 players): parallel build plan

Spec: §2.1–2.5, §2.7–2.8, §3.2–3.3, §3.6–3.7, Part 4 M2. Four packages build in parallel
off the stub commit; **file ownership is disjoint**. Only the integrator touches
`game/Main.gd` / `game/Main.tscn`. Every package writes its tests first.

**Acceptance (Part 4 M2):** two players take turns on one PC and can win; holes appear
where territories overlap and blocks fall through them; a cut-off tower loses its influence.

## Questions for the owner
Do not block — every package is designed so either answer fits. Relay and continue.

1. **Hot-seat turn model.** §2.2/§2.4 is real-time: every player has their own running
   block timer. One mouse cannot do that literally. **(a)** strict alternation — only the
   active slot's timer runs, the turn passes on place or auto-drop (§2.7's turn-based mode
   arriving early, minus its "wait for physics to settle" rule); **(b)** real-time — both
   timers run and slot 2's block auto-drops from wherever its ghost sits while slot 1 is
   still building. **Building (a)**; `MatchConfig.per_player_timer` + `hot_seat` make (b) a
   flag flip in `Match`, not a rewrite.
2. **[ORIGINAL] Releasing a block on an invalid spot.** §1.2 rule 4 says you may *only*
   drop inside your own area; §2.2 says a block released in a contested area "is thrown off
   the map". **Building:** while the ghost is red a deliberate click is *refused and costs
   nothing* (block kept, timer keeps running); only an **auto-drop** that finds no valid
   point within `auto_drop_search_max_radius` spawns the block and throws it off with the
   reject animation. The stricter reading — every invalid release burns the block — is a
   one-line change in `Match.request_place`. **[ORIGINAL] rule ⇒ a CLAUDE.md pause point.**
3. **Cut-off home flag.** §2.2 says the home circle exists "while the flag is on the disk";
   nothing covers a hole opening under one. **Building:** the flag falls,
   `PlayerSlot.home_flag_alive` goes false, that player's circles unanchor and their territory
   vanishes — effectively elimination. Confirm, or we anchor home circles forever.

## Work packages
### P1 — Pure territory & rules core — **opus** (16 owned files; the algorithmic heart, and everyone else codes against it)

**Owns:** `core/territory/{CellGrid,InfluenceCircle,TerritoryGroups,TerritorySolver,TerritoryRaster}.gd`, `core/rules/{WinChecker,PlacementRules}.gd`, `config/TerritoryTuning.gd` + `config/territory_tuning.tres`, `tests/unit/test_{cell_grid,influence_circle,territory_solver,territory_raster,win_checker,placement_rules}.gd`, `tests/bench/bench_territory.gd` + `.tscn`.
**Reads only:** `config/PhysicsTuning.gd` (settled thresholds), `config/MapDef.gd`.
**Tests first**, each pinning the spec rule it names:
- **Radius:** `r = base + k*h`, capped at `0.6 * field_radius`, `h ≤ 0` gives `base`; overlap
  is inclusive at exactly `r1 + r2`.
- **Overlap / connectivity:** two overlapping same-team circles → one group; two disjoint →
  two groups; chain A–B–C with A and C apart → still one group. A circle touching the home
  circle joins its group; a home circle is always a group seed.
- **Cut-off tower loses influence:** build home–A–B, remove A; B vanishes from the groups and
  `raster.team_at` over B's cells returns −1.
- **Teams merge without holes:** two slots, same team, overlapping → one group, zero
  contested cells, no hole ever. Two *different* teams overlapping → those cells read
  `TerritoryGroups.CONTESTED`, neither team owns them, `team_share` excludes them.
- **`hole_delay`:** contested 0.74 s → no hole; past 0.75 s → hole, index appears exactly
  once in `holes_opened()`.
- **`hole_mode`:** `TEMPORARY` — overlap ends, still a hole at 1.9 s, closed at 2.1 s, index
  in `holes_closed()`. `PERMANENT` — never closes, `holes_closed()` stays empty.
- **Win check:** all goals in one group → `capturing_team` set, progress ramps, `winner` at
  3.0 s; break at 2.9 s → progress back to 0. Two goals owned by the same **team** in two
  different **groups** → no capture.
- **Placement:** every footprint cell must be owned, uncontested, hole-free; a rotated
  footprint covers every cell its cubes overlap, not just cell centers; crossing the rim is
  `OFF_DISK`; `closest_valid_origin` returns `desired` when already valid, the nearest valid
  ring point otherwise, `NO_ORIGIN` once the search radius is exhausted.
**Acceptance:** all of the above pass; `bench_territory.gd` reports solve+raster time for 200
circles on map M, **budget ≤ 8 ms per solve** at 10 Hz — if missed, raise `hash_cell_size` /
lower `max_circles` **in the resource**, never in code, and report the numbers.
**Must NOT:** reference the scene tree, `Events`, `Match` or `game/` — `core/` stays pure. No
`push_error` in `solve`/`update` (10×/s). Remove every stub `@warning_ignore_start`.

### P2 — Match flow, feed, block identity — **sonnet** (13 owned files; mechanical, but it is the authority)
**Owns:** `autoload/Match.gd`, `config/MatchConfig.gd` + `match_defaults.tres`, `config/BlockFeedConfig.gd` + `block_feed.tres`, `core/feed/BlockBag.gd`, `core/rules/PlayerSlot.gd`, `game/{Block,BlockFactory,BlockRegistry}.gd`, `tests/unit/test_{block_bag,match_config,player_slot,match_flow,block_registry}.gd`.
**Reads only:** everything P1 owns, `config/MapDef.gd`, `config/PhysicsTuning.gd`.
**Tests first:** the bag deals every shape; weights hold over 2000 draws (±15%); every bag
carries ≥ `min_stabilizers_per_bag` stabilizers; the same seed deals the same sequence;
`peek(3)` never goes short across a bag boundary and does not consume. `MatchConfig`
`to_dict`/`from_dict` round-trips every field and `sanitize` clamps each §2.8 range.
`PlayerSlot.home_position_for`: 2 players sit π apart, 8 at π/4 steps, all at
`0.85 * field_radius`; `goal_positions_for(1)` is the center, `(3)` is symmetric at
`0.4 * field_radius`. State machine: `start_match` → Countdown → Playing after 3 s
(`countdown_tick` 3,2,1,0); `feed_timer_expired` fires at `block_timer`; the turn advances
on placement.
**`game/BlockRegistry.gd`** (new `Node`): listens to `Events.block_placed`/`block_removed`
and each physics frame runs the **settled** rule from `PhysicsTuning` — linear <
`sleep_linear_threshold` **and** angular < `sleep_angular_threshold`, held continuously for
`sleep_settle_time`; any frame above either threshold resets the accumulator to 0. Exposes
`influence_circles(slots, tuning, map_def) -> Array[InfluenceCircle]` (center of mass
projected to disk-local x/z, `top_height` = highest AABB corner above the disk surface),
`max_height_for_slot(slot_id) -> float`, `bodies_over_cells(cells) -> Array[RigidBody3D]`.
`Block` gains `owner_slot: int` and `net_id: int` (M3 uses `net_id`); `BlockFactory.build`
gains an `owner_slot` parameter **defaulted to −1** so M1's tests keep compiling.
**Acceptance:** a headless test drives `Match` Lobby-to-win through scripted `request_place` calls, with no scene tree beyond a bare `Field`.
**Must NOT:** touch `Field.gd`, `PlayerController.gd`, `GhostPreview.gd`, `ui/`, `shaders/`,
`Main.*`. Never re-implement a rule that lives in `core/` — call P1.

### P3 — Field cells, raster upload, shader, flags — **opus** (14 owned files; batched shape toggling and the shader are the subtlest work in M2)
**Owns:** `game/Field.gd` + `.tscn`, `game/TerritoryOverlay.gd`, `shaders/territory.gdshader`, `game/{HomeFlag,GoalFlag}.gd` + `.tscn`, `config/MapDef.gd`, `config/maps/round_{small,medium,large}.tres`, `config/TerritoryVisuals.gd` + `territory_visuals.tres`, `tests/unit/test_{field_cells,territory_overlay,flags}.gd`.
**Reads only:** everything P1 and P2 own.
**Tests first:** after `_ready` the grid holds exactly `CellGrid.in_disk_cell_count()`
enabled shape owners; `set_hole_cells` disables the right owners and never toggles more than
`max_cell_toggles_per_frame` in one frame, draining a backlog over several frames; a body over
a toggled cell is awake afterwards; a block dropped on an opened cell falls through to the
kill plane; `disk_local_from_world`/`world_from_disk_local` round-trip; the overlay's
`ImageTexture` is `territory_res²` and its R channel matches `owner_bytes` after the upscale.
**`Field` API — the contract P2 and P4 code against; implement exactly:**
```gdscript
func grid() -> CellGrid
func map_definition() -> MapDef
func surface_y() -> float                                    # world Y of the disk top; 0.0 while flat
func disk_local_from_world(world: Vector3) -> Vector2
func world_from_disk_local(local: Vector2, height: float) -> Vector3
func set_hole_cells(opened: PackedInt32Array, closed: PackedInt32Array) -> void
func is_hole_cell(index: int) -> bool
func pending_toggle_count() -> int                           # backlog not yet applied
func wake_blocks_above_cells(cells: PackedInt32Array) -> void
func set_overlay_source(raster: TerritoryRaster, slot_colors: PackedColorArray) -> void
func home_flag_position(slot_id: int, slot_count: int) -> Vector2
func goal_flag_positions(count: int) -> PackedVector2Array
func set_capture_progress(team_id: int, progress: float) -> void   # goal flags' radial ring
```
`class_name Field` must not change — `Match` types against it.
**Shader:** samples the texture (R = `team_id + 1`, 0 = unowned; G = `STATE_CONTESTED |
STATE_HOLE`), maps R through a `slot_colors` uniform array, `smoothstep`s the bilinear edge
into a soft tint with an animated outline, shimmers contested cells, glows hole rims, and
`discard`s hole pixels (§2.10, §3.3).
**Must NOT:** own rule logic — the hole decision is P1's, `Field` only applies it. No
`Events` emission beyond what the API implies. Do not touch `Main.*`.

### P4 — Placement feel, ghost tint, HUD, hot-seat — **sonnet** (11 owned files; broad, but each piece is small)
**Owns:** `game/PlayerController.gd`, `game/GhostPreview.gd`, `game/HotSeat.gd` + `.tscn`, `ui/HUD.gd` + `.tscn`, `config/GhostTuning.gd` + `ghost_tuning.tres`, `tests/unit/test_{hot_seat,ghost_tint,hud}.gd`.
**Reads only:** everything P1–P3 own.
**Tests first:** the ghost is the owner's color when `Match.preview_placement` returns
`VALID`, red for `OUTSIDE_TERRITORY`/`CONTESTED`/`OFF_DISK`, hatched over `HOLE` (§2.5); a
click while red emits `Events.placement_rejected` and spawns nothing;
`Events.feed_timer_expired` makes the controller call `Match.request_place(..., auto_drop =
true)` exactly once; `Events.turn_changed` swaps the ghost to the new slot's shape and color;
the timer ring reads `Match.feed_progress`. Gamepad parity uses synthetic `InputEventJoypad*`
via `Input.parse_input_event`, as `test_playercontroller_gamepad.gd` already does.
**`HotSeat.tscn`** is a self-contained subtree (controller + ghost + HUD) the integrator
drops into `Main.tscn` as one instance. It owns no rules: every placement goes through
`Match.request_place` even though both players are local.
**`HUD` API — implement exactly:**
```gdscript
func set_active_slot(slot_id: int, color: Color) -> void
func set_next_shape(shape: BlockShape) -> void
func set_feed_progress(fraction: float) -> void              # 1 -> 0, drives the timer ring
func set_height(meters: float) -> void
func set_territory_shares(shares: PackedFloat32Array) -> void
func set_capture(team_id: int, progress: float, color: Color) -> void
func show_reject(reason: StringName) -> void
func show_winner(team_id: int, color: Color) -> void
```
It connects to `Events` only — no node paths out of `ui/`.
**Must NOT:** spawn a `Block`, decide validity, or read the raster for rules — ask `Match`.
Do not touch `Field.gd`, `Match.gd`, `core/`, `Main.*`.

## Integration order
0. **Before packages start:** merge the in-flight physics-tuning and cleanup branches into
   `main`, then this plan branch. `autoload/Events.gd` is the one expected conflict — both
   sides only *append*, so keep both blocks.
1. **P1 lands first**, but P2–P4 start immediately: the stubs already compile, so everyone
   codes against the final signatures from day one.
2. **P2, then P3, then P4.** Each merge must pass `godot --headless --editor --path . --quit`
   (no errors, no new warnings) and the full GUT suite before the next lands.
3. **Integrator wires `Main.gd`/`Main.tscn`** — the only files nobody else owns. Instance
   `Field`, `HotSeat.tscn`, `BlocksContainer`, `BlockRegistry`; keep `CameraRig`. Call
   `Match.register_world(field, registry, blocks_container)`, then `Match.start_match()` with
   a **duplicate** of `match_defaults.tres` (`player_count = 2`, `hot_seat = true`), then
   `Field.set_overlay_source(Match.raster(), config.player_colors)`. Ticks all come from
   `Match._process` accumulators, never `Timer` nodes: **10 Hz** (`solve_hz`) —
   `registry.influence_circles(...)` → `TerritorySolver.solve` → `TerritoryRaster.update(...,
   1/solve_hz, permanent)` → `WinChecker.update` → emit `territory_updated`,
   `hole_cells_changed`, `goal_capture_progress`, `territory_share_changed`, and `match_won`
   on a winner; **5 Hz** (`raster_upload_hz`) — `TerritoryOverlay` rebuilds the
   `ImageTexture`. `Field` consumes `hole_cells_changed` the frame it arrives and drains its
   backlog at ≤ `max_cell_toggles_per_frame` per frame regardless of tick rate.
4. Manual pass against the Part 4 M2 criteria, plus a gamepad run written up for the owner.

## Where every tunable lives
No magic numbers anywhere (CLAUDE.md). Nothing below may appear as a literal in code.

| Resource | Owner | Holds |
|---|---|---|
| `territory_tuning.tres` | P1 | `influence_base` 1.5, `influence_k` 0.9, `influence_max_fraction` 0.6, `home_radius` 6.0, `max_circles` 400, `solve_hz` 10, `raster_upload_hz` 5, `hash_cell_size` 4.0, `hole_delay` 0.75, `hole_close_delay` 2.0, `max_cell_toggles_per_frame` 64, `capture_hold` 3.0, `auto_drop_search_step` 1.0, `auto_drop_search_max_radius` 12.0, `reject_impulse` 30.0, `reject_upward_fraction` 0.35 |
| `match_defaults.tres` | P2 | every §2.8 lobby setting, `per_player_timer`, `hot_seat`, `player_colors` (8), `rng_seed`, and the `*_MIN`/`*_MAX` range constants |
| `block_feed.tres` | P2 | `shapes`, `weight_overrides`, `stabilizer_ids`, `min_stabilizers_per_bag` 2, `bag_multiplier` 2.0, `preview_count` 1 |
| `maps/round_{s,m,l}.tres` | P3 | `field_radius` 30/45/60, `disk_height` 1.0, `cell_size` 1.0, `territory_res` 256/384/512, `home_flag_radius_fraction` 0.85, `goal_flag_radius_fraction` 0.4 |
| `territory_visuals.tres` | P3 | edge softness, tint alpha, outline speed, contested shimmer rate, hole rim glow, flag mesh size, capture ring thickness |
| `ghost_tuning.tres` | P4 | existing fields, plus invalid/hatched tint colors and hatch scale |
| `physics_tuning.tres` | read-only | **already has** the settled rule: `sleep_linear_threshold` 0.15, `sleep_angular_threshold` 0.3, `sleep_settle_time` 0.5. Also `cube_size`, `kill_plane_y`, `hover_height`, `gravity_multiplier`. |

## Design notes — the parts that are easy to get wrong
**Raster coordinates.** Disk-local space is plain Cartesian `(x, z)` in meters, origin at the
disk center; height never enters it. `CellGrid` lays a square `res × res` grid of `cell_size`
cells over the disk's bounding square, so cell `(0,0)` is the `−x/−z` corner and the index is
row-major `cy * res + cx`. **One cell is one raster pixel is one `BoxShape3D` shape owner in
`Field`** — that identity stops the three disagreeing about where a hole is. A cell is in the
disk if its *center* is, giving all three one shared rim.
`Field.disk_local_from_world`/`world_from_disk_local` are the only functions that change when
the disk starts tilting in M4.

**Raster resolution — `DECISION`.** §3.3 puts the raster at `territory_res` (256/384/512).
The **rules** raster runs at *cell* resolution instead (90×90 on map M): a 384² CPU fill at
10 Hz is ~140k pixel writes per tick in GDScript, and holes, validation and the win check are
all defined on cells anyway, so finer pixels buy nothing. `territory_res` stays in `MapDef`
and still does what §3.3 asks — `TerritoryOverlay` upscales the cell image with
`Image.resize(..., INTERPOLATE_BILINEAR)` (a C++ call, at 5 Hz), uploads that, and the shader
applies the smoothstep edge §3.3 already calls for. Contested time accumulates per cell,
exactly the granularity holes toggle at; hole granularity is 1 m either way, so this is
invisible in play.

**Settled.** §2.2: linear < 0.15 m/s **and** angular < 0.3 rad/s held continuously for 0.5 s.
One frame above either threshold resets the accumulator to zero — not a decay — so a falling
block never flashes influence on the way down. These are *rule* thresholds, deliberately
looser than Jolt's own sleep threshold (0.03 m/s); do not confuse them, and do not substitute
`RigidBody3D.sleeping`.

**Influence radius.** `r = influence_base + influence_k * h`, `h` = the block's highest point
above the disk surface **along the disk normal** (not world Y — that matters from M4), capped
at `influence_max_fraction * field_radius` (27 m at M). The circle centers on the center of
mass projected onto the disk plane, so a block overhanging an edge drags its circle with it.
§2.2's height credit then follows for free: circles carry `owner_slot`, so one block on an
enemy tower gives *you* a circle at that height.

**Team ownership and merging.** Union-find unites two circles only when they overlap **and**
share `team_id`; a component survives only if it holds an `is_home` circle. That one rule
delivers three spec rules at once — connectivity, the cut-off rule ("if a tower is cut off,
its influence is gone"), and teammate merging ("teammates never create holes between them").
Free-for-all needs no branch, since `MatchConfig.team_of_slot` gives every slot its own team.
Two *different* teams stamping a cell make it `CONTESTED`; two groups of the *same* team never
do. Per cell, `contested_time += delta` while contested and drains while not; crossing
`hole_delay` opens a hole into `holes_opened()`, and under `TEMPORARY` `hole_close_delay`
uncontested closes it into `holes_closed()` (under `PERMANENT`, never). `Field` applies both
lists with `shape_owner_set_disabled`, batched at ≤ 64 per frame (§3.3) through a FIFO
backlog, and **wakes every sleeping body above a changed cell** — without that a tower sits
happily on a hole that has no collision left.

**Solver → raster → win check.** `TerritorySolver.solve` returns `TerritoryGroups`, whose
group indices the raster writes into every cell. Both consumers read that one array:
`TerritoryRaster` maps group → team for ownership and color, and `WinChecker` reads the
**group index** at each goal and requires every goal to return the *same* group. Same group,
not same team — that is what makes it "one connected territory" (§2.3), so a team holding two
goals with two separate towers correctly does not win.

**Host authority now, clients in M3 (§3.4).** Everything authoritative already lives in
`Match` and `core/`: feed timers, the solve, the win check, validation. Even in hot-seat
`PlayerController` never spawns a block — it calls the single entry point
`Match.request_place(slot_id, origin, orientation_index, free_quat, auto_drop)` and reacts to
the returned reason, exactly the intent shape §3.4 specifies. The ghost tint uses the
read-only, advisory `Match.preview_placement`; `request_place` re-validates from scratch and
never trusts it. M3a then adds an `@rpc("any_peer", "call_remote", "reliable")` wrapper that
checks the caller's peer id against the slot and forwards — no rule code moves. Nothing in M2
may branch on `multiplayer.is_server()` yet, and nothing may assume a transport.
