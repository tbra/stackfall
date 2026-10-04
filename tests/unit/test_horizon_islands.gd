extends GutTest
## Bontago-mp0.123: the horizon island ring (game/HorizonIslands.gd).

func _build(map_id: StringName) -> HorizonIslands:
	var ring: HorizonIslands = HorizonIslands.new()
	add_child_autofree(ring)
	var map: MapDef = MapDef.new()
	map.id = map_id
	ring.rebuild_for_map(map)
	return ring


func test_spawns_configured_count_in_ring_band() -> void:
	var ring: HorizonIslands = _build(&"round_medium")
	var cfg: HorizonIslandsConfig = ring.config
	assert_eq(ring.get_child_count(), cfg.count)
	for child: Node in ring.get_children():
		var node: Node3D = child as Node3D
		var radius: float = Vector2(node.position.x, node.position.z).length()
		assert_between(radius, cfg.radius_min_m - 0.01, cfg.radius_max_m + 0.01)
		assert_between(node.position.y, cfg.height_min_m - 0.01, cfg.height_max_m + 0.01)
		assert_between(node.scale.y, cfg.scale_min - 0.001, cfg.scale_max + 0.001)


func test_caps_tilt_toward_arena_and_float_above_cloud_banks() -> void:
	# Bontago-mp0.123 root cause: horizon cloud banks (tops up to 60 m) hid the
	# rock bodies of islands whose caps sat near eye height. The whole body
	# must hang above the bank tops, and the cap must tip toward the center.
	var ring: HorizonIslands = _build(&"round_medium")
	var cfg: HorizonIslandsConfig = ring.config
	var highest_bank_top_m: float = 0.0
	for theme_path: String in DirAccess.get_files_at("res://config/sky_themes"):
		if theme_path.ends_with(".tres"):
			var theme: SkyThemeDef = load("res://config/sky_themes/" + theme_path) as SkyThemeDef
			if theme != null and theme.cloud_bank_count > 0:
				highest_bank_top_m = maxf(highest_bank_top_m, theme.cloud_bank_top_max_m)
	assert_gt(cfg.toward_tilt_deg, 0.0)
	for child: Node in ring.get_children():
		var island: Node3D = child as Node3D
		var lod0: VisualInstance3D = island.get_node("LOD0") as VisualInstance3D
		var bottom_y: float = (island.global_transform * lod0.get_aabb()).position.y
		assert_gt(bottom_y, highest_bank_top_m, "island body above the cloud-bank tops")
		var to_center: Vector3 = Vector3(-island.position.x, 0.0, -island.position.z).normalized()
		assert_gt(island.global_basis.y.normalized().dot(to_center), 0.0, "cap tips toward the arena")


func test_lods_use_visibility_ranges_no_shadow_no_collision() -> void:
	var ring: HorizonIslands = _build(&"round_medium")
	var cfg: HorizonIslandsConfig = ring.config
	for island: Node in ring.get_children():
		var lods: Array[GeometryInstance3D] = []
		for lod_name: String in HorizonIslands.LOD_NODE_NAMES:
			lods.append(island.get_node(lod_name) as GeometryInstance3D)
		assert_eq(lods[0].visibility_range_end, cfg.lod1_begin_m)
		assert_eq(lods[1].visibility_range_begin, cfg.lod1_begin_m)
		assert_eq(lods[1].visibility_range_end, cfg.lod2_begin_m)
		assert_eq(lods[2].visibility_range_begin, cfg.lod2_begin_m)
		for lod: GeometryInstance3D in lods:
			assert_true(lod.visible)
			assert_eq(lod.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_eq(ring.find_children("*", "CollisionObject3D", true, false).size(), 0)
	assert_eq(ring.find_children("*", "CollisionShape3D", true, false).size(), 0)


func test_placement_deterministic_per_map() -> void:
	var cfg: HorizonIslandsConfig = HorizonIslands.DEFAULT_CONFIG
	var a: Array[Dictionary] = HorizonIslands.placements_for(cfg, &"round_medium")
	var b: Array[Dictionary] = HorizonIslands.placements_for(cfg, &"round_medium")
	var c: Array[Dictionary] = HorizonIslands.placements_for(cfg, &"ring_large")
	assert_eq(a, b)
	assert_ne(a, c)


func test_disabled_or_zero_count_spawns_nothing() -> void:
	var cfg: HorizonIslandsConfig = HorizonIslandsConfig.new()
	cfg.count = 0
	assert_eq(HorizonIslands.placements_for(cfg, &"x").size(), 0)
	cfg.count = 3
	cfg.enabled = false
	assert_eq(HorizonIslands.placements_for(cfg, &"x").size(), 0)


func test_config_hints_complete() -> void:
	var hints: TuningPanelHints = load("res://config/tuning_panel_hints.tres") as TuningPanelHints
	for prop: Dictionary in HorizonIslandsConfig.new().get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_EDITOR) == 0 or (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n: String = str(prop["name"])
		assert_false(hints.description_for("HorizonIslandsConfig", n).is_empty(), n)
		var t: int = int(prop["type"])
		if t == TYPE_FLOAT or t == TYPE_INT:
			var r: Vector2 = hints.range_for("HorizonIslandsConfig", n)
			assert_false(is_nan(r.x), n)


func test_self_lit_material_follows_sun_and_config() -> void:
	# Sky ambient flattened every facet to one tone; the island shader is
	# unshaded and lit from the wired sun with a cap/rock split.
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	add_child_autofree(sun)
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_color = Color(0.9, 0.8, 0.7)
	var ring: HorizonIslands = HorizonIslands.new()
	add_child_autofree(ring)
	ring.sun_path = ring.get_path_to(sun)
	var map: MapDef = MapDef.new()
	map.id = &"round_medium"
	ring.rebuild_for_map(map)
	var lod0: GeometryInstance3D = ring.get_child(0).get_node("LOD0") as GeometryInstance3D
	var material: ShaderMaterial = lod0.material_override as ShaderMaterial
	assert_eq(material.shader, HorizonIslands.ISLAND_SHADER)
	assert_eq(material.get_shader_parameter(&"cap_tint"), ring.config.cap_tint)
	assert_eq(material.get_shader_parameter(&"shadow_level"), ring.config.shadow_level)
	var to_sun: Vector3 = material.get_shader_parameter(&"sun_direction") as Vector3
	# The light shines along its -Z, so the vector toward the sun is +Z.
	assert_almost_eq(to_sun.dot(sun.global_basis.z.normalized()), 1.0, 0.001)
	assert_eq(material.get_shader_parameter(&"sun_color"), sun.light_color)
	assert_lt(ring.config.shadow_level, ring.config.mid_level)
