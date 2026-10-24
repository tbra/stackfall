extends GutTest
## The circle / goal / argmax arguments of MatchReplicaPort.apply_replicated_territory reach the
## client's territory overlay, read back through Field.overlay()'s shader parameters (the way
## test_territory_overlay.gd reads them). The raster half of the same call is in test_replica_port.gd.

var _field: Field
var _registry: BlockRegistry
var _blocks_root: Node3D
var _port: MatchReplicaPort


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	var tiny_map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(tiny_map)
	config.player_count = 3
	config.game_mode = MatchConfig.GameMode.ELIMINATION
	config.gifts_enabled = false
	config.rng_seed = 4242
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	Match._net_provider = FakeNet.client(1)
	_port = MatchReplicaPort.new(Match)


func after_each() -> void:
	_port = null
	Match._net_provider = null
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _param(param_name: StringName) -> Variant:
	return _field.overlay().material().get_shader_parameter(param_name)


func _send(xs: PackedFloat32Array, goals: PackedVector2Array, argmax: bool) -> void:
	var count: int = xs.size()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	for i: int in range(count):
		zs.append(-xs[i] - 1.0)
		radii.append(2.0 + float(i))
		teams.append(i % 2)
	var goal_radii: PackedFloat32Array = PackedFloat32Array()
	for i: int in range(goals.size()):
		goal_radii.append(3.0 + float(i))
	_port.apply_replicated_territory(
		PackedInt32Array(), PackedByteArray(), PackedByteArray(), false,
		xs, zs, radii, teams, goals, goal_radii, argmax
	)


func test_circles_goals_and_argmax_reach_the_overlay() -> void:
	assert_not_null(_field.overlay().material(), "fixture: the client field has a configured overlay")
	_send(
		PackedFloat32Array([1.0, 5.0, 9.0]),
		PackedVector2Array([Vector2(4.0, -4.0), Vector2(-4.0, 4.0)]),
		true
	)
	assert_eq(int(_param(&"circle_count")), 3)
	assert_true(bool(_param(&"circles_valid")))
	assert_eq(_field.overlay().goal_count(), 2)
	assert_eq(int(_param(&"goal_count")), 2)
	assert_true(bool(_param(&"argmax_mode")))


func test_argmax_off_is_carried_too() -> void:
	_send(PackedFloat32Array([1.0]), PackedVector2Array(), true)
	assert_true(bool(_param(&"argmax_mode")))
	_send(PackedFloat32Array([1.0]), PackedVector2Array(), false)
	assert_false(bool(_param(&"argmax_mode")))


func test_a_packet_without_circles_leaves_the_overlay_as_it_was() -> void:
	_send(PackedFloat32Array([1.0, 5.0, 9.0]), PackedVector2Array([Vector2(4.0, -4.0)]), true)
	_port.apply_replicated_territory(PackedInt32Array(), PackedByteArray(), PackedByteArray(), false)
	assert_eq(int(_param(&"circle_count")), 3)
	assert_eq(_field.overlay().goal_count(), 1)
	assert_true(bool(_param(&"argmax_mode")))
