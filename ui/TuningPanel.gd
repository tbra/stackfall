class_name TuningPanel
extends CanvasLayer
## In-game tuning panel (Bontago-mv0.18, owner request: "add a settings menu
## with sliders so I can play around and adjust the camera in-game? same for
## physics properties like gravity, damping, bouncing, etc.").
##
## Five tabs, each built by reflection over a live tuning Resource's @export
## fields (Resource.get_property_list(), filtered to the four types a control
## exists for below) rather than one hand-authored row per field: CLAUDE.md's
## "no magic numbers... every tunable in a Resource" only pays off in
## practice if a config Resource's whole surface is reachable without a code
## change per field.
##
##   Camera    -> CameraRig.tuning (CameraTuning)
##   Controls  -> PlayerController.ghost_tuning (GhostTuning)
##   Physics   -> PlayerController.tuning (PhysicsTuning)
##   Territory -> Field.territory_tuning (TerritoryTuning) + Field.visuals
##                (TerritoryVisuals). Bontago-1pi.1: the Skybox dropdown row
##                (Bontago-xtq.22, config/SkyboxConfig.gd's `default_set`/
##                `enabled`) that used to live here moved to the Sky tab
##                below (owner playtest: "the skybox setting in territory
##                should probably move over to sky settings") -- see
##                _build_skybox_row()'s own doc.
##   Feed      -> config/block_feed.tres (BlockFeedConfig), preloaded
##                directly -- autoload/Match.gd is the only script holding a
##                live reference to this one and it's a different package's
##                file, but preloading the same path still resolves to the
##                identical cached Resource instance Match reads (Godot caches
##                a Resource by path within one process), so no line there is
##                actually required for this field to be editable here.
##
## Bontago-xtq.36 (M7 art direction): five more tabs, over the M7 config
## Resources, all preloaded the same "identical cached path" way Feed's own
## paragraph above documents -- none of these five needs a line anywhere else
## in the project either. MenuVisualTuning is not merged yet and has no tab.
##
##   Blocks FX -> game/BlockFactory.gd's VISUAL_TUNING const (BlockVisualTuning)
##                + game/BlockEffectsManager.gd's config (BlockEffectsConfig)
##   Beacons   -> game/HomeFlag.gd's beacon_visuals (BeaconVisualTuning)
##   Camera FX -> game/CameraRig.gd's shake_config (CameraShakeConfig)
##   HUD       -> ui/HUD.gd's hud_visual_tuning + ui/Minimap.gd's tuning
##                (both preload config/hud_visual_tuning.tres -- HUDVisualTuning)
##   Sky       -> game/Skybox.gd's theme (SkyThemeDef), config/sky_themes/
##                sunset.tres -- the only shipped theme on this branch --
##                plus the Skybox dropdown row (Bontago-1pi.1, moved from
##                Territory above)
##
## Every control writes straight onto the *live* resource instance the rest
## of the game already reads -- the same object every other
## `@export var tuning: ... = preload(...)` field across the project resolves
## to. There is no duplicate/copy step, so a change to a field something
## reads every frame (CameraRig's orbit speed, GhostPreview's tint colors,
## TerritorySolver's hash_cell_size, TerritoryOverlay's per-upload uniforms in
## set_circles()) is felt on the very next read. A few fields are only ever
## read once, at construction time, and need an explicit push:
##
##   - PhysicsTuning: apply_physics_live() re-applies damping/material/gravity
##     onto every Block already standing (Block.apply_physics_tuning(), via
##     the "tuning_blocks" group every Block joins in _ready()).
##     BlockFactory.build() already reads the same tuning for brand new
##     spawns, so nothing extra is needed there.
##   - TerritoryVisuals: refresh_territory_visuals_live() calls
##     TerritoryOverlay.refresh_visual_uniforms() so a shader uniform that
##     only configure() used to set (disk color, edge softness, outline,
##     contested shimmer, hole rim) updates immediately instead of waiting on
##     nothing (nothing else ever re-sends those particular uniforms).
##     refresh_visual_uniforms() also rebuilds the disk's CylinderMesh
##     (game/TerritoryOverlay.gd's own rebuild_disk_mesh()) whenever
##     disk_mesh_segments itself changed, so that field is live too now.
##     Bontago-xtq.12 step 2: the same function also calls
##     Skybox.refresh_from_visuals() on every rig in Skybox.TUNING_GROUP, so
##     the reflection probe/SSR fields (also on TerritoryVisuals) update live
##     too instead of only ever applying once at boot.
##   - CameraTuning: apply_camera_tuning_live() calls
##     CameraRig.apply_follow_tuning() on every rig in CameraRig.TUNING_GROUP,
##     re-snapshotting follow_distance/follow_pitch_deg (clamped, as _ready()
##     does) without disturbing a manual orbit/zoom the player already did.
##   - SkyboxConfig: the Territory tab's Skybox dropdown calls
##     apply_skybox_set(), which writes default_set/enabled onto the live
##     skybox_config and then calls Skybox.apply_set() on every Skybox in
##     Skybox.TUNING_GROUP so the loaded six-face set (and the Environment's
##     Sky material every reflection/ambient read samples -- see
##     game/Skybox.gd's own class doc) actually reloads, rather than only
##     changing a Resource field nothing re-reads on its own.
##   - SkyThemeDef: apply_sky_theme_live() calls Skybox.apply_theme() on every
##     rig in Skybox.TUNING_GROUP (see that function's own doc for a known
##     partial-live gap around the FogVolume child). Bontago-59o.18 (U1): a rig
##     running the day/night cycle gets refresh_cycle_sources() instead, so an
##     edit never swaps the live cycle for the static theme material.
##   - Cycle sky (Bontago-59o.18, U1): the Sky tab's Theme dropdown leads with a
##     "cycle" entry (Skybox.start_cycle(), persisted as
##     skybox_config.theme_name = "cycle") and a Time-of-day row (Running /
##     Sunset / Dawn / Night / Custom + a 0..1 phase slider) locks it through
##     Skybox.set_locked_phase(). Local dev tuning: nothing is replicated.
##
## BlockVisualTuning, BlockEffectsConfig, BeaconVisualTuning, CameraShakeConfig
## and HUDVisualTuning need no such hook: CameraShakeConfig/BlockEffectsConfig
## are already read live per-frame/per-event by their consumer, and
## BlockVisualTuning/BeaconVisualTuning/HUDVisualTuning are baked once at
## construction time (a block's toon material, a beacon's geometry, a HUD
## panel's StyleBoxFlat) with no existing re-push seam on that consumer -- an
## edit still takes effect for anything built from here on (see
## _on_field_changed()'s own comment on this). DECISION (Bontago-xtq.36): these
## five resources are likewise not added to reset_all()/save_overrides()/
## build_copy_text()/apply_saved_overrides() below -- the brief asked only for
## the tabs, the (for Sky) live-apply hook, and the three named tests; wiring
## Reset/Save/Copy for them is a reasonable small follow-up, not done here.
##
## Toggled by the tuning_panel_toggle Input Map action (F4; gamepad
## pause_menu[Start] + X -- see tools/bootstrap_project.gd's DECISION on that
## chord). While open: the mouse is released and gameplay input is
## suppressed (PlayerController.input_enabled), the same idea as
## ui/NetDebugOverlay.gd's F3 overlay, but this one also has to stop the game
## from reacting to clicks and drags meant for its own controls.
##
## Availability (owner: adjust the camera/physics "in-game"): open offline
## (sandbox, hot-seat) and by the host in a networked match; a client only
## ever sees Camera/Controls -- Net.is_host() is already true offline
## (autoload/Net.gd's own doc comment), so this is the one predicate to gate
## on. Editing Physics/Territory/Feed on a client would be inert anyway
## (CLAUDE.md: "only the host runs physics"; a client's bodies are frozen and
## moved by net/SnapshotSync.gd), not just hidden for tidiness.

const SAVE_PATH: String = "user://tuning_overrides.cfg"


## The file actually read/written: SAVE_PATH, or a per-PID file in a GUT run so
## tests never touch the owner's real F4 overrides (Bontago-1pi.21).
static func save_path() -> String:
	return UserPaths.resolve(SAVE_PATH)

const VALUE_WIDTH: float = 110.0

## Bontago-xtq.13: the selected-tab memory shares SAVE_PATH with every tuning
## resource's own override section (one ConfigFile, one section per concern)
## rather than a second settings file.
const SELECTED_TAB_SECTION: String = "TuningPanel"
const SELECTED_TAB_KEY: String = "selected_tab"

## DECISION (ui/TuningPanel.gd, Bontago-mv0.21): row name/description column
## widened from the bare label's old 260px width so a whole one-sentence
## description can sit under the field name without wrapping to more than a
## couple of lines at 1080p.
const NAME_COLUMN_WIDTH: float = 380.0
## DECISION (Bontago-hfa.9, P7 token swap): description and default-value labels use the
## theme's CaptionLabel variation (dust ink at caption size, 13 px) instead of a private colour
## and a smaller font, so the sentence reads as a sub-label and the name stays the primary line.
const CAPTION_THEME_VARIATION: StringName = &"CaptionLabel"
const MODIFIED_MARKER: String = "• "

## get_property_list() usage flags an @export'd script variable carries (see
## this file's own probe in the implementation notes): STORAGE so it's
## serialized, EDITOR so it's inspector-visible, SCRIPT_VARIABLE so it's a
## script-declared field rather than a base Resource/Object property like
## resource_path. Anything missing one of these three is skipped -- an
## un-exported script var, a resource_* built-in, or the `script` property
## itself.
const EXPORT_USAGE_MASK: int = PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE

## Tabs whose content is hidden from a client (see class doc "Availability").
## Indices match the order rebuild() adds tabs in -- rebuild() adds every
## client-visible tab first (Camera, Controls, then the M7 visual tabs: Blocks
## FX, Beacons, Camera FX, HUD, Sky) so this one cutoff still holds; Physics/
## Territory/Feed (host-only: they tune the physics/territory simulation
## itself, not just how it looks) always come last.
const CLIENT_HIDDEN_TAB_FIRST: int = 6

## Bontago-xtq.17 (owner playtest 2026-09-23: "heavier and more bouncy, but a
## dropped block shouldn't just bounce straight up again" -- research +
## A/B presets): the Physics tab's preset dropdown copies one of these
## PhysicsTuning resources' every exported field onto the live physics_tuning
## instance (apply_physics_preset() below). "heavy_bouncy" is byte-identical to
## config/physics_tuning.tres's own defaults (owner 2026-09-30: Heavy &
## Bouncy is the shipped default), so picking it is a no-op; "current" keeps
## the OLD default numbers, labelled "Previous default"; "heavy_bouncy"/"heavy_damped" both raise
## cube_mass and gravity_multiplier
## for a heavier fall and set rebound_damping below 1 so a flat drop doesn't
## bounce straight back up, while still giving lateral/tumbling liveliness
## from block_bounce (see config/PhysicsTuning.gd's rebound_damping DECISION
## and game/Block._damp_rebound()) -- "_bouncy" leans on a higher block_bounce
## for that liveliness, "_damped" leans on higher linear/angular damping so
## the same heavier fall settles quieter. See config/physics_presets/*.tres
## for the exact numbers.
const PHYSICS_PRESETS: Array[Dictionary] = [
	{"id": "current", "label": "Previous default", "path": "res://config/physics_presets/current.tres"},
	{"id": "heavy_bouncy", "label": "Heavy & Bouncy", "path": "res://config/physics_presets/heavy_bouncy.tres"},
	{"id": "heavy_damped", "label": "Heavy & Damped", "path": "res://config/physics_presets/heavy_damped.tres"},
	# Source material/damping defaults; Jolt solver and sleep remain unchanged.
	{"id": "tokamak_defaults", "label": "Tokamak defaults (Jolt)", "path": "res://config/physics_presets/tokamak_defaults.tres"},
	{"id": "original_feel", "label": "Original feel (experimental)", "path": "res://config/physics_presets/original_feel.tres"},
]

## Bontago-59o.18 (U1): the Theme dropdown's leading entry. It is not a file under
## config/sky_themes/; it is persisted on skybox_config.theme_name and handled by
## game/Skybox.gd (start_cycle()). The cycle's day half is the sunset.tres
## duplicate (Skybox.configure_match_sky), so the Sky tab's sliders edit that one.
const CYCLE_THEME_ID: String = "cycle"
## Time-of-day row choices, index-parallel to TIME_OF_DAY_LABELS. The three
## concrete ids are SkyThemeDef.locked_phase_for() keys (MatchConfig.SKY_THEME_IDS).
const TIME_RUNNING: String = "running"
const TIME_CUSTOM: String = "custom"
const TIME_OF_DAY_CHOICES: PackedStringArray = ["running", "sunset", "dawn", "night", "custom"]
const TIME_OF_DAY_LABELS: PackedStringArray = ["Running", "Sunset", "Dawn", "Night", "Custom"]
## A live locked phase within this of a preset's phase reads as that preset.
const TIME_OF_DAY_PHASE_EPSILON: float = 0.001
const TIME_OF_DAY_SLIDER_STEP: float = 0.005
## Custom slider seed when no live cycle can report its phase (0.25 = noon).
const TIME_OF_DAY_DEFAULT_CUSTOM_PHASE: float = 0.25
const TIME_OF_DAY_SLIDER_MIN_WIDTH: float = 160.0
const TIME_OF_DAY_VALUE_FORMAT: String = "%.3f"

## Bontago-1pi.113 (panel redo): rows sit in foldable sections (hints.sections);
## a section is open by default only when it is the first one on its tab, and
## the open/closed choice survives rebuild() (see _fold_open).
const SECTION_OPEN_MARK: String = "▾ "
const SECTION_CLOSED_MARK: String = "▸ "
## Gap between the columns of a row: name | control | value | default.
const ROW_SEPARATION: int = 12
## Every row's control column has at least this width (it takes the spare row width, identically on every row) (slider, spinbox, toggle, swatch,
## dropdown), so the value and default columns line up on every tab.
const CONTROL_COLUMN_WIDTH: float = 300.0
const CONTROL_MIN_WIDTH: float = 240.0
const FIXED_CONTROL_WIDTH: float = 140.0
const SWATCH_HEIGHT: float = 30.0
const TOGGLE_WIDTH: float = 90.0
const SPIN_WIDTH: float = 130.0
const DEFAULT_COLUMN_WIDTH: float = 200.0
## A float's displayed decimals come from its slider span so a 0..1 field and a
## 0..360 field both show about this many significant digits (see _decimals_for).
const SPAN_SIGNIFICANT_DIGITS: int = 3
const MAX_DISPLAY_DECIMALS: int = 5
const DEFAULT_PREFIX: String = "default "
## Written straight after the number ("45.0°"), unlike every other unit.
const DEGREE_UNIT: String = "°"
const BOOL_ON_TEXT: String = "On"
const BOOL_OFF_TEXT: String = "Off"
const SCENE_SECTION_TITLE: String = "Sky and weather"
const PRESET_SECTION_TITLE: String = "Presets"
const HAND_BUILT_CLASS: String = "Panel"

@export var hints: TuningPanelHints = preload("res://config/tuning_panel_hints.tres")

var camera_tuning: CameraTuning = preload("res://config/camera_tuning.tres")
var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
var physics_tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var territory_visuals: TerritoryVisuals = preload("res://config/territory_visuals.tres")
var block_feed_config: BlockFeedConfig = preload("res://config/block_feed.tres")

## Bontago-xtq.22: the same preloaded singleton game/Skybox.gd's own `config`
## field defaults to (Main.tscn's Skybox node never overrides it -- see
## config/SkyboxConfig.gd's own DECISION on why one field/one path is enough
## to keep this panel and every live Skybox reading/writing the identical
## Resource instance, the same BlockFeedConfig idiom this file's own class doc
## documents right above).
var skybox_config: SkyboxConfig = preload("res://config/skybox_config.tres")

## Bontago-xtq.36: M7's art-direction tunables, added to the same preload
## roster above -- each preloads the identical path its own consumer already
## preloads/exports (BlockFactory.gd's VISUAL_TUNING const, BlockEffectsManager.
## config, HomeFlag.beacon_visuals, CameraRig.shake_config, Skybox.theme), so
## Godot's per-path Resource cache (see this file's class doc, BlockFeedConfig
## paragraph) makes every field here the same live object those scripts read.
var block_visual_tuning: BlockVisualTuning = preload("res://config/block_visual_tuning.tres")
var block_effects_config: BlockEffectsConfig = preload("res://config/block_effects.tres")
var beacon_visual_tuning: BeaconVisualTuning = preload("res://config/beacon_visual_tuning.tres")
var camera_shake_config: CameraShakeConfig = preload("res://config/camera_shake.tres")
var hud_visual_tuning: HUDVisualTuning = preload("res://config/hud_visual_tuning.tres")
## Bontago-1pi.18.1: opt-in QoL experiments (host snapshots them at match start).
var qol_experiments: QolExperiments = preload("res://config/qol_experiments.tres")
var sky_theme: SkyThemeDef = preload("res://config/sky_themes/sunset.tres")

## DECISION (ui/TuningPanel.gd): same `Variant` test seam as
## ui/NetDebugOverlay.gd's net_provider -- GUT cannot double the plain Net
## autoload (addons/gut/test.gd's double_singleton only recognizes engine
## singletons).
var net_provider: Variant = null
## Test seam: the MatchWeather the Weather row drives (null = the Match autoload's).
var weather_provider: Variant = null

var _controller: PlayerController = null
var _camera_rig: CameraRig = null
var _field: Field = null

## One entry per built control: {"resource": Resource, "property": String,
## "control": Control}. Lets tests (and _on_field_changed()) find the control
## for a given resource field without walking the tree.
var _rows: Array[Dictionary] = []

## One {"resource", "title"} per section built (Bontago-1pi.112/113).
var _group_titles: Array[Dictionary] = []

## Open/closed state of each foldable section ("Class/Title" -> bool), kept
## across rebuild() and panel re-opens for the whole session.
static var _fold_open: Dictionary = {}

var _tab_container: TabContainer = null
var _status_label: Label = null

## Bontago-xtq.13 (owner playtest 2026-09-23, "F4 should remember which tab
## was active when reopened"): the last tab index the owner picked, restored
## onto _tab_container every rebuild() (rebuild() replaces every tab page,
## which would otherwise silently reset TabContainer.current_tab to 0) and
## persisted into SAVE_PATH's own ConfigFile so it survives a full app
## restart too, not just a close/reopen in the same session.
var _selected_tab_index: int = 0

## Bontago-xtq.13: true only while rebuild() is (re)populating _tab_container.
## Adding the *first* child tab to an emptied TabContainer auto-selects it and
## fires tab_changed(0) synchronously (unlike a plain property assignment on
## an already-populated container) -- without this guard, that spurious event
## reached _on_tab_changed() and clobbered _selected_tab_index back to 0
## before rebuild()'s own explicit restore below even ran.
var _rebuilding_tabs: bool = false

## Bontago-59o.18 (U1): the Sky tab's Time-of-day row state (TIME_OF_DAY_CHOICES
## entry, and the phase the Custom slider holds). Session-local: only
## skybox_config.theme_name = "cycle" persists.
var _time_of_day_choice: String = TIME_RUNNING
var _time_of_day_custom_phase: float = TIME_OF_DAY_DEFAULT_CUSTOM_PHASE


func _ready() -> void:
	visible = false
	net_provider = Net
	# DECISION (Bontago-1pi.11.5): the ~2900-node tab UI is no longer built
	# here. rebuild() builds it on first open (or on an explicit call, which
	# tests use) and _free_ui() frees it again on close, so a hidden panel
	# costs no nodes. Saved overrides apply via the static
	# apply_saved_overrides() at boot and never needed this UI.
	# Bontago-adt: the Sky tab's sliders edit whichever theme is active.
	var boot_theme: SkyThemeDef = Skybox.load_theme(skybox_config.theme_name)
	if boot_theme != null:
		sky_theme = boot_theme
	_selected_tab_index = _load_selected_tab_index()


# --- Wiring (game/Main.gd / HotSeat.gd / Sandbox.gd) -------------------------

## Called once by game/HotSeat.gd/Sandbox.gd, whose $PlayerController this
## panel's Controls/Physics tabs should read from (both fields already
## default to the same preloaded singletons a bare test constructs this panel
## with, so this only matters if a specific instance is ever wired to
## something else).
func set_controller(controller: PlayerController) -> void:
	_controller = controller
	if controller != null:
		ghost_tuning = controller.ghost_tuning
		physics_tuning = controller.tuning
	_rebuild_if_built()


## Called once by game/Main.gd (through HotSeat.gd/Sandbox.gd's own
## set_camera_rig()), after Main builds the shared CameraRig -- the same
## hand-off HotSeat.gd's own set_camera_rig() already documents.
func set_camera_rig(rig: CameraRig) -> void:
	_camera_rig = rig
	if rig != null:
		camera_tuning = rig.tuning
	_rebuild_if_built()


## Called once by game/Main.gd/Sandbox.gd with the shared Field, for the
## Territory tab and refresh_territory_visuals_live()'s overlay push.
func set_field(field: Field) -> void:
	_field = field
	if field != null:
		territory_tuning = field.territory_tuning
		territory_visuals = field.visuals
	_rebuild_if_built()


# --- Toggle (F4 / gamepad Start+X) -------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"tuning_panel_toggle"):
		return
	# Bontago-470.8: the F4 panel is debug-only (game/DebugMode.gd).
	if not DebugMode.is_enabled():
		return
	# See tools/bootstrap_project.gd's DECISION: the gamepad half of this
	# action is bound to X alone (every other button is already spoken for),
	# which is also hover_lower, so a joypad press only counts as the toggle
	# while pause_menu (Start) is also held -- the same two-action-chord
	# technique ui/NetDebugOverlay.gd's Back+Y toggle already established. A
	# keyboard press (F4) needs no modifier.
	if event is InputEventJoypadButton and not Input.is_action_pressed(&"pause_menu"):
		return
	_toggle_panel()
	get_viewport().set_input_as_handled()


func _toggle_panel() -> void:
	visible = not visible
	if not visible:
		_free_ui()
	if _controller != null:
		_controller.input_enabled = not visible
	AgentProbe.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED)
	if visible:
		# Reflects anything another system changed the live resources to
		# since this panel last opened (a match restart's fresh MatchConfig,
		# another peer... in practice nothing else writes these fields today,
		# but rebuilding is cheap and this is the one moment it's worth it).
		# Bontago-xtq.13: also restores _selected_tab_index (below), so a
		# close/reopen in the same session lands back on whichever tab was
		# open, not tab 0.
		rebuild()


# --- Tab memory (F4 remembers the last active tab, Bontago-xtq.13) ----------

## TabContainer.tab_changed fires both for a real click and for rebuild()'s
## own programmatic current_tab restore -- either way this is "the tab the
## owner should come back to", so it is also persisted immediately rather
## than only on close, surviving a crash/quit between now and the next save.
func _on_tab_changed(index: int) -> void:
	if _rebuilding_tabs:
		return
	_selected_tab_index = index


## Bontago-1pi.22: TabContainer.tab_clicked fires only for a user click
## on the tab bar, never for programmatic current_tab sets or
## child add/remove, so this is the only place the tab index is persisted.
func _on_tab_selected(index: int) -> void:
	if _rebuilding_tabs:
		return
	_selected_tab_index = index
	_save_selected_tab_index()


## Loads just the persisted tab index from SAVE_PATH, if any -- called once
## from _ready(), before the first rebuild() so the very first open already
## restores it. Returns 0 (the sane default) with no saved file, an unreadable
## one, or no matching key, exactly like _apply_saved_section()'s own
## stale/missing-key tolerance below.
func _load_selected_tab_index() -> int:
	var config: ConfigFile = ConfigFile.new()
	if config.load(save_path()) != OK:
		return 0
	if not config.has_section_key(SELECTED_TAB_SECTION, SELECTED_TAB_KEY):
		return 0
	return int(config.get_value(SELECTED_TAB_SECTION, SELECTED_TAB_KEY, 0))


## Writes just the selected-tab section into SAVE_PATH -- loads whatever is
## already on disk first (rather than a fresh ConfigFile, which save_overrides()
## below now also does) so this never clobbers the tuning-override sections a
## "Save override" click wrote, and vice versa: both share one file, per
## sections, the same way save_overrides() already groups every tuning
## resource under its own section.
func _save_selected_tab_index() -> void:
	if not UserPaths.persistence_allowed():
		return
	var config: ConfigFile = ConfigFile.new()
	config.load(save_path())
	config.set_value(SELECTED_TAB_SECTION, SELECTED_TAB_KEY, _selected_tab_index)
	config.save(save_path())


# --- Tab construction (reflection) -------------------------------------------

func _build_ui() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 60.0
	panel.offset_top = 60.0
	panel.offset_right = -60.0
	panel.offset_bottom = -60.0
	add_child(panel)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	panel.add_child(layout)

	var title: Label = Label.new()
	title.text = "Tuning panel (F4 / gamepad Start+X)"
	layout.add_child(title)

	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Bontago-xtq.13: fires for both a real click *and* rebuild()'s own
	# programmatic restore below -- either way, "whatever tab is now showing"
	# is exactly what the next close/reopen (or app restart) should return to.
	_tab_container.tab_changed.connect(_on_tab_changed)
	_tab_container.tab_clicked.connect(_on_tab_selected)
	layout.add_child(_tab_container)

	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	layout.add_child(button_row)

	var reset_button: Button = Button.new()
	reset_button.text = "Reset"
	reset_button.pressed.connect(_on_reset_pressed)
	button_row.add_child(reset_button)

	var save_button: Button = Button.new()
	save_button.text = "Save override"
	save_button.pressed.connect(_on_save_pressed)
	button_row.add_child(save_button)

	var copy_button: Button = Button.new()
	copy_button.text = "Copy"
	copy_button.pressed.connect(_on_copy_pressed)
	button_row.add_child(copy_button)

	_status_label = Label.new()
	button_row.add_child(_status_label)


## Wiring setters only refresh a UI that currently exists (panel open); a
## closed panel reads the new resources when next built.
func _rebuild_if_built() -> void:
	if _tab_container != null:
		rebuild()


## Frees the whole tab UI (Bontago-1pi.11.5). _rows is cleared with it so no
## stale control references survive; the selected tab index is already
## persisted by _on_tab_changed().
func _free_ui() -> void:
	if _tab_container == null:
		return
	var panel: Node = get_node_or_null("Panel")
	if panel != null:
		remove_child(panel)
		panel.queue_free()
	_tab_container = null
	_status_label = null
	_rows.clear()
	_group_titles.clear()


## Public so a test can force a rebuild after swapping camera_tuning/etc.
## directly (rather than through set_controller()/set_camera_rig()/
## set_field()).
func rebuild() -> void:
	if _tab_container == null:
		_build_ui()
	_rebuilding_tabs = true
	for child: Node in _tab_container.get_children():
		_tab_container.remove_child(child)
		# queue_free, not free: rebuild() is reached from a control's own signal
		# (e.g. the physics-preset OptionButton's item_selected), and freeing the
		# emitter mid-emission is a Godot error / potential crash.
		child.queue_free()
	_rows.clear()
	_group_titles.clear()
	_bind_sky_theme_to_live_cycle()

	var plan: Array[Dictionary] = _tab_plan()
	for entry: Dictionary in plan:
		_add_tab(String(entry["name"]), entry["resources"] as Array)

	_apply_availability()

	# Bontago-xtq.13: rebuild() just replaced every tab page (a fresh
	# TabContainer would otherwise land back on tab 0) -- restore whatever
	# tab the owner last had open, clamped in case a stale saved index no
	# longer fits (e.g. a client's hidden-tab availability changed the count).
	if _tab_container.get_tab_count() > 0:
		_tab_container.current_tab = clampi(_selected_tab_index, 0, _tab_container.get_tab_count() - 1)
	_rebuilding_tabs = false


## Bontago-1pi.113: tabs follow what a tuner thinks about, not which Resource a
## field lives in. Client-visible (look/feel) tabs first, host-only simulation
## tabs last (CLIENT_HIDDEN_TAB_FIRST). A resource listed on two tabs (Ghost)
## splits by section: hints.section_tabs names the sections that move to the
## later tab, the rest stay on the resource's first tab.
## DECISION: TerritoryVisuals is purely visual, so it sits with the beacons on a
## client-visible tab instead of the host-only Territory rules.
func _tab_plan() -> Array[Dictionary]:
	return [
		{"name": "Camera", "resources": [camera_tuning, camera_shake_config]},
		{"name": "Controls", "resources": [ghost_tuning]},
		{"name": "Ghost & Blocks", "resources": [ghost_tuning, block_visual_tuning, block_effects_config]},
		{"name": "Territory look", "resources": [territory_visuals, beacon_visual_tuning]},
		{"name": "HUD", "resources": [hud_visual_tuning]},
		{"name": "Sky", "resources": [sky_theme]},
		{"name": "Physics", "resources": [physics_tuning]},
		{"name": "Territory rules", "resources": [territory_tuning]},
		{"name": "Block bag", "resources": [block_feed_config]},
		{"name": "QoL", "resources": [qol_experiments]},
	]


## The first plan tab listing `resource`: where its sections live unless
## hints.section_tabs moves them.
func _default_tab_for(resource: Resource) -> String:
	for entry: Dictionary in _tab_plan():
		if (entry["resources"] as Array).has(resource):
			return String(entry["name"])
	return ""


func _add_tab(tab_name: String, resources: Array) -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = tab_name
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)

	var first_section: bool = true
	if tab_name == "Physics":
		var preset_rows: Array[Control] = [_build_physics_preset_row()]
		list.add_child(_build_section(HAND_BUILT_CLASS, PRESET_SECTION_TITLE, preset_rows, true))
		first_section = false
	if tab_name == "Sky":
		# Bontago-xtq.22 / 1pi.1: the Skybox row switches the loaded six-face
		# set; its live result (the disc's mirror) is judged against
		# TerritoryVisuals' reflection fields on the Territory look tab.
		# Bontago-1pi.113: Theme/Time/Skybox/Weather/Breeze are one ordinary
		# foldable section in the same grid as every reflected row.
		var scene_rows: Array[Control] = [
			_build_theme_row(), _build_time_of_day_row(), _build_skybox_row(),
			_build_weather_row(), _build_breeze_row(),
		]
		list.add_child(_build_section(HAND_BUILT_CLASS, SCENE_SECTION_TITLE, scene_rows, true))
		first_section = false

	for entry: Variant in resources:
		var resource: Resource = entry as Resource
		if resource == null:
			continue
		var built: Control = _build_resource_rows(resource, tab_name, first_section)
		if built.get_child_count() > 0:
			first_section = false
		list.add_child(built)

	scroll.add_child(list)
	_tab_container.add_child(scroll)


func _apply_availability() -> void:
	var full_access: bool = _has_full_access()
	for index: int in range(CLIENT_HIDDEN_TAB_FIRST, _tab_container.get_tab_count()):
		_tab_container.set_tab_hidden(index, not full_access)


func _has_full_access() -> bool:
	var provider: Variant = net_provider if net_provider != null else Net
	return bool(provider.is_host())


## Wraps `control` in the fixed-width control column of the row grid.
func _in_control_column(control: Control) -> Control:
	var holder: HBoxContainer = HBoxContainer.new()
	holder.custom_minimum_size = Vector2(CONTROL_COLUMN_WIDTH, 0.0)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.add_theme_constant_override("separation", ROW_SEPARATION)
	if not (control is HSlider):
		control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.add_child(control)
	return holder


## One foldable section per hints.sections title that belongs on `tab_name`,
## fields in declaration order (the order the config script lists them, which
## follows its own `## -- Title --` blocks). `first_on_tab` opens the first
## section built when no fold state was remembered yet.
func _build_resource_rows(resource: Resource, tab_name: String, first_on_tab: bool) -> VBoxContainer:
	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	var class_label: String = _class_label_for(resource)
	var fresh: Resource = _fresh_instance_for(resource)
	var default_tab: String = _default_tab_for(resource)

	var types: Dictionary = {}
	var names: Array[String] = []
	for prop: Dictionary in resource.get_property_list():
		if not _is_exported_field(prop):
			continue
		var prop_name: String = str(prop.get("name", ""))
		var type: int = int(prop.get("type", TYPE_NIL))
		if type != TYPE_BOOL and type != TYPE_INT and type != TYPE_FLOAT and type != TYPE_COLOR:
			continue
		types[prop_name] = type
		names.append(prop_name)

	var by_section: Dictionary = {}
	for prop_name: String in names:
		var title: String = _section_title(class_label, prop_name)
		if not by_section.has(title):
			by_section[title] = []
		(by_section[title] as Array).append(prop_name)

	var opened_one: bool = false
	for title: String in hints.ordered_sections(class_label, names):
		if hints.tab_for(class_label, title, default_tab) != tab_name:
			continue
		var built: Array[Control] = []
		for member: Variant in (by_section[title] as Array):
			var prop_name: String = String(member)
			var row: Control = _build_row_control(resource, prop_name, int(types[prop_name]), class_label, fresh)
			if row != null:
				built.append(row)
		if built.is_empty():
			continue
		var default_open: bool = first_on_tab and not opened_one
		opened_one = true
		list.add_child(_build_section(class_label, title, built, default_open))
		_group_titles.append({"resource": resource, "title": title})
	return list


func _section_title(class_label: String, prop_name: String) -> String:
	var title: String = hints.section_for(class_label, prop_name) if hints != null else ""
	return title if not title.is_empty() else TuningPanelHints.GENERAL_SECTION


## A foldable section: a flat header button ("v Title (N)") over a body holding
## the rows. The open state is remembered per Class/Title in _fold_open.
func _build_section(class_label: String, title: String, rows: Array[Control], default_open: bool) -> Control:
	var key: String = "%s/%s" % [class_label, title]
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Section_%s" % title.validate_node_name().replace(" ", "_")
	box.add_theme_constant_override("separation", 6)
	var header: Button = Button.new()
	header.name = "Header"
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# DECISION (Bontago-hfa.9): section headers take the arcade cream token (primary text).
	var header_ink: Color = MenuStyleFactory.arcade_tuning().cream_color
	header.add_theme_color_override("font_color", header_ink)
	header.add_theme_color_override("font_hover_color", header_ink)
	var body: VBoxContainer = VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 8)
	for row: Control in rows:
		body.add_child(row)
	var is_open: bool = bool(_fold_open.get(key, default_open))
	body.visible = is_open
	header.text = _section_header_text(title, rows.size(), is_open)
	header.pressed.connect(func() -> void:
		var now_open: bool = not body.visible
		body.visible = now_open
		_fold_open[key] = now_open
		header.text = _section_header_text(title, rows.size(), now_open)
	)
	box.add_child(HSeparator.new())
	box.add_child(header)
	box.add_child(body)
	return box


func _section_header_text(title: String, count: int, is_open: bool) -> String:
	return "%s%s (%d)" % [SECTION_OPEN_MARK if is_open else SECTION_CLOSED_MARK, title, count]


## The baseline a row's "(default X)" label and yellow modified-highlight
## compare against (outcome 2, Bontago-sen.7). It is exactly what Reset
## restores: the shipped .tres loaded fresh (CACHE_MODE_IGNORE, never the
## cached live instance) when `resource` has a resource_path, so the label and
## highlight can never disagree with _reset_resource(). Only a path-less
## resource falls back to a fresh instance of its own script (.gd @export
## defaults). Sky tab: the active theme is whichever resource is live, and its
## own resource_path picks sunset/night, so the baseline follows the theme.
## DECISION: Physics presets copy values onto the live physics_tuning but the
## baseline stays the shipped physics_tuning.tres, so after picking a
## non-default preset modified rows legitimately show yellow; Reset returns
## to the file and clears them.
## Built once per resource per rebuild() rather than once per field.
func _fresh_instance_for(resource: Resource) -> Resource:
	if resource == null:
		return null
	if not resource.resource_path.is_empty():
		var shipped: Resource = ResourceLoader.load(resource.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if shipped != null:
			return shipped
	if resource.get_script() == null:
		return null
	var script: Script = resource.get_script() as Script
	return script.new() as Resource


func _is_exported_field(prop: Dictionary) -> bool:
	var usage: int = int(prop.get("usage", 0))
	return (usage & EXPORT_USAGE_MASK) == EXPORT_USAGE_MASK


func _class_label_for(resource: Resource) -> String:
	if resource == null or resource.get_script() == null:
		return ""
	return String((resource.get_script() as Script).get_global_name())


func _build_row_control(resource: Resource, prop_name: String, type: int, class_label: String, fresh: Resource) -> Control:
	var default_value: Variant = fresh.get(prop_name) if fresh != null else resource.get(prop_name)
	match type:
		TYPE_BOOL:
			return _build_bool_row(resource, prop_name, class_label, default_value)
		TYPE_INT:
			return _build_int_row(resource, prop_name, class_label, default_value)
		TYPE_FLOAT:
			return _build_float_row(resource, prop_name, class_label, default_value)
		TYPE_COLOR:
			return _build_color_row(resource, prop_name, class_label, default_value)
		_:
			return null


## One row is four aligned columns: name (human label over a muted one-sentence
## description; a tooltip repeats it) | control | live value with its unit |
## "default X unit". `control` is added in the control column by the caller.
## Returns {"row": HBoxContainer, "name_label", "value_label", "default_label"}.
func _build_row_frame(prop_name: String, class_label: String, control: Control, type: int, default_value: Variant, unit: String, decimals: int) -> Dictionary:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)

	var block: VBoxContainer = VBoxContainer.new()
	block.custom_minimum_size = Vector2(NAME_COLUMN_WIDTH, 0.0)
	block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	block.add_theme_constant_override("separation", 0)
	var description: String = hints.description_for(class_label, prop_name) if hints != null else ""
	var name_label: Label = Label.new()
	name_label.text = _display_name(class_label, prop_name)
	if not description.is_empty():
		name_label.tooltip_text = description
	block.add_child(name_label)
	var desc_label: Label = Label.new()
	desc_label.text = description
	desc_label.theme_type_variation = CAPTION_THEME_VARIATION
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block.add_child(desc_label)
	row.add_child(block)

	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_in_control_column(control))

	var value_label: Label = Label.new()
	value_label.custom_minimum_size = Vector2(VALUE_WIDTH, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value_label)

	var default_label: Label = Label.new()
	default_label.custom_minimum_size = Vector2(DEFAULT_COLUMN_WIDTH, 0.0)
	default_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	default_label.theme_type_variation = CAPTION_THEME_VARIATION
	default_label.text = DEFAULT_PREFIX + _format_shown(default_value, type, unit, decimals)
	row.add_child(default_label)
	return {"row": row, "name_label": name_label, "value_label": value_label, "default_label": default_label}


func _display_name(class_label: String, prop_name: String) -> String:
	return hints.label_for(class_label, prop_name) if hints != null else prop_name


func _unit_of(class_label: String, prop_name: String) -> String:
	return hints.unit_for(class_label, prop_name) if hints != null else ""


## A float's displayed decimals: enough that the slider's span shows about
## SPAN_SIGNIFICANT_DIGITS digits (0..1 -> 3, 0..360 -> 1, 0..0.02 -> 5).
func _decimals_for(value_range: Vector2) -> int:
	var span: float = absf(value_range.y - value_range.x)
	if span <= 0.0:
		return SPAN_SIGNIFICANT_DIGITS
	var decimals: int = ceili(float(SPAN_SIGNIFICANT_DIGITS) - log(span) / log(10.0))
	return clampi(decimals, 0, MAX_DISPLAY_DECIMALS)


## "12.50 m" / "On" / "#ccd9ffd9" / "8 s": one formatter for the live value and
## the default column, so both always read alike.
func _format_shown(value: Variant, type: int, unit: String, decimals: int) -> String:
	var text: String = ""
	match type:
		TYPE_BOOL:
			return BOOL_ON_TEXT if bool(value) else BOOL_OFF_TEXT
		TYPE_INT:
			text = str(int(value))
		TYPE_FLOAT:
			text = String.num(float(value), decimals)
		TYPE_COLOR:
			return "#%s" % (value as Color).to_html(true)
		_:
			text = str(value)
	if unit.is_empty():
		return text
	return "%s%s" % [text, unit] if unit == DEGREE_UNIT else "%s %s" % [text, unit]


func _build_bool_row(resource: Resource, prop_name: String, class_label: String, default_value: Variant) -> Control:
	# Bontago-1pi.113: a text toggle ("On"/"Off", pressed = lit) instead of a
	# CheckButton whose off state was a nearly invisible dot.
	var check: Button = Button.new()
	check.toggle_mode = true
	check.custom_minimum_size = Vector2(TOGGLE_WIDTH, 0.0)
	check.button_pressed = bool(resource.get(prop_name))
	check.text = _format_shown(check.button_pressed, TYPE_BOOL, "", 0)
	var frame: Dictionary = _build_row_frame(prop_name, class_label, check, TYPE_BOOL, default_value, "", 0)
	var value_label: Label = frame["value_label"] as Label
	value_label.text = _format_shown(check.button_pressed, TYPE_BOOL, "", 0)
	check.toggled.connect(func(pressed: bool) -> void:
		resource.set(prop_name, pressed)
		value_label.text = _format_shown(pressed, TYPE_BOOL, "", 0)
		check.text = value_label.text
		_on_field_changed(resource, prop_name)
	)
	_register_row(frame, resource, prop_name, check, default_value, TYPE_BOOL, "", 0)
	return frame["row"] as Control


func _build_int_row(resource: Resource, prop_name: String, class_label: String, default_value: Variant) -> Control:
	var current: float = float(int(resource.get(prop_name)))
	var value_range: Vector2 = _range_for(class_label, prop_name, current)
	var unit: String = _unit_of(class_label, prop_name)

	var spin: SpinBox = SpinBox.new()
	spin.min_value = value_range.x
	spin.max_value = value_range.y
	spin.step = 1.0
	spin.value = current
	spin.suffix = unit
	spin.custom_minimum_size = Vector2(SPIN_WIDTH, 0.0)
	var frame: Dictionary = _build_row_frame(prop_name, class_label, spin, TYPE_INT, default_value, unit, 0)
	spin.value_changed.connect(func(v: float) -> void:
		resource.set(prop_name, int(round(v)))
		_on_field_changed(resource, prop_name)
	)
	_register_row(frame, resource, prop_name, spin, default_value, TYPE_INT, unit, 0)
	return frame["row"] as Control


func _build_float_row(resource: Resource, prop_name: String, class_label: String, default_value: Variant) -> Control:
	var current: float = float(resource.get(prop_name))
	var value_range: Vector2 = _range_for(class_label, prop_name, current)
	var unit: String = _unit_of(class_label, prop_name)
	var decimals: int = _decimals_for(value_range)

	var slider: HSlider = HSlider.new()
	slider.min_value = value_range.x
	slider.max_value = value_range.y
	# DECISION (ui/TuningPanel.gd): step = 0 (continuous) rather than a fixed
	# fraction of the range -- Range snaps `value` to the nearest multiple of
	# `step` on assignment, which quantized the row's *initial* display away
	# from the field's real current value (e.g. gravity_multiplier's exact
	# 1.0 initial value rendered as 0.999 with a 200-step range) with no
	# benefit: nothing here depends on a coarse arrow-key increment, and a
	# real mouse drag is already limited to the slider's own pixel width.
	slider.step = 0.0
	slider.value = current
	slider.custom_minimum_size = Vector2(CONTROL_MIN_WIDTH, 0.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var frame: Dictionary = _build_row_frame(prop_name, class_label, slider, TYPE_FLOAT, default_value, unit, decimals)
	var value_label: Label = frame["value_label"] as Label
	value_label.text = _format_shown(current, TYPE_FLOAT, unit, decimals)
	slider.value_changed.connect(func(v: float) -> void:
		resource.set(prop_name, v)
		value_label.text = _format_shown(v, TYPE_FLOAT, unit, decimals)
		_on_field_changed(resource, prop_name)
	)
	_register_row(frame, resource, prop_name, slider, default_value, TYPE_FLOAT, unit, decimals)
	return frame["row"] as Control


func _build_color_row(resource: Resource, prop_name: String, class_label: String, default_value: Variant) -> Control:
	var picker: ColorPickerButton = ColorPickerButton.new()
	picker.color = resource.get(prop_name)
	picker.custom_minimum_size = Vector2(FIXED_CONTROL_WIDTH, SWATCH_HEIGHT)
	var frame: Dictionary = _build_row_frame(prop_name, class_label, picker, TYPE_COLOR, default_value, "", 0)
	var value_label: Label = frame["value_label"] as Label
	value_label.text = _format_shown(picker.color, TYPE_COLOR, "", 0)
	picker.color_changed.connect(func(c: Color) -> void:
		resource.set(prop_name, c)
		value_label.text = _format_shown(c, TYPE_COLOR, "", 0)
		_on_field_changed(resource, prop_name)
	)
	_register_row(frame, resource, prop_name, picker, default_value, TYPE_COLOR, "", 0)
	return frame["row"] as Control


func _register_row(frame: Dictionary, resource: Resource, prop_name: String, control: Control, default_value: Variant, type: int, unit: String, decimals: int) -> void:
	_rows.append({
		"resource": resource, "property": prop_name, "control": control,
		"name_label": frame["name_label"], "default_label": frame["default_label"],
		"default": default_value, "type": type, "unit": unit, "decimals": decimals,
	})
	_refresh_row_marker(_rows[-1])


## Outcome 3: whether a row's live value has drifted from its default -- used
## both to decide the "•" marker's color/text and as this panel's own test
## seam (tests/unit/test_tuning_panel.gd checks this directly rather than
## parsing a Label's text).
func is_modified(resource: Resource, prop_name: String) -> bool:
	for row: Dictionary in _rows:
		if row.get("resource") == resource and row.get("property") == prop_name:
			return not _values_equal(resource.get(prop_name), row.get("default"), int(row.get("type", TYPE_NIL)))
	return false


func _values_equal(current: Variant, default_value: Variant, type: int) -> bool:
	match type:
		TYPE_FLOAT:
			return is_equal_approx(float(current), float(default_value))
		TYPE_INT:
			return int(current) == int(default_value)
		TYPE_BOOL:
			return bool(current) == bool(default_value)
		TYPE_COLOR:
			return (current as Color).is_equal_approx(default_value as Color)
		_:
			return current == default_value


## Re-derives one row's modified marker/colour from its resource's *current*
## value -- called right after a row is first built (nothing is modified yet,
## but this keeps one code path for both cases) and again from
## _on_field_changed() every time a control writes its resource, so the marker
## updates live without a full rebuild(). The default column is static text.
func _refresh_row_marker(row: Dictionary) -> void:
	var name_label: Label = row.get("name_label") as Label
	if name_label == null:
		return
	var resource: Resource = row.get("resource") as Resource
	var prop_name: String = String(row.get("property"))
	var type: int = int(row.get("type", TYPE_NIL))
	var modified: bool = not _values_equal(resource.get(prop_name), row.get("default"), type)

	var base_text: String = _display_name(_class_label_for(resource), prop_name)
	name_label.text = (MODIFIED_MARKER + base_text) if modified else base_text
	if modified:
		# DECISION (Bontago-hfa.9): the owner-adjusted highlight is the arcade rim gold, so an
		# adjusted field stays unmistakable against the cream names and dust captions.
		name_label.add_theme_color_override("font_color", MenuStyleFactory.arcade_tuning().rim_color)
	else:
		name_label.remove_theme_color_override("font_color")


## `hints`'s per-field entry, or a fallback derived from the field's current
## value (design brief: "default [0, 4x current] for unknowns").
func _range_for(class_label: String, prop_name: String, current: float) -> Vector2:
	var hinted: Vector2 = hints.range_for(class_label, prop_name) if hints != null else Vector2(NAN, NAN)
	if not (is_nan(hinted.x) or is_nan(hinted.y)):
		return hinted
	return _fallback_range(current)


## DECISION (ui/TuningPanel.gd): the design brief's fallback is literally
## "[0, 4x current]", which degenerates for a field whose sane value sits at
## or below zero (an unhinted negative-by-default field, or one that happens
## to read exactly 0 when the panel first builds its row) -- an inverted or
## zero-width range respectively. A negative current mirrors the same
## magnitude below zero instead; a zero current gets a small symmetric
## default rather than a slider with nowhere to go.
func _fallback_range(current: float) -> Vector2:
	if current > 0.0:
		return Vector2(0.0, current * 4.0)
	elif current < 0.0:
		return Vector2(current * 4.0, 0.0)
	return Vector2(-1.0, 1.0)


## Test/inspection seam: the control built for one resource field, or null if
## no such row exists (an un-exported field, an unsupported type, or a
## resource this panel doesn't currently reference).
func control_for(resource: Resource, prop_name: String) -> Control:
	for row: Dictionary in _rows:
		if row.get("resource") == resource and row.get("property") == prop_name:
			return row.get("control") as Control
	return null


## Test/inspection seam: the section titles built for `resource`, in order.
func section_titles_for(resource: Resource) -> Array[String]:
	var titles: Array[String] = []
	for entry: Dictionary in _group_titles:
		if entry.get("resource") == resource:
			titles.append(String(entry.get("title")))
	return titles


## Test/inspection seam: the _rows entry for one field ({} if none).
func _row_for(resource: Resource, prop_name: String) -> Dictionary:
	for row: Dictionary in _rows:
		if row.get("resource") == resource and row.get("property") == prop_name:
			return row
	return {}


## Test/inspection seam: how many rows this panel built for `resource`.
func row_count_for(resource: Resource) -> int:
	var count: int = 0
	for row: Dictionary in _rows:
		if row.get("resource") == resource:
			count += 1
	return count


## Test/inspection seam: every field name this panel built a row for on
## `resource` (outcome 2's "walk them" -- a test uses this to check every
## shown field has a description, without duplicating this file's own
## reflection loop).
func shown_fields_for(resource: Resource) -> Array[String]:
	var names: Array[String] = []
	for row: Dictionary in _rows:
		if row.get("resource") == resource:
			names.append(String(row.get("property")))
	return names


## Test/inspection seam: one field's row as text -- the modified marker, its
## human label and its "(default ...)" annotation -- without reaching into a
## Control tree.
func label_text_for(resource: Resource, prop_name: String) -> String:
	for row: Dictionary in _rows:
		if row.get("resource") == resource and row.get("property") == prop_name:
			return "%s (%s)" % [(row.get("name_label") as Label).text, (row.get("default_label") as Label).text]
	return ""


## Test/inspection seam: the default column's text for one field ("default 0.18 s").
func default_text_for(resource: Resource, prop_name: String) -> String:
	for row: Dictionary in _rows:
		if row.get("resource") == resource and row.get("property") == prop_name:
			return (row.get("default_label") as Label).text
	return ""


# --- Live-apply hooks (see class doc) ----------------------------------------

func _on_field_changed(resource: Resource, _prop_name: String) -> void:
	for row: Dictionary in _rows:
		if row.get("resource") == resource and row.get("property") == _prop_name:
			_refresh_row_marker(row)
			break
	if resource == physics_tuning:
		apply_physics_live()
	elif resource == territory_visuals:
		refresh_territory_visuals_live()
	elif resource == camera_tuning:
		apply_camera_tuning_live()
	elif resource == sky_theme:
		# Bontago-mp0.83: the day/night cycle length is a rate, not a look; it
		# goes through its own seam so the time of day stays put and the theme
		# is not re-applied over a running cycle.
		if _prop_name == "cycle_length_seconds":
			apply_cycle_length_live()
		else:
			apply_sky_theme_live()
			# Bontago-59o.18 (U1): editing a preset's locked phase moves the
			# sky now when that preset is the selected time of day.
			if _prop_name.begins_with("cycle_locked_phase") and _time_of_day_choice != TIME_CUSTOM:
				_push_locked_phase(_phase_for_time_choice(_time_of_day_choice))
	# ghost_tuning / territory_tuning / block_feed_config are already read
	# live by whatever consumes them each frame/tick -- see this file's class
	# doc for the live-apply hooks the other resources need. Bontago-xtq.36:
	# block_visual_tuning/block_effects_config/beacon_visual_tuning/
	# camera_shake_config/hud_visual_tuning need no hook either -- each is
	# either read live per-frame/per-event already (CameraShakeConfig,
	# BlockEffectsConfig) or baked once at construction time with no existing
	# re-push seam on the consumer (BlockVisualTuning's toon material in
	# BlockFactory.build(), BeaconVisualTuning's geometry in HomeFlag._build(),
	# HUDVisualTuning's StyleBoxFlat in HUD._style_panel()/_ensure_share_row_
	# count()) -- a value write here still takes effect for anything built
	# from here on, matching the brief's "otherwise a value write is enough".


## Bontago-xtq.17: the Physics tab's own preset row, built the same way every
## other row here is (a plain Control returned to _add_tab's caller) but not
## reflection-built and not registered in _rows -- it doesn't belong to one
## resource field, it writes every field of physics_tuning at once.
func _build_physics_preset_row() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)

	var label: Label = Label.new()
	label.text = "Physics preset"
	label.custom_minimum_size = Vector2(NAME_COLUMN_WIDTH, 0.0)
	row.add_child(label)

	var option: OptionButton = OptionButton.new()
	# Review fix (Bontago-xtq.17): cube_mass only feeds BlockFactory.build()'s
	# `mass = tuning.cube_mass * cube_count` at spawn time (game/BlockFactory.gd)
	# -- Block.apply_physics_tuning(), the live-apply path a preset pick also
	# runs (apply_physics_preset() below), never touches an existing body's
	# `.mass`. So switching presets mid-match changes how heavy the NEXT block
	# placed is, not any block already standing.
	option.tooltip_text = (
		"Presets change mass only for blocks placed after the switch " +
		"(mass is not live-applied to standing blocks). " +
		"Original feel adds a fixed 2-degree release tilt above a one-edge gap " +
		"to break flat-impact symmetry; experimental, not original-game evidence. " +
		"Tokamak defaults matches source material/damping values on Jolt; " +
		"it does not change the engine or reproduce Bontago settings."
	)
	for preset: Dictionary in PHYSICS_PRESETS:
		option.add_item(String(preset["label"]))
	option.item_selected.connect(func(index: int) -> void:
		apply_physics_preset(String(PHYSICS_PRESETS[index]["id"]))
	)
	row.add_child(_in_control_column(option))

	return row


## Loads `preset_id`'s config/physics_presets/*.tres and copies its every
## exported field onto the live physics_tuning instance, then pushes it out
## through the same live-apply path a slider drag already uses
## (apply_physics_live()) and rebuild()s so every Physics slider shows the
## new values (the same pattern reset_all() already uses below). A silent
## no-op for an id PHYSICS_PRESETS doesn't have (defensive; the dropdown
## itself can only emit an in-range index). Public so a test can pick a
## preset without a real OptionButton.
func apply_physics_preset(preset_id: String) -> void:
	var preset: PhysicsTuning = _physics_preset_resource(preset_id)
	if preset == null:
		return
	for prop: Dictionary in preset.get_property_list():
		if not _is_exported_field(prop):
			continue
		var prop_name: String = str(prop.get("name", ""))
		physics_tuning.set(prop_name, preset.get(prop_name))
	apply_physics_live()
	rebuild()


## Bontago-adt: the Sky tab's "Theme" dropdown (sunset / night / any future
## config/sky_themes/*.tres SkyThemeDef, discovered by
## Skybox.list_available_themes()), led by Bontago-59o.18's "cycle" entry (the
## default match sky: Skybox.start_cycle(); the Time-of-day row below locks it).
## DECISION: a sibling row directly above the
## Skybox row rather than extra Skybox entries -- the Skybox row picks a
## six-face texture set (or procedural), a different axis from the whole-look
## theme (light, fog, clouds, birds), and mixing them would make "night" and
## "beach" look like mutually exclusive choices. Persists like the Skybox row:
## the pick lives on skybox_config.theme_name (saved by Save override).
func _build_theme_row() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)

	var label: Label = Label.new()
	label.text = "Theme"
	label.custom_minimum_size = Vector2(NAME_COLUMN_WIDTH, 0.0)
	row.add_child(label)

	var option: OptionButton = OptionButton.new()
	option.name = "ThemeOption"
	option.tooltip_text = (
		"Switches the whole sky theme live (sky, light, fog, clouds, birds, sun " +
		"flare, reflections). The sliders below then edit the chosen theme. " +
		"cycle = the running day/night cycle (the default match sky; lock a time " +
		"with Time of day); every other entry is a static theme."
	)
	var ids: PackedStringArray = theme_ids()
	for theme_id: String in ids:
		option.add_item(theme_id)
	var selected_index: int = ids.find(theme_choice())
	option.selected = selected_index if selected_index >= 0 else 0
	option.item_selected.connect(func(index: int) -> void:
		apply_sky_theme_id(ids[index])
		rebuild()
	)
	row.add_child(_in_control_column(option))
	return row


## Bontago-470.1: the Sky tab's "Weather" dropdown -- "Schedule" (follow the
## lobby mode) / "Off" / every config/weather/*.tres by display name (new
## types appear automatically). Host-only effect via
## MatchWeather.set_debug_override(); switching ends the previous weather
## (restoring its physics) first. On a client the row is disabled with a hint;
## clients see the host's weather through normal replication.
## DECISION: no intensity slider -- a local intensity scale would not replicate,
## so a client would present a different strength than the host simulates.
func _build_weather_row() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)

	var label: Label = Label.new()
	label.text = "Weather"
	label.custom_minimum_size = Vector2(NAME_COLUMN_WIDTH, 0.0)
	row.add_child(label)

	var option: OptionButton = OptionButton.new()
	option.name = "WeatherOption"
	var weather: MatchWeather = _weather()
	var ids: Array[StringName] = [&"", MatchWeather.DEBUG_OFF]
	option.add_item("Schedule (lobby mode)")
	option.add_item("Off")
	if weather != null:
		for weather_id: StringName in weather.available_ids():
			ids.append(weather_id)
			option.add_item(_weather_display_name(weather_id))
		var current: int = ids.find(weather.debug_override())
		option.selected = current if current >= 0 else 0
	var host: bool = _has_full_access()
	option.disabled = not host or weather == null
	option.tooltip_text = (
		"Forces a weather for testing (host only), replacing the lobby mode until " +
		"the match ends or you pick Schedule. The previous weather is removed cleanly."
		if host else "Host only: the host decides the weather; you see it as it happens."
	)
	option.item_selected.connect(func(index: int) -> void:
		apply_weather_override(ids[index])
	)
	row.add_child(_in_control_column(option))
	if not host:
		var hint: Label = Label.new()
		hint.text = "(host only)"
		row.add_child(hint)
	return row


## Bontago-470.2: F4 toggle for the always-on Breeze gust layer (host only, for
## testing; strength lives in config/breeze.tres). Clients see gusts through
## replication, so the box is disabled with a hint on a client.
func _build_breeze_row() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)
	var label: Label = Label.new()
	label.text = "Breeze"
	label.custom_minimum_size = Vector2(NAME_COLUMN_WIDTH, 0.0)
	row.add_child(label)
	var box: CheckButton = CheckButton.new()
	box.name = "BreezeToggle"
	box.text = "Gusts on"
	var weather: MatchWeather = _weather()
	var host: bool = _has_full_access()
	box.button_pressed = weather != null and weather.breeze_enabled()
	box.disabled = not host or weather == null
	box.tooltip_text = "Always-on weak local gusts (host only; paused during storms). Turn off to test a weather alone." if host else "Host only."
	box.toggled.connect(func(pressed: bool) -> void:
		apply_breeze_enabled(pressed)
	)
	row.add_child(_in_control_column(box))
	if not host:
		var hint: Label = Label.new()
		hint.text = "(host only)"
		row.add_child(hint)
	return row


## Turns Breeze on/off on the host; false on a client or with no weather.
func apply_breeze_enabled(value: bool) -> bool:
	var weather: MatchWeather = _weather()
	if weather == null or not _has_full_access():
		return false
	return weather.set_breeze_enabled(value)


## Forces (or, with &"", releases) the debug weather on the host; false on a
## client, for an unknown id, or with no Match weather available. Public for tests.
func apply_weather_override(weather_id: StringName) -> bool:
	var weather: MatchWeather = _weather()
	if weather == null or not _has_full_access():
		return false
	return weather.set_debug_override(weather_id)


func _weather() -> MatchWeather:
	if weather_provider != null:
		return weather_provider as MatchWeather
	return Match.weather()


func _weather_display_name(weather_id: StringName) -> String:
	for def: WeatherTuning in WeatherTuning.load_all():
		if def.id == weather_id:
			return def.display_name if def.display_name != "" else DisplayNames.weather_id_label(weather_id)
	return DisplayNames.weather_id_label(weather_id)


## Bontago-adt: selects theme `theme_id` -- writes skybox_config.theme_name,
## rebinds sky_theme (the Sky tab's sliders' resource) and re-applies
## everything theme-driven on every live Skybox. False for an unknown id.
## The Sky tab rows are rebuilt by the caller (rebuild()).
func apply_sky_theme_id(theme_id: String) -> bool:
	if theme_id == CYCLE_THEME_ID:
		return _apply_cycle_theme()
	var chosen: SkyThemeDef = Skybox.load_theme(theme_id)
	if chosen == null:
		return false
	skybox_config.theme_name = theme_id
	sky_theme = chosen
	for node: Node in get_tree().get_nodes_in_group(Skybox.TUNING_GROUP):
		var skybox: Skybox = node as Skybox
		if skybox != null:
			skybox.set_theme_by_id(theme_id)
	return true


## Bontago-59o.18 (U1): the Theme dropdown's ids: the leading "cycle" entry,
## then every static theme file (Skybox.list_available_themes()).
func theme_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray([CYCLE_THEME_ID])
	ids.append_array(Skybox.list_available_themes())
	return ids


## The theme the Theme dropdown shows: "cycle" while skybox_config.theme_name says
## so or any live Skybox runs the day/night cycle (a match starts one by default,
## whatever theme_name was persisted), else skybox_config.theme_name.
func theme_choice() -> String:
	if skybox_config.theme_name == CYCLE_THEME_ID or _any_cycle_active():
		return CYCLE_THEME_ID
	return skybox_config.theme_name


## The theme the day/night cycle copies (Skybox.configure_match_sky: the DAY
## entry, sunset.tres). Its sliders and locked-phase exports drive the cycle.
func _cycle_source_theme() -> SkyThemeDef:
	return Skybox.load_theme(MatchConfig.SKY_THEME_IDS[MatchConfig.SkyThemeMode.DAY])


func _live_skyboxes() -> Array[Skybox]:
	var found: Array[Skybox] = []
	if not is_inside_tree():
		return found
	for node: Node in get_tree().get_nodes_in_group(Skybox.TUNING_GROUP):
		var skybox: Skybox = node as Skybox
		if skybox != null:
			found.append(skybox)
	return found


func _any_cycle_active() -> bool:
	for skybox: Skybox in _live_skyboxes():
		if skybox.is_cycle_active():
			return true
	return false


## While a cycle is the shown theme the Sky tab's sliders must edit the cycle's
## source theme, not whichever static theme the panel was last bound to.
func _bind_sky_theme_to_live_cycle() -> void:
	if theme_choice() != CYCLE_THEME_ID:
		return
	var source: SkyThemeDef = _cycle_source_theme()
	if source != null:
		sky_theme = source


## "cycle" theme pick: persists theme_name, rebinds the sliders to the cycle's
## source theme and (re)starts the running cycle on every live Skybox.
func _apply_cycle_theme() -> bool:
	var source: SkyThemeDef = _cycle_source_theme()
	if source == null:
		return false
	skybox_config.theme_name = CYCLE_THEME_ID
	sky_theme = source
	_time_of_day_choice = TIME_RUNNING
	for skybox: Skybox in _live_skyboxes():
		skybox.start_cycle()
	return true


## Bontago-59o.18 (U1): the Sky tab's "Time of day" row. Running / Sunset / Dawn /
## Night / Custom (a 0..1 phase slider, editable for Custom only) drive the
## cycle through Skybox.set_locked_phase(); the row is disabled while a static
## theme is shown (nothing to lock). Local dev tuning like the cycle length:
## nothing is replicated and nothing but theme_name = "cycle" persists.
func _build_time_of_day_row() -> Control:
	_sync_time_of_day_from_live()
	var active: bool = theme_choice() == CYCLE_THEME_ID
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)

	var label: Label = Label.new()
	label.text = "Time of day"
	label.custom_minimum_size = Vector2(NAME_COLUMN_WIDTH, 0.0)
	row.add_child(label)

	var option: OptionButton = OptionButton.new()
	option.name = "TimeOfDayOption"
	option.tooltip_text = (
		"Running keeps the day/night cycle moving. Sunset, Dawn and Night lock the " +
		"cycle at that time (the lobby's fixed options); Custom locks it where the " +
		"slider is. Only applies while the cycle theme is selected."
	)
	for choice_label: String in TIME_OF_DAY_LABELS:
		option.add_item(choice_label)
	option.selected = maxi(TIME_OF_DAY_CHOICES.find(_time_of_day_choice), 0)
	option.disabled = not active
	var holder: HBoxContainer = HBoxContainer.new()
	holder.custom_minimum_size = Vector2(CONTROL_COLUMN_WIDTH, 0.0)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("separation", ROW_SEPARATION)
	row.add_child(holder)
	holder.add_child(option)

	var slider: HSlider = HSlider.new()
	slider.name = "TimeOfDaySlider"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = TIME_OF_DAY_SLIDER_STEP
	slider.value = _displayed_time_phase()
	slider.editable = active and _time_of_day_choice == TIME_CUSTOM
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(TIME_OF_DAY_SLIDER_MIN_WIDTH, 0.0)
	slider.tooltip_text = "Cycle phase: 0 dawn, 0.25 noon, 0.5 sunset, 0.75 midnight. Editable with Custom."
	holder.add_child(slider)

	var value_label: Label = Label.new()
	value_label.name = "TimeOfDayValue"
	value_label.custom_minimum_size = Vector2(VALUE_WIDTH, 0.0)
	value_label.text = TIME_OF_DAY_VALUE_FORMAT % slider.value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	# Stand-in for the default column so the value column lines up with the
	# reflected rows' value column.
	var default_spacer: Control = Control.new()
	default_spacer.custom_minimum_size = Vector2(DEFAULT_COLUMN_WIDTH, 0.0)
	row.add_child(default_spacer)

	option.item_selected.connect(func(index: int) -> void:
		var choice: String = TIME_OF_DAY_CHOICES[index]
		apply_time_of_day(choice)
		slider.set_value_no_signal(_displayed_time_phase())
		slider.editable = choice == TIME_CUSTOM
		value_label.text = TIME_OF_DAY_VALUE_FORMAT % slider.value
	)
	slider.value_changed.connect(func(value: float) -> void:
		apply_custom_time_of_day(value)
		value_label.text = TIME_OF_DAY_VALUE_FORMAT % value
	)
	return row


## Selects a Time-of-day `choice` (a TIME_OF_DAY_CHOICES entry) on every live
## cycle Skybox: running -> set_locked_phase(-1), sunset/dawn/night -> the source
## theme's locked phase, custom -> locks where the cycle is now. False for an
## unknown choice. Public so a test can drive it without a real OptionButton.
func apply_time_of_day(choice: String) -> bool:
	if not TIME_OF_DAY_CHOICES.has(choice):
		return false
	_time_of_day_choice = choice
	if choice == TIME_CUSTOM:
		var live: float = _live_cycle_phase()
		if live >= 0.0:
			_time_of_day_custom_phase = live
	_push_locked_phase(_phase_for_time_choice(choice))
	return true


## The Custom slider: locks every live cycle Skybox at `phase` (clamped 0..1).
func apply_custom_time_of_day(phase: float) -> void:
	_time_of_day_choice = TIME_CUSTOM
	_time_of_day_custom_phase = clampf(phase, 0.0, 1.0)
	_push_locked_phase(_time_of_day_custom_phase)


## The Time-of-day choice currently selected (a TIME_OF_DAY_CHOICES entry).
func time_of_day_choice() -> String:
	return _time_of_day_choice


## The phase `choice` locks the cycle at; -1.0 for running (and for an
## unresolvable preset, which then leaves the cycle running).
func _phase_for_time_choice(choice: String) -> float:
	if choice == TIME_RUNNING:
		return -1.0
	if choice == TIME_CUSTOM:
		return _time_of_day_custom_phase
	var source: SkyThemeDef = _cycle_source_theme()
	return source.locked_phase_for(choice) if source != null else -1.0


## The phase the Custom slider shows for the current choice.
func _displayed_time_phase() -> float:
	var phase: float = _phase_for_time_choice(_time_of_day_choice)
	return phase if phase >= 0.0 else _time_of_day_custom_phase


func _push_locked_phase(phase: float) -> void:
	for skybox: Skybox in _live_skyboxes():
		if skybox.is_cycle_active():
			skybox.set_locked_phase(phase)


## The phase of the first live cycle Skybox (-1.0 when none runs one).
func _live_cycle_phase() -> float:
	for skybox: Skybox in _live_skyboxes():
		if skybox.is_cycle_active():
			return skybox.current_cycle_phase()
	return -1.0


## Seeds the row's state from the first live cycle Skybox (a match may have
## locked it from the lobby): running, a preset whose phase matches, or custom.
func _sync_time_of_day_from_live() -> void:
	for skybox: Skybox in _live_skyboxes():
		if not skybox.is_cycle_active():
			continue
		var locked: float = skybox.locked_phase()
		var current: float = skybox.current_cycle_phase()
		if current >= 0.0:
			_time_of_day_custom_phase = current
		if locked < 0.0:
			_time_of_day_choice = TIME_RUNNING
			return
		_time_of_day_custom_phase = locked
		_time_of_day_choice = _time_choice_for_phase(locked)
		return


func _time_choice_for_phase(phase: float) -> String:
	var source: SkyThemeDef = _cycle_source_theme()
	if source != null:
		for choice: String in TIME_OF_DAY_CHOICES:
			var preset: float = source.locked_phase_for(choice)
			if preset >= 0.0 and absf(preset - phase) <= TIME_OF_DAY_PHASE_EPSILON:
				return choice
	return TIME_CUSTOM


## Bontago-xtq.22: the Sky tab's own Skybox row (Bontago-1pi.1: moved here
## from the Territory tab -- owner playtest: "the skybox setting in
## territory should probably move over to sky settings"), built the same way
## _build_physics_preset_row() above is (a plain Control returned to
## _add_tab's caller, not reflection-built and not registered in _rows --
## config/SkyboxConfig.gd's `default_set`/`enabled` are a String and a bool
## the reflection loop either can't render (String) or would show as a
## second, redundant control alongside this dropdown (`enabled`), so both
## stay off the generic per-field roster and are written here as a pair
## instead, the same "one control owns several fields at once" idiom the
## preset row already established).
func _build_skybox_row() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)

	var label: Label = Label.new()
	label.text = "Skybox"
	label.custom_minimum_size = Vector2(NAME_COLUMN_WIDTH, 0.0)
	row.add_child(label)

	var option: OptionButton = OptionButton.new()
	option.tooltip_text = (
		"Switches the loaded six-face skybox set live (the sky and the disc's " +
		"mirror/reflection both update immediately) -- lets the owner judge " +
		"disc reflectivity against different skies without restarting the match."
	)
	var ids: Array[String] = [Skybox.PROCEDURAL_SET_ID]
	option.add_item("Procedural / none")
	for set_id: String in Skybox.list_available_sets():
		ids.append(set_id)
		option.add_item(set_id)

	var selected_id: String = (
		skybox_config.default_set if skybox_config.enabled else Skybox.PROCEDURAL_SET_ID
	)
	var selected_index: int = ids.find(selected_id)
	option.selected = selected_index if selected_index >= 0 else 0

	option.item_selected.connect(func(index: int) -> void:
		apply_skybox_set(ids[index])
	)
	row.add_child(_in_control_column(option))

	return row


## Writes the owner's dropdown pick onto the shared skybox_config (so it
## round-trips through Save override/Reset/Copy exactly like every other
## tunable -- see config/SkyboxConfig.gd's own DECISION) and then pushes it
## onto every live Skybox the same "every live instance already in the tree"
## way apply_physics_live()/apply_camera_tuning_live()/
## refresh_territory_visuals_live() already do via their own TUNING_GROUPs --
## a no-op push (but not a no-op write) in a bare-panel test with no Skybox in
## the tree, the same contract those three already have. Public so a test can
## drive it without a real OptionButton.
func apply_skybox_set(set_id: String) -> void:
	if set_id == Skybox.PROCEDURAL_SET_ID:
		skybox_config.enabled = false
	else:
		skybox_config.default_set = set_id
		skybox_config.enabled = true
	for node: Node in get_tree().get_nodes_in_group(Skybox.TUNING_GROUP):
		var skybox: Skybox = node as Skybox
		if skybox != null:
			skybox.apply_set(set_id)


func _physics_preset_resource(preset_id: String) -> PhysicsTuning:
	for preset: Dictionary in PHYSICS_PRESETS:
		if String(preset["id"]) == preset_id:
			return load(String(preset["path"])) as PhysicsTuning
	return null


## Pushes physics_tuning onto every Block already standing (BlockFactory.
## build() already reads it for anything spawned from here on). Public so a
## test can drive it directly instead of dragging a real slider.
func apply_physics_live() -> void:
	if is_instance_valid(_field) and _field.physics_material_override != null:
		_field.physics_material_override.friction = physics_tuning.disk_friction
	for node: Node in get_tree().get_nodes_in_group(Block.TUNING_GROUP):
		var block: Block = node as Block
		if block != null:
			block.apply_physics_tuning(physics_tuning)


## Pushes camera_tuning's follow_distance/follow_pitch_deg onto every live
## CameraRig immediately (Bontago-mv0.20b). Iterates CameraRig.TUNING_GROUP --
## the same "every live instance already in the tree" idiom apply_physics_
## live() uses for Block.TUNING_GROUP -- rather than this panel's own
## _camera_rig reference, so the push still reaches a rig in a bare-panel
## test that never called set_camera_rig(). Public so a test can drive it
## directly instead of dragging a real slider.
func apply_camera_tuning_live() -> void:
	for node: Node in get_tree().get_nodes_in_group(CameraRig.TUNING_GROUP):
		var rig: CameraRig = node as CameraRig
		if rig != null:
			rig.apply_follow_tuning()


## Pushes territory_visuals onto the wired Field's TerritoryOverlay shader
## immediately, and re-applies the same resource's reflection-probe/SSR
## fields onto every live Skybox (Bontago-xtq.12 step 2: those two only ever
## ran once at boot otherwise -- see game/Skybox.gd's refresh_from_visuals()
## doc). Iterates Skybox.TUNING_GROUP the same "every live instance already
## in the tree" idiom apply_camera_tuning_live()/apply_physics_live() use
## right above, so this half of the push works even in a bare-panel test
## that never wired a Field. The overlay half stays a no-op if this panel was
## never wired to a Field (a bare unit-test instance, or a moment before
## set_field() has run).
func refresh_territory_visuals_live() -> void:
	if _field != null:
		var overlay: TerritoryOverlay = _field.overlay()
		if overlay != null:
			overlay.refresh_visual_uniforms()
	for node: Node in get_tree().get_nodes_in_group(Skybox.TUNING_GROUP):
		var skybox: Skybox = node as Skybox
		if skybox != null:
			skybox.refresh_from_visuals()


## Bontago-xtq.36: pushes sky_theme onto every live Skybox's own public
## re-apply method (game/Skybox.gd's apply_theme(), the same seam
## apply_skybox_set() above already calls it through -- see that function
## and Skybox.apply_theme()'s own doc). Iterates Skybox.TUNING_GROUP, the same
## "every live instance already in the tree" idiom apply_camera_tuning_live()/
## refresh_territory_visuals_live() use, so this reaches a Skybox even in a
## bare-panel test. Known gap (not fixed here -- Skybox.gd isn't an owned
## file and apply_theme() doesn't touch it): Skybox._spawn_fog_volume() reads
## cloud_deck_size_m/cloud_deck_height_m/fog_density/fog_color only once, at
## _ready(), to build the FogVolume child's own size/position/FogMaterial --
## apply_theme() doesn't resync those, so an edit to one of those four fields
## only affects a Skybox that hasn't spawned its FogVolume yet.
func apply_sky_theme_live() -> void:
	for skybox: Skybox in _live_skyboxes():
		# Bontago-59o.18 (U1): a running cycle owns a live duplicate of the
		# source themes; apply_theme(sky_theme) would swap it for the static
		# material, so the edit is re-copied into the duplicate instead.
		if skybox.is_cycle_active():
			skybox.refresh_cycle_sources()
		else:
			skybox.apply_theme(sky_theme)


## Bontago-mp0.83 (owner playtest 2026-10-03: "control day/night length in F4"):
## pushes the Sky tab's cycle_length_seconds onto every live Skybox running a
## CYCLE match. Skybox re-bases its phase so the time of day does not jump.
## Local dev tuning only: nothing is replicated.
func apply_cycle_length_live() -> void:
	for node: Node in get_tree().get_nodes_in_group(Skybox.TUNING_GROUP):
		var skybox: Skybox = node as Skybox
		if skybox != null:
			skybox.set_cycle_length_seconds(sky_theme.cycle_length_seconds)


# --- Reset / Save / Copy -----------------------------------------------------

func _on_reset_pressed() -> void:
	reset_all()
	_status_label.text = "Reset to file."


## Reloads every tuning resource's fields from its .tres on disk, onto the
## *same* live instance (never replacing the reference every other system
## already holds -- see ResourceLoader.CACHE_MODE_IGNORE's use in
## _reset_resource()). Public so a test can call it without a real Button.
func reset_all() -> void:
	# Bontago-59o.18 (U1): the shipped theme_name is the static "sunset"; applying
	# it would turn a running cycle (the default sky) into the static theme.
	var cycle_was_active: bool = _any_cycle_active()
	_reset_resource(camera_tuning)
	_reset_resource(ghost_tuning)
	_reset_resource(physics_tuning)
	_reset_resource(territory_tuning)
	_reset_resource(territory_visuals)
	_reset_resource(block_feed_config)
	_reset_resource(skybox_config)
	# Bontago-1pi.1 (owner playtest: "Sky settings in F4 doesn't reset"):
	# sky_theme was the one preloaded tuning resource this loop never
	# touched -- Bontago-xtq.36's own DECISION (this file's class doc)
	# deliberately left it, along with Save/Copy/apply_saved_overrides, out
	# of this roster as "a reasonable small follow-up, not done here". Reset
	# is that follow-up; Save/Copy/apply_saved_overrides are unaffected
	# (still out of scope -- not what the owner reported).
	_reset_resource(sky_theme)
	for theme_id: String in Skybox.list_available_themes():
		_reset_resource(Skybox.load_theme(theme_id))
	apply_physics_live()
	refresh_territory_visuals_live()
	apply_skybox_set(skybox_config.default_set if skybox_config.enabled else Skybox.PROCEDURAL_SET_ID)
	if cycle_was_active:
		apply_sky_theme_live()
	elif not apply_sky_theme_id(skybox_config.theme_name):
		apply_sky_theme_live()
	rebuild()


func _reset_resource(resource: Resource) -> void:
	if resource == null or resource.resource_path.is_empty():
		return
	var fresh: Resource = ResourceLoader.load(resource.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if fresh == null:
		return
	for prop: Dictionary in resource.get_property_list():
		if not _is_exported_field(prop):
			continue
		var prop_name: String = str(prop.get("name", ""))
		resource.set(prop_name, fresh.get(prop_name))


func _on_save_pressed() -> void:
	var err: Error = save_overrides()
	_status_label.text = "Saved to %s." % save_path() if err == OK else "Save failed (%d)." % err


## Writes every exported float/int/bool/Color field of every tuning resource
## into user://tuning_overrides.cfg (one ConfigFile section per resource
## class). Public so a test can drive/verify it without a real Button.
## Bontago-xtq.13: loads whatever is already on disk first -- a fresh
## ConfigFile here would silently drop the selected-tab section
## _save_selected_tab_index() writes on its own, independent schedule.
func save_overrides() -> Error:
	if not UserPaths.persistence_allowed():
		return ERR_UNAVAILABLE
	var config: ConfigFile = ConfigFile.new()
	config.load(save_path())
	_write_overrides(config, "CameraTuning", camera_tuning)
	_write_overrides(config, "GhostTuning", ghost_tuning)
	_write_overrides(config, "PhysicsTuning", physics_tuning)
	_write_overrides(config, "TerritoryTuning", territory_tuning)
	_write_overrides(config, "TerritoryVisuals", territory_visuals)
	_write_overrides(config, "BlockFeedConfig", block_feed_config)
	_write_overrides(config, "SkyboxConfig", skybox_config)
	return config.save(save_path())


## Bontago-xtq.22: TYPE_STRING joins the allowed set here (and in
## _copy_section() below) so config/SkyboxConfig.gd's `default_set` --
## the F4 Skybox row's own value, not reflection-built and so never reaching
## either function through a Control -- still round-trips through Save
## override/Copy the same as every BOOL/INT/FLOAT/COLOR field already does.
## No existing resource this panel writes had a String field before, so nothing
## else changes behavior.
func _write_overrides(config: ConfigFile, section: String, resource: Resource) -> void:
	if resource == null:
		return
	for prop: Dictionary in resource.get_property_list():
		if not _is_exported_field(prop):
			continue
		var type: int = int(prop.get("type", TYPE_NIL))
		if (
			type != TYPE_BOOL and type != TYPE_INT and type != TYPE_FLOAT
			and type != TYPE_COLOR and type != TYPE_STRING
		):
			continue
		var prop_name: String = str(prop.get("name", ""))
		config.set_value(section, prop_name, resource.get(prop_name))


## Loads user://tuning_overrides.cfg (if any) onto the shared preloaded
## tuning singletons, before anything else in the game reads them. Called
## once by game/Main.gd's _ready(), first thing (Bontago-mv0.18's boot hook).
## Static and free of any node/scene-tree dependence, so it runs before a
## TuningPanel -- or even a Field/CameraRig/PlayerController -- exists.
static func apply_saved_overrides() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(save_path()) != OK:
		return
	_apply_saved_section(config, "CameraTuning", load("res://config/camera_tuning.tres"))
	_apply_saved_section(config, "GhostTuning", load("res://config/ghost_tuning.tres"))
	_apply_saved_section(config, "PhysicsTuning", load("res://config/physics_tuning.tres"))
	_apply_saved_section(config, "TerritoryTuning", load("res://config/territory_tuning.tres"))
	_apply_saved_section(config, "TerritoryVisuals", load("res://config/territory_visuals.tres"))
	_apply_saved_section(config, "BlockFeedConfig", load("res://config/block_feed.tres"))
	_apply_saved_section(config, "SkyboxConfig", load("res://config/skybox_config.tres"))


static func _apply_saved_section(config: ConfigFile, section: String, resource: Resource) -> void:
	if resource == null or not config.has_section(section):
		return
	# A stale key from an older build (a renamed/removed field) must not
	# reach Object.set() -- collect the resource's own current field names
	# first rather than trusting whatever the file on disk happens to say.
	var valid_props: Dictionary = {}
	for prop: Dictionary in resource.get_property_list():
		valid_props[str(prop.get("name", ""))] = true
	for key: String in config.get_section_keys(section):
		if not valid_props.has(key):
			continue
		resource.set(key, config.get_value(section, key))


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(build_copy_text())
	_status_label.text = "Copied."


## The current value of every exported float/int/bool/Color field of every
## tuning resource, formatted as ".tres"-style `name = value` lines grouped
## under a "# ClassName" header per resource -- meant to be pasted straight
## into the matching config/*.tres file. Public (and split from
## _on_copy_pressed(), which also touches the real clipboard) so a test can
## check its content headlessly.
func build_copy_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(_copy_section("CameraTuning", camera_tuning))
	parts.append(_copy_section("GhostTuning", ghost_tuning))
	parts.append(_copy_section("PhysicsTuning", physics_tuning))
	parts.append(_copy_section("TerritoryTuning", territory_tuning))
	parts.append(_copy_section("TerritoryVisuals", territory_visuals))
	parts.append(_copy_section("BlockFeedConfig", block_feed_config))
	parts.append(_copy_section("SkyboxConfig", skybox_config))
	return "\n\n".join(parts)


func _copy_section(section: String, resource: Resource) -> String:
	if resource == null:
		return "# %s\n(none)" % section
	var lines: PackedStringArray = PackedStringArray(["# %s" % section])
	for prop: Dictionary in resource.get_property_list():
		if not _is_exported_field(prop):
			continue
		var type: int = int(prop.get("type", TYPE_NIL))
		if (
			type != TYPE_BOOL and type != TYPE_INT and type != TYPE_FLOAT
			and type != TYPE_COLOR and type != TYPE_STRING
		):
			continue
		var prop_name: String = str(prop.get("name", ""))
		lines.append("%s = %s" % [prop_name, _format_value(resource.get(prop_name), type)])
	return "\n".join(lines)


func _format_value(value: Variant, type: int) -> String:
	match type:
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			var text: String = str(float(value))
			return text if (text.contains(".") or text.contains("e")) else "%s.0" % text
		TYPE_COLOR:
			var c: Color = value
			return "Color(%s, %s, %s, %s)" % [c.r, c.g, c.b, c.a]
		TYPE_STRING:
			return "\"%s\"" % String(value)
		_:
			return str(value)
