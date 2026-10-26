extends GutTest
## ("Start the first block higher up,
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

const MAPS_DIR: String = "res://config/match/maps/"
const CUBE_PATH: String = "res://config/blocks/cube.tres"
## Float slack for comparing a computed hover against the beacon top plus
## margin (the raise is computed to land exactly on it).
const HEIGHT_EPSILON: float = 0.0001
## Start of the downward beacon ray, well above any beacon.
const RAY_HEIGHT: float = 50.0
## Mouse travel that carries the cursor well clear of the block just released.
const MOVE_AWAY_PX: float = 800.0

var _tiny_map: MapDef
var _blocks_root: Node3D
var _registry: BlockRegistry
var _field: Field
var _ghost: GhostPreview


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
	_ghost = autofree(GhostPreview.new())
	add_child_autofree(_ghost)
	var controller: PlayerController = autofree(PlayerController.new())
	controller.ghost_path = _ghost.get_path()
	# Private copy so a test can retune the margin without touching the shared resource.
	controller.ghost_tuning = controller.ghost_tuning.duplicate() as GhostTuning
	add_child_autofree(controller)
	# The test drives the engine's per-frame callback itself (one deterministic step per call).
	controller.set_process(false)
	_ghost.set_shape(load(CUBE_PATH) as BlockShape)
	return controller


## One engine frame of the controller (poses the ghost at its cursor).
func _frame(controller: PlayerController, delta: float = 1.0 / 60.0) -> void:
	controller._process(delta)


## The player's wheel notch down, delivered the way the Input Map delivers it.
func _wheel_down(controller: PlayerController) -> void:
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	controller._unhandled_input(wheel)


## The ghost_place press the Input Map delivers.
func _click_place(controller: PlayerController) -> void:
	var press: InputEventAction = InputEventAction.new()
	press.action = &"ghost_place"
	press.pressed = true
	controller._unhandled_input(press)


## A started two-player match on a tiny round map and the controller for slot 0, seeded on its home
## flag as the game seeds a slot (LocalPlayer.bind_local_slot).
func _start_match_with_controller() -> PlayerController:
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.rng_seed = 24680
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	var controller: PlayerController = _make_controller()
	controller.set_acting_slot(0)
	_ghost.set_shape(Match.held_shape(0))
	controller.set_home_position(Match.default_ghost_origin(0))
	return controller


## World Y of the highest beacon collider point above the home flag, found by a
## downward ray against Field.BEACON_COLLISION_LAYER, measured independently of
## BeaconVisualTuning.beacon_top_height() so the two are cross-checked.
func _collider_top_world(field: Field, slot_id: int) -> float:
	await wait_physics_frames(1)
	var flag_pos: Vector3 = field.home_flags()[slot_id].global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		flag_pos + Vector3.UP * RAY_HEIGHT, flag_pos - Vector3.UP * RAY_HEIGHT, Field.BEACON_COLLISION_LAYER
	)
	var hit: Dictionary = field.direct_space().intersect_ray(query)
	assert_false(hit.is_empty(), "fixture: the home beacon collider answers a ray from above")
	return (hit["position"] as Vector3).y


## World Y of the held shape's lowest point right now, built from the ghost's
## own reported hover over the field's surface.
func _lowest_point_y(field: Field) -> float:
	return _ghost.height_above_surface() + field.surface_y()


func test_first_held_block_clears_the_home_beacon_on_every_map() -> void:
	var paths: PackedStringArray = _map_paths()
	assert_gt(paths.size(), 0, "fixture: config/match/maps must hold at least one map")
	for path: String in paths:
		var map: MapDef = load(path) as MapDef
		var field: Field = _make_field(map)
		var controller: PlayerController = _make_controller()
		var margin: float = controller.ghost_tuning.home_spawn_beacon_margin
		var home: Vector3 = field.home_flags()[0].global_position
		var beacon_top: float = await _collider_top_world(field, 0)

		controller.set_home_position(home)
		await wait_physics_frames(1)
		_frame(controller)

		assert_gte(
			_lowest_point_y(field), beacon_top + margin - HEIGHT_EPSILON,
			"%s: the first block's lowest point must clear the home beacon top (%.3f) by the %.2f m margin"
			% [path.get_file(), beacon_top, margin]
		)
		field.queue_free()


func test_raise_is_dropped_by_the_next_accepted_spawn_so_later_blocks_are_unchanged() -> void:
	var controller: PlayerController = _start_match_with_controller()
	assert_gt(_ghost.manual_hover_offset, 0.0, "fixture: the first piece is raised")
	_frame(controller)
	_click_place(controller)
	assert_eq(_blocks_root.get_child_count(), 1, "fixture: the release spawned the first block")

	# The next piece after the accepted placement: its spawn takes the first piece's raise off.
	await wait_physics_frames(1)
	_frame(controller, controller.ghost_tuning.spawn_clearance_settle_timeout_s)

	assert_eq(_ghost.manual_hover_offset, 0.0, "the next piece hovers at the player's own height again")


func test_players_own_hover_input_takes_over_the_raise() -> void:
	var controller: PlayerController = _start_match_with_controller()
	_wheel_down(controller)
	var player_owned: float = _ghost.manual_hover_offset
	assert_gt(player_owned, 0.0, "fixture: one notch down leaves part of the raise")
	_frame(controller)
	_click_place(controller)
	assert_eq(_blocks_root.get_child_count(), 1, "fixture: the release spawned the first block")
	# The player moves the cursor off the block just released, so the next piece has nothing to clear.
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(MOVE_AWAY_PX, 0.0)
	controller._unhandled_input(motion)

	await wait_physics_frames(1)
	_frame(controller, controller.ghost_tuning.spawn_clearance_settle_timeout_s)

	assert_eq(_ghost.manual_hover_offset, player_owned, "a hover the player set is theirs and persists")


func test_host_spawns_the_first_released_block_above_the_beacon() -> void:
	# End to end through the real host rules: the pose the ghost sends is where
	# the block spawns, so it spawns clear of the beacon.
	var controller: PlayerController = _start_match_with_controller()
	await wait_physics_frames(1)
	_frame(controller)
	var margin: float = controller.ghost_tuning.home_spawn_beacon_margin
	var beacon_top: float = _field.global_position.y + controller.beacon_visuals.beacon_top_height()

	_click_place(controller)

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
