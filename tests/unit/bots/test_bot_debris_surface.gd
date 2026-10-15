extends GutTest
## Bontago-1t5.68 (owner: "as long as the surface is horizontal (or perpendicular to the disc in case it tilts) it
## should be fine"): after a collapse a bot may build beside the old pile and on its debris when every face under
## the piece lies flat against the disc. Tilted faces still reject, the centre of mass is still checked through the
## whole pile (the debris blocks as carriers), and flatness is judged against the disc normal, not world up.
## Pure snapshots (BotStack) except the tilted-disc test, which goes through game/BotStackProbe's frame conversion.

const CUBE: float = 1.0
const HALF: float = 0.5
const MASS: float = 1.0
const BAR_MASS: float = 3.0
const EPS: float = 0.01
## The 1t5.54 clearance these sites and bases used to keep from any unsound cube.
const OLD_CLEARANCE_M: float = 2.0
const LEAN_DEG: float = 30.0
const PILE_LEAN_DEG: float = 20.0

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const HOME_A: Vector2 = Vector2(-10.0, 0.0)
const HOME_B: Vector2 = Vector2(10.0, 0.0)
const TEAM: int = 0
const ENEMY: int = 1
const CANDIDATE_COUNT: int = 40
const SEED: int = 6868
const FOUNDATION_DIRECTIONS: int = 8
## Generator scene: a flat fallen cube west of the base, a leaning cube east of it (foundation jitter 0.5 m).
const FLAT_XZ: Vector2 = Vector2(-10.6, 0.0)
const LEAN_XZ: Vector2 = Vector2(-9.4, 0.0)
const BODY_ID_BASE: int = 500

var _t: BotStackTuning = preload("res://config/bots/bot_stack_tuning.tres")
var _gen_tuning: BotGenTuning = preload("res://config/bots/bot_gen_tuning.tres")
var _strategy_tuning: BotStrategyTuning = preload("res://config/bots/bot_strategy_tuning.tres")
var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")

var _grid: CellGrid = null
var _raster: TerritoryRaster = null
var _slots: Array[PlayerSlot] = []
var _next_id: int = BODY_ID_BASE


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_raster = TerritoryRaster.new(_grid, _territory_tuning)
	_slots = [
		PlayerSlot.new(0, TEAM, "a", Color.WHITE, HOME_A),
		PlayerSlot.new(1, ENEMY, "b", Color.WHITE, HOME_B),
	]
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(HOME_A, 0, TEAM, _territory_tuning),
		InfluenceCircle.for_home(HOME_B, 1, ENEMY, _territory_tuning),
	]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	_raster.update(circles, solver.solve(circles), 0.1, false, false)
	_next_id = BODY_ID_BASE
	BotThink._strategy_memory.clear()


# --- fixtures -----------------------------------------------------------------------------------------------


func _stack() -> BotStack:
	var stack: BotStack = BotStack.new()
	stack.cube_size = CUBE
	return stack


func _analysed(stack: BotStack) -> BotStack:
	while not stack.analyse_step(stack.body_count(), _t):
		pass
	return stack


## Adds a body and returns its id.
func _add(
	stack: BotStack, cubes: Array[Vector3], basis: Basis = Basis.IDENTITY, mass: float = MASS, settled: bool = true
) -> int:
	var id: int = _next_id
	_next_id += 1
	stack.add_body(id, TEAM, basis, PackedVector3Array(cubes), mass, settled)
	return id


## A single cube resting on the disc at `xz`, tilted `deg` about z (0 = flat).
func _disc_cube(stack: BotStack, xz: Vector2, deg: float = 0.0) -> int:
	return _add(stack, [Vector3(xz.x, HALF, xz.y)], Basis(Vector3.BACK, deg_to_rad(deg)))


## A three-cube bar lying flat along x, centred at `xz`, its cubes `y` high (a fallen bar).
func _lying_bar(stack: BotStack, xz: Vector2, y: float) -> int:
	var cubes: Array[Vector3] = [
		Vector3(xz.x - CUBE, y, xz.y), Vector3(xz.x, y, xz.y), Vector3(xz.x + CUBE, y, xz.y)
	]
	return _add(stack, cubes, Basis(Vector3.BACK, deg_to_rad(90.0)), BAR_MASS)


func _points(values: Array[Vector2]) -> PackedVector2Array:
	return PackedVector2Array(values)


# --- the support-face rule (BotStack) ------------------------------------------------------------------------


func test_a_fallen_block_lying_flat_on_the_disc_is_a_valid_support() -> void:
	var stack: BotStack = _stack()
	var bar: int = _lying_bar(stack, Vector2.ZERO, HALF)
	_disc_cube(stack, Vector2(0.0, 1.5), LEAN_DEG)
	_analysed(stack)
	var b: int = stack.index_of(bar)
	assert_true(stack.is_flat_support(b), "a bar lying flat on the disc offers flat faces")
	assert_eq(stack.surface_at(Vector2.ZERO), b)
	var margin: float = stack.rest_margin(_points([Vector2.ZERO]), Vector2.ZERO, MASS)
	assert_false(is_inf(margin), "the piece rests on the fallen bar, not the disc")
	assert_gte(margin, 0.0, "a site on the fallen bar is accepted")


# --- the generator and the new base --------------------------------------------------------------------------

## `own_xz`: own block circles (1 m tops) so the plan has own blocks.
func _view(own_xz: Array[Vector2]) -> BotWorldView:
	var xs: PackedFloat32Array = PackedFloat32Array([HOME_A.x, HOME_B.x])
	var zs: PackedFloat32Array = PackedFloat32Array([HOME_A.y, HOME_B.y])
	var radii: PackedFloat32Array = PackedFloat32Array([_territory_tuning.home_radius, _territory_tuning.home_radius])
	var teams: PackedInt32Array = PackedInt32Array([TEAM, ENEMY])
	for xz: Vector2 in own_xz:
		xs.append(xz.x)
		zs.append(xz.y)
		radii.append(InfluenceCircle.radius_for_height(CUBE, _territory_tuning, MAP_RADIUS))
		teams.append(TEAM)
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = MatchConfig.GameMode.REACH_THE_SKY
	return BotWorldView.build(
		0, TEAM, {"xs": xs, "zs": zs, "radii": radii, "teams": teams}, _slots, _raster,
		PackedVector2Array([Vector2.ZERO]), _territory_tuning.goal_zone_radius, _cube, _cube, goal,
		PackedVector2Array(), PackedVector2Array()
	)


func _profile() -> BotDifficultyProfile:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.candidate_count = CANDIDATE_COUNT
	profile.stability_raycast_count = 9
	return profile


func _rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


func _has_site_at(sites: Array[BotCandidate], point: Vector2) -> bool:
	for site: BotCandidate in sites:
		if site.origin.distance_to(point) < EPS:
			return true
	return false


func test_new_base_sites_rest_beside_and_on_flat_debris_but_never_on_tilted_debris() -> void:
	var view: BotWorldView = _view([FLAT_XZ, LEAN_XZ])
	var stack: BotStack = _stack()
	var flat: int = _disc_cube(stack, FLAT_XZ)
	# Bontago-1t5.72 (H13): a tilted face is centred on the face, not the cube centre, so a cube leaning towards the
	# home would overhang the foundation points; it leans away from them (the sign) and the sites beside it stay bare.
	var lean: int = _disc_cube(stack, LEAN_XZ, -LEAN_DEG)
	view.stack = _analysed(stack)
	var intent: BotIntent = BotStrategy._make(_strategy_tuning, BotIntent.Kind.ANCHOR, HOME_A)
	intent.new_base = true
	var sites: Array[BotCandidate] = BotCandidateGen.sites(view, intent, _profile(), _rng())
	var on_flat: int = 0
	var beside: int = 0
	for site: BotCandidate in sites:
		var body: int = stack.surface_at(site.origin)
		assert_ne(body, stack.index_of(lean), "no site rests on the leaning cube (%s)" % site.origin)
		if body == stack.index_of(flat):
			on_flat += 1
		elif body < 0 and site.origin.distance_to(LEAN_XZ) < OLD_CLEARANCE_M:
			beside += 1
	# The foundation ring: the base and eight points 0.5 m around it, each placeable own land.
	var ring: Array[Vector2] = [HOME_A]
	for step: int in range(FOUNDATION_DIRECTIONS):
		ring.append(HOME_A + Vector2.from_angle(TAU * float(step) / float(FOUNDATION_DIRECTIONS)) * _gen_tuning.foundation_jitter_m)
	for point: Vector2 in ring:
		assert_eq(PlacementRules.validate_point(point, _raster, TEAM), PlacementRules.Result.VALID, "fixture: %s" % point)
		var over_lean: bool = stack.surface_at(point) == stack.index_of(lean)
		assert_eq(_has_site_at(sites, point), not over_lean, "foundation point %s kept iff not on the lean" % point)
	assert_gt(on_flat, 0, "sites rest on the flat fallen cube")
	assert_gt(beside, 0, "sites sit on the bare disc right beside the leaning cube")


func test_the_new_base_may_sit_on_a_flat_fallen_block_but_not_on_a_flat_top_of_a_leaning_pile() -> void:
	var first: Vector2 = _first_base_sample()
	var far_base: Vector2 = HOME_A + Vector2(0.0, -_territory_tuning.home_radius)
	# Bontago-1t5.70: the grace time has run out (sky_lost), so the fallen tower starts the new base at once.
	var memory: Dictionary = {
		"sky_base": far_base, "sky_peak": 9.0, "sky_pending": false,
		"sky_lost": BotStrategy.SHIPPED_TUNING.collapse_grace_thinks,
	}
	# A flat fallen cube under the first sample, a leaning one 1.1 m east of it.
	var view: BotWorldView = _view([first, first + Vector2(1.1, 0.0)])
	var stack: BotStack = _stack()
	var fallen: int = _disc_cube(stack, first)
	_disc_cube(stack, first + Vector2(1.1, 0.0), LEAN_DEG)
	view.stack = _analysed(stack)
	var intent: BotIntent = BotStrategy.choose(view, BotChains.build(view), _profile(), null, memory)
	assert_true(intent.new_base, "the tower fell (no sound top near the old base)")
	assert_lt(intent.target.distance_to(first), EPS, "the base sits on the flat fallen cube")
	assert_eq(stack.surface_at(intent.target), stack.index_of(fallen))
	# DECISION pinned (BotStrategy._base_usable): a flat top on a leaning pile may carry sites, not the base.
	var pile_view: BotWorldView = _view([first])
	var pile: BotStack = _stack()
	_disc_cube(pile, first, PILE_LEAN_DEG)
	var top: int = _add(pile, [Vector3(first.x, HALF + CUBE, first.y)])
	pile_view.stack = _analysed(pile)
	assert_true(pile.is_flat_support(pile.index_of(top)), "fixture: the pile's top is a flat support")
	var moved: BotIntent = BotStrategy.choose(pile_view, BotChains.build(pile_view), _profile(), null, {})
	assert_true(moved.new_base)
	assert_gt(moved.target.distance_to(first), EPS, "the base is not on the unsound pile")
	assert_eq(pile.surface_at(moved.target), -1)


## BotStrategy._find_new_base's first sunflower point over the home circle (the nearest one to the home).
func _first_base_sample() -> Vector2:
	var samples: int = maxi(_strategy_tuning.base_samples, 1)
	return HOME_A + Vector2.from_angle(0.0) * (_territory_tuning.home_radius * sqrt(0.5 / float(samples)))
