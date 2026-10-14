# Bontago-1t5.52: bot tower failures in Reach the Sky. Diagnosis and design for 1t5.53, 1t5.54 and 1t5.55

Planner: stackfall-planner (Opus override). I only read main 363f9887; I edited nothing in the repo and launched no Godot runs or bot matches.
I also read the in-flight 1t5.51 candidate (M:/Bontago-worktrees/bot-disc, wt/bot-disc 4ba2edab, reviewed and approved, not yet landed).

## A. Answers to the owner's questions

**Do the bots rotate blocks?** Yes, but only in 90-degree steps, and the maths behind it was wrong.
- Each piece has 24 axis-aligned orientations. The bot reduces them to at most 6 distinct ones: `core/ai/BotStatics.gd:115-145`, `max_orientations_per_shape` 6.
- It never uses free rotation. It always sends `Quaternion.IDENTITY` (`game/BotController.gd:1057-1058`).
- At the territory frontier it picks the tallest orientation under a tip-risk cap, so a pillar stands up there (`core/ai/BotCandidateGen.gd:165-183`, `tip_risk_max` 0.4).
- On a tower top it picks the 2 least risky orientations, then the lowest of them (`BotCandidateGen.gd:184-194`). So pillars lie flat on towers: +1 m per piece instead of +3 m.
- The bot's own model of a rotated piece sits 0.5-1.4 m away from where the piece actually spawns (root cause B1 below).
- Until 1t5.51, a piece lying on its side also spawned half inside the disc and fell through it.

**Do they plan ahead?** Hardly. Every piece is a one-move decision with no physics prediction.
- The next piece is known but nothing uses it. `BotWorldView.next_shape` is set (`core/ai/BotWorldView.gd:45,104`) and no planner reads it.
- A physics rollout is not possible from script: `PhysicsServer3D.step` is not exposed (`docs/BOT_AI_REDESIGN.md` 2.2 row B).
- The look-ahead that does exist is short:
  - whether an enemy circle could grow over the block's base with one placement (`core/ai/BotEvaluator.gd:221-258`);
  - Hard looks 3 m further ahead for threats (`config/bot_tuning.tres:91-107`, `threat_lookahead_m` 3.0);
  - landing points of falling gifts and incoming specials (`BotEvaluator.gd:114-123`);
  - a habit of keeping the same plan for at least 3 pieces (`core/ai/BotStrategy.gd:79-106`).
- Nothing plans a tower as a sequence of pieces, such as a wide base first, then height.

**Do they have strategies?** Yes, chosen fresh for each piece, but for Reach the Sky the strategy is one rule: "stack on my highest settled block".
- Every piece gets a plan: race, anchor, finish, hold, defend, strike, siege or area (`BotStrategy.gd:34-74`).
- In Reach the Sky the default plan is "build on my tower" (ANCHOR). It aims at the bot's own tallest *settled* block (`BotStrategy.gd:143-148`, target from `autoload/match/MatchTerritory.gd:417-424` via `game/BlockRegistry.gd:432-444`).
- Defend and strike can interrupt it when an enemy circle threatens.
- It has no idea of base width, keeping a tower centred, or giving up on a collapsed pile.

## B. Ranked root causes

### 1. The bot's model of where its piece lands is offset from where it actually spawns (precision, centre of mass; every tier)
- The bot models each cube at `origin + B*cell`:
  - `BotStatics.orientation_info` `:86-97`;
  - the footprint via `PlacementRules.footprint_cells:128-131` from `BotCandidateGen._try_add:379-381`.
- The spawned body puts each cube at `origin + B*(cell - bottom_center())`:
  - `game/BlockFactory.gd:132-134`;
  - checked by `autoload/match/MatchPlacement.gd:757-761`.
- Every shape's cells start at (0,0,0), so the model is shifted by `B*pivot`. Shift for an unrotated piece:

  | Shift | Shapes |
  |---|---|
  | 0 | cube, upright pillar |
  | 0.5 m | domino, L3, L4 |
  | 0.71 m | square4, corner4, cube8 |
  | 1.0 m | bar3, T4, S4, arch5, stair6 |
  | 1.12 m | slab6, u5 |
  | 1.41 m | plate9, plus5 |

- Consequences:
  - The support probes (`core/ai/BotThink.gd:396-413`) and the tip-risk check (`BotStatics._risk:194-214`) look at the wrong patch.
  - Hard takes the single best-scoring site, so it reliably picks sites where the *model* is supported. The real piece then lands shifted by `-B*pivot`, on an edge or corner: the owner's "places on corners and edges".
  - If the real footprint clips a neighbouring tower, the host lifts the piece clear (`MatchPlacement._lift_pose_clear:702-733`, up to `spawn_clearance_max_raise` 20 m, `config/ghost_tuning.tres:54`). The piece then drops onto that tower's top edge. Blocks are bouncy (`block_bounce` 0.4, `config/physics_tuning.tres`). This is the "falls off and knocks the tower" sequence.
- The height part of the same mistake is 1t5.51 (confirmed in its candidate: `BlockShape.rotated_bottom_offset`, and `BotController` now raises the pivot by it).
  - The host's overlap check only counts `RigidBody3D` (`MatchPlacement.gd:752,766`). The disc is an `AnimatableBody3D` (`game/Field.gd:3-6`), so a lying piece spawned inside the disc was never lifted out.
- The sideways part is still open after 1t5.51. That is 1t5.55a.

### 2. The support under the piece is sampled too thinly and in the wrong places (precision; worse for lower tiers)
- `_fire_cell_probes` (`BotThink.gd:396-413`) probes only the first `stability_raycast_count` footprint grid cells, in footprint order:
  - Hard 6 (`bot_tuning.tres:94`), Normal 4 (the default), Easy 2 (`:58`);
  - plate9 has 9 cubes, and up to 36 cells when it does not line up with the grid.
- A bottom cube with no probed cell is treated as supported (`BotStatics._supported_contacts:258`, `matches == 0`). So the far end of a long or wide piece is never checked.
- The probes sit at 1 m grid-cell centres, not at the cubes.
- The supported area is the bounding rectangle of the supported cubes (`BotStatics.gd:9-11` DECISION, `_risk:197-209`), so a split support looks solid.
- The support plane is the single ray under the pivot (`BotThink._probe_one:370-374`), not the highest surface under the footprint. Contact is judged against the wrong height when a footprint spans two heights.

### 3. Only the placed piece is checked for tipping, never the tower (centre of mass)
- The tip check is the new piece's centre of mass against its own direct support (`BotStatics.gd:3-7`).
- Nothing checks the combined centre of mass of everything above each contact level in the tower.
- Tower-top sites are centred on the top block's centre of mass (`BotCandidateGen.add_stack_sites:305-328`; circle centre = block COM, spec 2.2). So an off-centre top pulls the next piece further off-centre and the drift builds up level by level.

### 4. The scoring trades safety for height
- Tower-building weights: height reach 1.0, tip risk 3.0 (`config/BotStrategyTuning.gd:47`; the .tres does not override them).
- The cheap first-pass score rewards the highest top first (`BotEvaluator.gd:37`).
- Tip risk is capped at 1. It already saturates at half a cube of overhang (`overhang_full_cubes` 0.5, `BotStatics._risk:208`).
- So a sure fall costs 3.0, about the same as 3.6 m of extra top height (reach grows tan 40 = 0.84 m per metre of height).
- In Hard this only decides between sites. Root causes 1 and 2 make the risk numbers themselves wrong.

### 5. After a topple the bot treats the pile as its tower (leaning piles)
- The Reach the Sky target is the bot's own tallest settled block (`MatchTerritory.gd:417-424`, `BlockRegistry.tallest_settled_for_slot:432-444`):
  - "settled" only means asleep;
  - tilt and support are ignored.
- Tower-top sites are the tallest own circles first, with no soundness check (`BotCandidateGen.gd:307-317`).
- The bot remembers no collapse. Its memory only keeps the current plan (`BotStrategy._sticky:79-106`).
- So the top of the debris becomes the new target, and it keeps feeding the pile until blocks fall off the disc.

### 6. Climb rate (not a cause of toppling)
- Tower-top sites lay pillars flat (`stack_orientation_variants` 2, sorted by risk then height, `BotCandidateGen.gd:184-194`).
- The cap is 5 s per piece (`block_timer`, `config/match_defaults.tres:13`), so slow climbing directly limits the height a bot reaches in the owner's ~2 minutes.

### 7. Difficulty tiers
- The offset (cause 1) is the same in every tier. Hard suffers it most consistently because it always takes the best-scoring site.
- Normal v2 and Easy v2 add aim noise of 3.0 m and 3.5 m (`bot_tuning.tres:83,59`) *after* the decision (`BotController.gd:1047`, `:1176-1179`), plus 90-100% random sites. They can never hit a 1-3 m tower top, so they make piles whatever the bot believes (see D1).
- Hard's 0.05 m of noise does not matter.

### 8. Latent problem (not hit in the owner's match)
- The bot's probe ray starts at `map_def.cell_wake_height`: 60 m on the medium map (`Field.raycast_disk_column:965-973`, `BotController._column_hit:563`).
- The Reach the Sky target is 100 m (`NetConfig.build_height_target_m`).
- Above 60 m the support probes break. Track this separately.

## C. Design

### Packages and order
Every package is ≤ 10 owned files, about 30 minutes of work, Sonnet. A reviewer is required for every core/ai change.

```
1t5.51 (landing)
   |
   +--> 55a frame --> 55b probes --> 53b wiring --> 54 tower base
   |
53a BotStack (pure, from main now, parallel with 55a/55b) --> 53b
T  sky stats tooling (parallel any time)
```
- These shared files force the chain to run in order:
  - `game/BotController.gd`: .51, 55a, 55b, 53b;
  - `core/ai/BotThink.gd`: 55b, 53b;
  - `core/ai/BotStatics.gd`: 55a, 55b;
  - `core/ai/BotCandidateGen.gd`: 55a, 54;
  - `core/ai/BotCandidate.gd`: 55b.
- Each consumer must check that its base contains its predecessor's commit.
- **55b is the interface-stub package for 53b.** It adds the `BotCandidate` fields `probe_points`, `support_bodies` and `load_margin` (defaults keep today's behaviour). 53b only fills and reads them.
- **53a is the stub package for 53b and 54.** It provides the `BotStack` API.
- Splitting .55 into 55a/55b and .53 into 53a/53b is a proposal; the orchestrator owns sub-bead creation.

### 1t5.55a: model the piece where it actually spawns (precision; the biggest single fix)
- **Change:**
  - `OrientationInfo.cubes`, `contact` and `com` move to the spawn frame `B*(cell - pivot)`, in cube units.
  - New fields: `pivot_shift: Vector2` (`(B*pivot).xz`) and `center_shift: Vector2` (rotated bounding-box centre minus pivot, xz).
  - The footprint comes from `PlacementRules.footprint_cells(cells, B, origin - pivot_shift*cube, cube, grid)`, which is exact with no change to PlacementRules.
  - `candidate.origin` stays the **pivot**. It is the point the host tests (`MatchPlacement.request_place:234-243`), so `_placeable` keeps checking the same point.
  - Tower-top and frontier sites put the *footprint centre* on the intended point (`origin = point - center_shift*cube`). For yaw-only orientations `center_shift` is 0.
  - The send code becomes a static pure seam so tests use exactly the same conversion.
- **Owned files:**
  - `config/blocks/BlockShape.gd` (next to 1t5.51's helper)
  - `core/ai/BotStatics.gd`
  - `core/ai/BotCandidateGen.gd`
  - `game/BotController.gd` (`_send_best_placement` goes through `spawn_pose`)
  - new `tests/unit/test_bot_pose_frame.gd`
  - `tests/unit/test_bot_think_determinism.gd` (re-baseline `BASELINE_MD5` with a DECISION line)
  - `tests/unit/test_bot_statics.gd` and `tests/unit/test_bot_candidate_gen.gd` (only hard-coded expectations of the old frame)
- **Interfaces:**
```gdscript
# config/blocks/BlockShape.gd
func cube_offsets(basis: Basis, cube_size: float) -> PackedVector3Array   # basis*((cell-bottom_center())*cube_size), cells order (BlockFactory.gd:132-134 parity)
func rotated_center_offset(basis: Basis, cube_size: float) -> Vector3     # GhostPreview.rotated_center_offset:1014-1029 parity
# core/ai/BotStatics.gd  (OrientationInfo gains)
var pivot_shift: Vector2   # (B*bottom_center()).xz, cube units
var center_shift: Vector2  # rotated bbox centre - pivot, xz, cube units
static func footprint_cells_of(shape: BlockShape, info: OrientationInfo, origin: Vector2, cube_size: float, grid: CellGrid) -> PackedInt32Array
# game/BotController.gd
static func spawn_pose(shape: BlockShape, orientation_index: int, pivot_xz: Vector2, support_y: float, physics: PhysicsTuning) -> Vector3  # disk-local (pivot.x, support_y + 1t5.51 lift, pivot.y)
```
- **Tuning:** no new tunables (pure geometry). Cube size comes from `PhysicsTuning`.
- **CPU:**
  - One extra `Vector3` subtraction per cube when an `OrientationInfo` is built (cached per shape, `BotStatics.gd:115-145`).
  - No new rays, so the per-decision cost is unchanged (about 10-15 ms for a Hard think, sliced to ≤ 1.6 ms per tick).
- **Tests (headless, no match):**
  1. Parity: for every bag shape and every kept `OrientationInfo`, `info.cubes*cube` equals the `CollisionShape3D` positions of a `BlockFactory.build` body under that basis (1e-4).
  2. `footprint_cells_of` equals the cells covered by those boxes.
  3. Tower-top sites for T4, plate9 and bar3 on a single 2x2 column (synthetic probe that answers "on the column top" inside the column's square): every chosen site's spawn-frame footprint centre is within `stack_jitter_m` of the column centre. This fails on base, where the offset is ≥ 1 m.
  4. A disc placement in every orientation rests on the disc (1t5.51's test stays green).
- **Acceptance:**
  - tests 1-4 pass;
  - `test_bot_*` and `test_headless_bot_*` pass;
  - `lint_layers` and the open-project check are clean;
  - S-gate interim (below): Sky Hard `lost/placed` ≤ 0.5 × S0.

### 1t5.55b: probe the real cubes, every one on Hard, outer cubes first
- **Change:**
  - `_fire_cell_probes` fires at `BotStatics.contact_probe_points` instead of grid-cell centres. These are the real bottom-cube centres, ordered from the outermost inward (descending distance from the contact centroid), so a capped tier still probes the cubes that decide an overhang.
  - The resting plane is the highest probed hit, which is what the host lift actually puts the piece on. `support_height` becomes that height, and contact means within `contact_tolerance_m` of it.
  - Cubes are matched directly, with no grid matching.
  - An unprobed cube still counts as supported. DECISION: lower tiers stay cheap; the outermost cubes are always probed.
  - `_probe_cell` returns the collider's instance id.
  - `_send_best_placement` probes the contact points again at the noisy origin and sends the highest hit (≤ 9 rays, once per decision).
  - Hard `stability_raycast_count` 6 → 9 (`hard_v2` only).
- **Owned files:**
  - `core/ai/BotThink.gd` (`_probe_one`, `_fire_cell_probes`)
  - `core/ai/BotStatics.gd` (`contact_probe_points`, `tip_risk_of` / `_supported_contacts`)
  - `core/ai/BotCandidate.gd` (new fields, stub for 53b)
  - `game/BotController.gd` (`_probe_cell`, the send re-probe)
  - `config/bot_tuning.tres`
  - new `tests/unit/test_bot_stack_precision.gd`
  - `tests/unit/test_bot_think_determinism.gd` (re-baseline again with a DECISION line, or fold into 55a's if both land together)
- **Interfaces:**
```gdscript
# core/ai/BotCandidate.gd (append-only)
var probe_points: PackedVector2Array = PackedVector2Array()  # disk-local XZ of each probed bottom cube
var support_bodies: PackedInt64Array = PackedInt64Array()    # parallel: collider instance id, -1 = disc / miss
var load_margin: float = INF                                 # 53b fills it; INF = no block support / no snapshot
# core/ai/BotStatics.gd
static func contact_probe_points(c: BotCandidate, info: OrientationInfo, cube_size: float, max_count: int) -> PackedVector2Array
# probe contract (BotThink.cell_probe): {hit: bool, height: float, body: int}  ("body" optional, default -1)
```
- **CPU:** per site, 1 centre ray plus up to 9 cube rays (today 1 + 6 cell rays). At 4.9 µs per ray (BOT_AI_REDESIGN 2.2 probe) Hard goes from about 3.8 to about 4.0 ms of rays per decision (average bottom-cube count is about 3-4), plus ≤ 9 rays at send. For 7 bots deciding every 5 s that is about 6 ms of CPU per second, sliced.
- **Tests:**
  1. A scripted physics scenario following `tests/unit/test_drop_displacement.gd`'s harness:
     - set-up: `Field.new()` plus real blocks from `BlockFactory`, awaited until asleep;
     - scene: a settled 3-level square4 column;
     - drive: `BotThink` with probes over `Field.raycast_disk_column`, intent ANCHOR on the column, held bar3, T4 and plate9;
     - spawn at `spawn_pose`, run 180 physics frames;
     - assert the piece rests on the column top (top y within 0.1 m of expected, centre of mass inside the top square);
     - assert no column block moved more than 0.05 m.
  2. A synthetic probe where the overhanging cube is the 7th footprint cell: the overhang is detected (it is missed on base).
  3. A synthetic straddle (half the footprint over a block 1 m up): `support_height` = 1 m.
- **Acceptance:** the tests pass. Then run the S-gate after 55b.

### 1t5.53a: `BotStack`, a pure model of tower statics (centre of mass)
- **Change:** a pure, team-agnostic snapshot of cubes near the bot's own towers and an analysis of it:
  - which body rests on which: a cube is above another when `0 < dy ≤ cube + rest_tolerance_m` and their XZ squares overlap ≥ `min_contact_overlap_m`;
  - the support polygon of each body: the convex hull of its contact points (corners of each cube square inside the other square), or of its bottom cubes when it rests on the disc;
  - the load above each body (mass and centre of mass of everything resting on it, directly or indirectly, plus the body itself). DECISION: the full load is attributed to each supporting body, because the true split is statically indeterminate;
  - soundness: tilt ≤ `max_tilt_deg`, current margin ≥ 0, and every support sound.
- **Owned files:**
  - new `core/ai/BotStack.gd`
  - new `config/BotStackTuning.gd`
  - new `config/bot_stack_tuning.tres`
  - new `tests/unit/test_bot_stack.gd`
- **Interfaces:**
```gdscript
class_name BotStack extends RefCounted      # core/ai/BotStack.gd, pure, filled by game/BotStackProbe.gd (53b)
var cube_size: float
var body_ids: PackedInt64Array; var body_team: PackedInt32Array; var body_mass: PackedFloat32Array
var body_com: PackedVector3Array; var body_basis: Array[Basis]; var body_tilt_deg: PackedFloat32Array
var body_settled: PackedByteArray
var cube_pos: PackedVector3Array; var cube_body: PackedInt32Array      # disk-local cube centres
func add_body(id: int, team: int, basis: Basis, cubes: PackedVector3Array, mass: float, settled: bool) -> void
func analyse_step(max_bodies: int, t: BotStackTuning) -> bool   # sliceable, true when done
func index_of(body_id: int) -> int                               # -1 unknown
func load_margin(support_ids: PackedInt64Array, piece_com: Vector3, piece_mass: float) -> float  # min signed metres inside every support hull down to the disc; INF without block support
func is_sound(body: int) -> bool
func sound_tops(team: int) -> PackedInt32Array    # sound bodies with nothing resting on them, tallest first
func top_height(body: int) -> float
func debris_near(point: Vector2, radius: float) -> bool   # any unsound cube within radius (column hash)
```
- **BotStackTuning** (all exported, no magic numbers):
  - `rest_tolerance_m` 0.08
  - `min_contact_overlap_m` 0.1
  - `max_tilt_deg` 8.0
  - `safe_margin_m` 0.2
  - `snapshot_radius_m` 4.0
  - `snapshot_max_bodies` 96
  - `analyse_bodies_per_step` 8
  - `settled_speed_mps` 0.15 (spec 2.2's settle filter value; read `TerritoryTuning` if exposed there)
- **CPU:**
  - Analysis is linear thanks to a column hash: ≤ 96 bodies, about 4 cubes each, about 8 point tests per contact pair, so about 20-40k GDScript operations, about 0.5-1 ms per think, sliced over `analyse_bodies_per_step`.
  - `load_margin`: walks the supports down to the disc (about 30 bodies × about 6 hull edges), about 50-90 µs per supported site. The downward set is cached per support set.
- **Tests (pure, synthetic snapshots):**
  1. A centred 2-cube tower has a margin of about 0.5 m.
  2. A piece centre beyond the top edge gives a negative margin.
  3. An L-overhang where the top contact is fine but a lower contact fails is negative, which shows the walk goes down the tower.
  4. Two legs: a centre of mass between them is inside the hull.
  5. A 30-degree tilted body is unsound, and so is everything resting on it.
  6. A cube at disc level rests on the disc.
  7. Analysis sliced into steps gives the same result as one pass.
  8. With 400 cubes the analysis finishes within `ceil(bodies/analyse_bodies_per_step)` steps.

### 1t5.53b: wire `BotStack` into the think (centre of mass decides the pick)
- **Change:**
  - `BotStackProbe.build(registry, field, centres, tuning)` collects the bodies to analyse:
    - all blocks of any team whose centre of mass lies within `snapshot_radius_m` of the own tower-top sources (the tallest `stack_site_count` own circles plus the Reach the Sky target);
    - nearest first, capped at `snapshot_max_bodies`;
    - cubes from the body's `CollisionShape3D` children (general: covers fused and gift bodies);
    - a static per-instance cache keyed on `global_transform`, so sleeping blocks cost one comparison.
  - `BotController._begin_thinking` sets `view.stack`.
  - `BotThink` gets a sliced `Phase.STACK` (one unit per body) before PROBE. PROBE fills `c.load_margin` for every site that has block support.
  - The evaluator adds `stack_risk(c)` to the TIP term in both `proxy_terms:58` and `measure:77`: `stack_risk_weight * clamp(1 - margin/safe_margin_m, 0, 1)`, plus `topple_penalty` when margin < 0.
  - `view.stack == null` or margin INF gives exactly today's behaviour, so the determinism baseline is unchanged by 53b.
- **Owned files:**
  - new `game/BotStackProbe.gd`
  - `game/BotController.gd`
  - `core/ai/BotWorldView.gd` (`var stack: BotStack = null`)
  - `core/ai/BotThink.gd`
  - `core/ai/BotEvaluator.gd`
  - `config/BotEvalTuning.gd` and `config/bot_eval_tuning.tres` (`stack_risk_weight` 1.0, `topple_penalty` 10.0, following the `rim_outside_penalty` precedent)
  - new `tests/unit/test_bot_stack_scenarios.gd`
- **CPU per Hard decision:**
  - gather ≤ 0.3 ms (cached);
  - STACK ≤ 1 ms, sliced;
  - margins about 50 tower-top sites × ≤ 90 µs ≈ ≤ 4.5 ms, sliced in PROBE.
  - Total: about +5 ms over a 10-15 ms think. With 7 bots that is about 7 ms of CPU per second and ≤ 1.6 ms per bot per tick (`think_budget_us`), so the frame cap is untouched.
- **Tests (physics scenarios, scripted, no match):**
  1. A 6-level column with an offset T4 at level 3 (scripted spawns, settled), held domino and T4. The pick's margin is ≥ `safe_margin_m`. After 3 s simulated, every column block moved less than 0.1 m.
  2. The same scene with `view.stack = null` versus with it: the site with a negative margin ranks below a safe one.
  3. Determinism holds with no snapshot.
  4. `lint_layers`: `BotStackProbe` stays in game/, and core/ai/BotStack has no scene references.

### 1t5.54: leaning piles, building on sound stacks and starting a new base after a collapse

> Superseded in part (owner 2026-10-14, Bontago-1t5.68): `debris_clearance_m` is gone. A site may rest on or beside debris when every supporting face is parallel to the disc within `BotStackTuning.support_face_tolerance_deg` (disc-local frame); tilted faces still reject and the load-margin check runs through debris carriers.
- **Change:**
  - **Tower-top site filter (all modes):** tower-top sites only on sound tops, matched through `view.stack.index_of` at the circle centre's column. Unsound tops are skipped.
  - **Reach the Sky plan (`_mode_plan` branch):** the target is the tallest of `view.stack.sound_tops(team)`. The seat memory keeps `base` (xz), `base_peak` and `base_age`.
  - **Collapse rule:** the bot starts a new base when either holds:
    - no sound top lies within `base_match_radius_m` of `base`;
    - the sound top is below `base_peak - collapse_drop_m`.
  - **New base point:** a deterministic sunflower of `base_samples` points over the own home circle, then the own circles. Keep a point when:
    - `validate_point` says VALID;
    - `!stack.debris_near(p, debris_clearance_m)`;
    - rim risk is 0.
  - Among the kept points, the one closest to home wins; ties go to the lower hazard.
  - The intent stays ANCHOR, with `new_base = true` and the target at the base.
  - The generator then adds FOUNDATION sites (new `SITE_FOUNDATION = 5`) around the base with the widest, flattest orientation (contact area first). Base keys reset when `own_count == 0`.
  - DECISION: `_strategy_memory` is static and is never cleared between matches today (`BotThink.gd:42`).
- **Owned files:**
  - `core/ai/BotStrategy.gd`
  - `core/ai/BotIntent.gd` (`var new_base: bool = false`)
  - `core/ai/BotCandidateGen.gd`
  - `config/BotStrategyTuning.gd` and `config/bot_strategy_tuning.tres`:
    - `collapse_drop_m` 3.0
    - `base_match_radius_m` 1.5
    - `debris_clearance_m` 2.0
    - `base_samples` 24
  - `config/BotGenTuning.gd`:
    - `foundation_site_count` 12
    - `foundation_jitter_m` 0.5
  - new `tests/unit/test_bot_tower_base.gd`
- **CPU:**
  - The sound-top filter is one lookup per tower-top source.
  - A new-base search runs only on a collapse: 24 × (`validate_point` 5.6 µs + a column-hash debris lookup) ≈ 0.3 ms.
- **Tests (pure, synthetic BotStack plus raster):**
  1. A pile (6 bodies, tilted 25-40 degrees) next to a sound 2-block stack: the target is the sound stack.
  2. A pile only: `new_base` is set. Every FOUNDATION site is ≥ `debris_clearance_m` from the debris cubes, VALID, and uses the flattest orientation.
  3. The base persists for 3 pieces. After a collapse (`base_peak` 9 m, sound top 4 m) it moves.
  4. `own_count == 0` resets the base.
  5. Classic intents are unchanged with the stack filter: `test_bot_strategy` passes.

### T (Haiku, parallel): Reach the Sky height stats for the measurement
- **Change:**
  - `tools/bot_h2h.py --stats` parses the `stats=` field of HEADLESS_MATCH (`game/MainHeadlessBotsFlow.gd:182-188`; today it only parses the winner and duration, `bot_h2h.py:77-79`).
  - It prints per side: median/p25/max of peak and peak180, and lost/placed.
  - New headless flag `--gifts=0` (the owner's match had no gifts; `config/match_defaults.tres:16` enables them).
- **Owned files:**
  - `tools/bot_h2h.py`
  - `tools/test_bot_h2h.py`
  - `game/MainHeadlessBotsFlow.gd`
  - `tests/unit/test_headless_bot_overrides.gd`

### Measurement (orchestrator, idle PC only, sequential)
- **S0 baseline:** on main once 1t5.51 has landed.
- **S-gate after each of 55b, 53b and 54.** Settings: 8 seats = 1 passive seat (auto-drop pile, a free reference) + 7 Hard v2, Reach the Sky, no gifts, no weather, `--seconds=180`, 10 seeds.
  - Draft command (confirm flags with T's `--dry-run`):
```
python tools/bot_h2h.py --bots 7 --players 8 --mode sky --no-swap --pairs 10 --seconds 180 --stats --cand-slots-a 0,1,2,3,4,5,6 --godot-args "--match-seed={seed} --bot-difficulty=hard --bot-brain=v2 --gifts=0"
# (1t5.56: without --cand-slots-a 0..6 side A is only 4 of the 7 bots.)
```
- **Targets (provisional, to be re-pinned against S0):**
  - bot-seat median peak ≥ max(2 × S0, 25 m);
  - p25 peak ≥ 15 m;
  - lost/placed ≤ 0.15 (E7's bar);
  - bot median ≥ the passive pile in ≥ 8 of 10 seeds.
  - Reference: owner 18.8 m best and 8-10 m typical at about 120 s; idle auto-drop piles reached 20-27 m (BOT_AI_REDESIGN 2.1).
- **No-regression screen:**
  - E3 (Classic vs passive): 20/20 wins, median ≤ 120 s;
  - E5a: 10-pair screen, Hard vs Normal ≥ 0.75.

### Risks
- **Determinism baseline churn:** 55a and 55b re-baseline it once each, with a DECISION line.
- **Concurrent 1t5.51 edits:** 55a must start on 1t5.51's commit (`BlockShape.gd`, `BotController.gd`, `GhostPreview.gd`).
- **More conservative play could lower Classic speed:** the stack term only applies to block-supported sites; the E3 screen catches it.
- **The full-load-per-support approximation is wrong under arches:** this errs towards caution.
- **Contacts between tilted bodies are only approximate:** tilt above `max_tilt_deg` simply marks the body unsound.

## D. Proposed owner decisions (I have not decided these)
- **D1. Lower-tier aim noise versus towers.** DECIDED 2026-10-14 (Bontago-1t5.57): none of the options below; every tier uses Hard's mechanics and Easy/Normal get a slightly larger aim error (start 0.5 / 0.25 m, final values from the 1t5.60 measurement). Implemented in Bontago-1t5.61. D3 answered (a).
  - Problem: Normal (3.0 m) and Easy (3.5 m) noise is applied after the choice, so these tiers cannot stack at all in Reach the Sky.
  - Options:
    - (a) keep as tuned in 1t5.40;
    - (b) apply the noise to the site *before* evaluation, so they misjudge but know where the piece lands (weaker towers, not piles);
    - (c) scale the noise down on tower-top sites only.
  - Any change alters Normal and Easy feel in every mode and needs an E5 re-measure.
- **D2. Point checked for legality on pitched or rolled pieces (affects humans, found in passing).**
  - Problem: spec 2.5 says "one ray straight down from the ghost's middle". The host tests the unrotated bottom-centre pivot (`MatchPlacement.gd:234-243`, the ghost's `global_position`). For a lying piece that pivot is on an end face, up to about 1-2 m from the middle.
  - Options: (a) keep; (b) test at the rotated footprint centre, as the spec text says.
  - This is a separate bead. The bot design above follows whatever the host tests.
- **D3 (optional).** With gifts on, may bots spend a Bomb or Black hole on their *own* debris to clear a base, or only abandon it (the design above)?
