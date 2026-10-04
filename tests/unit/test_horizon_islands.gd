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
