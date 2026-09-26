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
##                (TerritoryVisuals) + a Skybox dropdown row (Bontago-xtq.22,
##                config/SkyboxConfig.gd's `default_set`/`enabled`, not
##                reflection-built -- see _build_skybox_row()'s own doc)
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
##                sunset.tres -- the only shipped theme on this branch
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
##     partial-live gap around the FogVolume child).
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
const VALUE_WIDTH: float = 74.0

## Bontago-xtq.13: the selected-tab memory shares SAVE_PATH with every tuning
## resource's own override section (one ConfigFile, one section per concern)
## rather than a second settings file.
const SELECTED_TAB_SECTION: String = "TuningPanel"
const SELECTED_TAB_KEY: String = "selected_tab"

## DECISION (ui/TuningPanel.gd, Bontago-mv0.21): row name/description column
## widened from the bare label's old 260px width so a whole one-sentence
## description can sit under the field name without wrapping to more than a
## couple of lines at 1080p.
const NAME_COLUMN_WIDTH: float = 320.0
## DECISION: muted relative to the panel's default text color so the sentence
## reads as a sub-label, not a second heading -- same idea as _class_label_for
## rows' own lighter blue tint just below in this file.
const DESCRIPTION_COLOR: Color = Color(0.72, 0.72, 0.78, 0.85)
## DECISION: smaller than the panel's default font so the name stays the
## visually primary line of each row.
const DESCRIPTION_FONT_SIZE: int = 12
## DECISION: a warm highlight -- distinct from DESCRIPTION_COLOR and from the
## class-header blue -- so an owner-adjusted field is unmistakable at a
## glance ("outcome 3": visible when live differs from default).
const MODIFIED_COLOR: Color = Color(1.0, 0.82, 0.3)
const MODIFIED_MARKER: String = "• "
## DECISION: matches _build_float_row's own "%.4f" precision for the live
## value label; the default annotation trims trailing zeros afterward (see
## _format_default()) so "-35.0000" reads as "-35" and "0.0150" as "0.015".
const DEFAULT_FLOAT_PRECISION: int = 4

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
const CLIENT_HIDDEN_TAB_FIRST: int = 7

## Bontago-xtq.17 (owner playtest 2026-09-23: "heavier and more bouncy, but a
## dropped block shouldn't just bounce straight up again" -- research +
## A/B presets): the Physics tab's preset dropdown copies one of these
## PhysicsTuning resources' every exported field onto the live physics_tuning
## instance (apply_physics_preset() below). "current" is byte-identical to
## config/physics_tuning.tres's own defaults, so picking it is a no-op;
## "heavy_bouncy"/"heavy_damped" both raise cube_mass and gravity_multiplier
## for a heavier fall and set rebound_damping below 1 so a flat drop doesn't
## bounce straight back up, while still giving lateral/tumbling liveliness
## from block_bounce (see config/PhysicsTuning.gd's rebound_damping DECISION
## and game/Block._damp_rebound()) -- "_bouncy" leans on a higher block_bounce
## for that liveliness, "_damped" leans on higher linear/angular damping so
## the same heavier fall settles quieter. See config/physics_presets/*.tres
## for the exact numbers.
const PHYSICS_PRESETS: Array[Dictionary] = [
	{"id": "current", "label": "Current", "path": "res://config/physics_presets/current.tres"},
	{"id": "heavy_bouncy", "label": "Heavy & Bouncy", "path": "res://config/physics_presets/heavy_bouncy.tres"},
	{"id": "heavy_damped", "label": "Heavy & Damped", "path": "res://config/physics_presets/heavy_damped.tres"},
]

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
var sky_theme: SkyThemeDef = preload("res://config/sky_themes/sunset.tres")

## DECISION (ui/TuningPanel.gd): same `Variant` test seam as
## ui/NetDebugOverlay.gd's net_provider -- GUT cannot double the plain Net
## autoload (addons/gut/test.gd's double_singleton only recognizes engine
## singletons).
var net_provider: Variant = null

var _controller: PlayerController = null
var _camera_rig: CameraRig = null
var _field: Field = null

## One entry per built control: {"resource": Resource, "property": String,
## "control": Control}. Lets tests (and _on_field_changed()) find the control
## for a given resource field without walking the tree.
var _rows: Array[Dictionary] = []

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


func _ready() -> void:
	visible = false
	net_provider = Net
	_build_ui()
	_selected_tab_index = _load_selected_tab_index()
	rebuild()


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
	rebuild()


## Called once by game/Main.gd (through HotSeat.gd/Sandbox.gd's own
## set_camera_rig()), after Main builds the shared CameraRig -- the same
## hand-off HotSeat.gd's own set_camera_rig() already documents.
func set_camera_rig(rig: CameraRig) -> void:
	_camera_rig = rig
	if rig != null:
		camera_tuning = rig.tuning
	rebuild()


## Called once by game/Main.gd/Sandbox.gd with the shared Field, for the
## Territory tab and refresh_territory_visuals_live()'s overlay push.
func set_field(field: Field) -> void:
	_field = field
	if field != null:
		territory_tuning = field.territory_tuning
		territory_visuals = field.visuals
	rebuild()


# --- Toggle (F4 / gamepad Start+X) -------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"tuning_panel_toggle"):
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
	if _controller != null:
		_controller.input_enabled = not visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
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
	_save_selected_tab_index()


## Loads just the persisted tab index from SAVE_PATH, if any -- called once
## from _ready(), before the first rebuild() so the very first open already
## restores it. Returns 0 (the sane default) with no saved file, an unreadable
## one, or no matching key, exactly like _apply_saved_section()'s own
## stale/missing-key tolerance below.
func _load_selected_tab_index() -> int:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
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
	var config: ConfigFile = ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value(SELECTED_TAB_SECTION, SELECTED_TAB_KEY, _selected_tab_index)
	config.save(SAVE_PATH)


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


## Public so a test can force a rebuild after swapping camera_tuning/etc.
## directly (rather than through set_controller()/set_camera_rig()/
## set_field()).
func rebuild() -> void:
	if _tab_container == null:
		return
	_rebuilding_tabs = true
	for child: Node in _tab_container.get_children():
		_tab_container.remove_child(child)
		# queue_free, not free: rebuild() is reached from a control's own signal
		# (e.g. the physics-preset OptionButton's item_selected), and freeing the
		# emitter mid-emission is a Godot error / potential crash.
		child.queue_free()
	_rows.clear()

	_add_tab("Camera", [camera_tuning])
	_add_tab("Controls", [ghost_tuning])
	# Bontago-xtq.36: the M7 art-direction tabs -- purely visual, so (unlike
	# Physics/Territory/Feed below) available to a client too, hence grouped
	# here before CLIENT_HIDDEN_TAB_FIRST's cutoff (see that constant's doc).
	_add_tab("Blocks FX", [block_visual_tuning, block_effects_config])
	_add_tab("Beacons", [beacon_visual_tuning])
	_add_tab("Camera FX", [camera_shake_config])
	_add_tab("HUD", [hud_visual_tuning])
	_add_tab("Sky", [sky_theme])
	_add_tab("Physics", [physics_tuning])
	_add_tab("Territory", [territory_tuning, territory_visuals])
	_add_tab("Feed", [block_feed_config])

	_apply_availability()

	# Bontago-xtq.13: rebuild() just replaced every tab page (a fresh
	# TabContainer would otherwise land back on tab 0) -- restore whatever
	# tab the owner last had open, clamped in case a stale saved index no
	# longer fits (e.g. a client's hidden-tab availability changed the count).
	if _tab_container.get_tab_count() > 0:
		_tab_container.current_tab = clampi(_selected_tab_index, 0, _tab_container.get_tab_count() - 1)
	_rebuilding_tabs = false


func _add_tab(tab_name: String, resources: Array) -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = tab_name
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)

	if tab_name == "Physics":
		list.add_child(_build_physics_preset_row())
	if tab_name == "Territory":
		# Bontago-xtq.22 (owner: disc reflectivity is "hard to judge with that
		# texture -- add an option to F4 to change the skybox"): placed here,
		# not a new tab of its own, alongside TerritoryVisuals' own reflection
		# fields (reflection_probe_*/ssr_*/mirror_*) this row's live-switch
		# result is judged against.
		list.add_child(_build_skybox_row())

	for entry: Variant in resources:
		var resource: Resource = entry as Resource
		if resource == null:
			continue
		list.add_child(_build_resource_rows(resource))

	scroll.add_child(list)
	_tab_container.add_child(scroll)


func _apply_availability() -> void:
	var full_access: bool = _has_full_access()
	for index: int in range(CLIENT_HIDDEN_TAB_FIRST, _tab_container.get_tab_count()):
		_tab_container.set_tab_hidden(index, not full_access)


func _has_full_access() -> bool:
	var provider: Variant = net_provider if net_provider != null else Net
	return bool(provider.is_host())


func _build_resource_rows(resource: Resource) -> VBoxContainer:
	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	var class_label: String = _class_label_for(resource)
	var fresh: Resource = _fresh_instance_for(resource)

	var header: Label = Label.new()
	header.text = class_label
	header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	list.add_child(header)

	for prop: Dictionary in resource.get_property_list():
		if not _is_exported_field(prop):
			continue
		var prop_name: String = str(prop.get("name", ""))
		var type: int = int(prop.get("type", TYPE_NIL))
		var row: Control = _build_row_control(resource, prop_name, type, class_label, fresh)
		if row != null:
			list.add_child(row)
	return list


## A fresh, un-tuned instance of `resource`'s own script (outcome 2: "the
## default comes from a fresh instance of the resource's script
## (resource.get_script().new()) ... never from the live instance"). Built
## once per resource per rebuild() rather than once per field, since every
## field on one resource shares the same script. Every tuning Resource this
## panel reflects over is a plain Resource subclass with only @export fields
## and no _init() side effects, so Script.new() is safe here and yields the
## same defaults the .gd file declares -- verified by this package's
## test_tuning_panel.gd "defaults" tests, which check CameraTuning.new()/
## GhostTuning.new() directly against the same numbers.
func _fresh_instance_for(resource: Resource) -> Resource:
	if resource == null or resource.get_script() == null:
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


## Outcome 2: every row's name is followed by "(default <value>)", and a
## smaller muted sentence describing what the field controls sits beneath it
## (a tooltip on the name label repeats the same sentence -- "a tooltip in
## addition is fine"). Returns the built Label so the caller can register it
## in _rows for _refresh_row_marker() to find later (outcome 3).
func _row_name_block(prop_name: String, class_label: String, default_value: Variant, type: int) -> Dictionary:
	var block: VBoxContainer = VBoxContainer.new()
	block.custom_minimum_size = Vector2(NAME_COLUMN_WIDTH, 0.0)
	block.add_theme_constant_override("separation", 0)

	var description: String = hints.description_for(class_label, prop_name) if hints != null else ""

	var name_label: Label = Label.new()
	name_label.text = "%s (default %s)" % [prop_name, _format_default(default_value, type)]
	if not description.is_empty():
		name_label.tooltip_text = description
	block.add_child(name_label)

	var desc_label: Label = Label.new()
	desc_label.text = description
	desc_label.add_theme_color_override("font_color", DESCRIPTION_COLOR)
	desc_label.add_theme_font_size_override("font_size", DESCRIPTION_FONT_SIZE)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block.add_child(desc_label)

	return {"container": block, "name_label": name_label}


func _build_bool_row(resource: Resource, prop_name: String, class_label: String, default_value: Variant) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var name_block: Dictionary = _row_name_block(prop_name, class_label, default_value, TYPE_BOOL)
	row.add_child(name_block["container"] as Control)

	var check: CheckButton = CheckButton.new()
	check.button_pressed = bool(resource.get(prop_name))
	check.toggled.connect(func(pressed: bool) -> void:
		resource.set(prop_name, pressed)
		_on_field_changed(resource, prop_name)
	)
	row.add_child(check)

	_rows.append({
		"resource": resource, "property": prop_name, "control": check,
		"name_label": name_block["name_label"], "default": default_value, "type": TYPE_BOOL,
	})
	_refresh_row_marker(_rows[-1])
	return row


func _build_int_row(resource: Resource, prop_name: String, class_label: String, default_value: Variant) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var name_block: Dictionary = _row_name_block(prop_name, class_label, default_value, TYPE_INT)
	row.add_child(name_block["container"] as Control)

	var current: float = float(int(resource.get(prop_name)))
	var value_range: Vector2 = _range_for(class_label, prop_name, current)

	var spin: SpinBox = SpinBox.new()
	spin.min_value = value_range.x
	spin.max_value = value_range.y
	spin.step = 1.0
	spin.value = current
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float) -> void:
		resource.set(prop_name, int(round(v)))
		_on_field_changed(resource, prop_name)
	)
	row.add_child(spin)

	_rows.append({
		"resource": resource, "property": prop_name, "control": spin,
		"name_label": name_block["name_label"], "default": default_value, "type": TYPE_INT,
	})
	_refresh_row_marker(_rows[-1])
	return row


func _build_float_row(resource: Resource, prop_name: String, class_label: String, default_value: Variant) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var name_block: Dictionary = _row_name_block(prop_name, class_label, default_value, TYPE_FLOAT)
	row.add_child(name_block["container"] as Control)

	var current: float = float(resource.get(prop_name))
	var value_range: Vector2 = _range_for(class_label, prop_name, current)

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
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var value_label: Label = Label.new()
	value_label.custom_minimum_size = Vector2(VALUE_WIDTH, 0.0)
	value_label.text = "%.4f" % current
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float) -> void:
		resource.set(prop_name, v)
		value_label.text = "%.4f" % v
		_on_field_changed(resource, prop_name)
	)

	_rows.append({
		"resource": resource, "property": prop_name, "control": slider,
		"name_label": name_block["name_label"], "default": default_value, "type": TYPE_FLOAT,
	})
	_refresh_row_marker(_rows[-1])
	return row


func _build_color_row(resource: Resource, prop_name: String, class_label: String, default_value: Variant) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var name_block: Dictionary = _row_name_block(prop_name, class_label, default_value, TYPE_COLOR)
	row.add_child(name_block["container"] as Control)

	var picker: ColorPickerButton = ColorPickerButton.new()
	picker.color = resource.get(prop_name)
	picker.custom_minimum_size = Vector2(90.0, 0.0)
	picker.color_changed.connect(func(c: Color) -> void:
		resource.set(prop_name, c)
		_on_field_changed(resource, prop_name)
	)
	row.add_child(picker)

	_rows.append({
		"resource": resource, "property": prop_name, "control": picker,
		"name_label": name_block["name_label"], "default": default_value, "type": TYPE_COLOR,
	})
	_refresh_row_marker(_rows[-1])
	return row


## Outcome 2's default annotation, formatted per type: "true"/"false" for a
## bool, a plain integer for an int, a trimmed-decimal number for a float
## (String.num()'s fixed precision with trailing zeros/dot stripped, so
## -35.0 reads as "-35" and 0.015 as "0.015" rather than "-35.0000"), and a
## "#rrggbbaa" hex code for a Color (the same shorthand a .tres file itself
## would accept back).
func _format_default(value: Variant, type: int) -> String:
	match type:
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			return _format_float_compact(float(value))
		TYPE_COLOR:
			var c: Color = value
			return "#%s" % c.to_html(true)
		_:
			return str(value)


func _format_float_compact(value: float) -> String:
	var text: String = String.num(value, DEFAULT_FLOAT_PRECISION)
	if text.contains("."):
		text = text.rstrip("0")
		if text.ends_with("."):
			text = text.left(text.length() - 1)
	return text


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


## Re-derives one row's "(default ...)" text and modified-marker/color from
## its resource's *current* value -- called right after a row is first built
## (nothing is modified yet, but this keeps one code path for both cases) and
## again from _on_field_changed() every time a control writes its resource,
## so the marker updates live without a full rebuild().
func _refresh_row_marker(row: Dictionary) -> void:
	var name_label: Label = row.get("name_label") as Label
	if name_label == null:
		return
	var resource: Resource = row.get("resource") as Resource
	var prop_name: String = String(row.get("property"))
	var default_value: Variant = row.get("default")
	var type: int = int(row.get("type", TYPE_NIL))
	var current: Variant = resource.get(prop_name)
	var modified: bool = not _values_equal(current, default_value, type)

	var base_text: String = "%s (default %s)" % [prop_name, _format_default(default_value, type)]
	name_label.text = (MODIFIED_MARKER + base_text) if modified else base_text
	if modified:
		name_label.add_theme_color_override("font_color", MODIFIED_COLOR)
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


## Test/inspection seam: the built name Label's current text (the field name,
## "(default ...)" annotation, and modified marker) for one field, without
## reaching into a Control tree.
func label_text_for(resource: Resource, prop_name: String) -> String:
	for row: Dictionary in _rows:
		if row.get("resource") == resource and row.get("property") == prop_name:
			return (row.get("name_label") as Label).text
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
		apply_sky_theme_live()
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
	row.add_theme_constant_override("separation", 8)

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
		"(mass is not live-applied to standing blocks)."
	)
	for preset: Dictionary in PHYSICS_PRESETS:
		option.add_item(String(preset["label"]))
	option.item_selected.connect(func(index: int) -> void:
		apply_physics_preset(String(PHYSICS_PRESETS[index]["id"]))
	)
	row.add_child(option)

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


## Bontago-xtq.22: the Territory tab's own Skybox row, built the same way
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
	row.add_theme_constant_override("separation", 8)

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
	row.add_child(option)

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
	for node: Node in get_tree().get_nodes_in_group(Skybox.TUNING_GROUP):
		var skybox: Skybox = node as Skybox
		if skybox != null:
			skybox.apply_theme(sky_theme)


# --- Reset / Save / Copy -----------------------------------------------------

func _on_reset_pressed() -> void:
	reset_all()
	_status_label.text = "Reset to file."


## Reloads every tuning resource's fields from its .tres on disk, onto the
## *same* live instance (never replacing the reference every other system
## already holds -- see ResourceLoader.CACHE_MODE_IGNORE's use in
## _reset_resource()). Public so a test can call it without a real Button.
func reset_all() -> void:
	_reset_resource(camera_tuning)
	_reset_resource(ghost_tuning)
	_reset_resource(physics_tuning)
	_reset_resource(territory_tuning)
	_reset_resource(territory_visuals)
	_reset_resource(block_feed_config)
	_reset_resource(skybox_config)
	apply_physics_live()
	refresh_territory_visuals_live()
	apply_skybox_set(skybox_config.default_set if skybox_config.enabled else Skybox.PROCEDURAL_SET_ID)
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
	_status_label.text = "Saved to %s." % SAVE_PATH if err == OK else "Save failed (%d)." % err


## Writes every exported float/int/bool/Color field of every tuning resource
## into user://tuning_overrides.cfg (one ConfigFile section per resource
## class). Public so a test can drive/verify it without a real Button.
## Bontago-xtq.13: loads whatever is already on disk first -- a fresh
## ConfigFile here would silently drop the selected-tab section
## _save_selected_tab_index() writes on its own, independent schedule.
func save_overrides() -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.load(SAVE_PATH)
	_write_overrides(config, "CameraTuning", camera_tuning)
	_write_overrides(config, "GhostTuning", ghost_tuning)
	_write_overrides(config, "PhysicsTuning", physics_tuning)
	_write_overrides(config, "TerritoryTuning", territory_tuning)
	_write_overrides(config, "TerritoryVisuals", territory_visuals)
	_write_overrides(config, "BlockFeedConfig", block_feed_config)
	_write_overrides(config, "SkyboxConfig", skybox_config)
	return config.save(SAVE_PATH)


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
	if config.load(SAVE_PATH) != OK:
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
