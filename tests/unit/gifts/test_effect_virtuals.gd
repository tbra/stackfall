extends GutTest
## The per-effect virtuals of SpecialEffect, asked through every shipped SpecialDef (no
## fabricated defs): upward aiming, launch facing, the stored launch direction, the effect
## radius and the client visual each effect builds.

const ROCKET_ID: StringName = &"rocket"
const PAINTBALL_ID: StringName = &"paintball"
const MAGNET_ID: StringName = &"magnet"
const FX_POINT: Vector3 = Vector3(1.5, 0.5, -1.0)
const MAP_RADIUS_M: float = 6.0
const OWNER_SLOT: int = 0
const BASIS_EPS: float = 0.0001

const FORWARD: Vector3 = Vector3(0.0, 0.0, -1.0)
const FORWARD_UP: Vector3 = Vector3(0.0, 0.5, -1.0)
const FORWARD_DOWN: Vector3 = Vector3(0.0, -0.5, -1.0)
const STRAIGHT_UP: Vector3 = Vector3.UP
const THROW_VELOCITY: Vector3 = Vector3(2.0, 3.0, -4.0)

## Ids whose effect draws something on a client, with the node it adds.
const CLIENT_FX_ID_COUNT: int = 7

var _previous_context: MatchContext = null
var _context: FakeMatchContext = null
var _field: Field = null
var _blocks_parent: Node3D = null


func before_each() -> void:
	_previous_context = MatchContext.installed()
	_field = autofree(Field.new())
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_effect_virtuals"
	map_def.field_radius = MAP_RADIUS_M
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	_field.map_def = map_def
	add_child_autofree(_field)
	_blocks_parent = autofree(Node3D.new())
	add_child_autofree(_blocks_parent)
	var slot: PlayerSlot = PlayerSlot.new()
	slot.color = Color.RED
	_context = FakeMatchContext.new()
	_context.has_authority_value = false
	_context.net_is_client_value = true
	_context.field_value = _field
	_context.blocks_parent_value = _blocks_parent
	_context.slot_count_value = 1
	_context.slot_by_id = {OWNER_SLOT: slot}
	MatchContext.install(_context)


func after_each() -> void:
	MatchContext.install(_previous_context)


func _effect_of(def: SpecialDef) -> SpecialEffect:
	return def.effect as SpecialEffect


func _all_defs() -> Array[SpecialDef]:
	var defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	assert_gt(defs.size(), 0, "the shipped roster is not empty")
	return defs


func _carrier() -> Block:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	block.owner_slot = OWNER_SLOT
	return block


func _descendant_count(root: Node) -> int:
	var count: int = 0
	for child: Node in root.get_children():
		count += 1 + _descendant_count(child)
	return count


func _first_of(root: Node, script_class: Script) -> Node:
	for child: Node in root.get_children():
		if child.get_script() == script_class:
			return child
		var deeper: Node = _first_of(child, script_class)
		if deeper != null:
			return deeper
	return null


## -- may_aim_upward --------------------------------------------------------------------

func test_only_the_rocket_may_aim_upward() -> void:
	for def: SpecialDef in _all_defs():
		assert_eq(_effect_of(def).may_aim_upward(), def.id == ROCKET_ID, "may_aim_upward for %s" % def.id)


## -- faces_launch / launch_facing ------------------------------------------------------

func _expected_faces(id: StringName, mode: GiftThrow.Mode, aim: Vector3, velocity: Vector3) -> bool:
	if id == ROCKET_ID:
		return mode == GiftThrow.Mode.AIMED and aim.is_finite() and aim.length() > 0.001
	if id == PAINTBALL_ID:
		return mode == GiftThrow.Mode.AIMED and aim != STRAIGHT_UP and aim != Vector3.ZERO
	if id == MAGNET_ID:
		return mode == GiftThrow.Mode.THROW and velocity.length() > 0.0
	return false


func test_faces_launch_per_effect_mode_and_aim() -> void:
	var aims: Array[Vector3] = [FORWARD, FORWARD_UP, FORWARD_DOWN, STRAIGHT_UP, Vector3.ZERO]
	var velocities: Array[Vector3] = [Vector3.ZERO, THROW_VELOCITY]
	var modes: Array[GiftThrow.Mode] = [GiftThrow.Mode.NONE, GiftThrow.Mode.THROW, GiftThrow.Mode.AIMED]
	for def: SpecialDef in _all_defs():
		for mode: GiftThrow.Mode in modes:
			for aim: Vector3 in aims:
				for velocity: Vector3 in velocities:
					assert_eq(
						_effect_of(def).faces_launch(mode, aim, velocity),
						_expected_faces(def.id, mode, aim, velocity),
						"faces_launch %s mode %d aim %s velocity %s" % [def.id, mode, aim, velocity])


func test_rocket_faces_an_upward_and_a_straight_up_aim() -> void:
	var rocket: SpecialEffect = _effect_of(SpecialDef.find_by_id(ROCKET_ID))
	assert_true(rocket.faces_launch(GiftThrow.Mode.AIMED, FORWARD_UP, Vector3.ZERO))
	assert_true(rocket.faces_launch(GiftThrow.Mode.AIMED, STRAIGHT_UP, Vector3.ZERO))
	assert_false(rocket.faces_launch(GiftThrow.Mode.AIMED, Vector3.ZERO, Vector3.ZERO), "a degenerate aim keeps the drop pose")
	assert_false(rocket.faces_launch(GiftThrow.Mode.AIMED, Vector3(INF, 0.0, 0.0), Vector3.ZERO), "a non-finite aim keeps the drop pose")


func test_paintball_does_not_face_a_straight_up_aim() -> void:
	var paintball: SpecialEffect = _effect_of(SpecialDef.find_by_id(PAINTBALL_ID))
	assert_false(paintball.faces_launch(GiftThrow.Mode.AIMED, STRAIGHT_UP, Vector3.ZERO))
	assert_true(paintball.faces_launch(GiftThrow.Mode.AIMED, FORWARD_DOWN, Vector3.ZERO))
	assert_true(paintball.faces_launch(GiftThrow.Mode.AIMED, FORWARD, Vector3.ZERO))


func test_rocket_launch_facing_noses_along_the_aim_even_upward() -> void:
	var effect: RocketEffect = SpecialDef.find_by_id(ROCKET_ID).effect as RocketEffect
	for aim: Vector3 in [FORWARD, FORWARD_UP, STRAIGHT_UP]:
		var basis: Basis = effect.launch_facing(GiftThrow.Mode.AIMED, aim, Vector3.ZERO)
		var expected: Basis = FlightFacing.nose_basis(effect.model_nose_axis, aim.normalized())
		assert_true(basis.is_equal_approx(expected), "rocket nose follows aim %s" % aim)
		assert_almost_eq((basis * effect.model_nose_axis).normalized(), aim.normalized(), Vector3.ONE * BASIS_EPS)


func test_paintball_launch_facing_drops_the_upward_part_and_stays_upright() -> void:
	var effect: PaintballEffect = SpecialDef.find_by_id(PAINTBALL_ID).effect as PaintballEffect
	var basis: Basis = effect.launch_facing(GiftThrow.Mode.AIMED, FORWARD_UP, Vector3.ZERO)
	var expected: Basis = FlightFacing.upright_nose_basis(effect.model_nose_axis, FORWARD)
	assert_true(basis.is_equal_approx(expected))
	assert_true(effect.launch_facing(GiftThrow.Mode.AIMED, FORWARD_DOWN, Vector3.ZERO).is_equal_approx(
		FlightFacing.upright_nose_basis(effect.model_nose_axis, FORWARD_DOWN.normalized())))


func test_magnet_launch_facing_noses_along_the_throw_velocity() -> void:
	var effect: MagnetEffect = SpecialDef.find_by_id(MAGNET_ID).effect as MagnetEffect
	var basis: Basis = effect.launch_facing(GiftThrow.Mode.THROW, Vector3.ZERO, THROW_VELOCITY)
	assert_true(basis.is_equal_approx(FlightFacing.nose_basis(effect.model_nose_axis, THROW_VELOCITY)))


## -- apply_launch ------------------------------------------------------------------------

func test_rocket_apply_launch_stores_the_normalised_direction_upward_included() -> void:
	var effect: SpecialEffect = _effect_of(SpecialDef.find_by_id(ROCKET_ID))
	var block: Block = _carrier()

	effect.apply_launch(block, FORWARD_UP * 3.0)

	assert_true(block.has_meta(RocketEffect.LAUNCH_DIRECTION_META))
	assert_almost_eq(block.get_meta(RocketEffect.LAUNCH_DIRECTION_META, Vector3.ZERO) as Vector3, FORWARD_UP.normalized(), Vector3.ONE * BASIS_EPS)


func test_rocket_apply_launch_refuses_a_degenerate_or_non_finite_direction() -> void:
	var effect: SpecialEffect = _effect_of(SpecialDef.find_by_id(ROCKET_ID))
	var block: Block = _carrier()
	effect.apply_launch(block, Vector3.ZERO)
	effect.apply_launch(block, Vector3(NAN, 0.0, 1.0))
	assert_false(block.has_meta(RocketEffect.LAUNCH_DIRECTION_META))


func test_paintball_apply_launch_stores_the_direction_without_its_upward_part() -> void:
	var effect: SpecialEffect = _effect_of(SpecialDef.find_by_id(PAINTBALL_ID))
	var block: Block = _carrier()

	effect.apply_launch(block, FORWARD_UP * 2.0)

	assert_true(block.has_meta(PaintballEffect.LAUNCH_DIRECTION_META))
	assert_almost_eq(block.get_meta(PaintballEffect.LAUNCH_DIRECTION_META, Vector3.ZERO) as Vector3, FORWARD, Vector3.ONE * BASIS_EPS)


func test_paintball_apply_launch_refuses_a_straight_up_direction() -> void:
	var effect: SpecialEffect = _effect_of(SpecialDef.find_by_id(PAINTBALL_ID))
	var block: Block = _carrier()
	effect.apply_launch(block, STRAIGHT_UP)
	assert_false(block.has_meta(PaintballEffect.LAUNCH_DIRECTION_META))


func test_every_other_effect_leaves_the_block_untouched_on_apply_launch() -> void:
	for def: SpecialDef in _all_defs():
		if def.id == ROCKET_ID or def.id == PAINTBALL_ID:
			continue
		var block: Block = _carrier()
		_effect_of(def).apply_launch(block, FORWARD_DOWN)
		assert_eq(block.get_meta_list().size(), 0, "apply_launch of %s stores nothing" % def.id)


## -- effect_radius_m ---------------------------------------------------------------------

## The property scan BotController used before the virtual existed.
func _scanned_radius_m(def: SpecialDef) -> float:
	if def == null or def.effect == null:
		return 0.0
	for property: String in ["base_radius_m", "hole_radius_m", "splash_radius_m", "radius_m"]:
		var value: Variant = def.effect.get(property)
		if value is float and float(value) > 0.0:
			return float(value)
	var blast: ExplosionTuning = def.effect.get("blast") as ExplosionTuning
	return blast.radius_m if blast != null else 0.0


func test_effect_radius_matches_the_property_scan_for_every_shipped_def() -> void:
	for def: SpecialDef in _all_defs():
		assert_almost_eq(_effect_of(def).effect_radius_m(), _scanned_radius_m(def), 0.00001, "effect_radius_m of %s" % def.id)


func test_the_explosive_and_area_effects_report_a_positive_radius() -> void:
	for id: StringName in [&"bomb", ROCKET_ID]:
		assert_gt(_effect_of(SpecialDef.find_by_id(id)).effect_radius_m(), 0.0, "%s has a blast radius" % id)


## -- build_client_fx ---------------------------------------------------------------------

func _expected_fx_class(id: StringName) -> Script:
	match id:
		&"paintball":
			return PaintballSplash
		&"black_hole":
			return BlackHoleVisual
		&"bomb", &"rocket":
			return CartoonBlast
		&"volcano":
			return VolcanoStructure
		&"propeller":
			return PropellerStand
		&"freeze":
			return FreezeBurst
	return null


func test_build_client_fx_adds_the_expected_node_for_the_seven_visual_effects() -> void:
	var drawn: int = 0
	for def: SpecialDef in _all_defs():
		var expected: Script = _expected_fx_class(def.id)
		if expected == null:
			continue
		var carrier: Block = _carrier()
		_effect_of(def).build_client_fx(_context, carrier, FX_POINT, OWNER_SLOT)
		var found: Node = _first_of(_field, expected)
		if found == null:
			found = _first_of(_blocks_parent, expected)
		assert_not_null(found, "%s draws its client visual" % def.id)
		if found != null:
			drawn += 1
			found.free()
	assert_eq(drawn, CLIENT_FX_ID_COUNT)


func test_build_client_fx_adds_nothing_for_the_other_effects() -> void:
	var carrier: Block = _carrier()
	var before: int = _descendant_count(_field) + _descendant_count(_blocks_parent)
	for def: SpecialDef in _all_defs():
		if _expected_fx_class(def.id) != null:
			continue
		_effect_of(def).build_client_fx(_context, carrier, FX_POINT, OWNER_SLOT)
		assert_eq(_descendant_count(_field) + _descendant_count(_blocks_parent), before, "%s adds no client node" % def.id)


func test_build_client_fx_tolerates_a_missing_carrier() -> void:
	for def: SpecialDef in _all_defs():
		_effect_of(def).build_client_fx(_context, null, FX_POINT, OWNER_SLOT)
	pass_test("no effect needs the carrier on a client")
