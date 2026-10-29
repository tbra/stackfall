class_name SpectatorController
extends Node
## what the local player has in a debug "Watch bots" match (every seat is a bot, so there
## is no LocalPlayer, ghost or held block). It owns the spectator camera, the speed control and a corner HUD:
##   - overview: free orbit / pan / zoom over the arena (the CameraRig's own orbit and zoom input, plus
##     spectate pan here);
##   - follow: spectate_next / spectate_prev cycle through the bot seats (wrapping) and the camera tracks
##     that bot's latest piece (its tower while it has none), the HUD shows that bot; spectate_overview
##     returns to the free view;
##   - speed: spectate_speed steps 1x -> 2x -> 4x -> 1x, spectate_pause freezes the match. Engine.time_scale
##     is acceptable here because the match is a host-only local one; physics ticks per second stay put.
##     The scale goes back to 1x when the match ends or this node leaves the tree.
## Built and freed by game/main/MainMatchFlow.gd next to the bot controllers; never exists outside a watch match.

signal follow_changed(slot_id: int)
signal speed_changed(time_scale: float)

const OVERVIEW: int = -1
const SPEED_UP_ACTION: StringName = &"spectate_speed"
const PAUSE_ACTION: StringName = &"spectate_pause"
const NEXT_ACTION: StringName = &"spectate_next"
const PREV_ACTION: StringName = &"spectate_prev"
const OVERVIEW_ACTION: StringName = &"spectate_overview"
const PAUSED_TEXT: String = "PAUSED"
const SPEED_FORMAT: String = "%sx"
const FOLLOW_FORMAT: String = "Following %s"
const OVERVIEW_TEXT: String = "Overview"
const HINT_NEXT_TEXT: String = "next bot"
const HINT_PREV_TEXT: String = "previous"
const HINT_OVERVIEW_TEXT: String = "overview"
const HINT_SPEED_TEXT: String = "speed"
const HINT_PAUSE_TEXT: String = "pause"

var tuning: WatchBotsTuning = null

var _rig: CameraRig = null
var _slot_count: int = 0
var _follow_slot: int = OVERVIEW
var _speed_index: int = 0
var _paused: bool = false
var _free_target: Vector3 = Vector3.ZERO
var _eased_target: Vector3 = Vector3.ZERO
var _last_s: float = 0.0
var _last_block_by_slot: Dictionary = {}
var _hud: HUD = null
var _canvas: CanvasLayer = null
var _speed_label: Label = null
var _follow_label: Label = null
var _hint_row: HBoxContainer = null


func _init() -> void:
	tuning = WatchBotsOptions.tuning()


## `rig` may be null (tests); `slot_count` is the number of bot seats (all of them).
func setup(rig: CameraRig, slot_count: int) -> void:
	_rig = rig
	_slot_count = slot_count
	_last_s = Time.get_unix_time_from_system()
	_follow_slot = OVERVIEW
	_speed_index = 0
	_paused = false
	_free_target = Vector3.ZERO
	_eased_target = Vector3.ZERO
	_apply_overview_pose()


## Adds the on-screen parts: the match HUD (scoreboard, round timer, the followed bot's held/next cards),
## the F4 tuning panel and the corner labels. Separate from setup() so the logic runs in a bare tree.
func build_presentation(hud_scene: PackedScene, tuning_panel_scene: PackedScene, field: Field, context: MatchContext) -> void:
	_hud = hud_scene.instantiate() as HUD
	_hud.match_context = context
	add_child(_hud)
	var panel: TuningPanel = tuning_panel_scene.instantiate() as TuningPanel
	add_child(panel)
	panel.set_camera_rig(_rig)
	panel.set_field(field)
	_build_labels()
	_refresh_labels()
	_apply_hud_slot()


func _ready() -> void:
	Events.block_placed.connect(_on_block_placed)
	Events.match_state_changed.connect(_on_match_state_changed)
	Events.match_scope_reset.connect(reset_speed)
	Events.turn_changed.connect(_on_turn_changed)
	_last_s = Time.get_unix_time_from_system()


func _exit_tree() -> void:
	reset_speed()


# --- Follow ------------------------------------------------------------------


func follow_next() -> void:
	_step_follow(1)


func follow_prev() -> void:
	_step_follow(-1)


## Back to the free overview camera.
func overview() -> void:
	var was_following: bool = _follow_slot != OVERVIEW
	_follow_slot = OVERVIEW
	_apply_overview_pose()
	if was_following:
		_on_follow_changed()


func _step_follow(direction: int) -> void:
	if _slot_count <= 0:
		return
	var was_overview: bool = _follow_slot == OVERVIEW
	if was_overview:
		_follow_slot = 0 if direction > 0 else _slot_count - 1
	else:
		_follow_slot = posmod(_follow_slot + direction, _slot_count)
	if _rig != null:
		if was_overview:
			# Coming in from the overview: close in on the bot (cycling between bots keeps the zoom).
			_rig.set_spectator_pose(_rig.get_target(), tuning.follow_distance_m, tuning.follow_pitch_deg)
		_eased_target = _rig.get_target()
	_on_follow_changed()


func _on_follow_changed() -> void:
	_refresh_labels()
	_apply_hud_slot()
	follow_changed.emit(_follow_slot)


## The point the camera tracks for a slot: its latest placed block while that still exists, else its
## tower (home flag column) at tower_focus_fraction of the height it has reached.
func follow_point(slot_id: int) -> Vector3:
	var block: Variant = _last_block_by_slot.get(slot_id)
	if block is Node3D and is_instance_valid(block) and (block as Node3D).is_inside_tree():
		return (block as Node3D).global_position
	var base: Vector3 = Match.default_ghost_origin(slot_id)
	return base + Vector3.UP * Match.max_height_for_slot(slot_id) * tuning.tower_focus_fraction


func _on_block_placed(block: RigidBody3D, _shape_id: StringName) -> void:
	var owner_slot: Variant = block.get(&"owner_slot")
	if owner_slot is int and int(owner_slot) >= 0:
		_last_block_by_slot[int(owner_slot)] = block


func _on_turn_changed(_slot_id: int) -> void:
	# The HUD re-points itself at the substituted local slot on every turn_changed (its handler may run
	# after ours); put it back on the followed bot once all handlers are done.
	_apply_hud_slot.call_deferred()


func _apply_hud_slot() -> void:
	if _hud != null:
		_hud.set_local_slot(_follow_slot)


func _apply_overview_pose() -> void:
	if _rig == null:
		return
	var radius: float = _rig.map_def.field_radius if _rig.map_def != null else 0.0
	_free_target = Vector3.ZERO
	_rig.set_spectator_pose(_free_target, radius * tuning.overview_distance_factor, tuning.overview_pitch_deg)


# --- Speed -------------------------------------------------------------------

## Steps the speed 1x -> 2x -> 4x -> 1x (un-pausing first when paused).
func cycle_speed() -> void:
	_paused = false
	_speed_index = (_speed_index + 1) % tuning.speeds.size()
	_apply_speed()


func toggle_pause() -> void:
	_paused = not _paused
	_apply_speed()


## The speed the match runs at right now (0.0 while paused).
func time_scale() -> float:
	return 0.0 if _paused else tuning.speeds[_speed_index]


## Back to normal speed, un-paused; the engine scale returns to 1.0.
func reset_speed() -> void:
	_speed_index = 0
	_paused = false
	_apply_speed()


func _apply_speed() -> void:
	Engine.time_scale = time_scale()
	_refresh_labels()
	speed_changed.emit(time_scale())


func _on_match_state_changed(_from_state: int, to_state: int) -> void:
	if Match.is_lobby_or_end(to_state):
		reset_speed()


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _rig != null and _rig.input_gate.is_blocked():
		return
	if event.is_action_pressed(NEXT_ACTION):
		follow_next()
	elif event.is_action_pressed(PREV_ACTION):
		follow_prev()
	elif event.is_action_pressed(OVERVIEW_ACTION):
		overview()
	elif event.is_action_pressed(SPEED_UP_ACTION):
		cycle_speed()
	elif event.is_action_pressed(PAUSE_ACTION):
		toggle_pause()
	elif event is InputEventMouseButton and _rig != null:
		# The wheel zooms the spectator camera (hover_raise / hover_lower are the wheel's actions).
		if event.is_action_pressed(&"hover_raise"):
			_rig.zoom_continuous(-tuning.wheel_zoom_step_m)
		elif event.is_action_pressed(&"hover_lower"):
			_rig.zoom_continuous(tuning.wheel_zoom_step_m)
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# Unscaled time: the camera keeps moving while the match is paused or sped up.
	var now: float = Time.get_unix_time_from_system()
	var dt: float = now - _last_s
	_last_s = now
	if _rig == null:
		return
	var pan: Vector2 = Vector2.ZERO
	var zoom_axis: float = 0.0
	if not _rig.input_gate.is_blocked():
		var stick: Vector2 = Vector2(
			Input.get_action_strength(&"camera_pan_right") - Input.get_action_strength(&"camera_pan_left"),
			Input.get_action_strength(&"camera_pan_back") - Input.get_action_strength(&"camera_pan_forward"))
		if Input.get_action_strength(&"camera_zoom_modifier") > 0.5:
			zoom_axis = stick.y if absf(stick.y) > tuning.stick_deadzone else 0.0
		elif stick.length() > tuning.stick_deadzone:
			pan = stick
	if zoom_axis != 0.0:
		_rig.zoom_continuous(zoom_axis * tuning.pad_zoom_speed_mps * dt)
	if pan != Vector2.ZERO and _follow_slot != OVERVIEW:
		# Panning while following lets go of the bot and pans from where the camera is.
		_free_target = _rig.get_target()
		_follow_slot = OVERVIEW
		_on_follow_changed()
	if _follow_slot == OVERVIEW:
		if pan != Vector2.ZERO:
			var forward: Vector3 = Vector3(sin(_rig.get_yaw()), 0.0, cos(_rig.get_yaw()))
			var right: Vector3 = Vector3(forward.z, 0.0, -forward.x)
			_free_target += (right * pan.x + forward * pan.y) * tuning.pan_speed_per_distance * _rig.get_distance() * dt
		_rig.set_follow_position(_free_target)
	else:
		var weight: float = clampf(1.0 - exp(-dt * tuning.follow_ease_per_s), 0.0, 1.0)
		_eased_target = _eased_target.lerp(follow_point(_follow_slot), weight)
		_rig.set_follow_position(_eased_target)


# --- Labels ------------------------------------------------------------------

func _build_labels() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = tuning.canvas_layer
	add_child(_canvas)
	var top: MarginContainer = _make_margin(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override(&"margin_top", tuning.label_margin_px + tuning.speed_label_top_px)
	_speed_label = _make_label(top)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bottom: MarginContainer = _make_margin(Control.PRESET_BOTTOM_WIDE)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_END
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(stack)
	_follow_label = _make_label(stack)
	_follow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_row = HBoxContainer.new()
	_hint_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_row.modulate.a = tuning.hint_alpha
	stack.add_child(_hint_row)
	for pair: Array in [[NEXT_ACTION, HINT_NEXT_TEXT], [PREV_ACTION, HINT_PREV_TEXT], [OVERVIEW_ACTION, HINT_OVERVIEW_TEXT], [SPEED_UP_ACTION, HINT_SPEED_TEXT], [PAUSE_ACTION, HINT_PAUSE_TEXT]]:
		_add_hint(pair[0] as StringName, pair[1] as String)


func _make_margin(preset: Control.LayoutPreset) -> MarginContainer:
	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, tuning.label_margin_px)
	_canvas.add_child(margin)
	margin.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN if preset == Control.PRESET_BOTTOM_WIDE else Control.GROW_DIRECTION_END
	return margin


func _make_label(parent: Control) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", tuning.label_font_size)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", tuning.label_outline_px)
	parent.add_child(label)
	return label


## One "[glyph] text" entry of the controls hint row; the glyph follows the active input device.
func _add_hint(action: StringName, text: String) -> void:
	InputGlyph.build_for_action(_hint_row, action, 1)
	var label: Label = _make_label(_hint_row)
	label.add_theme_font_size_override(&"font_size", tuning.hint_font_size)
	label.text = " %s    " % text


func _refresh_labels() -> void:
	if _speed_label != null:
		_speed_label.text = PAUSED_TEXT if _paused else SPEED_FORMAT % String.num(tuning.speeds[_speed_index], 0)
	if _follow_label != null:
		_follow_label.text = OVERVIEW_TEXT if _follow_slot == OVERVIEW else FOLLOW_FORMAT % slot_name(_follow_slot)
		var face: Color = Color.WHITE if _follow_slot == OVERVIEW else Match.slot_color(_follow_slot).lightened(tuning.follow_label_lighten)
		_follow_label.add_theme_color_override(&"font_color", face)


## The bot's display name as the HUD shows it.
func slot_name(slot_id: int) -> String:
	var seat: PlayerSlot = Match.slot(slot_id)
	if seat == null:
		return PlayerNames.label_for_slot(slot_id, "", true, "")
	return PlayerNames.label_for_slot(slot_id, seat.display_name, seat.is_bot, "")
