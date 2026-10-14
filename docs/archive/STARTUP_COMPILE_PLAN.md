# Startup compile plan: autoload GDScript cascade (Bontago-1pi.11.55)

Design contract for slice 2 of Bontago-1pi.11.55. Measured on `wt/autoload-lazy` at
71788e5 (planner, 2026-10-07). Measurement only: no game code changed in slice 1.

## 1. Measurements

Machine idle, each windowed run off-screen (`--windowed --position 10000,10000
--resolution 320x180 --audio-driver Dummy ... -- --agent-probe`, worktree `override.cfg`), main
scene `res://tools/probe_startup_gaps.tscn` with `boot`. Windowed runs were used for the target
because engine and display initialization (1.31 s) is part of the time to the first frame. The
per-file cost model uses a headless run because compile cost does not depend on the display.

| Measurement (3 runs, median) | Value |
| --- | --- |
| First frame (probe `_ready`, Boot path), unmodified | **4.90 s** (4.996 / 4.899 / 4.881) |
| Engine/display initialization before the first autoload | 1.31 s |
| Autoload phase (first autoload `_init` to probe ready) | 3.58 s, all on the main thread with no message pump |

Per-autoload cost, measured by putting a marker autoload between each real autoload. The
markers were added through a temporary `[autoload]` re-order in `override.cfg`; the original
`override.cfg` was restored afterwards.

| Autoload | load+compile+init (median ms) | Share of 3.58 s | Why |
| --- | ---: | ---: | --- |
| Events | 57 | 1.6 % | 6 files (TerritoryRaster for signal types) |
| Settings | 147 | 4.1 % | 20 files, config `.tres` |
| **Net** | **2562** | **71.6 %** | first to touch the 186-file world SCC (via SnapshotSync, LanDiscovery, SteamClient -> Match -> world) |
| Match | 3 | 0.1 % | already compiled by Net's closure |
| SnapshotSync | 4 | 0.1 % | already compiled |
| **MatchNet** | **528** | **14.7 %** | MatchNet.gd itself (236 ms) + WeatherNet/SnowNet/weather presenters, ModeObjective tree |
| Sfx | 149 | 4.2 % | Sfx.gd 78 ms + audio config resources |
| Screenshots | 9 | 0.3 % | |
| Rumble | 41 | 1.1 % | |
| `_ready` of all autoloads | 38 | 1.1 % | Settings 13, MatchNet 13 |
| other (main-scene load) | 44 | 1.2 % | |

Per-file model (`tools/probe_script_self_cost.tscn`, headless): this run warm-loads every game
script, then times a `CACHE_MODE_IGNORE` reload of each one. Summed over a static compile graph
it matches the measurements: whole autoload closure predicted 3479 ms against 3582 ms measured
(the difference is ready/resources); Net marginal 2577 ms against 2562 ms; MatchNet 595 ms
against 528 ms. The graph treats these as edges, following `GDScriptCache` dependency recording
and `finish_compiling()`, which fully compiles every recorded dependency:
- a `class_name` identifier anywhere in the file (types, `.new()`, static calls, `is`/`as`, consts)
- an autoload identifier
- `preload` of a `.gd`
- the scripts inside a preloaded `.tscn`/`.tres`
- `extends`

Runtime `load("...")` is not an edge.

### Decisive findings

1. **The autoloads pull in a world strongly connected component (SCC).** Its core is 113 files:
   Block, Field, BlockRegistry, BlockFactory, SpecialDef -> SpecialEffect -> all specials,
   GiftFxPresenter, DiscBody, HoleDissolver and others (about 1.5 s). With
   `autoload/match/*`, vfx and net helpers it grows to 186 files and 48.7k lines. Every
   world class references `Match`/`Net`/`MatchNet` by autoload name, and those autoload
   scripts reference world classes by type, so the cycle closes. Net's own code is light. It
   pays the whole bill only because it is the first autoload to reach the SCC.
2. **Cuts are all-or-nothing.** The SCC is reached only through 98 references in four autoload
   scripts (counts are textual occurrences):
   - `autoload/Match.gd` (41): the 7 controllers, CatController/CatEffect, Field,
     BlockRegistry, Block, SpecialDef, GiftFxPresenter
   - `net/SnapshotSync.gd` (17): Block, BlockRegistry, Field
   - `net/MatchNet.gd` (37): Block, MatchGifts consts, BlockRegistry, WeatherNet, SpecialDef,
     CatController, MatchStats/ModeObjective static validators, BlockFactory
   - `autoload/Sfx.gd` (3): Block static vars and `is Block`

   Leaving any one of them in place pulls the SCC back:

   | Cut state | Modelled compile |
   | --- | ---: |
   | All cut except Match | 3137 ms |
   | All cut except SnapshotSync or Sfx | 2387 ms |
   | All cut except MatchNet | 3200 ms |
   | All four cut | **994 ms** |

   Events, Settings, Net, Screenshots and Rumble need no cuts.
3. **Engine initialization takes 1.31 s of the 2 s budget.** Measured without GodotSteam, which
   is gitignored and missing from worktrees; the main checkout loads its DLL as well. After all
   four cuts the remaining autoload compile is 994 ms: the autoload scripts themselves 659 ms
   (MatchNet 236, Net 120, Sfx 78, SnapshotSync 74, Match 62, Settings 42, Rumble 37) plus light
   dependencies 335 ms. Predicted first frame **~2.41 s**. Getting under 2 s also requires
   moving the autoload scripts' own bulk off the boot path:

   | Further change | Predicted first frame |
   | --- | ---: |
   | Thin MatchNet | 2.15 s |
   | + thin Net | 1.96 s |
   | + thin SnapshotSync | 1.86 s |
4. **A pump guard is feasible.** Probe `tools/probe_pump_guard.gd` is placed as the first
   autoload. It compiles the remaining autoload scripts on a worker thread, one
   `load_threaded_request` at a time, while calling `DisplayServer.process_events()`. Result:
   233 pumps, **max gap 29 ms**, no errors. The real autoload loads then hit the cache
   (9 ms). The first frame is 0.19 s later (5.09 s), and quit-time ObjectDB leaks rose from
   about 45 to 119 because the probe held references at exit. This removes Windows'
   "Not responding" during the autoload phase, whatever size the graph grows to. It does
   not move the first main-loop frame.
5. **Time to menu barely changes with any of these slices.** The world (about 2.5 s) and
   Main's own 66 files (about 2.4 s) still compile, on Boot's worker thread instead of the
   main thread. Menu stays at about 7.6 to 8.1 s. The slices buy a pumped window and early
   frames (room for a loading animation in Boot), not a faster menu.

## 2. Plan (independently landable slices)

Order: **A** (immediate fix, independent) -> **B0a + B0b** (interface stubs, parallel, disjoint) -> **B1, B2, B3 in parallel** (B2 needs only B0a) -> **B4**
(lint enforcement). **C1/C2 are optional**: re-measure after B before deciding.

Every slice:
- uses static typing, with a `# DECISION:` comment wherever a boundary is widened
- adds no magic numbers (consts carry a DECISION; nothing tunable)
- keeps `core/` free of scene-tree dependence
- keeps the Events bus
- passes `godot --headless --editor --path . --quit` with no errors or new warnings
- passes `python tools/lint_magic_numbers.py` and `python tools/lint_single_source.py`
- runs `python tools/affected_tests.py --path <checkout>` and the tests it lists

Saving is re-measured with the 3x windowed `probe_startup_gaps boot` (median), plus the marker
override where noted.

### Slice A: StartupPump autoload (Sonnet, about 30 min, review: yes because it touches autoload/)

Outcome: the main thread pumps window messages through the whole autoload phase, so Windows can
no longer show "Not responding" there.

Owned files:
- `autoload/StartupPump.gd` (new)
- `tools/bootstrap_project.gd` (`_apply_autoloads`)
- `project.godot` (regenerated `[autoload]` only)
- `tests/unit/test_project_setup.gd`
- `tests/unit/test_startup_pump.gd` (new)

Interface:
```gdscript
extends Node   # non-singleton autoload, FIRST in [autoload]
const PUMP_INTERVAL_MS: int = 5          # DECISION: implementation constant, not a tunable
static func autoload_script_paths() -> PackedStringArray   # ProjectSettings autoload/* order, '*' stripped, .gd only, excludes itself
static func pump_until_loaded(paths: PackedStringArray, pump: Callable, sleep_ms: int) -> Array[Resource]
func _init() -> void      # headless: return; else pump_until_loaded(autoload_script_paths(), DisplayServer.force_process_and_drop_events, PUMP_INTERVAL_MS) and hold the results
func _ready() -> void     # clears the held refs (main.cpp owns them now; avoids the exit-leak delta seen in the probe)
```

Rules:
- One `load_threaded_request` at a time, in autoload order. Do not issue concurrent requests:
  the closures overlap and are cyclic.
- A failed or invalid status ends that path's loop without an error of its own. main.cpp's own
  synchronous load reports it as today.
- `bootstrap_project.gd` owns the complete ordered autoload list: remove every
  `autoload/*` entry, then set them in order with `StartupPump="res://autoload/StartupPump.gd"`
  first. Regenerate it. `git diff project.godot` must show only the `[autoload]` re-order.

Tests:
- `test_project_setup`: the AUTOLOADS list is updated and StartupPump is root child index 0.
- `test_startup_pump`:
  - path list order, star-stripping and self-exclusion
  - `pump_until_loaded` with a counting Callable loads a small script and returns it
  - a missing path returns without hanging, under a 5 s guard
  - headless `_init` does nothing
- `test_boot` still passes.

Acceptance:
- Windowed probe with `probe_pump_guard`-style logging, or a temporary print: max pump gap
  ≤ 50 ms.
- First frame no worse than baseline + 0.25 s.
- Quit-time leak counts no higher than baseline (7 Texture RIDs, about 45 ObjectDB).

Risk:
- World static initializers now run on a worker thread. The probe showed no errors. Any future
  static init that touches main-thread-only API would fail here first.

### Slice B0a: light boundary types (Sonnet, about 25 min; interface-stub package, commit before B1-B3)

Owned files:
- `game/BlockBody.gd` (new)
- `game/Block.gd`
- `core/gifts/GiftWirePhase.gd` (new)
- `autoload/match/MatchGifts.gd`
- `core/rules/ResultsValidation.gd` (new)
- `autoload/match/MatchStats.gd`
- `core/rules/ModeObjective.gd`
- `tests/unit/test_light_boundary_types.gd` (new)

```gdscript
class_name BlockBody extends RigidBody3D      # game/BlockBody.gd; references no other class_name
@export var shape_id: StringName = &""          # MOVED from Block.gd:8 (also owner_slot :14, gift_id :19, net_id :23); not duplicated
static var impact_speed_min: float = 1.0        # MOVED from Block.gd:56/59 so Sfx can set them without naming Block
static var impacts_enabled: bool = true
# Block.gd: `extends BlockBody` (was RigidBody3D); delete the moved declarations.
# Members the autoloads call but that stay on Block (set_frozen_visual, is_frozen_visual,
# set_contributing_visual) are reached dynamically.

class_name GiftWirePhase extends RefCounted     # core/gifts/GiftWirePhase.gd
const FALLING: int = 0; const LANDED: int = 1; const WIRE_LEGACY: int = 2; const WIRE_REMOVED: int = 3
const PENDING_SPECIAL_ID: StringName = &"special_pending"
static func is_valid_wire_phase(value: int) -> bool
# MatchGifts.gd:20-35 re-exports them (const FALLING: int = GiftWirePhase.FALLING ...), so other consumers are unchanged.

class_name ResultsValidation extends RefCounted # core/rules/ResultsValidation.gd, pure
static func validate_results_payload(raw: Variant) -> Dictionary   # body MOVED from MatchStats.gd:418
static func validate_mode_state(raw: Variant) -> Dictionary        # body MOVED from ModeObjective.gd:205
# The old names remain one-line forwards. If validate_state needs the objective subclasses,
# leave it in ModeObjective: that costs about 134 ms but is not in the SCC.
```

Tests:
- `test_light_boundary_types`:
  - a static source scan finds that BlockBody, GiftWirePhase and ResultsValidation name no
    other class_name except Variant/native types
  - Block `is BlockBody`
  - moved `@export`s still load from block scenes
  - validator parity on the existing fixtures
- Also run `test_block*`, `test_gift*`, `test_match_stats*`, `test_mode_objective*`,
  `test_results*`, `test_sfx*`, plus the `affected_tests.py` list.

### Slice B0b: late-activation hook (Sonnet, about 20 min; commit before B1 and B3)

Owned files:
- `autoload/LateScripts.gd` (new)
- `game/Boot.gd`
- `tests/unit/test_late_scripts.gd` (new)
- `tests/unit/test_boot.gd`

```gdscript
class_name LateScripts extends RefCounted       # string paths ONLY: never a class_name, autoload name or preload of a world script
const MATCH_FEED: String = "res://autoload/match/MatchFeed.gd"   # ... one const per lazily loaded script (the 7 Match
#   controllers, GiftFxPresenter, CatController, WeatherNet, BlockFactory, SpecialDef, cat.tres)
const ACTIVATE_METHOD: StringName = &"late_activate"
static func paths() -> PackedStringArray        # every script const, for Boot's prewarm
static func script(path: String) -> GDScript    # load(path) as GDScript; push_error on null
static func boot_defers_activation(tree: SceneTree) -> bool   # tree.current_scene is Boot and DisplayServer.get_name() != "headless"
static func activate_autoloads(tree: SceneTree) -> void       # for each tree.root child in order: if has_method(ACTIVATE_METHOD), call it (idempotent per facade)
```

Each of B1-B3 adds `late_activate()` and `is_late_active()` to its own facade. LateScripts never
names the facades, so this package does not touch their files.

Boot.gd:
- In both paths, Boot prewarms `LateScripts.paths()` before `_start_main`.
- Threaded path: one `load_threaded_request` at a time after Main.tscn, polled in `_process`.
- Sync or fallback path: `load()`.
- It then calls `LateScripts.activate_autoloads(get_tree())`.
- Headless: the facades have already activated in `_ready`, so this does nothing.

Tests:
- `test_late_scripts`:
  - every path loads
  - `paths()` covers every const (reflection over the script constant map)
  - a source scan finds no class_name identifiers
  - `boot_defers_activation` is false headless and when `current_scene` is not Boot
  - `activate_autoloads` calls `late_activate` once on a test node
- `test_boot`: prewarm, then activation, before Main is added; the failure path is unchanged.

Acceptance check, one off-screen windowed probe: at autoload `_ready` time `get_tree().current_scene`
is the Boot instance. Expected from the main.cpp order, where `add_current_scene` runs before
`SceneTree.initialize`. Record the result. If it is null, use the fallback predicate
`ProjectSettings application/run/main_scene == Boot path and no scene argument on the command
line`, and record the DECISION.

Saving from B0a+B0b alone: none. They establish the types and the hook that B1-B3 use.

### Slice B1: Match facade (Sonnet, about 30 min, review: yes)

Owned files: `autoload/Match.gd` only. Fix any compile fallout in consumers only if the import
check reports errors; widening return types to native types gives UNSAFE_* warnings, which this
project leaves at "ignore".

Changes (anchors in `autoload/Match.gd`):
- Lines 126-127 `_field: Field` / `_registry: BlockRegistry` become `Node3D` / `Node`.
- Lines 146-163, the seven controllers plus `_cat`/`_gift_fx`, become `RefCounted` / `Node`
  (DECISION: the light boundary keeps the world SCC out of the autoload compile).
- `_ready()` at lines 167-190 is split:
  - The light part stays: Events connects that need no controller.
  - Controller and GiftFxPresenter creation moves to `late_activate()`, using
    `LateScripts.script(LateScripts.MATCH_FEED).new()` and so on, then `setup(self)` in the
    same order as today.
  - `_ready` calls `late_activate()` unless `LateScripts.boot_defers_activation(get_tree())`.
  - `_process`/`_physics_process` stay disabled until active.
- Public signatures are widened:
  - `active_cat() -> RigidBody3D` (line 192)
  - `start_cat(..., effect: Resource)` (196)
  - `register_world(field: Node3D, ...)` (345)
  - `registry() -> Node` (359)
  - `convert_block_owner(block: BlockBody, ...)` (363)
  - `field() -> Node3D` (383)
  - `orb_def: Resource` / `-> BlockBody` (800-802)
  - `weather() -> RefCounted` (894)
  - `stats() -> RefCounted` (905)
- Lines 209/235: `CatController.new()` becomes the LateScripts load.
- Line 234: `as SpecialDef` / `as CatEffect` become `Resource` plus a dynamic `.effect`.

Tests:
- `test_match*`, `test_gift*`, `test_cat*`, `test_sandbox*`, plus the `affected_tests.py` list.
- New `test_match_activation`: a fresh `MatchAutoload` instance with deferral forced is inactive
  after `_ready`; `late_activate()` creates the controllers in order; a second call does nothing.

Risks:
- An autoload `_ready` or Events emit before activation (windowed only) would reach a null
  controller. Audit `Net._ready` (Net.gd:250), `SnapshotSync._ready`, `MatchNet._ready`
  (MatchNet.gd:332), `Sfx._ready` (Sfx.gd:97), `Settings._ready` and `Rumble._ready` for
  `Match.*` calls and Events emits that controllers listen to.
- Typed-array assignments from now-dynamic calls must use an untyped `Array` local. Assigning
  `Array[Block]` to `Array[BlockBody]` is a runtime error.

### Slice B2: SnapshotSync and Sfx boundary (Sonnet, about 20 min, review: yes)

Owned files: `net/SnapshotSync.gd`, `autoload/Sfx.gd`.

SnapshotSync changes:
- `Block` becomes `BlockBody` (lines 393, 741-804, 951-959).
- `_registry: BlockRegistry` (85) and `begin_match(registry: BlockRegistry, ...)` (195) become
  `Node` with dynamic calls.
- `_disk as Field` (427) becomes `Node3D`.

Sfx changes:
- Lines 98-99 become `BlockBody.impact_speed_min` / `BlockBody.impacts_enabled`.
- Line 640 `is Block` becomes `is BlockBody`.
- If SnapshotSync's `_ready` touches no world code, it needs no activation; otherwise its
  `late_activate()` holds that part.

Tests: `test_snapshot*`, `test_interpolat*`, `test_sfx*`, `test_audio*`, the
`affected_tests.py` list, and the ENet harness `./tools/run_m3a_local.ps1 -Peers 4 -SimLag 100
-SimLoss 0.02` (one run, 15 min deadline).

### Slice B3: MatchNet boundary (Sonnet netcode, about 30 min, review: yes)

Owned files: `net/MatchNet.gd` only.

Changes:
- Lines 78-81 `MatchGifts.*` become `GiftWirePhase.*`, as do lines 1239, 1316 and 2185.
- Line 326 `_weather_net: WeatherNet` becomes `Node`. The WeatherNet child (367-370) is created
  in `late_activate()` through LateScripts. The RPC path `/root/MatchNet/WeatherNet` is unchanged,
  and both peers activate before any session can start.
- Lines 453/2190 `CatController` become `RigidBody3D`.
- `Block` becomes `BlockBody` (740, 757, 1679, 2115-2118, 2320, 2922, 2959, 3007, 3035).
- `BlockRegistry` becomes `Node` (2113, 2317, 2919, 2956, 2988, 3032).
- Line 1298 `SpecialDef.load_all_specials()` becomes a LateScripts-loaded static call.
- Lines 2724, 2736 and 2743 use the light validators from B0.
- Lines 3007/3017 `BlockFactory.build/apply_gift_visual` go through LateScripts.

Tests: `test_match_net*`, `test_weather_net*`, `test_gift*`, `test_net*`, the
`affected_tests.py` list, and the ENet harness (one run, 15 min).

**Expected saving when B1+B2+B3 have all landed:** autoload compile 3.48 s -> about 0.99 s, and
first frame 4.90 s -> about **2.41 s** (model error about ±10 %). Partial landings save about
0 to 0.3 s.

### Slice B4: autoload closure lint (Haiku/Sonnet tooling, about 20 min, no review)

Owned files:
- `tools/lint_autoload_closure.py` (new; port the graph in section 1)
- `tools/autoload_closure_baseline.json` (new)
- `tools/full_gate.py` (one hook after `lint_single_source`)

Behaviour:
- Computes the static compile closure of the `[autoload]` scripts.
- Fails if any file in the closure is not in the baseline, or if total lines exceed the baseline.
- `--update` only lowers the baseline.
- Before B1-B3 land, it runs in `--report` mode only. After they land, record the baseline
  (about 52 files / 19k lines).

Check: `python tools/lint_autoload_closure.py` passes on the post-B main and fails when one
`var x: Block` is added to Match.gd.

### Optional slices C1/C2 (to get under 2 s; decide after re-measuring B)

- **C1, thin MatchNet** (netcode, Sonnet; split if over 10 files): MatchNet.gd keeps its public
  API, its constants and the RPC entry points that peers call by path. Handler bulk moves into
  child nodes created in `late_activate()`, following the existing WeatherNet/SnowNet/BreezeNet
  pattern. Predicted -0.26 s (to ~2.15 s).
- **C2, thin Net**: the same pattern for Net.gd (2141 lines), for example LAN/Steam/lobby
  helpers as late children. Predicted -0.20 s (to ~1.96 s).

Both change RPC node paths and need the ENet harness and review. They are not recommended unless
the post-B measurement plus GodotSteam load misses the target by a margin that matters.

## 3. Throwaway probes (slice 1, uncommitted)

- `tools/probe_autoload_mark.gd`: interleaved marker autoload, used with a temporary
  `override.cfg` `[autoload]` re-order (`Name=null` then re-add).
- `tools/probe_script_self_cost.gd/.tscn`: warm per-file recompile cost.
- `tools/probe_pump_guard.gd`: pump-guard feasibility.

Graph scripts, logs and the marker `override.cfg` are kept in the planner scratchpad. The
probes may be deleted or kept as tools; slice A reuses the `probe_pump_guard` logic.
