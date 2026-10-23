extends GutTest
## Characterization of what a returned-to-lobby Match gives back, read only through the
## public API: Match accessors, the territory raster and MatchFingerprint. Each controller
## (block feed, territory, gifts, stats, lifecycle clocks, the Field tilt) hands its state
## back when a match is aborted, and a match started after that is indistinguishable from
## the first one in a process. It must keep passing however the reset is split between the
## controllers.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const STEP: float = 1.0 / 60.0
const SETTLE_FRAME_CAP: int = 600
const EXTRA_SOLVE_STEPS: int = 90
const SEED: int = 4242
const FIELD_RADIUS: float = 20.0
const BLOCK_TIMER_S: float = 6.0
const RUN_AFTER_START_S: float = 2.0
const GLUE_DROPS: int = 2
const TILT_IMPULSE: float = 5.0
const TILT_STEPS: int = 20
const TILT_STEP_S: float = 0.05
const TURN_RUN_S: float = 7.0  # past TerritoryTuning.turn_based_max_settle_s
const ROUND_MINUTES: int = 2

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _mains: Array[Node] = []


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	Net.leave()
	SnapshotSync.end_match()
	Match._lifecycle._host_bot_names = PackedStringArray()


func after_each() -> void:
	Match._net_provider = null
	Match.set_replicator(null)
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	for main: Node in _mains:
		if is_instance_valid(main):
			main.queue_free()
	_mains.clear()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame
	await get_tree().process_frame


# --- fixtures -------------------------------------------------------------------------

func _light_world() -> void:
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = FIELD_RADIUS
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func _config(game_mode: int = MatchConfig.GameMode.CLASSIC, turn_based: bool = false) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.block_timer = BLOCK_TIMER_S
	config.rng_seed = SEED
	config.game_mode = game_mode as MatchConfig.GameMode
	config.round_timer_minutes = ROUND_MINUTES
	config.turn_based = turn_based
	config.scripted_gifts = true  # opens debug_queue_special; the same in every match compared
	return config


func _start_playing(config: MatchConfig) -> void:
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(STEP)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: playing")


func _place(slot_id: int) -> StringName:
	var home: Vector2 = Match.slot(slot_id).home_position
	var world: Vector3 = _field.to_global(Vector3(home.x, 5.0, home.y))
	return Match.request_place(slot_id, world, 0, Quaternion.IDENTITY, false)


func _step() -> void:
	await wait_physics_frames(1)
	Match._process(STEP)


func _run(seconds: float) -> void:
	for _i: int in range(int(ceil(seconds / STEP))):
		Match._process(STEP)


## Match A, left in a state every controller has something to give back: a placed block with
## its solve applied, a held shape and a running feed timer, a queued special and glue, a
## credited elimination, a tilted disc, a stopped feed timer.
func _play_dirty_a(config: MatchConfig) -> void:
	_start_playing(config)
	assert_eq(_place(0), PlacementRules.REASON_OK, "fixture: slot 0 placed on its home flag")
	for _i: int in range(SETTLE_FRAME_CAP):
		await _step()
		if _registry.all_settled():
			break
	assert_true(_registry.all_settled(), "fixture: the block settled")
	for _i: int in range(EXTRA_SOLVE_STEPS):
		await _step()
	assert_gt(Match.raster().content_revision(), 0, "fixture: a territory solve ran")
	assert_gt(Match.territory_share(0), 0.0, "fixture: the block claimed ground")
	assert_not_null(Match.held_shape(1), "fixture: slot 1 holds a shape")
	assert_lt(Match.feed_time_left(1), BLOCK_TIMER_S, "fixture: slot 1's feed timer is running down")
	assert_eq(Match.feed_seq(0), 1, "fixture: slot 0 consumed one block")
	assert_eq(Match.stats().blocks_placed(0), 1, "fixture: the placement is in the stats")
	assert_true(Match.debug_queue_special(0, &"anvil"), "fixture: a special is queued")
	assert_true(Match.grant_glue_drops(0, GLUE_DROPS))
	assert_eq(Match.glue_drops_left(0), GLUE_DROPS)
	assert_eq(Match.pending_special_count(0), 1)
	Match.apply_replicated_elimination(1, 0)
	assert_eq(Match.eliminated_by(1), 0, "fixture: slot 1's elimination is credited")
	assert_gt((Match.circle_render_arrays()["goal_positions"] as PackedVector2Array).size() + _circle_count(), 0)
	_field.apply_tilt_impulse(Vector2.RIGHT, TILT_IMPULSE)
	for _i: int in range(TILT_STEPS):
		_field._physics_process(TILT_STEP_S)
	assert_ne(_field.tilt_vector(), Vector2.ZERO, "fixture: the disc is tilted")
	Match.set_feed_timer_enabled(false)
	assert_false(Match.feed_timer_enabled(), "fixture: the feed timer is stopped")


## Blocks the next frame will still see: a reset frees them with queue_free().
func _live_blocks() -> int:
	var count: int = 0
	for block: Block in _registry.all_blocks():
		if not block.is_queued_for_deletion():
			count += 1
	return count


func _circle_count() -> int:
	return (Match.circle_render_arrays()["xs"] as PackedFloat32Array).size()


## Everything a caller can read from the running match, as plain values.
func _reads() -> Dictionary:
	var out: Dictionary = {}
	out["state"] = int(Match.state())
	out["slots"] = Match.slot_count()
	out["active_slot"] = Match.active_slot()
	out["timer_left"] = snappedf(Match.match_timer_left(), 0.001)
	out["feed_timer_enabled"] = Match.feed_timer_enabled()
	out["winner"] = Match.winner_team()
	out["circles"] = _circle_count()
	out["blocks"] = _live_blocks()
	var per_slot: Array = []
	for slot_id: int in range(Match.slot_count()):
		var held: BlockShape = Match.held_shape(slot_id)
		var next: BlockShape = Match.next_shape(slot_id)
		per_slot.append([
			str(held.id) if held != null else "", str(next.id) if next != null else "",
			snappedf(Match.feed_time_left(slot_id), 0.001), Match.feed_seq(slot_id),
			Match.is_release_locked(slot_id), str(Match.held_special(slot_id)),
			Match.pending_special_count(slot_id), Match.glue_drops_left(slot_id),
			Match.eliminated_by(slot_id), Match.stats().blocks_placed(slot_id),
			snappedf(Match.territory_share(slot_id), 0.0001),
		])
	out["per_slot"] = per_slot
	var raster: TerritoryRaster = Match.raster()
	out["raster_revision"] = raster.content_revision() if raster != null else -1
	out["tilt"] = _field.tilt_vector()
	out["mode_state"] = Match.mode_state_snapshot().size()
	return out


# --- what the lobby shows after an abort -------------------------------------------------

func test_aborting_a_played_match_hands_back_every_controllers_state() -> void:
	_light_world()
	await _play_dirty_a(_config(MatchConfig.GameMode.DOMINATION))
	assert_gt(Match.match_timer_left(), 0.0, "fixture: the round timer is armed")
	assert_false(Match.mode_state_snapshot().is_empty(), "fixture: the mode objective is live")
	assert_gt(_live_blocks(), 0, "fixture: a block is on the field")
	assert_not_null(Match.cell_grid(), "fixture: the cell grid exists")
	assert_not_null(Match.config, "fixture: the config is held")

	Match.abort_match()

	assert_eq(Match.state(), Match.State.LOBBY)
	# block store
	assert_eq(_live_blocks(), 0, "no block stays in the registry")
	for child: Node in _blocks_root.get_children():
		assert_true(child.is_queued_for_deletion(), "no block node stays under the blocks parent")
	# slots and the feed controller
	assert_eq(Match.slot_count(), 0, "no seats")
	assert_null(Match.next_shape(0), "no bag deals a next shape")
	assert_null(Match.held_shape(0), "no shape is held")
	assert_null(Match.held_shape(1))
	assert_eq(Match.feed_time_left(1), 0.0, "no feed timer runs")
	assert_eq(Match.feed_seq(0), -1, "no feed sequence is kept")
	assert_false(Match.is_release_locked(0), "no release lock is kept")
	assert_true(Match.feed_timer_enabled(), "the feed timer is enabled again")
	# lifecycle
	assert_eq(Match.eliminated_by(1), -1, "no elimination is credited")
	assert_eq(Match.active_slot(), -1, "no active slot")
	assert_eq(Match.match_timer_left(), 0.0, "the round timer is cleared")
	assert_eq(Match.countdown_remaining(), 0.0)
	assert_null(Match.config, "the config is dropped")
	assert_eq(Match.feed_progress(1), 0.0)
	# territory
	assert_null(Match.raster(), "no raster")
	assert_null(Match.cell_grid(), "no cell grid")
	assert_eq(Match.territory_share(0), 0.0)
	assert_eq(Match.winner_team(), -1)
	assert_true(Match.mode_state_snapshot().is_empty(), "no objective keeps mode state")
	assert_true(Match.fresh_solve_matches_live(), "no solver has a board to compare")
	var circles: Dictionary = Match.circle_render_arrays()
	assert_eq((circles["xs"] as PackedFloat32Array).size(), 0, "no influence circles")
	assert_eq((circles["teams"] as PackedInt32Array).size(), 0)
	# gifts and stats
	assert_eq(Match.pending_special_count(0), 0, "no queued special")
	assert_eq(Match.held_special(0), &"")
	assert_eq(Match.glue_drops_left(0), 0, "no glue charge")
	assert_eq(Match.stats().blocks_placed(0), 0, "no placement is counted")
	# Field
	assert_eq(_field.tilt_vector(), Vector2.ZERO, "the disc is level")
	_field.apply_tilt_impulse(Vector2.RIGHT, TILT_IMPULSE)
	_field._physics_process(TILT_STEP_S)
	assert_eq(_field.tilt_vector(), Vector2.ZERO, "tilt is off while the field sits idle")


func test_a_countdown_held_in_one_match_does_not_hold_the_next() -> void:
	_light_world()
	Match.start_match(_config())
	Match.set_countdown_held(true)
	_run(Match.COUNTDOWN_SECONDS + 1.0)
	assert_eq(Match.state(), Match.State.COUNTDOWN, "fixture: the hold stops the countdown")
	Match.abort_match()

	_start_playing(_config())


func test_a_turn_wait_armed_in_one_match_does_not_hand_over_the_next_matchs_turn() -> void:
	_light_world()
	_start_playing(_config(MatchConfig.GameMode.CLASSIC, true))
	var first: int = Match.active_slot()
	_run(TURN_RUN_S)
	assert_eq(Match.active_slot(), first, "fixture: with no placement a fresh turn match keeps its turn")
	Match.abort_match()

	_start_playing(_config(MatchConfig.GameMode.CLASSIC, true))
	var turn_slot: int = Match.active_slot()
	assert_eq(_place(turn_slot), PlacementRules.REASON_OK, "fixture: the turn's block is placed")
	assert_eq(Match.active_slot(), turn_slot, "fixture: the turn waits for the block to settle")
	Match.abort_match()
	await get_tree().process_frame  # the freed block leaves the registry, so nothing but a stale wait could move the turn

	_start_playing(_config(MatchConfig.GameMode.CLASSIC, true))
	assert_eq(Match.active_slot(), first, "the first tick of the new match leaves the turn alone")
	_run(TURN_RUN_S)
	assert_eq(Match.active_slot(), first, "nobody placed, so the turn stays")


# --- a match after a played one equals the first match -----------------------------------

func test_a_match_after_a_played_one_reads_like_a_fresh_one() -> void:
	_light_world()
	_start_playing(_config(MatchConfig.GameMode.DOMINATION))
	await _settle_frames()
	var fresh: Dictionary = _reads()
	Match.abort_match()

	await _play_dirty_a(_config(MatchConfig.GameMode.DOMINATION))
	Match.abort_match()
	_start_playing(_config(MatchConfig.GameMode.DOMINATION))
	await _settle_frames()
	var again: Dictionary = _reads()

	assert_eq(again, fresh, "every public read of match B equals a fresh match's")
	assert_eq((again["per_slot"] as Array).size(), 2)
	assert_true(Match.feed_timer_enabled())
	assert_eq(Match.raster().content_revision(), fresh["raster_revision"], "no solve of A touched B's raster")


func _settle_frames() -> void:
	for _i: int in range(int(ceil(RUN_AFTER_START_S / STEP))):
		await _step()


# --- the same, on a real Main through the fingerprint ------------------------------------

func _new_main() -> Node:
	var main: Node = MAIN_SCENE.instantiate()
	(main.get_node("Field") as Field).map_def = _tiny_map
	add_child(main)
	_mains.append(main)
	return main


func _main_config() -> MatchConfig:
	var config: MatchConfig = _config()
	config.weather_mode = MatchConfig.WeatherMode.OFF
	config.sky_theme_mode = MatchConfig.SkyThemeMode.DAY
	return config


func _host() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)


func _main_place(main: Node, slot_id: int) -> StringName:
	var field: Field = main.get_node("Field") as Field
	var home: Vector2 = Match.slot(slot_id).home_position
	return Match.request_place(slot_id, field.to_global(Vector3(home.x, 5.0, home.y)), 0, Quaternion.IDENTITY, false)


func _fingerprint_b(main: Node) -> Dictionary:
	await get_tree().process_frame
	await get_tree().process_frame
	_run(Match.COUNTDOWN_SECONDS + 1.0)
	await get_tree().process_frame
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: B is playing")
	return MatchFingerprint.without_volatile(MatchFingerprint.capture(main))


func test_a_main_match_after_a_played_one_fingerprints_like_a_fresh_one() -> void:
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = FIELD_RADIUS
	var reference_main: Node = _new_main()
	_host()
	reference_main._on_lobby_start_requested(_main_config())
	var reference: Dictionary = await _fingerprint_b(reference_main)
	Net.leave()
	Match.abort_match()
	_mains.erase(reference_main)
	reference_main.queue_free()
	await get_tree().process_frame

	var main: Node = _new_main()
	_host()
	main._on_lobby_start_requested(_main_config())
	await get_tree().process_frame
	_run(Match.COUNTDOWN_SECONDS + 1.0)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: A is playing")
	assert_eq(_main_place(main, 0), PlacementRules.REASON_OK, "fixture: A placed a block")
	assert_not_null(Match.held_shape(1), "fixture: A holds a shape")
	for _i: int in range(SETTLE_FRAME_CAP):
		await wait_physics_frames(1)
		Match._process(STEP)
		if Match.registry().all_settled():
			break
	_run(RUN_AFTER_START_S)
	assert_gt(Match.raster().content_revision(), 0, "fixture: A's territory solved")
	assert_gt(Match.registry().all_blocks().size(), 0, "fixture: A left a block")
	main._on_pause_leave_requested()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(Match.state(), Match.State.LOBBY)

	_host()
	main._on_lobby_start_requested(_main_config())
	var again: Dictionary = await _fingerprint_b(main)

	var found: PackedStringArray = MatchFingerprint.diff(reference, again)
	assert_eq(found.size(), 0, "B differs from a fresh launch in:\n  %s" % "\n  ".join(found))
