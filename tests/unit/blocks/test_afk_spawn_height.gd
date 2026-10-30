extends GutTest
## Follow-up to "Start the first block higher up, it loads inside the home beacon".
##
## An earlier change raised the *player's* first-block hover above the home beacon, but the
## host's AFK auto-drop (MatchNet's feed-timer-expired handler, via SlotCursors.auto_drop_pose) still fell back
## to Match.default_ghost_origin() -- the home flag at disc level -- for a remote
## slot that never sent a cursor, so that block spawned inside the beacon's
## socket and crystal. The fallback origin now rises to the same clearance the
## player's first block gets (GhostTuning.home_spawn_pivot_height(), built on the
## same home_spawn_clear_hover() PlayerController uses).
##
## These drive the **real** Match and MatchNet (a real listen server with no peer), like
## test_match_net.gd: every assertion is about the block the host actually spawned.

const MatchNetScript := preload("res://net/MatchNet.gd")
## Disc-size factors (config/match/disc_size_tuning.tres smallest, default and largest steps), built at their real
## radius so "every disc size" is exercised, not a shrunk stand-in. The beacon height is a
## constant, but flag placement, field and territory geometry are rebuilt per scale.
const DISC_FACTORS: Array[float] = [0.75, 1.0, 1.75]
const CUBE_PATH: String = "res://config/blocks/cube.tres"
## Float slack for comparing a spawned height against beacon top plus margin.
const HEIGHT_EPSILON: float = 0.0001
const REMOTE_SLOT: int = 1

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _net: MatchNetScript
var _ghost_tuning: GhostTuning = preload("res://config/blocks/tuning/ghost_tuning.tres")
var _beacon_visuals: BeaconVisualTuning = preload("res://config/territory/beacon_visual_tuning.tres")


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()


func after_each() -> void:
	_teardown_world()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _teardown_world() -> void:
	Net.leave()
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

	# The real listen server with no peer: slot 1 is a seat this instance does not drive, so the
	# host auto-drops for it, and the real MatchNet autoload is the replicator.
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie", false), OK)
	Match.set_replicator(MatchNet)
	_net = MatchNet

	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 4242
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture should reach PLAYING")


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


func test_afk_auto_drop_with_no_cursor_clears_the_home_beacon_on_every_disc_size() -> void:
	for factor: float in DISC_FACTORS:
		var map_name: String = "disc x%.2f" % factor
		_teardown_world()
		_start_host_match(MapDef.base().scaled(factor))
		var margin: float = _ghost_tuning.home_spawn_beacon_margin
		assert_true(_net.cursor_for_slot(REMOTE_SLOT).is_empty(), "%s: fixture: slot 1 never sent a cursor" % map_name)

		Events.feed_timer_expired.emit(REMOTE_SLOT)

		assert_eq(_blocks_root.get_child_count(), 1, "%s: the host must auto-drop the remote slot's block" % map_name)
		assert_eq(_net.counters.accepted_count(REMOTE_SLOT), 0, "%s: an auto-drop, not an accepted intent" % map_name)
		var lowest: float = _lowest_point_y(_blocks_root.get_child(0) as Node3D)
		assert_lt(lowest, INF, "%s: fixture: the spawned block must carry its collision boxes" % map_name)
		assert_gte(
			lowest, _beacon_top_y() + margin - HEIGHT_EPSILON,
			"%s: an AFK auto-drop with no cursor must spawn above beacon top (%.3f) plus the %.2f m margin"
			% [map_name, _beacon_top_y(), margin]
		)


func test_the_fallback_lands_on_the_same_clearance_the_players_first_block_gets() -> void:
	# Drift guard: PlayerController and SlotCursors both derive their height from
	# GhostTuning.home_spawn_clear_hover(), so the two lowest points must agree.
	_start_host_match(MapDef.base().scaled(0.75))
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var controller: PlayerController = autofree(PlayerController.new())
	controller.ghost_path = ghost.get_path()
	add_child_autofree(controller)
	ghost.set_shape(load(CUBE_PATH) as BlockShape)
	controller.set_home_position(Match.default_ghost_origin(REMOTE_SLOT))
	await wait_physics_frames(1)
	controller.spawn_camera_anchor()  # poses the ghost at its cursor
	var player_lowest: float = ghost.height_above_surface() + _field.surface_y()

	Events.feed_timer_expired.emit(REMOTE_SLOT)

	var host_lowest: float = _lowest_point_y(_blocks_root.get_child(0) as Node3D)
	assert_almost_eq(
		host_lowest, player_lowest, HEIGHT_EPSILON,
		"the host's no-cursor fallback and the player's first-block hover clear the beacon by the same rule"
	)


