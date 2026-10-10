extends GutTest
## core/ai/BotStatics.gd (Bontago-1t5.21, Bot V2 P2): orientation dedup and the
## analytic tip-risk (overhang + slenderness). Pure: a real CellGrid, no scene tree.

const MAP_RADIUS: float = 20.0
const CELL: float = 0.5
const ORIGIN: Vector2 = Vector2(2.0, 3.0)

var _tuning: BotGenTuning = preload("res://config/bot_gen_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _pillar: BlockShape = preload("res://config/blocks/pillar.tres")
var _bar3: BlockShape = preload("res://config/blocks/bar3.tres")
var _bar5: BlockShape = preload("res://config/blocks/bar5.tres")
var _grid: CellGrid = CellGrid.new(MAP_RADIUS, CELL)


func _info_with_height(shape: BlockShape, height: float) -> BotStatics.OrientationInfo:
	for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(shape, _tuning):
		if is_equal_approx(info.height, height):
			return info
	return null


func _candidate(shape: BlockShape, info: BotStatics.OrientationInfo) -> BotCandidate:
	var c: BotCandidate = BotCandidate.new()
	c.origin = ORIGIN
	c.orientation_index = info.index
	c.shape_height = info.height
	c.footprint_cells = PlacementRules.footprint_cells(
		shape.cells, BlockOrientations.get_basis(info.index), ORIGIN, 1.0, _grid
	)
	return c


func test_cube_has_one_orientation_and_pillar_two_heights() -> void:
	assert_eq(BotStatics.orientation_infos(_cube, _tuning).size(), 1)
	var heights: Array[float] = []
	for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(_pillar, _tuning):
		if not heights.has(info.height):
			heights.append(info.height)
	assert_eq(heights.size(), 2, "flat and upright")
	assert_true(heights.has(3.0))
	assert_true(heights.has(1.0))


func test_orientations_are_capped_and_distinct() -> void:
	for shape: BlockShape in BlockShape.load_all_shapes():
		var infos: Array[BotStatics.OrientationInfo] = BotStatics.orientation_infos(shape, _tuning)
		assert_true(infos.size() <= _tuning.max_orientations_per_shape, "%s capped" % shape.id)
		assert_false(infos.is_empty())
		var signatures: Dictionary = {}
		for info: BotStatics.OrientationInfo in infos:
			assert_false(signatures.has(info.signature), "%s distinct" % shape.id)
			signatures[info.signature] = true


func test_upright_pillar_is_acceptable_but_upright_bar5_is_not() -> void:
	var pillar_up: BotStatics.OrientationInfo = _info_with_height(_pillar, 3.0)
	var bar5_up: BotStatics.OrientationInfo = _info_with_height(_bar5, 5.0)
	assert_not_null(bar5_up)
	assert_true(pillar_up.flat_risk <= _tuning.tip_risk_max)
	assert_true(bar5_up.flat_risk > _tuning.tip_risk_max)
	assert_almost_eq(_info_with_height(_pillar, 1.0).flat_risk, 0.0, 0.001)


func test_tip_risk_without_probes_is_the_flat_risk() -> void:
	var info: BotStatics.OrientationInfo = _info_with_height(_pillar, 3.0)
	assert_almost_eq(BotStatics.tip_risk(_candidate(_pillar, info), _pillar, _grid, _tuning), info.flat_risk, 0.0001)


## Probes: every cell supported, or only the cells under the cube farthest from the COM.
func _probe(c: BotCandidate, info: BotStatics.OrientationInfo, only_far_cube: bool) -> void:
	var far: Vector2 = info.contact[0]
	for p: Vector2 in info.contact:
		if p.distance_to(info.com) > far.distance_to(info.com):
			far = p
	var far_world: Vector2 = c.origin + far
	c.cell_support.resize(c.footprint_cells.size())
	for i: int in range(c.footprint_cells.size()):
		var center: Vector2 = _grid.index_center(c.footprint_cells[i])
		var under_far: bool = absf(center.x - far_world.x) <= 0.5 and absf(center.y - far_world.y) <= 0.5
		c.cell_support[i] = c.support_height if (under_far or not only_far_cube) else BotThink.NO_SUPPORT


func test_overhanging_orientation_exceeds_the_threshold() -> void:
	var info: BotStatics.OrientationInfo = _info_with_height(_bar3, 1.0)
	var c: BotCandidate = _candidate(_bar3, info)
	_probe(c, info, false)
	assert_true(BotStatics.tip_risk(c, _bar3, _grid, _tuning) <= _tuning.tip_risk_max, "fully supported is fine")
	_probe(c, info, true)
	assert_true(BotStatics.tip_risk(c, _bar3, _grid, _tuning) > _tuning.tip_risk_max, "only the end cube supported")


func test_unsupported_share_without_a_grid_raises_risk() -> void:
	var info: BotStatics.OrientationInfo = _info_with_height(_bar3, 1.0)
	var c: BotCandidate = _candidate(_bar3, info)
	_probe(c, info, false)
	var supported: float = BotStatics.tip_risk(c, _bar3, null, _tuning)
	_probe(c, info, true)
	var overhung: float = BotStatics.tip_risk(c, _bar3, null, _tuning)
	assert_true(overhung > supported)
	assert_true(overhung > _tuning.tip_risk_max)


func test_nothing_supported_is_certain_tip() -> void:
	var info: BotStatics.OrientationInfo = _info_with_height(_cube, 1.0)
	var c: BotCandidate = _candidate(_cube, info)
	c.cell_support.resize(c.footprint_cells.size())
	c.cell_support.fill(BotThink.NO_SUPPORT)
	assert_almost_eq(BotStatics.tip_risk(c, _cube, _grid, _tuning), 1.0, 0.0001)


func test_cube_size_argument_changes_cell_matching() -> void:
	var info: BotStatics.OrientationInfo = _info_with_height(_bar3, 1.0)
	var c: BotCandidate = _candidate(_bar3, info)
	_probe(c, info, true)
	var shipped: float = BotStatics.tip_risk(c, _bar3, _grid, _tuning)
	var huge: float = BotStatics.tip_risk(c, _bar3, _grid, _tuning, 100.0)
	assert_true(huge != shipped or huge <= _tuning.tip_risk_max, "a different cube size is honoured")
	assert_true(huge < shipped, "huge cubes match every probed cell, so unsupported cells are diluted")
