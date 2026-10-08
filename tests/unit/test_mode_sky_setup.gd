extends GutTest
## Bontago-1pi.108: every mode that builds a world (hot-seat, sandbox, tutorial,
## and the gift demo / tower topple sandbox presets) must configure the Skybox for
## the config's theme / cycle, not leave it on the launch fallback sky.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")

var _main: Variant = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = MapDef.new()
	tiny_map.id = &"tiny_sky"
	tiny_map.field_radius = 12.0
	tiny_map.cell_size = 1.0
	var tiny_config: MatchConfig = (
		load("res://config/match_defaults.tres") as MatchConfig
	).duplicate(true)
	tiny_config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(tiny_config as TinyMapMatchConfig).set_tiny_map(tiny_map)
	tiny_config.rng_seed = 90210
	_main.match_config = tiny_config
	add_child_autofree(_main)


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame


func _assert_sky_configured(mode: String) -> void:
	var sky: Skybox = _main.get_node("Skybox") as Skybox
	assert_true(sky.is_cycle_active(), "%s: the Skybox must run the configured sky cycle" % mode)
	assert_ne(sky.theme, null, "%s: a theme is applied" % mode)
	# Bontago-1pi.127: the panorama (the launch fallback sky / textured set) is absent: the live
	# sky is the cycle's own procedural material and no textured face is drawn.
	assert_true(sky.theme.sky_look_procedural, "%s: procedural sky look" % mode)
	assert_eq(sky.environment.sky.sky_material, sky.theme.sky_material, "%s: the cycle's material is the live sky" % mode)
	assert_true(sky.fallback_active, "%s: no textured panorama set is loaded" % mode)
	for face: MeshInstance3D in sky._face_meshes.values():
		assert_false(face.visible, "%s: textured sky face %s hidden" % [mode, face.name])



func test_hot_seat_configures_sky() -> void:
	_main._start_hot_seat_match()
	_assert_sky_configured("hot-seat")


func test_sandbox_configures_sky() -> void:
	_main._start_sandbox_match_with_args(PackedStringArray(["--players=2"]))
	_assert_sky_configured("sandbox")


func test_tutorial_configures_sky() -> void:
	_main.start_tutorial_from_menu()
	_assert_sky_configured("tutorial")


func test_gift_demo_configures_sky() -> void:
	_main.start_gift_demo_from_menu()
	_assert_sky_configured("gift demo")


func test_tower_topple_configures_sky() -> void:
	_main.start_tower_topple_from_menu()
	_assert_sky_configured("tower topple")


## Bontago-1pi.127 (owner screenshot 2026-10-08 showed the painted sunset): the real menu
## entry, with the match clock running, keeps the painted panorama off the live sky material
## (procedural_sea_mix replaces it entirely) and survives the F5 reset's restart.
func test_menu_sandbox_never_samples_the_painted_panorama() -> void:
	Match.set_process(true)
	_main.start_sandbox_from_menu()
	var sky: Skybox = _main.get_node("Skybox") as Skybox
	for step: int in 3:
		await get_tree().create_timer(0.2).timeout
		_assert_sky_configured("menu sandbox step %d" % step)
		var material: ShaderMaterial = sky.environment.sky.sky_material as ShaderMaterial
		assert_eq(float(material.get_shader_parameter(&"procedural_sea_mix")), 1.0, "painted panorama fully replaced")
		if step == 1:
			_main._sandbox._reset_field()
	Match.set_process(false)
