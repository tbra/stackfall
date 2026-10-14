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
## The field's largest tilt (TiltTuning.max_tilt_deg, spec 3.5): well past the support-face tolerance.
const DISC_TILT_DEG: float = 12.0
## Cube pivots sit at the bottom face: lift the scripted blocks a hair off the disc.
const LIFT_M: float = 0.02
const BOT_SLOT: int = 0

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
var _physics: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
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
	assert_true(stack.debris_near(Vector2.ZERO, OLD_CLEARANCE_M), "fixture: the old clearance rejected this site")


func test_a_tilted_debris_block_rejects_sites_resting_on_it() -> void:
	var stack: BotStack = _stack()
	var lean: int = _disc_cube(stack, Vector2.ZERO, LEAN_DEG)
	var slight: int = _disc_cube(stack, Vector2(4.0, 0.0), _t.support_face_tolerance_deg - 3.0)
	var steep: int = _disc_cube(stack, Vector2(8.0, 0.0), _t.support_face_tolerance_deg + 4.0)
	_analysed(stack)
	assert_false(stack.is_flat_support(stack.index_of(lean)))
	assert_eq(stack.rest_margin(_points([Vector2.ZERO]), Vector2.ZERO, MASS), -INF, "a leaning face rejects the site")
	assert_true(stack.is_flat_support(stack.index_of(slight)), "within the tolerance the face counts as flat")
	assert_gte(stack.rest_margin(_points([Vector2(4.0, 0.0)]), Vector2(4.0, 0.0), MASS), 0.0)
	assert_false(stack.is_flat_support(stack.index_of(steep)), "past the tolerance it does not")
	# One cube of a bar over the leaning block is enough to reject the whole piece.
	var bar: PackedVector2Array = _points([Vector2(-1.0, 0.0), Vector2.ZERO, Vector2(1.0, 0.0)])
	assert_eq(stack.rest_margin(bar, Vector2.ZERO, BAR_MASS), -INF)


func test_a_site_right_beside_debris_on_the_flat_disc_is_accepted() -> void:
	var stack: BotStack = _stack()
	_disc_cube(stack, Vector2.ZERO, LEAN_DEG)
	_analysed(stack)
	# A 30 degree lean about z narrows the cube's outline to about +-0.43 m in x: 0.8 m away is bare disc.
	var bar: PackedVector2Array = _points([Vector2(0.8, 0.0), Vector2(1.8, 0.0), Vector2(2.8, 0.0)])
	assert_eq(stack.surface_at(Vector2(0.8, 0.0)), -1, "fixture: the probe beside the debris hits the disc")
	assert_eq(stack.rest_margin(bar, Vector2(1.8, 0.0), BAR_MASS), INF, "on the disc: no block support to fail")
	assert_true(stack.debris_near(Vector2(0.8, 0.0), OLD_CLEARANCE_M), "fixture: the old clearance rejected it")


func test_a_flat_top_on_a_leaning_pile_is_judged_by_the_load_margin() -> void:
	# A cube leaning 20 degrees on the disc (outline +-0.47 m in x) carries a flat bar (3 cubes, centred on it).
	var stack: BotStack = _stack()
	var lean: int = _disc_cube(stack, Vector2.ZERO, PILE_LEAN_DEG)
	var top: int = _lying_bar(stack, Vector2.ZERO, HALF + CUBE)
	_analysed(stack)
	var l: int = stack.index_of(lean)
	var f: int = stack.index_of(top)
	assert_false(stack.is_sound(l), "fixture: the carrier leans")
	assert_false(stack.is_sound(f), "the flat top is still unsound as a tower (its carrier leans)")
	assert_true(stack.is_flat_support(f), "but its faces lie flat and its carrier chain is known")
	assert_false(stack.is_flat_support(l))
	# A light piece over the middle keeps the pile's centre of mass over the leaning carrier.
	var centred: float = stack.rest_margin(_points([Vector2.ZERO]), Vector2.ZERO, MASS)
	assert_gte(centred, 0.0, "a centred piece on the flat top is accepted")
	assert_lt(centred, HALF, "the leaning carrier's contact, not the bar's footprint, bounds the margin")
	# A bar at the far end: its own footprint holds it (0.3 m inside the top bar), but the top bar's load now
	# leaves the contact with the leaning carrier.
	var far: PackedVector2Array = _points([Vector2(0.2, 0.0), Vector2(1.2, 0.0), Vector2(2.2, 0.0)])
	var margin: float = stack.rest_margin(far, Vector2(1.2, 0.0), BAR_MASS)
	assert_lt(margin, 0.0, "the centre of mass leaves the support polygon: rejected")
	assert_false(is_inf(margin), "rejected by the load margin, not by the face rule")


func test_a_flat_face_over_an_unknown_or_moving_carrier_is_not_a_support() -> void:
	var stack: BotStack = _stack()
	# A bar on a cube whose own support is missing from the snapshot (it floats a cube above the disc).
	_add(stack, [Vector3(0.0, HALF + CUBE, 0.0)])
	var on_floating: int = _lying_bar(stack, Vector2.ZERO, HALF + 2.0 * CUBE)
	# A bar on a cube that is still sliding.
	_add(stack, [Vector3(6.0, HALF, 0.0)], Basis.IDENTITY, MASS, false)
	var on_moving: int = _lying_bar(stack, Vector2(6.0, 0.0), HALF + CUBE)
	_analysed(stack)
	assert_false(stack.is_flat_support(stack.index_of(on_floating)), "an unverifiable carrier chain")
	assert_eq(stack.rest_margin(_points([Vector2.ZERO]), Vector2.ZERO, MASS), -INF)
	assert_false(stack.is_flat_support(stack.index_of(on_moving)), "a moving carrier")
	assert_eq(stack.rest_margin(_points([Vector2(6.0, 0.0)]), Vector2(6.0, 0.0), MASS), -INF)


func test_on_a_tilted_disc_faces_are_judged_against_the_disc_normal() -> void:
	assert_gt(DISC_TILT_DEG, _t.support_face_tolerance_deg, "fixture: the disc tilts past the tolerance")
	var field: Node3D = Node3D.new()
	add_child_autofree(field)
	field.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(DISC_TILT_DEG)), Vector3.ZERO)
	var registry: BlockRegistry = BlockRegistry.new()
	autofree(registry)
	var along_xz: Vector2 = Vector2(-2.0, 0.0)
	var level_xz: Vector2 = Vector2(2.0, 0.0)
	# One cube lying flat on the tilted disc (12 degrees off world up), one level in the world (not the disc).
	var along: Block = _scripted_block(field, registry, along_xz, field.global_transform.basis)
	var level: Block = _scripted_block(field, registry, level_xz, Basis.IDENTITY)
	var stack: BotStack = BotStackProbe.build(
		registry, field, PackedVector2Array([along_xz, level_xz]), _t, _physics.cube_size,
		func(_slot: int) -> int: return TEAM
	)
	assert_not_null(stack)
	if stack == null:
		return
	_analysed(stack)
	var a: int = stack.index_of(along.get_instance_id())
	var b: int = stack.index_of(level.get_instance_id())
	assert_almost_eq(stack.body_tilt_deg[a], 0.0, 0.1, "parallel to the disc: no tilt against its normal")
	assert_almost_eq(stack.body_tilt_deg[b], DISC_TILT_DEG, 0.1, "level in the world: tilted against the disc")
	assert_true(stack.is_flat_support(a), "a face parallel to the disc is accepted while the disc tilts")
	assert_false(stack.is_flat_support(b), "a face parallel to world up but not the disc is rejected")
	assert_gte(stack.rest_margin(_points([along_xz]), along_xz, MASS), 0.0)
	assert_eq(stack.rest_margin(_points([level_xz]), level_xz, MASS), -INF)


## A frozen cube block with its pivot (bottom face) on the disc at disk-local `xz`, oriented `world_basis`.
func _scripted_block(field: Node3D, registry: BlockRegistry, xz: Vector2, world_basis: Basis) -> Block:
	var block: Block = BlockFactory.build(_cube, _physics, BOT_SLOT)
	block.freeze = true
	add_child_autofree(block)
	block.global_transform = Transform3D(world_basis, field.to_global(Vector3(xz.x, LIFT_M, xz.y)))
	registry._on_block_placed(block, _cube.id)
	return block


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


func test_the_new_base_may_sit_beside_the_pile() -> void:
	# The sunflower's first sample over the home circle (the one nearest the home) lies 0.87 m east of the home;
	# a leaning cube 0.73 m further east kept it out under the old clearance.
	var first: Vector2 = _first_base_sample()
	var lean_xz: Vector2 = first + Vector2(0.73, 0.0)
	var view: BotWorldView = _view([lean_xz])
	var stack: BotStack = _stack()
	_disc_cube(stack, lean_xz, LEAN_DEG)
	view.stack = _analysed(stack)
	var intent: BotIntent = BotStrategy.choose(view, BotChains.build(view), _profile(), null, {})
	assert_true(intent.new_base, "no sound top: a new base")
	assert_lt(intent.target.distance_to(first), EPS, "the nearest sample wins although it is beside the debris")
	assert_lt(intent.target.distance_to(lean_xz), OLD_CLEARANCE_M)
	assert_eq(stack.surface_at(intent.target), -1, "the base rests on the disc")


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
