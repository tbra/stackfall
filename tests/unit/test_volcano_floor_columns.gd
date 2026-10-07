extends GutTest
## Bontago-1pi.85.55: a Volcano never removes floor. The placement/cursor column ray
## (Field.raycast_down_disk_local, PLACEMENT_QUERY_MASK) keeps hitting the disc floor at
## every point of the cone's footprint, through the rise and the eruption.

const TICK: float = 1.0 / 60.0
const SAMPLE_OFFSETS: Array[Vector2] = [
	Vector2.ZERO, Vector2(1.0, 0.0), Vector2(-2.0, 0.5), Vector2(0.0, 3.0), Vector2(4.0, -4.0)]
const RIM_MARGIN_M: float = 1.0
const FLOOR_TOLERANCE_M: float = 0.2

var _field: Field
var _blocks: Node3D
var _registry: BlockRegistry
var _map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _map
	add_child_autofree(_field)
	_blocks = autofree(Node3D.new())
	add_child_autofree(_blocks)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks)


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	for child: Node in _blocks.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _start() -> void:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true)
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = 2
	config.hot_seat = false
	config.gifts_enabled = false
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(TICK)


func _assert_floor_under_footprint(home: Vector2, label: String) -> void:
	for offset: Vector2 in SAMPLE_OFFSETS:
		if (home + offset).length() > _map.field_radius - RIM_MARGIN_M:
			continue
		var hit: Variant = _field.raycast_down_disk_local(_field.world_from_disk_local(home + offset, _field.surface_y()))
		assert_not_null(hit, "%s: floor ray at home%s hits something" % [label, offset])
		if hit != null:
			assert_almost_eq((hit as Vector2).x, home.x + offset.x, FLOOR_TOLERANCE_M)


func test_floor_ray_still_hits_across_the_footprint_through_rise_and_eruption() -> void:
	_start()
	var home: Vector2 = Match.slot(0).home_position
	_assert_floor_under_footprint(home, "before")
	var effect: VolcanoEffect = VolcanoEffect.new()
	var structure: VolcanoStructure = VolcanoStructure.spawn_host(
		effect, _field.world_from_disk_local(home, _field.surface_y()), 0)
	assert_not_null(structure)
	structure.set_physics_process(false)
	for phase: String in ["rising", "risen", "erupting"]:
		var seconds: float = effect.rise_s * 0.5 if phase == "rising" else (effect.rise_s if phase == "risen" else 8.0)
		for _i: int in range(int(ceil(seconds / TICK))):
			structure.tick(TICK)
		await wait_physics_frames(2)
		_assert_floor_under_footprint(home, phase)
