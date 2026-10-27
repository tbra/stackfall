extends GutTest
## GhostSweep contract over a real physics space: the held shape's boxes slide from `from`
## towards `to` and stop short of a placed block (a RigidBody3D, the same type the real
## blocks use) by the collision skin; blocked motion slides along the free axis (full motion,
## then X-only, then Z-only); a box that starts embedded in a block gets the full motion;
## non-block colliders are skipped, at most `collision_probe_max_bodies` of them per cast.
##
## Geometry: unit cubes (half 0.5). The swept box is inflated by the skin, so a box whose
## centre leads towards a block face at distance d stops with its centre d - half - skin away.

const HALF: float = 0.5
const TOL: float = 0.05

var _root: Node3D


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)


func _tuning(skin: float = 0.03, max_bodies: int = 8) -> GhostTuning:
	var tuning: GhostTuning = GhostTuning.new()
	tuning.ghost_collision_skin = skin
	tuning.collision_probe_max_bodies = max_bodies
	return tuning


func _add_body(body: PhysicsBody3D, centre: Vector3, size: Vector3) -> void:
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	body.position = centre
	_root.add_child(body)


## A placed block stand-in: a frozen RigidBody3D, the type the sweep treats as a block.
func _add_block(centre: Vector3, size: Vector3 = Vector3.ONE) -> void:
	var body: RigidBody3D = RigidBody3D.new()
	body.freeze = true
	_add_body(body, centre, size)


## A non-block collider (terrain, props): the sweep must look through it.
func _add_static(centre: Vector3, size: Vector3 = Vector3.ONE) -> void:
	_add_body(StaticBody3D.new(), centre, size)


func _space() -> PhysicsDirectSpaceState3D:
	await wait_physics_frames(2)
	return _root.get_viewport().world_3d.direct_space_state


func _sweep(
	tuning: GhostTuning, centres: Array[Vector3], basis: Basis, from: Vector3, to: Vector3
) -> Vector3:
	var space: PhysicsDirectSpaceState3D = await _space()
	return GhostSweep.new(tuning).sweep(space, centres, HALF, basis, from, to)


func _single() -> Array[Vector3]:
	return [Vector3.ZERO]


# --- Free motion -----------------------------------------------------------

func test_free_motion_reaches_the_target() -> void:
	var to: Vector3 = Vector3(5.0, 0.0, 2.0)
	var result: Vector3 = await _sweep(_tuning(), _single(), Basis.IDENTITY, Vector3.ZERO, to)
	assert_true(result.is_equal_approx(to), "nothing in the way: the sweep returns `to`, got %s." % result)


func test_zero_motion_returns_the_start() -> void:
	_add_block(Vector3(4.0, 0.0, 0.0))
	var from: Vector3 = Vector3(1.0, 0.0, 0.5)
	var result: Vector3 = await _sweep(_tuning(), _single(), Basis.IDENTITY, from, from)
	assert_true(result.is_equal_approx(from), "no motion requested: stays at `from`, got %s." % result)


func test_no_boxes_returns_the_target() -> void:
	_add_block(Vector3(4.0, 0.0, 0.0))
	var to: Vector3 = Vector3(6.0, 0.0, 0.0)
	var none: Array[Vector3] = []
	var result: Vector3 = await _sweep(_tuning(), none, Basis.IDENTITY, Vector3.ZERO, to)
	assert_true(result.is_equal_approx(to), "a shape with no boxes cannot collide, got %s." % result)


func test_motion_that_stops_before_the_block_is_not_clamped() -> void:
	_add_block(Vector3(4.0, 0.0, 0.0))
	var to: Vector3 = Vector3(1.0, 0.0, 0.0)
	var result: Vector3 = await _sweep(_tuning(), _single(), Basis.IDENTITY, Vector3.ZERO, to)
	assert_true(result.is_equal_approx(to), "short of the block the whole motion is allowed, got %s." % result)


# --- Blocked motion --------------------------------------------------------

func test_blocked_motion_stops_one_skin_short_of_the_block_face() -> void:
	_add_block(Vector3(4.0, 0.0, 0.0))
	var skin: float = 0.03
	var result: Vector3 = await _sweep(
		_tuning(skin), _single(), Basis.IDENTITY, Vector3.ZERO, Vector3(6.0, 0.0, 0.0)
	)
	# Block face at x = 3.5; box half edge 0.5 + skin.
	assert_almost_eq(result.x, 3.5 - HALF - skin, TOL, "stops at the face minus half minus skin.")
	assert_almost_eq(result.z, 0.0, TOL)
	assert_lt(result.x, 3.5 - HALF, "must leave a gap: the unflated box would touch the face.")


func test_a_larger_skin_leaves_a_larger_gap() -> void:
	_add_block(Vector3(4.0, 0.0, 0.0))
	var to: Vector3 = Vector3(6.0, 0.0, 0.0)
	var tight: Vector3 = await _sweep(_tuning(0.03), _single(), Basis.IDENTITY, Vector3.ZERO, to)
	var loose: Vector3 = await _sweep(_tuning(0.23), _single(), Basis.IDENTITY, Vector3.ZERO, to)
	assert_almost_eq(tight.x - loose.x, 0.2, TOL, "the gap grows by exactly the skin difference.")


func test_vertical_motion_stops_below_a_block_above() -> void:
	_add_block(Vector3(0.0, 3.0, 0.0))
	var skin: float = 0.03
	var result: Vector3 = await _sweep(
		_tuning(skin), _single(), Basis.IDENTITY, Vector3.ZERO, Vector3(0.0, 5.0, 0.0)
	)
	assert_almost_eq(result.y, 2.5 - HALF - skin, TOL, "the hover clamp's vertical motion just stops.")
	assert_almost_eq(result.x, 0.0, TOL)
	assert_almost_eq(result.z, 0.0, TOL)


func test_the_leading_box_of_a_multi_box_shape_decides_where_it_stops() -> void:
	_add_block(Vector3(4.0, 0.0, 0.0))
	var centres: Array[Vector3] = [Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)]
	var result: Vector3 = await _sweep(
		_tuning(), centres, Basis.IDENTITY, Vector3.ZERO, Vector3(6.0, 0.0, 0.0)
	)
	assert_almost_eq(result.x, 3.5 - HALF - 0.03 - 1.0, TOL, "the box at +1 m reaches the block first.")


func test_the_basis_rotates_the_box_centres() -> void:
	_add_block(Vector3(4.0, 0.0, 0.0))
	var centres: Array[Vector3] = [Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)]
	var quarter_turn: Basis = Basis(Vector3.UP, PI * 0.5)
	var result: Vector3 = await _sweep(
		_tuning(), centres, quarter_turn, Vector3.ZERO, Vector3(6.0, 0.0, 0.0)
	)
	# Turned a quarter, the pair lies along Z, so both boxes lead with the same x edge.
	assert_almost_eq(result.x, 3.5 - HALF - 0.03, TOL, "rotated centres no longer reach out along X.")


# --- Slide: full motion, then X-only, then Z-only --------------------------

func test_diagonal_motion_into_an_x_wall_slides_along_z() -> void:
	_add_block(Vector3(4.0, 0.0, 0.0), Vector3(1.0, 1.0, 20.0))
	var result: Vector3 = await _sweep(
		_tuning(), _single(), Basis.IDENTITY, Vector3.ZERO, Vector3(6.0, 0.0, 3.0)
	)
	assert_almost_eq(result.x, 3.5 - HALF - 0.03, TOL, "x stops at the wall.")
	assert_almost_eq(result.z, 3.0, TOL, "z keeps going: the Z-only remainder is free.")


func test_diagonal_motion_into_a_z_wall_slides_along_x() -> void:
	_add_block(Vector3(0.0, 0.0, 4.0), Vector3(20.0, 1.0, 1.0))
	var result: Vector3 = await _sweep(
		_tuning(), _single(), Basis.IDENTITY, Vector3.ZERO, Vector3(3.0, 0.0, 6.0)
	)
	assert_almost_eq(result.z, 3.5 - HALF - 0.03, TOL, "z stops at the wall.")
	assert_almost_eq(result.x, 3.0, TOL, "x keeps going: the X-only remainder is free.")


func test_diagonal_motion_into_a_corner_stops_on_both_axes() -> void:
	_add_block(Vector3(4.0, 0.0, 0.0), Vector3(1.0, 1.0, 20.0))
	_add_block(Vector3(0.0, 0.0, 4.0), Vector3(20.0, 1.0, 1.0))
	var result: Vector3 = await _sweep(
		_tuning(), _single(), Basis.IDENTITY, Vector3.ZERO, Vector3(6.0, 0.0, 6.0)
	)
	assert_almost_eq(result.x, 3.5 - HALF - 0.03, TOL, "stopped on x.")
	assert_almost_eq(result.z, 3.5 - HALF - 0.03, TOL, "stopped on z.")


func test_straight_motion_into_a_wall_does_not_slide() -> void:
	_add_block(Vector3(4.0, 0.0, 0.0), Vector3(1.0, 1.0, 20.0))
	var result: Vector3 = await _sweep(
		_tuning(), _single(), Basis.IDENTITY, Vector3.ZERO, Vector3(6.0, 0.0, 0.0)
	)
	assert_almost_eq(result.z, 0.0, TOL, "no Z component was asked for, none appears.")


# --- Already embedded ------------------------------------------------------

func test_a_box_that_starts_inside_a_block_gets_the_full_motion() -> void:
	_add_block(Vector3(0.0, 0.0, 0.0), Vector3(1.0, 3.0, 1.0))
	var to: Vector3 = Vector3(0.0, 2.0, 0.0)
	var result: Vector3 = await _sweep(_tuning(), _single(), Basis.IDENTITY, Vector3(0.0, 0.2, 0.0), to)
	assert_true(
		result.is_equal_approx(to),
		"embedded in a block: the way out is the requested motion, not frozen at the start, got %s." % result
	)


# --- Non-block colliders and the probe bound -------------------------------

func test_a_non_block_collider_does_not_stop_the_sweep() -> void:
	_add_static(Vector3(4.0, 0.0, 0.0))
	var to: Vector3 = Vector3(6.0, 0.0, 0.0)
	var result: Vector3 = await _sweep(_tuning(), _single(), Basis.IDENTITY, Vector3.ZERO, to)
	assert_true(result.is_equal_approx(to), "only placed blocks block the ghost, got %s." % result)


func test_a_block_behind_non_block_colliders_still_stops_the_sweep() -> void:
	_add_static(Vector3(2.0, 0.0, 0.0))
	_add_static(Vector3(3.0, 0.0, 0.0))
	_add_block(Vector3(5.0, 0.0, 0.0))
	var result: Vector3 = await _sweep(
		_tuning(0.03, 8), _single(), Basis.IDENTITY, Vector3.ZERO, Vector3(8.0, 0.0, 0.0)
	)
	assert_almost_eq(result.x, 4.5 - HALF - 0.03, TOL, "the block behind two props is still found.")


func test_probe_budget_comes_from_tuning() -> void:
	_add_static(Vector3(2.0, 0.0, 0.0))
	_add_static(Vector3(3.0, 0.0, 0.0))
	var to: Vector3 = Vector3(6.0, 0.0, 0.0)
	var generous: Vector3 = await _sweep(_tuning(0.03, 8), _single(), Basis.IDENTITY, Vector3.ZERO, to)
	var stingy: Vector3 = await _sweep(_tuning(0.03, 1), _single(), Basis.IDENTITY, Vector3.ZERO, to)
	assert_true(generous.is_equal_approx(to), "a budget of 8 skips both props, got %s." % generous)
	assert_almost_eq(stingy.x, 0.0, TOL, "a budget of 1 cannot skip two props, so the cast gives up.")
