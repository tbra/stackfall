extends GutTest
## PropellerEffect (spec 2.6; Bontago-1pi.85.45): the Anvil in reverse, activated in
## place (no carrier). The effect triggers at once and spawns a PropellerStand that runs
## DiscForce.apply(sign -1) every tick for `disc_force.duration_s` on the host and only
## draws on a client. Tilt is compared with an Anvil at the same point on a real Field.

const TICK: float = 1.0 / 60.0
const COMPARE_DISTANCE_M: float = 3.0
const COMPARE_SECONDS: float = 8.0
const MIN_PEAK_RATIO: float = 0.5
const MAX_PEAK_RATIO: float = 2.0
const HEIGHT_EPSILON_M: float = 0.0001


## Records what reaches Field.apply_tilt_impulse(). With `passthrough` the real
## spring still integrates it (physics tests).
class SpyField:
	extends Field
	var call_count: int = 0
	var last_direction: Vector2 = Vector2.ZERO
	var last_magnitude: float = 0.0
	var passthrough: bool = false

	func apply_tilt_impulse(direction: Vector2, magnitude: float) -> void:
		call_count += 1
		last_direction = direction
		last_magnitude = magnitude
		if passthrough:
			super.apply_tilt_impulse(direction, magnitude)


func _small_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_propeller"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	return map_def


var _blocks_root: Node3D = null
var _registry: BlockRegistry = null


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	MatchTestReset.clear_world()


func _register_field(field: Field) -> void:
	field.map_def = _small_map()
	add_child_autofree(field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(field, _registry, _blocks_root)


func _register_spy_field(passthrough: bool = false) -> SpyField:
	var field: SpyField = autofree(SpyField.new())
	field.passthrough = passthrough
	_register_field(field)
	return field


func _load_propeller_def() -> SpecialDef:
	var def: SpecialDef = SpecialDef.find_by_id(&"propeller")
	assert_not_null(def, "config/specials/propeller.tres must be found by id")
	return def


## A stand at a world point of the registered field; ticks are driven by the test.
func _stand(field: Field, effect: PropellerEffect, world_position: Vector3, physics: bool = true) -> PropellerStand:
	var stand: PropellerStand = PropellerStand.new()
	stand.configure(effect, physics)
	field.add_child(stand)
	stand.global_position = world_position
	return stand


# --- in place: no carrier, instant trigger -----------------------------------

func test_propeller_activates_in_place_and_triggers_at_once() -> void:
	var def: SpecialDef = _load_propeller_def()
	var effect: PropellerEffect = def.effect as PropellerEffect
	assert_true(def.activates_in_place)
	assert_eq(def.arm_delay, 0.0)
	assert_false(effect.needs_landing(), "no carrier to wait for")
	assert_true(effect.detaches())
	assert_true(effect.wants_early_trigger(null, null))
	assert_almost_eq(effect.effect_lifetime_s(), effect.disc_force.duration_s, HEIGHT_EPSILON_M)


func test_detonate_spawns_one_host_stand_with_no_carrier_in_the_registry() -> void:
	var field: SpyField = _register_spy_field()
	var effect: PropellerEffect = _load_propeller_def().effect as PropellerEffect
	var anchor: Block = autofree(Block.new())
	add_child_autofree(anchor)
	anchor.global_position = Vector3(3.0, 0.0, 4.0)
	effect.detonate(anchor, null, 0)
	var stands: Array[Node] = field.find_children("*", "PropellerStand", true, false)
	assert_eq(stands.size(), 1)
	assert_true((stands[0] as PropellerStand).has_force(), "the host stand runs the blow")
	assert_eq(_registry.tracked_block_count(), 0, "no carrier registered")
	assert_eq(_blocks_root.get_child_count(), 0, "no carrier in the blocks root")


# --- the stand: rise, blow, sink ---------------------------------------------

func test_stand_rises_from_below_the_surface_spins_then_sinks() -> void:
	var field: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	var stand: PropellerStand = _stand(field, effect, Vector3(3.0, 0.0, 4.0))
	assert_almost_eq(stand.height_at(0.0), -effect.start_depth_m, HEIGHT_EPSILON_M, "starts hidden below the surface")
	assert_lt(stand.visual().position.y, 0.0)
	assert_almost_eq(stand.height_at(effect.emerge_s), effect.emerge_height_m, HEIGHT_EPSILON_M, "risen")
	assert_almost_eq(stand.height_at(effect.disc_force.duration_s * 0.5), effect.emerge_height_m, HEIGHT_EPSILON_M, "holds while blowing")
	assert_almost_eq(stand.height_at(effect.disc_force.duration_s), -effect.start_depth_m, HEIGHT_EPSILON_M, "sunk at the end")
	assert_gt(stand.height_at(effect.emerge_s * 0.5), -effect.start_depth_m, "rising")
	assert_lt(stand.height_at(effect.emerge_s * 0.5), effect.emerge_height_m)


func test_stand_tilts_away_from_its_own_disk_position() -> void:
	var field: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	var stand: PropellerStand = _stand(field, effect, Vector3(3.0, 0.0, 4.0))  # local (3, 4)
	stand.tick(0.1)
	assert_eq(field.call_count, 1)
	assert_almost_eq(field.last_magnitude, effect.disc_force.strength * 5.0 * 0.1, 0.0001, "strength * distance * delta")
	assert_almost_eq(field.last_direction.x, -0.6, 0.001)
	assert_almost_eq(field.last_direction.y, -0.8, 0.001)


func test_no_tilt_impulse_at_the_exact_centre() -> void:
	var field: SpyField = _register_spy_field()
	var stand: PropellerStand = _stand(field, PropellerEffect.new(), Vector3.ZERO)
	stand.tick(0.1)
	assert_eq(field.call_count, 0, "no side to name at the exact centre")


func test_tilt_fires_every_tick_for_the_window_then_the_stand_frees_itself() -> void:
	var field: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	effect.disc_force.duration_s = 1.0
	var stand: PropellerStand = _stand(field, effect, Vector3(3.0, 0.0, 4.0))
	for _i: int in range(3):
		stand.tick(0.25)
	assert_eq(field.call_count, 3)
	assert_false(stand.is_queued_for_deletion())
	stand.tick(0.25)
	assert_true(stand.is_queued_for_deletion(), "freed when duration_s has elapsed")
	var calls: int = field.call_count
	stand.tick(0.25)
	assert_eq(field.call_count, calls, "no more blow after the window")


func test_client_stand_is_visual_only() -> void:
	var field: SpyField = _register_spy_field()
	var stand: PropellerStand = _stand(field, PropellerEffect.new(), Vector3(3.0, 0.0, 4.0), false)
	stand.tick(0.1)
	assert_eq(field.call_count, 0, "a client never tilts the disc")
	assert_false(stand.has_force())


func test_client_build_is_null_on_the_host_and_a_visual_off_it() -> void:
	var field: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	var point: Vector3 = Vector3(3.0, 0.0, 4.0)
	assert_null(PropellerStand.build_client_visual(effect, point), "the host's own stand already draws it")
	var net: FakeNet = FakeNet.new()
	net.is_host_value = false
	net.is_client_value = true
	net.is_offline_value = false
	Match.set_net_provider(net)
	var stand: PropellerStand = PropellerStand.build_client_visual(effect, point)
	assert_not_null(stand)
	if stand != null:
		assert_false(stand.has_force())
		assert_eq(stand.get_parent(), field)


func test_stand_frees_itself_when_the_match_is_not_live() -> void:
	var field: SpyField = _register_spy_field()
	var stand: PropellerStand = _stand(field, PropellerEffect.new(), Vector3(3.0, 0.0, 4.0))
	stand.bind_to_match = true
	stand.tick(0.1)
	assert_true(stand.is_queued_for_deletion())
	assert_eq(field.call_count, 0)


# --- propeller.tres ------------------------------------------------------------

func test_propeller_tres_loads_with_expected_id_and_effect() -> void:
	var found: SpecialDef = _load_propeller_def()
	assert_true(found.effect is PropellerEffect)
	var effect: PropellerEffect = found.effect as PropellerEffect
	assert_gt(effect.disc_force.duration_s, 0.0)
	assert_gt(effect.emerge_height_m, 0.0)
	assert_gt(effect.emerge_s, 0.0)
	assert_gt(effect.sink_s, 0.0)
	assert_lt(effect.emerge_s + effect.sink_s, effect.disc_force.duration_s, "rise and sink fit the window")


## The real Field's own tilt-disabled guard is enough.
func test_respects_tilt_mode_off_via_the_real_field_guard() -> void:
	var field: Field = autofree(Field.new())
	_register_field(field)
	var stand: PropellerStand = _stand(field, PropellerEffect.new(), Vector3(3.0, 0.0, 4.0))
	stand.tick(0.1)
	field._update_tilt(TICK)
	assert_eq(field.tilt_vector(), Vector2.ZERO, "tilt_mode OFF must leave the disk untouched")


func test_impact_never_triggers_it() -> void:
	assert_false(PropellerEffect.new().impact_triggers(null, null), "the impact veto stands (Bontago-1en.22)")


# --- acceptance: real Field, compared with an Anvil ---------------------------

## Peak |tilt| of a real Field and the tilt vector at that peak: one Anvil
## detonate, or the Propeller stand ticking over its whole window at the same point.
func _real_field_tilt(use_anvil: bool) -> Dictionary:
	var field: Field = autofree(Field.new())
	_register_field(field)
	field.set_tilt_enabled(true)
	var point: Vector3 = field.world_from_disk_local(Vector2(COMPARE_DISTANCE_M, 0.0), 0.0)
	var propeller: PropellerEffect = _load_propeller_def().effect as PropellerEffect
	var stand: PropellerStand = _stand(field, propeller, point)
	if use_anvil:
		var block: Block = autofree(Block.new())
		add_child_autofree(block)
		block.global_position = point
		AnvilEffect.new().detonate(block, null, 0)
	var peak: float = 0.0
	var peak_tilt: Vector2 = Vector2.ZERO
	for _tick: int in range(int(COMPARE_SECONDS / TICK)):
		if not use_anvil and not stand.is_queued_for_deletion():
			stand.tick(TICK)
		field._update_tilt(TICK)
		if field.tilt_vector().length() > peak:
			peak = field.tilt_vector().length()
			peak_tilt = field.tilt_vector()
	return {"peak": peak, "tilt": peak_tilt}


func test_propeller_tilts_opposite_to_an_anvil_at_the_same_point() -> void:
	var anvil: Dictionary = _real_field_tilt(true)
	Match.abort_match()
	MatchTestReset.clear_world()
	var prop: Dictionary = _real_field_tilt(false)
	var anvil_tilt: Vector2 = anvil["tilt"] as Vector2
	var prop_tilt: Vector2 = prop["tilt"] as Vector2
	assert_gt(float(anvil["peak"]), 0.0, "fixture: the anvil tilted the disc")
	assert_lt(anvil_tilt.normalized().dot(prop_tilt.normalized()), -0.9, "opposite tilt")
	var ratio: float = float(prop["peak"]) / float(anvil["peak"])
	assert_gt(ratio, MIN_PEAK_RATIO, "propeller peak tilt comparable to the anvil's (ratio %f)" % ratio)
	assert_lt(ratio, MAX_PEAK_RATIO, "propeller peak tilt comparable to the anvil's (ratio %f)" % ratio)
