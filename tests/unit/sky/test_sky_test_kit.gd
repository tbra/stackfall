extends GutTest
## tests/support/SkyTestKit.gd (SKY-15a): the shared set-up helpers, and its sky/cloud helpers.

const NIGHT_LOCK: float = 0.75
## More than three radii of the shipped puff (about 17 m).
const ASIDE_M: float = 60.0


func test_cycle_loads_a_fresh_sky_cycle_def() -> void:
	var first: SkyCycleDef = SkyTestKit.cycle()
	assert_not_null(first, "shipped sky_cycle.tres loads as SkyCycleDef")
	first.cycle_locked_phase_night = 0.1
	assert_ne(SkyTestKit.cycle().cycle_locked_phase_night, 0.1, "each call is a fresh load, safe to edit")


func test_storm_overlay_loads() -> void:
	assert_not_null(SkyTestKit.storm_overlay(), "shipped storm_overlay.tres loads as SkyOverlayDef")


func test_golden_is_a_non_empty_dictionary() -> void:
	var golden: Dictionary = SkyTestKit.golden()
	assert_false(golden.is_empty(), "the golden fixture parses to a non-empty Dictionary")
	assert_true(golden.has("states"), "the golden carries its state table")


func test_locked_phase_night_is_the_shipped_night_lock() -> void:
	assert_eq(SkyTestKit.locked_phase("night"), NIGHT_LOCK, "night locks at the shipped night phase")


func test_locked_phase_unknown_id_is_minus_one() -> void:
	assert_eq(SkyTestKit.locked_phase("no_such_sky"), -1.0, "an unknown sky id has no locked phase")


func test_make_skybox_is_added_to_parent_on_the_shipped_cycle() -> void:
	var parent: Node = add_child_autofree(Node.new())
	var skybox: Skybox = SkyTestKit.make_skybox(parent)
	assert_eq(skybox.get_parent(), parent, "the skybox is added to the given parent")
	assert_not_null(skybox.sky_def, "the skybox carries a cycle")
	assert_not_null(skybox.config, "the skybox carries its own config")


func _skybox_with_environment(parent: Node) -> Skybox:
	var skybox: Skybox = SkyTestKit.make_skybox(parent)
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	skybox.environment = environment
	return skybox


func _single_puff_sea() -> CloudSea:
	var def: SkyCycleDef = SkyTestKit.cycle()
	def.cloud_clump_count = 1
	def.cloud_bank_count = 0
	def.proc_far_count = 0
	def.cloud_puffs_per_clump = 1
	def.cloud_drift_speed_min_mps = 0.0
	def.cloud_drift_speed_max_mps = 0.0
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure_cycle(def, null, 1.0, 1)
	return sea


func test_sky_material_is_the_material_installed_on_the_sky() -> void:
	var parent: Node = add_child_autofree(Node.new())
	var skybox: Skybox = _skybox_with_environment(parent)
	skybox.start_cycle(NIGHT_LOCK)
	var material: ShaderMaterial = SkyTestKit.sky_material(skybox)
	assert_not_null(material, "a started cycle binds the dome material")
	assert_same(material, skybox.environment.sky.sky_material, "it is the material installed on the sky")


func test_sky_material_is_null_without_an_environment() -> void:
	var skybox: Skybox = Skybox.new()
	autofree(skybox)
	assert_null(SkyTestKit.sky_material(skybox), "no environment, no dome material")


func test_puff_material_is_shared_by_the_sea_and_upper_layers() -> void:
	var parent: Node = add_child_autofree(Node.new())
	var empty: CloudSea = CloudSea.new()
	parent.add_child(empty)
	assert_null(SkyTestKit.puff_material(empty), "an unbuilt sea has no puff material")
	var skybox: Skybox = _skybox_with_environment(parent)
	skybox.start_cycle(NIGHT_LOCK)
	var sea: CloudSea = skybox.get_node("CloudSea") as CloudSea
	var material: ShaderMaterial = SkyTestKit.puff_material(sea)
	assert_not_null(material, "a built sea draws with a puff material")
	var seen: int = 0
	for child: Node in sea.get_children():
		if child is MultiMeshInstance3D and not child.is_queued_for_deletion():
			seen += 1
			assert_same((child as MultiMeshInstance3D).material_override, material, "%s shares it" % child.name)
	assert_gt(seen, 1, "the sea and upper layers both exist")


func test_puff_centre_is_the_occlusion_centre() -> void:
	var sea: CloudSea = _single_puff_sea()
	var centre: Vector3 = SkyTestKit.puff_centre(sea)
	var through: float = sea.sun_ray_cloud_occlusion(centre - Vector3(500.0, 0.0, 0.0), Vector3.RIGHT, null, Vector2.ZERO)
	assert_gt(through, 0.99, "a ray through the centre is hidden")
	var aside: float = sea.sun_ray_cloud_occlusion(centre + Vector3(-500.0, 0.0, ASIDE_M), Vector3.RIGHT, null, Vector2.ZERO)
	assert_eq(aside, 0.0, "a ray 3 radii aside is clear")


func test_run_to_clock_moves_a_running_cycle_to_the_clock_phase() -> void:
	var parent: Node = add_child_autofree(Node.new())
	var skybox: Skybox = _skybox_with_environment(parent)
	skybox.start_cycle()
	var context: FakeMatchContext = FakeMatchContext.new()
	var previous: MatchContext = MatchContext.installed()
	MatchContext.install(context)
	var length: float = skybox.sky_def.cycle_length_seconds
	SkyTestKit.run_to_clock(skybox, context, length * 0.25)
	var first: float = skybox.current_cycle_phase()
	SkyTestKit.run_to_clock(skybox, context, length * 0.5)
	var second: float = skybox.current_cycle_phase()
	MatchContext.install(previous)
	assert_ne(first, second, "a later clock gives a later phase")
	assert_almost_eq(fposmod(second - first, 1.0), 0.25, 0.01, "a quarter cycle of clock is a quarter of phase")


func test_run_to_clock_leaves_a_locked_sky_where_it_is() -> void:
	var parent: Node = add_child_autofree(Node.new())
	var skybox: Skybox = _skybox_with_environment(parent)
	skybox.start_cycle(NIGHT_LOCK)
	var context: FakeMatchContext = FakeMatchContext.new()
	var previous: MatchContext = MatchContext.installed()
	MatchContext.install(context)
	SkyTestKit.run_to_clock(skybox, context, skybox.sky_def.cycle_length_seconds * 0.4)
	MatchContext.install(previous)
	assert_almost_eq(skybox.current_cycle_phase(), NIGHT_LOCK, 0.0001, "a locked sky ignores the clock")


func test_settle_makes_a_queued_storm_visible_in_the_dome() -> void:
	var parent: Node = add_child_autofree(Node.new())
	var skybox: Skybox = _skybox_with_environment(parent)
	skybox.start_cycle(NIGHT_LOCK)
	SkyTestKit.settle(skybox)
	var material: ShaderMaterial = SkyTestKit.sky_material(skybox)
	var before: Dictionary = _dome_params(material)
	skybox.set_storm_sky(1.0, SkyTestKit.storm_overlay())
	assert_eq(_dome_params(material), before, "a queued storm is not yet in the dome")
	SkyTestKit.settle(skybox)
	assert_ne(_dome_params(material), before, "settle flushes it into the dome material")


func _dome_params(material: ShaderMaterial) -> Dictionary:
	var out: Dictionary = {}
	for property: Dictionary in material.shader.get_shader_uniform_list():
		var name: StringName = property[&"name"] as StringName
		out[name] = material.get_shader_parameter(name)
	return out
