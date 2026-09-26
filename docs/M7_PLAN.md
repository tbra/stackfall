# M7 Plan: Art Direction & Presentation

Epic bead: `Bontago-xtq.24` (M7 art-direction proposal). Owner decisions binding this
plan: `Bontago-5h7` (2026-09-26 art-direction answers, recorded in full in
`docs/M7_ART_DIRECTION.md`), `Bontago-9yb` (reference selection), `Bontago-xtq.3/.5/.8/.12/.17/.20/.22`,
`Bontago-mv0.11/.17/.18/.21`. Spec: `docs/SPEC.md` §2.10 (blocks, amended per
Bontago-5h7 to merged-mesh + shader cell-grid + toon outline) and the M7/M8
milestone acceptance criteria in Part 4. Base checkout: `M:/Bontago` @ `d57bfda`
on `main`. No game code has landed for M7 yet; this plan is the design contract
for the seven work packages below (P1-P7).

Every package obeys `CLAUDE.md`'s tech rules unchanged: GDScript static typing
everywhere, no magic numbers (new tunables go in a `res://config` `Resource`),
pure rule logic stays in `res://core/` untouched by this milestone, all new
signals go through `Events` (or a package's own well-scoped signal if no
consumer exists yet), all new input goes through the Input Map, no new addons.

## Current-state audit (corrects stale claims in `M7_ART_DIRECTION.md`)

Grounding reads this session found several systems more built than the
art-direction doc's inventory assumed. Packages below are scoped to the actual
gap, not a rebuild:

- **`autoload/Settings.gd`** (198 lines) is a fully implemented autoload, not a
  stub: `signal graphics_preset_changed(preset: GraphicsPreset)` (line 14),
  `func current_graphics_preset() -> GraphicsPreset` (line 44),
  `func set_graphics_preset(id: StringName) -> void` (line 48, emits the
  signal). A repo-wide grep found **zero consumers** of
  `graphics_preset_changed` besides the emit site and
  `tests/unit/test_settings.gd:73`. P1's entire scope is closing that gap.
- **Territory/disk visuals** (`config/TerritoryVisuals.gd`, 296 lines,
  `shaders/territory.gdshader`, 448 lines, `game/DiscMirror.gd`) are mature and
  fully wired: outline pulse, contested shimmer, capture ring, reflection
  probe, SSR and mirror fields all already exist as live shader uniforms. M7's
  disk/territory scope is tuning values against the mockups, not new
  systems — no package below touches these files except where a hook is
  strictly required (P4's shake, P5's minimap read).
- **`game/Skybox.gd`** (507 lines) loads a six-face textured box from
  `res://assets/original/textures/<set>/`, which is third-party and **not
  shipped** in this repo (`_resolve_asset_root()`, line 282, and
  `list_available_sets()`, line 296, both degrade gracefully to empty/missing
  rather than erroring). On missing assets it falls back to the existing
  `ProceduralSkyMaterial` (`_fallback_sky_material`, `fallback_active: bool =
  true` by default — the CI/no-asset case). **Consequence: the "sunset theme"
  cannot be a texture swap.** P3 adds a new procedural `SkyThemeDef` Resource
  applied to the fallback `ProceduralSkyMaterial` path instead.
- **`core/blocks/BlockMeshBuilder.gd`** (161 lines) already emits per-face UVs
  spanning the full 0..1 range per cell (`uv_corners`, lines 136-138). P2's
  cell-grid-line shader can use a UV-edge-proximity test with **zero changes**
  to this file — it stays read-only this milestone.
- **`autoload/Sfx.gd`** (303 lines) plays exactly one music stream
  (`_play_music_stream`); there is no crossfade and only one audio asset exists
  on disk (`assets/original/audio/bontago1.mp3`, confirmed via glob — no second
  stem file). P6 is a genuine new feature and carries an explicit asset-supply
  risk (see P6 below).
- Existing test files for every UI/audio/camera surface this milestone touches
  already exist and should be extended, not created new:
  `tests/unit/test_main_menu.gd`, `test_lobby.gd`, `test_options_menu.gd`,
  `test_sfx.gd`, `test_camera_rig.gd`, `test_hud.gd`, `test_field.gd`,
  `test_skybox.gd`, `test_disc_mirror.gd`, `test_tuning_panel.gd`.

## Shared-file hotspots (flagged, serialize — do not parallelize these files)

- **`game/Field.tscn`**: P3 adds an optional `FogVolume` node; P4 adds a
  `BlockEffectsManager` node. Dispatch P4 first (smaller, additive-only child
  node), land and commit it, then dispatch P3's scene edit against the updated
  base. Do not run P3 and P4 in parallel worktrees against this file.
- **`ui/OptionsMenu.gd`**: P4 adds one camera-shake toggle control; P7 reskins
  the whole menu with a new `Theme`. Dispatch P4 first so its control exists
  before P7's layout pass wraps it; P7 must preserve the toggle's
  `%UniqueName` binding and signal handler.
- **`config/GraphicsPreset.gd`**: P1 adds `volumetric_fog_enabled: bool` and
  wires the apply path; P3 reads that field to gate `FogVolume` on Low. P1
  must land first (see dispatch order).
- No other file is owned by more than one package.

## Package split

### P1 — Graphics-preset consumer (model: Sonnet)

**Owned files:**
- `config/GraphicsPreset.gd` (add `volumetric_fog_enabled: bool = true`)
- `config/graphics_presets/high.tres`, `medium.tres`, `low.tres` (set the new
  field; `low.tres` sets it `false` per the binding decision "cloud deck via
  `FogVolume` dropped on Low")
- `game/Main.gd` (add a `_apply_graphics_preset(preset: GraphicsPreset) ->
  void` handler connected to `Settings.graphics_preset_changed`, called once
  at startup with `Settings.current_graphics_preset()`)
- `tests/unit/test_settings.gd` (extend — do not remove
  `test_graphics_preset_changed_signal_emits_the_new_preset` at line 73)
- New: `tests/unit/test_main_graphics_preset.gd`

**Interfaces added:** none new; consumes the existing
`Settings.graphics_preset_changed(preset: GraphicsPreset)` signal (line 14)
and `Settings.current_graphics_preset()` (line 44). Applies `msaa_3d` and
`shadow_atlas_size` to the active `Viewport`/`DirectionalLight3D` shadow
settings, and forwards `ssr_enabled`/`volumetric_fog_enabled` to any
`WorldEnvironment` found under the active scene (used by P3).

**Dependencies:** none (first dispatched). P3 depends on
`volumetric_fog_enabled` existing before wiring `FogVolume` visibility to it.

**Acceptance checks:**
- `godot --headless --editor --path . --quit` clean.
- `tests/unit/test_main_graphics_preset.gd`: instancing `Main`, calling
  `set_graphics_preset(&"low")`, asserting the viewport's `msaa_3d` and a
  probed `WorldEnvironment.environment.ssr_enabled` change accordingly.
- `tests/unit/test_settings.gd` unchanged tests still pass.
- No screenshot required.

**Manual owner test steps:** Options → Graphics preset → switch High/Low while
in a match; confirm shadow crispness and reflection changes visibly without
restarting.

### P2 — Block toon material + outline + cell-grid influence glow (model: Sonnet)

**Owned files:**
- `game/BlockFactory.gd` (extend `_add_shape_visual()`, line 132: add a second
  `MeshInstance3D` using the same `ArrayMesh` with `cull_mode = CULL_FRONT`
  vertex-push-out outline shader; keep the existing single-mesh-per-block rule
  from `Bontago-xtq.3`)
- `config/BlockVisualTuning.gd` (new `Resource`: `outline_width_m: float`,
  `outline_color: Color`, `toon_band_count: int`, `grid_line_width_px: float`,
  `grid_line_color: Color`, `grid_line_glow_color: Color`,
  `grid_line_glow_strength: float`)
- `config/block_visual_tuning.tres` (new default instance)
- `shaders/block_outline.gdshader` (new — inverted-hull outline pass)
- `shaders/block_cell_grid.gdshader` (new — toon diffuse bands + UV-edge
  cell-grid lines, glow driven by a per-instance shader parameter)
- `tests/bench/bench_block_material_cost.gd` (new — 300-block bench modeled on
  `tests/bench/bench_rain.gd`'s `BLOCK_COUNT=300`/`RUN_SECONDS=5.0` pattern)
- `tests/unit/test_block_factory.gd` (extend — confirm exactly 2 child
  `MeshInstance3D` nodes per built block, not more)

**Interfaces added:** `BlockFactory._add_shape_visual()` gains the outline
child; blocks expose the glow toggle via
`GeometryInstance3D.set_instance_shader_parameter(&"contributing", bool)`,
driven by `RigidBody3D.sleeping_state_changed` as the "contributing to
territory influence" proxy (# DECISION — an implementation detail, not a rule
change: a resting/settled block reads as contributing; this avoids new
territory-solver plumbing this milestone).

**Dependencies:** none on other P-packages. `core/blocks/BlockMeshBuilder.gd`
stays read-only (its existing 0..1 per-cell UVs, lines 136-138, already
support the grid-line UV-edge test).

**Acceptance checks:**
- `godot --headless --editor --path . --quit` clean.
- `tests/unit/test_block_factory.gd`: mesh-instance-count assertion above.
- `tests/bench/bench_block_material_cost.gd`: 300 blocks, headless physics
  step stays under `bench_rain.gd`'s existing `TARGET_STEP_MS` threshold
  (`1000.0/120.0`) — this is a physics-step regression proxy, not a GPU/fps
  measurement (see Performance gate).
- One off-screen screenshot (`--position 10000,10000`, `--quit-after 3`) of a
  single block showing outline + toon bands + grid lines, for owner sign-off
  against mockup 08.

**Manual owner test steps:** Start a sandbox match, drop several blocks of
different shapes/colours; confirm outline visibility at typical camera
distance and that settled blocks show the grid-line glow while an in-flight
block does not.

### P3 — Sky theme (sunset) + cloud deck (model: Sonnet)

**Owned files:**
- `config/SkyThemeDef.gd` (new `Resource`: `sky_top_color`, `sky_horizon_color`,
  `ground_bottom_color`, `ground_horizon_color`, `sun_angle_min_max: Vector2`,
  `fog_color`, `fog_density`, matching `ProceduralSkyMaterial`/
  `Environment.fog_*` fields)
- `config/sky_themes/sunset.tres` (new default instance, tuned to mockup
  references from `Bontago-9yb`)
- `game/Skybox.gd` (add `@export var theme: SkyThemeDef` and
  `func apply_theme(theme: SkyThemeDef) -> void`, called from `_ready()` when
  `fallback_active` is true — i.e. layered onto the existing
  `_fallback_sky_material` path at line ~120, not the textured-box path)
- `game/Skybox.gd` also gains a `FogVolume` child spawn gated by
  `GraphicsPreset.volumetric_fog_enabled` (from P1) — dropped entirely on Low
- `game/Field.tscn` (add the `FogVolume` node reference — **dispatch after
  P4**, see hotspots)
- `tests/unit/test_skybox.gd` (extend — theme application + fog-gating tests)

**Interfaces added:** `Skybox.apply_theme(theme: SkyThemeDef) -> void`. No new
signals — reads `Settings.current_graphics_preset()` directly (same pattern
P1 establishes).

**Dependencies:** P1 (`volumetric_fog_enabled` field must exist first); must
land after P4's `Field.tscn` edit lands (hotspot above).

**Acceptance checks:**
- `godot --headless --editor --path . --quit` clean.
- `tests/unit/test_skybox.gd`: `apply_theme()` sets expected
  `ProceduralSkyMaterial` fields; `FogVolume` node is absent/hidden when
  preset is Low, present on Medium/High.
- One off-screen screenshot of the sunset sky + fog on High preset, for owner
  sign-off against mockup reference.

**Manual owner test steps:** Load a match on High preset at dusk-facing camera
angle; confirm sunset colour grading and a subtle low cloud deck; switch to
Low preset and confirm the cloud deck disappears with no fps hitch.

**M8 follow-up (must not be built now):** dawn, stormy and night `SkyThemeDef`
instances, plus the optional distant backdrop ring, are explicitly deferred —
file as an M8 bead when this package closes.

### P4 — Effects + camera shake (model: Sonnet)

**Owned files:**
- `config/CameraShakeConfig.gd` (new `Resource`: `impact_speed_threshold`,
  `max_offset_m`, `decay_seconds`, `frequency_hz`)
- `config/camera_shake.tres` (new default instance)
- `game/CameraRig.gd` (add shake offset applied inside `_update_transform()`,
  line 388; subscribes to `Events.block_impacted(speed: float)`)
- `game/BlockEffectsManager.gd` (new — subscribes to
  `Events.block_impacted(speed)` for landing dust + impact burst particles,
  and to `Events.block_removed(block, reason)` filtering
  `reason == Events.REASON_KILL_PLANE` for an edge-fall trail+fade burst at
  the block's last position; # DECISION: the trail is a one-shot particle
  burst fired at removal time, not a continuous falling trail, since the
  block node is about to be freed — matches spec intent without new
  mid-flight tracking)
- `game/Field.tscn` (add the `BlockEffectsManager` node — **dispatch before
  P3**, see hotspots)
- `ui/OptionsMenu.gd` (add one camera-shake-enabled `CheckButton` control and
  handler, persisted via a new `Settings.camera_shake_enabled()`/
  `set_camera_shake_enabled()` pair following the existing
  `master_volume_db()` accessor pattern) — **dispatch before P7**, see
  hotspots
- `autoload/Settings.gd` (add the persisted bool above)
- `tests/unit/test_camera_shake.gd` (new)
- `tests/unit/test_block_effects.gd` (new)

**Interfaces added:** `Settings.camera_shake_enabled() -> bool`,
`Settings.set_camera_shake_enabled(enabled: bool) -> void`. No new
Events-bus signals — reuses `block_impacted` and `block_removed` verbatim.

**Dependencies:** none blocking; must land in `Field.tscn` before P3 (hotspot)
and in `OptionsMenu.gd` before P7 (hotspot).

**Acceptance checks:**
- `godot --headless --editor --path . --quit` clean.
- `tests/unit/test_camera_shake.gd`: synthetic `Events.block_impacted.emit(20.0)`
  produces a nonzero, decaying offset read from `CameraRig`; shake stays zero
  when `Settings.camera_shake_enabled()` is false.
- `tests/unit/test_block_effects.gd`: synthetic `Events.block_removed.emit(block,
  Events.REASON_KILL_PLANE)` spawns exactly one particle-effect node under
  `BlockEffectsManager`; a non-kill-plane reason spawns none.
- No screenshot required (particle visuals are covered by the P2 screenshot's
  general block-scene sign-off; shake is not screenshot-verifiable).

**Manual owner test steps:** Drop a block from height; confirm landing dust
and a brief camera shake proportional to impact speed. Push a block off the
disk edge; confirm a fade/trail burst as it's removed. Toggle "Camera shake"
off in Options and confirm shake stops while dust/impact particles remain.

### P5 — HUD minimap + reskin (model: Sonnet)

**Owned files:**
- `ui/HUD.gd` (add `@onready` `SubViewport`/`TextureRect` minimap nodes; a
  `_update_minimap() -> void` called from the existing
  `_on_territory_share_changed` handler, no new signal needed)
- `ui/HUD.tscn` (add the `SubViewport` + `TextureRect` display node; apply the
  reskinned panel styling from the mockups)
- `ui/Minimap.gd` (new — owns a top-down `Camera3D` inside the `SubViewport`,
  positioned from `MapDef` radius, reused from the field's own `MapDef`
  reference already passed into `CameraRig`)
- `config/HUDVisualTuning.gd` (new `Resource`: `minimap_zoom_margin_m`,
  `minimap_refresh_hz`, HUD panel colours if not covered by P7's `Theme`)
- `config/hud_visual_tuning.tres`
- `tests/unit/test_hud.gd` (extend — do not remove existing
  `_on_goal_capture_progress` coverage at HUD.gd line 360)

**Interfaces added:** none new on the Events bus — reuses
`territory_share_changed`. `Minimap.gd` exposes
`func set_map_def(map_def: MapDef) -> void`.

**Dependencies:** none blocking other packages. Reads `game/Field.tscn`'s
existing field root but does not modify it (its `SubViewport` lives entirely
under `ui/HUD.tscn`).

**Acceptance checks:**
- `godot --headless --editor --path . --quit` clean.
- `tests/unit/test_hud.gd`: minimap `SubViewport` exists and its `Camera3D`
  updates position when `set_map_def()` is called with a different `MapDef`
  radius.
- One off-screen screenshot of the in-match HUD with minimap populated, for
  owner sign-off against the HUD portion of the mockups.

**Manual owner test steps:** Start a match, confirm the minimap shows live
territory colouring and player positions, matches the main view, and doesn't
drop frame rate noticeably.

### P6 — Adaptive music (two-stem crossfade) (model: Sonnet)

**Owned files:**
- `config/AudioConfig.gd` (add `music_stem_calm_file: String`,
  `music_stem_tense_file: String`, `music_crossfade_seconds: float`,
  `music_tense_progress_threshold: float`)
- `autoload/Sfx.gd` (add a second `AudioStreamPlayer` for the tense stem; a
  `_on_goal_capture_progress(team_id: int, progress: float) -> void` handler
  — new to `Sfx.gd` specifically, does not touch `ui/HUD.gd`'s own handler of
  the same signal name at line 360 — crossfades stem volumes via `Tween`
  toward `music_tense_progress_threshold`)
- `tests/unit/test_sfx.gd` (extend)

**Interfaces added:** none new — subscribes to the existing
`Events.goal_capture_progress(team_id, progress)` signal already consumed by
`ui/HUD.gd`.

**Dependencies:** none.

**Risk (flag, do not block dispatch on it):** only one music asset exists on
disk today (`assets/original/audio/bontago1.mp3`); no second "tense" stem
file is shipped. # DECISION: `Sfx.gd` must degrade gracefully (skip the
crossfade, stay on the single stream) when `music_stem_tense_file` resolves to
a missing file, mirroring `Skybox.gd`'s `fallback_active` pattern — this keeps
`--editor --quit` and the test suite clean without a second real asset. File
an M8 (or immediate) bead for the owner to supply/approve a real tense stem
if desired.

**Acceptance checks:**
- `godot --headless --editor --path . --quit` clean.
- `tests/unit/test_sfx.gd`: synthetic `Events.goal_capture_progress.emit(0,
  0.9)` raises the tense stem's target volume above the calm stem's; missing
  tense-stem file leaves single-stream playback working (no error).
- No screenshot (audio only).

**Manual owner test steps:** Approach a goal capture threshold in a match;
confirm the music shifts noticeably in intensity, then settles back down if
the capture is contested away from the threshold.

### P7 — Main menu / lobby reskin (model: Sonnet, needs a screenshot approval gate)

**Owned files:**
- `ui/theme/stackfall_theme.tres` (new Godot `Theme` resource: coral primary,
  `StyleBoxFlat` panels per mockup 10/11, dark gamepad-focus outline,
  Godot default font per binding decision)
- `ui/MainMenu.tscn` (relayout per mockup 10; keep every existing node the
  script references — `MainMenu.gd`'s full onready set: name edit, host/
  sandbox/tutorial/options/quit buttons, LAN game list, direct IP join, Steam
  lobby section)
- `ui/Lobby.tscn` (relayout per mockup 11; keep every `%UniqueName` binding
  `Lobby.gd` references — map/players/AI/team mode/timers/gravity/goal flags/
  gifts/specials/tilt/hole mode/sudden death/turn-based/specials checklist/
  player list/ready/start/invite)
- `ui/MainMenu.gd` (add diorama background instancing only — no handler
  changes; `sandbox_requested`/`tutorial_requested` signals and
  `parse_address()` stay untouched)
- `ui/Lobby.gd` (add diorama background instancing only — no handler changes;
  `start_requested(config: MatchConfig)` stays untouched)
- `ui/MenuDiorama.gd` (new — builds a small `SubViewport` background scene
  reusing `game/Field.tscn`/block/beacon scenes, slowly orbits a camera around
  a static decorative arrangement; must not run match logic or physics beyond
  what's needed for a settled decorative scene)
- `ui/OptionsMenu.gd` (visual restyle only — apply `stackfall_theme.tres`;
  must preserve P4's camera-shake toggle control and handler verbatim)
- `tests/unit/test_main_menu.gd`, `tests/unit/test_lobby.gd`,
  `tests/unit/test_options_menu.gd` (extend — assert every existing signal/
  handler still fires under the new scene layout; do not delete any existing
  assertion)

**Interfaces added:** none — this package is explicitly scoped as a visual
skin over the existing flows per the binding decision "keep existing flows/
actions."

**Dependencies:** must land after P4's `OptionsMenu.gd` edit (hotspot above).
Independent of P1/P2/P3/P5/P6 otherwise.

**Acceptance checks:**
- `godot --headless --editor --path . --quit` clean.
- `tests/unit/test_main_menu.gd`, `test_lobby.gd`, `test_options_menu.gd`: all
  existing assertions plus new ones confirming every button/handler pair from
  the current implementation still exists and fires (host, sandbox, tutorial,
  options, quit, LAN list, direct IP join, Steam lobby; every Lobby control
  listed above; the P4 shake toggle).
- Exactly one off-screen screenshot (`--position 10000,10000`,
  `--quit-after 3`) of the reskinned main menu with diorama background, held
  for **explicit owner approval before merge** per the binding decision ("one
  off-screen screenshot for owner approval before merge").

**Manual owner test steps:** Launch the game, confirm the main menu matches
mockup 10 (coral primary, diorama background, readable at 1440p), navigate
into the lobby and confirm every option control from the current build is
present and functional, tab through controls with a gamepad and confirm the
dark focus outline is visible.

### P8 — Procedural home beacons + neutral goal beacon (model: Sonnet)

Added by the orchestrator (owner decision Bontago-5h7 Q6): the pennant flags
are replaced by procedural beacons — a socket, a luminous ring and a faceted
crystal in the owner colour (mockup 08); the goal flag gets a neutral variant
and keeps its capture ring.

**Owned files:**
- `game/HomeFlag.gd`, `game/HomeFlag.tscn` (replace the pole+banner build
  with socket + ring + crystal built from primitives/ArrayMesh in code; keep
  `set_slot()`, `slot_id()`, `color()`, `banner_scale()` and `visuals`
  verbatim so `Field`/`Match` callers and `test_flags.gd` keep working)
- `game/GoalFlag.gd`, `game/GoalFlag.tscn` (neutral beacon body; keep
  `set_capture()`, `capture_team()`, `capture_progress()`, `ring_visible()`,
  `ring_mesh()` and the `_build_arc()` capture ring verbatim)
- `config/BeaconVisualTuning.gd` (new `Resource`: socket radius/height, ring
  radius/thickness/emission strength, crystal height/facets, neutral colour)
- `config/beacon_visual_tuning.tres`
- `tests/unit/test_flags.gd` (extend — node/child count and colour
  application; do not delete existing assertions)

**Interfaces added:** none; public API of both scripts unchanged.

**Dependencies:** none. P7's diorama reuses the beacon scenes, so dispatch P7
after P8 lands (soft ordering; P7 already waits on P4).

**Acceptance checks:**
- `godot --headless --editor --path . --quit` clean.
- `tests/unit/test_flags.gd` passes with the new assertions.
- One off-screen screenshot (`--position 10000,10000`, `--quit-after 3`) of a
  home beacon and the goal beacon for owner sign-off against mockup 08.

**Manual owner test steps:** start a sandbox match; each home shows a beacon in
the slot colour, the goal shows the neutral beacon, and the capture ring still
fills when a team holds the goal.

## Dispatch order and parallelism

1. **P1** alone first (`Settings`/`GraphicsPreset` consumer — nothing else
   depends on scene edits yet).
2. **P2**, **P4**, **P5**, **P6**, **P8** in parallel worktrees once P1 lands (P2 only
   needs `BlockFactory.gd`/new files; P4 only needs `Events`/`CameraRig.gd`/
   new files; P5 only needs `HUD.gd`/new files; P6 only needs `Sfx.gd`/
   `AudioConfig.gd`). None of these four touch each other's owned files.
3. **P3** after P1 (needs `volumetric_fog_enabled`) and after **P4** commits
   its `Field.tscn` change (hotspot serialization).
4. **P7** after **P4** commits its `OptionsMenu.gd` change (hotspot
   serialization) and after **P8** (diorama reuses the beacon scenes). P7 can run in parallel with P3 once P4 has landed, since
   they touch disjoint files.
5. First dispatchable set today: **P1** solo, then **{P2, P4, P5, P6, P8}** in
   parallel, then **{P3, P7}** in parallel once P4 is integrated.

## Performance gate

Headless-measurable now (part of each package's acceptance checks above):
- `godot --headless --editor --path . --quit` stays clean (no new errors or
  warnings) for every package.
- `tests/bench/bench_block_material_cost.gd` (P2): 300-block physics-step
  regression proxy against `bench_rain.gd`'s existing `TARGET_STEP_MS`
  threshold — this bounds physics/script overhead from the new outline mesh
  and per-instance shader parameter, not GPU fill cost.
- Node/child count assertions in each package's unit tests bound draw-call
  growth indirectly (e.g. P2's "exactly 2 `MeshInstance3D` per block" test).

Only verifiable by the owner in a windowed run (not headless-measurable):
- Actual frames-per-second at 1440p on the High preset with ~300 placed
  blocks, the sunset sky + fog, minimap, and full menu diorama all active
  simultaneously, against the spec's 144 fps accept target. Manual test step:
  after P2/P3/P5 are integrated, run a sandbox match to ~300 blocks on High
  preset at 1440p and read the engine's built-in FPS counter (Debug →
  Monitor, or a temporary `Engine.get_frames_per_second()` print) over a few
  seconds of normal play.
- Subjective toon-shading, outline, and cell-grid-glow readability at typical
  camera distance (screenshots from P2/P3/P5/P7 support this but are not a
  substitute for the owner's own windowed look).

## M8 follow-ups (file as beads when this milestone's packages close)

- Dawn, stormy, and night `SkyThemeDef` instances (P3 ships sunset only).
- Optional distant backdrop ring around the sky (P3 explicitly drops this to
  low priority / deferred).
- A real "tense" music stem asset and owner approval of the crossfade feel
  (P6 ships with graceful single-stream degradation if no asset is supplied).
- Drive the block cell-grid glow from real territory contribution
  (`InfluenceCircle.body_id` of kept circles, replicated to clients) instead
  of P2's settled-block proxy.
- Any HUD/menu accessibility follow-up raised during the owner's P7 screenshot
  approval (colour-blind palette check, further gamepad-focus contrast tuning)
  if not resolved inline during P7.
