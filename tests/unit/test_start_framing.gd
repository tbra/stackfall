extends GutTest
## Bontago-1pi.79 (owner playtest 2026-10-04): the match opens at the owner's
## start framing with the first ghost in hand and the HUD populated. Real Main
## scene on a host; the rig's begin_start_framing() is what Main calls when the
## ready gate opens (the headless run has no loading overlay, so it is driven
## directly), compared with CameraTuning's configured values per map size.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const MAP_PATHS: Array[String] = [
	"res://config/maps/round_small.tres",
	"res://config/maps/round_medium.tres",
	"res://config/maps/round_large.tres",
]
const POSITION_TOLERANCE_M: float = 0.01
const HELD_SLOT: int = 0

var _main: Variant = null


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame


func _start_match(map: MapDef) -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	(_main.get_node("Field") as Field).map_def = map
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.rng_seed = 777
	_main.match_config = config
	add_child_autofree(_main)
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=1", "--players=2"]))
	await get_tree().process_frame
	await get_tree().process_frame


func _step_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home(slot: int) -> Vector3:
	for flag: HomeFlag in Match.field().home_flags():
		if flag.slot_id() == slot:
			return flag.global_position
	return Vector3.ZERO


func test_camera_equals_configured_start_framing_for_each_map_size() -> void:
	for path: String in MAP_PATHS:
		var map: MapDef = (load(path) as MapDef).duplicate(true)
		await _start_match(map)
		var rig: CameraRig = _main._camera_rig
		var tuning: CameraTuning = rig.tuning
		assert_true(rig.begin_start_framing(HELD_SLOT), path)
		var home: Vector3 = _home(HELD_SLOT)
		var away: Vector3 = Vector3(home.x, 0.0, home.z).normalized()
		var pitch: float = deg_to_rad(tuning.start_pitch_deg)
		var distance: float = tuning.start_distance(map.field_radius)
		var pivot: Vector3 = tuning.start_pivot(home)
		var expected: Vector3 = pivot + Vector3(away.x * cos(pitch), -sin(pitch), away.z * cos(pitch)) * distance
		var actual: Vector3 = rig.get_camera().global_position
		assert_lt(actual.distance_to(expected), POSITION_TOLERANCE_M, "%s: camera sits at the configured framing" % path)
		assert_gt(actual.y, 0.0, "%s: raised above the disc" % path)
		assert_gt(Vector2(actual.x, actual.z).length(), map.field_radius, "%s: just outside the rim" % path)
		# Held through the whole countdown, not dragged to the ghost.
		_step_countdown_frames_before_play(rig, expected)
		_main.queue_free()
		await get_tree().process_frame
		Net.leave()


func _step_countdown_frames_before_play(rig: CameraRig, expected: Vector3) -> void:
	rig._process(0.016)
	rig.set_follow_position(Vector3(3.0, 4.0, 5.0))
	rig._process(0.016)
	assert_lt(rig.get_camera().global_position.distance_to(expected), POSITION_TOLERANCE_M, "countdown holds the framing")
	assert_true(rig.is_start_framing())


func test_first_gameplay_frame_has_ghost_hud_cards_and_rows() -> void:
	var map: MapDef = (load(MAP_PATHS[0]) as MapDef).duplicate(true)
	await _start_match(map)
	var hud: HUD = _main._hot_seat.hud()
	var ghost: GhostPreview = _main._hot_seat.ghost()
	# Gate-open moment (COUNTDOWN): already populated.
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	assert_not_null(Match.held_shape(HELD_SLOT), "first block issued when the countdown exists")
	assert_not_null(ghost.get_shape(), "local ghost holds the first block at gate open")
	assert_not_null(hud._held_shape, "HELD card populated at gate open")
	assert_not_null(hud._next_shape, "NEXT card populated at gate open")
	var held_id: StringName = ghost.get_shape().id
	_step_countdown()
	await get_tree().process_frame
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_eq(ghost.get_shape().id, held_id, "the same first block, not a re-issue, on the first PLAYING frame")
	assert_not_null(hud._held_shape, "HELD card populated")
	assert_not_null(hud._next_shape, "NEXT card populated")
	assert_eq(hud._share_rows.size(), Match.slot_count(), "one score row per player")


func test_client_mirror_populates_held_and_next_cards_during_the_countdown() -> void:
	var map: MapDef = (load(MAP_PATHS[0]) as MapDef).duplicate(true)
	await _start_match(map)
	var hud: HUD = _main._hot_seat.hud()
	hud.set_held_shape(null)
	hud.set_next_shape(null)
	var held: BlockShape = Match.held_shape(HELD_SLOT)
	var next: BlockShape = Match.next_shape(HELD_SLOT)
	# What a client receives over the wire for the host's countdown-time issue.
	Events.feed_block_issued.emit(HELD_SLOT, held.id, next.id)
	assert_eq(hud._held_shape.id if hud._held_shape != null else &"", held.id)
	assert_eq(hud._next_shape.id if hud._next_shape != null else &"", next.id)


func test_late_bound_controller_pulls_the_held_block_into_its_ghost() -> void:
	# The staged windowed build issues (host) / receives (client) the first block
	# before the controller exists; binding afterwards must still fill the ghost.
	var map: MapDef = (load(MAP_PATHS[0]) as MapDef).duplicate(true)
	await _start_match(map)
	var ghost: GhostPreview = _main._hot_seat.ghost()
	ghost.set_shape(null)
	assert_null(ghost.get_shape())
	_main._hot_seat.bind_local_slot(HELD_SLOT)
	assert_not_null(ghost.get_shape(), "bind pulls the slot's held block")
	assert_eq(ghost.get_shape().id, Match.held_shape(HELD_SLOT).id)


func test_player_camera_input_during_the_hold_takes_over() -> void:
	var map: MapDef = (load(MAP_PATHS[0]) as MapDef).duplicate(true)
	await _start_match(map)
	var rig: CameraRig = _main._camera_rig
	assert_true(rig.begin_start_framing(HELD_SLOT))
	rig._process(0.016)
	var before: float = rig.get_distance()
	rig.zoom_by_orbit_step(1.0)
	var zoomed: float = rig.get_distance()
	assert_ne(zoomed, before)
	rig._process(0.016)
	assert_false(rig.is_start_framing(), "input ends the hold")
	assert_almost_eq(rig.get_distance(), zoomed, 0.001, "and is not overwritten")
