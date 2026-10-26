extends Node
## P3 parity recipe: a scripted, tick-indexed offline run of the local-player stack (controller, ghost,
## arc preview, camera rig, remote cursor ghost, LocalHeldView) in a real hosted Main + Match whose recorded
## state must not change across the P3 refactor. Driven only through the Input singleton, the Events bus and
## the public Match/controller API, one scripted step per physics tick; no ENet peer (the throw pair is P3-0b).
##
## Record a run (the committed reference comes from an unmodified main):
##   godot --headless --fixed-fps 60 --path . res://tests/bench/bench_p3_parity.tscn -- --out=run.json [--rng-seed=N] [--wallclock]
## Compare two recordings (exit 1 on any difference above --tol, default 0):
##   godot --headless --path . res://tests/bench/bench_p3_parity.tscn -- --compare=a.json,b.json [--tol=0.0001]
##
## Determinism rules (plan 6.1): (a) accumulated input off and the buffer flushed after every tick;
## (b) Settings is isolated (a scene under res://tests/ or `-- --agent-probe` gives defaults, never the user's
## settings.cfg; the scale is recorded in the header and a non-isolated run refuses to start); wall-clock fields are never recorded (LocalHeldView.updated_msec only under --wallclock, which exists
## to show that it differs); (c) offline, no peer. Ticks are counted from the first PLAYING tick, so
## load-timed world building does not shift the keys.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const CUBE_PATH: String = "res://config/blocks/cube.tres"
const MAP_PATH: String = "res://config/match/maps/round.tres"
const DEFAULTS_PATH: String = "res://config/match/match_defaults.tres"
const OUT_ARG: String = "--out="
const COMPARE_ARG: String = "--compare="
const TOL_ARG: String = "--tol="
const SEED_ARG: String = "--rng-seed="
const WALLCLOCK_ARG: String = "--wallclock"
const DEFAULT_SEED: int = 20261025
const HOST_SLOT: int = 0
const REMOTE_SLOT: int = 1
const PLAYER_COUNT: int = 2
const FIELD_RADIUS_M: float = 20.0
const MAX_LOAD_TICKS: int = 3000
const GIFT_ID: StringName = &"bomb"
const ROUND_STEP: float = 0.0001

## Scripted timeline, in ticks since PLAYING.
const PLACE_TICKS: Array[int] = [30, 150, 270]
const SLIDE_AWAY_TICK: int = 400
const SLIDE_AWAY_TICKS: int = 8
const SLIDE_AWAY_PX: float = -0.5
const SLIDE_IN_TICK: int = 420
const SLIDE_IN_TICKS: int = 30
const SLIDE_IN_PX: float = 0.2
const WHEEL_TICK: int = 470
const WHEEL_NOTCHES: int = 6
const WHEEL_SPACING: int = 3
const HOLD_RAISE_TICK: int = 500
const HOLD_LOWER_TICK: int = 560
const HOLD_TICKS: int = 45
const ROTATE_TICK: int = 620
const ROTATE_SPACING: int = 4
const TAP_TICK: int = 660
const DRAG_TICK: int = 670
const DRAG_STEPS: int = 6
const DRAG_STEP_PX: Vector2 = Vector2(14.0, 5.0)
const ROTATED_PLACE_TICK: int = 720
const GIFT_QUEUE_TICK: int = 880
const GIFT_FEED_TICK: int = 960
const GIFT_THROW_TICK: int = 1020
const THROW_WATCH_TICKS: int = 90
const ORBIT_TICK: int = 1140
const ORBIT_STEPS: int = 10
const ORBIT_STEP_PX: Vector2 = Vector2(9.0, -4.0)
const ZOOM_TICK: int = 1170
const SNAP_HOME_TICK: int = 1200
const CAMERA_RESET_TICK: int = 1240
const REMOTE_TICK: int = 1270
const REMOTE_STEPS: int = 4
const REMOTE_SPACING: int = 5
const PAUSE_OPEN_TICK: int = 1330
const PAUSE_CLICK_TICK: int = 1335
const PAUSE_CLOSE_TICK: int = 1340
const CHAT_OPEN_TICK: int = 1350
const CHAT_CLOSE_TICK: int = 1360
const RESULTS_TICK: int = 1370
const SCOPE_RESET_TICK: int = 1380
const END_TICK: int = 1420

var _out_path: String = ""
var _wallclock: bool = false
var _record: Dictionary = {}
var _events: Array = []
var _tick: int = -1
var _main: Node = null
var _controller: PlayerController = null
var _rig: CameraRig = null
var _remote: RemoteCursors = null
var _load_ticks: int = 0
var _watched: Array[RigidBody3D] = []
var _throw_open_tick: int = -1


func _ready() -> void:
	var compare: String = ""
	var tol: float = 0.0
	var rng_seed: int = DEFAULT_SEED
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_ARG):
			_out_path = arg.substr(OUT_ARG.length())
		elif arg.begins_with(COMPARE_ARG):
			compare = arg.substr(COMPARE_ARG.length())
		elif arg.begins_with(TOL_ARG):
			tol = arg.substr(TOL_ARG.length()).to_float()
		elif arg.begins_with(SEED_ARG):
			rng_seed = arg.substr(SEED_ARG.length()).to_int()
		elif arg == WALLCLOCK_ARG:
			_wallclock = true
	if not compare.is_empty():
		get_tree().quit(_compare(compare, tol))
		set_physics_process(false)
		return
	if not UserPaths.is_isolated_run():
		push_error("bench_p3_parity: not an isolated run, Settings would read the user's settings.cfg")
		get_tree().quit(1)
		return
	_record["header.mouse_move_speed_scale"] = _r(Settings.mouse_move_speed_scale())
	Input.use_accumulated_input = false
	seed(rng_seed)
	_clear_input()
	_build_world(rng_seed)
	Events.feed_block_issued.connect(_on_feed_block_issued)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.placement_relocated.connect(_on_placement_relocated)
	Events.turn_changed.connect(_on_turn_changed)
	Events.block_placed.connect(_on_block_placed)


## The hosted Main of test_drop_displacement_real_flow on a small map, with the world registered and the
## match started the way MainHeadlessBotsFlow does, minus the bot. DECISION: no bot seat, so no bot think
## timing or thread joins can reach the record; the feed timer is off (unlimited blocks, as the sandbox runs
## it) so a scripted click is never refused by the interval lock and no auto-drop fires; scripted_gifts keeps random crates out and opens the
## debug gift seam.
func _build_world(rng_seed: int) -> void:
	assert(Net.host_game(AgentProbe.free_udp_port(), "Hostie") == OK)
	_main = MAIN_SCENE.instantiate()
	var map: MapDef = (load(MAP_PATH) as MapDef).duplicate(true)
	map.field_radius = FIELD_RADIUS_M
	(_main.get_node("Field") as Field).map_def = map
	add_child(_main)
	var config: MatchConfig = (load(DEFAULTS_PATH) as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.rng_seed = rng_seed
	config.ai_count = 0
	config.player_count = PLAYER_COUNT
	config.sandbox = false
	config.scripted_gifts = true
	config.countdown_seconds = 0.0
	var pinned: BlockFeedConfig = Match._block_feed_config.duplicate() as BlockFeedConfig
	pinned.shapes = [load(CUBE_PATH) as BlockShape]
	pinned.weight_overrides = PackedFloat32Array()
	Match._block_feed_config = pinned
	Match.register_world(_main.get_node("Field"), _main.get_node("BlockRegistry"), _main.get_node("BlocksContainer"))
	Match.start_match(config)
	Match.set_feed_timer_enabled(false)


func _physics_process(_delta: float) -> void:
	if _tick < 0 and not _find_world():
		_load_ticks += 1
		if _load_ticks > MAX_LOAD_TICKS:
			push_error("bench_p3_parity: world never reached PLAYING")
			get_tree().quit(1)
			set_physics_process(false)
		return
	_tick += 1
	_step()
	_sample()
	Input.flush_buffered_events()
	if _tick >= END_TICK:
		set_physics_process(false)
		_finish()


func _find_world() -> bool:
	if Match.state() != Match.State.PLAYING:
		return false
	_controller = _find(_main, "PlayerController") as PlayerController
	_remote = _find(_main, "RemoteCursors") as RemoteCursors
	_rig = _main.get_node("CameraRig") as CameraRig
	return _controller != null and _remote != null and _rig != null


func _find(node: Node, class_label: String) -> Node:
	if node.get_script() != null and (node.get_script() as Script).get_global_name() == class_label:
		return node
	for child: Node in node.get_children():
		var hit: Node = _find(child, class_label)
		if hit != null:
			return hit
	return null


# --- scripted input -------------------------------------------------------------------------

func _step() -> void:
	if _tick in PLACE_TICKS or _tick == ROTATED_PLACE_TICK or _tick == GIFT_FEED_TICK or _tick == GIFT_THROW_TICK:
		_click_place()
	_script_cursor()
	_script_hover()
	_script_rotation()
	_script_camera()
	_script_gate()
	if _tick == GIFT_QUEUE_TICK:
		_events.append("%d|gift_queued|%s" % [_tick, Match.debug_queue_special(HOST_SLOT, GIFT_ID)])
	if _tick >= REMOTE_TICK and _tick < REMOTE_TICK + REMOTE_STEPS * REMOTE_SPACING and (_tick - REMOTE_TICK) % REMOTE_SPACING == 0:
		var step: int = (_tick - REMOTE_TICK) / REMOTE_SPACING
		Events.remote_cursor_updated.emit(
			REMOTE_SLOT, Vector3(2.0 + float(step), 3.0, -1.0), step * 3, Quaternion(Vector3.UP, 0.2 * float(step))
		)


func _script_cursor() -> void:
	if _tick >= SLIDE_AWAY_TICK and _tick < SLIDE_AWAY_TICK + SLIDE_AWAY_TICKS:
		_motion(Vector2(SLIDE_AWAY_PX, 0.0))
	if _tick >= SLIDE_IN_TICK and _tick < SLIDE_IN_TICK + SLIDE_IN_TICKS:
		_motion(Vector2(SLIDE_IN_PX, 0.0))


func _script_hover() -> void:
	if _tick >= WHEEL_TICK and _tick < WHEEL_TICK + WHEEL_NOTCHES * WHEEL_SPACING and (_tick - WHEEL_TICK) % WHEEL_SPACING == 0:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
	var lower_tick: int = WHEEL_TICK + WHEEL_NOTCHES * WHEEL_SPACING
	if _tick >= lower_tick and _tick < lower_tick + WHEEL_NOTCHES * WHEEL_SPACING and (_tick - lower_tick) % WHEEL_SPACING == 0:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_hold(&"hover_raise", HOLD_RAISE_TICK)
	_hold(&"hover_lower", HOLD_LOWER_TICK)


func _script_rotation() -> void:
	var taps: Array[StringName] = [
		&"rotate_yaw_cw", &"rotate_pitch_fwd", &"rotate_roll_left", &"rotate_yaw_ccw", &"rotate_pitch_back", &"rotate_roll_right",
	]
	var index: int = (_tick - ROTATE_TICK) / ROTATE_SPACING
	if _tick >= ROTATE_TICK and (_tick - ROTATE_TICK) % ROTATE_SPACING == 0 and index < taps.size():
		_action_tap(taps[index])
	if _tick == TAP_TICK:
		_button(MOUSE_BUTTON_MIDDLE, true)
	elif _tick == TAP_TICK + 1:
		_button(MOUSE_BUTTON_MIDDLE, false)
	if _tick == DRAG_TICK:
		_button(MOUSE_BUTTON_MIDDLE, true)
	elif _tick > DRAG_TICK and _tick <= DRAG_TICK + DRAG_STEPS:
		_motion(DRAG_STEP_PX)
	elif _tick == DRAG_TICK + DRAG_STEPS + 1:
		_button(MOUSE_BUTTON_MIDDLE, false)
	if _tick == ROTATED_PLACE_TICK - 1:
		_action_tap(&"rotate_yaw_cw")


func _script_camera() -> void:
	if _tick == ORBIT_TICK:
		_button(MOUSE_BUTTON_RIGHT, true)
	elif _tick > ORBIT_TICK and _tick <= ORBIT_TICK + ORBIT_STEPS:
		_motion(ORBIT_STEP_PX)
	elif _tick == ORBIT_TICK + ORBIT_STEPS + 1:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
		_button(MOUSE_BUTTON_RIGHT, false)
	if _tick == ZOOM_TICK:
		_action_tap(&"camera_zoom_in")
	elif _tick == ZOOM_TICK + 5:
		_action_tap(&"camera_zoom_out")
	if _tick == SNAP_HOME_TICK:
		_action_set(&"camera_snap_home", true)
	elif _tick == SNAP_HOME_TICK + 20:
		_action_set(&"camera_snap_home", false)
	elif _tick == CAMERA_RESET_TICK:
		_action_tap(&"camera_reset")


## Pause, chat and results gates (audit V6), each followed by a click that must or must not place.
func _script_gate() -> void:
	match _tick:
		PAUSE_OPEN_TICK:
			Events.pause_menu_opened.emit()
		PAUSE_CLICK_TICK:
			_click_place()
		PAUSE_CLOSE_TICK:
			Events.pause_menu_closed.emit()
		CHAT_OPEN_TICK:
			Events.chat_input_opened.emit()
		CHAT_CLOSE_TICK:
			Events.chat_input_closed.emit()
		RESULTS_TICK:
			Events.match_results_ready.emit({})
		SCOPE_RESET_TICK:
			Events.match_scope_reset.emit()


func _hold(action: StringName, start: int) -> void:
	if _tick == start:
		Input.action_press(action)
	elif _tick == start + HOLD_TICKS:
		Input.action_release(action)


func _clear_input() -> void:
	Input.flush_buffered_events()
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)


func _motion(relative: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.relative = relative
	Input.parse_input_event(event)


func _button(index: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)


func _wheel(index: MouseButton) -> void:
	_button(index, true)
	_button(index, false)


func _action_set(action: StringName, pressed: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _action_tap(action: StringName) -> void:
	_action_set(action, true)
	_action_set(action, false)


## A plain click on ghost_place; the recorded intent is the pose the controller is about to send.
func _click_place() -> void:
	var ghost: GhostPreview = _controller.get_node(_controller.ghost_path) as GhostPreview
	var key: String = "t%04d.intent." % _tick
	_record[key + "slot"] = HOST_SLOT
	_record[key + "feed_seq"] = Match.feed_seq(HOST_SLOT)
	_record[key + "held"] = String(Match.held_special(HOST_SLOT))
	_record[key + "orientation"] = ghost.orientation_index
	_put_vector(key + "origin", ghost.global_position)
	_put_quat(key + "free_quat", ghost.free_quaternion)
	_button(MOUSE_BUTTON_LEFT, true)
	_button(MOUSE_BUTTON_LEFT, false)


# --- recording ------------------------------------------------------------------------------

func _on_feed_block_issued(slot_id: int, shape_id: StringName, next_shape_id: StringName) -> void:
	_events.append("%d|feed_block_issued|%d|%s|%s" % [_tick, slot_id, shape_id, next_shape_id])


func _on_placement_rejected(slot_id: int, reason: StringName) -> void:
	_events.append("%d|placement_rejected|%d|%s" % [_tick, slot_id, reason])


func _on_placement_relocated(slot_id: int, point: Vector2) -> void:
	_events.append("%d|placement_relocated|%d|%s|%s" % [_tick, slot_id, _r(point.x), _r(point.y)])


func _on_turn_changed(slot_id: int) -> void:
	_events.append("%d|turn_changed|%d" % [_tick, slot_id])


func _on_block_placed(block: RigidBody3D, shape_id: StringName) -> void:
	var at: Vector3 = block.global_position
	_events.append("%d|block_placed|%s|%s|%s|%s" % [_tick, shape_id, _r(at.x), _r(at.y), _r(at.z)])
	if _tick >= GIFT_THROW_TICK:
		_watched.append(block)
		_throw_open_tick = _tick


func _r(value: float) -> float:
	return snappedf(value, ROUND_STEP) + 0.0


func _put_vector(key: String, v: Vector3) -> void:
	_record[key + ".x"] = _r(v.x)
	_record[key + ".y"] = _r(v.y)
	_record[key + ".z"] = _r(v.z)


func _put_quat(key: String, q: Quaternion) -> void:
	_record[key + ".x"] = _r(q.x)
	_record[key + ".y"] = _r(q.y)
	_record[key + ".z"] = _r(q.z)
	_record[key + ".w"] = _r(q.w)


func _put_transform(key: String, xf: Transform3D) -> void:
	_put_vector(key + ".o", xf.origin)
	_put_vector(key + ".bx", xf.basis.x)
	_put_vector(key + ".by", xf.basis.y)
	_put_vector(key + ".bz", xf.basis.z)


func _sample() -> void:
	var prefix: String = "t%04d." % _tick
	var ghost: GhostPreview = _controller.get_node(_controller.ghost_path) as GhostPreview
	_put_transform(prefix + "ghost", ghost.global_transform)
	_record[prefix + "ghost.hover"] = _r(ghost.manual_hover_offset)
	_record[prefix + "ghost.orientation"] = ghost.orientation_index
	_record[prefix + "ghost.visible"] = int(ghost.visible)
	_record[prefix + "ghost.tint"] = String(ghost.current_state())
	_record[prefix + "input_enabled"] = int(_controller.input_enabled)
	_record[prefix + "rig_blocked"] = int(_rig.is_input_blocked())
	_put_transform(prefix + "cam", _rig.get_camera().global_transform)
	_record[prefix + "cam.fov"] = _r(_rig.get_camera().fov)
	_record[prefix + "cam.dist"] = _r(_rig.get_distance())
	_put_vector(prefix + "cam.target", _rig.get_target())
	_record[prefix + "held_special"] = String(Match.held_special(HOST_SLOT))
	_sample_held(prefix)
	_sample_arc(prefix)
	var remote: GhostPreview = _remote.ghost_for_slot(REMOTE_SLOT)
	if remote != null:
		_put_transform(prefix + "remote", remote.global_transform)
		_record[prefix + "remote.orientation"] = remote.orientation_index
	for i: int in range(_watched.size()):
		if _tick - _throw_open_tick < THROW_WATCH_TICKS and is_instance_valid(_watched[i]):
			_put_vector("%sflight%d" % [prefix, i], _watched[i].global_position)


func _sample_held(prefix: String) -> void:
	var held: LocalHeldView = Match.context().local_held()
	_record[prefix + "held.slot"] = held.slot_id
	_record[prefix + "held.shape"] = String(held.shape.id) if held.shape != null else ""
	_put_vector(prefix + "held.origin", held.origin)
	_record[prefix + "held.orientation"] = held.orientation_index
	_put_quat(prefix + "held.free_quat", held.free_quat)
	_record[prefix + "held.visible"] = int(held.visible)
	_record[prefix + "held.height"] = _r(held.height_above_surface)
	if _wallclock:
		_record[prefix + "held.updated_msec"] = held.updated_msec


func _sample_arc(prefix: String) -> void:
	var launch: Dictionary = _controller.gift_launch_preview()
	if launch.is_empty():
		return
	_put_vector(prefix + "arc.origin", launch["origin"] as Vector3)
	_put_vector(prefix + "arc.velocity", launch["velocity"] as Vector3)
	_record[prefix + "arc.gravity"] = _r(float(launch["gravity_scale"]))


func _finish() -> void:
	_record["events"] = _events
	var text: String = JSON.stringify(_record, "\t", true)
	if not _out_path.is_empty():
		var file: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
		if file == null:
			push_error("bench_p3_parity: cannot write %s" % _out_path)
			get_tree().quit(1)
			return
		file.store_string(text)
		file.close()
	print("BENCH_P3_PARITY sha256=%s ticks=%d keys=%d events=%d" % [text.sha256_text(), END_TICK, _record.size(), _events.size()])
	get_tree().quit(0)


## Prints the per-field maximum difference and returns the exit code (1 on any difference above `tol`).
func _compare(arg: String, tol: float) -> int:
	var parts: PackedStringArray = arg.split(",")
	if parts.size() != 2:
		push_error("bench_p3_parity: --compare needs a.json,b.json")
		return 1
	var a: Variant = JSON.parse_string(FileAccess.get_file_as_string(parts[0]))
	var b: Variant = JSON.parse_string(FileAccess.get_file_as_string(parts[1]))
	if not (a is Dictionary and b is Dictionary):
		push_error("bench_p3_parity: unreadable recording")
		return 1
	var left: Dictionary = a as Dictionary
	var right: Dictionary = b as Dictionary
	var tolerances: Dictionary = {"": tol} if tol > 0.0 else {}
	var differing: PackedStringArray = MatchFingerprint.diff(left, right, tolerances)
	var worst: Dictionary = {}
	for line: String in differing:
		var key: String = line.get_slice(": ", 0)
		var field: String = key.substr(key.find(".") + 1) if key.begins_with("t") else key
		var current: float = worst.get(field, 0.0)
		var numeric: bool = left.has(key) and right.has(key) and (left[key] is float or left[key] is int) and (right[key] is float or right[key] is int)
		worst[field] = maxf(current, absf(float(left[key]) - float(right[key]))) if numeric else INF
	var fields: Array = worst.keys()
	fields.sort()
	for field: String in fields:
		print("BENCH_P3_PARITY field=%s max_diff=%s" % [field, worst[field]])
	print("BENCH_P3_PARITY compare keys=%d differing=%d tol=%s" % [left.size(), differing.size(), tol])
	return 1 if not differing.is_empty() else 0
