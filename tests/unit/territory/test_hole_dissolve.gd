extends GutTest
## Hole dissolve: the disc stays solid under holes, and
## game/field/HoleDissolver.gd (owned by BlockRegistry) dissolves a block that
## rests or lands on an applied hole cell and removes it through the edge-fall
## path. The first half drives a bare Field + BlockRegistry on a 6 m disk; the
## second half the real Match (a punched hole under a home flag) and MatchNet
## (replication).

const MatchNetScript := preload("res://net/MatchNet.gd")

## Frames for a dropped cube to come to rest on the disk.
const SETTLE_FRAMES: int = 60
## Generous ceiling for one dissolve (0.35 s = 21 frames) to complete.
const DISSOLVE_FRAMES: int = 60
## A bar resting on two cubes starts just above their tops.
const BRIDGE_DROP_HEIGHT_M: float = 1.05
## The bridging bar must rest clearly above the disc for the fixture to mean anything.
const BRIDGE_MIN_REST_HEIGHT_M: float = 0.9

var _tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
var _dissolve_tuning: HoleDissolveTuning = load("res://config/blocks/tuning/hole_dissolve_tuning.tres")
var _cube: BlockShape = load("res://config/blocks/cube.tres")
var _bar3: BlockShape = load("res://config/blocks/bar3.tres")

var _field: Field
var _registry: BlockRegistry
var _root: Node3D
var _net: MatchNetScript
## instance id -> removal reason, for every Events.block_removed this test saw
## (ids, because a removed block is freed right after).
var _removed: Dictionary = {}


func before_each() -> void:
	_removed = {}
	Events.block_removed.connect(_record_removed)


func after_each() -> void:
	if Events.block_removed.is_connected(_record_removed):
		Events.block_removed.disconnect(_record_removed)
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _record_removed(block: RigidBody3D, reason: String) -> void:
	_removed[block.get_instance_id()] = reason


func _was_removed(id: int) -> bool:
	return _removed.has(id)


# --- Bare Field + BlockRegistry ---------------------------------------------

func _small_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_hole_dissolve"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	return map_def


func _make_world() -> void:
	_field = Field.new()
	_field.map_def = _small_map()
	add_child_autofree(_field)
	_root = Node3D.new()
	add_child_autofree(_root)
	_registry = BlockRegistry.new()
	add_child_autofree(_registry)
	_registry.set_host_authority(true)
	_registry.configure(_field, _field.map_def)


func _middle_cell(dx: int = 0, dy: int = 0) -> int:
	var grid: CellGrid = _field.grid()
	var middle: int = floori(float(grid.res) * 0.5)
	return grid.cell_index(middle + dx, middle + dy)


func _spawn(shape: BlockShape, cell: int, height: float) -> Block:
	var block: Block = BlockFactory.build(shape, _tuning, 0)
	_root.add_child(block)
	block.global_position = _field.world_from_disk_local(_field.grid().index_center(cell), height)
	Events.block_placed.emit(block, shape.id)
	return block


func _dissolver() -> HoleDissolver:
	return _registry.hole_dissolver()


func _open(cells: PackedInt32Array) -> void:
	_field.set_hole_cells(cells, PackedInt32Array())


func _wait_removed(id: int, max_frames: int) -> int:
	var frames: int = 0
	while frames < max_frames and not _was_removed(id):
		await wait_physics_frames(1)
		frames += 1
	return frames


func test_a_block_resting_on_a_newly_opened_hole_dissolves_then_is_removed_as_an_edge_fall() -> void:
	_make_world()
	var cell: int = _middle_cell()
	var block: Block = _spawn(_cube, cell, 0.02)
	var id: int = block.get_instance_id()
	await wait_physics_frames(SETTLE_FRAMES)
	block.sleeping = true
	var resting_y: float = block.global_position.y
	var builds: int = _field.disk_mesh_build_count()
	watch_signals(Events)

	_open(PackedInt32Array([cell]))
	await wait_physics_frames(2)

	assert_true(_dissolver().is_dissolving(block), "Opening the hole under a resting block starts its dissolve.")
	assert_signal_emitted_with_parameters(
		Events, "block_dissolve_started", [block, block.net_id, _dissolve_tuning.dissolve_delay_s]
	)
	assert_false(_was_removed(id), "Removal waits for the dissolve delay.")
	assert_almost_eq(block.global_position.y, resting_y, 0.05, "The disc is solid: the block does not fall.")

	await _wait_removed(id, DISSOLVE_FRAMES)
	assert_true(_was_removed(id), "The dissolved block is removed.")
	assert_eq(_removed.get(id, ""), String(Events.REASON_KILL_PLANE), "Same reason as an edge fall.")
	assert_eq(_registry.tracked_block_count(), 0, "The registry forgets it.")
	assert_eq(_field.disk_mesh_build_count(), builds, "No disc rebuild on the hole change.")


func test_footprint_cache_rebuilds_when_collision_swaps_with_same_child_count() -> void:
	_make_world()
	var block: Block = _spawn(_cube, _middle_cell(), 0.02)
	var first: Variant = _dissolver()._footprint(block)
	assert_eq(_dissolver()._footprint(block), first, "Unchanged collision reuses the cache.")
	var collision: CollisionShape3D = null
	for child: Node in block.get_children():
		if child is CollisionShape3D:
			collision = child as CollisionShape3D
			break
	assert_not_null(collision)
	var count: int = block.get_child_count()
	var bigger: BoxShape3D = BoxShape3D.new()
	bigger.size = Vector3.ONE * 3.0
	collision.shape = bigger
	assert_eq(block.get_child_count(), count, "Child count is unchanged.")
	assert_ne(_dissolver()._footprint(block), first, "A swapped shape rebuilds the footprint.")


func test_a_dissolve_overrides_a_freeze_hold_and_releases_the_tower_above() -> void:
	_make_world()
	var cell: int = _middle_cell()
	var low: Block = _spawn(_cube, cell, 0.02)
	var top: Block = _spawn(_cube, cell, 1.2)
	await wait_physics_frames(SETTLE_FRAMES)
	var low_id: int = low.get_instance_id()
	var effect: FreezeEffect = FreezeEffect.new()
	effect.freeze_block(low, _field)
	effect.freeze_block(top, _field)
	assert_true(low.is_freeze_static() and top.is_freeze_static(), "fixture: both held")

	_open(PackedInt32Array([cell]))
	await wait_physics_frames(2)
	assert_true(_dissolver().is_dissolving(low), "the frozen block touching the void still dissolves")
	assert_false(low.is_freeze_static(), "the dissolve overrides the Freeze hold")

	await _wait_removed(low_id, DISSOLVE_FRAMES)
	assert_true(_was_removed(low_id))
	assert_false(top.is_freeze_static(), "the block above is released so it does not hang")
	assert_false(top.is_frozen_visual())


func test_a_block_bridging_a_hole_above_the_disc_is_unaffected() -> void:
	_make_world()
	var left: Block = _spawn(_cube, _middle_cell(-1), 0.02)
	var right: Block = _spawn(_cube, _middle_cell(1), 0.02)
	await wait_physics_frames(SETTLE_FRAMES)
	var bar: Block = _spawn(_bar3, _middle_cell(), BRIDGE_DROP_HEIGHT_M)
	await wait_physics_frames(SETTLE_FRAMES)
	var bar_y: float = bar.global_position.y
	assert_gt(bar_y, BRIDGE_MIN_REST_HEIGHT_M, "fixture: the bar rests on the two cubes, a cube above the disc")

	_open(PackedInt32Array([_middle_cell()]))
	await wait_physics_frames(DISSOLVE_FRAMES)

	assert_eq(_dissolver().dissolves_started, 0, "Nothing touches the hole at disc level.")
	assert_true(is_instance_valid(bar) and not bar.is_queued_for_deletion(), "The bar over the hole stays.")
	assert_true(is_instance_valid(left) and is_instance_valid(right), "Its supports on solid cells stay.")
	assert_almost_eq(bar.global_position.y, bar_y, 0.05)


## A hole opening under a gift special's carrier block never starts a dissolve;
## a plain neighbour on the same hole still does.
func test_a_hole_never_dissolves_a_gift_block_but_still_dissolves_a_plain_one() -> void:
	_make_world()
	var gift: Block = _spawn(_cube, _middle_cell(-3), 0.02)
	gift.gift_id = &"bomb"
	var plain: Block = _spawn(_cube, _middle_cell(3), 0.02)
	var plain_id: int = plain.get_instance_id()
	await wait_physics_frames(SETTLE_FRAMES)

	_open(PackedInt32Array([_middle_cell(-3), _middle_cell(3)]))
	assert_false(_dissolver().touches_hole(gift), "a gift block is never a hole-dissolve candidate")
	await wait_physics_frames(DISSOLVE_FRAMES)

	assert_true(_dissolver().dissolves_started >= 1 and _was_removed(plain_id), "control: plain block dissolves")
	assert_true(is_instance_valid(gift) and not _dissolver().is_dissolving(gift))
	assert_false(_was_removed(gift.get_instance_id()), "the gift block was not removed by hole logic")


func test_a_hole_change_never_rebuilds_the_disc_or_wakes_a_far_block() -> void:
	_make_world()
	var far: Block = _spawn(_cube, _middle_cell(-3), 0.02)
	await wait_physics_frames(SETTLE_FRAMES)
	far.sleeping = true
	await wait_physics_frames(1)
	var builds: int = _field.disk_mesh_build_count()

	var cells: PackedInt32Array = PackedInt32Array([_middle_cell(2), _middle_cell(2, 1), _middle_cell(3)])
	_open(cells)
	await wait_physics_frames(2)
	assert_true(far.sleeping, "A hole elsewhere wakes nothing.")
	_field.set_hole_cells(PackedInt32Array(), cells)
	await wait_physics_frames(2)

	assert_eq(_field.disk_mesh_build_count(), builds, "Neither opening nor closing rebuilds (no set_faces).")
	assert_true(far.sleeping)
	assert_eq(_dissolver().dissolves_started, 0)


func test_a_client_registry_never_dissolves() -> void:
	_make_world()
	_registry.set_host_authority(false)
	var cell: int = _middle_cell()
	var block: Block = _spawn(_cube, cell, 0.02)
	await wait_physics_frames(SETTLE_FRAMES)

	_open(PackedInt32Array([cell]))
	await wait_physics_frames(DISSOLVE_FRAMES)

	assert_eq(_dissolver().dissolves_started, 0, "Only the host decides a block dissolves.")
	assert_false(_was_removed(block.get_instance_id()))


func test_a_block_leaving_the_disc_does_not_touch_the_hole_under_it() -> void:
	_make_world()
	var cell: int = _middle_cell()
	var block: Block = _spawn(_cube, cell, 0.02)
	await wait_physics_frames(SETTLE_FRAMES)
	block.sleeping = true
	_field._set_hole_applied(cell, true)

	assert_true(_dissolver().touches_hole(block), "fixture: resting on the hole touches it")
	block.linear_velocity = _field.global_transform.basis.y * (_dissolve_tuning.contact_leave_speed + 2.0)
	assert_false(_dissolver().touches_hole(block), "Kicked off the disc (a Jumping Bean hop) is not contact.")


# --- Real Match --------------------------------------------------------------

func _start_match(hole_mode: MatchConfig.HoleMode, hot_seat: bool = true) -> void:
	Match.set_process(false)
	Match.abort_match()
	var tiny_map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	_field = Field.new()
	_field.map_def = tiny_map
	add_child_autofree(_field)
	_root = Node3D.new()
	add_child_autofree(_root)
	_registry = BlockRegistry.new()
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _root)
	var config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(tiny_map)
	config.player_count = 2
	config.hot_seat = hot_seat
	config.block_timer = 6.0
	config.rng_seed = 12345
	config.hole_mode = hole_mode
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _spawn_at_local(local: Vector2) -> Block:
	var grid: CellGrid = Match.cell_grid()
	var coords: Vector2i = grid.world_to_cell(local)
	var block: Block = BlockFactory.build(_cube, _tuning, 1)
	_root.add_child(block)
	block.global_position = _field.world_from_disk_local(grid.cell_center(coords.x, coords.y), 0.02)
	Events.block_placed.emit(block, _cube.id)
	return block


func test_home_elimination_still_triggers_and_blocks_on_the_punched_hole_dissolve() -> void:
	_start_match(MatchConfig.HoleMode.TEMPORARY)
	var home0: Vector2 = Match.slot(0).home_position
	var inward: Vector2 = -home0.normalized() * 2.0
	var id: int = _spawn_at_local(home0 + inward).get_instance_id()
	await wait_physics_frames(SETTLE_FRAMES)

	Match.punch_special_hole(home0, 3.0, 2.0)
	assert_false(Match.slot(0).home_flag_alive, "A hole opening under a home flag still eliminates it.")

	await _wait_removed(id, DISSOLVE_FRAMES)
	assert_true(_was_removed(id), "The block resting in the punched area dissolves.")


# --- Replication ---------------------------------------------------------------

func _make_net(client_mode: bool) -> MatchNetScript:
	var fake: FakeNet = FakeNet.client(1) if client_mode else FakeNet.host({2: 1}, [0])
	fake.slots_by_peer = {} if client_mode else {2: 1}
	Match.set_net_provider(fake)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(fake, Match)
	_net = node
	return node


func test_host_replicates_the_dissolve_start_and_the_despawn() -> void:
	var net: MatchNetScript = _make_net(false)
	_start_match(MatchConfig.HoleMode.TEMPORARY, false)
	var block: Block = _spawn_at_local(Match.slot(1).home_position * 0.5)
	net.replicate_spawn(block, block.net_id)
	assert_true(net._spawned_net_ids.has(block.net_id), "fixture: the host announced the spawn")

	var dissolver: HoleDissolver = _registry.hole_dissolver()
	dissolver.start_dissolve(block)
	assert_eq(net.replicated_dissolve_starts.size(), 1, "The start goes to clients.")
	assert_eq(net.replicated_dissolve_starts[0], block.net_id)
	var no_candidates: Array[Block] = []
	dissolver.physics_tick(_dissolve_tuning.dissolve_delay_s + 0.01, no_candidates)

	assert_true(_was_removed(block.get_instance_id()))
	assert_false(net._spawned_net_ids.has(block.net_id), "The removal goes out as the ordinary despawn.")


func test_a_client_mirrors_a_replicated_dissolve_start_and_drops_bad_payloads() -> void:
	Match.set_net_provider(FakeNet.host({}, [0, 1]))
	_start_match(MatchConfig.HoleMode.TEMPORARY, false)
	var net: MatchNetScript = _make_net(true)
	_registry.set_host_authority(false)
	var block: Block = BlockFactory.build(_cube, _tuning, 1)
	_root.add_child(block)
	Events.block_placed.emit(block, _cube.id)
	_registry.bind_net_id(block, 91)
	watch_signals(Events)

	for payload: Array in [[], [92], ["91"], [-1], [91, 0]]:
		net.net_match_event(MatchNetScript.EVENT_BLOCK_DISSOLVE_STARTED, payload)
	assert_signal_not_emitted(Events, "block_dissolve_started", "Malformed or unknown ids are dropped.")

	net.net_match_event(MatchNetScript.EVENT_BLOCK_DISSOLVE_STARTED, [91])
	assert_signal_emitted_with_parameters(
		Events, "block_dissolve_started", [block, 91, _dissolve_tuning.dissolve_delay_s]
	)
	assert_eq(_registry.hole_dissolver().dissolves_started, 0, "A client only mirrors; it never dissolves.")

	net.net_block_despawned(91, String(Events.REASON_KILL_PLANE))
	assert_true(_was_removed(block.get_instance_id()), "The replicated despawn removes the client's copy.")
