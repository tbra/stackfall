# M5 — AI bots: build plan

Spec: §2.9 (AI bots — placement scoring, specials, difficulty), §2.6 (gifts &
specials, referenced by the bot's own special use), §2.5 (throw), §2.8
(lobby "Players / AI count & difficulty" row), §3.2 (`game/BotController.gd`
in the project layout), Part 4 "### M5 — AI bots". Base: `main` @ `0cc41cd`,
clean (worktree `M:/Bontago-worktrees/m5plan`, branch `wt/m5-plan`). Epic:
Bontago-d5c.

**Accept (Part 4 M5):** a Hard bot beats a passive player in under 10
minutes; an 8-bot headless match finishes without errors.

## What the existing code already gives this milestone for free

Read before assigning anything — these are not new interfaces, they are
already-committed, already-public seams M5 only has to call:

- `config/MatchConfig.gd:14,45-46` already has `enum AiDifficulty { EASY,
  NORMAL, HARD }`, `@export var ai_count: int`, `@export var ai_difficulty:
  AiDifficulty` — serialized (`to_dict`/`from_dict`), sanitized, and fully
  wired into `ui/Lobby.gd`'s `%AiCountSpin`/`%AiDifficultyOption` controls
  already (`ui/Lobby.gd:39-40,77-78,114,139,144,217-218,267-268`). Spec 2.8's
  table gives the whole lobby **one** shared difficulty for every bot, not a
  per-bot setting — this is an existing, already-shipped architectural
  decision, not something M5 redesigns.
- `core/rules/PlayerSlot.gd:7-8,21` already declares `var is_bot: bool =
  false` with the header comment "M2 fills these from MatchConfig in
  hot-seat; M3a fills `peer_id`... and **M5 sets `is_bot`**." Nobody sets it
  yet (confirmed by grep — zero writes to `.is_bot` anywhere in the tree
  except this declaration).
- **The one real gap `config/MatchConfig.gd:165-167`'s own comment names
  outright:** `clamp_to_connected_peers(peer_count)` currently does
  `player_count = clampi(peer_count, MIN, MAX); ai_count = 0` — it forcibly
  **zeroes every bot** the instant a human presses Start
  (`ui/Lobby.gd:401`, `_on_start_pressed()`). `tests/unit/
  test_match_config.gd:108-116` and `tests/unit/test_lobby.gd:203-216` both
  assert `ai_count == 0` with the literal message `"bots don't exist until
  M5"`. This is the one production behaviour change this milestone must make
  before any bot can ever occupy a real lobby-started match.
- `game/PlayerController.gd` is **not** touched by this plan. A bot never
  drives a `GhostPreview`/`PlayerController` — it calls `Match.request_place()`
  /`Match.request_throw()` directly, the same authoritative entry points
  `MatchPlacement.gd` documents as "every placement in the game goes through
  here, local or remote" (`autoload/match/MatchPlacement.gd:76-117`) and
  `request_throw()` (`:269-372`). This is what "bots must go through the same
  host-validated entry points, never bypass rules" means concretely: no new
  Match method, no shortcut into `_placement`/`_territory` internals.
- Every read a scorer needs already has a public accessor, so **no
  interface-stub package is needed for any other system** (unlike M4's
  `SpecialDef`/`SpecialEffect`, which genuinely did not exist yet):
  - Height/support at a candidate: `Field.world_from_disk_local(xz, y) ->
    Vector3` + `Node3D.to_local()` (inherited) + a bot's own
    `get_world_3d().direct_space_state.intersect_ray()` — the same technique
    `Field.raycast_down_disk_local()` already uses
    (`game/Field.gd:777-798`), just keeping the hit height instead of
    discarding it.
  - Territory/goal queries: `Match.raster()`, `Match.cell_grid()`,
    `TerritoryRaster.team_at()/is_contested()/is_hole()`
    (`core/territory/TerritoryRaster.gd:223-253`), `PlayerSlot.
    goal_positions_for(count, map_def)` (`core/rules/PlayerSlot.gd:62-65`,
    pure, callable directly with `Match.config.goal_flag_count`/`map_def()`).
  - Footprint/stability: `PlacementRules.footprint_cells(cells, basis,
    origin, cube_size, grid)` (`core/rules/PlacementRules.gd:105-157`) is
    still compiled and public even though live placement validation only
    uses the single-point check — a bot can use it for a stability estimate
    with zero new code elsewhere.
  - Orientation table: `BlockOrientations.get_basis(i)`/`count()`
    (`core/blocks/BlockOrientations.gd:23-30`).
  - Influence-radius estimate for "how much closer the territory edge gets
    to the goal": `InfluenceCircle.radius_for_height(height, tuning,
    field_radius)` (`core/territory/InfluenceCircle.gd:53-57`), pure and
    static.
  - Active specials to avoid/target: `get_tree().get_nodes_in_group(
    SpecialBehavior.GROUP)` (`game/specials/SpecialBehavior.gd:25`) — a
    plain Godot node group, and `SpecialBehavior.is_armed()`/
    `is_triggered()` are already public; a node's parent (`.get_parent()`)
    is the `Block` itself, so its `.global_position` needs no new getter on
    `SpecialBehavior.gd` at all. **This plan touches nothing under
    `game/specials/`.**
  - What special a bot is holding: `Match.held_special(slot_id) ->
    StringName` (`autoload/Match.gd:313-315`) already returns the real drawn
    id (e.g. `&"rocket"`) once P2c/the M4 roster landed — a bot's own
    special-use heuristics dispatch on this id directly.
  - Block placement pipeline reference: `BlockFactory.build(shape, tuning,
    slot_id, color) -> Block`, `BlockShape.bottom_center()` (the pivot
    convention every origin below already assumes).

## Package plan

### P0 — `BotTuning`/`BotDifficultyProfile` + the `clamp_to_connected_peers` fix

**Owns:** `config/BotDifficultyProfile.gd` (new), `config/BotTuning.gd`
(new), `config/bot_tuning.tres` (new), `config/MatchConfig.gd` (edit
`clamp_to_connected_peers()` only), `tests/unit/test_bot_tuning.gd` (new),
`tests/unit/test_match_config.gd` (edit the one assertion named above).
**Reads only:** nothing new — `MatchConfig`'s existing `PLAYER_COUNT_MIN/MAX`
constants.

```gdscript
# config/BotDifficultyProfile.gd
class_name BotDifficultyProfile
extends Resource
## Spec 2.9 "Difficulty: candidate count sampled, aiming error, reaction
## delay, defensive-specials use."
@export var candidate_count: int = 60          # spec 2.9's 40-120 range
@export var candidates_per_frame: int = 8      # time-slicing budget (perf)
@export var stability_raycast_count: int = 4   # footprint-corner raycasts/candidate
@export var aim_noise_m: float = 0.3           # random aiming error
@export var reaction_delay_s: float = 0.6      # delay after a block is issued
@export var uses_defensive_specials: bool = false
@export var uses_offensive_specials: bool = false

# config/BotTuning.gd
class_name BotTuning
extends Resource
@export var easy: BotDifficultyProfile
@export var normal: BotDifficultyProfile
@export var hard: BotDifficultyProfile
@export var weight_height: float = 1.0
@export var weight_goal_progress: float = 1.5
@export var weight_stability: float = 2.0
@export var weight_risk: float = 1.0
@export var risk_enemy_territory_radius_m: float = 4.0
@export var risk_active_special_radius_m: float = 5.0
## Per-bot phase offset so N bots' think-ticks don't all land on one frame
## (spec 2.9: "for multiple bots it spreads its thinking across several
## frames").
@export var think_phase_jitter_s: float = 0.4

func profile_for(difficulty: MatchConfig.AiDifficulty) -> BotDifficultyProfile:
    match difficulty:
        MatchConfig.AiDifficulty.EASY: return easy
        MatchConfig.AiDifficulty.HARD: return hard
        _: return normal
```

**`MatchConfig.clamp_to_connected_peers()` — the actual behaviour change:**

```gdscript
## Bontago-d5c (M5): a bot never needs a connected peer behind it -- only
## ai_count and the spec 2.8 range bound it. Humans always get seated first
## (peer_count is never reduced to make room for a bot); ai_count fills
## whatever room is left up to what the lobby asked for, trimmed rather than
## zeroed if there isn't enough room for all of it.
func clamp_to_connected_peers(peer_count: int) -> void:
    var wanted_total: int = clampi(peer_count + ai_count, peer_count, PLAYER_COUNT_MAX)
    ai_count = clampi(wanted_total - peer_count, 0, PLAYER_COUNT_MAX - peer_count)
    player_count = clampi(peer_count + ai_count, PLAYER_COUNT_MIN, PLAYER_COUNT_MAX)
```

With `ai_count == 0` this reduces to the exact old formula (`player_count =
clampi(peer_count, MIN, MAX)`, `ai_count` stays `0`) — every existing caller
that never touches `ai_count` sees no behaviour change. `# DECISION`: humans
outrank bots for the available seats when both compete (8 connected peers +
a stale `ai_count = 3` in the config trims to `ai_count = 0`, not to fewer
peers) — the simplest reading of "AI count" as "how many *extra* seats to
fill," not a request that can evict a connected human.

**Tests first:** `BotTuning.profile_for()` returns the right profile per
enum value; a loaded `bot_tuning.tres` has all three profiles non-null and
every numeric field positive. `clamp_to_connected_peers`: `ai_count == 0`
behaves exactly as before (the existing assertion, now asserting the bot
seats it fills instead of asserting they're zeroed); `peer_count=1,
ai_count=7` yields `player_count=8, ai_count=7`; `peer_count=8, ai_count=3`
yields `player_count=8, ai_count=0`; every result stays inside
`[PLAYER_COUNT_MIN, PLAYER_COUNT_MAX]`.

**Acceptance:** `tools/run_gut.ps1 test_bot_tuning,test_match_config` passes.
**Review:** recommended (rule-shaped change to lobby seat allocation, even
though `config/` isn't on the mandatory `core/`/`net/`/`autoload/`/physics/
rules review list). **Jev:** "small resource + a rule-shaped Resource method
edit with existing test coverage to update — kind=feature, review=optional."

---

### P1 — `BotController` skeleton + `is_bot` wiring — **the interface-stub package**

**Must land before P2, P3, P4 and P5 begin.** Creates the two files P2/P3
extend in place and the one flag P4/P5 read.

**Owns:** `game/BotController.gd` (new), `core/ai/BotCandidate.gd` (new),
`core/ai/BotPlacementScorer.gd` (new — **trivial-but-real** default: always
picks the first candidate generated, no scoring yet), `core/ai/
BotSpecialPlanner.gd` (new — trivial default: never throws, always falls
back to placing a held special like an ordinary block),
`autoload/match/MatchLifecycle.gd` (append: one line in `_build_slots()`),
`tests/unit/test_bot_controller.gd` (new), `tests/unit/
test_match_lifecycle.gd` (append: `is_bot` assertion), `tests/unit/
test_player_slot.gd` (append if it asserts the default `is_bot`; confirm at
dispatch).
**Reads only:** `autoload/Match.gd`'s public API (`held_shape`,
`held_special`, `is_release_locked`, `feed_seq`, `request_place`,
`request_throw`, `raster`, `cell_grid`, `config`, `slot`, `field`,
`registry`), `game/Field.gd`'s public queries (read-only — `to_local`,
`world_from_disk_local`, `map_def`), `game/BlockRegistry.gd`'s
`bodies_over_cells`, `core/blocks/BlockOrientations.gd`,
`core/rules/PlacementRules.gd`'s `footprint_cells`, P0's `BotTuning`.
**Must NOT** touch `game/specials/`, `net/MatchNet.gd`, or any file already
owned by another M4/M5 package.

**`_build_slots()` append (`autoload/match/MatchLifecycle.gd`):**

```gdscript
# inside the existing per-slot loop, right after PlayerSlot.new(...):
slot.is_bot = i >= _match.config.player_count - _match.config.ai_count
```

The trailing `ai_count` slots become bots; every slot before that stays a
human seat exactly as today (a connected peer fills it, or — outside a real
lobby — nothing does, unchanged from current behaviour). Hot-seat and
sandbox configs already force `ai_count = 0` (`game/Main.gd:149,209`), so
this is a no-op there; bots only ever exist through the networked lobby path
and P5's own headless entry point.

**Interfaces this package commits (typed; P2/P3 extend the *bodies*, never
these signatures, without touching `game/BotController.gd`):**

```gdscript
# core/ai/BotCandidate.gd
class_name BotCandidate
extends RefCounted
## One sampled placement spot (spec 2.9): a disk-local origin, an
## orientation, and what BotController's own raycasts found there. Pure data
## -- no scene-tree reference, so core/ai/ scorers can be unit-tested without
## a running Field.
var origin: Vector2 = Vector2.ZERO            # disk-local (x, z), BlockShape.bottom_center() pivot
var orientation_index: int = 0                 # BlockOrientations index
var support_height: float = 0.0                # disk-local (Field-local) Y of whatever is directly below
var footprint_cells: PackedInt32Array = PackedInt32Array()
var on_top_of_own_stack: bool = false


# core/ai/BotPlacementScorer.gd
class_name BotPlacementScorer
extends RefCounted
## Pure (CLAUDE.md "core/ ... no dependence on the scene tree"): every
## argument is a value type or an already-built core/ object.
##
## P1's own default body: `pick_best()` returns `candidates[0]` unscored,
## `score()` returns 0.0, `flattest_orientations()` returns `[0]`. P2 rewrites
## every body below; this file's *signatures* do not change.
static func score(
    candidate: BotCandidate,
    raster: TerritoryRaster,
    grid: CellGrid,
    team_id: int,
    goal_positions: PackedVector2Array,
    enemy_circle_centers: PackedVector2Array,
    active_special_positions: PackedVector2Array,
    tuning: BotTuning,
    field_radius: float
) -> float

## Spec 2.9 "the orientation (out of the 24) that gives the flattest base" --
## purely from `shape.cells` geometry, independent of terrain. Returns a
## short ranked list, not all 24; the caller still scores each returned index
## against the real site.
static func flattest_orientations(shape: BlockShape, max_count: int) -> Array[int]

## The one entry point BotController calls once a think-tick's candidate list
## is complete. Null only when `candidates` is empty.
static func pick_best(
    candidates: Array[BotCandidate],
    raster: TerritoryRaster,
    grid: CellGrid,
    team_id: int,
    goal_positions: PackedVector2Array,
    enemy_circle_centers: PackedVector2Array,
    active_special_positions: PackedVector2Array,
    tuning: BotTuning,
    field_radius: float
) -> BotCandidate


# core/ai/BotSpecialPlanner.gd
class_name BotSpecialPlanner
extends RefCounted

class BotSpecialAction:
    var should_throw: bool = false
    var throw_origin: Vector2 = Vector2.ZERO     # disk-local release point, inside own territory
    var throw_velocity: Vector3 = Vector3.ZERO   # world-space; caller still clamps via request_throw()
    var should_place_ordinarily: bool = true     # fall back to an ordinary placement candidate

## P1's own default body: always returns should_throw=false,
## should_place_ordinarily=true (spend the special like a normal block). P3
## rewrites the body; this signature does not change.
static func plan(
    held_special_id: StringName,
    own_home_position: Vector2,
    own_territory_sample_points: PackedVector2Array,
    enemy_circle_centers: PackedVector2Array,
    active_special_positions: PackedVector2Array,
    difficulty: MatchConfig.AiDifficulty,
    tuning: BotTuning
) -> BotSpecialAction
```

**`game/BotController.gd` — the Node, and the only file that calls into both
of the above.** One instance drives exactly one bot slot on the host, the
same "one controller per seat" shape `game/HotSeat.gd` already establishes
for a human (`@onready var _controller: PlayerController = $PlayerController`,
`bind_local_slot()`). Host-gated the same way every `Match`/`autoload/match/`
controller already is (`if not Net.is_host(): return`, true offline too, so
a bare unit test or a bench scene needs no networking to exercise this).

```gdscript
class_name BotController
extends Node

@export var tuning: BotTuning = preload("res://config/bot_tuning.tres")

func setup(slot_id: int, difficulty: MatchConfig.AiDifficulty, field: Field, registry: BlockRegistry) -> void
## Test seams, same DECISION as PlayerController/Match for a plain autoload
## GUT cannot double.
func set_match_provider(provider: Variant) -> void   # null = the real Match
func set_net_provider(provider: Variant) -> void      # null = the real Net
```

**Think cadence and time-slicing (perf-critical — see Risks):**
`_physics_process(delta)` no-ops unless `Net.is_host()` and `Match.state() ==
PLAYING`. Listens to `Events.feed_block_issued(slot_id, ...)` for its own
slot to reset a `reaction_delay_s + think_phase_jitter_s`-seeded countdown
(the jitter term is drawn once per bot at `setup()`, not re-rolled every
block, so one bot's own cadence is stable but different bots land on
different frames). Once the countdown clears and `not Match.
is_release_locked(slot_id)`, runs a small state machine — `GENERATING`
(builds up to `profile.candidates_per_frame` candidates per physics frame,
each with one support-height raycast plus
`profile.stability_raycast_count` footprint-corner raycasts, until
`profile.candidate_count` candidates exist or a hard frame-count cap is hit)
then `ACTING` (one frame: `BotPlacementScorer.pick_best()` or, when `Match.
held_special(slot_id) != &""`, `BotSpecialPlanner.plan()` first) then back to
`IDLE`. `profile.aim_noise_m` perturbs the chosen candidate's `origin` by a
small random 2D offset **before** the request goes out (so `PlacementRules.
validate_point()` still gets the final word — a noisy aim can legitimately
land the bot in a worse, even invalid, spot, which is the point of "random
aiming error"). Sends exactly one `Match.request_place(slot_id, world_origin,
orientation_index, free_quat, false, Match.feed_seq(slot_id))` (or
`request_throw(...)`) per completed think-cycle — the same call shape
`PlayerController._request_place()`/`_request_throw()` already use, feed_seq
included for the same idempotency defence, even though a host-local caller
could pass `-1`.

**Tests first (`test_bot_controller.gd`):** a bot slot with a held shape and
no lock, ticked past `reaction_delay_s`, sends exactly one `request_place`
call (a `FakeMatch` double, mirroring `test_match_flow.gd`'s existing
pattern); it sends nothing while release-locked or with no held shape;
setting `Net`'s provider to a non-host double makes it a no-op every frame;
two `BotController`s with different `think_phase_jitter_s` draws never fire
their first think-tick on the identical physics frame (a seeded-RNG,
deterministic check). `test_match_lifecycle.gd`: `_build_slots()` marks
exactly the trailing `ai_count` slots `is_bot == true` for `player_count=6,
ai_count=2`.

**Acceptance:** `tools/run_gut.ps1 test_bot_controller,test_match_lifecycle`
passes; `godot --headless --editor --path . --quit` stays clean.
**Review:** yes (`autoload/match/` change, and the new host-authoritative
driver every other M5 package builds on). **Jev:** "New Node + two stub core/
files + a one-line autoload append — kind=feature, review=yes (foundation
for four other packages)."

---

### P2 — Real placement scoring (parallel with P3)

**Depends on P1 committed.** **Owns:** `core/ai/BotPlacementScorer.gd`
(rewrites every function body; may append fields to `core/ai/
BotCandidate.gd` if a genuinely new fact is needed — flag it, don't silently
duplicate what `BotController` already computes), `tests/unit/
test_bot_placement_scorer.gd` (new).
**Reads only:** P1's committed `BotCandidate.gd` (may append), `core/
territory/TerritoryRaster.gd`, `core/territory/InfluenceCircle.gd`
(`radius_for_height`), `config/BotTuning.gd`. **Must NOT** touch
`game/BotController.gd` or `core/ai/BotSpecialPlanner.gd`.

**Scoring (spec 2.9's four named factors), concretely:**
- **Height gained:** `candidate.support_height` relative to the bot's own
  current max height (or simply the raw support height — reward building
  up, since a taller stack's influence radius grows per
  `InfluenceCircle.radius_for_height`).
- **Goal progress:** for the nearest goal flag (`PlayerSlot.
  goal_positions_for(config.goal_flag_count, map_def)`), approximate "how
  much closer its territory edge gets to the goal" as `distance(candidate.
  origin, nearest_goal) - InfluenceCircle.radius_for_height(candidate.
  support_height + shape_height, tuning, field_radius)` — a smaller number
  (even negative, meaning the estimated circle already reaches the goal) is
  better. `# DECISION`: this is an estimate off one candidate's own future
  circle, not a real solve of the territory graph (spec 2.9 does not demand
  an exact recompute per candidate, and doing a full `TerritorySolver.solve()`
  per one of up to 120 candidates would be the actual perf risk this plan
  flags below).
- **Stability:** the footprint's contact area under `candidate.
  footprint_cells` (via the corner raycasts `BotController` already ran) and
  whether the candidate's own center of mass — approximated as
  `candidate.origin` for a single-cube-pivot shape, or the shape's own
  centroid offset for a multi-cube one — falls inside the convex hull of
  supported cells. A candidate resting entirely on `on_top_of_own_stack ==
  true` with full contact scores higher than one balanced on a corner.
- **Risk:** a distance-based penalty inside
  `tuning.risk_enemy_territory_radius_m` of any `enemy_circle_centers` entry,
  and inside `tuning.risk_active_special_radius_m` of any
  `active_special_positions` entry (both team-agnostic, matching M4's own
  "explosions are team-agnostic" decision — a bot avoids friendly specials
  too, which is the safe default, not a new gameplay rule).

Combine as one weighted sum using `BotTuning`'s four weights;
`flattest_orientations()` ranks `shape.cells`' own bounding-box faces by
which one, resting flat, covers the most cube footprint at `y == min_y`
(pure geometry, no candidate/terrain involved) and returns the top
`max_count` distinct orientation indices whose basis rotates that face to
face-down.

**Tests first:** `score()` prefers a fully-supported flat candidate over a
corner-balanced one at equal height; prefers a candidate closer to (or
already covering) the goal over a farther one, all else equal; penalizes a
candidate inside `risk_enemy_territory_radius_m` of an enemy circle;
`flattest_orientations()` returns the identity orientation first for `cube`
(any face is equally flat, so index 0 is a valid, if arbitrary, answer) and
returns an orientation that lays `bar4`/`slab6` on their long/flat face
first, not standing on end; `pick_best()` returns the highest-scoring
candidate from a hand-built list, and null on an empty one.

**Acceptance:** `tools/run_gut.ps1 test_bot_placement_scorer` passes;
`godot --headless --editor --path . --quit` stays clean.
**Review:** yes (`core/` change; the scoring math is the one part of this
milestone with real game-feel consequences). **Jev:** "New pure scoring
module against a landed stub interface — kind=feature, review=yes."

---

### P3 — Real specials use (parallel with P2)

**Depends on P1 committed.** **Owns:** `core/ai/BotSpecialPlanner.gd`
(rewrites every function body), `tests/unit/test_bot_special_planner.gd`
(new). **Reads only:** P1's committed `BotSpecialPlanner.gd` signature,
`config/specials/SpecialDef.gd` (read-only, for the roster of known ids —
does not need to touch it), `config/BotTuning.gd`.
**Must NOT** touch `game/BotController.gd`, `core/ai/BotPlacementScorer.gd`,
or anything under `game/specials/`.

**Per-type heuristics (spec 2.9: "do not aim a Rocket as if it homes or a
Propeller as if it blows sideways"), keyed on `held_special_id`:**
- **Rocket** (§2.6: launches upward, no homing, explodes on fuel-out):
  throwing it does not aim at a target the way a homing weapon would — a bot
  instead **places** it (never throws) near the densest cluster of
  `enemy_circle_centers`, so its untargeted upward launch and eventual blast
  radius has the best chance of catching something. `should_throw = false`.
- **Bomb/DaBomb** (impact-activated, no proximity trigger by the landed
  code): thrown *at* the nearest enemy cluster, since an impact is what
  activates it — `should_throw = true`, `throw_origin` inside the bot's own
  territory nearest that cluster, `throw_velocity` aimed at it, capped by
  `SpecialTuning.throw_max_speed` (the actual clamp still lives in
  `MatchPlacement.request_throw()`; this planner only picks a reasonable
  pre-clamp velocity).
- **Volcano** (self-erupting, no target needed): placed defensively near the
  bot's own weakest/most-contested border when `uses_defensive_specials`,
  else near the enemy cluster when `uses_offensive_specials`; never thrown
  (an eruption doesn't benefit from a throw's flight time).
- **Earthquake/Anvil/Propeller** (self-triggering tilt effects — landed
  `EarthquakeEffect.gd`/`AnvilEffect.gd`/`PropellerEffect.gd`, read-only):
  placed near the disk edge farthest from the bot's own home (a bigger lever
  arm on the tilt), only when `uses_defensive_specials` or
  `uses_offensive_specials` is true for at least one — otherwise placed
  ordinarily (`should_place_ordinarily = true`, matching P1's own default),
  since an Easy bot (`difficulty == EASY`, both flags false per P0's
  defaults) should not use any of the disk-affecting specials with intent.
- **Jumping Bean** (hops, punches holes — a rules consequence, not just
  physics): placed near the bot's own territory edge nearest an enemy's home
  flag when `uses_offensive_specials`, since its hop-hole can threaten a
  home flag exactly like a natural hole (M4's own decision, `docs/
  M4_SPECIALS_PACKAGES.md` "Open question 2").
- **Any unrecognized id** (a future M8 special, or the roster empty):
  `should_place_ordinarily = true`, the same safe default P1 already ships —
  this file must never crash on an id it doesn't recognize.

**Tests first:** `plan(&"rocket", ...)` never sets `should_throw`; `plan(&"bomb",
...)` sets `should_throw = true` and aims `throw_velocity` toward the nearest
of a hand-built `enemy_circle_centers` list; an `EASY` difficulty with both
`uses_*_specials` false always returns `should_place_ordinarily = true`
regardless of the id; an unrecognized id falls back the same way; every
returned `throw_velocity` has a finite length (no NaN/zero-direction crash
when `enemy_circle_centers` is empty — falls back to placing ordinarily
instead of throwing at nothing).

**Acceptance:** `tools/run_gut.ps1 test_bot_special_planner` passes;
`godot --headless --editor --path . --quit` stays clean.
**Review:** recommended, not mandatory (pure `core/ai/` logic with no
physics side effects of its own — `request_throw()`'s own guards are the
real safety net if this ever aims badly). **Jev:** "New pure heuristic
module against a landed stub interface — kind=feature."

---

### P4 — Lobby integration: bots visible in the roster (parallel with P2/P3)

**Depends on P1 committed** (reads `slot.is_bot`, which does not exist
before P1 lands). **Owns:** `ui/Lobby.gd` (append to `_build_roster()`/
`_apply_roster()` only), `tests/unit/test_lobby.gd` (append — serialize
after P0's own edit to this file lands, since both touch it; a fresh
worktree base must include P0's committed change first).
**Reads only:** `config/MatchConfig.gd` (`ai_count`, `player_colors`),
`core/rules/PlayerSlot.gd` (`is_bot`, read-only).
**Must NOT** touch `ui/Lobby.tscn` — every roster row is already built
dynamically (`HBoxContainer`/`ColorRect`/`Label` in `_apply_roster()`,
`ui/Lobby.gd:313-332`), so a bot row needs no new scene node.

**Work.** `_build_roster()` (the host's own outbound publish, `ui/
Lobby.gd:298-310`) today only ever iterates `net_provider.peer_ids()` —
connected humans. Append one synthetic entry per bot seat, `slot_id` running
from `player_count - ai_count` to `player_count - 1` (matching P1's own
`_build_slots()` formula, so the lobby preview and the eventual real slots
never disagree about which ids are bots), `name = "Bot %d (%s)" % [index,
["Easy", "Normal", "Hard"][config.ai_difficulty]]`, `ready = true` (a bot is
always ready — `all_peers_ready()`'s own aggregate, which only iterates real
peers, is untouched by this). `_apply_roster()` needs no change: it already
reads `slot_id`/`name`/`ready` off whatever dictionary array it's handed,
generically.

**`# DECISION` (bot names/colours, minor ambiguity, no owner sign-off
needed):** `"Bot %d (%s)"` naming and the existing per-slot `player_colors`
palette (already indexed by `slot_id` for every seat, human or bot — no
separate bot colour scheme). Simplest reasonable option; revisit in M7
presentation polish if it reads poorly in the actual UI.

**Tests first:** a lobby with `player_count=6, ai_count=2` and 4 connected
peers shows 6 roster rows total, the last 2 labelled `"Bot 1 (...)"`/`"Bot 2
(...)"` in the configured difficulty; `all_peers_ready()`'s existing
peer-only aggregate is unaffected (a lobby with bots but no human peers
ready still can't Start until real peers are).

**Acceptance:** `tools/run_gut.ps1 test_lobby` passes; a manual windowed
check (owner step below) that the lobby's player list actually shows bot
rows once `AiCountSpin` is raised.
**Review:** not required (UI-only, per `docs/AGENT_WORKFLOW.md`'s "UI,
tooling and docs packages skip independent review"). **Jev:** "Roster
display append, no new scene nodes — kind=feature, review=no."

---

### P5 — Headless bot match: `--bots=N` and the 8-bot acceptance harness

**Depends on P1 committed** (needs a real `BotController` to instantiate;
does **not** need P2/P3's real scoring — a trivially-scoring bot that always
places its first candidate is enough to prove "finishes without errors").
**Owns:** `game/Main.gd` (append: `--bots=<n>` cmdline parsing and bot
instantiation in the match-world build/teardown — this milestone is the only
one touching this file, so the normal implementer-dispatch rule applies
despite the file's own "nobody but the integrator owns this" header comment;
flag to the orchestrator if a concurrent milestone also wants `Main.gd`
during this package's window), `tests/bench/bench_headless_bots.gd` + `.tscn`
(new), `tests/unit/test_headless_bot_match.gd` (new, or append to
`tests/unit/test_sandbox.gd` if the existing `Main` test fixture there is
reusable — confirm at dispatch).
**Reads only:** P1's committed `BotController.gd`, `autoload/Net.gd`'s
existing `apply_command_line()`/`OS.get_cmdline_user_args()` parsing
convention (`game/Main.gd:214-246`'s own `_sandbox_player_count()`/
`_sandbox_force_special_arg()` are the precedent to follow, not touch).

**`game/Main.gd` work:**
1. A new `_bots_arg(args) -> int` parser, same "-"-stripping/`PREFIX`
   convention as `_sandbox_player_count()`/`_sandbox_force_special_arg()`
   (`game/Main.gd:221-246`), reading `--bots=<n>`.
2. When `--headless-host` was given **and** `--bots=<n>` (n > 0) is present,
   skip the normal Lobby wait-for-Start path (a headless process has no
   human to click Start) and build the match directly, the same shape
   `_start_sandbox_match_with_args()` already uses: `Match.register_world(...)`
   then `Match.start_match(config)` with `config.ai_count = n`,
   `config.player_count = n` (every seat a bot; `--players=<n2>` may still
   raise `player_count` above `n` to leave human seats idle, matching
   `--sandbox`'s own `--players=` precedent, but is not required for the
   acceptance criterion), `config.hot_seat = false`, `config.sandbox =
   false` (a real match, real timers/cadence — the whole point is proving
   the real feed/territory/win loop survives 8 concurrent bots, not
   sandbox's relaxed rules).
3. **Every** match-world build that has `Match.config.ai_count > 0` —
   this headless path **and** an ordinary networked lobby match — needs one
   `BotController` per bot slot, instantiated in `_build_match_world()`
   (`game/Main.gd:336-372`) right alongside `_hot_seat`, and freed in
   `_end_match_world()` (`:375-393`) the same way. This is the one piece of
   real, shared wiring P4's lobby-only work does not itself provide — done
   here, not duplicated in a P4 append, since `_build_match_world()`/
   `_end_match_world()` are this file's own functions and P4 does not touch
   `game/Main.gd` at all.

**Tests first:** `_bots_arg(["--bots=8"]) == 8`; `_bots_arg([]) == 0`
(feature off by default, so every existing `--headless-host`-only command
line is unaffected); a scripted `_start_headless_bot_match_with_args(["--
bots=4"])` (the same explicit-args seam `_start_sandbox_match_with_args()`
already demonstrates) builds a `PLAYING` match with 4 bot slots and no
`HotSeat`/`PlayerController` instantiated.

**`tests/bench/bench_headless_bots.gd`/`.tscn` — the milestone's graded
harness**, following `tests/bench/bench_specials_chain.gd`'s exact shape
(one `BENCH_HEADLESS_BOTS result=PASS|FAIL` line, `get_tree().quit()`): builds
a `Field`/`BlockRegistry`/`Match` fixture directly (no `Net`/`Lobby`, matching
`bench_specials_chain.gd`'s own "bench scenes build the fixture, not the
production menu path" precedent) with `player_count = ai_count = 8`, one
`BotController` per slot, `gifts_enabled = true` and every landed special
enabled (so a real 8-bot match exercises the whole M4 surface too, not just
placement), runs for a fixed sim duration (long enough for several placement
windows and at least one likely special claim/chain at the test's own seeded
`rng_seed`), and fails if any `push_error`/uncaught script error was logged
during the run (piped through `tools/triage_log.py`, per CLAUDE.md's "Use it
on the M5 bot matches") **or** if the match never reaches at least one
`Events.player_eliminated`/`Events.match_won`/a fixed number of successful
placements — proving "finishes without errors" is actually about the match
*running*, not merely "the process didn't crash in the first second."

**The literal owner-facing gate (manual + CI, not this file's own unit
test):** `godot --headless --path . -- --headless-host --bots=8 2>&1 | python
tools/triage_log.py` — exit code from `triage_log.py` gates on a confident
likely-bug; a clean run prints the boot line, eight bot slots issuing
blocks, and (depending on `--match-timer`/win conditions) either a natural
win or an indefinite PLAYING state that must be bounded by a `--seconds=<n>`
flag this package also adds (`Main.gd`'s own `_ready()` calling `get_tree().
create_timer(n).timeout` → `get_tree().quit(0)` when `--bots=` is present, so
the acceptance command is not left to hang forever without a real win
condition).

**Acceptance:** `tools/run_gut.ps1 test_headless_bot_match` passes;
`godot --headless --path . res://tests/bench/bench_headless_bots.tscn`
prints `BENCH_HEADLESS_BOTS result=PASS`; the literal command above run once
by hand/CI, piped through `tools/triage_log.py`, reports no likely bug.
**Review:** yes (`game/Main.gd` change, even though scoped to one milestone's
exclusive window — the file's own header note about shared ownership makes
any edit here worth a second look). **Jev:** "Cmdline parsing append +
lifecycle wiring in the one file every milestone is cautious about —
kind=feature, review=yes."

---

### P6 — Acceptance bench: Hard bot beats a passive player in under 10 minutes

**Depends on P1, P2 and P3 all committed** (needs real scoring and real
special use — a trivially-scoring Hard bot cannot be expected to win
reliably). **Owns:** `tests/bench/bench_bot_vs_passive.gd` + `.tscn` (new).
**Reads only:** everything P1-P3 committed; follows P5's own
`Field`/`BlockRegistry`/`Match`-direct fixture pattern (precedent, not a file
dependency).

**"Passive player", defined here (a test-harness contract, not a new
gameplay rule):** a second slot that never receives any intent at all — no
`PlayerController`, no `BotController`, nothing. Its held block still
auto-drops at `MatchPlacement.default_ghost_origin(slot_id)` every window
(`autoload/match/MatchPlacement.gd:676-681`, "the slot's own home flag
position is the honest stand-in") exactly as the existing auto-drop path
already guarantees for any silent slot — so a passive player is not "does
nothing at all," it is "plays exactly as badly as a human who never once
touches the controls," which is the fairest apples-to-apples reading of
spec 2.9's acceptance line.

**`# DECISION` (bench-only, not a gameplay change):** `gifts_enabled =
false` for this specific bench. The acceptance criterion is about placement/
territory play beating a do-nothing opponent inside a time bound, and a
random special claim (by either side) would make the bench's own pass/fail
non-deterministic even at a fixed `rng_seed` (a crate's claim depends on the
live territory solve, not the seed alone once physics settling time varies
run to run). Real special use is already proven deterministically by P3's
own unit tests; this bench isolates the placement-scoring win condition.

**Setup:** `player_count = 2`, slot 0 = one `BotController` at `ai_difficulty
= HARD`, slot 1 = passive (above). `hole_mode = TEMPORARY` (the fidelity
default), `goal_flag_count = 1`, everything else at `config/
match_defaults.tres`. Runs physics ticks until `Events.match_won` fires or a
`600` real-seconds (`10 * 60 * Engine.physics_ticks_per_second` ticks)
timeout, whichever comes first.

**Tests first:** none beyond the bench itself — this is a single graded
scenario, same as `bench_specials_chain.gd`'s own "correctness smoke test,
not a benchmark" framing, just for a win-condition instead of a frame-time
budget.

**Acceptance:** `godot --headless --path . res://tests/bench/
bench_bot_vs_passive.tscn` prints `BENCH_BOT_VS_PASSIVE result=PASS
winner_team=0 elapsed_s=<n>` with `elapsed_s < 600`; **run at least 3 times
with different `rng_seed`s** before calling this milestone's acceptance
satisfied — a single seeded pass is not proof the Hard bot reliably wins
(spec says "beats a passive player," not "beats it once with a hand-picked
seed"). Record all seeds/results in the Beads checkpoint.
**Review:** recommended (the one scenario this whole milestone's acceptance
literally hinges on). **Jev:** "Graded acceptance scenario over three
already-reviewed packages — kind=gate, review=yes."

## Dispatch order and parallelism

1. **P0** lands first (or in the same checkout ahead of P1 if a second
   worktree isn't ready yet) — nothing depends on it being separate, but P1
   reads `BotTuning`.
2. **P1** lands once P0 is committed — the interface-stub package. Nothing
   else in this milestone can start until `game/BotController.gd`,
   `core/ai/BotCandidate.gd`, `core/ai/BotPlacementScorer.gd`, `core/ai/
   BotSpecialPlanner.gd` and `PlayerSlot.is_bot` are all real and compiling.
3. **P2, P3, P4 and P5 run fully in parallel once P1 is committed** —
   four disjoint file sets (`core/ai/BotPlacementScorer.gd` only;
   `core/ai/BotSpecialPlanner.gd` only; `ui/Lobby.gd` only; `game/Main.gd` +
   new bench/test files only). P4's own `tests/unit/test_lobby.gd` append
   must serialize behind P0's own edit to that same file (both touch it;
   trivial to order since P0 lands first regardless).
4. **P6** starts once P2 and P3 are both committed (needs real scoring and
   real special use to have any chance of winning reliably); P5's harness
   pattern is a precedent to follow, not a file dependency, so P6 does not
   need to wait on P5 finishing, only on P2/P3.
5. Each merge passes `godot --headless --editor --path . --quit` (no errors,
   no new warnings) and its own targeted GUT set; the orchestrator runs the
   full suite once per merged batch, same as every other milestone.
6. **Integration** confirms `game/Main.gd`'s bot instantiation in
   `_build_match_world()`/`_end_match_world()` (P5) actually fires for an
   ordinary lobby-started match with `ai_count > 0` too, not only the
   headless entry point — a mixed human+bot lobby match is the other half of
   this milestone's own acceptance line ("mix bots and humans in the
   lobby"), and no package above has a dedicated end-to-end test for that
   combination; a short manual windowed check (below) is the practical
   verification until/unless the integrator adds one.

## Tunables introduced — no magic numbers (CLAUDE.md)

| Resource | Owner | Fields (defaults) |
|---|---|---|
| `config/bot_tuning.tres` (`BotTuning`) | P0 | `weight_height` 1.0, `weight_goal_progress` 1.5, `weight_stability` 2.0, `weight_risk` 1.0, `risk_enemy_territory_radius_m` 4.0, `risk_active_special_radius_m` 5.0, `think_phase_jitter_s` 0.4 |
| `BotDifficultyProfile` (×3: easy/normal/hard) | P0 | `candidate_count` (suggest 40/70/110, spec's 40-120 range), `candidates_per_frame` 8, `stability_raycast_count` (suggest 2/4/6), `aim_noise_m` (suggest 0.6/0.3/0.05), `reaction_delay_s` (suggest 1.2/0.6/0.2), `uses_defensive_specials` (false/true/true), `uses_offensive_specials` (false/false/true) |

Every provisional default above is a starting value for playtesting, not a
claim of original fidelity (spec 2.9 gives no numbers at all — it names only
the four scoring factors and the four difficulty axes).

## Known risks

- **Perf: candidate scoring at 60 Hz must be time-sliced, and it is the one
  place this plan asks an implementer to actually engineer something, not
  just port a formula.** Up to 120 candidates × (1 support raycast + up to 6
  stability raycasts) is ~800 physics-world queries for **one** bot's **one**
  think-cycle; 8 Hard bots thinking in the same window without staggering
  would be ~6,400 queries in one or two frames. P1's `think_phase_jitter_s`
  stagger plus `candidates_per_frame`'s per-frame budget are the two
  mitigations this plan specifies; P5's `bench_headless_bots` harness is
  where this actually gets measured (average `Performance.
  TIME_PHYSICS_PROCESS` across the whole 8-bot run, following
  `bench_specials_chain.gd`'s own pattern) — **if that number is not
  comfortably inside the 60 fps budget, the fallback (not built now,
  flagged as a follow-up if triggered) is lowering `candidates_per_frame`
  and `candidate_count` further before spending engineering time on a
  smarter raycast batching scheme.**
- **Determinism for the seeded acceptance bench (P6):** `MatchConfig.
  rng_seed` already makes the block bag and gift spawner deterministic
  (`autoload/match/MatchFeed.gd:198-206`, `autoload/match/MatchGifts.gd:308-
  321`), but a bot's own `aim_noise_m` perturbation and `think_phase_jitter_s`
  stagger are new sources of randomness this milestone introduces — both
  **must** draw from a `RandomNumberGenerator` seeded off `Match.config.
  rng_seed` (the same `+ large_odd_stride` convention every other per-system
  RNG in this codebase already uses — see `MatchFeed._build_bags()`,
  `MatchGifts._ensure_rng()`/`_ensure_special_rng()`), never
  `randi()`/`randf()`'s global state, or P6's "run 3 seeds" acceptance step
  cannot actually reproduce a failure for a bug report.
- **`clamp_to_connected_peers()`'s new humans-outrank-bots rule (P0) changes
  observable lobby behaviour** the instant it lands, before P1-P6 exist: a
  host with `ai_count > 0` set (impossible to reach today, since nothing
  sets it non-zero in the shipped UI's own default, but reachable the
  moment a host raises `AiCountSpin`) will see `player_count` grow past the
  connected peer count for the first time. This is exactly the intended new
  behaviour, not a bug, but it means P0 cannot be considered "done" merely
  because its own two unit tests pass — the integrator should also confirm
  a lobby with `ai_count > 0` and no P1-built `BotController` yet (P0 landing
  ahead of P1 in a serialized single-checkout dispatch) does not crash
  `Match.start_match()` by seating a slot nobody drives at all (it should
  behave exactly like today's "a lobby seat above the connected peer count,"
  which already exists and already just sits idle/auto-drops — not a new
  failure mode, but worth a explicit confirmation before P1 lands).

## Testing without a second PC, without real hardware for fps

Same posture M3a/M4 already established: GUT unit tests for every pure rule
(`BotTuning`, `MatchConfig`, `BotPlacementScorer`, `BotSpecialPlanner`,
`BotController`'s own cadence/gating) run headless and fast, with `FakeMatch`/
`FakeNet`-style doubles for the host-authority gate, matching `test_match_
flow.gd`'s and `game/PlayerController.gd`'s own established seam pattern.
`tests/bench/bench_headless_bots.tscn` and `bench_bot_vs_passive.tscn` give
repeatable headless regression numbers; the 60 fps claim implicit in "8 bots
without errors" carries the same `bench_rain.gd`/`bench_specials_chain.gd`
caveat every prior milestone's headless timing already does — a windowed run
on real hardware (manual owner step below) is the only way to actually see
it, not merely time it.

## Manual owner steps

- Host a lobby, raise `AiCountSpin` above 0 with fewer human peers than
  `PlayerCountSpin`, confirm the roster list shows bot rows (P4) and that
  pressing Start actually seats and drives them (P5's `Main.gd` wiring) —
  this is the one "mix bots and humans" end-to-end path no automated test in
  this plan directly covers.
- Watch one Hard bot play for a few minutes in a windowed run: confirm it
  visibly builds toward the goal flag rather than placing at random, uses a
  claimed special sensibly for its type (a Rocket placed rather than thrown,
  a Bomb thrown at a cluster), and never places somewhere `PlacementRules`
  would refuse (a rejected-and-retried bot is not a bug, but a bot that
  *only* ever gets rejected would be).
- Run `godot --headless --path . -- --headless-host --bots=8` by hand once,
  piped through `python tools/triage_log.py`, and read its actual summary
  rather than trusting exit code 0 alone.

## Model routing

Sonnet for every package. None of this milestone's work is the kind of
"failure mode is silent and broad, physics-shape-redesign" reasoning M4's P0
needed Opus for — every package here is new, disjoint, unit-testable logic
against interfaces that already exist (or, for P1, a small and fully
specified stub). The orchestrator still runs `tools/route_model.py` per
package at dispatch per `docs/AGENT_WORKFLOW.md`; override only with a
stated reason.

## Open questions for the owner

None of this milestone's own scoring/heuristic choices rise to "changes
rules, game feel, scope, or player-facing behaviour in a way the spec
doesn't settle" — spec 2.9 already names the four scoring factors and the
four difficulty axes; every number and formula above is a `# DECISION`-level
implementation detail (explicitly flagged as such throughout each package
section), not a rule change, and none of them touch an `[ORIGINAL]`-tagged
rule. Two items are worth the orchestrator's attention even though they
don't need a `bd human` decision issue:

1. **Bot names/colours** (P4): `"Bot N (Difficulty)"` + the existing
   per-slot palette. Purely cosmetic; flagged in case the owner has a
   preference before M7 presentation polish revisits it anyway.
2. **One shared `ai_difficulty` for every bot in a match** is an
   already-existing `MatchConfig`/`ui/Lobby.gd` design (predates this
   milestone, matches spec 2.8's own single-row table) — this plan does not
   redesign it into a per-bot-slot difficulty, which would be materially
   more `MatchConfig`/lobby-UI surface for a feature the spec table doesn't
   ask for. Flagged so the owner can say so explicitly if a mixed-difficulty
   lobby turns out to matter before M6.

## Known limitations (planned, M5)

- **`BotSpecialPlanner`'s per-type heuristics cover only the seven landed
  M4 specials** (Rocket, Bomb, Volcano, Earthquake, Anvil, Propeller,
  Jumping Bean); Magnet/Freeze/Glue/Gravity Well are M8 scope and fall back
  to `should_place_ordinarily = true` until M8 lands its own effects and this
  file is revisited.
- **No per-bot difficulty within one match** (see "Open questions" above) —
  every bot in a lobby shares `config.ai_difficulty`.
- **`bench_headless_bots`/`bench_bot_vs_passive`'s pass/fail is a headless
  timing/behaviour proxy**, the same caveat every prior milestone's bench
  scenes already carry — a windowed run on real hardware (manual owner step
  above) is the only way to verify the *feel* of 8 bots playing at once, not
  just that the process didn't error out.
- **A mixed human+bot lobby match has no dedicated automated end-to-end
  test in this plan** (see the Integration order's own note) — covered only
  by the manual owner step until/unless a follow-up adds one.

## Orchestrator decisions

<!-- Left empty for the orchestrator to record acceptance/routing decisions
     as packages are dispatched and reviewed. -->
