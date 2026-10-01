extends GutTest
## Bontago-1pi.11.41 (owner decision Bontago-gdb, option A): the disc stays
## solid under holes; game/HoleDissolver.gd (owned by BlockRegistry) dissolves
## a block that rests or lands on an applied hole cell and removes it through
## the edge-fall path. The first half drives a bare Field + BlockRegistry on a
## 6 m disk; the second half the real Match (home elimination, Jumping Bean,
## HoleMode.OFF) and MatchNet (replication).

const MatchNetScript := preload("res://net/MatchNet.gd")

## Frames for a dropped cube to come to rest on the disk.
const SETTLE_FRAMES: int = 60
## Generous ceiling for one dissolve (0.35 s = 21 frames) to complete.
const DISSOLVE_FRAMES: int = 60
## A three-high stack: three dissolves plus two ~1 m falls, well inside 5 s.
const STACK_TIMEOUT_FRAMES: int = 300

var _tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
var _dissolve_tuning: HoleDissolveTuning = load("res://config/hole_dissolve_tuning.tres")
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


func test_a_block_bridging_a_hole_above_the_disc_is_unaffected() -> void:
	_make_world()
	var left: Block = _spawn(_cube, _middle_cell(-1), 0.02)
	var right: Block = _spawn(_cube, _middle_cell(1), 0.02)
	await wait_physics_frames(SETTLE_FRAMES)
	var bar: Block = _spawn(_bar3, _middle_cell(), 1.05)
	await wait_physics_frames(SETTLE_FRAMES)
	var bar_y: float = bar.global_position.y
	assert_gt(bar_y, 0.9, "fixture: the bar rests on the two cubes, a cube above the disc")

	_open(PackedInt32Array([_middle_cell()]))
	await wait_physics_frames(DISSOLVE_FRAMES)

	assert_eq(_dissolver().dissolves_started, 0, "Nothing touches the hole at disc level.")
	assert_true(is_instance_valid(bar) and not bar.is_queued_for_deletion(), "The bar over the hole stays.")
	assert_true(is_instance_valid(left) and is_instance_valid(right), "Its supports on solid cells stay.")
	assert_almost_eq(bar.global_position.y, bar_y, 0.05)


func test_a_stack_over_a_hole_chain_dissolves_within_a_bounded_time() -> void:
	_make_world()
	var cell: int = _middle_cell()
	var stack: Array[Block] = []
	var ids: Array[int] = []
	for level: int in range(3):
		stack.append(_spawn(_cube, cell, 0.02 + float(level) * _tuning.cube_size))
		ids.append(stack[level].get_instance_id())
		await wait_physics_frames(SETTLE_FRAMES)
	# Stable-frozen (spec 3.5) as a long-settled tower would be.
	for block: Block in stack:
		block.request_freeze_static(Block.FREEZE_REASON_STABLE)
	await wait_physics_frames(1)

	_open(PackedInt32Array([cell]))
	var frames: int = 0
	while frames < STACK_TIMEOUT_FRAMES and _registry.tracked_block_count() > 0:
		await wait_physics_frames(1)
		frames += 1

	assert_eq(_registry.tracked_block_count(), 0, "All three levels dissolve (took %d frames)." % frames)
	assert_lt(frames, STACK_TIMEOUT_FRAMES)
	assert_eq(_dissolver().dissolves_started, 3)
	for id: int in ids:
		assert_true(_was_removed(id))


func test_a_block_dropped_into_an_open_hole_dissolves_on_landing() -> void:
	_make_world()
	var cell: int = _middle_cell()
	_open(PackedInt32Array([cell]))
	await wait_physics_frames(2)
	var block: Block = _spawn(_cube, cell, 3.0)
	var id: int = block.get_instance_id()
	var lowest: float = INF
	var started_at_height: float = INF
	var frames: int = 0
	while frames < 120 and not _was_removed(id):
		await wait_physics_frames(1)
		frames += 1
		if not _was_removed(id):
			lowest = minf(lowest, block.global_position.y)
			if started_at_height == INF and _dissolver().is_dissolving(block):
				started_at_height = block.global_position.y
	assert_true(_was_removed(id), "The dropped block dissolves and is removed.")
	assert_lt(started_at_height, 0.3, "The dissolve starts on landing, not in the air.")
	assert_gt(lowest, -0.1, "The disc stays solid under the hole.")


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
	var tiny_map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	_field = Field.new()
	_field.map_def = tiny_map
	add_child_autofree(_field)
	_root = Node3D.new()
	add_child_autofree(_root)
	_registry = BlockRegistry.new()
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _root)
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
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


func test_a_jumping_bean_hole_dissolves_the_blocks_it_opens_under_but_not_the_bean() -> void:
	_start_match(MatchConfig.HoleMode.TEMPORARY)
	var grid: CellGrid = Match.cell_grid()
	var middle: int = floori(float(grid.res) * 0.5)
	# Off the disc centre, where the goal flag stands.
	var bean_local: Vector2 = grid.cell_center(middle + 5, middle)
	var bean: Block = _spawn_at_local(bean_local)
	var neighbour: Block = _spawn_at_local(grid.cell_center(middle + 6, middle))
	await wait_physics_frames(SETTLE_FRAMES)
	var effect: JumpingBeanEffect = JumpingBeanEffect.new()
	effect.hole_radius_m = grid.cell_size * 1.2

	effect._hop(bean)
	await wait_physics_frames(3)

	var cell: Vector2i = grid.world_to_cell(bean_local)
	assert_true(_field.is_hole_cell(grid.cell_index(cell.x, cell.y)), "fixture: the hop punched a hole")
	assert_true(_registry.hole_dissolver().is_dissolving(neighbour), "The block on the bean's hole dissolves.")
	assert_false(_registry.hole_dissolver().is_dissolving(bean), "The bean kicked off its own hole does not.")
	var neighbour_id: int = neighbour.get_instance_id()
	await _wait_removed(neighbour_id, DISSOLVE_FRAMES)
	assert_true(_was_removed(neighbour_id))


func test_hole_mode_off_never_dissolves() -> void:
	_start_match(MatchConfig.HoleMode.OFF)
	var home0: Vector2 = Match.slot(0).home_position
	var block: Block = _spawn_at_local(home0 - home0.normalized() * 2.0)
	await wait_physics_frames(SETTLE_FRAMES)

	Match.punch_special_hole(home0, 3.0, 2.0)
	await wait_physics_frames(DISSOLVE_FRAMES)

	assert_eq(_field.applied_hole_count(), 0, "OFF opens no hole.")
	assert_eq(_registry.hole_dissolver().dissolves_started, 0)
	assert_false(_was_removed(block.get_instance_id()))


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
