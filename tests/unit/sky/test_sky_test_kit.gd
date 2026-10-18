extends GutTest
## tests/support/SkyTestKit.gd (SKY-15a): the shared set-up helpers, and Skybox.sky_material().

const NIGHT_LOCK: float = 0.75


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


func test_sky_material_is_the_dome_writers_material_after_a_cycle_starts() -> void:
	var parent: Node = add_child_autofree(Node.new())
	var skybox: Skybox = SkyTestKit.make_skybox(parent)
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	skybox.environment = environment
	skybox.start_cycle(NIGHT_LOCK)
	var material: ShaderMaterial = skybox.sky_material()
	assert_not_null(material, "a started cycle binds the dome material")
	assert_same(material, environment.sky.sky_material, "sky_material() is the material installed on the sky")
