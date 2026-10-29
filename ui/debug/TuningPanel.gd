class_name TuningPanel
extends CanvasLayer
## In-game tuning panel: sliders over the camera, physics and visual tuning Resources so they can
## be adjusted while playing.
##
## Tabs are built by reflection over a live tuning Resource's @export fields
## (Resource.get_property_list(), filtered to the four types a control exists for below) rather
## than one hand-authored row per field, so a config Resource's whole surface is reachable without
## a code change per field. Which resources sit on which tab is _tab_plan().
##
## Every control writes straight onto the *live* resource instance the rest of the game already
## reads: every `@export var tuning: ... = preload(...)` resolves to the same cached Resource, so
## there is no copy step and a field read every frame is felt on the next read. Resources
## preloaded here by path are the same instance their consumer's preload yields. Fields read only
## once, at construction time, need an explicit push:
##
##   - PhysicsTuning: apply_physics_live() re-applies damping/material/gravity onto every Block
##     already standing (Block.apply_physics_tuning(), via the "tuning_blocks" group).
##     BlockFactory.build() already reads the same tuning for new spawns.
##   - TerritoryVisuals: refresh_territory_visuals_live() calls
##     TerritoryOverlay.refresh_visual_uniforms() (shader uniforms only configure() set, and the
##     disk mesh when disk_mesh_segments changed) and Skybox.refresh_from_visuals() on every rig in
##     Skybox.TUNING_GROUP (reflection probe / SSR fields).
##   - CameraTuning: apply_camera_tuning_live() calls CameraRig.apply_follow_tuning() on every rig
##     in CameraRig.TUNING_GROUP, re-snapshotting follow_distance/follow_pitch_deg (clamped, as
##     _ready() does) without disturbing a manual orbit/zoom.
##   - Sky tab: edits SkyCycleDef (sky_cycle), its two day SkyKeyframes, the SkyNightKeyframe and the
##     storm SkyOverlayDef. Every edit copies the cycle's own fields onto each live Skybox's sky_def
##     and calls Skybox.refresh_sky_def() on every rig in Skybox.TUNING_GROUP (the keyframes are
##     shared sub-resources, so they need no copy); cycle_length_seconds keeps its own seam
##     (apply_cycle_length_live). The Time-of-day row (Running / Sunset / Dawn / Night / Custom + a
##     0..1 phase slider) locks the cycle through Skybox.set_locked_phase(). Local dev tuning:
##     nothing is replicated.
##
## BlockVisualTuning, BlockEffectsConfig, BeaconVisualTuning, CameraShakeConfig and
## HUDVisualTuning need no such hook: CameraShakeConfig/BlockEffectsConfig are read live per
## frame/event, and BlockVisualTuning/BeaconVisualTuning/HUDVisualTuning are baked once at
## construction (a block's toon material, a beacon's geometry, a HUD panel's StyleBoxFlat), so an
## edit takes effect for anything built from here on (see _on_field_changed()).
## DECISION: these five resources are not added to reset_all() / save_overrides() /
## TuningOverrides.copy_text() / TuningOverrides.apply_saved() below.
##
## Toggled by the tuning_panel_toggle Input Map action (F4; gamepad pause_menu[Start] + X). While
## open: the mouse is released and gameplay input is suppressed (PlayerController.input_enabled).
##
## Availability: open offline (sandbox or tutorial) and by the host in a networked match; a client
## only sees the client-visible tabs. Net.is_host() is already true offline, so it is the one
## predicate to gate on. Editing Physics/Territory/Feed on a client would be inert anyway (a
## client's bodies are frozen and moved by net/SnapshotSync.gd), not just hidden for tidiness.

const SAVE_PATH: String = TuningOverrides.SAVE_PATH


## The file actually read/written: SAVE_PATH, or a per-PID file in a GUT run so
## tests never touch the owner's real F4 overrides.
static func save_path() -> String:
	return TuningOverrides.save_path()

const VALUE_WIDTH: float = 110.0

## The F4 panel is a bottom dock. It takes this fraction of the logical viewport height (the arena
## centre stays visible above it at any resolution; the project stretch rule keeps the logical
## viewport 1280x720 or wider), inset by DOCK_MARGIN_PX.
const DOCK_HEIGHT_FRACTION: float = 0.42
const DOCK_MARGIN_PX: float = 8.0
const DOCK_PLATE_ALPHA: float = 0.9
const DOCK_THEME: Theme = preload("res://ui/theme/stackfall_theme.tres")

## The selected-tab memory shares SAVE_PATH with every tuning resource's own override section (one
## ConfigFile, one section per concern) rather than a second settings file.
const SELECTED_TAB_SECTION: String = "TuningPanel"
const SELECTED_TAB_KEY: String = "selected_tab"

## DECISION (ui/debug/TuningPanel.gd): a wide name/description column so a whole one-sentence
## description fits under the field name in at most a couple of lines at 1080p.
const NAME_COLUMN_WIDTH: float = 380.0
## DECISION: description and default-value labels use the
## theme's CaptionLabel variation (dust ink at caption size, 13 px) instead of a private colour
## and a smaller font, so the sentence reads as a sub-label and the name stays the primary line.
const CAPTION_THEME_VARIATION: StringName = &"CaptionLabel"
const MODIFIED_MARKER: String = "• "

## Tabs whose content is hidden from a client (see class doc "Availability"). Indices match the
## order rebuild() adds tabs in: every client-visible tab (the SFX tab too, audio is local) comes
## first so this one cutoff holds; Physics/Territory/Feed (host-only: they tune the simulation
## itself, not just how it looks) always come last.
const CLIENT_HIDDEN_TAB_FIRST: int = 7
## The Field-only arena look tab, inserted after Territory look.
const ARENA_TAB: String = "Arena"
const ARENA_TAB_INDEX: int = 4
const ARENA_STYLE_PROP: String = "style"
## Dropdown labels, indexed by ArenaSideStyle.Style.
const ARENA_STYLE_NAMES: PackedStringArray = ["Current", "Layered plates", "Rocky island", "Machined disc", "Stylised machined", "Detailed machined", "Heavy machined", "Monolith", "Tapered strata", "Plated dome", "Shader dome"]

## Physics tab presets: the preset dropdown copies one of these PhysicsTuning resources' every
## exported field onto the live physics_tuning instance (apply_physics_preset()). "heavy_bouncy" is
## byte-identical to config/physics/physics_tuning.tres's defaults, so picking it is a no-op;
## "current" keeps the previous default numbers. The heavy_* presets raise cube_mass and
## gravity_multiplier and set rebound_damping below 1 so a flat drop doesn't bounce straight back
## up (see PhysicsTuning's rebound_damping DECISION and Block._damp_rebound()); "_bouncy" leans on
## block_bounce for liveliness, "_damped" on higher linear/angular damping. Exact numbers:
## config/physics/presets/*.tres.
const PHYSICS_PRESETS: Array[Dictionary] = [
	{"id": "current", "label": "Previous default", "path": "res://config/physics/presets/current.tres"},
	{"id": "heavy_bouncy", "label": "Heavy & Bouncy", "path": "res://config/physics/presets/heavy_bouncy.tres"},
	{"id": "heavy_damped", "label": "Heavy & Damped", "path": "res://config/physics/presets/heavy_damped.tres"},
	# Source material/damping defaults; Jolt solver and sleep remain unchanged.
	{"id": "tokamak_defaults", "label": "Tokamak defaults (Jolt)", "path": "res://config/physics/presets/tokamak_defaults.tres"},
	{"id": "original_feel", "label": "Original feel (experimental)", "path": "res://config/physics/presets/original_feel.tres"},
]

## Time-of-day row choices, index-parallel to TIME_OF_DAY_LABELS. The three
## concrete ids are SkyCycleDef.locked_phase_for() keys (MatchConfig.SKY_THEME_IDS).
const TIME_RUNNING: String = "running"
const TIME_CUSTOM: String = "custom"
const TIME_OF_DAY_CHOICES: PackedStringArray = ["running", "sunset", "dawn", "night", "custom"]
const TIME_OF_DAY_LABELS: PackedStringArray = ["Running", "Sunset", "Dawn", "Night", "Custom"]
## A live locked phase within this of a preset's phase reads as that preset.
const TIME_OF_DAY_PHASE_EPSILON: float = 0.001
## Sky tab section heading prefixes: the day keyframes by position, the night keyframe, the overlay.
const SKY_TAG_DAY_KEYS: PackedStringArray = ["Day key", "Evening key"]
const SKY_TAG_NIGHT: String = "Night key"
const SKY_TAG_STORM: String = "Storm"
const TIME_OF_DAY_SLIDER_STEP: float = 0.005
## Custom slider seed when no live cycle can report its phase (0.25 = noon).
const TIME_OF_DAY_DEFAULT_CUSTOM_PHASE: float = 0.25
const TIME_OF_DAY_SLIDER_MIN_WIDTH: float = 160.0
const TIME_OF_DAY_VALUE_FORMAT: String = "%.3f"

## Rows sit in foldable sections (hints.sections); a section is open by default only when it is
## the first one on its tab, and the open/closed choice survives rebuild() (see _fold_open).
const SECTION_OPEN_MARK: String = "▾ "
const SECTION_CLOSED_MARK: String = "▸ "
## Gap between the columns of a row: name | control | value | default.
const ROW_SEPARATION: int = 12
## Every row's control column has at least this width (slider, spinbox, toggle, swatch, dropdown),
## so the value and default columns line up on every tab; it takes the spare row width,
## identically on every row.
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

@export var hints: TuningPanelHints = preload("res://config/ui/tuning_panel_hints.tres")

var camera_tuning: CameraTuning = preload("res://config/player/camera_tuning.tres")
var ghost_tuning: GhostTuning = preload("res://config/blocks/tuning/ghost_tuning.tres")
var physics_tuning: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
var territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var territory_visuals: TerritoryVisuals = preload("res://config/territory/territory_visuals.tres")
var block_feed_config: BlockFeedConfig = preload("res://config/match/block_feed.tres")

## The same preloaded singleton game/sky/Skybox.gd's `config` defaults to, so this panel and every
## live Skybox read and write one Resource instance.
var skybox_config: SkyboxConfig = preload("res://config/sky/skybox_config.tres")

## The art-direction tunables: each preloads the identical path its own consumer preloads/exports
## (BlockFactory.gd's VISUAL_TUNING, BlockEffectsManager.config, HomeFlag.beacon_visuals,
## CameraRig.shake_config, Skybox.sky_def), so the per-path Resource cache makes every field here the
## same live object those scripts read.
var block_visual_tuning: BlockVisualTuning = preload("res://config/blocks/tuning/block_visual_tuning.tres")
var block_effects_config: BlockEffectsConfig = preload("res://config/blocks/tuning/block_effects.tres")
var beacon_visual_tuning: BeaconVisualTuning = preload("res://config/territory/beacon_visual_tuning.tres")
var camera_shake_config: CameraShakeConfig = preload("res://config/physics/camera_shake.tres")
var hud_visual_tuning: HUDVisualTuning = preload("res://config/ui/hud_visual_tuning.tres")
## The arena side/underside look. set_field() swaps it for the wired Field's own instance (the one
## TerritoryOverlay builds from); the Arena tab only exists while a Field is wired.
var arena_side_style: ArenaSideStyle = preload("res://config/territory/arena_side_style.tres")
## Opt-in QoL experiments (host snapshots them at match start).
var qol_experiments: QolExperiments = preload("res://config/match/qol_experiments.tres")
## The bots' tower-statics tunables: the same cached instance core/ai/BotEvaluator.stack_tuning reads
## on every think, so an edit here reaches the next bot evaluation.
var bot_stack_tuning: BotStackTuning = preload("res://config/bots/bot_stack_tuning.tres")
## the SFX tab edits the live AudioConfig autoload/Sfx.gd reads (the same cached
## preload instance, so no copy step; Reset/tests restore the shipped file values).
var audio_config: AudioConfig = preload("res://config/audio/audio_config.tres")
## The Sky tab's resources: the one cycle definition (its day keyframes and night keyframe are
## sub-resources of it) and the storm overlay. Preloaded, so a later Skybox copies the edited values.
var sky_cycle: SkyCycleDef = preload("res://config/sky/sky_cycle.tres")
var storm_overlay: SkyOverlayDef = preload("res://config/sky/storm_overlay.tres")

## DECISION (ui/debug/TuningPanel.gd): same `Variant` test seam as ui/debug/NetDebugOverlay.gd's
## net_provider; GUT cannot double the plain Net autoload.
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

## Open/closed state of each foldable section ("Class/Title" -> bool), kept
## across rebuild() and panel re-opens for the whole session.
static var _fold_open: Dictionary = {}

var _tab_container: TabContainer = null
var _status_label: Label = null

## The last tab index the owner picked, restored onto _tab_container every rebuild() (which
## replaces every tab page and would reset current_tab to 0) and persisted into SAVE_PATH's own
## ConfigFile so it survives an app restart.
var _selected_tab_index: int = 0

## True only while rebuild() is (re)populating _tab_container. Adding the *first* child tab to an
## emptied TabContainer auto-selects it and fires tab_changed(0) synchronously; without this guard
## that event reached _on_tab_changed() and reset _selected_tab_index to 0 before rebuild()'s
## explicit restore ran.
var _rebuilding_tabs: bool = false

## Tab pages not yet filled: scroll page -> {"name", "resources"}. A page's rows are built the first
## time its tab is shown (_build_tab_if_pending), then kept until the next rebuild().
var _pending_tabs: Dictionary = {}

## The Sky tab's Time-of-day row state (TIME_OF_DAY_CHOICES
## entry, and the phase the Custom slider holds). Session-local: only
## skybox_config.theme_name = "cycle" persists.
## The shipped sky_cycle.tres loaded fresh once per rebuild: the baseline of the cycle's own fields
## and of its keyframes (sub-resources have no file of their own to reload).
var _fresh_sky_cycle: SkyCycleDef = null
var _time_of_day_choice: String = TIME_RUNNING
var _time_of_day_custom_phase: float = TIME_OF_DAY_DEFAULT_CUSTOM_PHASE


func _ready() -> void:
	visible = false
	net_provider = Net
	# DECISION: the tab UI (each tab's rows on its first show) is built on first open by rebuild() (or an explicit call, which
	# tests use) and freed on close by _free_ui(), so a hidden panel costs no nodes. Saved overrides
	# apply via the static TuningOverrides.apply_saved() at boot and never needed this UI.
	_selected_tab_index = _load_selected_tab_index()


# --- Wiring (game/main/LocalPlayer.gd / game/player/SpectatorController.gd) ------------

## Called once by game/main/LocalPlayer.gd: the controller whose Controls/Physics tabs this panel
## reads (both fields default to the same preloaded singletons a bare test constructs this panel
## with).
func set_controller(controller: PlayerController) -> void:
	_controller = controller
	if controller != null:
		ghost_tuning = controller.ghost_tuning
		physics_tuning = controller.tuning
	_rebuild_if_built()


## Called by game/main/LocalPlayer.gd and game/player/SpectatorController.gd with the shared CameraRig.
func set_camera_rig(rig: CameraRig) -> void:
	_camera_rig = rig
	if rig != null:
		camera_tuning = rig.tuning
	_rebuild_if_built()


## Called by game/main/LocalPlayer.gd and game/player/SpectatorController.gd with the shared Field, for the
## Territory tab and refresh_territory_visuals_live()'s overlay push.
func set_field(field: Field) -> void:
	_field = field
	if field != null:
		territory_tuning = field.territory_tuning
		territory_visuals = field.visuals
		if field.arena_side_style != null:
			arena_side_style = field.arena_side_style
	_rebuild_if_built()


# --- Toggle (F4 / gamepad Start+X) -------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"tuning_panel_toggle"):
		return
	# the F4 panel is debug-only (game/debug/DebugMode.gd).
	if not DebugMode.is_enabled():
		return
	# The gamepad half of this action is bound to X alone, which is also hover_lower, so a joypad
	# press only counts as the toggle while pause_menu (Start) is also held (the Start+X chord). A
	# keyboard press (F4) needs no modifier.
	if event is InputEventJoypadButton and not Input.is_action_pressed(&"pause_menu"):
		return
	_toggle_panel()
	get_viewport().set_input_as_handled()


## The gate outlives this panel (it lives on the CameraRig), so a panel open at match end
## must not leave the next match with PANEL set.
func _exit_tree() -> void:
	if is_instance_valid(_controller):
		_controller.input_gate.set_blocker(InputGate.Blocker.PANEL, false)


func _toggle_panel() -> void:
	visible = not visible
	if not visible:
		_free_ui()
	if _controller != null:
		_controller.input_gate.set_blocker(InputGate.Blocker.PANEL, visible)
	AgentProbe.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED)
	if visible:
		# Reflects anything another system changed on the live resources since this panel last
		# opened (a match restart's fresh MatchConfig). rebuild() also restores _selected_tab_index,
		# so a close/reopen in the same session lands back on the tab that was open.
		rebuild()


# --- Tab memory (F4 remembers the last active tab) ----------

## TabContainer.tab_changed fires for a real click and for rebuild()'s programmatic current_tab
## restore alike; either way it is the tab to come back to, so it is remembered here. Only a click
## persists it (_on_tab_selected()).
func _on_tab_changed(index: int) -> void:
	if _rebuilding_tabs:
		return
	_selected_tab_index = index
	_build_tab_if_pending(index)


## TabContainer.tab_clicked fires only for a user click on the tab bar, never for programmatic
## current_tab sets or child add/remove, so this is the only place the tab index is persisted.
func _on_tab_selected(index: int) -> void:
	if _rebuilding_tabs:
		return
	_selected_tab_index = index
	_save_selected_tab_index()


## Loads just the persisted tab index from SAVE_PATH, if any; called once from _ready() so the very
## first open already restores it. Returns 0 with no saved file, an unreadable one, or no matching
## key.
func _load_selected_tab_index() -> int:
	var config: ConfigFile = ConfigFile.new()
	if config.load(save_path()) != OK:
		return 0
	if not config.has_section_key(SELECTED_TAB_SECTION, SELECTED_TAB_KEY):
		return 0
	return int(config.get_value(SELECTED_TAB_SECTION, SELECTED_TAB_KEY, 0))


## Writes just the selected-tab section into SAVE_PATH, loading whatever is already on disk first
## so it never clobbers the tuning-override sections a "Save override" click wrote, and vice
## versa: both share one file, one section per concern.
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
	# A docked bottom plate (disc-900 plate, theme fonts) rather than a near-fullscreen sheet, so the
	# arena above it stays visible while a value is dragged. The tab pages scroll inside the
	# remaining height.
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.anchor_top = 1.0 - DOCK_HEIGHT_FRACTION
	panel.offset_left = DOCK_MARGIN_PX
	panel.offset_top = 0.0
	panel.offset_right = -DOCK_MARGIN_PX
	panel.offset_bottom = -DOCK_MARGIN_PX
	panel.theme = DOCK_THEME
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var backing: StyleBoxFlat = MenuStyleFactory.make_plate(Color(arcade.disc_900_color, DOCK_PLATE_ALPHA))
	backing.set_corner_radius_all(arcade.radius_block_px)
	backing.shadow_size = 0
	backing.content_margin_left = float(arcade.space_4_px)
	backing.content_margin_right = float(arcade.space_4_px)
	backing.content_margin_top = float(arcade.space_1_px)
	backing.content_margin_bottom = float(arcade.space_1_px)
	panel.add_theme_stylebox_override("panel", backing)
	add_child(panel)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	panel.add_child(layout)

	var title: Label = Label.new()
	title.text = "Tuning panel (F4 / gamepad Start+X)"
	layout.add_child(title)

	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Fires for a real click and for rebuild()'s programmatic restore below: either way, whatever
	# tab is showing is what the next close/reopen (or app restart) should return to.
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


## Frees the whole tab UI. _rows is cleared with it so no stale control references survive; the
## selected tab index is already remembered by _on_tab_changed().
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
	_pending_tabs.clear()


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
	_pending_tabs.clear()
	_fresh_sky_cycle = null

	var plan: Array[Dictionary] = _tab_plan()
	for entry: Dictionary in plan:
		_add_tab(String(entry["name"]), entry["resources"] as Array)

	_apply_availability()

	# rebuild() just replaced every tab page (a fresh TabContainer would land on tab 0): restore the
	# owner's last tab, clamped in case a stale saved index no longer fits (e.g. a client's
	# hidden-tab availability changed the count).
	if _tab_container.get_tab_count() > 0:
		_tab_container.current_tab = clampi(_selected_tab_index, 0, _tab_container.get_tab_count() - 1)
		_build_tab_if_pending(_tab_container.current_tab)
	_rebuilding_tabs = false


## Tabs follow what a tuner thinks about, not which Resource a
## field lives in. Client-visible (look/feel) tabs first, host-only simulation
## tabs last (CLIENT_HIDDEN_TAB_FIRST). A resource listed on two tabs (Ghost)
## splits by section: hints.section_tabs names the sections that move to the
## later tab, the rest stay on the resource's first tab.
## DECISION: TerritoryVisuals is purely visual, so it sits with the beacons on a
## client-visible tab instead of the host-only Territory rules.
func _tab_plan() -> Array[Dictionary]:
	var plan: Array[Dictionary] = _base_tab_plan()
	if _field != null and arena_side_style != null:
		# client-visible look tab, right after Territory look.
		plan.insert(ARENA_TAB_INDEX, {"name": ARENA_TAB, "resources": [arena_side_style]})
	return plan


func _base_tab_plan() -> Array[Dictionary]:
	return [
		{"name": "Camera", "resources": [camera_tuning, camera_shake_config]},
		{"name": "Controls", "resources": [ghost_tuning]},
		{"name": "Ghost & Blocks", "resources": [ghost_tuning, block_visual_tuning, block_effects_config]},
		{"name": "Territory look", "resources": [territory_visuals, beacon_visual_tuning]},
		{"name": "HUD", "resources": [hud_visual_tuning]},
		{"name": "Sky", "resources": _sky_resources()},
		{"name": TuningSfxTab.TAB_NAME, "resources": []},
		{"name": "Physics", "resources": [physics_tuning]},
		{"name": "Territory rules", "resources": [territory_tuning]},
		{"name": "Block bag", "resources": [block_feed_config]},
		{"name": "QoL", "resources": [qol_experiments]},
		{"name": "Bots", "resources": [bot_stack_tuning]},
	]


## The first plan tab listing `resource`: where its sections live unless
## hints.section_tabs moves them.
func _default_tab_for(resource: Resource) -> String:
	for entry: Dictionary in _tab_plan():
		if (entry["resources"] as Array).has(resource):
			return String(entry["name"])
	return ""


## Adds an empty page; its rows are built when the tab is first shown (_build_tab_if_pending).
func _add_tab(tab_name: String, resources: Array) -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = tab_name
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pending_tabs[scroll] = {"name": tab_name, "resources": resources}
	_tab_container.add_child(scroll)


func _build_tab_if_pending(index: int) -> void:
	var scroll: ScrollContainer = _tab_container.get_tab_control(index) as ScrollContainer
	if scroll == null or not _pending_tabs.has(scroll):
		return
	var pending: Dictionary = _pending_tabs[scroll]
	_pending_tabs.erase(scroll)
	_fill_tab(scroll, String(pending["name"]), pending["resources"] as Array)


func _fill_tab(scroll: ScrollContainer, tab_name: String, resources: Array) -> void:
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)

	var first_section: bool = true
	if tab_name == "Physics":
		var preset_rows: Array[Control] = [_build_physics_preset_row()]
		list.add_child(_build_section(HAND_BUILT_CLASS, PRESET_SECTION_TITLE, preset_rows, true))
		first_section = false
	if tab_name == "Sky":
		# Theme/Time/Weather/Breeze are one ordinary foldable section in the same grid as every
		# reflected row.
		var scene_rows: Array[Control] = [
			_build_time_of_day_row(),
			_build_weather_row(), _build_breeze_row(),
		]
		list.add_child(_build_section(HAND_BUILT_CLASS, SCENE_SECTION_TITLE, scene_rows, true))
		first_section = false

	if tab_name == TuningSfxTab.TAB_NAME:
		list.add_child(_build_sfx_section())

	for entry: Variant in resources:
		var resource: Resource = entry as Resource
		if resource == null:
			continue
		var built: Control = _build_resource_rows(resource, tab_name, first_section)
		if built.get_child_count() > 0:
			first_section = false
		list.add_child(built)

	scroll.add_child(list)


func _apply_availability() -> void:
	var full_access: bool = _has_full_access()
	# The Arena tab (Field wired) shifts the host-only tabs one place right.
	var first_hidden: int = CLIENT_HIDDEN_TAB_FIRST + (1 if _field != null and arena_side_style != null else 0)
	for index: int in range(first_hidden, _tab_container.get_tab_count()):
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
		if not TuningOverrides.is_exported_field(prop):
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
		var tag: String = _sky_section_tag(resource)
		var shown_title: String = title if tag.is_empty() else "%s: %s" % [tag, title]
		var fold_class: String = class_label if tag.is_empty() else "%s/%s" % [class_label, tag]
		list.add_child(_build_section(fold_class, shown_title, built, default_open))
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
	# DECISION: section headers take the arcade cream token (primary text).
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


## The baseline a row's "(default X)" label and yellow modified-highlight compare against. It is
## exactly what Reset
## restores: the shipped .tres loaded fresh (CACHE_MODE_IGNORE, never the
## cached live instance) when `resource` has a resource_path, so the label and
## highlight can never disagree with TuningOverrides.reset_resource(). Only a path-less
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
	var sky_shipped: Resource = _shipped_sky_counterpart(resource)
	if sky_shipped != null:
		return sky_shipped
	if not resource.resource_path.is_empty():
		var shipped: Resource = ResourceLoader.load(resource.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if shipped != null:
			return shipped
	if resource.get_script() == null:
		return null
	var script: Script = resource.get_script() as Script
	return script.new() as Resource


func _class_label_for(resource: Resource) -> String:
	if resource == null or resource.get_script() == null:
		return ""
	return String((resource.get_script() as Script).get_global_name())


func _build_row_control(resource: Resource, prop_name: String, type: int, class_label: String, fresh: Resource) -> Control:
	var default_value: Variant = fresh.get(prop_name) if fresh != null else resource.get(prop_name)
	if resource is ArenaSideStyle and prop_name == ARENA_STYLE_PROP:
		return _build_arena_style_row(resource, prop_name, class_label, default_value)
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
	# A text toggle ("On"/"Off", pressed = lit): a CheckButton's off state is a nearly invisible
	# dot.
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


## The arena style enum as a dropdown; picking one rebuilds the arena mesh live.
func _build_arena_style_row(resource: Resource, prop_name: String, class_label: String, default_value: Variant) -> Control:
	var option: OptionButton = OptionButton.new()
	option.name = "ArenaStyleOption"
	var keys: Array = ArenaSideStyle.Style.keys()
	for index: int in keys.size():
		option.add_item(ARENA_STYLE_NAMES[index], int(ArenaSideStyle.Style[keys[index]]))
	option.select(option.get_item_index(int(resource.get(prop_name))))
	var frame: Dictionary = _build_row_frame(prop_name, class_label, option, TYPE_INT, default_value, "", 0)
	var value_label: Label = frame["value_label"] as Label
	value_label.text = String(keys[int(resource.get(prop_name))])
	(frame["default_label"] as Label).text = DEFAULT_PREFIX + String(keys[int(default_value)])
	option.item_selected.connect(func(index: int) -> void:
		var id: int = option.get_item_id(index)
		resource.set(prop_name, id)
		value_label.text = String(keys[id])
		_on_field_changed(resource, prop_name)
	)
	_register_row(frame, resource, prop_name, option, default_value, TYPE_INT, "", 0)
	return frame["row"] as Control


## the SFX tab's one section: a dropdown + Play row per AudioConfig effect-file
## field (TuningSfxTab.sfx_fields). Registered in _rows like a reflected row, so the modified marker,
## default column, Reset and Save all work on it; the live config is what Sfx reads on the next event.
func _build_sfx_section() -> Control:
	var available: PackedStringArray = Sfx.effect_files()
	var rows: Array[Control] = []
	for prop_name: String in TuningSfxTab.sfx_fields(audio_config, available):
		rows.append(_build_sfx_row(prop_name, available))
	return _build_section(TuningSfxTab.CLASS_LABEL, TuningSfxTab.SECTION_TITLE, rows, true)


func _build_sfx_row(prop_name: String, available: PackedStringArray) -> Control:
	var fresh: Resource = _fresh_instance_for(audio_config)
	var default_value: Variant = fresh.get(prop_name) if fresh != null else audio_config.get(prop_name)
	var current: String = String(audio_config.get(prop_name))
	var choices: PackedStringArray = TuningSfxTab.ordered_choices(current, available)
	var holder: HBoxContainer = HBoxContainer.new()
	holder.add_theme_constant_override("separation", ROW_SEPARATION)
	var option: OptionButton = OptionButton.new()
	option.name = "SfxOption"
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for filename: String in choices:
		option.add_item(filename)
	option.select(maxi(choices.find(current), 0))
	holder.add_child(option)
	var play: Button = Button.new()
	play.name = "PlayButton"
	play.text = "Play"
	holder.add_child(play)
	var frame: Dictionary = _build_row_frame(prop_name, TuningSfxTab.CLASS_LABEL, holder, TYPE_STRING, default_value, "", 0)
	var value_label: Label = frame["value_label"] as Label
	value_label.text = current
	option.item_selected.connect(func(index: int) -> void:
		audio_config.set(prop_name, option.get_item_text(index))
		value_label.text = option.get_item_text(index)
		_on_field_changed(audio_config, prop_name)
	)
	play.pressed.connect(func() -> void: preview_sfx(prop_name))
	_register_row(frame, audio_config, prop_name, holder, default_value, TYPE_STRING, "", 0)
	return frame["row"] as Control


## Plays `prop_name`'s current file once through Sfx's own pool and volume. False for a missing file
## (or a field that is not an AudioConfig string). Public so a test can press Play without a Button.
func preview_sfx(prop_name: String) -> bool:
	var value: Variant = audio_config.get(prop_name)
	return value is String and Sfx.preview_file(String(value))


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
	# DECISION (ui/debug/TuningPanel.gd): step = 0 (continuous) rather than a fixed fraction of the
	# range: Range snaps `value` to the nearest multiple of `step` on assignment, which quantized
	# the row's initial display away from the field's real value (gravity_multiplier's exact 1.0
	# rendered as 0.999 with a 200-step range). Nothing here needs a coarse arrow-key increment.
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


## Re-derives one row's modified marker/colour from its resource's *current* value: called when a
## row is first built and again from _on_field_changed() every time a control writes its resource,
## so the marker updates live without a full rebuild(). The default column is static text.
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
		# DECISION: the owner-adjusted highlight is the arcade rim gold, so an
		# adjusted field stays unmistakable against the cream names and dust captions.
		name_label.add_theme_color_override("font_color", MenuStyleFactory.arcade_tuning().rim_color)
	else:
		name_label.remove_theme_color_override("font_color")


## `hints`'s per-field entry, or a fallback of [0, 4x current] derived from the field's current
## value.
func _range_for(class_label: String, prop_name: String, current: float) -> Vector2:
	var hinted: Vector2 = hints.range_for(class_label, prop_name) if hints != null else Vector2(NAN, NAN)
	if not (is_nan(hinted.x) or is_nan(hinted.y)):
		return hinted
	return _fallback_range(current)


## DECISION (ui/debug/TuningPanel.gd): the [0, 4x current] fallback degenerates for a field whose
## sane value sits at or below zero (an inverted or zero-width range), so a negative current
## mirrors the same magnitude below zero and a zero current gets a small symmetric default rather
## than a slider with nowhere to go.
func _fallback_range(current: float) -> Vector2:
	if current > 0.0:
		return Vector2(0.0, current * 4.0)
	elif current < 0.0:
		return Vector2(current * 4.0, 0.0)
	return Vector2(-1.0, 1.0)


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
	elif resource == arena_side_style:
		apply_arena_style_live()
	elif resource == camera_tuning:
		apply_camera_tuning_live()
	elif resource == block_visual_tuning:
		BlockFactory.refresh_visual_tuning()
	elif resource == beacon_visual_tuning:
		apply_beacon_tuning_live()
	elif _is_sky_resource(resource):
		# The day/night cycle length is a rate, not a look: it goes through its own seam so the time of
		# day stays put.
		if resource == sky_cycle and _prop_name == "cycle_length_seconds":
			apply_cycle_length_live()
		else:
			apply_sky_def_live()
			# Editing a preset's locked phase moves the sky now when that preset is the selected time of
			# day.
			if resource == sky_cycle and _prop_name.begins_with("cycle_locked_phase") and _time_of_day_choice != TIME_CUSTOM:
				_push_locked_phase(_phase_for_time_choice(_time_of_day_choice))
	# BlockVisualTuning (BlockFactory.refresh_visual_tuning()) and BeaconVisualTuning
	# (apply_beacon_tuning_live()) have live hooks. ghost_tuning / territory_tuning /
	# block_feed_config are read live each frame/tick; block_effects_config / camera_shake_config
	# are read live per event; hud_visual_tuning is baked at HUD build. A value write here still
	# takes effect for anything built from here on.


## The Physics tab's own preset row: a plain Control returned to _add_tab's caller, but not
## reflection-built and not registered in _rows, since it writes every field of physics_tuning at
## once.
func _build_physics_preset_row() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)

	var label: Label = Label.new()
	label.text = "Physics preset"
	label.custom_minimum_size = Vector2(NAME_COLUMN_WIDTH, 0.0)
	row.add_child(label)

	var option: OptionButton = OptionButton.new()
	# cube_mass only feeds BlockFactory.build()'s `mass = tuning.cube_mass * cube_count` at spawn
	# time; Block.apply_physics_tuning() (the live path a preset pick also runs) never touches an
	# existing body's `.mass`. So switching presets mid-match changes how heavy the NEXT block placed
	# is, not any block already standing.
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


## Loads `preset_id`'s config/physics/presets/*.tres and copies its every exported field onto the
## live physics_tuning instance, pushes it through apply_physics_live() and rebuild()s so every
## Physics slider shows the new values. A silent no-op for an id PHYSICS_PRESETS doesn't have.
## Public so a test can pick a preset without a real OptionButton.
func apply_physics_preset(preset_id: String) -> void:
	var preset: PhysicsTuning = _physics_preset_resource(preset_id)
	if preset == null:
		return
	for prop: Dictionary in preset.get_property_list():
		if not TuningOverrides.is_exported_field(prop):
			continue
		var prop_name: String = str(prop.get("name", ""))
		physics_tuning.set(prop_name, preset.get(prop_name))
	apply_physics_live()
	rebuild()


## the Sky tab's "Weather" dropdown -- "Schedule" (follow the
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


## F4 toggle for the always-on Breeze gust layer (host only, for
## testing; strength lives in config/breeze/breeze.tres). Clients see gusts through
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


# --- Sky tab: resources and live apply -----------------------------------------

## The Sky tab's resources in row order: the cycle, its day keyframes, the night keyframe, the storm
## overlay.
func _sky_resources() -> Array[Resource]:
	var found: Array[Resource] = [sky_cycle]
	for key: SkyKeyframe in sky_cycle.day_keyframes:
		found.append(key)
	if sky_cycle.night != null:
		found.append(sky_cycle.night)
	found.append(storm_overlay)
	return found


func _is_sky_resource(resource: Resource) -> bool:
	return resource != null and _sky_resources().has(resource)


func _day_key_index(resource: Resource) -> int:
	if resource is SkyKeyframe:
		return sky_cycle.day_keyframes.find(resource as SkyKeyframe)
	return -1


## The heading prefix that tells the day keyframes, the night keyframe and the overlay apart ("" for
## the cycle itself).
func _sky_section_tag(resource: Resource) -> String:
	if resource == null or resource == sky_cycle:
		return ""
	if resource == sky_cycle.night:
		return SKY_TAG_NIGHT
	if resource == storm_overlay:
		return SKY_TAG_STORM
	var index: int = _day_key_index(resource)
	if index < 0:
		return ""
	return SKY_TAG_DAY_KEYS[index] if index < SKY_TAG_DAY_KEYS.size() else "Day key %d" % (index + 1)


## The shipped value source for a Sky tab resource that has no file of its own (the cycle and its
## keyframes: sub-resources of sky_cycle.tres). Null for every other resource.
func _shipped_sky_counterpart(resource: Resource) -> Resource:
	if resource == null or not _is_sky_cycle_part(resource):
		return null
	var shipped: SkyCycleDef = _shipped_sky_cycle()
	if shipped == null:
		return null
	if resource == sky_cycle:
		return shipped
	if resource == sky_cycle.night:
		return shipped.night
	var index: int = _day_key_index(resource)
	if index >= 0 and index < shipped.day_keyframes.size():
		return shipped.day_keyframes[index]
	return null


func _is_sky_cycle_part(resource: Resource) -> bool:
	return resource == sky_cycle or resource == sky_cycle.night or _day_key_index(resource) >= 0


func _shipped_sky_cycle() -> SkyCycleDef:
	if _fresh_sky_cycle == null:
		_fresh_sky_cycle = ResourceLoader.load(sky_cycle.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as SkyCycleDef
	return _fresh_sky_cycle


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


## The Sky tab's "Time of day" row. Running / Sunset /
## Night / Custom (a 0..1 phase slider, editable for Custom only) drive the
## cycle through Skybox.set_locked_phase(); the row is disabled while a static
## sky is live (nothing to lock). Local dev tuning like the cycle length:
## nothing is replicated or persisted.
func _build_time_of_day_row() -> Control:
	_sync_time_of_day_from_live()
	var active: bool = _any_cycle_active()
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
		"slider is. Needs a running sky."
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


## The phase `choice` locks the cycle at; -1.0 for running (and for an
## unresolvable preset, which then leaves the cycle running).
func _phase_for_time_choice(choice: String) -> float:
	if choice == TIME_RUNNING:
		return -1.0
	if choice == TIME_CUSTOM:
		return _time_of_day_custom_phase
	return sky_cycle.locked_phase_for(choice)


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
	for choice: String in TIME_OF_DAY_CHOICES:
		var preset: float = sky_cycle.locked_phase_for(choice)
		if preset >= 0.0 and absf(preset - phase) <= TIME_OF_DAY_PHASE_EPSILON:
			return choice
	return TIME_CUSTOM


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


## Pushes camera_tuning's follow_distance/follow_pitch_deg onto every live CameraRig immediately.
## Iterates CameraRig.TUNING_GROUP rather than this panel's own _camera_rig, so a bare-panel test
## that never called set_camera_rig() still reaches a rig. Public so a test can drive it directly
## instead of dragging a real slider.
func apply_camera_tuning_live() -> void:
	for node: Node in get_tree().get_nodes_in_group(CameraRig.TUNING_GROUP):
		var rig: CameraRig = node as CameraRig
		if rig != null:
			rig.apply_follow_tuning()


## Pushes territory_visuals onto the wired Field's TerritoryOverlay shader immediately, and
## re-applies its reflection-probe/SSR fields onto every live Skybox (those only ran once at boot
## otherwise; see Skybox.refresh_from_visuals()). Iterates Skybox.TUNING_GROUP, so that half works
## in a bare-panel test; the overlay half is a no-op without a wired Field.
func refresh_territory_visuals_live() -> void:
	if _field != null:
		var overlay: TerritoryOverlay = _field.overlay()
		if overlay != null:
			overlay.refresh_visual_uniforms()
	for node: Node in get_tree().get_nodes_in_group(Skybox.TUNING_GROUP):
		var skybox: Skybox = node as Skybox
		if skybox != null:
			skybox.refresh_from_visuals()


## Rebuilds every HomeFlag/GoalFlag beacon in the tree from the
## edited beacon_visual_tuning (their geometry and materials are baked in _build()).
func apply_beacon_tuning_live() -> void:
	for node: Node in get_tree().get_nodes_in_group(HomeFlag.TUNING_GROUP):
		var flag: HomeFlag = node as HomeFlag
		if flag != null:
			flag.rebuild_beacon()


## Rebuilds the wired Field's arena mesh (top slab + side
## surfaces) from arena_side_style. Collision is a separate Field shape and is
## untouched; the territory material and its uniforms are kept by
## TerritoryOverlay.rebuild_disk_mesh(). No-op without a Field.
func apply_arena_style_live() -> void:
	if _field == null:
		return
	var overlay: TerritoryOverlay = _field.overlay()
	if overlay != null:
		overlay.rebuild_disk_mesh()


## Copies the cycle's plain fields onto every live Skybox's own sky_def copy (the keyframes, night
## and materials are shared sub-resources) and asks each Skybox to re-evaluate through
## refresh_sky_def(), so a palette edit shows on the next tick. Iterates Skybox.TUNING_GROUP, so it
## reaches a Skybox even in a bare-panel test.
func apply_sky_def_live() -> void:
	for skybox: Skybox in _live_skyboxes():
		if skybox.sky_def != null and skybox.sky_def != sky_cycle:
			_copy_plain_fields(sky_cycle, skybox.sky_def)
		skybox.refresh_sky_def()


func _copy_plain_fields(from: Resource, to: Resource) -> void:
	for prop: Dictionary in from.get_property_list():
		if not TuningOverrides.is_exported_field(prop):
			continue
		var type: int = int(prop.get("type", TYPE_NIL))
		if type == TYPE_BOOL or type == TYPE_INT or type == TYPE_FLOAT or type == TYPE_COLOR:
			var prop_name: String = str(prop.get("name", ""))
			to.set(prop_name, from.get(prop_name))


## Pushes the Sky tab's cycle_length_seconds onto every live Skybox running a CYCLE match. Skybox
## re-bases its phase so the time of day does not jump. Local dev tuning only: nothing is
## replicated.
func apply_cycle_length_live() -> void:
	for skybox: Skybox in _live_skyboxes():
		skybox.set_cycle_length_seconds(sky_cycle.cycle_length_seconds)


# --- Reset / Save / Copy -----------------------------------------------------

func _on_reset_pressed() -> void:
	reset_all()
	_status_label.text = "Reset to file."


## Reloads every tuning resource's fields from its .tres on disk, onto the
## *same* live instance (never replacing the reference every other system
## already holds -- see ResourceLoader.CACHE_MODE_IGNORE's use in
## TuningOverrides.reset_resource()). Public so a test can call it without a real Button.
func reset_all() -> void:
	for resource: Resource in _tuning_instances().values():
		TuningOverrides.reset_resource(resource)
	TuningOverrides.reset_resource(bot_stack_tuning)
	TuningSfxTab.reset_fields(audio_config)
	# The sky resources are reset too; Save/Copy/TuningOverrides.apply_saved still skip them.
	_fresh_sky_cycle = null
	_reset_sky_resources()
	apply_physics_live()
	refresh_territory_visuals_live()
	apply_arena_style_live()
	apply_sky_def_live()
	rebuild()


## Reloads the shipped values of the cycle, its keyframes, the night keyframe and the storm
## overlay. The keyframes are sub-resources, so they copy from a fresh load of sky_cycle.tres by
## position.
func _reset_sky_resources() -> void:
	for resource: Resource in _sky_resources():
		var shipped: Resource = _shipped_sky_counterpart(resource)
		if shipped == null:
			TuningOverrides.reset_resource(resource)
			continue
		for prop: Dictionary in resource.get_property_list():
			var type: int = int(prop.get("type", TYPE_NIL))
			# Sub-resources and the keyframe array stay the live objects; only plain values reload.
			if TuningOverrides.is_exported_field(prop) and type != TYPE_OBJECT and type != TYPE_ARRAY:
				var prop_name: String = str(prop.get("name", ""))
				resource.set(prop_name, shipped.get(prop_name))


func _on_save_pressed() -> void:
	var err: Error = save_overrides()
	_status_label.text = "Saved to %s." % save_path() if err == OK else "Save failed (%d)." % err


## Writes every exported float/int/bool/Color field of every tuning resource
## into user://tuning_overrides.cfg (one ConfigFile section per resource
## class). Public so a test can drive/verify it without a real Button.
## Loads whatever is already on disk first: a fresh ConfigFile would drop the selected-tab section
## _save_selected_tab_index() writes on its own schedule.
func save_overrides() -> Error:
	if not UserPaths.persistence_allowed():
		return ERR_UNAVAILABLE
	var config: ConfigFile = ConfigFile.new()
	config.load(save_path())
	TuningOverrides.write_sections(config, _tuning_instances())
	TuningSfxTab.write_overrides(config, audio_config, Sfx.effect_files())
	return config.save(save_path())


## Label -> the panel's current instance of each persisted resource (set_field() and friends swap
## three of them), keyed like TuningOverrides.SECTIONS.
func _tuning_instances() -> Dictionary:
	return {
		"CameraTuning": camera_tuning,
		"GhostTuning": ghost_tuning,
		"PhysicsTuning": physics_tuning,
		"TerritoryTuning": territory_tuning,
		"TerritoryVisuals": territory_visuals,
		"BlockFeedConfig": block_feed_config,
		"SkyboxConfig": skybox_config,
		"ArenaSideStyle": arena_side_style,
	}


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(TuningOverrides.copy_text(_tuning_instances()))
	_status_label.text = "Copied."
