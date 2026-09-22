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
##                (TerritoryVisuals)
##   Feed      -> config/block_feed.tres (BlockFeedConfig), preloaded
##                directly -- autoload/Match.gd is the only script holding a
##                live reference to this one and it's a different package's
##                file, but preloading the same path still resolves to the
##                identical cached Resource instance Match reads (Godot caches
##                a Resource by path within one process), so no line there is
##                actually required for this field to be editable here.
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
##
## Not live (documented rather than fixed -- both live in files this package
## does not own): game/CameraRig.gd snapshots follow_distance/follow_pitch_deg
## into its own _distance/_pitch once in _ready(), so those two only take
## effect from the next camera rebuild (next match/scene reload); Territory-
## Visuals.disk_mesh_segments is baked into the disk CylinderMesh once at
## Field/TerritoryOverlay.configure() time.
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
const LABEL_WIDTH: float = 260.0
const VALUE_WIDTH: float = 74.0

## get_property_list() usage flags an @export'd script variable carries (see
## this file's own probe in the implementation notes): STORAGE so it's
## serialized, EDITOR so it's inspector-visible, SCRIPT_VARIABLE so it's a
## script-declared field rather than a base Resource/Object property like
## resource_path. Anything missing one of these three is skipped -- an
## un-exported script var, a resource_* built-in, or the `script` property
## itself.
const EXPORT_USAGE_MASK: int = PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE

## Tabs whose content is hidden from a client (see class doc "Availability").
## Indices match the order _rebuild_tabs() adds tabs in.
const CLIENT_HIDDEN_TAB_FIRST: int = 2

@export var hints: TuningPanelHints = preload("res://config/tuning_panel_hints.tres")

var camera_tuning: CameraTuning = preload("res://config/camera_tuning.tres")
var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
var physics_tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var territory_visuals: TerritoryVisuals = preload("res://config/territory_visuals.tres")
var block_feed_config: BlockFeedConfig = preload("res://config/block_feed.tres")

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


func _ready() -> void:
	visible = false
	net_provider = Net
	_build_ui()
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
		rebuild()


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
	for child: Node in _tab_container.get_children():
		_tab_container.remove_child(child)
		child.free()
	_rows.clear()

	_add_tab("Camera", [camera_tuning])
	_add_tab("Controls", [ghost_tuning])
	_add_tab("Physics", [physics_tuning])
	_add_tab("Territory", [territory_tuning, territory_visuals])
	_add_tab("Feed", [block_feed_config])

	_apply_availability()


func _add_tab(tab_name: String, resources: Array) -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = tab_name
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)

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

	var header: Label = Label.new()
	header.text = class_label
	header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	list.add_child(header)

	for prop: Dictionary in resource.get_property_list():
		if not _is_exported_field(prop):
			continue
		var prop_name: String = str(prop.get("name", ""))
		var type: int = int(prop.get("type", TYPE_NIL))
		var row: Control = _build_row_control(resource, prop_name, type, class_label)
		if row != null:
			list.add_child(row)
	return list


func _is_exported_field(prop: Dictionary) -> bool:
	var usage: int = int(prop.get("usage", 0))
	return (usage & EXPORT_USAGE_MASK) == EXPORT_USAGE_MASK


func _class_label_for(resource: Resource) -> String:
	if resource == null or resource.get_script() == null:
		return ""
	return String((resource.get_script() as Script).get_global_name())


func _build_row_control(resource: Resource, prop_name: String, type: int, class_label: String) -> Control:
	match type:
		TYPE_BOOL:
			return _build_bool_row(resource, prop_name)
		TYPE_INT:
			return _build_int_row(resource, prop_name, class_label)
		TYPE_FLOAT:
			return _build_float_row(resource, prop_name, class_label)
		TYPE_COLOR:
			return _build_color_row(resource, prop_name)
		_:
			return null


func _row_label(prop_name: String) -> Label:
	var label: Label = Label.new()
	label.text = prop_name
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	return label


func _build_bool_row(resource: Resource, prop_name: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(_row_label(prop_name))

	var check: CheckButton = CheckButton.new()
	check.button_pressed = bool(resource.get(prop_name))
	check.toggled.connect(func(pressed: bool) -> void:
		resource.set(prop_name, pressed)
		_on_field_changed(resource, prop_name)
	)
	row.add_child(check)

	_rows.append({"resource": resource, "property": prop_name, "control": check})
	return row


func _build_int_row(resource: Resource, prop_name: String, class_label: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(_row_label(prop_name))

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

	_rows.append({"resource": resource, "property": prop_name, "control": spin})
	return row


func _build_float_row(resource: Resource, prop_name: String, class_label: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(_row_label(prop_name))

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

	_rows.append({"resource": resource, "property": prop_name, "control": slider})
	return row


func _build_color_row(resource: Resource, prop_name: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(_row_label(prop_name))

	var picker: ColorPickerButton = ColorPickerButton.new()
	picker.color = resource.get(prop_name)
	picker.custom_minimum_size = Vector2(90.0, 0.0)
	picker.color_changed.connect(func(c: Color) -> void:
		resource.set(prop_name, c)
		_on_field_changed(resource, prop_name)
	)
	row.add_child(picker)

	_rows.append({"resource": resource, "property": prop_name, "control": picker})
	return row


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


# --- Live-apply hooks (see class doc) ----------------------------------------

func _on_field_changed(resource: Resource, _prop_name: String) -> void:
	if resource == physics_tuning:
		apply_physics_live()
	elif resource == territory_visuals:
		refresh_territory_visuals_live()
	# camera_tuning / ghost_tuning / territory_tuning / block_feed_config are
	# already read live by whatever consumes them each frame/tick -- see this
	# file's class doc for the (documented, not fixed) exceptions.


## Pushes physics_tuning onto every Block already standing (BlockFactory.
## build() already reads it for anything spawned from here on). Public so a
## test can drive it directly instead of dragging a real slider.
func apply_physics_live() -> void:
	for node: Node in get_tree().get_nodes_in_group(Block.TUNING_GROUP):
		var block: Block = node as Block
		if block != null:
			block.apply_physics_tuning(physics_tuning)


## Pushes territory_visuals onto the wired Field's TerritoryOverlay shader
## immediately. A no-op if this panel was never wired to a Field (a bare
## unit-test instance, or a moment before set_field() has run).
func refresh_territory_visuals_live() -> void:
	if _field == null:
		return
	var overlay: TerritoryOverlay = _field.overlay()
	if overlay != null:
		overlay.refresh_visual_uniforms()


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
	apply_physics_live()
	refresh_territory_visuals_live()
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
func save_overrides() -> Error:
	var config: ConfigFile = ConfigFile.new()
	_write_overrides(config, "CameraTuning", camera_tuning)
	_write_overrides(config, "GhostTuning", ghost_tuning)
	_write_overrides(config, "PhysicsTuning", physics_tuning)
	_write_overrides(config, "TerritoryTuning", territory_tuning)
	_write_overrides(config, "TerritoryVisuals", territory_visuals)
	_write_overrides(config, "BlockFeedConfig", block_feed_config)
	return config.save(SAVE_PATH)


func _write_overrides(config: ConfigFile, section: String, resource: Resource) -> void:
	if resource == null:
		return
	for prop: Dictionary in resource.get_property_list():
		if not _is_exported_field(prop):
			continue
		var type: int = int(prop.get("type", TYPE_NIL))
		if type != TYPE_BOOL and type != TYPE_INT and type != TYPE_FLOAT and type != TYPE_COLOR:
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
	return "\n\n".join(parts)


func _copy_section(section: String, resource: Resource) -> String:
	if resource == null:
		return "# %s\n(none)" % section
	var lines: PackedStringArray = PackedStringArray(["# %s" % section])
	for prop: Dictionary in resource.get_property_list():
		if not _is_exported_field(prop):
			continue
		var type: int = int(prop.get("type", TYPE_NIL))
		if type != TYPE_BOOL and type != TYPE_INT and type != TYPE_FLOAT and type != TYPE_COLOR:
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
		_:
			return str(value)
