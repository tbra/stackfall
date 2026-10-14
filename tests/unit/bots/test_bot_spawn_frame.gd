extends GutTest
## Bontago-1t5.55.1 (docs/BOT_TOWER_PLAN.md 55a): the bot models a piece where it actually spawns,
## cube at B*(cell - bottom_center()) around the pivot the host is given (BlockFactory.build parity).
## Pure geometry: no match, no physics stepping.

const MAP_RADIUS: float = 20.0
const CELL: float = 0.5
const HOME_A: Vector2 = Vector2(-15.0, 0.0)
const HOME_B: Vector2 = Vector2(15.0, 0.0)
const TOWER_POS: Vector2 = Vector2(-6.0, 3.0)
const TOWER_TOP_M: float = 4.0
const CANDIDATE_COUNT: int = 150
const SEED: int = 7
const EPS: float = 1e-4
const SUPPORT_Y: float = 1.25

var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _tuning: BotGenTuning = preload("res://config/bots/bot_gen_tuning.tres")
var _physics: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
var _slots: Array[PlayerSlot] = []


func before_each() -> void:
	_slots = [
		PlayerSlot.new(0, 0, "a", Color.WHITE, HOME_A),
		PlayerSlot.new(1, 1, "b", Color.WHITE, HOME_B),
	]


func _view(held: BlockShape) -> BotWorldView:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, CELL)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, _territory_tuning)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(HOME_A, 0, 0, _territory_tuning),
		InfluenceCircle.for_home(HOME_B, 1, 1, _territory_tuning),
		InfluenceCircle.for_block(TOWER_POS, TOWER_TOP_M, 0, 0, 1, _territory_tuning, MAP_RADIUS),
	]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	raster.update(circles, solver.solve(circles), 0.1, false, false)
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	for circle: InfluenceCircle in circles:
		xs.append(circle.center.x)
		zs.append(circle.center.y)
		radii.append(circle.radius)
		teams.append(circle.team_id)
	var arrays: Dictionary = {"xs": xs, "zs": zs, "radii": radii, "teams": teams}
	return BotWorldView.build(
		0, 0, arrays, _slots, raster, PackedVector2Array([Vector2.ZERO]), 0.0, held, held, null,
		PackedVector2Array(), PackedVector2Array()
	)


func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func test_info_cubes_match_the_spawned_collision_cubes() -> void:
	for shape: BlockShape in BlockShape.load_bag_shapes():
		var block: Block = BlockFactory.build(shape, _physics)
		add_child_autofree(block)
		var positions: Array[Vector3] = []
		for child: Node in block.get_children():
			if child is CollisionShape3D:
				positions.append((child as CollisionShape3D).position)
		assert_eq(positions.size(), shape.cells.size(), "%s collision cubes" % shape.id)
		for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(shape, _tuning):
			var basis: Basis = BlockOrientations.get_basis(info.index)
			var offsets: PackedVector3Array = shape.cube_offsets(basis, _physics.cube_size)
			var info_set: Array[Vector2] = []
			for p: Vector2 in info.cubes:
				info_set.append(p * _physics.cube_size)
			for pos: Vector3 in positions:
				var rotated: Vector2 = _xz(basis * pos)
				var found: bool = false
				for q: Vector2 in info_set:
					if q.distance_to(rotated) <= EPS:
						found = true
						break
				assert_true(found, "%s o%d cube at %s" % [shape.id, info.index, rotated])
				var in_offsets: bool = false
				for o: Vector3 in offsets:
					if _xz(o).distance_to(rotated) <= EPS:
						in_offsets = true
						break
				assert_true(in_offsets, "%s o%d cube_offsets parity" % [shape.id, info.index])


func test_footprint_cells_of_covers_the_spawned_boxes() -> void:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, CELL)
	var origin: Vector2 = Vector2(1.3, -2.1)
	var half: float = _physics.cube_size * 0.5 - 0.001
	for shape: BlockShape in BlockShape.load_bag_shapes():
		for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(shape, _tuning):
			var basis: Basis = BlockOrientations.get_basis(info.index)
			var expected: Dictionary = {}
			for offset: Vector3 in shape.cube_offsets(basis, _physics.cube_size):
				var centre: Vector2 = origin + _xz(offset)
				var x0: int = floori((centre.x - half + grid.half_extent) / grid.cell_size)
				var x1: int = ceili((centre.x + half + grid.half_extent) / grid.cell_size) - 1
				var y0: int = floori((centre.y - half + grid.half_extent) / grid.cell_size)
				var y1: int = ceili((centre.y + half + grid.half_extent) / grid.cell_size) - 1
				for cy: int in range(y0, y1 + 1):
					for cx: int in range(x0, x1 + 1):
						expected[cy * grid.res + cx] = true
			var got: PackedInt32Array = BotStatics.footprint_cells_of(shape, info, origin, _physics.cube_size, grid)
			var got_set: Dictionary = {}
			for index: int in got:
				got_set[index] = true
			assert_eq(got_set.keys().size(), expected.keys().size(), "%s o%d cell count" % [shape.id, info.index])
			for index: Variant in expected:
				assert_true(got_set.has(index), "%s o%d covers cell %s" % [shape.id, info.index, index])


func test_stack_sites_centre_the_footprint_on_the_tower() -> void:
	var intent: BotIntent = BotIntent.new()
	intent.kind = BotIntent.Kind.ANCHOR
	intent.target = HOME_B
	for id: String in ["T4", "plate9", "bar3"]:
		var shape: BlockShape = _shape_by_id(id)
		assert_not_null(shape, id)
		if shape == null:
			continue
		var view: BotWorldView = _view(shape)
		var profile: BotDifficultyProfile = BotDifficultyProfile.new()
		profile.candidate_count = CANDIDATE_COUNT
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = SEED
		var stacks: int = 0
		for c: BotCandidate in BotCandidateGen.sites(view, intent, profile, rng, _tuning):
			if c.site_kind != BotCandidateGen.SITE_STACK:
				continue
			stacks += 1
			var basis: Basis = BlockOrientations.get_basis(c.orientation_index)
			var lo: Vector2 = Vector2(INF, INF)
			var hi: Vector2 = Vector2(-INF, -INF)
			for offset: Vector3 in shape.cube_offsets(basis, _physics.cube_size):
				lo = lo.min(_xz(offset))
				hi = hi.max(_xz(offset))
			var centre: Vector2 = c.origin + (lo + hi) * 0.5
			assert_true(
				centre.distance_to(TOWER_POS) <= _tuning.stack_jitter_m + EPS,
				"%s o%d footprint centre %s is %.2f m from the tower" % [id, c.orientation_index, centre, centre.distance_to(TOWER_POS)]
			)
		assert_true(stacks > 0, "%s has stack sites" % id)


func test_spawn_pose_rests_every_orientation_on_the_support() -> void:
	for shape: BlockShape in BlockShape.load_bag_shapes():
		var half: float = (_physics.cube_size - _physics.cube_margin) * 0.5
		for index: int in range(BlockOrientations.count()):
			var basis: Basis = BlockOrientations.get_basis(index)
			var pose: Vector3 = BotController.spawn_pose(shape, index, Vector2(2.0, 3.0), SUPPORT_Y, _physics)
			assert_eq(Vector2(pose.x, pose.z), Vector2(2.0, 3.0))
			var lowest: float = INF
			for local: Vector3 in shape.cube_offsets(Basis.IDENTITY, _physics.cube_size):
				for corner_sign: Vector3 in BlockShape.CORNER_SIGNS:
					lowest = minf(lowest, pose.y + (basis * (local + corner_sign * half)).y)
			assert_almost_eq(lowest, SUPPORT_Y, EPS, "%s o%d rests on the support" % [shape.id, index])


func _shape_by_id(id: String) -> BlockShape:
	for shape: BlockShape in BlockShape.load_bag_shapes():
		if String(shape.id) == id:
			return shape
	return null
