# Block Pool Selection & Block Builder: Design Options

Bead: `Bontago-1pi.17`. Planner output; design only, no code. Needs owner
answers (section 6) before any implementation dispatch. Base: `main` @ `1268f9d`.

Owner request (game_roadmap): "Players before each round get to select which
blocks they want to add to the pool, include more variations. Add a simple
block builder?"

## PAUSE POINT STATUS

- **No [ORIGINAL] rule is changed by the recommended path.** SPEC 2.4 (line
  169) tags only "base cube plus combinations; the exact original set is
  unknown" as [ORIGINAL]; the shape table, the weights and the bag are
  explicitly [NEW] ("Weighted random feed ... bag randomizer ... [NEW]",
  line 185). Section 1.0 ([ORIGINAL] description) says only "randomly supplied
  cube-based shapes".
- **FLAG (genuine owner pause):** *letting players choose their own blocks
  changes "randomly supplied"* from the [ORIGINAL] description (SPEC line 31,
  also 155: "each handling their own supplied piece"). A shared/opt-in pool
  that is still drawn randomly keeps the rule intact; per-player *direct*
  picking of the held piece would break it. The plan below keeps the draw
  random, so it is an owner-confirm, not a rule change. The owner must
  confirm that reading (Q1).
- Everything here is player-facing and changes lobby flow: owner decision
  required first (CLAUDE.md pause points). Ask through a Beads `decision`
  issue (`--label human --assignee Tony`); orchestrator creates it.

## 1. Current state (anchors)

- 11 `BlockShape` resources in `config/blocks/` (cube, domino, bar3, bar4, L3,
  L4, T4, S4, square4, slab6, pillar); matches the SPEC 2.4 table exactly.
  `BlockShape` (`config/blocks/BlockShape.gd`): `id`, `cells: Array[Vector3i]`,
  `weight`, `sloped_cells`, `mesh`; `load_all_shapes()` scans the directory
  sorted by id (also works in exported `.remap` builds).
- `config/BlockFeedConfig.gd` (`config/block_feed.tres`): `shapes` (empty =
  all), `weight_overrides` (parallel array), `stabilizer_ids`
  (`square4, slab6, cube`), `min_stabilizers_per_bag = 2`, `bag_multiplier =
  2.0`, `preview_count`.
- `core/feed/BlockBag.gd` (pure): bag = `round(weight*multiplier)` copies per
  shape (min 1), topped up with stabilizers, Fisher-Yates shuffled with a
  seeded RNG; `next()`, `peek()`; state clonable for deterministic peek.
- `autoload/match/MatchFeed._build_bags()` (line ~400): one `BlockBag` per slot,
  all sharing `Match._block_feed_config` (a preload, line 61), seed =
  `rng_seed + slot*1000003`. So today every player draws from the **same
  global pool**; there is no per-match or per-player pool.
- Mass = `cube_mass * cell count` (`game/BlockFactory.gd:99`); one
  `BoxShape3D` per cell. Cost scales with cell count.
- Network: `Events.feed_block_issued(slot, shape_id, next_shape_id)` carries
  **ids only**; clients resolve ids with a local `BlockShape.load_all_shapes()`
  index (`MatchFeed._shape_by_id`, `net/MatchNet.gd:1219`). So any shape must
  already exist on the client by id. `MatchConfig` serializes via
  `to_dict()/from_dict()` and carries `rng_seed`, so a pool list can ride it.
- Lobby: `ui/Lobby.gd` emits `start_requested(config: MatchConfig)`; a match is
  one "round" (no multi-round series exists; "before each round" = before
  match start, plus after a rematch, see Q2). Bots: `game/BotController.gd`
  reads `held_shape`, never chooses shapes.

## 2. Pre-round selection options

All options keep the draw random from the resulting pool (SPEC "randomly
supplied"). Output of every option: a `BlockPool` = `Array[StringName]` ids
(+ optional per-id weight) stored in `MatchConfig` (new field `block_pool`),
fed to `BlockBag` instead of the global config. Empty = today's behavior.

**Option A, host picks (smallest).** A "Block pool" section in the Lobby
advanced rules: checklist of all shapes (mirrors the existing specials
checklist, `Lobby._build_specials_checklist`), plus presets (Classic = all 11
original, Stackers, Chaos, Tiny). Host only; clients see a read-only summary.
Pro: no timing, trivially host-authoritative, deterministic. Con: no
per-player agency (the owner's wording "players ... select").

**Option B, shared pool vote/nominate (recommended).** Pre-match "Draft"
screen, `draft_seconds` (default 20, 5-60) after the lobby Start. Each player
toggles shapes (checkbox grid, each shape shown with a rotating 3D preview).
Each player has `picks_per_player` tokens (default 3; SPEC-style tunable in a
new `BlockPoolConfig`). The pool = union of the always-on base set
(`stabilizer_ids` + cube so no empty/unfair pool) + every shape that got >=1
pick; weight = base `weight` + `pick_bonus * (picks - 1)` capped by
`max_weight_mult`. Everyone draws from the same pool, so it is fair by
construction; picks shape the match but nobody can hold a private advantage.
Timer expiry or no input = no picks (base pool only); host start-early when
all players ready.

**Option C, per-player pools.** Each player picks N shapes for their *own*
bag. Most "player choice", but unfair (a player can load up on
slab6/square4, or deny themselves tall bars to turtle), needs per-slot balance
caps, and conflicts with "each handling their own supplied piece" only in
spirit. Needs a budget system (shape point cost = cell count + stability
tier) to be fair. Not recommended for v1; reserve as a variant of B.

**UI flow (all options, B detailed).** New scene `ui/BlockDraft.tscn`: grid of
shape cards; mouse click toggles a card; keyboard/gamepad: `ui_left/right/up/
down` move focus, `ui_accept` (A) toggles, `ui_cancel` (B) = clear, a new
`draft_ready` action (default Space / gamepad Y; added in
`tools/bootstrap_project.gd`, both bindings) marks ready; top shows tokens
left and the countdown ring (reuse HUD timer-ring style). Focus chain
wiring follows `Lobby._wire_focus_chain`.

**Fairness/balance notes.** (1) Always-on stabilizers keep the existing
"no long stabilizer drought" guarantee; the pool must satisfy
`min_stabilizers_per_bag` or `BlockBag` tops up (already does). (2) Cap
heavy/tall shapes' weight so a pool of only `bar4`/`pillar` stays playable.
(3) Pool-size minimum 4 shapes. (4) Bots (section 5) and humans vote the
same way, but bots are weighted so they cannot swing human votes. (5) Pool is
announced to all before play.

## 3. More variations (new `BlockShape` resources, no code change)

Each is a new `.tres` in `config/blocks/` (auto-picked by
`load_all_shapes()`). Coordinates are cell offsets (y up), 1 m cubes,
`weight` suggested. All are static-body safe at the 0.02 m margin; no new
physics.

| id | cells | shape | weight | notes |
|---|---|---|---|---|
| bar5 | 5 | 5 in a line, flat | 0.4 | bridge maker; rare |
| plus5 | 5 | flat plus: (1,0,0)(0,0,1)(1,0,1)(2,0,1)(1,0,2) | 0.6 | broad base |
| u5 | 5 | flat U: (0,0,0)(2,0,0)(0,0,1)(1,0,1)(2,0,1) | 0.6 | traps/encloses |
| corner4 | 4 | 3D corner: (0,0,0)(1,0,0)(0,0,1)(0,1,0) | 0.8 | the one chiral 3D piece |
| stair6 | 6 | staircase: (0,0,0)(1,0,0)(2,0,0)(1,1,0)(2,1,0)(2,2,0) | 0.5 | ramps |
| arch5 | 5 | upright arch: (0,0,0)(0,1,0)(1,1,0)(2,1,0)(2,0,0) | 0.5 | bridges, funny physics |
| cube8 | 8 | solid 2x2x2 | 0.25 | heavy anchor |
| plate9 | 9 | flat 3x3 | 0.25 | big stable base; add to stabilizers? (Q6) |

Mirror images (J/Z) are not needed: blocks rotate in 3D, so a pitch flip
yields the mirror. Total 19 shapes. Cells max 9; the SPEC 3.5 body limits are
per-block, so cost is ~9 box shapes worst case. These extend the [NEW]
shape table only; the `Classic` preset (the original 11) stays selectable.

## 4. Block builder

Scope options:

- **None** (cheapest): ship section 3 only.
- **Voxel builder, session-only (recommended phase 2):** `ui/BlockBuilder.tscn`
  from the Draft screen/main menu: a 5x5x5 grid editor (cap `max_cells` =
  8, `max_extent` = 3 per axis; both in `BlockPoolConfig`), click to add/remove
  cubes (gamepad: cursor with d-pad/stick, A add, X remove, LB/RB layer).
  Validated by pure `core/feed/ShapeValidator.gd`: non-empty, <= max cells,
  unique cells, **6-connected** (face-adjacent) via flood fill (no
  floating bits), bounds, normalized to min corner (0,0,0), and a canonical
  hash to dedupe against existing shapes under 24 rotations. Output =
  `CustomShapeDef` (RefCounted: `id` = `"c_" + hash`, `cells`).
- **Saved shapes:** `user://block_shapes/*.json` (cells only, no scripts or
  resources loaded from disk, to avoid arbitrary `.tres` loading), a
  library list in the builder; selecting up to `custom_per_player` (default
  1) adds them to the player's draft picks.

Constraints: max 8 cells keeps mass (<= 8 kg) and collision cost <= the
largest shipped shape (slab6 = 6, plate9/cube8 use rare weights); require
>= 2 cells (a cube already exists); mass is `cube_mass * cells` so heavy
shapes cannot exceed the cap. Custom shapes get a low default weight
(`custom_weight` 0.5, no stabilizer status).

Network: ids alone no longer suffice. At draft close the **host** validates
each submitted custom shape with `ShapeValidator` (never trusts the client),
assigns the pool, and puts the final `custom_shapes: Array[Dictionary]`
(`{id, cells}`, packed `Vector3i` components as bytes, same style as
`core/net/CircleWire.gd`) into the match-start payload. Clients build
`BlockShape` instances at match start and register them in the
`MatchFeed._shapes_by_id` / `MatchNet._shapes_by_id` indexes (those are
local indexes, so a small `ShapeRegistry` helper owned by core/ is needed so both
share one source). Cap payload: `max_custom_total` = 8 shapes per match.

## 5. Host authority, late join, bots

- **Host authority.** Clients send intents only: `draft_pick(shape_id)`,
  `draft_unpick`, `draft_ready`, `submit_custom(cells)` over `MultiplayerAPI`
  RPCs in a new `net/DraftNet.gd`; the host checks the phase, the token
  budget, the id exists in the offered list, the custom-shape rules and the
  rate (1 submit/s). The host resolves the pool, sets `MatchConfig.block_pool`
  and `custom_shapes`, and starts the match; no client computes the pool.
- **Determinism.** The pool order is sorted by id before `BlockBag` is
  built so the same `rng_seed` + same pool = same sequence.
- **Late join / reconnect.** `allow_mid_match_join` exists
  (`MatchConfig`); a joiner receives the final pool and custom shapes in the
  same start payload (they ride `to_dict()`), so they resolve every id; they
  skip the draft (base picks only). Reconnect during the draft restores the
  picks from host state.
- **Bots.** Bots never open the UI; at draft close each bot adds
  `bot_picks` (default 2) chosen by the host: weighted-random from the
  non-rare shapes, seeded from `rng_seed`, so replays are stable. They
  never submit custom shapes. The existing `BotController` is unchanged:
  placement already scores whatever `held_shape` it gets, and
  `BotPlacementScorer.flattest_orientations` handles any cells. Check bot
  scoring against 5-9 cell shapes (acceptance test).
- **Sandbox/hot-seat.** Sandbox keeps its full block picker
  (`force_next_shape`); hot-seat uses host-picks (Option A) since one screen.

## 6. Recommendation, packages, owner questions

**Recommended:** ship **Option B** (shared pool draft with the base set
always on) + section 3 shapes now; builder as **phase 2** (voxel builder,
8 cells, session + saved JSON). Option A (host checklist + presets) is built
first inside B because B reuses it as the fallback/skip path.

Interface stub package P0 (below) must land before consumers.

### P0, pool contract + stubs (Sonnet)
Owns: `config/BlockPoolConfig.gd`, `config/block_pool.tres`,
`core/feed/BlockPool.gd` (pure: `build(base_ids, picks, config) ->
Array[BlockShape]` + weights, sort by id), `config/MatchConfig.gd` (add
`block_pool: PackedStringArray` to `to_dict/from_dict`, default empty),
`tests/unit/test_block_pool.gd`. Tests: empty pool = today's behavior,
stabilizer guarantee, min size, determinism, round-trip of `to_dict`.

### P1, new shapes (Haiku)
Owns: 8 `.tres` in `config/blocks/` (section 3), `tests/unit/test_block_shapes_v2.gd`
(connected, unique cells, weights > 0, ids unique, loaded by
`load_all_shapes()`, mass = cells). Needs nothing. Parallel with P0.

### P2, feed wiring (Sonnet; needs P0)
Owns: `autoload/match/MatchFeed.gd` (`_build_bags()` uses
`BlockPool.build` when `config.block_pool` is non-empty),
`core/feed/BlockBag.gd` (accept an explicit shape/weight list),
`tests/unit/test_block_bag_pool.gd`. Tests: pool restricts draws, bag
determinism per slot unchanged, gifts/backlog unaffected.

### P3, Lobby presets + host checklist (Sonnet; needs P0, P1)
Owns: `ui/Lobby.gd`, `ui/Lobby.tscn` (shared hotspot, serialize with other
lobby work), `tests/unit/test_lobby_block_pool.gd`. Checklist + presets,
keyboard/gamepad focus chain.

### P4, draft screen + net (Sonnet or netcode; needs P0, P2)
Owns: `ui/BlockDraft.gd/.tscn`, `net/DraftNet.gd`, `autoload/Events.gd`
(signals `draft_started`, `draft_closed`), `tools/bootstrap_project.gd`
(`draft_ready` action), `tests/unit/test_draft_net.gd`. Tests: host rejects
over-budget/unknown/late picks, ENet client with simulated lag, timer expiry,
late joiner gets pool, headless gamepad events toggle a card.

### P5, bots + balance (Sonnet; needs P2)
Owns: `core/ai/BotDraft.gd`, `config/BotTuning.gd` (+ `.tres`),
`tests/unit/test_bot_draft.gd`, bench rows. Tests: seeded picks stable;
bot match of 8 with all 19 shapes runs the soak without errors.

### P6, builder (phase 2, Sonnet; needs P4)
Owns: `core/feed/ShapeValidator.gd`, `core/feed/ShapeRegistry.gd`,
`ui/BlockBuilder.gd/.tscn`, `net/DraftNet.gd` (append `submit_custom`;
reassign from P4), `tests/unit/test_shape_validator.gd`,
`test_custom_shape_net.gd`. Tests: connectivity, rotation dedupe, cap,
host rejects forged cells, clients see an identical shape.

Order: P0 and P1 parallel, then P2, then P3 and P4 and P5 parallel (P3 only
touches Lobby files; P4 and P5 are disjoint), P6 last. Each package <=10
files, targeted GUT only; the orchestrator runs the full gate once per batch.

### Owner questions (batch in one Beads `decision`, label human)

1. Is "random draw from a player-shaped pool" acceptable given the
   [ORIGINAL] "randomly supplied" description (SPEC lines 31, 155)? If the
   owner wants direct choice of the held piece, that is an [ORIGINAL] change
   needing explicit approval.
2. Which Option: A (host picks), B (shared draft, recommended) or C
   (per-player pools)? "Before each round" = before each match; is a
   rematch/series draft needed?
3. Draft length (default 20 s) and picks per player (default 3)? Skippable
   for LAN/quick play?
4. Is the always-on base set (stabilizers + cube) OK, or should players be
   able to remove anything?
5. Builder: none, phase-2 voxel builder (8 cells max), or larger? Saved
   shapes in scope? Should custom shapes be usable in ranked/public matches
   or only private ones (cosmetic stacking exploits)?
6. Approve the 8 new shapes and weights (section 3), and whether plate9 and
   plus5 count as stabilizers?
