extends GutTest
## The Propeller gift party balloon (PropellerStand + BalloonRig): the state sequence
## inflate -> rise -> hold -> pop, the team colour, the confetti count from config, and the
## in-place net id that carries the owner slot to clients.

const EPSILON: float = 0.0001
const TEAM_COLOR: Color = Color(0.1, 0.8, 0.3, 1.0)


func _effect() -> PropellerEffect:
	return SpecialDef.find_by_id(&"propeller").effect as PropellerEffect


func _stand(effect: PropellerEffect) -> PropellerStand:
	var stand: PropellerStand = PropellerStand.new()
	stand.configure(effect, false, -1)
	add_child_autofree(stand)
	return stand


func test_phases_run_inflate_rise_hold_popped() -> void:
	var effect: PropellerEffect = _effect()
	var stand: PropellerStand = _stand(effect)
	assert_eq(stand.phase_at(0.0), PropellerStand.Phase.INFLATE)
	assert_eq(stand.phase_at(effect.inflate_s * 0.5), PropellerStand.Phase.INFLATE)
	assert_eq(stand.phase_at(effect.inflate_s + effect.rise_s * 0.5), PropellerStand.Phase.RISE)
	assert_eq(stand.phase_at(effect.inflate_s + effect.rise_s + 0.1), PropellerStand.Phase.HOLD)
	assert_eq(stand.phase_at(effect.disc_force.duration_s), PropellerStand.Phase.POPPED)


func test_height_is_zero_while_inflating_then_reaches_the_string_length() -> void:
	var effect: PropellerEffect = _effect()
	var stand: PropellerStand = _stand(effect)
	assert_almost_eq(stand.height_at(effect.inflate_s * 0.9), 0.0, EPSILON)
	assert_almost_eq(stand.height_at(effect.inflate_s + effect.rise_s), effect.string_length_m, EPSILON)
	assert_gt(stand.height_at(effect.inflate_s + effect.rise_s * 0.5), 0.0)
	assert_lt(stand.height_at(effect.inflate_s + effect.rise_s * 0.5), effect.string_length_m)
	assert_almost_eq(stand.inflate_at(effect.inflate_s), 1.0, EPSILON)


func test_rig_inflates_overshoots_and_settles() -> void:
	var effect: PropellerEffect = _effect()
	var rig: BalloonRig = BalloonRig.new()
	add_child_autofree(rig)
	rig.setup(effect.fx, TEAM_COLOR)
	assert_false(rig._body.visible, "nothing before inflating")
	rig.pose(0.0, 0.5, 0.0, 0.0)
	assert_true(rig._body.visible)
	rig.pose(0.0, 0.5, 0.0, 0.0)
	var mid: float = rig._body.scale.x
	assert_gt(mid, 0.5, "past half size mid-inflate (overshoot curve)")
	rig.pose(0.0, 1.0, 0.0, 0.0)
	assert_almost_eq(rig._body.scale.x, 1.0, EPSILON, "settles at full size")


func test_pop_spawns_the_configured_confetti_and_frees_the_rig() -> void:
	var effect: PropellerEffect = _effect()
	var rig: BalloonRig = BalloonRig.new()
	add_child_autofree(rig)
	rig.setup(effect.fx, TEAM_COLOR)
	rig.pose(effect.string_length_m, 1.0, 1.0, 0.0)
	rig.begin_pop()
	assert_true(rig._popped)
	assert_false(rig._body.visible, "the balloon is gone")
	rig.advance(0.01)
	assert_eq(_live_shards(rig), effect.fx.confetti_count)
	rig.begin_pop()
	assert_eq(_live_shards(rig), effect.fx.confetti_count, "begin_pop is idempotent")
	rig.advance(maxf(effect.fx.confetti_life_s, effect.fx.rag_fall_s) + 1.0)
	assert_true(rig.is_queued_for_deletion(), "frees itself after the pop")


func test_stand_hands_the_rig_to_the_field_to_pop_at_expiry() -> void:
	var effect: PropellerEffect = _effect()
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	var stand: PropellerStand = PropellerStand.new()
	stand.configure(effect, false, -1)
	parent.add_child(stand)
	var rig: BalloonRig = stand._rig
	assert_not_null(rig)
	stand.tick(effect.disc_force.duration_s + 0.01)
	assert_true(stand.is_queued_for_deletion())
	assert_true(rig._popped, "popped at the end of the blow")
	assert_eq(rig.get_parent(), parent, "the pop plays on under the field, not the freed stand")


func test_team_colour_is_applied_to_the_balloon() -> void:
	var effect: PropellerEffect = _effect()
	var rig: BalloonRig = BalloonRig.new()
	add_child_autofree(rig)
	rig.setup(effect.fx, TEAM_COLOR)
	var body: Node3D = rig.find_child("Body", true, false) as Node3D
	var latex: MeshInstance3D = body.get_child(0) as MeshInstance3D
	var material: ShaderMaterial = latex.material_override as ShaderMaterial
	assert_eq(material.get_shader_parameter(&"albedo_color"), TEAM_COLOR)


func test_in_place_net_id_carries_the_owner_slot() -> void:
	assert_eq(SpecialIds.in_place_net_id(0), SpecialIds.IN_PLACE_NET_ID, "slot 0 is the plain sentinel")
	for slot_id: int in range(8):
		assert_eq(SpecialIds.in_place_slot(SpecialIds.in_place_net_id(slot_id)), slot_id)
	assert_eq(SpecialIds.in_place_slot(5), -1, "an ordinary block net id is not in place")


func test_presenter_slot_and_seed_differ_per_spawn() -> void:
	var net_id: int = SpecialIds.in_place_net_id(3)
	assert_eq(SpecialIds.in_place_slot(net_id), 3, "slot > 0 reaches the presenter as that slot")
	assert_ne(SpecialIds.in_place_net_id(3), SpecialIds.in_place_net_id(0))
	assert_ne(PropellerStand.seed_for(Vector3(1.0, 0.0, 2.0)), PropellerStand.seed_for(Vector3(-4.0, 0.0, 3.0)), "different drop points seed differently")
	var effect: PropellerEffect = _effect()
	var stand: PropellerStand = PropellerStand.new()
	stand.configure(effect, false, 3, 12345)
	add_child_autofree(stand)
	assert_eq(stand._rig._rng.seed, 12345, "the rig takes the spawn seed")


func _live_shards(rig: BalloonRig) -> int:
	var live: int = 0
	for shard: MeshInstance3D in rig._shards:
		if is_instance_valid(shard) and shard.visible:
			live += 1
	return live
