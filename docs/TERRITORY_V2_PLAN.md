# Territory v2 — design contract (owner clarifications, 2026-09-20)

> **Fidelity audit amendment, later 2026-09-20:** the owner subsequently requested priority for concrete original-game evidence. Read `SPEC.md` §§1.2, 2.2–2.5 and 3.3 plus its current decision record before implementing this older plan. Original fixed placement windows and overlap holes now take priority over immediate-reset timers and the `OFF` default proposed below. The owner explicitly retained the 3-second capture hold. This plan remains the historical design for the optional v2/no-overlap alternative; its completed packages do not establish default-rule compliance.
>
> **Review findings, not code changes:** `radius - distance` is additively weighted distance, not a power/Laguerre kernel. With radii 10 and 2, centers 3 apart, the large circle wins everywhere: the "never the rival's whole area" claim below is false in general. A pre-clipping circle graph also cannot prove an unbroken route in final owned territory. Per-block top elevation, settled filtering and the lower-team-ID tie-break are design choices, not verified original rules or automatically gameplay-neutral. The raster-smoothing claim below was already disproved by package C (see Beads `Bontago-cmc.5`). Reconcile these findings before treating the existing reasoning as acceptance evidence.
>
> **Amendment (2026-09-20, Bontago-cmc.7):** SPEC.md's evidence audit ("Decisions made —
> current target") restored overlap holes as the fidelity default and made
> `MatchConfig.hole_mode = TEMPORARY` the default again; `HoleMode.OFF`, the argmax
> no-overlap ruleset this whole plan describes, is now the **optional** mode, not the
> default. Read this document as the design of `HoleMode.OFF` specifically, not of the
> game's default rules. Point-ray placement, continuous solving and goal no-build zones
> are the parts of this plan the audit *kept* as owner-retained requirements — those now
> apply under every `hole_mode`, not only `OFF` — see "Reconciled 2026-09-20" at the end
> of this file for exactly what changed and stayed the same.

Historical basis: the earlier **"Owner clarifications — 2026-09-20"** record and
`docs/bloody_mess.md` (the owner's own words). The current `docs/SPEC.md` decision record
and Part 2 now take precedence over this plan. Also read: §2.2, §2.3, §2.5, §3.3, §3.6, §3.7, `docs/M2_PLAN.md` (how territory
was built), `docs/M3a_PLAN.md`'s "Design notes" (raster replication). This plan is a
**rules rewrite**, not a new milestone's worth of new systems: it replaces how area of
influence is computed and rendered, and how placement is validated, while reusing almost
everything else — connectivity, the win check, replication, the HUD and `Field`'s
collision/hole machinery all either need no change or a small, additive one.

**Two decisions the owner/orchestrator have already settled (not open questions, folded
in below):**
1. **Floor holes are removed from the default ruleset but kept as a future lobby mode.**
   `Field.set_hole_cells`/`_hole_*`/`Events.hole_cells_changed` and the whole legacy
   contested-cell/hole state machine stay compiled and tested, gated behind
   `MatchConfig.hole_mode`, which now defaults to a new `OFF` value. `Bontago-ruw` (the
   lone-hole-cell rim bug) stays parked — it is unreachable in the new default rules and
   remains exactly as risky/rare as before in the legacy mode.
2. **Home-flag elimination stays as today**: an enemy area swallowing a start flag
   eliminates that slot, and last-team-standing ends the match. Only *how* "swallowed" is
   detected changes (§ "Home-flag elimination" below), because it can no longer be driven
   by a hole-opened event under the default rules.

## What actually has to change, and what does not

Reading the current code against the owner's text turns up less new surface than it
looks like at first:

- **The radius formula is already right.** `InfluenceCircle.radius_for_height` /
  `BlockRegistry._top_height_local` already give each block a circle sized by *how high
  above the disk that block's own top sits* — which, because physics is what got the
  block there, already reads as "the height of the stack it belongs to" without any
  contact-graph bookkeeping. Kept unchanged; see "Stack height" below for why.
- **Connectivity is already a circle graph.** `TerritorySolver`'s union-find over
  overlapping same-team circles, anchored on a home circle, is exactly "your territory is
  the union of circles connected to your home flag" and exactly "an undisrupted path...
  built from one or more connecting towers." Kept unchanged.
- **The win check is already group-based, not team-based.** `WinChecker.update()` reads
  `TerritoryRaster.group_at_point()` at every goal and requires the *same* group at all of
  them. Kept unchanged — it will keep working once the raster's fill produces v2's
  ownership groups instead of cell-stamped ones.
- **What has to change:** the raster's *fill* (stamp-first-come-and-contest → argmax over
  a per-circle kernel, "never overlap, taller stack pushes the border"), placement
  validation (multi-cell footprint → one raycast + one point test), and a small,
  additive no-build-zone concept for goal flags. `Field`, `TerritoryOverlay`, `MatchNet`,
  `SnapshotSync` and `HUD` need at most one small addition each (`Field` gains one new
  method; the rest need none — see their sections).

## The formula

**Kernel.** For a circle `c` (home or block) and a disk-local point `p`:

```
kernel_value(c, p) = c.radius - distance(p, c.center)
```

Positive inside the circle, negative outside, zero on the rim — the signed "how deep
inside this circle" value. This is a weighted (power/Laguerre) Voronoi kernel: it is the
simplest function whose argmax satisfies every owner bullet at once (worked through
below), and it needs no new tunable — it is built entirely from `radius`, which the
existing formula already supplies.

**Ownership at a point.** Only circles belonging to a **home-anchored group**
(`TerritorySolver`'s output — exactly the circles `TerritoryRaster.update()` already
iterates via `groups.circles_of(group)`) take part. The owner of point `p` is the team of
whichever anchored circle has the **largest** `kernel_value(c, p)`, or unowned if every
value is `≤ 0` there (`p` is outside every one of that circle's radius).

**Why this satisfies the owner's bullets:**
- **Never overlap:** argmax is a function, not a set — every point has exactly one
  winner (or none). ✓ ("Different players areas of influence can't overlap.")
- **Border pushed by height, not all-or-nothing:** for two circles of radius `r1`, `r2`
  whose centers are `d` apart, the argmax switches exactly where `r1 - x = r2 - (d - x)`,
  i.e. at `x = (d + r1 - r2) / 2` from circle 1's center. A taller (bigger-radius) circle's
  boundary sits further from *its own* center than a shorter rival's, so it claims more of
  the space between them — but the border is still strictly between the two centers
  (unless one circle doesn't reach that far at all), never the rival's whole area. ✓
  ("the taller local stack gets more of the shared region, but not all of it")
- **Individual stacks count, never a global per-player value:** the argmax is over
  **individual circles**, not a per-team sum or max-of-sums. A player's five short, spread
  out towers never gang up to out-push one enemy's single tall one at any given point —
  only whichever of that player's circles is locally strongest there is compared. ✓
  ("it is the individual contesting stacks that count, never a global per-player value")
- **Cut-off towers lose influence, for area as well as the win check:** because only
  `groups.circles_of(group)` (i.e. already home-anchored) circles are ever evaluated, a
  tower separated from its player's home the instant it's cut off drops out of the field
  the same tick `TerritorySolver` drops it from a group — not just out of the win check,
  out of the *visible area* too, which the spec 2.2 cut-off rule never distinguished.

**Tie-break** (two circles score exactly equal, e.g. a symmetric layout): lower `team_id`
wins. Routine implementation detail, no gameplay impact — `# DECISION` at the compare.

**Home circle / "extra space".** The owner's "small circle... plus some extra space" is
already one number, `TerritoryTuning.home_radius` (6.0). No decomposition into two fields;
`# DECISION`, since nothing downstream needs the two pieces separately.

## Stack height — what "the stack it belongs to" means here

`BlockRegistry._top_height_local(block)` already reports *that block's own* highest point
above the disk surface, not a global tower height. Two readings were possible:

1. **Keep it** — a block's own elevation, which can only be that high because physics is
   holding it up there (directly or through a contact chain). This is what's implemented.
2. **Walk the contact/support graph** to compute each tower's actual base-to-tip height and
   give every block in that tower the tower's height, not its own.

(1) is chosen: it already produces exactly the owner's described behavior ("stack blocks
on top and the circle grows... top block on an enemy tower steals credit at that height",
spec 2.2's "height credit") with **zero new code**, is trivially robust to leaning/partial
towers and knocked-over piles (a support-graph walk has to define what happens when the
graph is disconnected or cyclic through resting contacts, which real physics produces
constantly), and costs one AABB scan per block, already paid. A contact-graph height would
require walking `PhysicsDirectSpaceState3D` contact pairs or shape overlaps for every
settled block every solve tick — real cost and real edge cases — for a difference that is
only visible when a block sits *directly on the disk next to, but not on top of,* a tall
tower, which is already the correct behavior (that block should get a small circle; it
isn't part of the tower). `# DECISION`, no owner input needed — this is what the current
code already does; v2 keeps it.

## Continuous updates — "immediately, not only when a new block is placed"

`BlockRegistry`'s settled/unsettled flag already flips every **physics frame** (60 Hz) the
moment a block's velocity crosses the threshold, so a falling stack stops contributing the
instant it starts moving. The only lag is how often `Match` actually re-collects circles
and refills the raster: today, `TerritoryTuning.solve_hz = 10.0` (100 ms). `# DECISION`:
raise the default to **20.0 Hz** (50 ms) — "recomputed... every physics tick or a fixed
high rate" per the assignment, and a full physics-tick (60 Hz) rate roughly doubles cost
again for a difference no player will feel over 50 ms. `bench_territory.gd`'s existing
200-circle numbers (3.5–6 ms observed) leave headroom at either rate; re-measure at 20 Hz
and raise `solve_hz` back down **in the resource** if the budget doesn't hold, per the
project's established pattern (`TerritoryTuning.hash_cell_size`'s own history).
`raster_upload_hz` (5 Hz, purely visual) is unaffected.

## Goal-flag no-build zones

Replace the "hole opens where two territories overlap" reading of §2.2's "hole" mechanic
entirely (under the default rules) with a static, per-goal-flag no-build disc:
`TerritoryTuning.goal_zone_radius` (new field, default 4.0 m — comparable to a couple of
cube widths around the flag pole, `# DECISION`, tune freely). No player may place a block
whose validity point falls inside any goal flag's zone; **ownership/area is unaffected** —
a player's territory can and must extend *through* a goal's zone to capture it (see "Owner
questions" below for the one genuine ambiguity this raises).

Zones are static for a match (goal flag positions never move), so they're rasterized once,
not every tick.

## Placement validity — one raycast, one point test

Owner: *"just do a raycast from the middle of the ghost block and straight down... has to
be inside your own area of influence and not within the goal flags' area of influence...
no cell footprint tests."*

- **`Field.raycast_down_disk_local(world_origin: Vector3) -> Variant`** (new, additive —
  the **only** change to `Field.gd` in this plan): casts straight down in **world space**
  from `map_def.cell_wake_height` above `(world_origin.x, world_origin.z)` to
  `tuning.kill_plane_y`, against the live physics world (the disk and every resting
  block), and returns the hit point converted through `disk_local_from_world()`, or `null`
  if nothing was hit (only possible off the rim with nothing beneath). Deliberately
  **independent of however the ghost itself got positioned** — `PlayerController`'s own
  ghost-follow raycast can be a raking camera- or gamepad-ray that grazes the side of a
  tower; the *legality* ray always asks "what is directly beneath the ghost's current
  world position," which is what the owner's words describe and removes any mismatch
  between where the ghost visually sits and what decides validity.
- **`PlacementRules.validate_point(point: Vector2, raster: TerritoryRaster, team_id: int) -> Result`**
  (new): off the disk → `OFF_DISK`; inside a goal zone → new `Result.GOAL_ZONE`; owned by
  a different team → `OUTSIDE_TERRITORY`; else `VALID`. One cell lookup (`raster.grid()`,
  `raster.team_at()`, new `raster.is_goal_zone()`), not a footprint scan.
- **`PlacementRules.closest_valid_point(desired, raster, team_id, tuning) -> Vector2`**
  (new): the owner's "sample the field on a ring/grid around the cursor" auto-drop
  relocation — same widening-ring geometry as the existing `closest_valid_origin`
  (`auto_drop_search_step`/`auto_drop_search_max_radius`, both reused unchanged), testing
  one point per candidate via `validate_point` instead of a rotated multi-cell footprint.
  No physics re-raycast per candidate — ownership at a candidate point is pure math once
  the raster is filled.
- Both **kept, unchanged**, for the legacy hole mode: `footprint_cells`, `validate`,
  `closest_valid_origin`, `Result.CONTESTED`/`HOLE`, `REASON_CONTESTED`/`REASON_HOLE`.

`Match.request_place()`/`preview_placement()` branch on
`config.hole_mode == MatchConfig.HoleMode.OFF` (v2, default): raycast via `Field`, then
`validate_point`/`closest_valid_point`. Otherwise (legacy): the existing footprint path,
byte-identical to today. The block's spawn Y is unaffected either way — it still drops
from the ghost's own height and free-falls into place under physics, exactly as now; only
how `(x, z)` legality is decided changes. `preview_placement` runs the same raycast on
whichever machine calls it (host or a client's own local, physics-populated, frozen-body
world — freezing a body doesn't disable its collision shape, so a client's raycast against
its mirrored blocks returns the same hit a physics query would), so the ghost tint works
identically online and offline, exactly as it does today.

## Home-flag elimination (kept behavior, new trigger)

The home circle is always one of the anchored circles feeding the field, so under normal
play it always wins the argmax at its own center (`value = home_radius` there, `dist = 0`)
— unless an enemy circle is both close enough and tall enough to out-score it. New
`Match._check_home_flags_v2()`, run every v2 territory step (not event-driven, since there
is no hole-opened event under the default rules): for every living slot, look up
`raster.team_at()` at its home cell; if it isn't that slot's own team, the enemy area has
swallowed the flag — call the existing `_eliminate_slot()` (unchanged: sets
`home_flag_alive = false`, emits `Events.player_eliminated`, checks last-team-standing).
Legacy mode keeps today's hole-opened-driven `_check_home_flags(opened)` exactly as is.

## Rendering — reuse the raster/shader pipeline, don't build a new one

Owner: *"should look smooth... some kind of metaballs system... don't overcomplicate."*
The existing pipeline (cell-resolution raster → `Image.resize(..., INTERPOLATE_BILINEAR)`
upscale to `MapDef.territory_res` → shader `smoothstep` on the bilinear ramp) already
exists to do exactly this and gets materially smoother output than the current jagged
first-come stamping simply by switching what decides ownership per cell to the argmax —
the boundary itself becomes the smooth curved locus the kernel formula describes, and the
existing bilinear+smoothstep softens it further for the "metaball" look. **Recommended
over** a GPU shader that evaluates a live circle-list uniform per pixel: that needs a hard
cap on circle count (`max_circles` already exists for the solver, but a shader uniform
array cap is a second number to keep in sync, a fallback behavior to design for when it's
exceeded, and a new upload path), for a look the raster route already gets close enough to
for M-whatever's presentation bar. Flag it as a future option if the owner wants truer
metaballs later; not built here.

**`shaders/territory.gdshader`**: one new bit. `STATE_GOAL_ZONE = 4` (bit 2, distinct from
today's `STATE_CONTESTED = 1` and `STATE_HOLE = 2`, so both mode's bits coexist in one byte
without collision). Reuse the existing contested-shimmer code path, relabeled to shimmer
over goal zones instead (both communicate "something's different about this ground");
`STATE_HOLE`'s discard is untouched and simply never fires under the default rules, since
`_hole` stays all-zero when v2 fill runs. **`TerritoryOverlay.gd` needs no change at
all** — it only ever uploads whatever bytes `TerritoryRaster` hands it; it has never
interpreted a state bit itself.

**`GhostPreview.gd`**: one match-arm addition. `Result.GOAL_ZONE` joins `Result.HOLE` in
the existing hatched-tint branch (`apply_validity`/`current_state()`) — the spec's
"hatched pattern when over a hole" visual language already reads as "can't build here" for
either reason, so it's reused rather than inventing a fourth tint state or a new
`GhostTuning` field.

**HUD, `MatchNet`, `SnapshotSync`: no changes.** `HUD.set_territory_shares` only ever
consumed `Match.territory_share(team_id)` → `TerritoryRaster.team_share()`, which still
just counts `_team_ids` entries — unaffected by *how* those entries got decided.
`MatchNet.replicate_territory()` already ships `raster.owner_bytes()`/`state_bytes()` as
opaque byte diffs at `raster_diff_hz` on the reliable channel (§3.4); the v2 fill produces
those same two byte arrays in the same shape, just with different values inside them (an
argmax-decided owner byte; a state byte whose contested/hole bits stay 0 and whose new
goal-zone bit rides along like any other byte change). **What v2 should send is exactly
what it sends today** — nothing new is needed on the wire. `TerritoryRaster`'s replication
methods gain one line each (`_write_replicated_cell` also unpacks `STATE_GOAL_ZONE` into
the mirror's `_goal_zone` array) so a client's mirror answers `is_goal_zone()` correctly
too, but that is a `TerritoryRaster.gd`-internal change, not a `MatchNet`/`SnapshotSync`
one.

## Work packages

### A — Core territory & rules v2 — **opus** (algorithmic core; the argmax formula's
interaction with existing connectivity, the cut-off rule, legacy-mode byte-for-byte
preservation and replication compatibility are exactly the kind of interacting invariants
the model-routing table reserves Opus for — see M2's P1 for the precedent)

**Owns:**
`core/territory/TerritoryRaster.gd`, `core/rules/PlacementRules.gd`,
`config/TerritoryTuning.gd` + `config/territory_tuning.tres`,
`config/MatchConfig.gd` + `config/match_defaults.tres`,
`tests/unit/test_territory_raster.gd`, `tests/unit/test_placement_rules.gd`,
`tests/unit/test_win_checker.gd` (extend only), `tests/unit/test_match_config.gd`
(extend only), `tests/bench/bench_territory.gd` + `.tscn`.

**Reads only:** `core/territory/{InfluenceCircle,TerritoryGroups,TerritorySolver,CellGrid}.gd`
(unchanged, reused as-is), `core/rules/WinChecker.gd` (unchanged, reused as-is).

**`TerritoryRaster.gd` changes:**
- `update()` gains two bool parameters, not a new enum type (keeps `core/` free of any
  `MatchConfig` reference — `core/` stays pure per CLAUDE.md, and nothing here needs to
  know the lobby setting's name, only whether holes are on and whether they're permanent):
  `func update(circles, groups, delta, holes_enabled: bool, permanent_holes: bool) -> void`.
  `holes_enabled == false` (the v2/default path) runs the new `_fill_v2()`
  (below) and skips `_advance_timers()` entirely — `_hole`/`_contested_time` stay all-zero,
  so `holes_opened()`/`holes_closed()` are always empty and `is_hole_index()`/
  `is_contested()` always read false. `holes_enabled == true` runs exactly today's
  `_stamp()`-based fill (rename to `_fill_legacy()` for clarity, no behavior change) plus
  `_advance_timers(delta, permanent_holes)`, byte-for-byte as now.
- New `_fill_v2(circles, groups)`: same bounding-box row-scan geometry as today's
  `_stamp()` (a circle only ever visits cells inside its own radius — no change there),
  but the per-cell decision is `kernel_value = circle.radius - dist`; keep whichever
  circle scores highest per cell in a new scratch `_best_value: PackedFloat32Array`
  (`-INF` at the start of every `_fill_v2()` call), writing that circle's `group`/`team`
  into `_group_ids`/`_team_ids` exactly as `_stamp()` already does, maintaining
  `_team_counts` the same way (increment the new owner, decrement whichever team, if any,
  previously held that cell). `TerritoryGroups.CONTESTED` is never written by this path.
- New `set_goal_zones(positions: PackedVector2Array, radius: float) -> void`: stamps a
  persistent `_goal_zone: PackedByteArray` (same row-scan helper, reused, since a goal
  zone is geometrically just another circle) — called once per match, not per tick.
  `is_goal_zone(cx, cy)` / `is_goal_zone_index(index)` accessors, parallel to
  `is_hole`/`is_hole_index`. `reset()` clears `_goal_zone` and `_best_value` too.
- `state_bytes()`: OR in `STATE_GOAL_ZONE = 4` (new const) from `_goal_zone`, alongside
  the existing `STATE_CONTESTED`/`STATE_HOLE` bits (which simply stay 0 under v2).
- `_write_replicated_cell()`: one added line, unpack `STATE_GOAL_ZONE` into `_goal_zone`
  on the mirror. No other replication method changes — `apply_replicated_state`/
  `_diff`/`REPLICATED_GROUP` semantics are untouched.

**`PlacementRules.gd` changes:** add `Result.GOAL_ZONE` (appended, so existing ordinals
for `OUTSIDE_TERRITORY`/`CONTESTED`/`HOLE`/`OFF_DISK`/`EMPTY` don't move — nothing depends
on the new value's position since it's never combined via the legacy "worst of many cells"
`maxi` reduction, only produced by the new single-point path), `REASON_GOAL_ZONE`,
`validate_point()`, `closest_valid_point()` (both described above). Keep
`footprint_cells`/`validate`/`closest_valid_origin`/`Result.CONTESTED`/`HOLE`/
`REASON_CONTESTED`/`REASON_HOLE` **entirely unchanged**, for the legacy path.

**`MatchConfig.gd` changes:** `enum HoleMode { TEMPORARY, PERMANENT, OFF }` — **append**
`OFF` at the end (`= 2`), do **not** reorder the existing two values. `# DECISION`:
appending instead of inserting-and-renumbering means any already-serialized raw int
(`.tres` files, saved lobby presets) that says `0` or `1` keeps meaning exactly what it
meant before; only the *default* changes, from `HoleMode.TEMPORARY` to `HoleMode.OFF`.
Verify `config/match_defaults.tres`'s stored `hole_mode` value explicitly after this change
— if it was written out as a literal `0`, it needs to become `2` (or be removed so the
new GDScript default applies); `sanitize()`'s `clampi(hole_mode, HoleMode.TEMPORARY, HoleMode.OFF)`
stays a valid 0..2 clamp regardless of which end `OFF` is tested against.

**Tests first**, each pinning one owner bullet or invariant:
- **Argmax never overlaps:** two same-radius circles of different teams at any positive
  distance apart never both claim the midpoint; exactly one team owns every in-range cell.
- **Border pushed proportionally:** two circles of radius `r1 > r2` at distance `d < r1 + r2`
  — the boundary along the line between centers sits at `(d + r1 - r2) / 2` from circle 1
  within one cell's tolerance, not at the midpoint and not entirely at circle 2's center.
- **Individual stacks, not a team sum:** a team with five small, far-apart circles near an
  enemy's one tall circle never wins a cell none of those five individually reaches, even
  though their combined "total height" would exceed the enemy's if summed.
- **Cut-off circles are excluded from area, not just the win check:** build home–A–B (A, B
  same team, overlapping, B far taller/bigger), sever A from home; on the next `_fill_v2`
  cells that were B's now read unowned or the rival's — mirrors
  `test_territory_solver.gd`'s existing cut-off case, but asserts on the raster's owner
  byte, not the solver's group membership.
- **Legacy path is byte-identical to before:** every existing `test_territory_raster.gd`
  case (contested cells, `hole_delay`, `hole_mode` TEMPORARY/PERMANENT open/close) still
  passes unchanged, called through the new two-bool `update()` signature with
  `holes_enabled = true`.
- **Goal zones:** `set_goal_zones` marks exactly the cells within `goal_zone_radius`;
  `state_bytes()` carries `STATE_GOAL_ZONE` there and nowhere else; a v2-owned cell inside
  a goal zone still reports its real owner via `team_at()` (zones don't affect ownership).
- **`validate_point`/`closest_valid_point`:** off-disk → `OFF_DISK`; inside a goal zone →
  `GOAL_ZONE` even when the point is also inside the caller's own owned area (zone check
  wins); wrong-team cell → `OUTSIDE_TERRITORY`; `closest_valid_point` returns `desired`
  unchanged when already valid, the nearest valid ring point otherwise, `NO_ORIGIN` once
  `auto_drop_search_max_radius` is exhausted (mirrors `closest_valid_origin`'s cases).
- **`MatchConfig` round-trip:** `HoleMode.OFF` is the default on a fresh `MatchConfig`;
  `to_dict`/`from_dict` round-trips all three values by their (new, stable) int; a raw
  `0`/`1` arriving over the wire or from an old save still sanitizes to
  `TEMPORARY`/`PERMANENT`, never silently becoming `OFF`.

**Acceptance:** all of the above pass; `bench_territory.gd` reports the v2 fill's
solve+raster+win time for 200 circles on map M at the new `solve_hz` (20 Hz → 50 ms
available), against the **same 8 ms budget** as before — if missed, raise
`hash_cell_size`/lower `solve_hz` **in the resource**, report the numbers, exactly as the
M2 precedent allows; also report the legacy-fill row unchanged, as a regression guard.

**Must NOT:** reference `MatchConfig`, `Events`, the scene tree, or anything under
`game/`/`net/` from `core/`. No `push_error` in any hot path. Do not touch
`TerritorySolver.gd`, `TerritoryGroups.gd`, `InfluenceCircle.gd`, `WinChecker.gd`,
`CellGrid.gd`, `game/Field.gd`, or `MapDef.gd` — none of them need to change for this
package, and touching them would blur package B's ownership.

### B — Match integration & the one `Field` raycast — **sonnet** (mechanical wiring
against A's interfaces, plus one bounded physics-query method; not the kind of interacting
invariant design A is)

**Owns:** `autoload/Match.gd`, `game/Field.gd` (one additive method only — see below),
`tests/unit/test_match_flow.gd` (extend only), `tests/unit/test_field.gd` or a new
`tests/unit/test_field_raycast.gd` (new, small — covers only the new method).

**Reads only:** everything package A owns/produces, `core/territory/{TerritorySolver,
TerritoryGroups,InfluenceCircle,CellGrid}.gd`, `core/rules/{WinChecker,PlayerSlot}.gd`,
`game/BlockRegistry.gd` (unchanged, reused for `influence_circles()`).

**`Field.gd`** gains exactly one method, `raycast_down_disk_local(world_origin: Vector3) -> Variant`
(described above under "Placement validity"). Nothing else in `Field.gd` changes —
its cell/hole/kill-plane/overlay/flag code is all reused verbatim by the legacy path and
untouched by the default one.

**`Match.gd` changes:**
- `_build_territory()`: after building `_raster`/`_win_checker`, call
  `_raster.set_goal_zones(goal_positions, _territory_tuning.goal_zone_radius)` **only**
  when `config.hole_mode == MatchConfig.HoleMode.OFF` — legacy mode must stay byte-
  identical to the pre-v2 game, which never had goal zones.
- `request_place()`/`preview_placement()`: branch on `config.hole_mode == MatchConfig.HoleMode.OFF`.
  v2: `_field.raycast_down_disk_local(origin)` → on a hit, `PlacementRules.validate_point()`;
  on a miss, treat as `Result.OFF_DISK`. Auto-drop relocation calls
  `PlacementRules.closest_valid_point()` from the hit point (or `origin`'s flat projection
  if the raycast missed). Legacy: exactly today's `footprint_cells`/`validate`/
  `closest_valid_origin` call chain, unchanged. The final spawn transform logic (burn-
  clamping, `_spawn_block`, `_consume_and_refeed`) is untouched either way — only how
  `(x, z)` validity and relocation are decided branches.
- `_run_territory_step()`: `_raster.update(circles, groups, delta, config.hole_mode != MatchConfig.HoleMode.OFF, config.hole_mode == MatchConfig.HoleMode.PERMANENT)`.
  After that call, branch: v2 → new `_check_home_flags_v2()` (every step, described
  above); legacy → today's `holes_opened()`/`holes_closed()` → `Events.hole_cells_changed`
  → `_check_home_flags(opened)` chain, unchanged.
- New `_check_home_flags_v2()` (described above under "Home-flag elimination").

**Tests first:**
- `raycast_down_disk_local`: hits the bare disk at its own `(x, z)` when nothing is
  stacked there; hits the top of a resting block when one is; returns `null` well past the
  rim with nothing beneath; independent of the ghost's *own* hover raycast direction (cast
  straight down even when the caller's world_origin came from an angled ray elsewhere).
- `request_place` (v2): a point inside the caller's own owned area and outside every goal
  zone spawns; a point inside another team's area or inside a goal zone burns the block
  (existing burn/relocate machinery, exercised through the new validity path) — same
  assertions `test_match_flow.gd` already makes for the legacy path, mirrored for v2.
- `_check_home_flags_v2`: a slot's own home cell reads that slot's team while unchallenged;
  once an overlapping enemy circle's kernel value exceeds `home_radius` at the home
  position, the next territory step eliminates it and `Events.player_eliminated` fires;
  last-team-standing still ends the match, unchanged from today's test.
- Legacy-mode regression: `test_match_flow.gd`'s existing hole-driven elimination test
  still passes untouched with `MatchConfig.hole_mode = MatchConfig.HoleMode.TEMPORARY`.

**Acceptance:** a headless test drives `Match` Lobby-to-win entirely through
`request_place()` under v2 rules (`hole_mode = OFF`, the new default), with a bare `Field`
in the tree (the raycast needs a real physics world, unlike M2's rule-only harness) —
mirrors M2's P2 acceptance shape, extended to need physics.

**Must NOT:** touch anything package A owns, `game/GhostPreview.gd`, `game/PlayerController.gd`,
`shaders/`, `ui/`, `net/`, `Main.*`. Never re-derive a rule `core/` already answers —
call into A's functions.

### C — Presentation: shader bit, ghost tint — **sonnet** (small, independent of B; can
start as soon as A's `Result.GOAL_ZONE` and `STATE_GOAL_ZONE` land, even before B merges)

**Owns:** `shaders/territory.gdshader`, `game/GhostPreview.gd`,
`tests/unit/test_ghost_tint.gd` (extend only).

**Reads only:** package A's `PlacementRules.Result`/`TerritoryRaster` state-bit constants.

**Work:** shader gains `STATE_GOAL_ZONE = 4` and relabels the existing contested-shimmer
code path to run for it too (described above); `GhostPreview.apply_validity()`/
`current_state()` add `Result.GOAL_ZONE` to the existing hatched branch.

**Tests first:** `GhostPreview.current_state()` returns the hatched state for
`Result.GOAL_ZONE` exactly as it already does for `Result.HOLE`; `current_tint_color()`
for `GOAL_ZONE` matches `ghost_tuning.hole_tint_color` (reused, no new tuning field).
Shader correctness itself is not GUT-testable headlessly (no renderer) — same as today's
`territory.gdshader`, which has no dedicated shader test; verify by a windowed manual run
(below) instead.

**Must NOT:** touch `TerritoryOverlay.gd` (needs no change — see "Rendering" above),
`Field.gd`, `Match.gd`, `core/`.

## Integration order

1. **Package A lands first**, fully (not just stubs) — it is self-contained `core/` +
   `config/` with no scene-tree dependency, so it is independently testable end to end
   before anyone else needs it, the same reason M2's P1 landed first. Publish its final
   signatures (`TerritoryRaster.update()`'s new two-bool shape, `PlacementRules.validate_point`/
   `closest_valid_point`, `MatchConfig.HoleMode.OFF`, `TerritoryTuning.goal_zone_radius`)
   as soon as they compile, so B and C can start against them immediately even before A's
   own tests are all green.
2. **B and C build in parallel** off A's landed commit — disjoint files, and C depends only
   on A's enum/const additions, not on B's `Match`/`Field` wiring. Each merge passes
   `godot --headless --editor --path . --quit` (no errors, no new warnings) and the full
   GUT suite before the next lands, same gate as every prior milestone.
3. **No integrator step is needed for `Main.tscn`/`project.godot`** — this plan adds no new
   scene, node or autoload; B's one `Field` method and `Match.gd` branch, and C's shader/
   ghost changes, all slot into scenes and autoloads that already exist and are already
   wired. The orchestrator's integration pass is: merge A → B → C in that order, run the
   full suite once combined, then the manual/harness pass below.
4. **Manual pass, single PC:** hot-seat or 2-instance run confirming (a) a circle visibly
   shrinks the instant a stack topples, not on the next placement; (b) two adjacent
   players' areas visibly push against each other with a curved, non-overlapping border
   that moves toward the shorter stack as one side builds higher; (c) placing inside a
   goal's zone is refused with the hatched tint even when the spot is otherwise the
   player's own territory; (d) a connected tower touching every goal flag's base wins after
   `capture_hold`; (e) an enemy area engulfing a player's home flag eliminates them; (f) a
   debug run with `hole_mode` explicitly set to `TEMPORARY` reproduces the old
   contested/hole visuals and physical hole-through behavior unchanged, proving the legacy
   path is intact.
5. **`tools/run_m3a_local.ps1 -Peers 4`** (unchanged tool) re-run under the new default
   rules, confirming replication needed no changes — the acceptance criteria it already
   checks (no duplicated/lost placements, raster convergence) are exactly what still needs
   to hold with the v2 fill's bytes flowing through the same pipe.

## Tunables — where every number lives (CLAUDE.md: nothing below may be a literal in code)

| Resource | Owner | New/changed |
|---|---|---|
| `territory_tuning.tres` | A | `solve_hz` 10.0 → **20.0** (DECISION, re-measure and adjust); new `goal_zone_radius` 4.0. Everything else (`influence_base`/`k`/`max_fraction`, `home_radius`, `max_circles`, `hash_cell_size`, `hole_delay`, `hole_close_delay`, `max_cell_toggles_per_frame`, `capture_hold`, `auto_drop_search_step`/`max_radius`, `reject_impulse`/`upward_fraction`) **unchanged** — the legacy path still needs every hole-related one exactly as is. |
| `match_defaults.tres` | A | `hole_mode` default becomes `HoleMode.OFF` (verify the stored raw int after the enum append — see the `MatchConfig.gd` DECISION above). |
| `ghost_tuning.tres` | C | none new — `hole_tint_color` reused for `GOAL_ZONE`. |
| `maps/*.tres` | unchanged | no new fields; `goal_zone_radius` lives in `TerritoryTuning`, not per-map, matching `home_radius`'s existing precedent (a flat rule number, not a map-geometry fraction). `# DECISION`. |

## Retired vs. kept

- **Retired from the default ruleset, kept compiled+tested behind `hole_mode != OFF`:**
  `Field.set_hole_cells`/`_hole_applied`/`_hole_wanted`/toggle backlog, `is_hole_cell()`,
  `Events.hole_cells_changed`, `TerritoryRaster`'s contested-time/hole state machine
  (`_contested_time`, `_idle_time`, `hole_delay`, `hole_close_delay`,
  `holes_opened()`/`closed()`), `PlacementRules.footprint_cells`/`validate`/
  `closest_valid_origin`, `Result.CONTESTED`/`HOLE`. All of `test_field_cells.gd`
  (including the pending lone-hole case, `Bontago-ruw`) keeps passing/pending exactly as
  today, now exercising a mode instead of the only mode.
- **Retired outright (no gameplay path produces it anymore):** nothing is deleted; even
  `TerritoryGroups.CONTESTED` stays defined and meaningful, just legacy-only now.
- **Unchanged, reused as-is:** `TerritorySolver`, `TerritoryGroups`, `InfluenceCircle`,
  `CellGrid`, `WinChecker`, `BlockRegistry.influence_circles`/`_top_height_local`,
  `TerritoryOverlay.gd`, `HUD.gd`, `net/MatchNet.gd`, `net/SnapshotSync.gd`, all of
  `Field.gd` apart from the one new method.

## Owner questions — genuine ambiguity only

> **Orchestrator decision 2026-09-20 (minor ambiguity, no owner pause):** goal-flag zones block
> placement only, never influence — the owner's text says "no blocks are allowed to be placed",
> and blocking influence would make the flag base uncapturable. Recorded as a `# DECISION` in
> package A. Package C's acceptance additionally includes a windowed screenshot review of the
> smoothness of the territory edge; if the owner still finds it jagged, the fallback is a shader
> that evaluates the circle list directly (bounded by `max_circles`).

1. **Do goal-flag no-build zones also block *influence*, or only placement?** Built here:
   **placement-only** — a zone stops a block from being dropped there, but a player's
   argmax-owned area can and must extend through/over it, because winning requires the
   zone's own flag base to be *inside* that owned area. Blocking influence too would make
   the zone permanently unowned by anyone and the flag uncapturable, which cannot be what
   "capture the goal flags" means. This reading seems structurally forced rather than a
   real 50/50 choice, but it does change what "no-build zone" visually looks like in play
   (territory tint *will* cover the shimmering zone once a player's area reaches it), so
   flagging it rather than assuming it's uncontroversial.

## What I could not determine by reading

- **Exact visual "feel" of the metaball look** (how blurry/tight the edge should read, how
  strongly the outline should pulse near a contested border) is a presentation judgment
  call, not a rules one — `TerritoryVisuals.edge_softness`/`outline_*` are already tunable
  and untouched by this plan; tune them by eye once B/C land, no plan-level decision
  needed.
- **Whether `solve_hz = 20` actually clears `bench_territory.gd`'s budget** on the
  reviewer's/owner's actual machine — I can read the last recorded numbers but can't run
  the benchmark from here; package A's acceptance step must re-measure.

## Reconciled 2026-09-20 (Bontago-cmc.7)

SPEC.md's evidence audit reads the installed original's own tutorial text as confirming
overlap sinking (`docs/ORIGINAL_INSTALL_EVIDENCE.md`), which the "two decisions the
owner/orchestrator have already settled" note above (no floor holes by default) directly
contradicted. The audit's "Decisions made — current target" resolves that conflict in
the original's favor: `MatchConfig.hole_mode` defaults to `TEMPORARY` again; `OFF` (this
whole plan's argmax ruleset) is the optional no-overlap mode. What that changes, and what
it does not:

- **Now mode-independent (every `hole_mode`, not just `OFF`):**
  - **Placement legality.** `autoload/Match.gd`'s `request_place()`/`preview_placement()`
    no longer branch on `hole_mode` at all: both always cast the one downward raycast and
    call `PlacementRules.validate_point()`. `footprint_cells()`/`validate()`/
    `closest_valid_origin()` stay compiled, but only `tests/bench/bench_territory.gd`'s
    legacy row and their own direct unit tests (`tests/unit/test_placement_rules.gd`) call
    them now — no live code path reaches them under any mode.
  - **`validate_point()` itself.** Extended to check `raster.is_hole()`/`is_contested()`
    before falling back to `team_at()`, so a contested or holed point now returns
    `Result.HOLE`/`Result.CONTESTED` instead of the generic `OUTSIDE_TERRITORY` it used to
    report for every non-`OFF` mode. Under `OFF` this is a no-op: `_fill_v2()` never sets
    either flag, so the check always falls through exactly as before.
  - **Goal-flag no-build zones.** `_build_territory()` calls `TerritoryRaster.
    set_goal_zones()` unconditionally now, not only when `hole_mode == OFF`. Zones still
    only ever block placement (`validate_point()`'s `GOAL_ZONE` case); they never touch
    `TerritoryRaster`'s hole state or ownership, in either fill.
  - **The continuous solve rate.** `_tick_territory()`/`_run_territory_step()` were never
    mode-conditional — `TerritoryTuning.solve_hz` (20 Hz) already drove
    `TerritoryRaster._fill_legacy()` at the same cadence as `_fill_v2()`, so contest/hole
    timers under the now-default overlap modes update every solve, not only on placement.
    No code changed here; only the doc comments (`config/TerritoryTuning.gd`) were brought
    up to date, since this rate now matters for the default mode, not only the optional one.
  - **Auto-drop relocation.** `PlacementRules.closest_valid_point()` is the one relocation
    search `request_place()` calls now, under every mode. It was already point-based and
    needed no change; only its doc comment was updated to say so and to flag SPEC.md's
    [OPEN] note that relocate-vs-lose-vs-retain is not evidenced for the original.
- **Still mode-specific, unchanged by this reconciliation:**
  - **The raster fill.** `TerritoryRaster.update()`'s `holes_enabled` argument still
    selects `_fill_legacy()` (`TEMPORARY`/`PERMANENT`) vs. `_fill_v2()` (`OFF`); this plan's
    argmax formula, tie-break and border math are exactly as designed above, just no
    longer the default caller's fill.
  - **Home-flag elimination.** `TEMPORARY`/`PERMANENT` still trigger through
    `_check_home_flags()` (a hole opening under the flag, spec 2.2's original M2 rule);
    `OFF` still triggers through `_check_home_flags_v2()` (an enemy circle outscoring the
    home circle at its own point). SPEC.md's audit flags the overlap-mode trigger as
    explicitly `[OPEN]` — "the persistent home circle prevents enemy ownership at its
    center; resolve the trigger before implementation" — and this reconciliation
    deliberately does **not** invent a new one: keeping the pre-existing, already-tested M2
    trigger is the least-invented option available, not a claim that it matches the
    original. See the `# DECISION` at its call site in `autoload/Match.gd`.
- **Known consequence, not fixed here:** `tests/bench/m2_acceptance.gd`'s scenario (d)
  (a capture at the goal flag's exact center point) can now fail under `TEMPORARY`,
  because the goal zone this reconciliation stamps for every mode blocks the scripted
  march's last step into the flag's own no-build radius. Rewriting that scenario to march
  to the zone's rim instead of the flag's center point is `Bontago-cmc.6`'s job, not this
  ticket's.
