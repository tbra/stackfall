extends GutTest
## Bontago-mp0.123: the horizon island ring (game/sky/HorizonIslands.gd).

func _enabled_config() -> HorizonIslandsConfig:
	# Shipped default is off (Bontago-mp0.133); these tests exercise the restored ring.
	var cfg: HorizonIslandsConfig = HorizonIslands.DEFAULT_CONFIG.duplicate() as HorizonIslandsConfig
	cfg.enabled = true
	return cfg


func _build(map_id: StringName) -> HorizonIslands:
	var ring: HorizonIslands = HorizonIslands.new()
	ring.config = _enabled_config()
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


func test_placement_deterministic_per_map() -> void:
	var cfg: HorizonIslandsConfig = _enabled_config()
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

