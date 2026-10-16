extends GutTest
## 55b: the bot probes the REAL bottom cubes (outermost first), the resting plane is the
## highest probed hit, an overhanging cube beyond a capped tier's first cells is detected, and BotCandidate
## carries the stub fields 1t5.53b fills (probe_points, support_bodies).

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const HOME_A: Vector2 = Vector2(-10.0, 0.0)
const HOME_B: Vector2 = Vector2(10.0, 0.0)
const CUBE: float = 1.0
const ORIGIN: Vector2 = Vector2(2.2, 3.3)
const STEP_HEIGHT_M: float = 1.0
const HARD_RAYS: int = 9
const EASY_RAYS: int = 2
const PLATE_CUBES: int = 9
const SITES: int = 40
const TOL_M: float = 0.001
const FAR_X_M: float = 100.0

var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _gen_tuning: BotGenTuning = preload("res://config/bots/bot_gen_tuning.tres")
var _grid: CellGrid = null
var _raster: TerritoryRaster = null
var _slots: Array[PlayerSlot] = []
var _plate: BlockShape = preload("res://config/blocks/plate9.tres")
var _tower_edge_x: float = 0.0
var _cell_calls: int = 0
var _centre_calls: int = 0


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_raster = TerritoryRaster.new(_grid, _territory_tuning)
	_slots = [PlayerSlot.new(0, 0, "a", Color.WHITE, HOME_A), PlayerSlot.new(1, 1, "b", Color.WHITE, HOME_B)]
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(HOME_A, 0, 0, _territory_tuning),
		InfluenceCircle.for_home(HOME_B, 1, 1, _territory_tuning),
	]
	_raster.fill_ownership(circles, TerritorySolver.new(_territory_tuning).solve(circles), false)
	_raster.adopt_fill(_raster, 0.1, false, false)
	_cell_calls = 0
	_centre_calls = 0
	_tower_edge_x = FAR_X_M


func _view(held: BlockShape) -> BotWorldView:
	var arrays: Dictionary = {
		"xs": PackedFloat32Array([HOME_A.x, HOME_B.x]),
		"zs": PackedFloat32Array([HOME_A.y, HOME_B.y]),
		"radii": PackedFloat32Array([_territory_tuning.home_radius, _territory_tuning.home_radius]),
		"teams": PackedInt32Array([0, 1]),
	}
	return BotWorldView.build(
		0, 0, arrays, _slots, _raster, PackedVector2Array([Vector2.ZERO]),
		_territory_tuning.goal_zone_radius, held, held, null, PackedVector2Array(), PackedVector2Array()
	)


func _profile(rays: int) -> BotDifficultyProfile:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.candidate_count = SITES
	profile.stability_raycast_count = rays
	profile.eval_top_k = 0
	profile.pick_pool = 1
	return profile


## Flat ground except a 1 m block covering x >= _tower_edge_x.
func _surface(xz: Vector2) -> float:
	return STEP_HEIGHT_M if xz.x >= _tower_edge_x else 0.0


func _candidate(origin: Vector2, orientation: int) -> BotCandidate:
	var c: BotCandidate = BotCandidate.new()
	c.origin = origin
	c.orientation_index = orientation
	return c


## The orientation of `shape` with the most bottom cubes (lying flat).
func _flat_info(shape: BlockShape) -> BotStatics.OrientationInfo:
	var best: BotStatics.OrientationInfo = null
	for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(shape, _gen_tuning):
		if best == null or info.contact_area > best.contact_area:
			best = info
	return best


func _requirement(view: BotWorldView) -> BotStability.Requirement:
	var bot_tuning: BotTuning = load("res://config/bots/bot_tuning.tres") as BotTuning
	return BotStability.requirement(
		_profile(HARD_RAYS), view, preload("res://config/bots/bot_stack_tuning.tres"), bot_tuning.stability_contact_tolerance_m
	)


func test_contact_points_are_the_real_cubes_outermost_first() -> void:
	var info: BotStatics.OrientationInfo = _flat_info(_plate)
	assert_eq(info.contact.size(), PLATE_CUBES, "plate9 lying flat has 9 bottom cubes")
	var c: BotCandidate = _candidate(ORIGIN, info.index)
	var all: PackedVector2Array = BotStatics.contact_probe_points(c, info, CUBE, HARD_RAYS)
	assert_eq(all.size(), PLATE_CUBES)
	var centroid: Vector2 = Vector2.ZERO
	for p: Vector2 in all:
		centroid += p
	centroid /= float(PLATE_CUBES)
	for i: int in range(1, all.size()):
		assert_gte(all[i - 1].distance_to(centroid) + TOL_M, all[i].distance_to(centroid), "descending distance")
	var capped: PackedVector2Array = BotStatics.contact_probe_points(c, info, CUBE, EASY_RAYS)
	assert_eq(capped.size(), EASY_RAYS)
	assert_gt(capped[0].distance_to(centroid), CUBE, "a capped tier probes a corner cube first")
	for p: Vector2 in all:
		var found: bool = false
		for offset: Vector2 in info.contact:
			if p.distance_to(ORIGIN + offset * CUBE) < TOL_M:
				found = true
		assert_true(found, "every point is a cube centre in the spawn frame")
	assert_eq(BotStatics.contact_probe_points(c, info, CUBE, 0).size(), 0)


## Only the outer column rests on something; the nine rays see the other six cubes hang: sure overhang.
func test_a_one_sided_support_is_detected() -> void:
	var info: BotStatics.OrientationInfo = _flat_info(_plate)
	var c: BotCandidate = _candidate(ORIGIN, info.index)
	c.probe_points = BotStatics.contact_probe_points(c, info, CUBE, HARD_RAYS)
	c.cell_support.resize(c.probe_points.size())
	c.support_bodies.resize(c.probe_points.size())
	c.support_bodies.fill(-1)
	var max_x: float = ORIGIN.x + CUBE
	for i: int in range(c.probe_points.size()):
		c.cell_support[i] = 0.0 if c.probe_points[i].x > max_x - TOL_M else BotThink.NO_SUPPORT
	var view: BotWorldView = _view(_plate)
	var req: BotStability.Requirement = _requirement(view)
	assert_lte(BotStability.evaluate(c, info, view, req).slack, 0.0, "the centre of mass is over empty air")
	var flat: BotCandidate = _candidate(ORIGIN, info.index)
	flat.probe_points = c.probe_points
	flat.cell_support.resize(c.probe_points.size())
	flat.cell_support.fill(0.0)
	flat.support_bodies.resize(c.probe_points.size())
	flat.support_bodies.fill(-1)
	assert_gt(BotStability.evaluate(flat, info, view, req).slack, 0.0, "every cube on the disc stands")
	var none: BotCandidate = _candidate(ORIGIN, info.index)
	none.probe_points = c.probe_points
	none.cell_support.resize(c.probe_points.size())
	none.cell_support.fill(BotThink.NO_SUPPORT)
	none.support_bodies.resize(c.probe_points.size())
	none.support_bodies.fill(-1)
	assert_eq(BotStability.evaluate(none, info, view, req).slack, -INF, "no cube supported")


# --- Send-time support (BotController.highest_cube_support / spawn_pose) ---------------------------------

const NOISY_ORIGIN: Vector2 = Vector2(5.45, -2.7)
var _send_rays: int = 0
var _send_miss: bool = false


## Step of STEP_HEIGHT_M under every cube centred at x >= _tower_edge_x; the pivot column stays on the ground.
func _send_ray(xz: Vector2) -> Dictionary:
	_send_rays += 1
	if _send_miss:
		return {"hit": false, "height": 0.0}
	return {"hit": true, "height": _surface(xz)}


func test_send_support_is_the_highest_cube_hit_not_the_pivot_column() -> void:
	var physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	var info: BotStatics.OrientationInfo = _flat_info(_plate)
	_tower_edge_x = NOISY_ORIGIN.x + CUBE - TOL_M  # only the outer column of the plate is on the step
	var pivot_y: float = _surface(NOISY_ORIGIN)
	assert_eq(pivot_y, 0.0, "the pivot column itself is on the ground")
	_send_rays = 0
	var support: float = BotController.highest_cube_support(
		_plate, info.index, NOISY_ORIGIN, pivot_y, physics.cube_size, HARD_RAYS, _send_ray
	)
	assert_almost_eq(support, STEP_HEIGHT_M, TOL_M)
	assert_lte(_send_rays, HARD_RAYS)
	var pose: Vector3 = BotController.spawn_pose(_plate, info.index, NOISY_ORIGIN, support, physics)
	var lift: float = -_plate.rotated_bottom_offset(BlockOrientations.get_basis(info.index), physics.cube_size, physics.cube_margin)
	assert_almost_eq(pose.y, STEP_HEIGHT_M + lift, TOL_M, "sent y = step + lift, not the pivot column's y")
	assert_eq(Vector2(pose.x, pose.z), NOISY_ORIGIN)
