extends GutTest
## Bontago-mv0.35 (second pass): "there is still a maximum height the block
## cannot be raised or placed above", owner on main c50510c in a real
## `--headless-host --bots=3 --players=4` match. These drive the *real* match
## path, not the bare sandbox fixture: the real Main scene, a real
## Net.host_game() listen server, Match started through Main's own
## `_start_headless_bot_match_with_args()` (the exact function the owner's
## command line reaches), and the HotSeat PlayerController / GhostPreview /
## CameraRig / HUD that Main itself wires for the host's slot 0.
##
## Trace result that motivated the fix (see the package report): on that path
## nothing clamped the wheel below GhostTuning.hover_manual_max (60 m) and a
## place at 55 m was accepted -- the caps the owner could actually hit were
## (1) the 60 m manual cap itself, 12 m short of the wire band, (2) the held
## PageUp/gamepad raise at a flat 1 m/s, which the 6 s feed timer auto-drops
## after ~6 m, and (3) no on-screen sign the block was rising at all: the
## follow camera keeps the ghost centred and the HUD's only "Height" line is
## the tallest *placed* tower, which stays put while the ghost is raised.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const HOST_SLOT: int = 0
## The owner's report and this package's brief: raising must reach at least
## this far above the disk, and a placement there must be accepted.
const REQUIRED_RAISE_M: float = 50.0
## How far under the band's ceiling a pose may stop and still count as
## "reached the band": one wheel notch plus float slack.
const BAND_TOLERANCE_M: float = 0.5
## A held raise over one block timer must clear at least this much.
const REQUIRED_HELD_RAISE_M: float = 30.0

var _main: Variant = null
var _tiny_map: MapDef
var _net_config: NetConfig = preload("res://config/net_config.tres")
## Clear of test_net_session (47800+), test_match_lifecycle (47900+) and
## test_headless_bot_match (48300+).
static var _next_port: int = 48700


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.rng_seed = 13579
	_main.match_config = config
	add_child_autofree(_main)


func after_each() -> void:
	Input.action_release(&"hover_raise")
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame


func _take_port() -> int:
	var port: int = _next_port
	_next_port += 1
	return port


## The owner's own path: a listen server, then Main's --bots= match build
## (one bot, one human so the test's tiny map stays cheap), countdown pumped
## by hand so Match's feed timer never auto-drops mid-test.
func _start_hosted_match() -> void:
	assert_eq(Net.host_game(_take_port(), "Hostie"), OK)
	assert_eq(Net.mode(), Net.Mode.HOST, "fixture: Net must really be the host")
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=1", "--players=2"]))
	await get_tree().process_frame
	await get_tree().process_frame
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture should reach PLAYING")
	await get_tree().process_frame
	await get_tree().process_frame


func _controller() -> PlayerController:
	return _main._hot_seat.controller()


func _wheel_up() -> InputEventMouseButton:
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	event.position = centre
	event.global_position = centre
	return event


func _trace(label: String) -> void:
	var controller: PlayerController = _controller()
	var ghost: GhostPreview = controller._ghost
	var rig: CameraRig = _main._camera_rig
	gut.p("%s offset=%.2f origin_y=%.2f block_h=%.2f cam_target_y=%.2f frustum=%s state=%s ceiling=%.2f" % [
		label, ghost.manual_hover_offset, ghost.global_position.y, ghost.height_above_surface(),
		rig.get_target().y, rig.get_camera().is_position_in_frustum(ghost.rotated_center_world()),
		ghost.current_state(), controller._hover_offset_ceiling(),
	])


## Wheels up through the real viewport (Input.parse_input_event, the route a
## real mouse notch takes: GUI first, then _unhandled_input), one notch per
## frame, until the ghost stops rising or `max_notches` run out.
func _wheel_until_stuck(max_notches: int) -> void:
	var controller: PlayerController = _controller()
	var stalled: int = 0
	for i: int in range(max_notches):
		var before: float = controller._ghost.manual_hover_offset
		Input.parse_input_event(_wheel_up())
		var release: InputEventMouseButton = _wheel_up()
		release.pressed = false
		Input.parse_input_event(release)
		await get_tree().process_frame
		if i % 25 == 0:
			_trace("notch %d" % i)
		stalled = stalled + 1 if is_equal_approx(controller._ghost.manual_hover_offset, before) else 0
		if stalled >= 3:
			break
	_trace("stopped")


func test_wheel_reaches_the_wire_band_and_the_host_accepts_the_placement() -> void:
	await _start_hosted_match()
	var controller: PlayerController = _controller()
	assert_not_null(controller._ghost.get_shape(), "fixture: slot 0 holds a block")
	_trace("start")
	var notches: int = int(ceil(_net_config.pos_max_y / controller.ghost_tuning.hover_wheel_step)) + 10
	await _wheel_until_stuck(notches)

	var origin_y: float = controller._ghost.global_position.y
	var band_top: float = _net_config.pos_max_y - controller.ghost_tuning.hover_ceiling_margin
	assert_gte(controller._ghost.manual_hover_offset, REQUIRED_RAISE_M, "the wheel must raise the block past 50 m")
	assert_gte(
		origin_y, band_top - BAND_TOLERANCE_M,
		"the raise must only stop at the wire band's own ceiling (pos_max_y - hover_ceiling_margin), not at a cap below it (was 60.3 m)"
	)
	assert_lte(origin_y, _net_config.pos_max_y, "and never above the band the host can replicate")

	var blocks: Node = _main.get_node("BlocksContainer")
	var blocks_before: int = blocks.get_child_count()
	var reason: StringName = controller._request_place(false)
	gut.p("place at origin_y=%.2f reason='%s'" % [origin_y, reason])
	assert_eq(reason, PlacementRules.REASON_OK, "the host must accept a placement at the top of the raise")
	assert_eq(blocks.get_child_count(), blocks_before + 1, "and actually spawn it")


func test_held_raise_clears_30m_within_one_block_timer() -> void:
	await _start_hosted_match()
	var controller: PlayerController = _controller()
	var step: float = 1.0 / Engine.physics_ticks_per_second
	var frames: int = int(Match.config.block_timer * Engine.physics_ticks_per_second)
	Input.action_press(&"hover_raise")
	for _i: int in range(frames):
		controller._handle_hover_adjust(step)
		controller._update_ghost_transform()
	Input.action_release(&"hover_raise")
	_trace("held for one block_timer")
	assert_gte(
		controller._ghost.manual_hover_offset, REQUIRED_HELD_RAISE_M,
		"holding PageUp / the gamepad raise for one block timer (%.0f s) must lift the block well clear of a tower -- a flat 1 m/s stopped at ~6 m before the auto-drop" % Match.config.block_timer
	)


func test_hud_shows_the_held_block_height_while_it_is_raised() -> void:
	await _start_hosted_match()
	var controller: PlayerController = _controller()
	for _i: int in range(50):
		controller._unhandled_input(_wheel_up())
	await get_tree().process_frame
	await get_tree().process_frame
	var hud: HUD = _main._hot_seat.hud()
	var text: String = hud._height_label.text
	gut.p("HUD height label: '%s'" % text)
	assert_gte(controller._ghost.height_above_surface(), 19.0, "fixture: 50 notches raise the block ~20 m")
	assert_string_contains(text, "Block: %.1f m" % controller._ghost.height_above_surface())
	assert_string_contains(text, "Tower: ", "the tallest-placed-structure figure is labelled for what it is")
