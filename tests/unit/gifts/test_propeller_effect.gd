extends GutTest
## PropellerEffect (spec 1.6): the Anvil in reverse, activated in
## place (no carrier). The effect triggers at once and spawns a PropellerStand that runs
## DiscForce.apply(sign -1) every tick for `disc_force.duration_s` on the host and only
## draws on a client. Tilt is compared with an Anvil at the same point on a real Field.

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
	Match._net_provider = null
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
	assert_not_null(def, "config/gifts/specials/propeller.tres must be found by id")
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
	var stand: PropellerStand = stands[0] as PropellerStand
	stand.bind_to_match = false  # no live match in this unit test
	stand.tick(0.1)
	assert_eq(field.call_count, 1, "the host stand runs the blow")
	assert_eq(_registry.tracked_block_count(), 0, "no carrier registered")
	assert_eq(_blocks_root.get_child_count(), 0, "no carrier in the blocks root")


# --- the stand: rise, blow, sink ---------------------------------------------

func test_stand_tilts_away_from_its_own_disk_position() -> void:
	var field: SpyField = _register_spy_field()
	var effect: PropellerEffect = PropellerEffect.new()
	var stand: PropellerStand = _stand(field, effect, Vector3(3.0, 0.0, 4.0))  # local (3, 4)
	stand.tick(0.1)
	assert_eq(field.call_count, 1)
	assert_almost_eq(field.last_magnitude, effect.disc_force.strength * 5.0 * 0.1, 0.0001, "strength * distance * delta")
	assert_almost_eq(field.last_direction.x, -0.6, 0.001)
	assert_almost_eq(field.last_direction.y, -0.8, 0.001)


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
