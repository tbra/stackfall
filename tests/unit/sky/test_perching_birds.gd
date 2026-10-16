extends GutTest
## game/ambient/PerchingBirds.gd + game/ambient/Fireflies.gd -- landing, flee
## triggers, tower perching, block-moved takeoff, theme gating and stable node
## counts over repeated theme switches.

const SUNSET_PATH: String = "res://config/sky/themes/sunset.tres"
const NIGHT_PATH: String = "res://config/sky/themes/night.tres"
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


## The birds currently in the scene (flying in, perched or fleeing): the manager's PerchingBird children.
func _birds(manager: PerchingBirds) -> Array[PerchingBird]:
	var result: Array[PerchingBird] = []
	for child: Node in manager.get_children():
		if child is PerchingBird:
			result.append(child as PerchingBird)
	return result


func _run_until_perched(manager: PerchingBirds) -> PerchingBird:
	for _i: int in range(MAX_STEPS):
		manager._process(STEP_S)
		for bird: PerchingBird in _birds(manager):
			if bird.state == PerchingBird.State.PERCHED:
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
	# PerchPlanner.is_on_disc probes the margin ring at EDGE_PROBES fixed
	# angles, so a spot between two probes may sit up to margin*(1-cos(pi/probes)) closer
	# to the rim than the nominal margin (the landing spot is random per run).
	var probe_gap_m: float = life.perch_edge_margin_m * (1.0 - cos(PI / float(PerchPlanner.EDGE_PROBES)))
	assert_lte(Vector2(spot.x, spot.z).length(), 30.0 - life.perch_edge_margin_m + probe_gap_m + 0.01)
	assert_almost_eq(bird.global_position.y, spot.y + bird.perch_height(), 0.001, "stands on the surface")


func test_flees_when_the_camera_comes_close() -> void:
	_manager = _make_manager(_life())
	var bird: PerchingBird = _run_until_perched(_manager)
	assert_not_null(bird)
	if bird == null:
		return
	_manager.camera_override = bird.global_position + Vector3(0.0, 4.0, 4.0)
	_force_poll(_manager)
	assert_eq(bird.state, PerchingBird.State.FLEE)


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
	assert_almost_eq(bird.perch_surface, Vector3(10.0, 1.0, 10.0), Vector3.ONE * 0.001)
	_manager._process(0.01)
	assert_eq(bird.state, PerchingBird.State.PERCHED)
	tower.global_position += Vector3(0.4, 0.0, 0.0)
	_manager._process(0.01)
	assert_eq(bird.state, PerchingBird.State.FLEE, "the block moved under it")


func test_match_state_change_clears_birds() -> void:
	_manager = _make_manager(_life(2))
	for _i: int in range(20):
		_manager._process(STEP_S)
	assert_gt(_birds(_manager).size(), 0)
	Events.match_state_changed.emit(Match.State.PLAYING, Match.State.END)
	assert_eq(_birds(_manager).size(), 0)
	assert_eq(_manager.get_child_count(), 0)


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
	assert_true((skybox.get_node("PerchingBirds") as PerchingBirds).visible)
	assert_null(skybox.get_node("Fireflies").get_node_or_null("Motes"))
	skybox.apply_theme(night)
	assert_false((skybox.get_node("PerchingBirds") as PerchingBirds).visible)
	assert_not_null(skybox.get_node("Fireflies").get_node_or_null("Motes"))
	assert_eq((skybox.get_node("Fireflies").get_node_or_null("Motes") as MultiMeshInstance3D).multimesh.instance_count, night.ambient_life.fireflies_count)


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
	assert_ne(bird.state, PerchingBird.State.PERCHED, "bird leaves its freed block")


# --- Flocks ------------------------------------------------------------

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
	for bird: PerchingBird in _birds(manager):
		if bird.state == PerchingBird.State.PERCHED:
			result.append(bird)
	return result


func _states(manager: PerchingBirds) -> Array[PerchingBird.State]:
	var result: Array[PerchingBird.State] = []
	for bird: PerchingBird in _birds(manager):
		result.append(bird.state)
	return result


func _all_fleeing(manager: PerchingBirds) -> bool:
	for state: PerchingBird.State in _states(manager):
		if state != PerchingBird.State.FLEE:
			return false
	return true


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

