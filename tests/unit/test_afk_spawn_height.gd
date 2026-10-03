extends GutTest
## Bontago-1pi.40 (follow-up to Bontago-1pi.33, owner playtest 2026-10-03:
## "Start the first block higher up, it loads inside the home beacon").
##
## 1pi.33 raised the *player's* first-block hover above the home beacon, but the
## host's AFK auto-drop (net/MatchNet.gd _on_feed_timer_expired) still fell back
## to Match.default_ghost_origin() -- the home flag at disc level -- for a remote
## slot that never sent a cursor, so that block spawned inside the beacon's
## socket and crystal. The fallback origin now rises to the same clearance the
## player's first block gets (GhostTuning.home_spawn_pivot_height(), built on the
## same home_spawn_clear_hover() PlayerController uses).
##
## These drive the **real** Match and MatchNet (faked Net, no peer), like
## test_match_net.gd: every assertion is about the block the host actually spawned.

const MatchNetScript := preload("res://net/MatchNet.gd")
const MAPS_DIR: String = "res://config/maps/"
## One map per MapDef size (small / medium / large), built at its real radius so
## "every map size" is exercised, not a shrunk stand-in. The beacon height is a
## constant, but flag placement, field and territory geometry are rebuilt per map.
const SIZE_MAPS: PackedStringArray = ["round_small", "round_medium", "round_large"]
const CUBE_PATH: String = "res://config/blocks/cube.tres"
## Float slack for comparing a spawned height against beacon top plus margin.
const HEIGHT_EPSILON: float = 0.0001
const HOST_PEER: int = 1
const REMOTE_PEER: int = 2
const REMOTE_SLOT: int = 1
## A malformed orientation index (one past the table) for the never-stored-cursor case.
const BAD_ORIENTATION: int = BlockOrientations.ORIENTATION_COUNT

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _net: MatchNetScript
var _fake_net: FakeNet
var _ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
var _beacon_visuals: BeaconVisualTuning = preload("res://config/beacon_visual_tuning.tres")
var _physics_tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()


func after_each() -> void:
	_teardown_world()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _teardown_world() -> void:
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	for node: Node in [_field, _blocks_root, _registry]:
		if node != null and is_instance_valid(node):
			node.free()
	_field = null
	_blocks_root = null
	_registry = null


## A listen-server host (peer 1, slot 0) with one remote client (peer 2,
## slot 1) on a match played on `map` (used as-is: no radius shrinking).
func _start_host_match(map: MapDef) -> void:
	_field = Field.new()
	_field.map_def = map
	add_child(_field)
	_blocks_root = Node3D.new()
	add_child(_blocks_root)
	_registry = BlockRegistry.new()
	add_child(_registry)
	Match.register_world(_field, _registry, _blocks_root)

	var peer_slots: Dictionary = {HOST_PEER: 0, REMOTE_PEER: REMOTE_SLOT}
	_fake_net = FakeNet.host(peer_slots, [0])
	_fake_net.slots_by_peer = peer_slots
	Match.set_net_provider(_fake_net)
	_net = MatchNetScript.new()
	_net.set_process(false)
	add_child(_net)
	_net.set_providers(_fake_net, Match)

	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 4242
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture should reach PLAYING")


func _load_map(map_name: String) -> MapDef:
	return load(MAPS_DIR + map_name + ".tres") as MapDef


## World Y of the spawned block's real lowest point: its collision boxes sit
## cube_margin/2 inside the shape's nominal bottom, so the node origin alone
## under-reads it (same measure test_home_spawn_height.gd uses for the player).
func _lowest_point_y(block: Node3D) -> float:
	var lowest: float = INF
	for child: Node in block.get_children():
		var box: CollisionShape3D = child as CollisionShape3D
		if box != null and box.shape is BoxShape3D:
			lowest = minf(lowest, box.global_position.y - (box.shape as BoxShape3D).size.y * 0.5)
	return lowest


func _beacon_top_y() -> float:
	return _field.global_position.y + _beacon_visuals.beacon_top_height()


func _home_world_position(slot_id: int, height: float = 0.0) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, height, home.y))


func test_afk_auto_drop_with_no_cursor_clears_the_home_beacon_on_every_map_size() -> void:
	for map_name: String in SIZE_MAPS:
		_teardown_world()
		_start_host_match(_load_map(map_name))
		var margin: float = _ghost_tuning.home_spawn_beacon_margin
		assert_true(_net.cursor_for_slot(REMOTE_SLOT).is_empty(), "%s: fixture: slot 1 never sent a cursor" % map_name)

		Events.feed_timer_expired.emit(REMOTE_SLOT)

		assert_eq(_blocks_root.get_child_count(), 1, "%s: the host must auto-drop the remote slot's block" % map_name)
		assert_eq(_net.auto_drops(REMOTE_SLOT), 1, "%s: counted as an auto-drop" % map_name)
		var lowest: float = _lowest_point_y(_blocks_root.get_child(0) as Node3D)
		assert_lt(lowest, INF, "%s: fixture: the spawned block must carry its collision boxes" % map_name)
		assert_gte(
			lowest, _beacon_top_y() + margin - HEIGHT_EPSILON,
			"%s: an AFK auto-drop with no cursor must spawn above beacon top (%.3f) plus the %.2f m margin"
			% [map_name, _beacon_top_y(), margin]
		)


func test_the_fallback_lands_on_the_same_clearance_the_players_first_block_gets() -> void:
	# Drift guard: PlayerController and MatchNet both derive their height from
	# GhostTuning.home_spawn_clear_hover(), so the two lowest points must agree.
	_start_host_match(_load_map("round_small"))
	var controller: PlayerController = autofree(PlayerController.new())
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	add_child_autofree(controller)
	controller._ghost = ghost
	ghost.set_shape(load(CUBE_PATH) as BlockShape)
	controller.set_home_position(Match.default_ghost_origin(REMOTE_SLOT))
	await wait_physics_frames(1)
	controller._update_ghost_transform()
	var player_lowest: float = ghost.height_above_surface() + controller._last_hit_point.y

	Events.feed_timer_expired.emit(REMOTE_SLOT)

	var host_lowest: float = _lowest_point_y(_blocks_root.get_child(0) as Node3D)
	assert_almost_eq(
		host_lowest, player_lowest, HEIGHT_EPSILON,
		"the host's no-cursor fallback and the player's first-block hover clear the beacon by the same rule"
	)


func test_fallback_height_tracks_the_margin_tunable() -> void:
	_start_host_match(_load_map("round_small"))
	var margin: float = _ghost_tuning.home_spawn_beacon_margin
	_ghost_tuning.home_spawn_beacon_margin = margin + 1.0
	Events.feed_timer_expired.emit(REMOTE_SLOT)
	_ghost_tuning.home_spawn_beacon_margin = margin

	assert_gte(
		_lowest_point_y(_blocks_root.get_child(0) as Node3D), _beacon_top_y() + margin + 1.0 - HEIGHT_EPSILON,
		"raising the margin tunable by a metre raises the fallback spawn by a metre (no second constant)"
	)


func test_the_replicated_spawn_carries_the_raised_position_inside_the_wire_band() -> void:
	# What a client receives for the auto-dropped block (net_block_spawned's args,
	# the same payload a mid-match join replays): the host's raised pose, inside
	# the volume Quantize packs positions into, so no client ever sees the block
	# inside the beacon or loses it to a wire-range refusal.
	_start_host_match(_load_map("round_small"))
	Events.feed_timer_expired.emit(REMOTE_SLOT)

	var block: Block = _blocks_root.get_child(0) as Block
	var wire_position: Vector3 = _net._spawn_args(block, block.net_id)[3] as Vector3
	assert_eq(wire_position, block.global_position, "the spawn announcement carries the host's spawn pose")
	assert_gte(wire_position.y, _beacon_top_y(), "the replicated origin is above the beacon top")
	assert_true(
		wire_position.y >= _net.config.pos_min_y and wire_position.y <= _net.config.pos_max_y,
		"the replicated height stays inside NetConfig's quantization band"
	)


func test_a_cursor_derived_auto_drop_keeps_the_cursors_own_height() -> void:
	_start_host_match(_load_map("round_small"))
	var where: Vector3 = _home_world_position(REMOTE_SLOT, 1.5)
	_net._handle_cursor_update(REMOTE_PEER, REMOTE_SLOT, where, 0, Quaternion.IDENTITY)

	Events.feed_timer_expired.emit(REMOTE_SLOT)

	var block: Node3D = _blocks_root.get_child(0) as Node3D
	assert_almost_eq(block.global_position.y, where.y, HEIGHT_EPSILON, "a stored cursor is dropped from where it was, not raised")


func test_a_slot_whose_only_cursor_was_malformed_still_gets_the_raised_fallback() -> void:
	_start_host_match(_load_map("round_small"))
	_net._handle_cursor_update(REMOTE_PEER, REMOTE_SLOT, _home_world_position(REMOTE_SLOT), BAD_ORIENTATION, Quaternion.IDENTITY)
	assert_true(_net.cursor_for_slot(REMOTE_SLOT).is_empty(), "fixture: a malformed first cursor is not stored")

	Events.feed_timer_expired.emit(REMOTE_SLOT)

	assert_gte(
		_lowest_point_y(_blocks_root.get_child(0) as Node3D),
		_beacon_top_y() + _ghost_tuning.home_spawn_beacon_margin - HEIGHT_EPSILON,
		"the fallback applies whether the cursor never arrived or was refused"
	)


func test_the_helper_is_the_players_clear_hover_less_the_pivot_to_lowest_point_gap() -> void:
	var clear_hover: float = _ghost_tuning.home_spawn_clear_hover(_beacon_visuals)
	assert_almost_eq(
		clear_hover, _beacon_visuals.beacon_top_height() + _ghost_tuning.home_spawn_beacon_margin, HEIGHT_EPSILON,
		"clear hover is beacon top plus margin"
	)
	assert_almost_eq(
		_ghost_tuning.home_spawn_pivot_height(_beacon_visuals, _physics_tuning),
		clear_hover - _physics_tuning.cube_margin * 0.5, HEIGHT_EPSILON,
		"an unrotated block's bottom-face pivot sits cube_margin/2 below its lowest collision point"
	)
