extends GutTest
## Snow (Bontago-22y.6): the host effect on a real (tiny) Field with real
## Jolt blocks. Growth, budgets, collider/visual correspondence (checked with
## rays against the live colliders), cleanup, melting, coverage, sleep
## preservation (no wake cascade), and the gameplay point: a block dropped on
## a snowy top does not rest flat.

const DT: float = 1.0 / 60.0
const SETTLE_FRAMES: int = 120
const HALF_SETTLE_FRAMES: int = 60
const GROW_FRAMES: int = 150
const SEED: int = 424242
const FIELD_RADIUS_M: float = 6.0
const MIN_SNOWY_TILT_DEG: float = 2.0
const MAX_FLAT_TILT_DEG: float = 0.5
const HULL_TOLERANCE_M: float = 0.008
const RAY_REACH_M: float = 0.5
## Only snow at least this fraction of max depth bears weight (rims do not).
const BEARING_FRACTION: float = 0.3
const MELT_SETTLE_FRAMES: int = 6

var _field: Field = null
var _root: Node3D = null
var _blocks: Array[Block] = []
var _physics: PhysicsTuning = null
var _snow: SnowTuning = null
var _effect: SnowEffect = null
var _next_net_id: int = 100


func before_each() -> void:
	_field = Field.new()
	_field.map_def = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_field.map_def.field_radius = FIELD_RADIUS_M
	add_child_autofree(_field)
	_root = Node3D.new()
	add_child_autofree(_root)
	_blocks.clear()
	_physics = load("res://config/physics_tuning.tres") as PhysicsTuning
	_snow = (load("res://config/weather/snow.tres") as SnowTuning).duplicate() as SnowTuning
	_snow.seconds_per_level = 0.05
	_snow.patch_checks_per_frame = 64
	_snow.discover_blocks_per_frame = 64
	_snow.max_disc_patches = 6
	_snow.disc_flag_clear_radius_m = 0.0
	_effect = null


func after_each() -> void:
	if _effect != null:
		_effect.restore()
	_effect = null


func _cube(pos: Vector3) -> Block:
	var block: Block = BlockFactory.build(load("res://config/blocks/cube.tres") as BlockShape, _physics)
	_root.add_child(block)
	block.global_position = pos
	block.net_id = _next_net_id
	_next_net_id += 1
	_blocks.append(block)
	return block


func _make_effect() -> SnowEffect:
	var effect: SnowEffect = SnowEffect.new()
	effect.bind(null, _snow)
	effect.set_world(_field, func() -> Array[Block]: return _blocks)
	effect.set_seed(SEED)
	_effect = effect
	return effect


func _frames(count: int, intensity: float = 1.0) -> void:
	for _i: int in range(count):
		await get_tree().physics_frame
		if _effect != null:
			_effect.tick(DT, intensity)


func _tilt_deg(block: Block) -> float:
	var best: float = 0.0
	for axis: Vector3 in [block.global_basis.x, block.global_basis.y, block.global_basis.z]:
		best = maxf(best, absf(axis.normalized().dot(Vector3.UP)))
	return rad_to_deg(acos(clampf(best, -1.0, 1.0)))


static func _mesh_vertices(holder: Node, cap_name: StringName) -> PackedVector3Array:
	var instance: MeshInstance3D = SnowCaps.cap_mesh(holder, cap_name)
	if instance == null or instance.mesh == null:
		return PackedVector3Array()
	return (instance.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


static func _disc_mesh_vertices(field: Node) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for instance: MeshInstance3D in SnowCaps.disc_cap_meshes(field):
		out.append_array((instance.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	return out


static func _collider_points(owner: Node) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for collision: CollisionShape3D in SnowCaps.lump_colliders(owner):
		out.append_array(collision.transform * (collision.shape as ConvexPolygonShape3D).points)
	return out


## Visual depth == collision depth: every drawn vertex is a collider point,
## and a ray dropped onto the live collider over each clearly snowy vertex
## lands within HULL_TOLERANCE_M of the drawn surface.
func _assert_mesh_matches_colliders(holder: Node3D, mesh_local: PackedVector3Array, collider_owners: Array[Node]) -> void:
	var shapes: PackedVector3Array = PackedVector3Array()
	for owner: Node in collider_owners:
		shapes.append_array(_collider_points(owner))
	assert_false(mesh_local.is_empty(), "cap mesh drawn")
	assert_false(shapes.is_empty(), "snow colliders exist")
	var lookup: Dictionary = {}
	for p: Vector3 in shapes:
		lookup[p] = true
	for v: Vector3 in mesh_local:
		if not lookup.has(v):
			fail_test("mesh vertex %s is not a collider point" % v)
			return
	var space: PhysicsDirectSpaceState3D = _field.get_world_3d().direct_space_state
	var up: Vector3 = holder.global_basis.y.normalized()
	var checked: int = 0
	var worst: float = 0.0
	var worst_at: String = ""
	var base_y: float = INF
	for v: Vector3 in mesh_local:
		base_y = minf(base_y, v.y)
	for v: Vector3 in mesh_local:
		if v.y - base_y < _snow.max_depth_m * BEARING_FRACTION:
			continue
		var world: Vector3 = holder.global_transform * v
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(world + up * RAY_REACH_M, world - up * RAY_REACH_M)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			fail_test("no collider under drawn snow at %s" % world)
			return
		var dev: float = ((hit["position"] as Vector3) - world).dot(up)
		if absf(dev) > worst:
			worst = absf(dev)
			worst_at = "vertex %s hit %s on %s" % [world, hit["position"], hit["collider"]]
		checked += 1
	assert_gt(checked, 0)
	gut.p("collider vs drawn surface: worst %.4f m over %d vertices (%s)" % [worst, checked, worst_at])
	if worst >= HULL_TOLERANCE_M:
		for owner: Node in collider_owners:
			for collision: CollisionShape3D in SnowCaps.lump_colliders(owner):
				var pts: PackedVector3Array = (collision.shape as ConvexPolygonShape3D).points
				var box: AABB = AABB(pts[0], Vector3.ZERO)
				for q: Vector3 in pts:
					box = box.expand(q)
				gut.p("  %s/%s aabb %s disabled=%s in_tree=%s" % [owner.name, collision.name, box, collision.disabled, collision.is_inside_tree()])
	assert_lt(worst, HULL_TOLERANCE_M, "drawn snow surface is where things rest")


# --- Tests -----------------------------------------------------------------------------

func test_snow_grows_in_steps_to_the_cap_and_stays_bounded() -> void:
	var cubes: Array[Block] = [_cube(Vector3(-2.0, 0.01, 0.0)), _cube(Vector3(0.0, 0.01, 0.0)), _cube(Vector3(2.0, 0.01, 0.0))]
	await _frames(SETTLE_FRAMES)
	var effect: SnowEffect = _make_effect()
	await _frames(4)
	for cube: Block in cubes:
		assert_eq(effect.block_levels(cube).size(), 1, "one exposed top")
	await _frames(GROW_FRAMES)
	var disc_snowy: int = 0
	for cube: Block in cubes:
		assert_eq(effect.block_levels(cube), PackedInt32Array([_snow.depth_levels]), "grew to the top level and stopped")
		assert_eq(SnowCaps.lump_colliders(cube).size(), 1, "one dome collider per patch")
	var disc: Dictionary = effect.disc_levels()
	assert_lte(disc.size(), _snow.max_disc_patches, "disc budget")
	for key: Variant in disc.keys():
		assert_between(int(disc[key]), 0, _snow.depth_levels)
		if int(disc[key]) > 0:
			disc_snowy += 1
	assert_gt(disc_snowy, 0, "the disc collects snow")
	assert_eq(effect.collider_count(), cubes.size() + disc_snowy)
	assert_eq(effect.cover_level(), _snow.depth_levels, "disc cover reached a blanket")
	var cover: SnowDiscCover = SnowCaps.disc_cover(_field)
	assert_not_null(cover, "visual disc cover exists")
	assert_eq(cover.level(), _snow.depth_levels)
	var disc_material: ShaderMaterial = _field.overlay().material()
	assert_eq(cover.material(), disc_material, "snow is a layer of the disc (territory) shader itself")
	assert_almost_eq(float(disc_material.get_shader_parameter(&"snow_strength")), minf(_snow.cover_strength_heavy, 1.0 - _snow.cover_territory_min), 0.001)
	assert_almost_eq(float(disc_material.get_shader_parameter(&"snow_threshold")), _snow.cover_amount_heavy, 0.001)
	assert_gt(cover.amount(), _snow.cover_amount_light, "the cover builds up with its level")
	assert_gte(1.0 - cover.strength() + 0.0001, _snow.cover_territory_min, "territory colour keeps its minimum share at full snow")
	assert_gt(_snow.cover_territory_min, 0.2, "the minimum is a real share, not zero")
	cover.finish_drift()
	assert_false(cover.is_drift_building())
	var grid: CellGrid = _field.grid()
	var under: Vector2i = grid.world_to_cell(_field.disk_local_from_world(cubes[1].global_position))
	assert_gt(cover.drift_at(grid.cell_index(under.x, under.y)), 0.5, "drifts pile up at block bases")
	var far: Vector2i = grid.world_to_cell(Vector2(0.0, 4.5))
	assert_eq(cover.drift_at(grid.cell_index(far.x, far.y)), 0.0, "open disc gets no base bias")
	for cube: Block in cubes:
		assert_almost_eq(_field.to_local(cube.global_position).y, 0.0, 0.05, "snow never lifts or pops the block it sits on")
		assert_false(cube.is_freeze_static(), "rebuild freeze released")


func test_drift_rebuild_survives_a_block_freed_mid_queue() -> void:
	# Bontago-1pi.11.26: a block freed (burned / kill plane) after the drift queue
	# was captured used to error on the typed cast every frame it was reached.
	var cubes: Array[Block] = [_cube(Vector3(-2.0, 0.01, 0.0)), _cube(Vector3(2.0, 0.01, 0.0))]
	await _frames(SETTLE_FRAMES)
	var effect: SnowEffect = _make_effect()
	await _frames(GROW_FRAMES)
	var cover: SnowDiscCover = SnowCaps.disc_cover(_field)
	assert_not_null(cover)
	cover.call(&"_start_drift")
	assert_true(cover.is_drift_building())
	cubes[0].free()
	cover.finish_drift()
	assert_false(cover.is_drift_building(), "queue drained past the freed block")
	assert_not_null(effect)


func test_block_patch_budget_is_global() -> void:
	_snow.max_block_patches = 2
	_snow.max_disc_patches = 0
	for i: int in range(4):
		_cube(Vector3(-3.0 + 2.0 * float(i), 0.01, 0.0))
	await _frames(SETTLE_FRAMES)
	var effect: SnowEffect = _make_effect()
	await _frames(GROW_FRAMES)
	assert_eq(effect.active_block_patches(), 2)
	assert_eq(effect.collider_count(), 2)
	var snowy: int = 0
	for block: Block in _blocks:
		if not SnowCaps.lump_colliders(block).is_empty():
			snowy += 1
	assert_eq(snowy, 2)


func test_rebuilds_are_amortised_per_frame() -> void:
	_snow.max_disc_patches = 0
	_snow.rebuild_patches_per_frame = 2
	for i: int in range(6):
		_cube(Vector3(-3.0 + 1.2 * float(i), 0.01, 0.0))
	await _frames(SETTLE_FRAMES)
	var effect: SnowEffect = _make_effect()
	var most_per_frame: int = 0
	var before: int = 0
	for _i: int in range(GROW_FRAMES):
		await _frames(1)
		var built: int = effect.builder().patches_built
		most_per_frame = maxi(most_per_frame, built - before)
		before = built
	assert_lte(most_per_frame, 2, "never more domes per frame than the budget")
	assert_eq(effect.builder().patches_built, 6 * _snow.depth_levels, "every level of every patch built once")
	for block: Block in _blocks:
		assert_eq(SnowCaps.lump_colliders(block).size(), 1)


func test_colliders_and_meshes_are_the_same_geometry() -> void:
	var cube: Block = _cube(Vector3(0.0, 0.01, 0.0))
	var domino: Block = BlockFactory.build(load("res://config/blocks/domino.tres") as BlockShape, _physics)
	_root.add_child(domino)
	domino.global_position = Vector3(2.5, 0.01, 1.5)
	domino.net_id = _next_net_id
	_next_net_id += 1
	_blocks.append(domino)
	await _frames(SETTLE_FRAMES)
	_make_effect()
	await _frames(GROW_FRAMES)
	var cube_owner: Array[Node] = [cube]
	var domino_owner: Array[Node] = [domino]
	_assert_mesh_matches_colliders(cube, _mesh_vertices(cube, SnowCaps.CAP_NAME), cube_owner)
	_assert_mesh_matches_colliders(domino, _mesh_vertices(domino, SnowCaps.CAP_NAME), domino_owner)
	var disc_owners: Array[Node] = []
	for body: StaticBody3D in SnowCaps.disc_bodies(_field):
		disc_owners.append(body)
	_assert_mesh_matches_colliders(_field, _disc_mesh_vertices(_field), disc_owners)
	# Snow never counts toward a tower's height credit.
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	for child: Node in cube.get_children():
		assert_false(child is MeshInstance3D and child.name == SnowCaps.CAP_MESH_NAME, "cap mesh is not a direct child")
	assert_almost_eq(registry.top_height_for_block(cube), _physics.cube_size, 0.02, "height credit ignores snow")


func test_client_draws_identical_caps_from_the_replicated_state() -> void:
	var cube: Block = _cube(Vector3(0.0, 0.01, 0.0))
	await _frames(SETTLE_FRAMES)
	var effect: SnowEffect = _make_effect()
	await _frames(GROW_FRAMES)
	var data: Dictionary = SnowGeometry.sanitize_state(effect.state(), _snow, _field.grid().cell_count() - 1)
	assert_false(data.is_empty(), "host state is valid on the wire")
	var record: Array = (data["blocks"] as Dictionary)[cube.net_id]
	var seed_value: int = int(data["seed"])
	# A client's copy of the same block, drawn by a collider-less builder.
	var mirror: Block = BlockFactory.build(load("res://config/blocks/cube.tres") as BlockShape, _physics)
	mirror.freeze = true
	_root.add_child(mirror)
	mirror.global_position = Vector3(0.0, 5.0, 3.0)
	var client: SnowCapBuilder = SnowCapBuilder.new(_snow, false)
	var axis: int = int(record[0])
	var cells: PackedInt32Array = record[1]
	var levels: PackedInt32Array = record[2]
	var centers: PackedVector3Array = SnowCaps.block_cells(mirror)
	for k: int in range(cells.size()):
		client.set_patch(
			"b%d" % cube.net_id, mirror, -1, cells[k],
			SnowGeometry.block_patch_transform(centers[cells[k]], axis, _physics.cube_size),
			SnowCaps.block_patch_edge(_physics.cube_size, _snow),
			SnowGeometry.patch_seed(seed_value, cube.net_id, cells[k], axis), levels[k]
		)
	var ghost_field: Node3D = autofree(Node3D.new())
	var grid: CellGrid = _field.grid()
	var disc: Dictionary = data["disc"]
	for key: Variant in disc.keys():
		var cell: int = int(key)
		var region: int = SnowCaps.disc_region(grid, cell, _snow)
		client.set_patch(
			"d%d" % region, ghost_field, region, cell, SnowCaps.disc_patch_frame(grid, cell),
			SnowCaps.disc_patch_edge(grid, _snow),
			SnowGeometry.patch_seed(seed_value, SnowGeometry.DISC_OWNER, cell, SnowGeometry.AXIS_UP), int(disc[key])
		)
	while not client.is_idle():
		client.step(_snow.rebuild_patches_per_frame)
	assert_eq(SnowCaps.lump_colliders(mirror).size(), 0, "a client builds no snow collider")
	assert_eq(_mesh_vertices(mirror, SnowCaps.CAP_NAME), _mesh_vertices(cube, SnowCaps.CAP_NAME), "same seed, same caps")
	var host_disc: PackedVector3Array = _disc_mesh_vertices(_field)
	var client_disc: PackedVector3Array = _disc_mesh_vertices(ghost_field)
	assert_false(host_disc.is_empty())
	assert_eq(client_disc.size(), host_disc.size(), "same disc drifts")
	assert_true(SnowCaps.disc_bodies(ghost_field).is_empty(), "no disc collider body on a client")
	mirror.free()


func test_restore_and_despawn_leave_no_snow() -> void:
	var a: Block = _cube(Vector3(-1.5, 0.01, 0.0))
	var b: Block = _cube(Vector3(1.5, 0.01, 0.0))
	await _frames(SETTLE_FRAMES)
	var effect: SnowEffect = _make_effect()
	await _frames(GROW_FRAMES)
	assert_gt(effect.collider_count(), 0)
	# Despawn: the effect forgets the block and its patches.
	var before_patches: int = effect.active_block_patches()
	Events.block_removed.emit(b, "test")
	_blocks.erase(b)
	b.queue_free()
	await _frames(2)
	assert_eq(effect.tracked_block_count(), 1)
	assert_eq(effect.active_block_patches(), before_patches - 1)
	var blocks_wire: PackedInt32Array = effect.state()["b"]
	assert_eq(blocks_wire[0], a.net_id, "state names only the live block")
	assert_eq(blocks_wire.size(), 3 + 2, "one record, one patch")
	# End of event / match end / abort all reach restore().
	effect.restore()
	assert_eq(effect.collider_count(), 0)
	assert_eq(SnowCaps.lump_colliders(a).size(), 0)
	assert_null(a.get_node_or_null(NodePath(String(SnowCaps.CAP_NAME))), "cap removed")
	assert_true(SnowCaps.disc_bodies(_field).is_empty(), "disc snow bodies removed")
	assert_true(SnowCaps.disc_cap_meshes(_field).is_empty(), "disc drifts removed")
	assert_null(SnowCaps.disc_cover(_field), "disc cover removed")
	assert_eq(float(_field.overlay().material().get_shader_parameter(&"snow_strength")), 0.0, "disc snow layer switched off")
	assert_false(a.is_freeze_static(), "no rebuild freeze left behind")
	assert_true(SnowRelay.is_empty_state(SnowRelay.instance().last_state), "empty state published")
	effect.restore()
	await _frames(3)
	assert_eq(SnowCaps.lump_colliders(a).size(), 0, "a restored effect never grows again")
	_effect = null


func test_ramp_out_melts_in_steps_to_nothing() -> void:
	var cube: Block = _cube(Vector3(0.0, 0.01, 0.0))
	await _frames(SETTLE_FRAMES)
	var effect: SnowEffect = _make_effect()
	await _frames(GROW_FRAMES)
	assert_eq(effect.block_levels(cube)[0], _snow.depth_levels)
	var seen: Array[int] = []
	var steps: int = 40
	for i: int in range(steps + 1):
		var value: float = 1.0 - float(i) / float(steps)
		await _frames(1, value)
		var level: int = effect.block_levels(cube)[0]
		if seen.is_empty() or seen[seen.size() - 1] != level:
			seen.append(level)
	assert_true(effect.is_melting())
	assert_eq(seen, [4, 3, 2, 1, 0], "shrinks one level at a time")
	# Geometry follows over the next frames (budgeted builder).
	await _frames(MELT_SETTLE_FRAMES, 0.0)
	assert_eq(effect.collider_count(), 0, "melted away before the event ends")
	assert_null(cube.get_node_or_null(NodePath(String(SnowCaps.CAP_NAME))))
	assert_eq(effect.cover_level(), 0)
	assert_null(SnowCaps.disc_cover(_field), "cover melted")
	assert_eq(float(_field.overlay().material().get_shader_parameter(&"snow_strength")), 0.0, "disc snow layer off after the melt")


func test_a_covered_top_stops_growing() -> void:
	_snow.max_disc_patches = 0
	var bottom: Block = _cube(Vector3(0.0, 0.01, 0.0))
	await _frames(HALF_SETTLE_FRAMES)
	var top: Block = _cube(Vector3(0.0, _physics.cube_size + 0.01, 0.0))
	await _frames(SETTLE_FRAMES)
	var effect: SnowEffect = _make_effect()
	await _frames(GROW_FRAMES)
	assert_eq(effect.block_levels(bottom), PackedInt32Array([0]), "a block resting on it keeps it bare")
	assert_eq(effect.block_levels(top), PackedInt32Array([_snow.depth_levels]))
	assert_true(top.sleeping or top.freeze, "the tower was not disturbed")


func test_rebuild_freeze_holds_only_sleeping_blocks_for_one_step() -> void:
	_snow.max_disc_patches = 0
	var resting: Block = _cube(Vector3(-1.5, 0.01, 0.0))
	var moving: Block = _cube(Vector3(1.5, 3.0, 0.0))
	await _frames(SETTLE_FRAMES)
	assert_true(resting.sleeping)
	moving.global_position = Vector3(1.5, 3.0, 0.0)
	moving.sleeping = false
	moving.linear_velocity = Vector3(0.0, -1.0, 0.0)
	await get_tree().physics_frame
	assert_false(moving.sleeping, "second block is in motion")
	var builder: SnowCapBuilder = SnowCapBuilder.new(_snow, true)
	var frame: Transform3D = SnowGeometry.block_patch_transform(SnowCaps.block_cells(resting)[0], SnowGeometry.AXIS_UP, _physics.cube_size)
	var edge: float = SnowCaps.block_patch_edge(_physics.cube_size, _snow)
	builder.set_patch("b%d" % resting.net_id, resting, -1, 0, frame, edge, 7, 2)
	builder.set_patch("b%d" % moving.net_id, moving, -1, 0, frame, edge, 8, 2)
	builder.step(10)
	assert_eq(SnowCaps.lump_colliders(moving).size(), 1)
	assert_false(moving.is_freeze_static(), "a moving block is never frozen")
	assert_false(moving.freeze, "a moving block keeps simulating")
	assert_true(resting.is_freeze_static(), "the sleeping block is held for its collider swap")
	await get_tree().physics_frame
	builder.step(10)
	assert_false(resting.is_freeze_static(), "released at the next tick: one physics step")
	assert_false(resting.freeze)
	assert_true(resting.sleeping, "back asleep, not woken")
	assert_eq(builder.pending_thaws(), 0)


func test_snow_on_a_settled_pile_wakes_nothing() -> void:
	_snow.max_disc_patches = 0
	# Two touching columns: a shape change on any one used to wake them all.
	var pile: Array[Block] = []
	for x: int in range(2):
		for y: int in range(2):
			pile.append(_cube(Vector3(float(x) * (_physics.cube_size - _physics.cube_margin), 0.01 + float(y) * _physics.cube_size, 0.0)))
			await _frames(HALF_SETTLE_FRAMES)
	await _frames(SETTLE_FRAMES)
	for block: Block in pile:
		assert_true(block.sleeping, "settled before snow")
	var effect: SnowEffect = _make_effect()
	var awake_frames: int = 0
	for _i: int in range(GROW_FRAMES):
		await _frames(1)
		for block: Block in pile:
			if not block.sleeping and not block.freeze:
				awake_frames += 1
	assert_gt(effect.builder().commits, 0)
	assert_eq(effect.block_levels(pile[1])[0], _snow.depth_levels, "top of the first column snowed")
	assert_eq(awake_frames, 0, "no body in the pile woke up")
	for block: Block in pile:
		assert_false(block.is_freeze_static(), "rebuild freeze released")


func test_a_tipped_block_loses_its_snow() -> void:
	_snow.max_disc_patches = 0
	var cube: Block = _cube(Vector3(0.0, 0.01, 0.0))
	await _frames(SETTLE_FRAMES)
	var effect: SnowEffect = _make_effect()
	await _frames(GROW_FRAMES)
	assert_eq(effect.block_axis(cube), SnowGeometry.AXIS_UP)
	_snow.seconds_per_level = 1000.0
	cube.freeze = true
	cube.global_basis = Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(90.0))
	cube.global_position = Vector3(0.0, 0.5, 0.0)
	await _frames(2)
	assert_false(effect.is_melting())
	assert_ne(effect.block_axis(cube), SnowGeometry.AXIS_UP, "old face dropped")
	assert_eq(SnowCaps.lump_colliders(cube).size(), 0, "its snow slid off")


func test_a_block_dropped_on_snow_does_not_rest_flat() -> void:
	_snow.max_disc_patches = 0
	var tilt_bare: float = await _drop_tilt(false)
	var tilt_snowy: float = await _drop_tilt(true)
	gut.p("tilt bare=%.3f deg snowy=%.3f deg" % [tilt_bare, tilt_snowy])
	assert_lt(tilt_bare, MAX_FLAT_TILT_DEG, "control: a bare top is flat")
	assert_gt(tilt_snowy, MIN_SNOWY_TILT_DEG, "snowy top tilts the next block")


func _drop_tilt(with_snow: bool) -> float:
	for block: Block in _blocks:
		block.free()
	_blocks.clear()
	var base: Block = _cube(Vector3(0.0, 0.01, 0.0))
	await _frames(SETTLE_FRAMES)
	if with_snow:
		_make_effect()
		await _frames(GROW_FRAMES)
		assert_eq(_effect.block_levels(base)[0], _snow.depth_levels)
	var dropped: Block = _cube(Vector3(0.0, _physics.cube_size + _snow.max_depth_m * 2.0 + _physics.hover_height, 0.0))
	await _frames(SETTLE_FRAMES * 2)
	var tilt: float = _tilt_deg(dropped)
	assert_gt(dropped.global_position.y, _physics.cube_size * 0.9, "still on the base block")
	if _effect != null:
		_effect.restore()
		_effect = null
	return tilt


func test_adjacent_cells_form_one_continuous_layer_with_rim_only_at_the_outside() -> void:
	_snow.max_disc_patches = 0
	var block: Block = BlockFactory.build(load("res://config/blocks/cube.tres") as BlockShape, _physics)
	_root.add_child(block)
	var cube: float = _physics.cube_size
	var builder: SnowCapBuilder = SnowCapBuilder.new(_snow, false)
	var edge: float = SnowCaps.block_patch_edge(cube, _snow)
	var level: int = _snow.depth_levels
	for k: int in range(2):
		var frame: Transform3D = SnowGeometry.block_patch_transform(Vector3(cube * float(k), cube * 0.5, 0.0), SnowGeometry.AXIS_UP, cube)
		builder.set_patch("b", block, -1, k, frame, edge, 11 + k, level)
	builder.step(10)
	var mesh: MeshInstance3D = SnowCaps.cap_mesh(block, SnowCaps.CAP_NAME)
	assert_not_null(mesh)
	var top: float = _snow.cap_lift_m + SnowGeometry.dome_height(level, _snow)
	var flat_at_seam: int = 0
	var rim_at_seam: int = 0
	for v: Vector3 in (mesh.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(v.x - cube * 0.5) < 0.001 and absf(v.z) < cube * 0.3:
			if absf(v.y - (cube + top)) < 0.001:
				flat_at_seam += 1
			elif v.y < cube + _snow.cap_lift_m + 0.001:
				rim_at_seam += 1
	assert_gt(flat_at_seam, 0, "the shared edge carries full-depth snow")
	assert_eq(rim_at_seam, 0, "no rim dips at the seam between two cells")


func _seam_counts(mesh: MeshInstance3D, seam_x: float, cube: float, level: int) -> Vector2i:
	var top: float = _snow.cap_lift_m + SnowGeometry.dome_height(level, _snow)
	var flat: int = 0
	var rim: int = 0
	for v: Vector3 in (mesh.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(v.x - seam_x) < 0.001 and absf(v.z) < cube * 0.3:
			if absf(v.y - (cube + top)) < 0.002:
				flat += 1
			elif v.y < cube + _snow.cap_lift_m + 0.001:
				rim += 1
	return Vector2i(flat, rim)


func test_touching_same_height_tops_of_two_blocks_merge_visually_and_reopen_when_one_moves() -> void:
	var cube: float = _physics.cube_size
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var a: Block = BlockFactory.build(shape, _physics)
	var b: Block = BlockFactory.build(shape, _physics)
	_root.add_child(a)
	_root.add_child(b)
	a.global_position = Vector3.ZERO
	b.global_position = Vector3(cube, 0.0, 0.0)
	var builder: SnowCapBuilder = SnowCapBuilder.new(_snow, true)
	var edge: float = SnowCaps.block_patch_edge(cube, _snow)
	var level: int = _snow.depth_levels
	var frame: Transform3D = SnowGeometry.block_patch_transform(Vector3(0.0, cube * 0.5, 0.0), SnowGeometry.AXIS_UP, cube)
	builder.set_patch("a", a, -1, 0, frame, edge, 5, level)
	builder.set_patch("b", b, -1, 0, frame, edge, 6, level)
	builder.step(10)
	builder.step(10)
	var mesh_a: MeshInstance3D = SnowCaps.cap_mesh(a, SnowCaps.CAP_NAME)
	assert_not_null(mesh_a)
	var seam: Vector2i = _seam_counts(mesh_a, cube * 0.5, cube, level)
	assert_gt(seam.x, 0, "full-depth snow reaches the shared edge between blocks")
	assert_eq(seam.y, 0, "no rim dips where two block tops meet")
	assert_eq(SnowCaps.lump_colliders(a).size(), 1, "hulls stay one per block patch")
	var hull_before: PackedVector3Array = ((SnowCaps.lump_colliders(a)[0] as CollisionShape3D).shape as ConvexPolygonShape3D).points
	# A block at another height does not merge; moving b away reopens the rim.
	b.global_position = Vector3(cube * 3.0, 0.0, 0.0)
	for _i: int in range(6):
		builder.step(10)
	mesh_a = SnowCaps.cap_mesh(a, SnowCaps.CAP_NAME)
	seam = _seam_counts(mesh_a, cube * 0.5, cube, level)
	assert_eq(seam, Vector2i.ZERO, "the cap pulls back from the edge once the neighbour is gone")
	var hull_after: PackedVector3Array = ((SnowCaps.lump_colliders(a)[0] as CollisionShape3D).shape as ConvexPolygonShape3D).points
	assert_eq(hull_after, hull_before, "the collider hull does not depend on the neighbour block")
