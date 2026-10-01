extends GutTest
## Bontago-adt.3: vfx/PerchingBirds.gd + vfx/Fireflies.gd -- landing, flee
## triggers, tower perching, block-moved takeoff, theme gating and stable node
## counts over repeated theme switches.

const SUNSET_PATH: String = "res://config/sky_themes/sunset.tres"
const NIGHT_PATH: String = "res://config/sky_themes/night.tres"
const STEP_S: float = 0.1
const MAX_STEPS: int = 600
const FAR_CAMERA: Vector3 = Vector3(0.0, 60.0, 400.0)

var _manager: PerchingBirds = null


func _life(count: int = 1) -> AmbientLifeConfig:
	var life: AmbientLifeConfig = AmbientLifeConfig.new()
	life.perch_bird_count = count
	life.spawn_delay_min_s = 0.0
	life.spawn_delay_max_s = 0.0
	life.approach_circle_time_min_s = 0.0
	life.approach_circle_time_max_s = 0.0
	life.approach_circle_radius_min_m = 50.0
	life.approach_circle_radius_max_m = 50.0
	life.perch_stay_min_s = 500.0
	life.perch_stay_max_s = 600.0
	life.perch_tower_fraction = 0.0
	life.perch_tower_min_settle_s = 0.0
	life.idle_hop_chance = 0.0
	return life


func _make_manager(life: AmbientLifeConfig) -> PerchingBirds:
	var manager: PerchingBirds = PerchingBirds.new()
	manager.disc_radius = 30.0
	manager.camera_override = FAR_CAMERA
	add_child_autofree(manager)
	manager.configure(life, true)
	return manager


func _run_until_perched(manager: PerchingBirds, index: int = 0) -> PerchingBird:
	for _i: int in range(MAX_STEPS):
		manager._process(STEP_S)
		var bird: PerchingBird = manager.bird_at(index)
		if bird != null and bird.is_perched():
			return bird
	return null


func _make_block(at: Vector3, size: Vector3 = Vector3.ONE) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.freeze = true
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)
	add_child_autofree(body)
	body.global_position = at
	return body


func _force_poll(manager: PerchingBirds) -> void:
	manager._poll_left = 0.0
	manager._process(0.0)


func test_lands_on_the_disc_away_from_players_and_edge() -> void:
	var life: AmbientLifeConfig = _life()
	_manager = _make_manager(life)
	_manager.home_points = PackedVector3Array([Vector3(12.0, 0.0, 0.0), Vector3(-12.0, 0.0, 0.0)])
	_manager.goal_points = PackedVector3Array([Vector3.ZERO])
	var bird: PerchingBird = _run_until_perched(_manager)
	assert_not_null(bird, "the bird glides in and lands")
	if bird == null:
		return
	var spot: Vector3 = bird.perch_surface
	for home: Vector3 in _manager.home_points:
		assert_gte(Vector2(spot.x - home.x, spot.z - home.z).length(), life.perch_min_player_distance_m - 0.01)
	assert_gte(Vector2(spot.x, spot.z).length(), life.perch_min_goal_distance_m - 0.01)
	assert_lte(Vector2(spot.x, spot.z).length(), 30.0 - life.perch_edge_margin_m + 0.01)
	assert_false(_manager.perched_on_tower(0))
	assert_almost_eq(bird.global_position.y, spot.y + bird.perch_height(), 0.001, "stands on the surface")


func test_perching_birds_are_drawn_at_the_configured_scale() -> void:
	var life: AmbientLifeConfig = _life()
	assert_gte(life.perch_bird_scale, 1.4, "owner 2026-09-30: birds are ~1.4-1.6x")
	assert_lte(life.perch_bird_scale, 1.6)
	_manager = _make_manager(life)
	var bird: PerchingBird = _run_until_perched(_manager)
	assert_not_null(bird)
	if bird == null:
		return
	assert_gte(bird.length_m, life.perch_bird_length_min_m * life.perch_bird_scale - 0.0001)
	assert_lte(bird.length_m, life.perch_bird_length_max_m * life.perch_bird_scale + 0.0001)


func test_flees_when_the_camera_comes_close() -> void:
	_manager = _make_manager(_life())
	var bird: PerchingBird = _run_until_perched(_manager)
	assert_not_null(bird)
	if bird == null:
		return
	_manager.camera_override = bird.global_position + Vector3(0.0, 4.0, 4.0)
	_force_poll(_manager)
	assert_eq(bird.state, PerchingBird.State.FLEE)


func test_flees_when_a_cursor_comes_close_and_ignores_a_far_one() -> void:
	_manager = _make_manager(_life())
	var bird: PerchingBird = _run_until_perched(_manager)
	assert_not_null(bird)
	if bird == null:
		return
	Events.remote_cursor_updated.emit(3, bird.global_position + Vector3(40.0, 0.0, 0.0), 0, Quaternion.IDENTITY)
	_force_poll(_manager)
	assert_eq(bird.state, PerchingBird.State.PERCHED, "a far cursor does not scare it")
	Events.remote_cursor_updated.emit(3, bird.global_position + Vector3(2.0, 1.0, 0.0), 0, Quaternion.IDENTITY)
	_force_poll(_manager)
	assert_eq(bird.state, PerchingBird.State.FLEE)


func test_flees_on_a_nearby_impact_only() -> void:
	_manager = _make_manager(_life())
	var bird: PerchingBird = _run_until_perched(_manager)
	assert_not_null(bird)
	if bird == null:
		return
	Events.block_impacted_at.emit(6.0, bird.global_position + Vector3(60.0, 0.0, 0.0))
	assert_eq(bird.state, PerchingBird.State.PERCHED)
	Events.block_impacted_at.emit(6.0, bird.global_position + Vector3(5.0, 0.0, 0.0))
	assert_eq(bird.state, PerchingBird.State.FLEE)


func test_flees_when_a_block_is_overhead() -> void:
	_manager = _make_manager(_life())
	var bird: PerchingBird = _run_until_perched(_manager)
	assert_not_null(bird)
	if bird == null:
		return
	var block: RigidBody3D = _make_block(bird.global_position + Vector3(0.5, 6.0, 0.0))
	_manager.blocks = [block]
	_force_poll(_manager)
	assert_eq(bird.state, PerchingBird.State.FLEE)


func test_flees_when_a_new_block_lands_nearby() -> void:
	var life: AmbientLifeConfig = _life()
	_manager = _make_manager(life)
	var bird: PerchingBird = _run_until_perched(_manager)
	assert_not_null(bird)
	if bird == null:
		return
	var block: RigidBody3D = _make_block(bird.global_position + Vector3(3.0, 0.0, 0.0))
	_manager.blocks = [block]
	_force_poll(_manager)
	assert_eq(bird.state, PerchingBird.State.FLEE, "a block that just appeared is unsettled and close")


func test_lands_on_top_of_a_settled_block_and_leaves_when_it_moves() -> void:
	var life: AmbientLifeConfig = _life()
	life.perch_tower_fraction = 1.0
	_manager = _make_manager(life)
	var tower: RigidBody3D = _make_block(Vector3(10.0, 0.5, 10.0))
	_manager.blocks = [tower]
	# The block must have been seen once for its settle clock to exist.
	_force_poll(_manager)
	var bird: PerchingBird = _run_until_perched(_manager)
	assert_not_null(bird)
	if bird == null:
		return
	assert_true(_manager.perched_on_tower(0), "tower fraction 1.0 prefers the block top")
	assert_almost_eq(bird.perch_surface, Vector3(10.0, 1.0, 10.0), Vector3.ONE * 0.001)
	_manager._process(0.01)
	assert_eq(bird.state, PerchingBird.State.PERCHED)
	tower.global_position += Vector3(0.4, 0.0, 0.0)
	_manager._process(0.01)
	assert_eq(bird.state, PerchingBird.State.FLEE, "the block moved under it")


func test_leaves_when_its_block_is_removed() -> void:
	var life: AmbientLifeConfig = _life()
	life.perch_tower_fraction = 1.0
	_manager = _make_manager(life)
	var tower: RigidBody3D = _make_block(Vector3(-10.0, 0.5, 8.0))
	_manager.blocks = [tower]
	_force_poll(_manager)
	var bird: PerchingBird = _run_until_perched(_manager)
	assert_not_null(bird)
	if bird == null:
		return
	assert_true(_manager.perched_on_tower(0))
	tower.free()
	_manager._process(0.01)
	assert_eq(bird.state, PerchingBird.State.FLEE)


func test_tower_needs_settle_time_and_a_clear_top() -> void:
	var life: AmbientLifeConfig = _life()
	life.perch_tower_fraction = 1.0
	life.perch_tower_min_settle_s = 5.0
	_manager = _make_manager(life)
	var lower: RigidBody3D = _make_block(Vector3(10.0, 0.5, 10.0))
	var upper: RigidBody3D = _make_block(Vector3(10.0, 1.5, 10.0))
	_manager.blocks = [lower, upper]
	_force_poll(_manager)
	_manager._build_hazards(PackedVector3Array(), null, false)
	assert_true(_manager.pick_tower_spot().is_empty(), "nothing has been still for 5 s yet")
	_manager._clock += 6.0
	_manager._build_hazards(PackedVector3Array(), null, false)
	var pick: Dictionary = _manager.pick_tower_spot()
	assert_false(pick.is_empty())
	if pick.is_empty():
		return
	assert_eq(pick["block"], upper, "only the top block face is free; the lower one has a block on it")
	assert_almost_eq(pick["surface"] as Vector3, Vector3(10.0, 2.0, 10.0), Vector3.ONE * 0.001)


func test_tower_spot_respects_player_distance() -> void:
	_manager = _make_manager(_life())
	var tower: RigidBody3D = _make_block(Vector3(10.0, 0.5, 10.0))
	_manager.blocks = [tower]
	_force_poll(_manager)
	_manager._clock += 10.0
	_manager._build_hazards(PackedVector3Array([Vector3(10.0, 0.0, 12.0)]), null, false)
	assert_true(_manager.pick_tower_spot().is_empty(), "a cursor within the player distance rules the block out")


func test_configure_never_duplicates_birds() -> void:
	var life: AmbientLifeConfig = _life(3)
	_manager = _make_manager(life)
	for _i: int in range(60):
		_manager._process(STEP_S)
	assert_gt(_manager.get_child_count(), 0)
	for _round: int in range(5):
		_manager.configure(life, true)
		assert_eq(_manager.get_child_count(), 0, "reconfigure frees every bird immediately")
		for _i: int in range(60):
			_manager._process(STEP_S)
		assert_lte(_manager.get_child_count(), life.perch_bird_count)
	_manager.configure(life, false)
	assert_eq(_manager.get_child_count(), 0)
	assert_false(_manager.visible)
	_manager.configure(null, true)
	assert_false(_manager.is_enabled())


func test_match_state_change_clears_birds() -> void:
	_manager = _make_manager(_life(2))
	for _i: int in range(20):
		_manager._process(STEP_S)
	assert_gt(_manager.active_bird_count(), 0)
	Events.match_state_changed.emit(Match.State.PLAYING, Match.State.END)
	assert_eq(_manager.active_bird_count(), 0)
	assert_eq(_manager.get_child_count(), 0)


func test_a_fleeing_bird_leaves_and_is_removed() -> void:
	var life: AmbientLifeConfig = _life()
	life.despawn_distance_m = 60.0
	life.spawn_delay_min_s = 500.0
	life.spawn_delay_max_s = 600.0
	_manager = _make_manager(life)
	_manager.spawn_now(0)
	var bird: PerchingBird = _run_until_perched(_manager)
	assert_not_null(bird)
	if bird == null:
		return
	Events.block_impacted_at.emit(6.0, bird.global_position + Vector3(2.0, 0.0, 0.0))
	for _i: int in range(600):
		_manager._process(STEP_S)
		if _manager.bird_at(0) == null:
			break
	assert_null(_manager.bird_at(0), "the escaped bird was removed and its replacement is waiting")
	assert_eq(_manager.get_child_count(), 0)


# --- Theme gating (game/Skybox.gd) ---------------------------------------------------

func _make_skybox() -> Skybox:
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment: Environment = Environment.new()
	environment.sky = sky
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = load(SUNSET_PATH) as SkyThemeDef
	add_child_autofree(skybox)
	return skybox


func test_birds_are_sunset_only_and_fireflies_night_only() -> void:
	var skybox: Skybox = _make_skybox()
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var night: SkyThemeDef = load(NIGHT_PATH) as SkyThemeDef
	assert_not_null(sunset.ambient_life)
	assert_not_null(night.ambient_life)
	skybox.apply_theme(sunset)
	assert_true(skybox.get_perching_birds().is_enabled())
	assert_null(skybox.get_fireflies().mote_instance())
	skybox.apply_theme(night)
	assert_false(skybox.get_perching_birds().is_enabled())
	assert_not_null(skybox.get_fireflies().mote_instance())
	assert_eq(skybox.get_fireflies().mote_instance().multimesh.instance_count, night.ambient_life.fireflies_count)


func test_node_counts_stay_stable_over_repeated_theme_switches() -> void:
	var skybox: Skybox = _make_skybox()
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var night: SkyThemeDef = load(NIGHT_PATH) as SkyThemeDef
	skybox.apply_theme(sunset)
	var baseline_children: int = skybox.get_child_count()
	for _round: int in range(6):
		skybox.apply_theme(night)
		assert_eq(skybox.get_child_count(), baseline_children)
		assert_eq(skybox.get_fireflies().get_child_count(), 1, "exactly one mote instance")
		assert_eq(skybox.get_perching_birds().get_child_count(), 0)
		skybox.apply_theme(sunset)
		assert_eq(skybox.get_child_count(), baseline_children)
		assert_eq(skybox.get_fireflies().get_child_count(), 0)
		for _i: int in range(30):
			skybox.get_perching_birds()._process(STEP_S)
		assert_lte(skybox.get_perching_birds().get_child_count(), sunset.ambient_life.perch_bird_count)


func test_low_preset_disables_ambient_life() -> void:
	var skybox: Skybox = _make_skybox()
	var low: GraphicsPreset = load("res://config/graphics_presets/low.tres") as GraphicsPreset
	var high: GraphicsPreset = load("res://config/graphics_presets/high.tres") as GraphicsPreset
	assert_false(low.ambient_life_enabled)
	assert_true(high.ambient_life_enabled)
	var night: SkyThemeDef = load(NIGHT_PATH) as SkyThemeDef
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	skybox._apply_ambient_life(low, night)
	assert_null(skybox.get_fireflies().mote_instance())
	skybox._apply_ambient_life(low, sunset)
	assert_false(skybox.get_perching_birds().is_enabled())
	skybox._apply_ambient_life(high, night)
	assert_not_null(skybox.get_fireflies().mote_instance())


func test_freed_block_never_reaches_typed_calls_during_polls() -> void:
	var life: AmbientLifeConfig = _life()
	life.perch_tower_fraction = 1.0
	_manager = _make_manager(life)
	var tower: RigidBody3D = _make_block(Vector3(-10.0, 0.5, 8.0))
	var other: RigidBody3D = _make_block(Vector3(10.0, 0.5, -8.0))
	_manager.blocks = [tower, other]
	_force_poll(_manager)
	var bird: PerchingBird = _run_until_perched(_manager)
	assert_not_null(bird)
	if bird == null:
		return
	tower.free()
	other.free()
	_manager._refresh_sources()
	assert_eq(_manager.blocks.size(), 0, "freed blocks are pruned")
	_force_poll(_manager)
	assert_eq(_manager._block_positions(tower).size(), 0)
	assert_ne(bird.state, PerchingBird.State.PERCHED, "bird leaves its freed block")


# --- Flocks (Bontago-6fc.3) ------------------------------------------------------------

func _flock_life(cap: int, size_min: int, size_max: int) -> AmbientLifeConfig:
	var life: AmbientLifeConfig = _life(cap)
	life.flock_size_min = size_min
	life.flock_size_max = size_max
	life.flock_count_max = 1
	life.flock_social_interval_min_s = 1000.0
	life.flock_social_interval_max_s = 1000.0
	return life


## Steps until `count` birds are perched; returns how many are.
func _run_until_n_perched(manager: PerchingBirds, count: int) -> int:
	var perched: int = 0
	for _i: int in range(MAX_STEPS * 3):
		manager._process(STEP_S)
		perched = _perched_birds(manager).size()
		if perched >= count:
			break
	return perched


func _perched_birds(manager: PerchingBirds) -> Array[PerchingBird]:
	var result: Array[PerchingBird] = []
	for index: int in range(manager.slot_count()):
		var bird: PerchingBird = manager.bird_at(index)
		if bird != null and bird.is_perched():
			result.append(bird)
	return result


func _states(manager: PerchingBirds) -> Array[PerchingBird.State]:
	var result: Array[PerchingBird.State] = []
	for index: int in range(manager.slot_count()):
		var bird: PerchingBird = manager.bird_at(index)
		if bird != null:
			result.append(bird.state)
	return result


func _all_fleeing(manager: PerchingBirds) -> bool:
	for state: PerchingBird.State in _states(manager):
		if state != PerchingBird.State.FLEE:
			return false
	return true


func test_flock_size_stays_within_the_configured_range() -> void:
	var seen: Dictionary = {}
	for _round: int in range(24):
		var manager: PerchingBirds = _make_manager(_flock_life(12, 2, 4))
		manager._process(0.0)
		var size: int = manager.flock_slot_indices(0).size()
		assert_between(size, 2, 4, "flock size within flock_size_min..max")
		seen[size] = true
		manager.free()
	assert_gt(seen.size(), 1, "the size varies between flocks")


func test_flock_members_perch_near_each_other() -> void:
	var life: AmbientLifeConfig = _flock_life(6, 6, 6)
	_manager = _make_manager(life)
	var perched: int = _run_until_n_perched(_manager, 6)
	assert_eq(perched, 6, "all six members land")
	var birds: Array[PerchingBird] = _perched_birds(_manager)
	for first: PerchingBird in birds:
		for second: PerchingBird in birds:
			if first == second:
				continue
			var gap: float = Vector2(first.perch_surface.x - second.perch_surface.x, first.perch_surface.z - second.perch_surface.z).length()
			assert_lte(gap, life.flock_perch_radius_m * 2.0 + 0.01, "within one flock radius of the anchor")
			assert_gte(gap, life.flock_member_spacing_m - 0.01, "members keep their spacing")


func test_flock_members_share_a_block_top() -> void:
	var life: AmbientLifeConfig = _flock_life(4, 4, 4)
	life.perch_tower_fraction = 1.0
	_manager = _make_manager(life)
	var tower: RigidBody3D = _make_block(Vector3(10.0, 0.5, 10.0), Vector3(3.0, 1.0, 3.0))
	_manager.blocks = [tower]
	_force_poll(_manager)
	var perched: int = _run_until_n_perched(_manager, 3)
	assert_gte(perched, 3, "several members fit on the same top")
	for bird: PerchingBird in _perched_birds(_manager):
		assert_almost_eq(bird.perch_surface.y, 1.0, 0.001, "on the block top")
		assert_lte(Vector2(bird.perch_surface.x - 10.0, bird.perch_surface.z - 10.0).length(), 1.5 * 1.42)
	tower.free()
	for _i: int in range(8):
		_manager._process(STEP_S)
	assert_true(_all_fleeing(_manager), "the whole flock leaves when its block goes")


func test_group_takeoff_when_one_bird_is_spooked() -> void:
	var life: AmbientLifeConfig = _flock_life(5, 5, 5)
	life.flee_impact_radius_m = 0.2
	life.flock_takeoff_stagger_max_s = 0.45
	_manager = _make_manager(life)
	assert_eq(_run_until_n_perched(_manager, 5), 5)
	var victim: PerchingBird = _perched_birds(_manager)[0]
	Events.block_impacted_at.emit(6.0, victim.global_position)
	assert_eq(victim.state, PerchingBird.State.FLEE, "the spooked bird leaves at once")
	assert_false(_all_fleeing(_manager), "the others are staggered, not simultaneous")
	for _i: int in range(int(ceil(life.flock_takeoff_stagger_max_s / STEP_S)) + 3):
		_manager._process(STEP_S)
	assert_true(_all_fleeing(_manager), "the rest follow within the stagger window")


func test_flock_leaves_together_when_its_stay_ends() -> void:
	var life: AmbientLifeConfig = _flock_life(4, 4, 4)
	life.perch_stay_min_s = 6.0
	life.perch_stay_max_s = 6.0
	life.flock_landing_stagger_s = 0.3
	life.flock_arrival_stagger_s = 0.1
	life.spawn_delay_min_s = 900.0
	life.spawn_delay_max_s = 900.0
	_manager = _make_manager(life)
	_manager.spawn_now()
	assert_eq(_run_until_n_perched(_manager, 4), 4)
	var left: bool = false
	for _i: int in range(100):
		_manager._process(STEP_S)
		if _perched_birds(_manager).size() < 4:
			left = true
			break
	assert_true(left, "the flock takes off once its stay ends")
	for _i: int in range(int(ceil(life.flock_takeoff_stagger_max_s / STEP_S)) + 3):
		_manager._process(STEP_S)
	assert_true(_all_fleeing(_manager))


func test_total_bird_cap_is_respected() -> void:
	var life: AmbientLifeConfig = _flock_life(3, 6, 6)
	life.flock_count_max = 4
	life.perch_stay_min_s = 3.0
	life.perch_stay_max_s = 4.0
	life.despawn_distance_m = 70.0
	_manager = _make_manager(life)
	var peak: int = 0
	for _i: int in range(900):
		_manager._process(STEP_S)
		peak = maxi(peak, _manager.active_bird_count())
		assert_lte(_manager.get_child_count(), life.perch_bird_count, "never more birds than the cap")
	assert_eq(peak, 3, "the cap is reached but not exceeded")


func test_perched_flockmates_swap_perches() -> void:
	var life: AmbientLifeConfig = _flock_life(3, 3, 3)
	life.flock_swap_chance = 1.0
	life.flock_chase_chance = 0.0
	life.flock_social_interval_min_s = 0.5
	life.flock_social_interval_max_s = 0.5
	_manager = _make_manager(life)
	assert_eq(_run_until_n_perched(_manager, 3), 3)
	var flew: bool = false
	for _i: int in range(100):
		_manager._process(STEP_S)
		for state: PerchingBird.State in _states(_manager):
			flew = flew or state == PerchingBird.State.GLIDE
	assert_true(flew, "a swap is a short flight")
	assert_eq(_manager.active_bird_count(), 3, "nobody is lost")


func test_perched_flockmates_chase_and_come_back() -> void:
	var life: AmbientLifeConfig = _flock_life(2, 2, 2)
	life.flock_chase_chance = 1.0
	life.flock_swap_chance = 0.0
	life.flock_social_interval_min_s = 0.5
	life.flock_social_interval_max_s = 0.5
	_manager = _make_manager(life)
	assert_eq(_run_until_n_perched(_manager, 2), 2)
	var orbited: bool = false
	for _i: int in range(60):
		_manager._process(STEP_S)
		for state: PerchingBird.State in _states(_manager):
			orbited = orbited or state == PerchingBird.State.ORBIT
	assert_true(orbited, "the pair takes a short chase flight")
	assert_eq(_manager.active_bird_count(), 2, "both come back and keep perching")
