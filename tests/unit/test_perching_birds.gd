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
