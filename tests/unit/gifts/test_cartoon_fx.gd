extends GutTest
## the cartoon gift effects (CartoonBlast, FreezeBurst, BeanHopFx,
## FxRing, FxEase). Visual-only nodes; these pin their lifecycles and the bean's
## hop/landing detection, not their look (see the probe screenshots on the bead).

const STEP_S: float = 1.0 / 60.0
const EXPLOSION_TUNING: GiftExplosionFxTuning = preload("res://config/gifts/specials/fx/gift_explosion_fx_tuning.tres")
const FREEZE_TUNING: FreezeFxTuning = preload("res://config/gifts/specials/fx/freeze_fx_tuning.tres")


func test_pop_overshoots_then_settles() -> void:
	assert_eq(FxEase.pop(-0.1, 0.2, 1.3), 0.0, "nothing before it starts")
	assert_almost_eq(FxEase.pop(0.2, 0.2, 1.3), 1.3, 0.001, "peak at pop_s")
	assert_almost_eq(FxEase.pop(0.3, 0.2, 1.3), 1.15, 0.001, "settling")
	assert_eq(FxEase.pop(0.5, 0.2, 1.3), 1.0, "settled")
	assert_eq(FxEase.shrink(0.1, 1.0, 0.5), 1.0)
	assert_almost_eq(FxEase.shrink(0.75, 1.0, 0.5), 0.75, 0.001)
	assert_eq(FxEase.shrink(1.0, 1.0, 0.5), 0.0)


func test_cartoon_blast_builds_its_layers_and_ends_after_its_duration() -> void:
	var blast: CartoonBlast = CartoonBlast.new()
	add_child_autofree(blast)
	blast.setup(EXPLOSION_TUNING, 8.0, 3)
	blast.set_process(false)
	assert_eq(blast.puff_count(), EXPLOSION_TUNING.puff_count)
	var meshes: int = 0
	for child: Node in blast.get_children():
		if child is MeshInstance3D:
			meshes += 1
	# puffs + debris + flash + ring + dust flipbook
	assert_eq(meshes, EXPLOSION_TUNING.puff_count + EXPLOSION_TUNING.debris_count + 3)
	assert_true(blast.advance(EXPLOSION_TUNING.duration_s * 0.5), "alive mid-way")
	assert_false(blast.advance(EXPLOSION_TUNING.duration_s), "done after its duration")


func test_cartoon_blast_frees_itself() -> void:
	var blast: CartoonBlast = CartoonBlast.new()
	add_child(blast)
	blast.setup(EXPLOSION_TUNING, 4.0)
	blast.advance(EXPLOSION_TUNING.duration_s)
	await wait_process_frames(3)
	assert_false(is_instance_valid(blast), "freed at the end")


func test_freeze_burst_grows_its_ring_to_the_freeze_radius() -> void:
	var burst: FreezeBurst = FreezeBurst.new()
	add_child_autofree(burst)
	burst.setup(FREEZE_TUNING, 6.0, 1)
	burst.set_process(false)
	assert_eq(burst.shard_count(), FREEZE_TUNING.shard_count)
	var ring: FxRing = null
	for child: Node in burst.get_children():
		if child is FxRing:
			ring = child as FxRing
	assert_not_null(ring)
	burst.advance(FREEZE_TUNING.ring_s * 0.999)
	assert_almost_eq(ring.scale.x, 6.0, 0.05, "ring reaches the freeze radius")
	assert_false(burst.advance(FREEZE_TUNING.duration_s), "done after its duration")


func test_fx_ring_plays_and_frees_itself() -> void:
	var ring: FxRing = FxRing.new()
	add_child(ring)
	ring.setup(Color.WHITE, 2.0, 0.3, 0.05)
	ring.play()
	await wait_seconds(0.2)
	assert_false(is_instance_valid(ring))


var _hop_events: int = 0


func _count_hop(_position: Vector3) -> void:
	_hop_events += 1


func before_each() -> void:
	_hop_events = 0
	if not Events.bean_hopped.is_connected(_count_hop):
		Events.bean_hopped.connect(_count_hop)


func after_each() -> void:
	if Events.bean_hopped.is_connected(_count_hop):
		Events.bean_hopped.disconnect(_count_hop)


func _bean_driver() -> BeanHopFx:
	var parent: Node3D = Node3D.new()
	add_child_autofree(parent)
	var bean: Block = Block.new()
	bean.gift_id = BeanHopFx.BEAN_ID
	parent.add_child(bean)
	assert_true(BeanHopFx.start_for_gift(bean))
	var driver: BeanHopFx = bean.get_node(NodePath(String(BeanHopFx.DRIVER_NAME))) as BeanHopFx
	driver.set_physics_process(false)
	return driver


func _rest(driver: BeanHopFx, y: float, ticks: int) -> void:
	for _i: int in range(ticks):
		driver.observe(y, STEP_S)


func test_bean_hop_after_rest_counts_and_spawns_a_ring() -> void:
	var driver: BeanHopFx = _bean_driver()
	_rest(driver, 0.0, driver.tuning.rest_ticks + 2)
	driver.observe(driver.tuning.takeoff_speed_mps * 2.0 * STEP_S, STEP_S)
	assert_eq(driver.hops, 1, "a take-off after resting is a hop")
	assert_eq(_hop_events, 1, "the hop is announced on Events.bean_hopped (the hop sound)")
	var rings: int = 0
	for child: Node in driver.get_parent().get_parent().get_children():
		if child is FxRing:
			rings += 1
	assert_eq(rings, 1, "the hop leaves a ring")


func test_bean_bounce_without_rest_is_not_a_hop_but_a_landing_is_seen() -> void:
	var driver: BeanHopFx = _bean_driver()
	var y: float = 10.0
	driver.observe(y, STEP_S)
	for _i: int in range(10):
		y -= driver.tuning.land_speed_mps * 2.0 * STEP_S
		driver.observe(y, STEP_S)
	# Bounce straight back up without resting.
	y += driver.tuning.takeoff_speed_mps * 2.0 * STEP_S
	driver.observe(y, STEP_S)
	assert_eq(driver.hops, 0, "a bounce is not a hop")
	for _i: int in range(10):
		y -= driver.tuning.land_speed_mps * 2.0 * STEP_S
		driver.observe(y, STEP_S)
	_rest(driver, y, 2)
	assert_eq(driver.landings, 1, "the stop after a fast fall is a landing")


func test_hop_driver_is_only_for_the_jumping_bean() -> void:
	var block: Block = autofree(Block.new())
	block.gift_id = &"bomb"
	assert_false(BeanHopFx.start_for_gift(block))
	assert_false(BeanHopFx.start_for_gift(null))
