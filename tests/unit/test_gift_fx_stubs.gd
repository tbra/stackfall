extends GutTest
## Stub verification: every A0 interface signature is callable and returns
## the correct type. This tests only interface existence and no-op safety,
## not implementation behavior (that is tested per-package in A1-A2).


func test_explosion_fx_blast_signature() -> void:
	# ExplosionFx.blast(space, center, tuning, exclude) -> Array[RigidBody3D]
	var tuning: ExplosionTuning = ExplosionTuning.new()
	var result: Array[RigidBody3D] = ExplosionFx.blast(null, Vector3.ZERO, tuning, [])
	assert_eq(result.size(), 0, "ExplosionFx.blast stub must return empty array")


func test_explosion_fx_chain_signature() -> void:
	# ExplosionFx.chain(behavior, center, radius, depth) -> void
	ExplosionFx.chain(null, Vector3.ZERO, 5.0, 0)
	pass_test("ExplosionFx.chain callable")


func test_disc_force_apply_signature() -> void:
	# DiscForce.apply(field, world_pos, sign, tuning, delta) -> void
	var tuning: DiscForceTuning = DiscForceTuning.new()
	DiscForce.apply(null, Vector3.ZERO, 1.0, tuning, 0.016)
	pass_test("DiscForce.apply callable")


func test_disc_force_shake_signature() -> void:
	# DiscForce.shake(field, tuning, elapsed, delta) -> void
	var tuning: DiscForceTuning = DiscForceTuning.new()
	DiscForce.shake(null, tuning, 0.0, 0.016)
	pass_test("DiscForce.shake callable")


func test_hole_punch_punch_signature() -> void:
	# HolePunch.punch(world_pos, radius_m, open_s) -> bool
	var result: bool = HolePunch.punch(Vector3.ZERO, 1.0, 2.5)
	assert_false(result, "HolePunch.punch stub must return false")


func test_radial_pull_pull_signature() -> void:
	# RadialPull.pull(space, center, tuning, exclude, filter, delta, on_captured) -> Array[RigidBody3D]
	var tuning: RadialPullTuning = RadialPullTuning.new()
	var filter: Callable = func(_body: RigidBody3D) -> bool: return true
	var result: Array[RigidBody3D] = RadialPull.pull(null, Vector3.ZERO, tuning, [], filter, 0.016)
	assert_eq(result.size(), 0, "RadialPull.pull stub must return empty array")


func test_block_spawner_spawn_signature() -> void:
	# BlockSpawner.spawn(shape, world_origin, basis, owner_slot, velocity, cap) -> Block
	var shape: BlockShape = BlockShape.new()
	var result: Block = BlockSpawner.spawn(shape, Vector3.ZERO, Basis.IDENTITY, 0, Vector3.ZERO, 100)
	assert_null(result, "BlockSpawner.spawn stub must return null")


func test_landed_probe_creation() -> void:
	# LandedProbe is a RefCounted with update() and has_landed() methods
	var probe: LandedProbe = LandedProbe.new()
	assert_is(probe, LandedProbe, "LandedProbe must be instantiable")


func test_landed_probe_update_signature() -> void:
	# func update(block: Block, delta: float) -> void
	var probe: LandedProbe = LandedProbe.new()
	probe.update(null, 0.016)
	pass_test("LandedProbe.update callable")


func test_landed_probe_has_landed_signature() -> void:
	# func has_landed() -> bool
	var probe: LandedProbe = LandedProbe.new()
	var result: bool = probe.has_landed()
	assert_false(result, "LandedProbe.has_landed stub must return false")


func test_landed_probe_landed_age_signature() -> void:
	# func landed_age() -> float
	var probe: LandedProbe = LandedProbe.new()
	var result: float = probe.landed_age()
	assert_eq(result, 0.0, "LandedProbe.landed_age stub must return 0.0")


func test_gift_blink_apply_signature() -> void:
	# GiftBlink.apply(block, period_s, duration_s) -> void
	GiftBlink.apply(null, 0.25, 3.0)
	pass_test("GiftBlink.apply callable")


func test_gift_fx_presenter_creation() -> void:
	# GiftFxPresenter is a Node
	var presenter: GiftFxPresenter = GiftFxPresenter.new()
	assert_is(presenter, Node, "GiftFxPresenter must be a Node")
