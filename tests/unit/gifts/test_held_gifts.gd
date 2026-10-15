extends GutTest
## / 85.79 / 85.80: held gifts keep their authored colours, the held slingshot
## faces the aim like the Rocket, and aimed Rocket/Paintball bodies spawn where the held model is
## drawn (host path: Match.request_throw; the client sees the same replicated spawn transform).

const AIM: Vector3 = Vector3(0.6, -0.3, -0.74)
const NOSE_TOLERANCE_DEG: float = 5.0
const PIVOT_TOLERANCE_M: float = 0.01
const POSE_HEIGHT_M: float = 5.0
const AIMED_GIFTS: Array[StringName] = [&"rocket", &"paintball"]

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _ghost_holding(id: StringName) -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	ghost.set_held_gift(id)
	return ghost


func _mesh_nodes(root: Node) -> Array[Node]:
	return root.find_children("*", "MeshInstance3D", true, false)


# --- 85.77: authored colours ---------------------------------------------------------------

func test_held_gift_materials_carry_no_tint_in_any_state() -> void:
	for entry: GiftModelEntry in GiftModelTable.shared().entries:
		var id: StringName = entry.id
		var ghost: GhostPreview = _ghost_holding(id)
		ghost.set_player_color(Color(0.1, 0.9, 0.2, 1.0))
		var reference: Node3D = autofree(GiftModelTable.shared().build_gift_visual(id))
		var states: Array[PlacementRules.Result] = [
			PlacementRules.Result.VALID, PlacementRules.Result.OUTSIDE_TERRITORY, PlacementRules.Result.HOLE]
		for state: PlacementRules.Result in states:
			ghost.apply_validity(state)
			var held: Array[Node] = _mesh_nodes(ghost.gift_visual())
			var authored: Array[Node] = _mesh_nodes(reference)
			assert_eq(held.size(), authored.size(), "%s mesh count" % id)
			for i: int in range(mini(held.size(), authored.size())):
				var mi: MeshInstance3D = held[i] as MeshInstance3D
				assert_null(mi.material_overlay, "%s no overlay (%d)" % [id, state])
				assert_eq(mi.material_override, (authored[i] as MeshInstance3D).material_override, "%s keeps its own override" % id)


# --- 85.79: slingshot faces the aim like the Rocket ----------------------------------------

func test_paintball_table_row_declares_its_firing_axis() -> void:
	var entry: GiftModelEntry = GiftModelTable.shared().entry_for(&"paintball")
	assert_ne(entry.held_nose_axis, Vector3.ZERO)
	var effect: PaintballEffect = SpecialDef.find_by_id(&"paintball").effect as PaintballEffect
	assert_eq(effect.model_nose_axis, entry.held_nose_axis, "held and body use one axis")
	assert_true(entry.held_keep_upright, "the slingshot never turns upside down")
	assert_false(GiftModelTable.shared().entry_for(&"rocket").held_keep_upright, "rocket keeps its shortest-arc path")


func test_spawned_slingshot_body_faces_the_aim_with_its_forks_up() -> void:
	var def: SpecialDef = SpecialDef.find_by_id(&"paintball")
	var effect: PaintballEffect = def.effect as PaintballEffect
	for aim: Vector3 in [AIM, Vector3(-0.8, -0.1, 0.5), Vector3(0.0, -0.5, -1.0)]:
		var faced: Variant = MatchPlacement.launch_facing_basis(def, GiftThrow.Mode.AIMED, aim.normalized(), Vector3.ZERO)
		assert_true(faced is Basis)
		var basis: Basis = faced as Basis
		assert_lt(rad_to_deg((basis * effect.model_nose_axis).angle_to(aim.normalized())), NOSE_TOLERANCE_DEG)
		assert_gt((basis * Vector3.UP).y, 0.0)


func test_held_slingshot_follows_the_aim_and_keeps_its_handle_down() -> void:
	var ghost: GhostPreview = _ghost_holding(&"paintball")
	var axis: Vector3 = GiftModelTable.shared().entry_for(&"paintball").held_nose_axis
	for aim: Vector3 in [AIM, Vector3(-0.8, -0.1, 0.5), Vector3(0.0, -0.5, -1.0)]:
		ghost.set_held_aim(aim)
		var front: Vector3 = (ghost.gift_visual().global_basis * axis).normalized()
		assert_lt(rad_to_deg(front.angle_to(aim.normalized())), NOSE_TOLERANCE_DEG, "front on aim %s" % aim)
		var up: Vector3 = ghost.gift_visual().global_basis * Vector3.UP
		assert_gt(up.y, 0.0, "forks stay up")


func test_held_slingshot_without_aim_follows_the_camera_yaw_like_the_rocket() -> void:
	var camera: Camera3D = autofree(Camera3D.new())
	add_child_autofree(camera)
	camera.current = true
	camera.rotation_degrees = Vector3(-30.0, 40.0, 0.0)
	var forward: Vector3 = -camera.global_transform.basis.z
	forward.y = 0.0
	for id: StringName in [&"rocket", &"paintball"]:
		var ghost: GhostPreview = _ghost_holding(id)
		ghost.set_held_aim(Vector3.ZERO)
		var axis: Vector3 = GiftModelTable.shared().entry_for(id).held_nose_axis
		var front: Vector3 = (ghost.gift_visual().global_basis * axis).normalized()
		assert_lt(rad_to_deg(front.angle_to(forward.normalized())), NOSE_TOLERANCE_DEG, String(id))


# --- 85.80: spawn at the held model ---------------------------------------------------------

func test_muzzle_matched_origin_puts_the_body_pivot_on_the_held_pivot() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	var origin: Vector3 = Vector3(3.0, 6.0, -2.0)
	var centre: Vector3 = BlockFactory.gift_cell_center(shape, tuning)
	for id: StringName in AIMED_GIFTS:
		var entry: GiftModelEntry = GiftModelTable.shared().entry_for(id)
		var faced: Basis = FlightFacing.nose_basis(entry.held_nose_axis, AIM.normalized())
		var spawn: Vector3 = BlockFactory.muzzle_matched_origin(origin, faced, shape, tuning, id)
		var scale_factor: float = BlockFactory.activation_scale_for(id)
		var body_root: Vector3 = centre + Vector3.UP * ((scale_factor - 1.0) * tuning.cube_size * 0.5)
		assert_true((spawn + faced * body_root).is_equal_approx(origin + centre), "%s pivot on held pivot" % id)


func _start_with(gift: StringName) -> void:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 97531
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	Match._gifts._ensure_capacity(0)
	Match._gifts._held_specials[0] = gift
	Match._feed._held_is_gift[0] = true


func test_real_aimed_launch_spawns_the_model_where_the_held_model_is_drawn() -> void:
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	for id: StringName in AIMED_GIFTS:
		_start_with(id)
		var shape: BlockShape = Match.held_shape(0)
		var home: Vector2 = Match.slot(0).home_position
		var pose: Vector3 = _field.to_global(Vector3(home.x, POSE_HEIGHT_M, home.y))
		var held_pivot: Vector3 = pose + BlockFactory.gift_cell_center(shape, tuning)
		var reason: StringName = Match.request_throw(0, pose, 0, Quaternion.IDENTITY, AIM.normalized())
		assert_eq(reason, PlacementRules.REASON_OK, String(id))
		var block: Block = _blocks_root.get_child(_blocks_root.get_child_count() - 1) as Block
		var visual: Node3D = block.get_node(NodePath(String(BlockFactory.GIFT_VISUAL_NODE))) as Node3D
		var pivot: Vector3 = block.global_transform * visual.position
		assert_lt(pivot.distance_to(held_pivot), PIVOT_TOLERANCE_M, "%s spawns at the held model (%s vs %s)" % [id, pivot, held_pivot])
		Match.abort_match()
		for child: Node in _blocks_root.get_children():
			child.free()
