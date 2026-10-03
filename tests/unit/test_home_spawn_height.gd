extends GutTest
## Bontago-1pi.33 (owner playtest 2026-10-03: "Start the first block higher up,
## it loads inside the home beacon currently").
##
## The match's first held piece is seeded on the owner's home flag
## (PlayerController.set_home_position()). The ghost anchors at the bare disc
## surface plus PhysicsTuning.hover_height, and the beacon is invisible to the
## placement ray (Field.PLACEMENT_QUERY_MASK) and to the spawn-clearance
## overlap query, so the piece used to sit inside the beacon's socket and
## crystal. set_home_position() now raises it until its lowest point clears the
## beacon's top by GhostTuning.home_spawn_beacon_margin.
##
## Every map in config/maps is covered: the beacon's height is the same on all
## of them, but the field, flag placement and ghost anchoring are rebuilt per
## map, so a regression that made the clearance depend on the map shows up here.

const MAPS_DIR: String = "res://config/maps/"
const CUBE_PATH: String = "res://config/blocks/cube.tres"
## Float slack for comparing a computed hover against the beacon top plus
## margin (the raise is computed to land exactly on it).
const HEIGHT_EPSILON: float = 0.0001

var _tiny_map: MapDef
var _blocks_root: Node3D
var _registry: BlockRegistry
var _field: Field


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _map_paths() -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	for file: String in DirAccess.get_files_at(MAPS_DIR):
		if file.ends_with(".tres"):
			paths.append(MAPS_DIR + file)
	paths.sort()
	return paths


func _make_field(map: MapDef) -> Field:
	var field: Field = autofree(Field.new())
	field.map_def = map
	add_child_autofree(field)
	field.place_flags(2, PackedColorArray([Color.RED, Color.BLUE]), 0)
	return field


func _make_controller() -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var controller: PlayerController = autofree(PlayerController.new())
	# Private copy so a test can retune the margin without touching the shared resource.
	controller.ghost_tuning = controller.ghost_tuning.duplicate() as GhostTuning
	add_child_autofree(controller)
	controller._ghost = ghost
	ghost.set_shape(load(CUBE_PATH) as BlockShape)
	return controller


## Highest point of the home flag's real collider in field-local space (socket
## and crystal shape owners on the beacon body), measured independently of
## BeaconVisualTuning.beacon_top_height() so the two are cross-checked.
func _collider_top_local(field: Field, slot_id: int) -> float:
	var body: AnimatableBody3D = field.beacon_body()
	var top: float = -INF
	for owner_id: int in field.flag_collision_owners(slot_id):
		var shape: Shape3D = body.shape_owner_get_shape(owner_id, 0)
		var xform: Transform3D = body.shape_owner_get_transform(owner_id)
		top = maxf(top, xform.origin.y + shape.get_debug_mesh().get_aabb().end.y)
	return top


## World Y of the held shape's lowest point right now, built from the ghost's
## own reported hover over the surface it was last placed on.
func _lowest_point_y(controller: PlayerController) -> float:
	return controller._ghost.height_above_surface() + controller._last_hit_point.y


func test_first_held_block_clears_the_home_beacon_on_every_map() -> void:
	var paths: PackedStringArray = _map_paths()
	assert_gt(paths.size(), 0, "fixture: config/maps must hold at least one map")
	for path: String in paths:
		var map: MapDef = load(path) as MapDef
		var field: Field = _make_field(map)
		var controller: PlayerController = _make_controller()
		var margin: float = controller.ghost_tuning.home_spawn_beacon_margin
		var home: Vector3 = field.home_flags()[0].global_position
		var beacon_top: float = field.global_position.y + _collider_top_local(field, 0)

		controller.set_home_position(home)
		await wait_physics_frames(1)
		controller._update_ghost_transform()

		assert_gte(
			_lowest_point_y(controller), beacon_top + margin - HEIGHT_EPSILON,
			"%s: the first block's lowest point must clear the home beacon top (%.3f) by the %.2f m margin"
			% [path.get_file(), beacon_top, margin]
		)
		field.queue_free()


func test_unseeded_hover_is_inside_the_beacon_so_the_raise_is_load_bearing() -> void:
	# The bug itself: without set_home_position()'s raise the ghost hovers only
	# tuning.hover_height above the disc, far below the beacon top.
	var map: MapDef = load("res://config/maps/round_small.tres") as MapDef
	var field: Field = _make_field(map)
	var controller: PlayerController = _make_controller()
	controller._cursor = field.home_flags()[0].global_position
	await wait_physics_frames(1)
	controller._update_ghost_transform()
	assert_lt(
		_lowest_point_y(controller), _collider_top_local(field, 0),
		"fixture: with no home raise the held block starts inside the beacon"
	)


func test_raise_tracks_the_margin_tunable() -> void:
	var field: Field = _make_field(load("res://config/maps/round_small.tres") as MapDef)
	var controller: PlayerController = _make_controller()
	var home: Vector3 = field.home_flags()[0].global_position
	controller.ghost_tuning.home_spawn_beacon_margin = 0.25
	controller.set_home_position(home)
	var small_margin_offset: float = controller._ghost.manual_hover_offset
	controller.ghost_tuning.home_spawn_beacon_margin = 1.25
	controller.set_home_position(home)
	assert_almost_eq(
		controller._ghost.manual_hover_offset - small_margin_offset, 1.0, HEIGHT_EPSILON,
		"re-seeding with a margin one metre larger raises the block one metre more (previous raise taken back first)"
	)


func test_no_raise_when_the_hover_already_clears_the_beacon() -> void:
	var field: Field = _make_field(load("res://config/maps/round_small.tres") as MapDef)
	var controller: PlayerController = _make_controller()
	var high: float = controller.beacon_visuals.beacon_top_height() + controller.ghost_tuning.home_spawn_beacon_margin + 5.0
	controller._ghost.manual_hover_offset = high
	controller.set_home_position(field.home_flags()[0].global_position)
	assert_eq(controller._ghost.manual_hover_offset, high, "a block already hovering above the beacon is left alone")


func test_raise_is_dropped_by_the_next_accepted_spawn_so_later_blocks_are_unchanged() -> void:
	var field: Field = _make_field(load("res://config/maps/round_small.tres") as MapDef)
	var controller: PlayerController = _make_controller()
	controller.set_home_position(field.home_flags()[0].global_position)
	assert_gt(controller._ghost.manual_hover_offset, 0.0, "fixture: the first piece is raised")

	# What _on_feed_block_issued()/_process() run for the piece after an accepted placement.
	controller._pending_spawn_active = true
	controller._apply_spawn_clearance()

	assert_eq(controller._ghost.manual_hover_offset, 0.0, "the next piece hovers at the player's own height again")


func test_players_own_hover_input_takes_over_the_raise() -> void:
	var field: Field = _make_field(load("res://config/maps/round_small.tres") as MapDef)
	var controller: PlayerController = _make_controller()
	controller.set_home_position(field.home_flags()[0].global_position)
	controller._step_hover(-1.0)
	var player_owned: float = controller._ghost.manual_hover_offset

	controller._pending_spawn_active = true
	controller._apply_spawn_clearance()

	assert_eq(controller._ghost.manual_hover_offset, player_owned, "a hover the player set is theirs and persists")


func test_host_spawns_the_first_released_block_above_the_beacon() -> void:
	# End to end through the real host rules: the pose the ghost sends is where
	# the block spawns, so it spawns clear of the beacon.
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.rng_seed = 24680
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)

	var controller: PlayerController = _make_controller()
	controller.set_acting_slot(0)
	controller._ghost.set_shape(Match.held_shape(0))
	controller.set_home_position(Match.default_ghost_origin(0))
	await wait_physics_frames(1)
	controller._update_ghost_transform()
	var margin: float = controller.ghost_tuning.home_spawn_beacon_margin
	var beacon_top: float = _field.global_position.y + controller.beacon_visuals.beacon_top_height()

	controller._place_ghost_block()

	assert_eq(_blocks_root.get_child_count(), 1, "fixture: the release must have spawned the first block")
	var block: Node3D = _blocks_root.get_child(0) as Node3D
	# The block's real lowest point: its collision boxes sit cube_margin/2 inside
	# the shape's nominal bottom, so the node origin alone under-reads it.
	var lowest: float = INF
	for child: Node in block.get_children():
		var box: CollisionShape3D = child as CollisionShape3D
		if box != null and box.shape is BoxShape3D:
			lowest = minf(lowest, box.global_position.y - (box.shape as BoxShape3D).size.y * 0.5)
	assert_lt(lowest, INF, "fixture: the spawned block must carry its collision boxes")
	assert_gte(
		lowest, beacon_top + margin - HEIGHT_EPSILON,
		"the host must spawn the first block's lowest point above the beacon top plus margin"
	)
