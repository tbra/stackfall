extends GutTest
## Snow: the host effect on a real (tiny) Field with real
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
const MELT_SETTLE_FRAMES: int = 6
## Melt time of the fixture snow (the shipped 20 s would make every test wait).
const FIXTURE_MELT_S: float = 1.0
var _field: Field = null
var _root: Node3D = null
var _blocks: Array[Block] = []
var _physics: PhysicsTuning = null
var _snow: SnowTuning = null
var _effect: SnowEffect = null
var _registry: BlockRegistry = null
var _context: FakeMatchContext = null
var _previous_context: MatchContext = null


func before_each() -> void:
	_field = Field.new()
	_field.map_def = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_field.map_def.field_radius = FIELD_RADIUS_M
	add_child_autofree(_field)
	_root = Node3D.new()
	add_child_autofree(_root)
	_blocks.clear()
	_physics = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	_snow = (load("res://config/weather/snow.tres") as SnowTuning).duplicate() as SnowTuning
	_snow.seconds_per_level = 0.05
	_snow.patch_checks_per_frame = 64
	_snow.discover_blocks_per_frame = 64
	_snow.max_disc_patches = 6
	_snow.disc_flag_clear_radius_m = 0.0
	# The fixture disc is only 12 m wide: a full-length drift would not fit.
	_snow.disc_drift_stretch = 1.5
	_snow.melt_duration_s = FIXTURE_MELT_S
	# The disc cover snaps between levels unless a test is about its easing.
	_snow.cover_ease_s = 0.0
	_effect = null
	_registry = BlockRegistry.new()
	add_child_autofree(_registry)
	_registry.configure(_field, _field.map_def)
	_previous_context = MatchContext.installed()
	_context = FakeMatchContext.new()
	_context.field_value = _field
	_context.registry_value = _registry
	_context.has_weather_value = true
	_context.weather_seed_value = SEED
	MatchContext.install(_context)


func after_each() -> void:
	if _effect != null:
		_effect.restore()
	_effect = null
	MatchContext.install(_previous_context)


func _cube(pos: Vector3) -> Block:
	var block: Block = BlockFactory.build(load("res://config/blocks/cube.tres") as BlockShape, _physics)
	_root.add_child(block)
	block.global_position = pos
	_blocks.append(block)
	Events.block_placed.emit(block, block.shape_id)
	return block


func _make_effect() -> SnowEffect:
	var effect: SnowEffect = SnowEffect.new()
	effect.bind(_context, _snow)
	_effect = effect
	return effect


func _frames(count: int, intensity: float = 1.0) -> void:
	for _i: int in range(count):
		await get_tree().physics_frame
		if _effect != null:
			_effect.tick(DT, intensity)


## The replicated state as a client reads it (levels above 0 only).
func _data(effect: SnowEffect) -> Dictionary:
	return SnowGeometry.sanitize_state(effect.state(), _snow, _field.grid().cell_count() - 1)


func _block_record(effect: SnowEffect, block: Block) -> Array:
	var blocks: Dictionary = _data(effect).get("blocks", {})
	return blocks.get(block.net_id, [])


func _block_levels(effect: SnowEffect, block: Block) -> PackedInt32Array:
	var record: Array = _block_record(effect, block)
	return record[2] if not record.is_empty() else PackedInt32Array()


func _top_level(effect: SnowEffect, block: Block) -> int:
	var levels: PackedInt32Array = _block_levels(effect, block)
	return levels[0] if not levels.is_empty() else 0


func _block_axis(effect: SnowEffect, block: Block) -> int:
	var record: Array = _block_record(effect, block)
	return int(record[0]) if not record.is_empty() else -1


func _disc_levels(effect: SnowEffect) -> Dictionary:
	return _data(effect).get("disc", {})


func _cover_level(effect: SnowEffect) -> int:
	return int(_data(effect).get("cover", 0))


## Snow colliders on every block plus the disc bodies.
func _collider_count() -> int:
	var total: int = 0
	for block: Block in _blocks:
		total += SnowCaps.lump_colliders(block).size()
	for body: StaticBody3D in SnowCaps.disc_bodies(_field):
		total += SnowCaps.lump_colliders(body).size()
	return total


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


func test_snow_grows_in_steps_to_the_cap_and_stays_bounded() -> void:
	var cubes: Array[Block] = [_cube(Vector3(-2.0, 0.01, 0.0)), _cube(Vector3(0.0, 0.01, 0.0)), _cube(Vector3(2.0, 0.01, 0.0))]
	await _frames(SETTLE_FRAMES)
	var effect: SnowEffect = _make_effect()
	await _frames(GROW_FRAMES)
	var disc_snowy: int = 0
	for cube: Block in cubes:
		assert_eq(_block_levels(effect, cube), PackedInt32Array([_snow.depth_levels]), "one exposed top, grew to the top level and stopped")
		assert_eq(SnowCaps.lump_colliders(cube).size(), 1, "one dome collider per patch")
	var disc: Dictionary = _disc_levels(effect)
	assert_lte(disc.size(), _snow.max_disc_patches, "disc budget")
	for key: Variant in disc.keys():
		assert_between(int(disc[key]), 0, _snow.depth_levels)
		if int(disc[key]) > 0:
			disc_snowy += 1
	assert_gt(disc_snowy, 0, "the disc collects snow")
	assert_eq(_collider_count(), cubes.size() + disc_snowy)
	assert_eq(_cover_level(effect), _snow.depth_levels, "disc cover reached a blanket")
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
	assert_gt(_collider_count(), 0)
	# Despawn: the effect forgets the block and its patches.
	Events.block_removed.emit(b, "test")
	_blocks.erase(b)
	b.queue_free()
	await _frames(2)
	assert_eq((_data(effect)["blocks"] as Dictionary).size(), 1, "only the live block keeps snow")
	var blocks_wire: PackedInt32Array = effect.state()["b"]
	assert_eq(blocks_wire[0], a.net_id, "state names only the live block")
	assert_eq(blocks_wire.size(), 3 + 2, "one record, one patch")
	# End of event / match end / abort all reach restore().
	effect.restore()
	assert_eq(_collider_count(), 0)
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
	assert_eq(_top_level(effect, cube), _snow.depth_levels)
	var seen: Array[int] = []
	var melt_frames: int = ceili(_snow.melt_time_s() / DT)
	for i: int in range(melt_frames + 1):
		# The intensity falls linearly (a real ramp-out); the melt clock decides.
		await _frames(1, 1.0 - float(i) / float(melt_frames))
		var level: int = _top_level(effect, cube)
		if seen.is_empty() or seen[seen.size() - 1] != level:
			seen.append(level)
	assert_eq(seen, [4, 3, 2, 1, 0], "shrinks one level at a time")
	# Geometry follows over the next frames (budgeted builder).
	await _frames(MELT_SETTLE_FRAMES, 0.0)
	assert_eq(_collider_count(), 0, "melted away before the event ends")
	assert_null(cube.get_node_or_null(NodePath(String(SnowCaps.CAP_NAME))))
	assert_eq(_cover_level(effect), 0)
	assert_null(SnowCaps.disc_cover(_field), "cover melted")
	assert_eq(float(_field.overlay().material().get_shader_parameter(&"snow_strength")), 0.0, "disc snow layer off after the melt")


## snowfall that stops dead (intensity straight to 0) used to
## drop every level at once; the melt clock now spreads it over the melt time.
func test_snow_melts_gradually_within_the_melt_time_after_snowfall_stops() -> void:
	var cube: Block = _cube(Vector3(0.0, 0.01, 0.0))
	await _frames(SETTLE_FRAMES)
	var effect: SnowEffect = _make_effect()
	await _frames(GROW_FRAMES)
	assert_eq(_top_level(effect, cube), _snow.depth_levels)
	assert_eq(_cover_level(effect), _snow.depth_levels)
	var disc_snowy_before: int = _disc_levels(effect).size()
	assert_gt(disc_snowy_before, 0, "fixture: the disc has colliding drifts to melt")
	var melt_frames: int = ceili(_snow.melt_time_s() / DT)
	assert_gt(melt_frames, 8, "fixture: a melt long enough to sample")
	var block_seen: Array[int] = []
	var cover_seen: Array[int] = []
	var middle_block: int = -1
	var middle_cover: int = -1
	var middle_colliders: int = -1
	for i: int in range(melt_frames + 1):
		await _frames(1, 0.0)
		var level: int = _top_level(effect, cube)
		if block_seen.is_empty() or block_seen[block_seen.size() - 1] != level:
			block_seen.append(level)
		var cover: int = _cover_level(effect)
		if cover_seen.is_empty() or cover_seen[cover_seen.size() - 1] != cover:
			cover_seen.append(cover)
		if i == melt_frames / 2:
			middle_block = level
			middle_cover = cover
			middle_colliders = _collider_count()
	assert_gt(middle_block, 0, "half way through the melt there is still snow on the block")
	assert_lt(middle_block, _snow.depth_levels, "and it has already shrunk")
	assert_gt(middle_cover, 0, "the disc cover is only half melted too")
	assert_lt(middle_cover, _snow.depth_levels)
	assert_gt(middle_colliders, 0)
	assert_eq(block_seen, [4, 3, 2, 1, 0], "the block's cap shrinks one level at a time down to nothing")
	assert_eq(cover_seen, [4, 3, 2, 1, 0], "so does the disc cover")
	await _frames(MELT_SETTLE_FRAMES, 0.0)
	assert_eq(_collider_count(), 0, "all colliders gone once the melt time has run")
	assert_true(SnowCaps.disc_cap_meshes(_field).is_empty(), "disc drifts melted")
	assert_null(cube.get_node_or_null(NodePath(String(SnowCaps.CAP_NAME))), "block cap melted")
	assert_null(SnowCaps.disc_cover(_field))
	assert_true(SnowRelay.is_empty_state(SnowRelay.instance().last_state), "the host replicated the empty state")


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
	assert_eq(_top_level(effect, pile[1]), _snow.depth_levels, "top of the first column snowed")
	assert_eq(awake_frames, 0, "no body in the pile woke up")
	for block: Block in pile:
		assert_false(block.is_freeze_static(), "rebuild freeze released")


func test_a_tipped_block_loses_its_snow() -> void:
	_snow.max_disc_patches = 0
	var cube: Block = _cube(Vector3(0.0, 0.01, 0.0))
	await _frames(SETTLE_FRAMES)
	var effect: SnowEffect = _make_effect()
	await _frames(GROW_FRAMES)
	assert_eq(_block_axis(effect, cube), SnowGeometry.AXIS_UP)
	_snow.seconds_per_level = 1000.0
	cube.freeze = true
	cube.global_basis = Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(90.0))
	cube.global_position = Vector3(0.0, 0.5, 0.0)
	await _frames(2)
	assert_ne(_block_axis(effect, cube), SnowGeometry.AXIS_UP, "old face dropped")
	assert_eq(SnowCaps.lump_colliders(cube).size(), 0, "its snow slid off")

