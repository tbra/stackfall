# Autoload decoupling plan: S1 MatchContext, S2 world bases + facades, S3 Net injection, S4 lint

Design contract for Bontago-1pi.11.76 (owner accepted Bontago-1pi.11.56, 2026-10-10); base `main@e51df2ea`
(S0 merged). **Supersedes docs/STARTUP_COMPILE_PLAN.md section 2 slices B0a-B4 and C1/C2** (slice A has
landed); its section 1 measurements and B-slice notes remain background, its line numbers are stale.
Simulations: `M:/Bontago-tools/scratch/decoupling-plan/{exp*.py,closure.py}` over dep_graph graph.json.
Every package: static typing, no magic numbers, `# DECISION:` at each widened boundary, no behaviour
change (pure refactor; no [ORIGINAL] rule, no owner question), import check clean, both lints green.

## 1. Baseline (dep_graph on e51df2ea)

- File SCC #1: **68 files** (Match, Net, SnapshotSync), 269 internal edges. Autoload compile
  closure (class/autoload_use/extends/preload/ext_resource edges from the 10 autoloads):
  **225 .gd / 59.5k lines** (STARTUP plan: 3.58 s autoload compile, first frame 4.90 s).
- Cycle-forming edge groups (src:line, first occurrence; edges are per file):
  - **G1 world -> Match** (S1): Field.gd:1160; GhostPreview.gd:2346,2347,2351,2354; GiftCrate.gd:325,395,414-440;
    HoleDissolver.gd:157; BlockEffectsManager.gd:292; specials Anvil:66, BlackHoleEffect:64,
    BlackHoleField:48, BlackHoleVisual:121, CatController:130,152-159, CatEffect:14-18, Earthquake:41,
    Freeze:92, Glue:13, JumpingBean:181,218-220, Paintball:93-106, PaintballSplash:33, PropellerStand:37,43,102,111,
    Rocket:107, Stackfall:31-48, StackfallRain:38,57,70,116, VolcanoStructure:63,69,80,171;
    fx/BlockSpawner:17-22, fx/DiscAnchor:11, fx/GiftFxPresenter:71-104, fx/HolePunch:18-25;
    vfx/weather RainPresentation:168, HorizonStormCells:64, StormPresentation:161, BreezePresenter:43.
  - **G2 world -> Net** (moved into S1, see D6): Field.gd:1345 `Net.is_host`, GhostPreview.gd:2346/2353
    `is_offline/local_slot`, GiftCrate.gd:417 `is_local_slot`, StableBlockManager.gd:104 `is_host`,
    FreezeEffect.gd:62 `is_client`.
  - **G3 weather effects -> MatchAutoload** (S1f): WeatherEffect.gd:19-24 `match_ref: MatchAutoload`,
    BreezeEffect.gd:67-70,251, StormEffect.gd:34, weather/SnowEffect.gd:115, MatchWeather.gd:93-95,458;
    closed through `config/weather/rain.tres:17 effect_script` (runtime path string).
  - **G4 specials -> autoload/match**: StackfallEffect.gd:27/42 `MatchGiftActivation.SEQ_META`.
  - **G5 net layer** (S3): LanDiscovery.gd:170,201 `Net.DISCOVERY_MAGIC`; SteamClient.gd:155-156
    `Net.STEAM_APP_ID_EXPECTED`; SnapshotSync.gd:119,285,290,340,363,420,907 `Net.*`; Net.gd:1206 ->
    SnapshotSync; Skybox.gd:351,404 `SnapshotSync.sky_cycle_seconds()`.
  - **G6 facades -> world** (S2): Match.gd:126-127,147-164,197,235,364; SnapshotSync.gd:85,374,408;
    MatchNet.gd (Block x17, BlockRegistry x9, SpecialDef x7, WeatherNet x3, MatchGifts consts x6, MatchStats/
    ModeObjective validators, CatController x2, BlockFactory x2, HoneyCoat x2); Sfx.gd:31,144-145,836.
- Simulation: cutting only G1+G2+G3+G4 gives SCCs 31 (world-internal, no autoload) + 10 (Match +
  controllers) + 4 (Net cluster). Any single remaining G1 edge keeps 66-68 (HoleDissolver alone keeps 66).

## 2. Decisions (minor; implementation detail, no gameplay impact)

- **D1** Boundary types live in **`game/world/`**, not `core/` as the audit sketched: CLAUDE.md and
  dep_graph's `core_scene_tree` rule forbid scene-tree types in core/, and MatchContext hands out
  Node3D/FieldBody. Pure pieces still go to core/ (MatchPhase, GiftWirePhase, ResultsValidation, NetIds).
- **D2** World code reads **`MatchContext.current()`**, a static holder installed by `Match._ready()`;
  setup points that already receive Match get it explicitly (`WeatherEffect/BreezeEffect.bind` via
  `Match.context()`). SpecialEffects are shared `.tres` Resources and fx helpers are static, so there is no
  per-instance setup point; existing tests keep driving the real Match. Tests installing a
  `FakeMatchContext` restore the previous one.
- **D3** Forwards are 1:1 and keep their source: `has_authority()` = `Match._is_host()` (honours
  `Match.set_net_provider`), `net_*()` = the real `Net` autoload (ignores that provider), exactly as each
  call site behaves today. Never merge the two.
- **D4** `Match.State` and its predicates move to pure **`core/rules/MatchPhase.gd`**; `MatchAutoload`
  keeps `const State = MatchPhase.State` (precedent `MatchConfig.MapVariant = MapDef.MapShape`) and
  one-line forwarding statics (~100 callers untouched); STATE_SET owner += MatchPhase. Fallback if the
  alias fails as a cross-class type (MatchLifecycle.gd:16,273,377,1176): keep `enum State` in Match, give
  MatchPhase `const LOBBY: int = 0 ...` and pin both in test_match_phase.
- **D5** Port signatures use native/light types (Node, Node3D, RigidBody3D, Resource, FieldBody, config/
  and core/ classes). World code casts locally (`as Field`, `as Block`, `as BlockRegistry`).
  `MatchContextLive` passes values straight through (implicit, runtime-checked conversion) so it names
  no game/ class outside game/world/ and stays out of the world compile closure.
- **D6** The G2 world -> Net edges move in S1 (same files, one edit each). S3 keeps the net-layer
  injection (G5).
- **D7** S2 absorbs B0a, B0b, B1, B3 and B2's Sfx half; B2's SnapshotSync half merges into S3a so
  `net/SnapshotSync.gd` has one owner. C1/C2 (thin MatchNet/Net) stay optional (S3c).
- **D8** FieldBody/BlockBody virtuals are overridden with identical signatures. Members whose signature
  names a heavy type (`BlockRegistry.all_blocks() -> Array[Block]`) are not lifted: facades hold them as
  `Node`, call dynamically (DECISION comment) and store typed-array results in an untyped `Array` local.
- **D9** The `{autoload/Match.gd, autoload/match/MatchContextLive.gd}` pair is a deliberate 2-file
  adapter cycle (allow-listed in S4), like the benign .gd/.tres pairs.

## 3. Interfaces (exact)

```gdscript
# core/rules/MatchPhase.gd (S1a) -- bodies MOVED from autoload/Match.gd:44-90
class_name MatchPhase
extends RefCounted
enum State { LOBBY, LOADING, COUNTDOWN, PLAYING, SUDDEN_DEATH, END }
static func is_live(state: int) -> bool   # also is_replicating, is_resetting, is_in_progress, is_pregame, is_lobby_or_end (same signature)
static func is_start_transition(from_state: int, to_state: int) -> bool
# autoload/Match.gd: `const State = MatchPhase.State`; each static above stays, body `return MatchPhase.<same>(...)`.

# game/world/MatchContext.gd (S1b) -- port; defaults = "no match, offline" null object
class_name MatchContext
extends RefCounted
static var _installed: MatchContext = null
static var _null_context: MatchContext = null
static func current() -> MatchContext        # _installed, else lazily-built MatchContext.new()
static func installed() -> MatchContext      # may be null; tests save/restore with it
static func install(context: MatchContext) -> void   # null uninstalls
# session (D3)
func has_authority() -> bool                 # true   | Match._is_host()
func net_is_host() -> bool                   # true   | Net.is_host()
func net_is_client() -> bool                 # false  | Net.is_client()
func net_is_offline() -> bool                # true   | Net.is_offline()
func net_local_slot() -> int                 # -1     | Net.local_slot()
func net_is_local_slot(slot_id: int) -> bool # false  | Net.is_local_slot(slot_id)
# read model
func config() -> MatchConfig                 # null   | Match.config
func physics_tuning() -> PhysicsTuning       # null   | Match._physics_tuning
func state() -> int                          # MatchPhase.State.LOBBY | Match.state()
func slot_count() -> int                     # 0
func slot(slot_id: int) -> PlayerSlot        # null
func slot_color(slot_id: int, fallback: Color = Color.WHITE) -> Color   # fallback
func active_slot() -> int                    # -1
func field() -> FieldBody                    # null
func registry() -> Node                      # null   | Match.registry() (a BlockRegistry)
func blocks_parent() -> Node3D               # null
func raster() -> TerritoryRaster             # null
func cell_grid() -> CellGrid                 # null
func qol_claim_radius() -> float             # 0.0
func glue_drops_left(slot_id: int) -> int    # 0
func feed_timer_enabled() -> bool            # false
func feed_time_left(slot_id: int) -> float   # 0.0
func has_weather() -> bool                   # false  | Match.weather() != null
func weather_seed() -> int                   # 0      | Match.weather().seed_value()
func weather_event_index() -> int            # 0      | Match.weather().event_index()
func shared_clock_seconds() -> float         # 0.0    | SnapshotSync.sky_cycle_seconds()
# host commands: Match re-validates each exactly as today (authority, slot range, state)
func start_cat(owner_slot: int, position: Vector3, effect: Resource) -> bool          # false
func end_cat(activation_id: int) -> void
func grant_glue_drops(slot_id: int, count: int) -> bool                               # false
func convert_block_owner(block: RigidBody3D, new_slot: int) -> bool                   # false
func spawn_special_projectile(shape: BlockShape, world_origin: Vector3, basis: Basis, owner_slot: int,
		initial_velocity: Vector3, orb_def: SpecialDef, orb_tuning: SpecialTuning) -> RigidBody3D   # null
func punch_special_hole(disk_pos: Vector2, radius_m: float, hole_open_s: float) -> void
func add_match_child(node: Node) -> void     # default: node.queue_free() | Match.add_child(node)

# autoload/match/MatchContextLive.gd (S1b): class_name MatchContextLive extends MatchContext
var _match: MatchAutoload
func _init(match_node: MatchAutoload) -> void
# overrides every method above with the forward shown after "|" (or the same-named Match method).
# autoload/Match.gd (S1b): var _context: MatchContextLive; func context() -> MatchContext
#   _ready(): first statements `_context = MatchContextLive.new(self)` + `MatchContext.install(_context)`
#   _notification(NOTIFICATION_PREDELETE): uninstall if MatchContext.installed() == _context

# game/world/FieldBody.gd (S1b): class_name FieldBody extends AnimatableBody3D; Field.gd `extends FieldBody`
@export var map_def: MapDef = preload("res://config/maps/round_medium.tres")   # MOVED Field.gd:66
func map_definition() -> MapDef; func surface_y() -> float                 # MOVED :218, :225
func disk_local_from_world(world: Vector3) -> Vector2                       # MOVED :232
func world_from_disk_local(local: Vector2, height: float) -> Vector3        # MOVED :238
# virtual stubs; Field keeps its bodies as overrides with identical signatures:
func grid() -> CellGrid                                      # null      (Field :212)
func tilt_vector() -> Vector2                                # ZERO      (:307)
func apply_tilt_impulse(direction: Vector2, magnitude: float) -> void           # (:330)
func apply_replicated_pose(offset: Vector3, tilt: Quaternion) -> void           # (:370)
func is_hole_cell(index: int) -> bool                        # false     (:891)
func remove_fallen_block(body: RigidBody3D) -> void          #           (:1344)

# tests/unit/support/FakeMatchContext.gd (S1b): class_name FakeMatchContext extends MatchContext;
# one public `<name>_value` field per read, `<command>_calls: Array[Dictionary]` per command.

# game/world/BlockBody.gd (S2a): class_name BlockBody extends RigidBody3D; Block.gd `extends BlockBody`
@export var shape_id: StringName = &""; @export var owner_slot: int = -1; @export var net_id: int = -1
var gift_id: StringName = &""                                # all MOVED from Block.gd:8,14,19,23
static var impact_speed_min: float = 1.0; static var impacts_enabled: bool = true   # MOVED :58,:61
# + same-signature virtual stubs for each Block method a facade calls (worker lists them, D8).

# S2a core/gifts/GiftWirePhase.gd + core/rules/ResultsValidation.gd: STARTUP plan B0a minus PENDING_SPECIAL_ID
#   (core/rules/SpecialIds.gd). S2b autoload/LateScripts.gd: STARTUP plan B0b API; path consts for the 7
#   controllers, MatchWeather, GiftFxPresenter, CatController, WeatherNet, BlockFactory, SpecialDef, HoneyCoat, cat.tres.
# S3a core/net/NetIds.gd (class_name NetIds extends RefCounted): const DISCOVERY_MAGIC: String,
#   const STEAM_APP_ID_EXPECTED: int, MOVED from Net.gd, which keeps `const X: T = NetIds.X` aliases.
# S3a net/SnapshotSync.gd: var _bound_net: Node; func bind_net(net: Node) -> void (called from Net._ready;
#   globals are bound before any _ready, main.cpp pass 2); func _net() -> Node replaces each direct `Net.`.
```

**S1 migration rules** (consumers): `Match.x()` -> `MatchContext.current().x()` (one local `ctx` per
function, never per loop element); `Match._is_host()` -> `has_authority()`; `Net.x()` -> `net_x()`;
`Match.config` -> `config()`; `Match.slot(i).color` -> `slot(i).color`; `MatchAutoload.is_live(Match.state())`
-> `MatchPhase.is_live(ctx.state())`; `Match.State.PLAYING` -> `MatchPhase.State.PLAYING`;
`Match.field()` -> `ctx.field()` typed `FieldBody` when only FieldBody API is used, else `as Field`;
`Match.add_child(n)` -> `add_match_child(n)`; `Match._physics_tuning` -> `physics_tuning()`.
Nothing else in the file changes. A protected file may name no autoload except Events/Settings/Sfx/Rumble.

## 4. Packages, order and expected SCC

| Pkg | Stage | Owned files (all others excluded) | Needs | Parallel with | Edges cut | Largest SCC after |
| --- | --- | --- | --- | --- | --- | --- |
| S1a | S1 stub | core/rules/MatchPhase.gd (new), autoload/Match.gd, tools/lint_single_source.py, tests/unit/test_match_phase.gd (new) | main | S2a, S2b, S4a | none (prep) | 68 |
| S1b | S1 stub | game/world/MatchContext.gd, game/world/FieldBody.gd, autoload/match/MatchContextLive.gd (new x3), autoload/Match.gd, game/Field.gd, tests/unit/support/FakeMatchContext.gd, tests/unit/test_match_context.gd (new x2) | S1a (same worktree, serial) | S2a, S2b, S4a | Field.gd:1160,1345 | 69 (adapter joins) |
| S1c | S1 | game/GhostPreview.gd, game/GiftCrate.gd, game/StableBlockManager.gd, game/BlockEffectsManager.gd, vfx/weather/{RainPresentation,HorizonStormCells,StormPresentation,BreezePresenter}.gd | S1b | S1d, S1e, S1f, S2* | G1/G2 for those 8 | 69 |
| S1d | S1 | game/specials/{CatController,CatEffect,GlueEffect,PaintballEffect,PaintballSplash,StackfallEffect,StackfallRain}.gd, autoload/match/MatchGiftActivation.gd, core/rules/SpecialIds.gd | S1b | S1c, S1e, S1f | G1 + G4 | ~68 |
| S1e | S1 | game/specials/{AnvilEffect,BlackHoleEffect,BlackHoleField,BlackHoleVisual,EarthquakeEffect,FreezeEffect,JumpingBeanEffect,PropellerStand,RocketEffect,VolcanoStructure}.gd | S1b | S1c, S1d, S1f | G1/G2 | ~68 |
| S1f | S1 | autoload/match/{WeatherEffect,WindEffect,BreezeEffect,StormEffect,MatchWeather}.gd, autoload/match/weather/{RainEffect,SnowEffect}.gd, tests/unit/test_gust_storm.gd, tests/unit/test_weather_snow.gd | S1b | S1c, S1d, S1e | G3 | ~67 |
| S1g | S1 (last) | game/specials/fx/{BlockSpawner,DiscAnchor,GiftFxPresenter,HolePunch}.gd, game/HoleDissolver.gd | S1b, **fca.75 merged** | S2a-S2d | last G1 edges | **31** world-only; autoload SCC 11 (Match + 9 controllers + adapter); Net 4 |
| S2a | S2 stub | game/world/BlockBody.gd, core/gifts/GiftWirePhase.gd, core/rules/ResultsValidation.gd (new x3), game/Block.gd, autoload/match/MatchGifts.gd, autoload/match/MatchStats.gd, core/rules/ModeObjective.gd, tests/unit/test_light_boundary_types.gd (new) | main | S1a-S1g, S2b | none (prep) | unchanged |
| S2b | S2 stub | autoload/LateScripts.gd (new), game/Boot.gd, tests/unit/test_late_scripts.gd (new), tests/unit/test_boot.gd | main | all | none (prep) | unchanged |
| S2c | S2 | autoload/Match.gd, autoload/match/MatchContextLive.gd, tests/unit/test_match_activation.gd (new) | S1b, S2a, S2b | S2d, S3a | G6 Match.gd | autoload SCC 2 (D9); controller pairs <=2 |
| S2d | S2 | net/MatchNet.gd | S2a, S2b | S2c, S3a | G6 MatchNet | unchanged (not in SCC) |
| S2e | S2 | autoload/Sfx.gd | S2a, **fca.76 merged** | any | G6 Sfx | unchanged |
| S3a | S2+S3 | core/net/NetIds.gd (new), autoload/Net.gd, net/LanDiscovery.gd, net/SteamClient.gd, net/SnapshotSync.gd, tests/unit/test_net_injection.gd (new) | S1b, S2a | S2c, S2d | G5 net + G6 SnapshotSync | Net SCC 4 -> 0 |
| S3b | S3 | game/Skybox.gd | S1b, **fca.76 merged** | any | Skybox.gd:351,404 | unchanged |
| S3c | S3 opt. | thin MatchNet/Net (STARTUP plan C1/C2; split if >10 files) | S2 measured | - | - | - |
| S4a | S4 | tools/lint_layers.py (new), tools/dep_graph.py, tools/test_lint_layers.py (new), tools/layer_baseline.json (new, report-only) | main | all | - | - |
| S4b | S4 | tools/full_gate.py, tools/layer_baseline.json | S1-S3 merged, S4a | - | - | records final |

Final (S1-S3 merged): no autoload in any SCC except the D9 pair; largest SCC ~29-31 (world-internal);
autoload closure ~76 .gd / ~23k lines (simulated 68 / 22.2k + ~8 new light files) vs 225 / 59.5k; modelled
first frame ~2.4 s (STARTUP plan B), only once S2c+S2d+S2e+S3a are all merged.

Integration batches (full gate once per batch, orchestrator): **B1** S1a+S1b (+S2a, S2b, S4a if ready);
**B2** S1c+S1d+S1e+S1f; **B3** S1g (after fca.75) then dep_graph confirms 31/11/4; **B4** S2c+S2d+S3a;
**B5** S2e+S3b (after fca.76); **B6** startup re-measure (integrator, idle machine) then S4b; S3c only if
first frame (3 windowed off-screen runs of `res://tools/probe_startup_gaps.tscn -- --agent-probe boot`,
median) is above 2.2 s. Writers of autoload/Match.gd are strictly serial: S1a -> S1b -> S2c.

## 5. Package briefs (dispatch-ready)

Sonnet unless noted; probes in scratchpad only; every harness/bot run has a 15 min deadline; every
brief also runs `affected_tests.py` and its list; "review" = stackfall-reviewer after the worker.

**S1a MatchPhase** (implementer, 20 min, review). Move `enum State` + the seven predicates from
Match.gd:44-90 into MatchPhase (D4); Match keeps alias + forwards; STATE_SET owners += MatchPhase.
test_match_phase: ordinals 0..5 pinned, `MatchAutoload.State.keys() == MatchPhase.State.keys()`, truth
table of every predicate over all states, forwards equal. Checks: import check, test_match_phase,
test_scoreboard_overlay, test_match_reset_rules, `python tools/test_lint_single_source.py`.

**S1b MatchContext stub** (implementer, 30 min, review; interface stub, merge before S1c-S1g). Section 3
verbatim; Field extends FieldBody (moved members, overrides kept), Field.gd:1160 ->
`qol_claim_radius()`, :1345 -> `net_is_host()`. test_match_context: null-object defaults;
install/installed/restore; live installed after boot; parity with Match (state, slot_count, config,
field/registry/blocks_parent after `Match.register_world` with a test Field); `has_authority()` follows
`Match.set_net_provider(FakeNet client)` while `net_is_host()` stays `Net.is_host()` (D3 guard);
`Field is FieldBody`, disk-local round trip unchanged. Checks: import check, test_match_context,
test_field_cells, test_match_restart, test_hole_dissolve, test_disc_body; ObjectDB-leak line of
`godot --headless --verbose --path . --quit-after 120` not above baseline (PREDELETE uninstall).

**S1c world presenters** (implementer, 25 min). Migration rules on the 8 files only.
`GiftCrate._local_watch_slot` keeps hot-seat -> `active_slot()`, else the `net_is_local_slot` loop;
HorizonStormCells seeds only when `has_weather()`. Checks: test_ghost_preview, test_ghost_tint,
test_gift_claim_crate_feedback, test_gift_flight, test_stable_block_manager, test_block_effects,
test_weather_rain, test_weather_storm, test_horizon_storm_cells, test_weather_breeze,
test_match_restart; `tools/run_m3a_local.ps1 -Peers 4 -SimLag 100 -SimLoss 0.02` (client tint/glue/feed ring).

**S1d specials, host commands** (implementer, 25 min, review). Migrate the 7 specials; SEQ_META value
moves to `SpecialIds.ACTIVATION_SEQ_META`, `MatchGiftActivation.SEQ_META` aliases it (S0 pattern);
CatEffect passes itself as `effect`. Add FakeMatchContext cases (GlueEffect records one
`grant_glue_drops` call; CatEffect on a non-authority fake does nothing). Checks: test_cat_effect,
test_glue_effect, test_paintball_effect, test_stackfall_effect, test_gift_in_place,
test_gift_effects_ride_disc, test_match_net, test_match_reset_fingerprint; `tools/run_gift_fx_enet.ps1`.

**S1e specials, world reads** (implementer, 25 min, review). Migrate the 10 files (FreezeEffect:62 ->
`net_is_client()`); FieldBody-typed locals where only FieldBody API is used. Checks: test_anvil_effect,
test_special_black_hole, test_black_hole_gift_demo_flow, test_earthquake_effect, test_freeze_effect,
test_jumping_bean_effect, test_propeller_effect, test_rocket_effect, test_volcano_effect,
test_volcano_structure, test_gift_entrances; `tools/run_black_hole_enet.ps1`.

**S1f weather effects** (implementer, 25 min, review). `WeatherEffect.match_ref: MatchAutoload` ->
`context: MatchContext`, `bind(context: MatchContext, weather_tuning: WeatherTuning)` (Storm/Snow
overrides follow); BreezeEffect.bind takes MatchContext and `_active_weather_id()` uses only its existing
`_weather_id_source`, which MatchWeather.setup now sets to its own `active_id`; MatchWeather passes
`_match.context()`; host checks -> `context.has_authority()`; registry/field cast locally.
test_gust_storm.gd:188 -> `bind(MatchContext.current())`. Checks: test_gust_storm, test_match_weather,
test_weather_rain, test_weather_storm, test_weather_snow, test_weather_breeze,
test_weather_wind_settled_tower, test_wire_schema.

**S1g fx + HoleDissolver** (implementer, 20 min, review; base must contain fca.75). Migrate 5 files; keep
HoleDissolver's `func _is_host` (LINE_ALLOW). `python tools/dep_graph.py --root <checkout> --out
<scratch>` must show largest SCC ~31 without autoloads plus a Match cluster ~11. Checks:
test_hole_dissolve, test_field_cells, test_gift_fx_spawner, test_gift_fx_presenter,
test_gift_effects_ride_disc, test_volcano_structure, test_jumping_bean_real_physics;
`tools/run_gift_fx_enet.ps1`. Integrator after B3: one bot match (`godot --headless --path . --
--headless-host --bots=8`, then `python tools/triage_log.py`), `run_m3a_local.ps1 -ReconnectPass
-LateJoinAfter 5`, `tools/run_reset_enet.ps1`.

**S2a light boundary types** (implementer, 25 min, review; stub). STARTUP plan B0a with D1 location, D8
virtual stubs, no PENDING const. Checks: test_light_boundary_types (source scan: the new files name no
class outside core/, config/, game/world/), test_block*, test_gift*, test_match_stats*,
test_mode_objective*, test_results*, test_sfx*.

**S2b LateScripts** (implementer, 20 min, review; stub). STARTUP plan B0b unchanged, including its one
off-screen windowed check that `current_scene` is Boot at autoload `_ready`. Checks: test_late_scripts,
test_boot, test_startup_pump.

**S2c Match facade** (implementer, 30 min, review). STARTUP plan B1 with deltas: `_field: FieldBody`,
`field() -> FieldBody`, `register_world(field: FieldBody, ...)`, `_registry: Node`; controllers,
MatchWeather, GiftFxPresenter, CatController, cat.tres via LateScripts in `late_activate()`;
`start_cat(..., effect: Resource)`; context install stays in the light `_ready`; every forward
MatchContextLive uses returns the null-object value before activation. test_match_activation (new):
deferred instance inactive after `_ready`, `late_activate` builds controllers in today's order, second
call no-op, context answers defaults while inactive. Checks: test_match*, test_gift*, test_cat*,
test_sandbox*, test_match_context; `run_m3a_local.ps1 -Peers 4 -SimLag 100 -SimLoss 0.02`.

**S2d MatchNet facade** (netcode, 30 min, review). STARTUP plan B3 plus HoneyCoat.set_coated,
MatchStats.build_live_payload, BlockFactory/SpecialDef statics via LateScripts or ResultsValidation;
WeatherNet created in `late_activate()`, RPC path `/root/MatchNet/WeatherNet` unchanged. Checks:
test_match_net*, test_gift*, test_net_session, test_net_helpers, test_late_join, test_late_join_silence,
test_intent_gate; `run_m3a_local.ps1 -Peers 4 -SimLag 100 -SimLoss 0.02 -ReconnectPass`.

**S2e Sfx** (implementer, 15 min, review; base must contain fca.76). Sfx.gd:144-145 ->
`BlockBody.impact_speed_min/impacts_enabled`, :836 `is BlockBody`. Checks: test_sfx, test_sfx_impacts,
test_block_awake_set.

**S3a Net layer** (netcode, 30 min, review). NetIds (Net keeps aliases); LanDiscovery/SteamClient use
NetIds; SnapshotSync `bind_net`/`_net()` (direct `Net.` sites -> `_net()`, `_session()` keeps provider
semantics, D3) plus B2 typing (BlockBody, Node registry, FieldBody `_disk`). test_net_injection (new):
bound net used, provider still wins in `_session()`, NetIds equal Net aliases. Checks:
test_snapshot_sync, test_snapshot_wire, test_interpolator, test_net_session, test_steam_client,
test_lan_discovery, test_late_join; `run_m3a_local.ps1 -Peers 4 -SimLag 100 -SimLoss 0.02
-LateJoinAfter 5`; `godot --headless --path . res://tests/bench/bench_snapshot.tscn` alone (no regression).

**S3b Skybox clock** (implementer, 10 min; base must contain fca.76). Skybox.gd:351,404 ->
`MatchContext.current().shared_clock_seconds()`. Checks: test_skybox, test_match_reset_sky,
test_sky_random_start.

**S4a lint tool** (tooling, 25 min, no review): section 6, report-only; `python tools/test_lint_layers.py`;
`--report` on main lists the G1-G5 sources and SCC 68. **S4b** (Haiku integrator, 10 min): record the
baseline, hook full_gate; fails on a scratch copy with `Match.state()` in a special or `var x: Block` in Match.gd.

## 6. S4: dep_graph-based layer lint

- CLI: `python tools/lint_layers.py [--root PATH] [--report] [--list] [--update] [--allow-new PATH]`;
  `python tools/dep_graph.py --check [same flags]` delegates. Reuses `dep_graph.build_graph()` (~10 s);
  exit 1 on violation unless `--report`.
- **L1 protected names.** Sources: `core/**`, `config/**`, `game/specials/**`, `game/world/**`, `vfx/**`
  and game/{Block, BlockFactory, BlockRegistry, BlockStepBatch, Field, GhostPreview, GiftCrate,
  HoleDissolver, StableBlockManager, SandboxConeAdapter, BlockEffectsManager, Skybox}.gd. Forbidden: any
  compile edge (class, autoload_use, extends, preload, ext_resource) to `autoload/Match.gd`,
  `autoload/Net.gd`, `net/**`, `autoload/match/**`. `path` edges (config/weather/*.tres `effect_script`)
  are info only (runtime `load()`, not a compile edge). No exceptions after S1-S3.
- **L2 SCC ratchet** on dep_graph's file SCCs (same numbers as cycles.md): fails if the largest SCC
  exceeds baseline or an SCC containing an autoload is not an allow-listed pair (D9); reports SCCs >= 5.
- **L3 autoload closure**: static compile closure of the `[autoload]` scripts (L1 edge kinds); fails when
  a file not in the baseline list enters it; reports .gd count and lines (lines never fail).
- Baseline `tools/layer_baseline.json` `{"largest_scc", "autoload_scc_pairs", "closure", "l1_exceptions"}`;
  `--update` only lowers/removes, additions need `--allow-new`. full_gate.py: `run_lint(path,
  "lint_layers", lint_layers)` after lint_single_source; `layer_lint=green|RED` in the FULL GATE line
  and result.json.
- `tools/test_lint_layers.py` (synthetic graphs): L1 hits on class and autoload_use edges; path edge
  ignored; SCC growth and a new closure file fail; allow-listed pair passes; `--update` never raises.

## 7. Risks and how they are caught

- **Host authority / intent validation**: no RPC handler, `request_*` or validation code moves; commands
  stay Match-side with today's guards; D3 keeps host checks identical (test_match_context provider
  case, test_intent_gate, effect tests, ENet runs with 100 ms lag / 2 % loss).
- **Replication, late join, reconnect, reset** (S2d, S3a): RPC paths unchanged; one context per process,
  Match keeps its field/registry validity guards; test_late_join*, test_snapshot*, test_match_restart,
  test_match_reset_*, `-LateJoinAfter 5`, `-ReconnectPass`, run_reset_enet.ps1, bench_snapshot.
- **Load order** (S2b/S2c): autoload globals are bound before any `_ready` (main.cpp pass 2); the
  context answers defaults before late activation; headless activates in `_ready`; audit other
  autoloads' `_ready` for Match calls (STARTUP plan B1 risk).
- **Test state / typing**: FakeMatchContext users restore `installed()` in `after_each`; implicit
  downcasts are runtime-checked; typed arrays and overrides per D8.
- **Overlap**: S1g waits for fca.75 (HoleDissolver); S2e/S3b wait for fca.76 (Sfx, Skybox). S1b's
  Field.gd change moves `map_def` only (fca.75 owns MapDef, not Field); rebase if both are open.
- **Startup**: L3 is the deterministic proxy; timing is batch B6 (3 runs, median, idle machine); no
  gain is expected until S2c+S2d+S2e+S3a are all merged.

## 8. Out of scope (follow-ups)

World-internal SCC ~29-31 (dropping Field or BlockRegistry in-edges leaves ~10-12; exp4.py: Block.gd:340,
BlockRegistry.gd:471, GiftFxPresenter); MatchLifecycle <-> MatchTerritory re-entrancy; HomeFlag/PulseRing.

## 9. Review notes (stackfall-reviewer, 2026-10-10) - binding for the package briefs

Verdict: approve with notes. Base for all packages is now main abb63afe (fca.75 merged: DiskShapeMesh and the
non-round shape code are gone; line numbers cited above may have moved - re-locate by symbol).
1. (Med, S1f) `bind(null, ...)` call sites (tests/bench/bench_snow.gd:139, tests/unit/test_weather_snow.gd:77):
   null must stay "no match", never fall back to `MatchContext.current()`. Add tests/bench/bench_snow.gd to S1f.
2. (Med, S3a) SnapshotSync `_net()` needs an unbound fallback to the real Net plus a test for it.
3. (Low, S3b/S2e) Skybox call sites are now around lines 374/449; Bontago-fca.76 owns Skybox/Sfx/AudioConfig/
   SkyboxConfig until it merges - S2e and S3b stay after fca.76 as planned.
4. (Low, B2) Add a headless bot match (`godot --headless --path . -- --headless-host --bots=8`, 15 min deadline)
   and `tools/run_reset_enet.ps1` (quote its ENET RESULT line) to batch B2's acceptance.
5. (Low, S1b) Guard against a leaked static `_installed` MatchContext between GUT scripts (uninstall on
   PREDELETE and reset in test support), with a test.
