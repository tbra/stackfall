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


func test_camera_starts_in_the_final_follow_view_for_each_map_size() -> void:
	for path: String in MAP_PATHS:
		var map: MapDef = (load(path) as MapDef).duplicate(true)
		await _start_match(map)
		var rig: CameraRig = _main._camera_rig
		var tuning: CameraTuning = rig.tuning
		assert_true(rig.begin_start_framing(HELD_SLOT), path)
		assert_almost_eq(rig.get_pitch(), deg_to_rad(tuning.start_pitch_deg), 0.0001, "%s: start pitch (view 3)" % path)
		assert_almost_eq(rig.get_distance(), clampf(tuning.start_distance_m, tuning.zoom_min, tuning.zoom_max), 0.0001, "%s: follow distance" % path)
		# Bontago-1pi.90: the pivot is the held piece's spawn anchor, the point the
		# follow tracks once play starts, not the bare beacon.
		var anchor: Vector3 = _main._hot_seat.controller()._camera_follow_anchor()
		assert_lt(rig.get_target().distance_to(anchor), POSITION_TOLERANCE_M, "%s: pivots on the held piece" % path)
		assert_gt(rig.get_target().distance_to(_home(HELD_SLOT)), POSITION_TOLERANCE_M, "%s: not on the bare beacon" % path)
		var first: Transform3D = rig.get_camera().global_transform
		# Ghost follow runs from the first frame; GO changes nothing about the pose.
		var follow: Vector3 = rig.get_target()
		rig.set_follow_position(follow)
		rig._process(0.016)
		assert_lt(rig.get_camera().global_position.distance_to(first.origin), POSITION_TOLERANCE_M, "%s: no shift on the first frame" % path)
		_step_countdown()
		for _i: int in range(60):
			rig.set_follow_position(follow)
			rig._process(0.016)
		assert_eq(Match.state(), Match.State.PLAYING)
		assert_lt(rig.get_camera().global_position.distance_to(first.origin), POSITION_TOLERANCE_M, "%s: no ease or shift through GO" % path)
		_main.queue_free()
		await get_tree().process_frame
		Net.leave()


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


func test_hud_stats_and_minimap_are_populated_in_the_countdown() -> void:
	var map: MapDef = (load(MAP_PATHS[0]) as MapDef).duplicate(true)
	await _start_match(map)
	var hud: HUD = _main._hot_seat.hud()
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	assert_eq(hud._share_rows.size(), Match.slot_count(), "one stats row per player before the first solve")
	assert_true(hud._minimap.visible, "minimap shown in the countdown")
