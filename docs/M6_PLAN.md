# M6 — Modes & settings: build plan

Spec: §2.7 (Modes), §2.8 (Match settings/lobby), §2.1-2.3 (field/territory/win,
teams), §3.6 (key data resources), §3.7 (match state machine), §3.1 (graphics
presets), §1.4/§2.10 (custom music folder, controls), Part 4 "### M6 — Modes &
settings", "Decisions made", "Fidelity gaps", "Owner clarifications — 2026-09-20".
Base: `main` @ `ad20774`, clean (worktree `M:/Bontago-worktrees/m6-plan`, branch
`wt/m6-plan`). Epic: Bontago-keo, children `Bontago-keo.1` (teams) and
`Bontago-keo.2` (Field map_def bug).

**Accept (Part 4 M6):** every setting in spec §2.8 changes gameplay as
described.

## What already works vs. what is a stub — read before assigning anything

This milestone's own children already name the two headline bugs
(`Bontago-keo.1`, `Bontago-keo.2`); the rest of this table is this plan's own
audit of every §2.8 row and every §2.7 mode, each grounded in a real read, not
assumed from the setting merely existing in `MatchConfig`.

| §2.8 row / §2.7 mode | Status | Evidence |
|---|---|---|
| Map (variant) | **Stub.** `config.map_variant` round-trips through the lobby (`ui/Lobby.gd:112,214,264`) but nothing reads it: `MatchConfig.map_def()` calls `MapDef.for_size(map_size)` only (`config/MatchConfig.gd:135-136`, `config/MapDef.gd:90-97`) — no variant branch exists. `core/territory/CellGrid.is_in_disk()` is a pure circle test (`length_squared() <= field_radius^2`, `core/territory/CellGrid.gd:103-104`) with no shape concept at all. |
| Map size | **Half-stub (Bontago-keo.2).** `Match.config.map_def()` is correct everywhere it's read (`BlockRegistry.gd:57`, `MatchTerritory.gd:74`, `SnapshotSync.begin_match`, win check) *except* `game/Field.gd`, which bakes its cells/kill-plane/overlay from its own `@export var map_def` (`game/Field.gd:59`, defaults to `round_medium.tres`), never overwritten by `game/Main.gd` (confirmed by grep: `Main.gd` reads `config.map_def()` only for `_skybox.load_set()`/`SnapshotSync.begin_match()`, never assigns it to `_field.map_def`). `_field` is a scene child (`@onready var _field: Field = $Field`, `Main.gd:69`) whose `_ready()` — and therefore `_build_cells()` — has already run by the time `Main._ready()`/`_build_match_world()` gets a sanitized config, so a later property write alone would not rebuild anything. |
| Players / AI / difficulty | **Works** (M5). |
| Teams (Bontago-keo.1) | **Stub, but everything downstream is already team-aware and just waiting for real numbers.** `MatchConfig.team_count()` returns `player_count`; `team_of_slot(slot_id)` returns `slot_id` (`config/MatchConfig.gd:145-151`) — free-for-all only. Every consumer already branches on `team_id`, not `slot_id`: `core/territory/TerritorySolver.gd` unions circles by `circle.team_id` (lines 159-161, 307, 320, 392); `core/rules/WinChecker.gd` reads `raster.team_at()` and compares teams, never slots (`_team_at()`, line 145-147); `MatchLifecycle._check_last_team_standing()` groups by `slot_item.team_id` (`autoload/match/MatchLifecycle.gd:407-413`); `MatchTerritory.gd:162` loops `range(_match.config.team_count())`; `net/MatchNet.gd:939` (`_team_shares()`) loops the same; `MatchLifecycle._build_slots()` already calls `_match.config.team_of_slot(i)` to set `PlayerSlot.team_id` (`MatchLifecycle.gd:316`); `game/BotController.gd` already reads `match_ref.team_of(_slot_id)` and computes "every other team's home" for its risk/target scoring (`BotController.gd:196,352,532-546`). Fixing two functions on `MatchConfig` is most of this ticket. |
| — found while reading keo.1: a real latent bug in gift claiming | `autoload/match/MatchGifts._claim_gift(gift_id, team_id)` pushes onto `_pending_queues[team_id]` (`MatchGifts.gd:434-445`), but `held_special(slot_id)`, `pop_pending_special(slot_id)`, `pending_special_count(slot_id)` and `debug_queue_special(slot_id, ...)` all index the same array **by `slot_id`** (`MatchGifts.gd:132-138,157-163,169-175,204-213`). Free-for-all hides this because `team_id == slot_id` today; the moment keo.1 makes them differ, a teammate whose `slot_id != team_id` reads an empty queue for a special their team actually claimed. This is a real regression keo.1 must not introduce, not a new feature — folded into the teams package below. |
| Block timer | **Works** (`MatchFeed._tick_feed()`/`_consume_and_refeed()` already read `config.block_timer`, `autoload/match/MatchFeed.gd:139,168,232` etc.). |
| Gravity | **Works** — `MatchLifecycle` writes `config.gravity_multiplier` into `PhysicsTuning` at match start (`MatchLifecycle.gd:105-115`), read by every `Block`/`BlockFactory` (`game/Block.gd:254`, `game/BlockFactory.gd:82`). |
| Goal flags | **Works** (`goal_flag_count` feeds `PlayerSlot.goal_positions_for()`/`WinChecker`). |
| Gifts on/off, probability per window | **Works** (M4 P1: `MatchGifts._tick_gifts()` gates on `config.gifts_enabled`; `GiftSpawner.should_spawn()` reads `config.special_frequency` scaled by `GiftConfig.frequency_to_chance_max`, `MatchGifts.gd:300`, `config/GiftConfig.gd:22-23`). |
| Enabled specials checklist + type weights | **Rule logic works, lobby UI does not exist.** `MatchGifts._draw_special_id()` already filters `SpecialDef.load_all_specials()` by `_match.config.enabled_specials` (`MatchGifts.gd:325,336-337`); the lobby has no checkboxes at all, only a static `%SpecialsNote` label (`ui/Lobby.gd:54,282-285`; confirmed no `CheckBox`/`ItemList` node in `ui/Lobby.tscn`). |
| Tilt mode | **SPECIALS_ONLY works** (M4 P0b). **PHYSICAL_BALANCE is an explicit stub** — `Field.gd`'s own header says so ("`PHYSICAL_BALANCE` tilt (a RigidBody3D on a joint) is M6 scope, out of this package", `game/Field.gd:9-10`), and `MatchConfig.sanitize()`/`TiltMode` accept the value but nothing reads it differently. |
| Hole mode | **Works** (TEMPORARY/PERMANENT/OFF all live, M4/v2). |
| Match timer | **Stub.** `grep` for `match_timer_minutes`/`sudden_death` outside `config/MatchConfig.gd` and `ui/Lobby.gd` returns nothing — no code reads either field. |
| Sudden death | **Stub, and the state machine already half-expects it.** `MatchAutoload.State` already declares `SUDDEN_DEATH` (`autoload/Match.gd:46`, matching spec 3.7's `Playing -> (SuddenDeath) -> End`), but `Match._process()`'s `match _lifecycle._state:` only branches on `COUNTDOWN`/`PLAYING` (`autoload/Match.gd:256-264`) — if anything ever set the state to `SUDDEN_DEATH`, feed/territory/disconnect-grace would all silently stop ticking. |
| Sandbox (§2.7: no timer, no territory limits, block picker, special menu, slow-mo, pause-physics, height record) | **Partial, and mis-scoped today.** `game/Sandbox.gd`/`ui/SandboxPanel.gd`/`config/SandboxConfig.gd` already exist, but only behind the unlisted `godot ... -- --sandbox` CLI flag (`game/Sandbox.gd:3-4`, `game/Main.gd:125-126`) — there is no Main Menu entry (`ui/MainMenu.gd` has no sandbox/tutorial button at all; confirmed by its full function list). `config.sandbox` today only disables the feed timer and relaxes `sanitize()`'s player-count floor (`MatchLifecycle.gd:121`, `MatchConfig.gd:187`) — it does **not** relax territory: `MatchPlacement.gd:191` calls `PlacementRules.validate_point()` unconditionally, so a sandbox match still refuses placement outside the player's own influence, contradicting spec 2.7's "no territory limits." None of the named tools (block picker, special spawn menu, slow-motion, pause-physics, height record) exist; `Sandbox.gd`'s current hotkeys are F5 reset / F7 spawn-tower-of-whatever's-held / F8 toggle overlay / F9 cycle a forced special (debug tools, not a player-facing menu). |
| Tutorial (5 steps) | **Does not exist.** No `Tutorial` file anywhere in the tree. |
| Turn-based [NEW] | **Does not exist as its own mode**, but the mechanism it needs mostly already does: `_active_slot`/`advance_turn()`/`Events.turn_changed` (`autoload/match/MatchLifecycle.gd:16,241,251,281-296`) already drive **hot-seat**'s strict single-slot alternation, triggered the instant a placement lands (`MatchPlacement.gd:276-277,382-383` call `_match.advance_turn()` right after a successful place/throw when `config.hot_seat`). Spec Part 4 M2 is explicit that hot-seat is a historical test harness, not the target cadence ("must not become normal play") — turn-based's own rule ("physics settles completely... before the next player's turn starts") is a materially different trigger (a wait, not an instant hand-off), so this needs a new `turn_based` flag and a settle-wait state, reusing the existing active-slot plumbing rather than repurposing `hot_seat`. |
| User settings (graphics presets, key rebinding, audio, custom music folder) | **`autoload/Settings.gd` is a registered but empty autoload.** `project.godot:26` lists `Settings="*res://autoload/Settings.gd"`; the file itself is a 4-line doc comment with no code (`autoload/Settings.gd`). No `ui/Settings.tscn`/options menu exists. `autoload/Sfx.gd._resolve_root_dir()` is hardcoded to the bundled `assets/original/audio` folder (`Sfx.gd:54-56`) — no custom-folder override anywhere. `game/Main.tscn`'s `WorldEnvironment` already has `ssr_enabled = true` (line 19) to toggle; SSIL/volumetric fog do not exist as render features yet (M7 scope), so a "Low preset" can only toggle what M6 actually has (SSR, MSAA, shadow/vsync) — noted as a limitation, not a shortfall of this plan. |

## Shared-file hotspots — read before dispatching two workers

Per `docs/AGENT_WORKFLOW.md` ("file ownership over function ownership... split
any other shared file the same way before dispatching two writers"), the
following files are touched by more than one package below. **Do not dispatch
two of these in parallel**; the dependency edges in each package description
already serialize them, but flagging the file itself here is the fast way to
check a new worktree isn't starting from a stale base:

- `game/Field.gd`: A0 only (map bake + shape mechanism), later B5 (PHYSICAL_BALANCE) appends to it — B5 depends on A0 committed.
- `game/Main.gd`: A0 (map rebuild call), B1 (Sandbox menu entry point) — B1 depends on A0 committed.
- `config/MatchConfig.gd`: A1 only (teams + map_def() routing + `turn_based` field). No other package edits this file; B4 (turn-based behavior) only *reads* the field A1 adds.
- `autoload/match/MatchGifts.gd`: A1 (team-index fix), A3 (sudden-death gift ramp) — A3 depends on A1 committed.
- `autoload/match/MatchLifecycle.gd`: A3 (sudden death), B4 (turn-based settle-wait), B5 (tilt-mode wiring) — dispatch strictly in that order (A3 → B4 → B5), each starting from the previous one's commit.
- `autoload/match/MatchTerritory.gd`: A0 (CellGrid.new call site), A3 (shrink punches) — A3 depends on A0 committed.
- `game/BlockRegistry.gd`: A0 (CellGrid.new call site), B4 (`all_settled()` aggregate) — B4 depends on A0 committed.
- `ui/MainMenu.gd`/`.tscn`: B1 (Sandbox button), B3 (Tutorial button), C2 (Options button) — dispatch strictly in that order.
- `config/tuning_panel_hints.tres`: not touched by any package below — every new tunable this milestone introduces lives on a resource the F4 panel does **not** show (`MapDef`, `TiltTuning`, `GiftConfig`, `GraphicsPreset`, `SandboxConfig`, `TutorialConfig` are absent from `ui/TuningPanel.gd:65-69`'s five-tab list: `CameraTuning`, `GhostTuning`, `PhysicsTuning`, `TerritoryTuning`/`TerritoryVisuals`, `BlockFeedConfig`), so `docs/AGENT_WORKFLOW.md`'s hints-file rule does not apply this milestone. Called out explicitly so no implementer goes looking for a tab that shouldn't exist.

## M6a — settings that exist become real

### A0 (P0, blocks every other map-related package) — Field bakes the real map (Bontago-keo.2) + the map-shape mechanism (map variants' interface stub)

**Owns:** `game/Field.gd`, `game/Main.gd`, `game/BlockRegistry.gd`,
`autoload/match/MatchTerritory.gd`, `core/territory/CellGrid.gd`,
`config/MapDef.gd`, `tests/unit/test_field_map_def.gd` (new),
`tests/unit/test_cell_grid.gd` (append), `tests/unit/test_map_def.gd` (new).
9 files. **Reads only:** nothing new.

**keo.2 fix, concretely.** `_build_cells()` (`Field.gd:392-460`) creates one
`ConcavePolygonShape3D` shape owner (`create_shape_owner(self)`, no matching
`remove_shape_owner` anywhere) and is only ever called from `_ready()`
(`Field.gd:159`). Split its body into a private `_rebuild_cells()` callable
more than once (freeing the previous `_disk_owner_id` via
`remove_shape_owner()` first, and resetting `_grid = null` so `grid()`
rebuilds `CellGrid` against the new `map_def`), and add a public
`rebuild_for_map(new_map_def: MapDef) -> void` that sets `map_def =
new_map_def`, re-runs `_rebuild_cells()`, frees and rebuilds the kill-plane
`Area3D` (`_build_kill_plane()`, `Field.gd:960-968` — cheap, and the only
existing per-shape-agnostic geometry: `span = map_def.field_radius *
KILL_PLANE_RADIUS_FACTOR`), and calls `_overlay.configure(map_def, visuals,
territory_tuning)` again — `TerritoryOverlay.configure()`/`rebuild_disk_mesh()`
already take `map_def` as a parameter and rebuild their `CylinderMesh` from it
(`game/TerritoryOverlay.gd:118,134-152`), so this needs no change of its own.
`game/Main.gd` calls `_field.rebuild_for_map(config.map_def())` at all three
existing call sites that already call `_field.place_flags(...)` +
`_field.set_overlay_source(...)` together (`Main.gd:169-171, 211-213,
586-591`), right before `place_flags()` (which reads `map_def`-derived
positions).

**The map-shape mechanism, concretely (this is what makes non-Round map
variants possible at all — the interface-stub other A2a/A2b packages need).**
`CellGrid.is_in_disk(cx, cy)` is the one predicate 17 files already depend on
(`grep` confirms: `TerritoryRaster`, `MatchTerritory`, `PlacementRules`,
`GiftSpawner`, `Field`, plus a dozen tests) and every one of them calls it as
a pure yes/no gate — none of them assume it's a circle. Add an **optional**
third constructor parameter, `p_shape_test: Callable = Callable()`
(`CellGrid._init(p_field_radius, p_cell_size, p_shape_test)`, `CellGrid.gd:49`),
consulted by `is_in_disk()` only when non-empty (`is_in_disk()` still runs its
existing circle test as the fallback, `CellGrid.gd:103-104` unchanged) — every
one of the dozen `CellGrid.new(radius, cell_size)` two-argument call sites
(tests included) keeps compiling and behaving byte-identically; this is
strictly additive. `config/MapDef.gd` gains:
```gdscript
enum MapShape { ROUND, OVAL, RING, TWIN, CROSS }
@export var map_shape: MapShape = MapShape.ROUND
## Oval: ellipse aspect ratio (x-radius = field_radius, z-radius = field_radius * oval_aspect).
@export var oval_aspect: float = 0.65
## Ring: no-disk hole in the middle, and the single goal flag sits on a bridge (spec 2.1).
@export var ring_hole_radius_fraction: float = 0.35
@export var ring_bridge_half_width: float = 3.0
## Twin: two same-size disks, centers this far apart on +/-x, joined by a bridge.
@export var twin_separation: float = 1.6   # multiple of field_radius
@export var twin_bridge_half_width: float = 3.0
## Cross: four arms this wide (fraction of field_radius) cut from a square bound.
@export var cross_arm_half_width_fraction: float = 0.4

func shape_contains(local: Vector2) -> bool:  # pure, per-variant geometry
    ...
func shape_test() -> Callable:
    return Callable(self, "shape_contains") if map_shape != MapShape.ROUND else Callable()
static func for_variant_and_size(variant: MapVariant, size: MapSize) -> MapDef: ...
```
(`MapVariant` is `MatchConfig.MapVariant`, already `ROUND/OVAL/RING/TWIN/CROSS`
— `config/MatchConfig.gd:11`; `MapDef.gd` cannot import `MatchConfig` without
a cycle per its own existing note at `MapDef.gd:8-11`, so
`for_variant_and_size` takes the same raw `int`/enum-compatible value
`MatchConfig.map_variant` already is, matching how `for_size(size: MapSize)`
already takes `MatchConfig.map_size`'s raw enum value today.) `ROUND` returns
`for_size(size)` unchanged (byte-identical to today for every existing
caller). The three production `CellGrid.new(map_def.field_radius,
map_def.cell_size)` call sites (`Field.gd:178`, `BlockRegistry.gd:57`,
`MatchTerritory.gd:74`) each gain the third argument:
`map_def.shape_test()`. `MatchConfig.map_def()` itself is **not** touched
here — A1 owns that one-line change (`for_variant_and_size` needs to exist
first, which is exactly why A1 depends on A0).

**`# DECISION` (config/MapDef.gd):** Ring's goal-on-a-bridge and Twin's
dual-disk-plus-bridge need `home_flag_position()`/`goal_flag_positions()`
overrides distinct from the circular-fraction formula every other variant
reuses (`MapDef.gd:113-139`); this package adds the override branches (keyed
on `map_shape`) since it already owns `MapDef.gd`, even though the *data*
(which numbers) ships with A2a/A2b's own `.tres` resources. Cross reuses the
existing symmetric ring formula for goal flags (extra goals still make sense
on a ring inscribed in the cross) and places home flags on the cross's own
arm tips rather than a circle — the simplest symmetric reading, not a rule
Concern; noted as a `# DECISION`, not an owner question, since spec 2.1 names
the five shapes but gives no interior layout for any of them ("[NEW], based
on the planned 2.0 feature").

**Tests first:** `test_field_map_def.gd` — instantiates `Main` (following
`tests/unit/test_headless_bot_match.gd`'s own "drive Main directly, no
Lobby/Net" pattern) with a non-default `map_size`/`map_variant`, asserts
`Field.map_definition()` (or the baked grid's `cell_size`/`field_radius`)
matches the selected `MapDef` — the exact acceptance criterion keo.2's own
Beads text already specifies. `test_cell_grid.gd` — a `CellGrid` built with a
`shape_test` Callable that always returns `false` reports `in_disk_cell_count()
== 0`; one that returns `true` unconditionally matches the plain two-argument
constructor's own circle count exactly (regression: shape_test present but
equivalent to the circle changes nothing). `test_map_def.gd` — `shape_contains()`
for each of the five shapes rejects points outside `field_radius`'s bounding
circle and accepts the center for every shape except `RING` (which must
reject its own hole) and `CROSS` (which must reject a corner between arms);
`for_variant_and_size(ROUND, size)` returns byte-identical fields to
`for_size(size)` for all three sizes.

**Acceptance:** `tools/run_gut.ps1 test_field_map_def,test_cell_grid,test_map_def`
passes; `godot --headless --editor --path . --quit` stays clean. **ENet
check:** not required (no `net/`/`autoload/` file touched; `game/Main.gd`'s
edit is host/client symmetric since both run the same `_build_match_world()`
path).

---

### A1 — MatchConfig completions: teams (Bontago-keo.1) + map_def() variant routing + `turn_based` field, plus the MatchGifts team-index fix

**Depends on A0 committed** (`map_def()` needs `MapDef.for_variant_and_size`).
**Owns:** `config/MatchConfig.gd`, `autoload/match/MatchGifts.gd`,
`tests/unit/test_match_config.gd`, `tests/unit/test_gift_claim.gd`. 4 files.
**Reads only:** `core/territory/TerritorySolver.gd`, `core/rules/WinChecker.gd`,
`autoload/match/MatchLifecycle.gd`, `autoload/match/MatchTerritory.gd`,
`net/MatchNet.gd`, `game/BotController.gd` (confirm, do not edit — all five
already consume `team_id`/`team_count()` correctly per the audit table above).

**`team_count()`/`team_of_slot()`, concretely:**
```gdscript
func team_count() -> int:
    if team_mode == TeamMode.OFF:
        return player_count
    return mini(team_mode_team_count(team_mode), player_count)

func team_of_slot(slot_id: int) -> int:
    if team_mode == TeamMode.OFF:
        return slot_id
    return posmod(slot_id, team_count())
```
`# DECISION` (config/MatchConfig.gd): teams interleave (`slot_id % team_count`)
rather than block-assign (first half one team, second half the other).
`MapDef.home_flag_position()` already spaces every slot's home flag evenly
around the disk by `slot_id` (`MapDef.gd:113-117`), so interleaving spreads
each team's starting positions around the disk instead of clustering them on
one arc — a reasonable default reading of "exact original team-win/home-anchor
semantics remain unverified" (spec 2.2). `mini(..., player_count)` guards the
degenerate case (`TEAMS_4` with `player_count == 2`: `team_count()` returns 2,
not 4, so no team is ever empty).

**MatchGifts fix, concretely (the bug found while reading keo.1, not new
scope):** `held_special(slot_id)`, `pop_pending_special(slot_id)`,
`pending_special_count(slot_id)` and `debug_queue_special(slot_id, ...)`
(`MatchGifts.gd:132,157,169,204-213`) each gain one line translating the
parameter before indexing: `var team_id: int =
_match.config.team_of_slot(slot_id)`, then index `_pending_queues[team_id]`
instead of `_pending_queues[slot_id]` (and `_ensure_capacity(team_id)` instead
of `_ensure_capacity(slot_id)`). Safe because `team_of_slot(slot_id) <=
slot_id` always under the interleaved assignment above, so the array's
existing slot_id-sized headroom is never exceeded. This is the one thing that
turns "which teammate's next block becomes the special" from silently wrong
into "every teammate's `held_special()`/HUD indicator reads the same shared
team queue" — not a resolution of the *design* question (below).

**`turn_based` field (interface only; B4 owns the behaviour):**
```gdscript
## Spec 2.7 "Turn-based [NEW]": physics settles completely before the next
## player's turn starts. Orthogonal to team_mode and to hot_seat (M2's own
## single-PC test harness, spec Part 4 M2: "must not become normal play") --
## turn_based is a real, networkable mode B4 implements against active_slot/
## advance_turn(), the same machinery hot_seat already uses for its own,
## different (instant hand-off) trigger.
@export var turn_based: bool = false
```
Added to `sanitize()` (no range to clamp, a plain bool), `to_dict()`/
`from_dict()`.

**Tests first:** `test_match_config.gd` — `team_of_slot()`/`team_count()` for
every `TeamMode` value and every `player_count` in 2..8 (interleaved
assignment, no team ever empty when `team_count() <= player_count`); `OFF`
behaves exactly as today (`team_count() == player_count`,
`team_of_slot(i) == i`); `map_def()` routes through `map_variant` for every
combination (spot-check against `MapDef.for_variant_and_size` directly);
`turn_based` round-trips through `to_dict()`/`from_dict()`. `test_gift_claim.gd`
— a claim while `team_of_slot(slotA) == team_of_slot(slotB)` (teammates) makes
`held_special(slotA)` and `held_special(slotB)` return the same special id;
`pop_pending_special(slotA)` empties it for `slotB` too (shared queue, not a
per-slot copy).

**Acceptance:** `tools/run_gut.ps1 test_match_config,test_gift_claim` passes;
`godot --headless --editor --path . --quit` stays clean. **ENet check:** not
required (pure `config/`/`autoload/match/` logic, no new wire message; existing
`to_dict()`/`from_dict()` round trip is already exercised by M3a's harness).

---

### A2a — Oval + Ring MapDef resources (pure data)

**Depends on A0 committed.** **Owns:** `config/maps/oval_small.tres`,
`oval_medium.tres`, `oval_large.tres`, `config/maps/ring_small.tres`,
`ring_medium.tres`, `ring_large.tres`. 6 files, no code. Each duplicates its
same-size Round resource's non-shape fields (`skybox_set`, `disk_height`,
`cell_size`, `territory_res`, flag fractions, `cell_wake_height`/
`cell_wake_max_bodies`) and sets `map_shape`/the variant's own new fields from
A0 (`oval_aspect`, `ring_hole_radius_fraction`, `ring_bridge_half_width`).

**Tests:** covered by A0's `test_map_def.gd` (shape math) plus one appended
case per new resource load — `MapDef.for_variant_and_size(OVAL/RING, size)`
returns a resource whose `map_shape` matches and whose `field_radius` matches
the same-size Round resource (S/M/L numbers must not drift between variants).
**Acceptance:** `tools/run_gut.ps1 test_map_def` passes. **Review:** not
required (data-only, no `core/`/`net/`/`autoload/`/physics file). **ENet
check:** not required.

---

### A2b — Twin + Cross MapDef resources (pure data, parallel with A2a)

**Depends on A0 committed.** **Owns:** `config/maps/twin_small.tres`,
`twin_medium.tres`, `twin_large.tres`, `config/maps/cross_small.tres`,
`cross_medium.tres`, `cross_large.tres`. 6 files, disjoint from A2a. Same
shape as A2a otherwise (`twin_separation`, `twin_bridge_half_width`,
`cross_arm_half_width_fraction` from A0).

**Acceptance/Review/ENet:** identical to A2a's.

**Known risk carried by A2a+A2b, flagged not fixed:** `core/gifts/
GiftSpawner.pick_spawn_point()` samples a random point inside a circle of
radius `field_radius - spawn_edge_margin_m` and rejects it via
`grid.is_in_disk()` (`core/gifts/GiftSpawner.gd:65,70`) — correct for every
shape (A0's generalized `is_in_disk` makes the rejection test exact), but on
`CROSS` (four narrow arms inside a much larger bounding circle) or `RING`
(a hole in the middle) the acceptance rate per random draw drops well below
Round/Oval's, costing more of `GiftConfig.spawn_max_attempts` before a
successful roll or (rarely, on Cross at a small map size) exhausting them and
skipping a spawn for that window. Not a correctness bug — `should_spawn()`
still tries again next window — but worth a bench-scene spot-check if a
manual Cross-map playtest reports gifts feeling rarer there than the lobby's
`special_frequency` implies. Left as a known limitation rather than an
optimization (e.g. rejection-sampling only the arm's own bounding boxes)
built now.

---

### A3 — Match timer + sudden death (spec 2.8's last two stub rows)

**Depends on A0 and A1 committed** (`MatchTerritory.gd`/`MatchGifts.gd`
already carry those packages' edits; this is a dependency chain, not a
parallel write). **Owns:** `autoload/Match.gd`, `autoload/match/
MatchLifecycle.gd`, `autoload/match/MatchTerritory.gd`, `autoload/match/
MatchGifts.gd`, `tests/unit/test_sudden_death.gd` (new), `tests/unit/
test_match_lifecycle.gd` (append). 6 files.

**Match timer, concretely.** `MatchLifecycle` gains `_match_timer_left: float`,
armed to `config.match_timer_minutes * 60.0` on `State.PLAYING` entry (only
when `> 0`; `0` means "off" per spec 2.8's own range row) and ticked from
`Match._process()`'s existing `State.PLAYING:` branch (`Match.gd:260-263`,
append one call). At `0.0`, if `config.sudden_death` is true, transition to
the already-declared `State.SUDDEN_DEATH` (`Match.gd:46`); otherwise the
match simply keeps running under normal rules with no more timer (spec 2.8:
sudden death is "on if match timer is set" by default, but the row is still
independently toggleable — an "off" sudden death with a set match timer means
the timer is cosmetic once it hits zero, which is what the spec's two
independent rows imply, not a contradiction).

**Sudden death, concretely (spec 2.8's own three bullets).** Add a
`State.SUDDEN_DEATH:` case to `Match._process()`'s match statement
(`Match.gd:256-264`) that runs the same three ticks `PLAYING` already does
(`_tick_disconnect_grace`, `_feed._tick_feed`, `_territory._tick_territory`)
plus a new `_lifecycle._tick_sudden_death(delta)` — closing the exact gap the
audit table above names (today, setting this state would silently freeze
everything).
- **Gift probability climbs toward the maximum:** `MatchGifts._tick_gifts()`'s
  existing call `GiftSpawner.should_spawn(_gift_config,
  float(_match.config.special_frequency), ...)` (`MatchGifts.gd:300`) becomes
  `GiftSpawner.should_spawn(_gift_config, _effective_special_frequency(), ...)`,
  where `_effective_special_frequency()` returns `config.special_frequency`
  outside sudden death and lerps toward `100.0` over
  `TerritoryTuning.sudden_death_ramp_s` (a new tunable — `# DECISION`, spec
  gives no ramp duration, "climbs toward the maximum" only) once
  `_lifecycle.sudden_death_active()` is true; `GiftConfig.frequency_to_chance_max`
  (already `0.5`, `config/GiftConfig.gd:22-23`) is exactly the finalized
  spawn model's own maximum spec 2.6 already names, so `should_spawn()` itself
  needs no change.
- **The disk's edge crumbles inward by 1 m every 10 s:** reuses the exact,
  already-proven hole-punch mechanism `MatchTerritory._punch_special_hole()`
  already demonstrates for Jumping Bean (`MatchTerritory.gd:392-437`: scan
  cells within a world-space radius, call `_raster.force_hole_cell(cx, cy,
  hole_open_s, permanent_holes)` for each newly-opened one, batch through the
  same backlog, then `Events.hole_cells_changed.emit()` and
  `_check_home_flags(opened)`), rather than resizing `CellGrid`/rebuilding
  `Field`'s trimesh (which A0 established is a whole-disk operation, not
  something to run every 10 s). Every 10 s, `_tick_sudden_death()` computes a
  new `shrink_radius = field_radius - floor(elapsed_since_sudden_death / 10.0)
  * 1.0` and calls a small new `MatchTerritory.shrink_to_radius(shrink_radius)`
  that punches every currently-solid, still-in-disk cell whose
  `grid.index_center(cell).length() > shrink_radius` as a **permanent** hole
  (`force_hole_cell(..., permanent = true)`, regardless of the match's own
  `hole_mode` — a shrunk cell must never reopen). `# DECISION`
  (autoload/match/MatchTerritory.gd): shrinking is expressed entirely in the
  existing hole vocabulary, not a second physical mechanism, so `Field.gd`
  needs **no new code at all** for sudden death — it already reacts to
  `set_hole_cells()`/wakes bodies above a newly-opened cell exactly as it does
  for a natural overlap hole.
- **Radius-8 tiebreak:** once `shrink_radius <= 8.0` (spec 2.8's own number)
  and no team has won yet, `_finish_match()` is called with the team holding
  the largest `TerritoryRaster.team_share(team_id)` across `range(config.
  team_count())` (ties broken by lowest team id — `# DECISION`, spec doesn't
  say, and an exact float tie between two teams' territory share is a
  vanishingly unlikely edge case not worth a second rule).

**Tests first:** `test_sudden_death.gd` — the match timer counts down only in
`PLAYING`, transitions to `SUDDEN_DEATH` at zero only when `config.
sudden_death` is true (stays in `PLAYING` otherwise); `Match._process()`'s new
`SUDDEN_DEATH` branch still ticks feed/territory/disconnect-grace (a
regression test against the exact gap named above: a scripted match forced
into `SUDDEN_DEATH` keeps issuing feed blocks); `shrink_to_radius()` punches
exactly the cells outside its argument and never reopens one already punched,
even if called again with a *larger* radius (monotonic shrink); the
radius-8 tiebreak picks the team with strictly more `team_share()` and is
deterministic on a tie (lowest team id); `_effective_special_frequency()`
lerps monotonically from `config.special_frequency` to `100.0` over the ramp
window and clamps there after. `test_match_lifecycle.gd` — appends a
"sudden death never fires with `match_timer_minutes == 0`" regression.

**Acceptance:** `tools/run_gut.ps1 test_sudden_death,test_match_lifecycle`
passes; `godot --headless --editor --path . --quit` stays clean. **Review:**
recommended (`autoload/`/rules-shaped state-machine change). **ENet check:**
not required for the shrink/timer logic itself (host-only, already-replicated
hole-cell events carry it to clients via the existing `Events.
hole_cells_changed` -> `net/MatchNet.gd` path with zero changes there); a
manual owner step (below) confirms a client actually sees the shrink.

---

### A4 — Enabled-specials checklist (lobby UI)

**Independent of A0-A3** (only `ui/Lobby.gd`/`.tscn`; the rule logic it wires
into, `MatchGifts._draw_special_id()`'s `enabled_specials` filter, already
works — `MatchGifts.gd:325,336-337`). **Owns:** `ui/Lobby.gd`, `ui/Lobby.tscn`,
`tests/unit/test_lobby.gd`. 3 files.

**Work.** Replace `%SpecialsNote`'s static label with one `CheckBox` per
`SpecialDef.load_all_specials()` entry (`config/specials/SpecialDef.gd:60`),
built dynamically in `_populate_options()`'s style (following the same
"every roster row is already built dynamically, no new scene node needed"
precedent M5's P4 already established for bot rows, `ui/Lobby.gd`'s own
`_apply_roster()`) inside a new `%SpecialsChecklist` `VBoxContainer`
(the one actual `.tscn` node this package adds, replacing `%SpecialsNote`).
Checked = enabled. `_config_from_controls()` sets `config.enabled_specials`
to the checked ids (empty array only if the player unchecks every box —
matches `MatchConfig`'s own existing "empty means all enabled" convention,
so unchecking everything must not accidentally mean "all," `# DECISION`:
represent "none enabled" as a length-8 array of *no* enabled ids is
impossible to distinguish from "not yet touched" under the current empty-
means-all contract; this package adds one explicit `ALL_DISABLED_SENTINEL`
i.e. a single reserved `StringName(&"__none__")` entry the checklist writes
when every box is unchecked, and `_draw_special_id()`/`MatchGifts.gd`'s
existing filter treats that sentinel as "empty roster, spawn nothing" one
line different from today's `is_empty()` check — flagged here since it is
the one place this package's UI-only scope needs a one-line rule-file change;
confirm at dispatch whether the orchestrator wants that line folded into A4
or split to a `stackfall-implementer` review-required micro-package since it
touches `autoload/match/MatchGifts.gd`, which A1/A3 already own this
milestone — **recommendation: serialize this one line after A3 lands**,
same as every other `MatchGifts.gd` writer this milestone).
`_apply_data()` reflects the wire `enabled_specials` back onto the checkboxes
the same way every other control already round-trips.

**Tests first:** `test_lobby.gd` — every loaded `SpecialDef` gets a checkbox
row; unchecking one and publishing removes exactly that id from `config.
enabled_specials`; unchecking all publishes the sentinel, not an empty array;
a lobby that receives `enabled_specials` over the wire (`_apply_data`) checks
exactly the matching boxes.

**Acceptance:** `tools/run_gut.ps1 test_lobby` passes; a manual windowed check
(owner step below) that unchecking a special in the lobby means it never
appears in that match's gifts. **Review:** not required for the UI (per
`docs/AGENT_WORKFLOW.md`, "UI, tooling and docs packages skip independent
review") but recommended for the one `MatchGifts.gd` sentinel line. **ENet
check:** not required beyond the existing `to_dict()`/`from_dict()` round trip
(no new wire message, `enabled_specials: Array[StringName]` already
serializes).

## M6b — modes

### B1 — Sandbox: no territory limits + Main Menu entry point

**Depends on A0 committed** (`game/Main.gd` edit base). **Owns:**
`autoload/match/MatchPlacement.gd`, `game/Main.gd`, `ui/MainMenu.gd`,
`ui/MainMenu.tscn`. 4 files (+ whichever of `tests/unit/test_sandbox.gd` /
`tests/unit/test_main_menu.gd` already asserts placement/menu behaviour —
append, don't create a new file if either already exercises this seam;
confirm at dispatch). Up to 6 files.

**Territory-limit bypass, concretely.** `MatchPlacement.gd:180-191`'s
`request_place()` validation (`result = PlacementRules.validate_point(...)`)
and its throw-path twin (`:342-357`) each gain one guard: when
`_match.config.sandbox` is true, remap `Result.OUTSIDE_TERRITORY` and
`Result.CONTESTED` to `Result.VALID` before the `if result !=
PlacementRules.Result.VALID` check — `Result.OFF_DISK`, `Result.HOLE` and
`Result.GOAL_ZONE` are left refused (spec 2.7 says "no territory limits," not
"place blocks in the void or through a hole"). `core/rules/PlacementRules.gd`
itself is **not** touched — it stays a pure, config-agnostic rule file every
other milestone's tests already pin tightly; the sandbox exception lives only
at the one call site that already knows about `config.sandbox`
(`MatchLifecycle.gd:121`'s own precedent).

**Main Menu entry point, concretely.** `game/Main.gd`'s existing
`_start_sandbox_match_with_args(args)` (`Main.gd:202-230`) is CLI-args-only,
called from `_ready()`'s `_has_cmdline_flag("sandbox")` branch (`Main.gd:125-
126`). Add a public `start_sandbox_from_menu() -> void` that calls the same
`_sandbox = SANDBOX_SCENE.instantiate()` / `Match.start_match(_build_sandbox_
config(sandbox_config.default_player_count))` sequence `_start_sandbox_match_
with_args([])` already runs (default player count, no forced special),
reachable once `ui/MainMenu.tscn` shows the initial menu (following the
existing `_on_host_pressed()`/`_on_direct_join_pressed()` button-handler
shape, `ui/MainMenu.gd:108-126`). New `%SandboxButton` in `ui/MainMenu.tscn`
next to the existing Host/Join controls.

**Tests first:** a scripted `start_sandbox_from_menu()` call builds a
`PLAYING` match with `config.sandbox == true` and no `Lobby`/`Net` state
touched (same "drive Main directly" pattern A0's own test uses); a placement
outside the sandbox slot's territory (but on-disk, non-hole, non-goal-zone)
succeeds where the identical placement in a non-sandbox match is refused
(`REASON_OUTSIDE_TERRITORY`); one still refused off-disk and one still
refused inside a hole, in sandbox, to prove the guard is scoped correctly.

**Acceptance:** targeted GUT run for whichever test file this appends to
passes; a manual windowed check (owner step below) that the Main Menu shows
a Sandbox button and it reaches a real, timer-less, territory-less match.
**Review:** recommended (`autoload/match/MatchPlacement.gd` is a rules file).
**ENet check:** not required (sandbox is explicitly offline-only, matching
`_build_sandbox_config()`'s existing `config.hot_seat = false`/no `Net`
involvement).

---

### B2 — Sandbox tools: block picker, special spawn menu, slow-motion, pause-physics, height record (parallel with B1)

**Depends on A0 committed only for context** (does not touch `game/Field.gd`
or `game/Main.gd`; disjoint files from B1, so genuinely parallel). **Owns:**
`game/Sandbox.gd`, `ui/SandboxPanel.gd`, `ui/SandboxPanel.tscn`,
`config/SandboxConfig.gd`, `tests/unit/test_sandbox.gd`. 5 files.

**Work, each reusing an existing seam rather than inventing one:**
- **Block picker:** `Sandbox._spawn_tower()`'s own `# DECISION` already names
  the constraint precisely — `request_place()` has no shape parameter, it
  always spawns whatever the target slot currently holds
  (`Sandbox.gd:191-202`). A block picker therefore needs a new, sandbox-only
  seam on `Match`/`MatchFeed`: `MatchFeed.debug_force_next_shape(slot_id: int,
  shape_id: StringName) -> void` (gated on `_match.config.sandbox`, same
  discipline as `debug_queue_special()`, `MatchGifts.gd:204-230`), replacing
  `_held_shapes[slot_id]` directly. **This is the one place B2's own file list
  above is incomplete: it needs a small append to `autoload/match/
  MatchFeed.gd`, which no other M6 package touches — add it to this
  package's owned files** (6 total). `ui/SandboxPanel.gd` adds an
  `OptionButton` populated from `BlockShape.load_all_shapes()`.
- **Special spawn menu:** `Sandbox._cycle_forced_special()`/`force_special_
  by_id()` already exist and already call `Match.debug_queue_special()`
  (`Sandbox.gd:234-270`) — this is a UI-only addition (a dropdown instead of
  the F9 cycle) reusing the exact same call, no new rule code.
- **Slow-motion:** `Engine.time_scale` is the standard Godot mechanism;
  `SandboxConfig` gains `@export var slow_motion_scale: float = 0.25` (a new
  hotkey, following `sandbox_toggle_timer`'s F6 precedent — `# DECISION`:
  bound through `tools/bootstrap_project.gd`'s existing action-generation
  convention, so this package's own owned-files list also needs one append
  there for a new `sandbox_slow_motion` action; confirmed in scope since
  `bootstrap_project.gd` is explicitly "where new actions get added," not a
  hand-edit of `project.godot`'s `[input]` section).
- **Pause-physics:** `get_tree().paused = true` with `Sandbox`/`SandboxPanel`
  set to `PROCESS_MODE_ALWAYS` so the panel itself stays interactive — a new
  hotkey (same bootstrap_project.gd append).
- **Height record:** `game/BlockRegistry.gd` already has a per-slot tallest-
  point query (`tallest_point_for(slot_id)`-shaped accessor implied by its
  "Tallest point any of slot_id's settled blocks reaches" doc comment,
  `BlockRegistry.gd:204-210`) — `SandboxPanel` polls it once per frame and
  keeps a running max in a plain `float`, displayed in the panel; no new
  `BlockRegistry` code needed (read-only).

**Tests first:** `debug_force_next_shape()` is refused off-sandbox and off-
host, exactly like `debug_queue_special()`'s own guard; `Engine.time_scale`
changes only while the sandbox slow-motion hotkey is held/toggled and resets
to `1.0` on scene teardown (no leaked global state into the next match — a
real risk, since `Engine.time_scale` is process-global, not scoped to one
scene); pause-physics leaves `SandboxPanel` responsive to input while
`get_tree().paused` is true; the height-record max only ever increases within
one match and resets on `sandbox_reset_field`.

**Acceptance:** `tools/run_gut.ps1 test_sandbox` passes; a manual windowed
check (owner step below) exercising all five tools. **Review:** recommended
for `MatchFeed.gd`'s new debug seam (touches `autoload/match/`), not required
for the rest. **ENet check:** not required (sandbox is offline-only).

---

### B3 — Tutorial (5 steps)

**Depends on B1 committed** (`ui/MainMenu.gd`/`.tscn` ownership serializes
after B1's own Sandbox-button append). **Owns:** `ui/Tutorial.tscn`,
`ui/Tutorial.gd`, `config/TutorialConfig.gd`, `ui/MainMenu.gd` (append),
`ui/MainMenu.tscn` (append), `tests/unit/test_tutorial.gd`. 6 files.

**Work.** A single-player, offline match built the same way `Sandbox`/
`HotSeat` already are (`Match.register_world()` -> `Match.start_match(config)`
with `config.sandbox = true`, `config.hot_seat = false`, `player_count = 1`),
driving a five-step sequence of typed step definitions:
```gdscript
class_name TutorialConfig
extends Resource
class Step:
    @export var id: StringName
    @export var prompt_text: String
    ## Which Events signal (or polled PlayerController/GhostPreview state)
    ## marks this step complete -- kept as a StringName key TutorialSteps.gd
    ## switches on, not a Callable resource, since a Resource cannot export one.
    @export var completion_signal: StringName
@export var steps: Array[Step] = []  # placing, rotating, territory, specials/throwing, camera
```
Step 1 (placing)/3 (territory) complete on `Events.block_placed`/a raster read
showing the tutorial slot owns new territory; step 2 (rotating) polls
`PlayerController`'s own current orientation index changing (no Events signal
exists for a purely local ghost manipulation, confirmed — rotation never
reaches the host until release); step 4 (specials & throwing) forces a
special via the same `debug_queue_special()` seam B2 exposes through the
panel (B3 calls the underlying `Match` method directly, not through
`SandboxPanel`, so it has no dependency on B2's UI) and completes on
`Events.special_consumed`; step 5 (camera) completes on any
`camera_orbit`/`camera_pan_*` input observed for a few seconds. `ui/
Tutorial.gd` shows/hides a prompt overlay per step and calls
`Match.abort_match()`/returns to `ui/MainMenu.tscn` on finish or Esc.

**Tests first:** each step's completion condition fires exactly once and
advances to the next step, not skipping or repeating; the tutorial ends and
returns control to the Main Menu after step 5; Esc at any point aborts
cleanly (`Match.abort_match()` called, no leaked `Tutorial` scene).

**Acceptance:** `tools/run_gut.ps1 test_tutorial` passes; a manual windowed
check (owner step below) playing all five steps start to finish. **Review:**
not required (new, self-contained UI/offline-match files; no `core/`/`net/`
change). **ENet check:** not required (offline single-player, same posture as
Sandbox).

---

### B4 — Turn-based mode

**Depends on A1 committed** (`config.turn_based` field) **and, for file
serialization only, on A3 landing first** (both touch `autoload/match/
MatchLifecycle.gd`; B4 rebases on A3's commit rather than writing in
parallel). **Owns:** `autoload/match/MatchLifecycle.gd`, `autoload/match/
MatchPlacement.gd`, `game/BlockRegistry.gd`, `tests/unit/test_turn_based.gd`
(new), `tests/unit/test_block_registry.gd` (append). 5 files.

**Work.** `game/BlockRegistry.gd` gains one small aggregate,
`all_settled() -> bool` (iterate `_entries`, `return false` on the first
`not entry.is_settled`, `true` otherwise — the exact per-block flag `_tick()`
already maintains via `PhysicsTuning.sleep_linear_threshold`/
`sleep_angular_threshold`/`sleep_settle_time`, `BlockRegistry.gd:149-167`, no
new physics query). `MatchLifecycle` gains `_turn_settle_wait_left: float =
-1.0` (`-1` = not waiting) and `begin_turn_settle_wait()` (arms it to
`TerritoryTuning.turn_based_max_settle_s`, a new tunable defaulting to `6.0`
per spec 2.7's own number), ticked from a new `_tick_turn_based(delta)` called
from `Match._process()`'s `PLAYING`/`SUDDEN_DEATH` branches (append, next to
A3's own `_tick_sudden_death` call) only when `config.turn_based`: once
`_match.registry().all_settled()` **or** the countdown reaches zero, calls
`advance_turn()` and clears the wait. `MatchPlacement.gd`'s two existing
`if _match.config.hot_seat: _match.advance_turn()` sites (`:276-277,382-383`)
each gain a parallel `elif _match.config.turn_based:
_match._lifecycle.begin_turn_settle_wait()` — hot-seat's own instant-hand-off
branch is untouched, keeping M2's "must not become normal play" test harness
byte-identical. The existing single-active-slot gate
(`_match.config.hot_seat and slot_id != _match.active_slot()`,
`MatchPlacement.gd:138,318`) gains the same `or (_match.config.turn_based and
slot_id != _match.active_slot())` so only the active slot may act — turn-based
needs the same one-slot-at-a-time enforcement hot-seat already has, just with
a different hand-off trigger. `# DECISION`: `turn_based` and `hot_seat` are
mutually exclusive in practice (the lobby never offers hot_seat; the CLI
`--hot-seat` path never sets `turn_based`), so no code resolves "both true"
— `sanitize()` does not need a cross-field rule for a combination no caller
can reach.

**Tests first:** `test_block_registry.gd` — `all_settled()` is `true` on an
empty registry and once every entry's own settled flag is true, `false` while
any one block is still moving. `test_turn_based.gd` — a placement under
`turn_based` does not advance the turn immediately (unlike `hot_seat`);
`advance_turn()` fires once `all_settled()` turns true; a still-moving tower
that never settles still advances at exactly `turn_based_max_settle_s`; a
non-active slot's placement attempt is refused
(`REASON_NOT_YOUR_TURN`-shaped) under `turn_based`, mirroring `hot_seat`'s own
existing assertion.

**Acceptance:** `tools/run_gut.ps1 test_turn_based,test_block_registry`
passes; `godot --headless --editor --path . --quit` stays clean. **Review:**
recommended (`autoload/match/` state-machine change). **ENet check:**
required — turn-based is reachable from the networked lobby (a new lobby
checkbox this package also needs; folded in as a `ui/Lobby.gd` one-control
append rather than a separate package, since it is one `CheckButton` next to
the existing `_sudden_death_check` pattern, `ui/Lobby.gd:53,151` — confirm at
dispatch whether this single-control append belongs to B4 or is better
serialized after A4's own `ui/Lobby.gd` edit; **recommendation: land after
A4**, same file). A short scripted ENet check (`tools/run_gut.ps1`-style, or
a manual 2-instance run per the owner steps below) confirms a client's turn
banner (`Events.turn_changed`) matches the host's.

---

### B5 — PHYSICAL_BALANCE tilt mode

**Depends on A0 committed (`game/Field.gd`) and, for file serialization, on
B4 landing first** (both touch `autoload/match/MatchLifecycle.gd`). **Owns:**
`game/Field.gd`, `config/TiltTuning.gd`, `autoload/match/MatchLifecycle.gd`,
`tests/unit/test_field_tilt.gd` (append), `tests/bench/
bench_physical_balance.gd` (+ `.tscn`, new). 5 files.

**`# DECISION` (game/Field.gd) — the one implementation-approach call in this
milestone worth flagging prominently, not just noting inline.** Spec 2.1's
own illustrative design is "the disk is a RigidBody3D attached to the
fulcrum with a joint that allows rotation on two axes," but spec 2.1 also
says this mode is "[NEW]... feasibility still to be benchmarked" and
"optional, not an original-fidelity requirement" — an explicit invitation to
choose the safer implementation, not a locked contract. `Field` is declared
`extends AnimatableBody3D` (`Field.gd:2`) and every other system (M4's
trimesh, `sync_to_physics`-driven block-carrying, `SnapshotSync`'s frozen-
mirror convention, the kill plane, the overlay) is built on that being a
*kinematic* body Field itself drives, never one Jolt simulates freely. Making
`PHYSICAL_BALANCE` a genuine second `RigidBody3D`-on-a-joint body would mean
either swapping `Field`'s base class at runtime (impossible in Godot) or
building and maintaining a second disk-body implementation end to end
(collision, snapshot sync, kill plane, overlay) alongside the first — the
same shape of physics-architecture risk M4's P0 escalated to Opus for
("silent and broad... a subtly wrong tradeoff regresses every future
milestone's physics"). This plan instead extends the **existing** kinematic
tilt spring (`Field._tilt_velocity`, already spec 3.5's "critically damped
spring," `Field.gd:320-332`) with a **continuous torque estimate** computed
from the same settled-block data `BlockRegistry` already tracks: every
physics frame, sum each settled block's `(disk-local XZ offset from center)
x (weight)` into a torque vector, scaled by a new `TiltTuning.
physical_balance_torque_gain` and fed into `_tilt_velocity` every frame (not
as a one-shot `apply_tilt_impulse()`, since this is continuous pressure, not
a discrete hit) whenever `Field`'s own new `_physical_balance_enabled` flag
is set — the exact same spring/clamp/transform-write pipeline
`SPECIALS_ONLY` already exercises and this milestone's own tests already
cover, so the *feel* spec 2.1 asks for (torque from block weight tilts it, a
restoring spring plus damping keeps it controllable) ships without a second
physics body or any risk to M4's `AnimatableBody3D`/trimesh work. This is a
real engineering trade (approximation vs. a literal dynamic joint), not a
gameplay-rule change — flagged for the orchestrator's attention and a
recommended **review** pass (not an owner pause: spec explicitly leaves this
mode's mechanism open), and named as the one package in this milestone worth
considering for an Opus-reviewed diff given the physics-architecture shape,
even though the implementation itself is additive and low-risk to existing
systems.

**Work.** `Field.set_physical_balance_enabled(enabled: bool)` (parallel to
`set_tilt_enabled()`, `Field.gd:233-245` — both may be true only when
`tilt_mode == PHYSICAL_BALANCE`, `set_tilt_enabled(true)` alone still handles
`SPECIALS_ONLY`); `_physics_process()` gains one more branch computing the
torque sum via `BlockRegistry.settled_blocks_for_torque()`-shaped read (a new,
read-only aggregate, or reuse `influence_circles()`'s existing settled-block
iteration if it already exposes position/mass — confirm at dispatch which is
cheaper) and adding it into `_tilt_velocity` before the existing spring
integration in `_update_tilt()`. `MatchLifecycle`'s existing single call site
that turns tilt on for a match (referenced in `Field.gd:212-219`'s own doc
comment as "wiring an actual call from there is left to whichever package
next reads MatchConfig into Field" — this is that package) gains an `elif
config.tilt_mode == TiltMode.PHYSICAL_BALANCE:
_field.set_physical_balance_enabled(true)` branch alongside its existing
`SPECIALS_ONLY` one.

**Tests first (append to `test_field_tilt.gd`):** a synthetic settled-block
layout entirely off-center (all weight on one side) drives `_tilt_velocity`
toward that side over several frames with `_physical_balance_enabled(true)`
and does nothing with it `false`; the same `max_tilt_deg` clamp already
proven for `SPECIALS_ONLY` still holds under continuous torque input (not
just discrete impulses); a perfectly centered/symmetric block layout produces
no net torque and the disk stays level. `bench_physical_balance.gd`/`.tscn`
(new, following `bench_tower.gd`'s `--trace=`/timing-print format): a
moderately tall, off-center tower under `PHYSICAL_BALANCE` runs for a fixed
sim duration and reports average `Performance.TIME_PHYSICS_PROCESS` — the
literal "feasibility still to be benchmarked" spec 2.1 calls for, same
headless-timing-is-a-proxy caveat every other bench in this codebase already
carries.

**Acceptance:** `tools/run_gut.ps1 test_field_tilt` passes; `godot --headless
--path . res://tests/bench/bench_physical_balance.tscn` prints a result line
with no error; a manual windowed check (owner step below) that a lopsided
tower visibly tilts the disk under its own weight and settles level once
balanced. **Review:** recommended (physics-shape decision, `game/Field.gd`).
**ENet check:** required (tilt already replicates via `Field.
apply_replicated_pose()`/`SnapshotSync`, `Field.gd:291-317` — confirm a
client sees the same continuous tilt, not just a host-only effect).

## M6c — user settings

### C1 (interface-stub) — `Settings.gd` fill-in, `GraphicsPreset`, persistence

**Independent of M6a/M6b** (touches only the empty `autoload/Settings.gd`
stub and new files). **Owns:** `autoload/Settings.gd`, `config/
GraphicsPreset.gd` (new), `config/graphics_presets/low.tres`,
`medium.tres`, `high.tres` (new), `tests/unit/test_settings.gd` (new). 6
files.

**Interfaces this package commits (typed; C2/C3 consume, never touch
`autoload/Settings.gd` itself):**
```gdscript
# config/GraphicsPreset.gd
class_name GraphicsPreset
extends Resource
@export var id: StringName
@export var ssr_enabled: bool = true
@export var msaa_3d: Viewport.MSAA = Viewport.MSAA_2X
@export var shadow_atlas_size: int = 4096
## SSIL/volumetric-fog fields intentionally absent -- neither render feature
## exists yet (M7 presentation polish adds them); a preset that named them
## today would be a promise this milestone cannot keep. Revisit once M7
## lands those effects (Known limitations, below).

# autoload/Settings.gd (fills the existing stub)
extends Node
signal graphics_preset_changed(preset: GraphicsPreset)
signal audio_settings_changed()
func current_graphics_preset() -> GraphicsPreset
func set_graphics_preset(id: StringName) -> void   # loads from config/graphics_presets/, persists, emits
func master_volume_db() -> float
func set_master_volume_db(db: float) -> void        # persists, emits audio_settings_changed
func custom_music_dir() -> String                   # "" = use the bundled folder
func set_custom_music_dir(path: String) -> void
func key_override_events(action: StringName) -> Array[InputEvent]  # persisted overrides only
func set_key_override(action: StringName, event: InputEvent) -> void
## Applies every InputMap override from user://settings.cfg. Called once from
## _ready(); never touches tools/bootstrap_project.gd's own generated
## defaults -- overrides layer on top via InputMap.action_erase_events()/
## action_add_event() at runtime (CLAUDE.md: "don't hand-edit the [input]
## section" -- this doesn't; it's a runtime API call, not a project.godot edit).
func _apply_key_overrides() -> void
```
Persistence: a single `ConfigFile` at `user://settings.cfg`
(`[graphics] preset`, `[audio] master_db`, `custom_music_dir`, `[input]
<action> = <event resource path or dict>`), loaded once in `_ready()` (the
autoload already runs before any scene, `project.godot:26`) and saved on
every setter — small, infrequent writes, no debouncing needed.

**Tests first:** `set_graphics_preset()`/`current_graphics_preset()` round-
trip and persist across a `Settings.new()` re-load of the same
`user://settings.cfg` path (test uses a temp path, following `Sfx.
set_root_dir_for_test()`'s own test-seam precedent, `Sfx.gd:159`);
`set_key_override()` immediately calls `InputMap.action_erase_events()`/
`action_add_event()` for that action and is readable back via
`key_override_events()`; a `Settings` with no saved file falls back to every
default (medium preset, 0 dB, no custom music dir, no key overrides) without
error.

**Acceptance:** `tools/run_gut.ps1 test_settings` passes; `godot --headless
--editor --path . --quit` stays clean. **Review:** recommended (a new
persistence/autoload surface every later package builds on). **ENet check:**
not required (purely local user preference, never sent over the wire).

---

### C2 — Options menu UI: graphics preset picker, audio sliders, key rebind rows

**Depends on C1 committed. Depends on B3 landing first for file
serialization** (`ui/MainMenu.gd`/`.tscn` ownership chain: B1 -> B3 -> C2).
**Owns:** `ui/OptionsMenu.tscn`, `ui/OptionsMenu.gd`, `ui/KeyRebindRow.tscn`,
`ui/KeyRebindRow.gd`, `ui/MainMenu.gd` (append), `ui/MainMenu.tscn` (append),
`tests/unit/test_options_menu.gd` (new). 7 files.

**Work.** `%OptionsButton` on the Main Menu (same button-handler shape as
B1's Sandbox button) opens `ui/OptionsMenu.tscn`: an `OptionButton` for the
graphics preset (`Settings.set_graphics_preset()`), an `HSlider` for master
volume (`Settings.set_master_volume_db()`), a `LineEdit`+file-picker button
for the custom music folder (`Settings.set_custom_music_dir()`), and one
`KeyRebindRow` per rebindable action — built dynamically from
`tools/bootstrap_project.gd`'s own `_actions()` dictionary keys (read-only:
this package **never** calls into `tools/bootstrap_project.gd` itself, it
only enumerates the same action names already registered in `InputMap` via
`InputMap.get_actions()`, filtered to the player-facing subset — gameplay
actions, not `screenshot_capture`/`net_debug_toggle`/`tuning_panel_toggle`/
`sandbox_*`/`throw_aim` debug-only ones — `# DECISION`: an explicit allow-list
constant in `ui/OptionsMenu.gd`, not a blanket "every InputMap action," so a
future debug hotkey doesn't silently become player-rebindable). Each
`KeyRebindRow` shows the action's current binding(s), a "rebind" button that
captures the next `InputEventKey`/`InputEventMouseButton`/
`InputEventJoypadButton` via `_unhandled_input()` (same "listen for the next
raw event" pattern controller code elsewhere already uses for gamepad
detection) and calls `Settings.set_key_override()`.

**Tests first:** `test_options_menu.gd` — the graphics preset dropdown
selecting an item calls `Settings.set_graphics_preset()` with the matching
id; the volume slider calls `set_master_volume_db()`; a synthetic
`InputEventKey`/`InputEventJoypadButton` (per CLAUDE.md's "synthetic events
through `Input.parse_input_event`" posture) fed to a `KeyRebindRow` in
"listening" state calls `Settings.set_key_override()` with that exact event
and exits listening state; the debug-only action allow-list excludes every
name in the exclusion list (a literal assertion against
`tools/bootstrap_project.gd`'s own `_actions()` keys, so a newly added debug
action doesn't silently leak into the player-facing menu without a matching
test update).

**Acceptance:** `tools/run_gut.ps1 test_options_menu` passes; a manual
windowed check (owner step below) rebinding one keyboard action and one
gamepad action and confirming both take effect in a match. **Review:** not
required (UI-only). **ENet check:** not required (local settings only).

---

### C3 — Custom music folder + audio volume application (parallel with C2)

**Depends on C1 committed only** (disjoint files from C2: `autoload/Sfx.gd`
vs. `ui/OptionsMenu.*`). **Owns:** `autoload/Sfx.gd`, `tests/unit/
test_sfx.gd` (append). 2 files.

**Work.** `Sfx._resolve_root_dir()` (`Sfx.gd:54-56`) becomes: if
`Settings.custom_music_dir()` is non-empty and
`DirAccess.dir_exists_absolute()` there, use it for **music only** (SFX stay
on the bundled `assets/original/audio` folder regardless — spec 1.4/2.10 only
ever name a *music* folder, never a custom SFX set); otherwise fall back to
today's bundled-folder logic unchanged. `Sfx._ready()`/`play()`/
`play_music()` read `Settings.master_volume_db()` as an additional offset on
top of `AudioConfig.sfx_volume_db`/`music_volume_db` (`Sfx.gd:82,115`) rather
than replacing them — the config resource keeps its own per-event baseline,
Settings only adds a single user-facing master fader. `Sfx` connects to
`Settings.audio_settings_changed` to re-read the volume live (no restart
needed to hear a slider move).

**Tests first (append `test_sfx.gd`):** a `Settings.custom_music_dir()`
pointing at a temp folder with one audio file makes `play_music()` load from
there instead of the bundled path; an absent/invalid custom dir falls back
silently (no error, matching the existing "supported absence" pattern
`Sfx.gd`'s own header already documents for the bundled folder itself);
`master_volume_db()` shifts every subsequent `play()`'s `volume_db` by
exactly that offset.

**Acceptance:** `tools/run_gut.ps1 test_sfx` passes; a manual owner step
(below) pointing the custom music folder at a real MP3 folder and confirming
it plays instead of the bundled track. **Review:** not required (`autoload/
Sfx.gd` is presentation, not rules/net/physics). **ENet check:** not required
(local audio only).

## Dispatch order and parallelism

1. **A0** first (P0) — nothing else map-related can start until `Field`
   bakes the right map and `CellGrid`/`MapDef` have a shape mechanism.
2. **A1** once A0 is committed. **A2a** and **A2b** once A0 is committed
   (fully parallel with A1 and with each other — disjoint files: A1 touches
   code, A2a/A2b are pure `.tres` data).
3. **A3** once A0 and A1 are both committed. **A4** any time (independent of
   A0-A3), but its one `MatchGifts.gd` sentinel line should land after A3.
4. **B1** and **B2** once A0 is committed (parallel — disjoint files).
   **B3** once B1 is committed (shares `ui/MainMenu.*`). **B4** once A1 is
   committed and, for file order, after A3. **B5** once A0 is committed and,
   for file order, after B4.
5. **C1** any time (fully independent of every M6a/M6b package). **C2** once
   C1 is committed and, for file order, after B3 (shares `ui/MainMenu.*`).
   **C3** once C1 is committed (parallel with C2 — disjoint files).
6. Each merge passes `godot --headless --editor --path . --quit` (no errors,
   no new warnings) and its own targeted GUT set; the orchestrator runs the
   full suite once per merged batch and the ENet harness for every package
   marked "ENet check: required" above (B4, B5) before calling this
   milestone's acceptance satisfied.
7. **Integration** must re-verify A0's own acceptance (map size actually
   changes the disk) against every non-Round variant once A2a/A2b land too —
   A0's own test only proves the mechanism and the Round sizes; a
   Ring/Twin/Cross map is the first time the *shape* test, not just the
   *radius*, is exercised end to end.

## Tunables introduced — no magic numbers (CLAUDE.md)

| Resource | Owner | Fields (defaults) |
|---|---|---|
| `config/MapDef.gd` (new fields) | A0 | `map_shape` (ROUND), `oval_aspect` 0.65, `ring_hole_radius_fraction` 0.35, `ring_bridge_half_width` 3.0, `twin_separation` 1.6, `twin_bridge_half_width` 3.0, `cross_arm_half_width_fraction` 0.4 |
| `config/TerritoryTuning.gd` (new fields) | A3 / B4 | `sudden_death_ramp_s` (A3 picks and records — spec gives no ramp duration), `turn_based_max_settle_s` 6.0 (spec 2.7's own number) |
| `config/TiltTuning.gd` (new field) | B5 | `physical_balance_torque_gain` (B5 picks and records — spec 2.1 gives no coupling constant, "feasibility still to be benchmarked") |
| `config/SandboxConfig.gd` (new field) | B2 | `slow_motion_scale` 0.25 |
| `config/GraphicsPreset.gd` (new resource, x3) | C1 | `ssr_enabled`, `msaa_3d`, `shadow_atlas_size` per preset (Low/Medium/High) |

**One correction to the Shared-file hotspots section above:**
`config/TerritoryTuning.gd` **is** one of `ui/TuningPanel.gd`'s five shown
resources (`Territory` tab, `TuningPanel.gd:68`), unlike the other four
resources in the table above (`MapDef`, `TiltTuning`, `SandboxConfig`,
`GraphicsPreset`, none of which appear in that five-tab list). So
`config/tuning_panel_hints.tres` **does** need a one-sentence entry for A3's
`sudden_death_ramp_s` and B4's `turn_based_max_settle_s` specifically, per
`docs/AGENT_WORKFLOW.md`'s hints-file rule — A3 and B4 should each append
their own field's entry when they land. Every other new tunable in the table
above lives on a resource the panel does not show and needs no hints entry.

## Known risks

- **Map shape generalization (A0) is the one package whose failure mode is
  silent and broad** in the same sense M4's P0 disk-trimesh work was: a
  wrong `is_in_disk()` predicate for Ring/Twin/Cross would not crash, it
  would just let a block sit on collision that the territory raster
  disagrees is there (or vice versa), the exact class of bug M4's own trimesh
  rebuild was built to eliminate for the Round case. Mitigated by keeping the
  change purely additive (an optional `Callable`, `is_in_disk()`'s existing
  circle fallback untouched) and by A0's own test asserting the physical
  hit-test and `is_in_disk()` agree at every in-disk cell for a non-Round
  shape, not just at the disk's own rim.
- **A2a/A2b's `.tres` resources are pure data and low-risk in isolation, but
  their correctness depends entirely on A0's shape math being right** — a
  wrong `ring_hole_radius_fraction` interpretation, say, would not fail any
  test A2a itself writes (it would just load a `MapDef` and trust A0's own
  `shape_contains()`), so A0's own `test_map_def.gd` carries the real weight
  of proving each shape's geometry, not the resource-loading packages.
- **The 5 packages sharing `autoload/match/MatchLifecycle.gd` (A3, B4, B5)
  and `ui/MainMenu.*` (B1, B3, C2) must be dispatched in the stated order,
  not truly parallel** — flagged twice already (Shared-file hotspots,
  Dispatch order) because it's the single most likely place a parallel
  dispatch would silently start from a stale base and produce a merge
  conflict or, worse, a silent overwrite of one package's edit by another's
  if force-resolved carelessly.
- **B5's kinematic-torque approximation of PHYSICAL_BALANCE (see its own
  `# DECISION`) is an explicit engineering trade against spec 2.1's literal
  "RigidBody3D on a joint" illustration.** Spec explicitly permits this
  ("feasibility still to be benchmarked... optional, not an original-fidelity
  requirement"), so it is resolved here rather than raised as an owner
  question, but it is the one architecture call this milestone makes that a
  reviewer should look at closely before the orchestrator accepts it, and a
  reasonable candidate for an Opus-reviewed diff even though Sonnet can write
  the implementation itself (see Model routing).
- **A3's disk-shrink reuses the existing hole-punch mechanism rather than
  resizing `CellGrid`/rebuilding `Field`'s trimesh every 10 s** — cheap and
  low-risk given `_punch_special_hole()`'s own proven batching, but it means
  a shrunk cell is gone forever even if `hole_mode == OFF` (v2's no-hole
  mode) — `# DECISION`, matching spec 2.8's own "the disk's edge crumbles
  inward" wording literally (an edge that crumbles is gone, not merely
  contested), not overridable by `hole_mode` for this one mechanic.

## Owner questions (pause points — file as `bd human`, do not resolve here)

1. **Which teammate's next fed block becomes a claimed special, under real
   teams?** A1's MatchGifts fix makes the shared team queue *consistent*
   (every teammate's `held_special()` reads the same front-of-queue id), but
   it does not decide *who is offered the choice to place it* when multiple
   teammates are simultaneously holding an ordinary block and the queue has
   one pending special — today's single-queue-per-team design means **every**
   teammate whose next `feed_block_issued` fires while the queue is non-empty
   receives that special (the first one to get fed after the claim "wins" it,
   effectively FIFO-by-feed-timing, not by choice or proximity). Options: (a)
   keep the current de-facto behavior (first teammate fed after the claim
   gets it, already true with A1's fix, no further work) — recommended, since
   it needs zero new code and spec 2.6/2.2 gives no basis to prefer a
   different teammate; (b) target the teammate whose circle is nearest the
   crate (matches "when a crate is inside *your* territory" reading "your"
   as the specific circle that popped it, closer to a solo-claim mental
   model); (c) let every teammate's next block become the special
   simultaneously (spends the team's one queued draw multiple times — likely
   too generous, and cheapens gifts, the exact "gifts felt too random"
   complaint spec 1.7 already lists as a problem this remake tries to fix).
   **Recommendation: (a)**, ship now, revisit only if a team playtest reports
   it feeling arbitrary which teammate got the special.
   **Owner answer (Bontago-keo.15, 2026-09-25): (b)** — implemented in
   Bontago-keo.17: `MatchGifts._resolve_recipient_slot()` picks the alive
   teammate whose home circle is nearest the crate (ties → lowest slot id),
   pending queues are keyed per recipient slot, and `Events.gift_claimed`
   carries that slot.
2. **Is the `PHYSICAL_BALANCE` kinematic-torque approximation (B5) an
   acceptable substitute for spec 2.1's illustrative "RigidBody3D on a
   joint," or does the owner want a genuine second dynamic-body prototype
   benchmarked before this ships?** Not filed as a `bd human` gate by this
   plan because spec 2.1 itself already calls the mode optional and its
   mechanism unsettled ("feasibility still to be benchmarked... not an
   original-fidelity requirement") — but flagged here explicitly since it is
   the one place this milestone substitutes engineering judgment for a
   literal spec illustration, and the orchestrator may still choose to raise
   it as a `bd human` decision issue before dispatching B5 if the owner would
   rather see the literal joint-body approach attempted first despite the
   added risk.

Neither of the above touches an `[ORIGINAL]`-tagged rule — teams (§2.2 "Teams:
allied placement is [ORIGINAL]") and the specials-claim mechanism are already
adopted as designed; this milestone's own choices are about *degenerate,
spec-silent* cases (multi-holder teams, an optional mode's mechanism), not a
change to the adopted rule itself.

## Manual owner steps

- Host a lobby, set Map to each of Round/Oval/Ring/Twin/Cross at each of
  S/M/L, Start, and confirm the disk's actual physical shape (not just the
  overlay tint) matches — walk a block to where Ring's hole/Twin's gap/
  Cross's missing corners should be and confirm it falls through.
- Host a 4-6 player lobby with Teams set to 2, confirm teammates' territory
  merges (no contested band between two same-team stacks) and a claimed
  special becomes available to whichever teammate is fed next, per OWNER Q 1.
- Set Match timer to a short value with Sudden death on, watch the disk edge
  visibly crumble every 10 s and gift crates start appearing noticeably more
  often; let it run to a radius-8 tiebreak and confirm the larger-territory
  side wins if nobody captured first.
- From the Main Menu: open Sandbox, confirm no timer/territory refusal,
  exercise the block picker, special spawn menu, slow-motion, pause-physics
  and height-record tools. Open Tutorial and play all five steps end to end.
- Start a turn-based match (2+ instances), confirm the active player's HUD
  banner and that the turn only passes once the previous player's tower
  actually stops moving (or 6 s), not the instant the block lands.
- Set Tilt mode to Physical balance, build a lopsided tower near the disk's
  edge, and confirm it visibly tilts the disk under its own weight and eases
  back level once the tower is removed/rebalanced.
- Open Options from the Main Menu: switch graphics presets and confirm a
  visible reflection/shadow change; drag the volume slider and confirm it's
  audible immediately; rebind one keyboard action and one gamepad button and
  confirm both take effect in a match; point the custom music folder at a
  real folder of MP3s and confirm playback switches to it.

## Model routing

Sonnet for every package except B5's `game/Field.gd` diff specifically, which
the orchestrator should route through an Opus-reviewed pass given its
physics-architecture shape (see Known risks) even though Sonnet writes the
implementation; every other package here is ordinary implementation/rules/UI
work against interfaces this plan already specifies concretely, matching
M4/M5's own routing table. Run `python tools/route_model.py` per package at
dispatch per `docs/AGENT_WORKFLOW.md`; override only with a stated reason.

## Known limitations (planned, M6)

- **`GraphicsPreset` (C1) cannot toggle SSIL or volumetric fog** — neither
  render feature exists in the project yet (M7 presentation polish scope);
  the Low/Medium/High presets this milestone ships only control what already
  exists (`ssr_enabled`, MSAA, shadow atlas size). Revisit once M7 lands
  those effects.
- **GiftSpawner's rejection-sampling efficiency on sparse shapes (Cross,
  Ring)** is not optimized this milestone (A2a/A2b's own risk note) — a
  correctness non-issue, a possible "gifts feel rarer on this map" playtest
  note.
- **B5's PHYSICAL_BALANCE is a kinematic-torque approximation, not a literal
  dynamic RigidBody3D-on-a-joint** (OWNER Q 2) — spec-permitted, flagged for
  revisit if a real dynamic-body prototype is ever wanted.
- **Turn-based mode's ENet parity gets a scripted/manual check, not a
  dedicated new multiplayer harness** — same posture M4/M5 already took for
  their own replication additions riding an already-proven reliable-RPC path
  (`Events.turn_changed` is not new wire plumbing, just a new trigger for an
  existing signal).
- **Enabled-specials checklist (A4) introduces one sentinel value
  (`&"__none__"`) into `enabled_specials` rather than extending
  `MatchConfig`'s serialization shape** — the simplest fix that doesn't
  collide with the existing "empty means all" contract; revisit if a future
  milestone wants a real tri-state (all / some / none) representation
  instead of a sentinel string.

## Orchestrator decisions

<!-- Left empty for the orchestrator to record acceptance/routing decisions
     as packages are dispatched and reviewed. -->
