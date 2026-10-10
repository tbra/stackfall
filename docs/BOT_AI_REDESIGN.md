# Bot AI redesign (Bontago-1t5.17)

Base main 75075586. Part 1 (audit) below; Part 2 (plan) is written separately from this audit.
Evidence: 128 recorded 8-bot Hard matches (47k decisions, M:/Bontago-tools/scratch/t1-run/data; classic 64 matches, elimination 60), code read, and three off-screen 4-seat watch runs (analysis scripts a1/a3/a4.py and sheets in M:/Bontago-tools/scratch/bot-plan/: sheet_4bot_hard_classic.png, sheet_1bot_vs_passive.png).

## 1. Audit

### How the bot works today (code anchors)
- Cadence: one placement per `MatchConfig.block_timer` = 5 s per seat (`BotController._on_feed_block_issued`, `_tick_idle`). Hard reaction is 0.2 s, so the 5 s interval, not thinking time, is the limit; only choice quality matters.
- Candidates (`BotController._tick_generating`, `_generate_one_candidate`, `_sample_territory_point`): 110 (Hard) spots drawn UNIFORMLY over the whole disk, 12 attempts each, accepted if `PlacementRules.validate_point` is valid; on failure the candidate falls back to the home position. Orientation = `flattest_orientations()` of the held shape only (flattest base): no reasoning about standing a pillar up or laying a bar toward the goal.
- Score (`BotPlacementScorer.score`): `1.0*support_height - 1.5*goal_metric + 2.0*stability - 1.0*risk`; goal_metric = distance(origin, nearest goal) minus the estimated future radius `InfluenceCircle.radius_for_height(support_height+shape_height)` (radius = 1.5 m + 1 m per metre of height, cap 0.6 R; `config/territory_tuning.tres`). `stability` = footprint cells in contact (corner raycasts, 6 for Hard) + 1.0 if on own stack. No physics prediction, no lookahead, no model of opponents' plans. Elimination adds `_elimination_term`; CTF/Sky/Domination have mode terms; multi-goal has `_multi_goal_term`.
- Specials (`BotSpecialPlanner.plan`): per-type one-liners keyed on the densest enemy circle / farthest own point; `block_samples` is always `[]` from `BotController._tick_acting`; enemy positions are home flags + circle centres only.
- Difficulty = candidate_count 40/70/110, raycasts 2/4/6, aim noise, reaction delay, special flags. All tiers share the same scorer, so the ceiling is the scorer.

### Ranked failure modes
1. **Bots do not build up; they smear a flat one-wide snake along the ground.** Chosen support height: median 0.0 m; only 9.6% of classic choices have h>=1 (mean 0.23 m); own tower max averages 3.9 m at match end (max 9.9). Yet radius grows 1 m per metre of height, and h>=1 placements gain about 57% more territory over 30 s (0.0086 vs 0.0055 share; 896 vs 9051 samples). In the 1-bot-vs-3-idle watch run the idle auto-drop seats ended at 20.7 m and 27.5 m tower height (big circles, 8-14% share) vs the Hard bot's 6.0 m and 9%; it won only by reaching the goal at 224 s. Both sheets show the same: every bot is a thin 1-block corridor toward the centre. The goal term decides the pick (per-candidate contribution sd 9.1 vs height 0.27, stability 2.2; goal-only argmax equals the pick 64%, height-only 5%). Code: `score()` weights; candidates are seldom ON a tower (see 2). Cheap fix: weight the FUTURE top (support+shape height = radius gain) explicitly and generate candidates on own tall stacks.
2. **Candidate generation wastes about 60% of the budget.** Classic: the top duplicate origin is 61% of the 110 candidates (the home fallback repeated); distinct origins mean 44 (22 at 1% share, 54 at 5%). Uniform-in-disk rejection sampling over R=45 m against a territory that is 1-6% of the disk (per-attempt success about equals share, 12 attempts). Only 4.5% of candidates have h>=0.9 though 87% of decisions have at least one. Elimination has 37% duplicates (frontier sampling helps). Code: `_sample_territory_point`. Cheap fix: sample from the raster's own cells / own circle edges / own block tops instead of the whole disk.
3. **Myopic goal chase, no second dimension of strategy.** The chosen goal metric equals the best available in the median decision (goal_gap 0.0, mean 0.47 m of a 26 m candidate spread): the pick is "closest to the goal". All bots take the same line to a single central goal, producing parallel snakes that meet and stall in the middle (4-bot sheet, 150-240 s: beacon fight, `frontier_gap` frozen at 24.76 from 180 to 240 s, no winner). No flanking, widening, blocking or defending of the line. Code: `_goal_progress_metric`, `_multi_goal_term`. Cheap fix: width/second-lane bonus; real fix is a strategy layer.
4. **Frontier stalls and zero-gain placements.** 27% of classic decisions sit in a >=30 s window without own-share growth (15% >=60 s); 36% gain <=0.001 share over 30 s (43% in elimination). Mean `d_share30` is 0.005 per placement; mean final share 5.9% (8 seats) against 8-20% for passive auto-drop seats in watch runs. Cause: points 1-3 plus risk/stability terms that rarely differentiate (risk sd 0.03). Cheap fix: score measured territory delta (short territory re-solve for top-k) instead of the distance proxy.
5. **Blind to physics and stability.** `corner_support_hits` counts flush cells only; no tip-over, load or centre-of-mass check; `weight_stability` 2.0 rewards 6/6 ground contact, which steers away from tall plays. 0.147 own blocks are lost per decision (about 1 in 7). Code: `_stability_term`, `_fire_stability_raycasts`. Cheap fix: height-aware stability (support area vs height) so stacks are not penalised.
6. **Elimination: no kill-chain in 60 matches.** 0 wins at the 296 s cap; 255 eliminations (about 4.2 per 8-seat match, mean 152 s) show attackers erode each other but nobody finishes. The mode term (sd 27) dominates everything else (height agrees with the pick only 11%), and it is a pure distance-to-target-home pull shared by all 8 bots, so all pile on one weakest home. Code: `_elimination_term`, `target_home_index`. Cheap fix: spread targets per seat.
7. **Specials are decorative.** Planners see only home flags and circle centres (`_enemy_circle_centers`), never block clusters (`block_samples=[]`); one static target per type, no combos or timing; black hole fallback treats circle centres as ground blocks. Only 2 special decisions in the 226 s sample match. Cheap fix: pass real enemy block samples from `Match` into `plan()`.
8. **Weight tuning is exhausted.** The T1 refit (fit.txt) moved weights +35..58% (height 1.50, goal 2.37, stab 2.69, risk 0.76) with top-1 agreement 0.95 yet only 58% h2h (CI 0.40-0.74): the four features cannot express tall-tower play because the candidate set rarely contains it (modes 1-2).

### Secondary observations
- Classic Hard 8-bot win time: median about 190 s, range 76-582 s; the 4-bot watch run had no winner in 240 s (beacon contested from about 170 s).
- Rejections are not a problem: about 1% of requests (outside_territory 99, goal_zone 6 of 11.4k classic).
- chosen == scored_best 100%: Hard's 0.05 m aim noise never changes the pick; Easy/Normal differ only by sample count, noise and delay.
- Method caveat: `Engine.time_scale` > 1 makes physics ticks coarse and desyncs HEADLESS_BOTS `t`; only scale-1 runs are quoted. One discarded x3 run and one failed launch (missing scene) were also made (4 Godot runs total, sequential).

### Screenshot sheets (both opened)
- sheet_4bot_hard_classic.png (14 frames, 15-240 s): thin parallel snakes toward the centre, no widening, central stalemate with a white special flash from about 170 s.
- sheet_1bot_vs_passive.png (9 frames, 20-223 s): bot (yellow) builds a narrow snake and wins at 224 s via the goal; passive seats' tall piles give bigger circles; result screen shows bot height 6.0 m vs 20.7/27.5 m.

## 2. Plan

Planner pass (stackfall-planner, 2026-10-10, base 75075586). One cost probe was run (headless, debug build, owner machine in use; `M:/Bontago-tools/scratch/bot-plan/probe_cost.gd` + `.log`): Jolt `intersect_ray` 4.9 us with 300 boxes; `PlacementRules.validate_point` 5.6 us; one 64-point raster sample of a future circle 297 us; a full `TerritorySolver.solve` + legacy `TerritoryRaster.update` (208 circles, M map) 11.9 ms.

### 2.1 Why the bots lose: how territory is actually won (rules as coded)
Note (orchestrator, 2026-10-10): the owner lowered the cone half-angle from 45 to 40 degrees (Bontago-1pi.155), so reach per metre of height below is tan(40) = 0.84 m, not 1 m; the mechanisms are unchanged.
- **Reach.** `InfluenceCircle.radius_for_height` (core/territory/InfluenceCircle.gd): r = 1.5 m + top height (45-degree cone), capped at 0.6 R (27 m on M). A ground piece at the territory tip moves the frontier by its own r: 2.5 m lying flat, 3.5-6.5 m standing (pillar, bar4, bar5); a stack at the tip adds 1 m per metre of height. Area grows with r^2: one 20 m pile is about 20% of the M disc, a 13-block snake about 2.5%.
- **Exclusion and kill (default hole mode).** `config/match_defaults.tres` hole_mode = 0 = TEMPORARY, so `TerritoryRaster` runs the legacy fill: a cell covered by two teams' home-anchored groups is CONTESTED and becomes a hole after `hole_delay` 0.75 s (closes 2 s after). `PlacementRules.validate_point` (core/rules/PlacementRules.gd:268) refuses contested/hole cells, so nobody can build inside an enemy circle, and `HoleDissolver` (game/HoleDissolver.gd) dissolves every disc-level block touching an applied hole, with its stack. Two stacks d apart: the first whose radius exceeds d + 0.5 m destroys the other's base. **Height is reach, area and the weapon.**
- **Fragility.** `TerritorySolver.solve` unions only same-team overlapping circles and drops components without a home circle. A one-wide snake has an articulation point at every block: one enemy circle touching it cuts everything downstream (area, contest and goal claim vanish).
- **Finish.** The goal sits in a 4 m no-build zone (`goal_zone_radius`), so capture needs a circle with r > distance to the goal (top >= about 3 m at the zone edge) and no enemy circle on the goal cell for `capture_hold` 20 s (`WinChecker.update`, core/rules/WinChecker.gd:60). The tallest stack near the goal owns the hold. Elimination is the same kill rule applied to a home flag (`MatchTerritory._check_home_flags`, autoload/match/MatchTerritory.gd:843).
- **The current bot uses none of this.** It never stacks (failure 1), its chains are one wide (3), it cannot exclude or cut, so central contests stall (4); it wins only by arriving first and unopposed. Even the race is slow: the goal gap of classic_1 match001 slot 0 shrinks 30.7 -> 2.3 m over 21 placements (1.35 m each) where about 3 m per uncontested placement is available at the tip, because uniform sampling rarely puts a site on the tip (failure 2) and each site gets one cycled orientation. Correction to the audit's code summary: `_tick_generating` (game/BotController.gd:242-250) cycles all 24 orientations sorted by flatness (`orientations[_candidates.size() % orientations.size()]`), so upright pieces do occur, but on random sites, and `_stability_term` then penalises their smaller contact.
- **Idle seats.** The auto-drop lands at `MatchPlacement.default_ghost_origin` every window, so passive seats pile 20-27 m: evidence that centred stacking is physically sustainable for a bot that does it on purpose.

### 2.2 Options and CPU (Hard, 8 bots, host only; 16.7 ms frame at 60 Hz; one territory step already costs 4-12 ms at 100-300 blocks, docs/TERRITORY_PERF_PLAN.md)
Current cost, estimated from the probe: 110 candidates x (about 9 rejection-sampling `validate_point` calls + 7 rays + score) is about 11 ms per decision, sliced at 8 candidates per frame (about 0.8 ms per frame for about 14 frames); 8 bots average about 18 ms of CPU per second.

| Option | Expected strength gain, why | Per-decision CPU | Risk | Files |
|---|---|---|---|---|
| **A** Strategy layer + targeted candidates | Large. Places at the tip in the best stable orientation (race about 2x faster), raises anchor and finish towers (reach, area, exclusion), cuts thin enemy chains and defends its own. Directly addresses failures 1-4 and 6. | 10-15 ms: 110 targeted sites (1-2 validates, 1 + footprint rays) about 6 ms; world view and chain graph 1-3 ms; 64-sample territory gain for the top 12 about 3.6 ms. Same slicing at <= 1 ms per bot frame, decision ready <= 0.3 s. | Medium: intent thresholds need tuning; towers can topple. | 6 new core/ai files, BotController, config |
| **B** Physics-aware evaluation + lookahead | Analytic statics (centre of mass over supported cells, stack slenderness): small, cheap, needed by A. **A Jolt rollout is not feasible from script**: `PhysicsServer3D.step` is not bound (only `space_set_active`, servers/physics_3d/physics_server_3d.cpp:720; Jolt steps every active space together, modules/jolt_physics/jolt_physics_server_3d.cpp:1623), so a shadow space advances one tick per real frame; it needs a C++ extension (new addon, owner approval). Full territory re-solve per candidate: 11.9 ms each, rejected. 2-ply lookahead with the known `next_shape`: modest gain, deferred. | statics < 0.5 ms; re-solve 95 ms for 8 candidates (no); 2-ply +11 ms | Low (statics) / high (rollout) | +1-2 core files |
| **C** T3 learned scorer | Unknown and bounded by the candidate set: the 47k recorded decisions come from a policy that never stacks (off-policy), d_share30 is a weak reward and weight tuning already plateaued (T1 58%). Worth doing later on top of A's terms. | MLP inference 0.1-0.2 ms per candidate (+11-22 ms) | High: training infrastructure and long soaks on a 4-core PC | tools + core |
| **D** A + analytic B (recommended) | A's gain plus fewer lost blocks; every term stays recordable so the existing fit pipeline (tools/bot_fit_weights.py) can later tune intent weights (C-lite). | 10-15 ms, <= 1 ms per bot frame | Medium | as A + 1 |

### 2.3 Recommended path: D (strategy layer + targeted sites + measured territory gain + analytic statics), behind a brain switch
The new brain (`V2`) runs beside the shipped one (`LEGACY`) per slot, so `tools/bot_h2h.py` can pit them on paired seeds; the default flips only after the shipping bar and owner approval. Bots keep acting only through `Match.request_place` / `request_throw` (host-validated, same rules as players) and read the host raster and circle list, as today.

Pipeline per piece, all pure in core/ai except the physics probe callable supplied by BotController:
1. **View** (`BotWorldView`): one snapshot from `Match.circle_render_arrays()` (xs, zs, radii, teams; home circles are included there and must be stripped by matching home positions, autoload/match/MatchTerritory.gd:760-800), raster, grid, homes, goals, `BotModeGoal`, held and next shape, live specials, landed gifts. Top height of a circle = r - influence_base.
2. **Chains** (`BotChains`): per team, the overlap graph of its circles rooted at the home circle: downstream count per circle (how much a cut there removes), articulation flags, gap of the component to any point (minimum of distance - r).
3. **Intent** (`BotStrategy`, first match wins): HOLD (goal cell already own: raise the covering stack, strike any enemy circle within reach + allowance of the goal); DEFEND (an own circle with downstream >= N, the goal-covering stack or the own home is within an enemy circle's reach + allowance: outgrow the threatener or cover its base); STRIKE (Hard: an enemy circle with downstream >= N or touching the goal whose base one placement can cover); FINISH (gap <= finish_gap_m: build the tower at the zone edge); ANCHOR (tip stack lower than anchor_min_height_m and an enemy circle within contest_lookahead_m of the tip, or anchor_rhythm race pieces since the last anchor); RACE (default: tip toward the unheld goal with the smallest gap). Mode adapters: Elimination replaces goals by a target home chosen per seat (smallest chord distance, ties to the clockwise neighbour so eight bots do not pile on one home) and SIEGE (stack outside the target's 6 m home circle until r covers the flag); the own home becomes the first DEFEND key. Domination: AREA (maximise area gain) plus STRIKE on the leader. Reach the Sky: ANCHOR on the own tallest stack (today's `_sky_term` idea). CTF: RACE to unheld beacons, HOLD held ones. Multi-goal Classic: target = unheld goal nearest the home component (today's `next_goal_index`).
4. **Sites** (`BotCandidateGen`): TIP (for each own circle the point at r - inset toward the target; best 12 plus lateral offsets), STACK (own stack tops), STRIKE/DEFEND (own edge facing the threat), FILL (a few uniform samples, mostly for Easy). Orientations are deduplicated by (footprint, height) signature (at most about 6 per shape); the one kept per site maximises reach subject to `BotStatics`. Every site is `validate_point`-valid before any ray is fired, so the home-position fallback duplicates disappear.
5. **Probe** (BotController callable): support ray plus one ray per footprint cell (per-cell support heights for statics).
6. **Evaluate** (`BotEvaluator`): proxy terms for every site, then measured terms for the top-k by proxy. Terms: reach toward the intent target (gap reduction); area gain (64 sunflower samples of the future circle against the raster: unowned and uncontested cells; OFF mode compares kernels instead); kill (enemy circle bases newly inside r + 0.5 m, weighted by their downstream count, plus goal or home cover); exposure (own new base within enemy reach + allowance); tip risk (statics); waste (future circle already own). Weighted by the intent's weight vector; Hard takes the argmax, lower tiers sample from the top few.
7. **Act**: re-validate the chosen origin (state can move during the think), add aim noise, send the request; specials go through `BotSpecialPlanner.plan_v2(view, chains)`; landed-gift claiming stays as today (`_gift_claim_target`).

Interface stubs (P1 creates `BotWorldView`, `BotIntent`, `BotThink` and the new `BotCandidate` fields; P2-P5 must confirm their base contains P1's commit). The other classes are created by their owning package with the signatures listed:
```gdscript
class_name BotWorldView extends RefCounted   # core/ai/BotWorldView.gd, pure snapshot
var slot_id: int; var team_id: int; var mode: int; var field_radius: float
var raster: TerritoryRaster; var grid: CellGrid; var territory_tuning: TerritoryTuning
var own_home: Vector2; var has_home: bool; var goals: PackedVector2Array; var goal_zone_radius: float
var enemy_homes: PackedVector2Array; var enemy_home_teams: PackedInt32Array
var cx: PackedFloat32Array; var cz: PackedFloat32Array; var cr: PackedFloat32Array; var cteam: PackedInt32Array
var held: BlockShape; var next_shape: BlockShape; var mode_goal: BotModeGoal
var specials: PackedVector2Array; var gifts: PackedVector2Array
static func build(slot_id: int, team_id: int, circles: Dictionary, slots: Array[PlayerSlot], raster: TerritoryRaster, goals: PackedVector2Array, goal_zone_radius: float, held: BlockShape, next_shape: BlockShape, mode_goal: BotModeGoal, specials: PackedVector2Array, gifts: PackedVector2Array) -> BotWorldView
func top_height(i: int) -> float
func indices_of_team(team: int) -> PackedInt32Array

class_name BotIntent extends RefCounted       # core/ai/BotIntent.gd, data only
enum Kind { RACE, ANCHOR, FINISH, HOLD, DEFEND, STRIKE, SIEGE, AREA }
enum Term { REACH, AREA, KILL, EXPOSURE, TIP, WASTE }
var kind: Kind = Kind.RACE; var target: Vector2 = Vector2.ZERO; var focus_circle: int = -1
var weights: PackedFloat32Array               # indexed by Term

class_name BotThink extends RefCounted        # core/ai/BotThink.gd, one resumable think-cycle
class Decision extends RefCounted:
	var kind: int            # PLACE or WAIT
	var origin: Vector2; var orientation_index: int; var intent: int; var terms: PackedFloat32Array
func _init(view: BotWorldView, profile: BotDifficultyProfile, rng: RandomNumberGenerator) -> void
func step(budget_usec: int, probe: Callable) -> bool   # probe(xz: Vector2) -> {hit, height, own}; true when done
func decision() -> Decision
# P2: BotCandidateGen.sites(view: BotWorldView, intent: BotIntent, profile: BotDifficultyProfile, rng: RandomNumberGenerator) -> Array[BotCandidate]
#     BotStatics.tip_risk(c: BotCandidate, shape: BlockShape) -> float
# P3: BotChains.build(view: BotWorldView) -> BotChains (downstream(i), is_articulation(i), gap_to(team, p))
#     BotEvaluator.proxy(c: BotCandidate, view: BotWorldView, intent: BotIntent) -> float
#     BotEvaluator.measure(c: BotCandidate, view: BotWorldView, chains: BotChains, intent: BotIntent) -> PackedFloat32Array
# P4: BotStrategy.choose(view: BotWorldView, chains: BotChains, profile: BotDifficultyProfile) -> BotIntent
```
`BotCandidate` gains `site_kind`, `top_height`, `cell_support: PackedFloat32Array` and `tip_risk`. P1's `BotThink` runs a legacy-equivalent pipeline (pure port of today's sampler + `BotPlacementScorer.pick_best`) so V2 plays from day one; P4 swaps in strategy, sites and evaluator. BotController adds `enum Brain { LEGACY, V2 }`, `set_brain()`, a V2 `THINKING` state calling `BotThink.step(profile.think_budget_us, _probe)` and a static per-physics-frame cap across all bots (`think_frame_cap_us`); the LEGACY path stays byte-identical.

### 2.4 Packages (dependency order; at most 10 owned files each; Sonnet unless noted)
| # | Outcome | Owned files | Depends | Acceptance |
|---|---|---|---|---|
| P1 | V2 skeleton and seams (interface-stub package) | new core/ai/BotWorldView.gd, BotIntent.gd, BotThink.gd (legacy-equivalent pipeline); edit core/ai/BotCandidate.gd, config/BotDifficultyProfile.gd (+`think_budget_us`, `eval_top_k`, `pick_temperature`, `intent_mask`), game/BotController.gd, game/MainHeadlessBotsFlow.gd (`--bot-brain=legacy` or `v2`, `--bot-brain-slots=`, `brains=` in the record header); new tests/unit/test_bot_think.gd | - | LEGACY unchanged (test_bot_controller, test_headless_bot_overrides, test_bot_decision_recorder pass); test_bot_think: fake probe, budget respected (step returns false when spent), seeded determinism, home circles stripped from the view; one `--bots=1 --players=4 --bot-brain=v2` headless match (timeout 300, --seconds=240) runs without errors; lint_layers clean |
| P1b | Eval tooling (Haiku) | tools/bot_h2h.py (`--candidate` optional when the template has no weight placeholder, `--players`, `--no-swap`, `--mode`, summary adds median/max candidate win time), new tools/test_bot_h2h.py | - | python tests pass; `--dry-run` prints the E1-E5 commands below |
| P1c | Legacy baseline (orchestrator run, no code) | none | P1, P1b | E3 and E4-passive numbers for legacy Hard recorded on the bead (10 seeds each, sequential) |
| P2 | Targeted sites and statics | new core/ai/BotCandidateGen.gd, new core/ai/BotStatics.gd, new config/BotGenTuning.gd + config/bot_gen_tuning.tres, new tests/unit/test_bot_candidate_gen.gd, test_bot_statics.gd | P1 | synthetic snake raster: TIP sites within 0.5 m of the edge nearest the target; >= 95% of 110 sites distinct and valid; pillar offered upright at the tip when statics allow, flattest on stack tops; an overhanging orientation gets tip_risk above threshold |
| P3 | Chains and evaluator | new core/ai/BotChains.gd, new core/ai/BotEvaluator.gd, new config/BotEvalTuning.gd + config/bot_eval_tuning.tres, new tests/unit/test_bot_chains.gd, test_bot_evaluator.gd | P1 (parallel with P2) | downstream counts and articulation on a fork; kill = downstream count when a site covers an enemy snake joint; a taller tip stack beats a flat piece behind the tip on reach; zero area gain plus waste deep inside own land; exposure > 0 inside enemy reach + allowance; OFF mode has no kill term |
| P4 | Strategy, assembly, difficulty tiers | new core/ai/BotStrategy.gd, core/ai/BotThink.gd, new config/BotStrategyTuning.gd + config/bot_strategy_tuning.tres, config/BotDifficultyProfile.gd, config/bot_tuning.tres, new tests/unit/test_bot_strategy.gd, tests/unit/test_bot_think.gd | P2, P3 | rule-table tests for every intent and mode adapter (threat -> DEFEND, goal held -> HOLD, gap <= finish -> FINISH, contested tip -> ANCHOR, else RACE; eight equidistant Elimination seats pick distinct targets); one v2 Hard vs 3 passive smoke win (timeout 300); think within budget. An Opus override is justified only if a Sonnet pass fails the screen (the intent policy is the crux) |
| P5 | Specials v2 | core/ai/BotSpecialPlanner.gd (`plan_v2(special_id, view, chains, profile, tuning)`), game/BotController.gd (V2 branch of `_tick_acting` calls `plan_v2`), tests/unit/test_bot_special_planner.gd | P3 (parallel with P4, which does not touch BotController) | Bomb/Rocket/Volcano/Black hole/Jumping Bean aim at the highest-downstream enemy joint or tower base in range; Paintball at the tallest enemy stack in range; Freeze/Glue on the own goal-covering or most threatened tower; Stackfall at the own tip; tilt specials keep today's heuristics; Easy never offensive |
| P6 | Evaluation and tuning (integrator, serial) | the four .tres files only (+ optional game/BotDecisionRecorder.gd: intent and terms for v2) | P4, P5 | screen, then the full battery below; results on the bead |
| P7 | Ship | game/BotController.gd (default `V2`), docs/SPEC.md §2.9 (orchestrator, after owner approval) | P6 + owner | reviewer pass on core/ai; legacy kept behind `--bot-brain=legacy` for one release |

P1 calls `BotSpecialPlanner.plan()` unchanged for V2 and must not edit BotSpecialPlanner.gd; P5 switches the V2 branch to `plan_v2`. P4 acceptance also covers the assembled pipeline (strategy -> sites -> probe -> proxy -> measured top-k -> pick -> re-validate). Reviewer: required for P1-P5 (core/ai). P2 and P3 run in parallel worktrees on P1's commit; P5 in parallel with P4 on P3's commit.

### 2.5 Evaluation harness and shipping bar
CPU cap: every run is sequential (`--parallel 1`) unless the orchestrator raises it; first a **screen** (E3 10 seeds + E2 10 pairs, about 1 h), the full battery only after the screen passes (an overnight job). Commands use `tools/bot_h2h.py` with `--godot-args "--match-seed={seed} --bot-difficulty=hard --bot-brain=v2 --bot-brain-slots={cand_slots}"` (P1b options).
- **E1 Classic 8 seats, v2 Hard x4 vs legacy Hard x4**, 50 seed pairs (100 matches, seats swapped), `--seconds 600`: Wilson lower bound >= 0.75 (tool PASS) and observed >= 0.85; timeouts <= 10%.
- **E2 Classic duel 1v1** (`--bots 2`, slots 0/1), 30 pairs: observed >= 0.85, lower bound >= 0.70.
- **E3 vs passive** (`--bots 1 --players 4 --no-swap`, 20 seeds, Classic M): 20/20 wins, median win time <= 120 s, max <= 240 s (legacy: 224 s in the one watched run; P1c measures its distribution). M5's < 10 min bar is kept for every tier.
- **E4 Elimination 8 seats**, 30 pairs, `--seconds 600`: >= 70% of matches decided (today 0 of 60 within 296 s), candidate share lower bound >= 0.65; vs passive (`--bots 1 --players 5 --mode=elimination`, 10 seeds): last seat standing within 600 s in >= 8/10 (provisional until P1c records legacy; passive piles reach 20+ m, so this tests the tower duel). 2-4 seat Elimination is excluded until owner decision Bontago-1t5.6 is answered.
- **E5 Tier ladder** (1v1, 20 pairs each): v2 Hard vs v2 Normal >= 75%, v2 Normal vs v2 Easy >= 75%, v2 Normal vs legacy Hard >= 55%; v2 Easy beats passive within 600 s in 10/10.
- **E6 Perf** (bench_headless_bots with `--bot-brain=v2`, alone on the machine): per-bot think <= 1.2 ms per physics frame, all bots <= 3 ms in any frame, decision ready <= 0.5 s after the release boundary; no errors.
- **E7 Feel check** (two off-screen sheets: 4-bot Hard Classic, Hard vs 3 passive): visible towers (own max >= 8 m by 180 s); no one-wide chain longer than about 10 m without an anchor; reacts to a threat within 2 placements; no dithering at the goal zone (gap <= 4 m to capture start <= 30 s); <= 15% placements with no measured gain and no intent; blocks lost per placement <= 0.15 (today 0.147); Easy visibly slower and wobblier. Recorded-data checks if P6 adds recorder support: chosen top >= 1 m in >= 35% of classic decisions (today 9.6%), >= 30 s no-growth stretches <= 10% of decisions (today 27%).
- Mode smoke: CTF, Reach the Sky and Domination, two matches each: no errors, each bot scores or grows.

### 2.6 Difficulty semantics (V2)
| | Easy | Normal | Hard |
|---|---|---|---|
| Intents | RACE, ANCHOR (fixed rhythm), FINISH | + HOLD, DEFEND (reactive only) | + STRIKE, threat look-ahead, Elimination target spread |
| Sites / measured top-k | 40 (half FILL) / 0 | 70 / 6 | 110 / 12 |
| Pick | sample from top 5 (high temperature) | sample from top 3 (low) | argmax |
| Aim noise / reaction | 0.6 m / 1.2 s | 0.3 m / 0.6 s | 0.05 m / 0.2 s |
| Specials | spent without targeting (today's Easy) | defensive + simple offensive | full v2 targeting |

Easy stays a beatable learner bot that still visibly builds and finishes; Normal should be about as strong as today's Hard; Hard is the strongest the frame budget allows.

### 2.7 Departures from docs/SPEC.md §2.9 (owner approval needed; §2.9 is [ORIGINAL feature, NEW implementation], so no [ORIGINAL] rule changes)
1. Candidate spots: from "samples 40-120 candidate spots" in its territory to 40-120 **targeted** sites (frontier tip toward the current target, own stack tops, strike/defend points) plus a few random ones.
2. Orientation: from "the orientation that gives the flattest base" to the orientation with the most reach that passes an analytic stability check (upright at the tip, flat as a tower base).
3. Scoring: "height gained, goal progress, stability, risk" become intent-weighted terms: reach toward the target, measured territory gain (raster samples), enemy chains/towers cut, exposure to enemy reach, tip-over risk, wasted overlap. Stability survives as tip risk and no longer rewards ground contact.
4. New strategy layer: explicit intents (race, anchor, finish, hold, defend, strike, plus siege/area per mode) chosen per piece.
5. Difficulty: adds intent set, evaluation depth and pick temperature to samples, aim error, reaction delay and specials use.
6. Specials: targets come from enemy chain joints/towers and own key towers (Paintball, Freeze and Glue used deliberately) instead of circle-centre clusters.
7. Thinking: still host-only and spread over frames, now by a per-frame microsecond budget instead of a fixed candidates-per-frame count.

### 2.8 Risks
- Towers topple: statics, flattest pieces for stacking, Glue/Freeze use; tracked as blocks lost per placement.
- OFF hole mode has no dissolve kill (argmax borders): the evaluator's kill term is mode-aware; one OFF smoke in P6.
- v2 mirror matches may stall in a central tower duel: E1/E4 timeout ceilings catch it; sudden death exists for timed matches.
- Evaluation wall time under the CPU cap (about 300 matches): screen first, battery overnight.
- Hard may feel unfair to new players: owner feel check on the E7 sheets.
