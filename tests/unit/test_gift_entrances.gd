extends GutTest
## Bontago-1pi.85.45 (docs/GIFT_PLAYTEST3_PLAN.md P1): the three new gift entrances.
## Propeller rises out of the disc at the drop point (PropellerStand, no carrier), the black
## hole opens up underneath it (core starts below the surface), the anvil is a physical
## carrier spawned sky_drop_height_m above the validated point that falls and tilts the disc
## only after it lands. Clients build the visuals from the replicated special_triggered.
## Fixture from test_gift_in_place.gd.

const MatchNetScript := preload("res://net/MatchNet.gd")
const TICK: float = 1.0 / 60.0
const FALL_MAX_FRAMES: int = 900
const TOWER_HEIGHT_M: float = 6.0
const SIDE_BLOCK_OFFSET_M: float = 2.5
const POST_LAND_FRAMES: int = 30
const HEIGHT_EPSILON_M: float = 0.001
const DROP_POINT_TOLERANCE_M: float = 1.0
## The carrier origin sits at its base; allow this much below the nominal height.
const SPAWN_HEIGHT_SLACK_M: float = 1.0
## Minimum frames the fall takes (measured about 53 with the project gravity; no fall at all would tilt at once).
const MIN_FALL_FRAMES: int = 30

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
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
	Match._placement._activation.clear()
	Match.abort_match()
	for child: Node in _field.get_children():
		if child is PropellerStand:
			child.free()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 13579
	return config


func _start() -> void:
	Match.start_match(_config())
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _release(slot_id: int, gift_id: StringName, hover_y: float = 5.0) -> StringName:
	Match._gifts._ensure_capacity(slot_id)
	Match._gifts._held_specials[slot_id] = gift_id
	Match._feed._held_is_gift[slot_id] = true
	var at: Vector3 = _home_world_position(slot_id)
	at.y = hover_y
	return Match.request_place(slot_id, at, 0, Quaternion.IDENTITY, false)


func _carrier() -> Block:
	for child: Node in _blocks_root.get_children():
		if child is Block and (child as Block).gift_id == &"anvil":
			return child as Block
	return null


## A static-ish cube at a world pose, in the physics space after two frames.
func _cube_at(at: Vector3) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var block: Block = BlockFactory.build(shape, tuning)
	_blocks_root.add_child(block)
	block.global_position = at
	block.gravity_scale = 0.0
	return block


func _stand() -> PropellerStand:
	for child: Node in _field.get_children():
		if child is PropellerStand:
			return child as PropellerStand
	return null


func test_presenter_registers_the_propeller_and_black_hole_builders() -> void:
	assert_true(Match._gift_fx.has_handler(&"propeller"))
	assert_true(Match._gift_fx.has_handler(&"black_hole"))


func test_propeller_rises_out_of_the_disc_at_the_drop_point_without_a_carrier() -> void:
	_start()
	assert_eq(_release(0, &"propeller"), PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 0, "no carrier in blocks_parent")
	assert_eq(_registry.tracked_block_count(), 0, "nothing registered")
	var stand: PropellerStand = _stand()
	assert_not_null(stand, "the stand is spawned on the host at release")
	if stand == null:
		return
	assert_true(stand.has_force(), "the host stand runs the disc blow")
	var effect: PropellerEffect = SpecialDef.find_by_id(&"propeller").effect as PropellerEffect
	var home: Vector2 = Match.slot(0).home_position
	assert_lt(_field.disk_local_from_world(stand.global_position).distance_to(home), DROP_POINT_TOLERANCE_M, "at the drop point")
	assert_lt(stand.visual().position.y, 0.0, "starts below the surface")
	stand.tick(effect.emerge_s)
	assert_almost_eq(stand.visual().position.y, effect.emerge_height_m, HEIGHT_EPSILON_M, "risen to the emerge height")
	assert_gt(stand.visual().get_child_count(), 0, "the gift model is built")


func test_propeller_stand_blows_for_the_duration_then_frees_itself() -> void:
	_start()
	_field.set_tilt_enabled(true)
	_release(0, &"propeller")
	var stand: PropellerStand = _stand()
	var effect: PropellerEffect = SpecialDef.find_by_id(&"propeller").effect as PropellerEffect
	var peak: float = 0.0
	var ticks: int = int(effect.disc_force.duration_s / TICK) - 1
	for _i: int in range(ticks):
		stand.tick(TICK)
		_field._update_tilt(TICK)
		peak = maxf(peak, _field.tilt_vector().length())
	assert_gt(peak, 0.0, "the stand tilts the disc while it stands")
	assert_false(stand.is_queued_for_deletion())
	stand.tick(TICK * 2.0)
	assert_true(stand.is_queued_for_deletion(), "freed once the duration has elapsed")
	assert_almost_eq(stand.height_at(effect.disc_force.duration_s), -effect.start_depth_m, HEIGHT_EPSILON_M, "sunk back at the end")


func test_black_hole_opens_up_underneath_the_drop_point_without_a_carrier() -> void:
	_start()
	assert_eq(_release(0, &"black_hole"), PlacementRules.REASON_OK)
	assert_eq(_registry.tracked_block_count(), 0, "nothing registered")
	var visuals: Array[Node] = _blocks_root.find_children("*", "BlackHoleVisual", true, false)
	assert_eq(visuals.size(), 1, "the vortex is drawn at the release point")
	assert_eq(_blocks_root.find_children("*", "BlackHoleField", true, false).size(), 1, "the pull field runs")
	for child: Node in _blocks_root.get_children():
		assert_false(child is Block, "no carrier body")
	var visual: BlackHoleVisual = visuals[0] as BlackHoleVisual
	var core: MeshInstance3D = visual.get_child(1) as MeshInstance3D
	var tuning: BlackHoleVisualTuning = load("res://config/black_hole_visual.tres") as BlackHoleVisualTuning
	assert_almost_eq(core.position.y, -tuning.core_emerge_depth_m * (1.0 - tuning.grow_start_fraction), HEIGHT_EPSILON_M, "core starts below the surface")
	visual._process(tuning.grow_in_s)
	assert_almost_eq(core.position.y, 0.0, HEIGHT_EPSILON_M, "core has risen to the surface")


func test_anvil_spawns_high_above_the_point_falls_and_tilts_only_after_landing() -> void:
	_start()
	_field.set_tilt_enabled(true)
	var def: SpecialDef = SpecialDef.find_by_id(&"anvil")
	assert_eq(_release(0, &"anvil"), PlacementRules.REASON_OK)
	assert_eq(_registry.tracked_block_count(), 1, "the anvil is a physical, registered carrier")
	var carrier: Block = null
	for child: Node in _blocks_root.get_children():
		if child is Block:
			carrier = child as Block
	assert_not_null(carrier)
	if carrier == null:
		return
	var surface_y: float = _field.to_global(Vector3(0.0, _field.surface_y(), 0.0)).y
	assert_gt(carrier.global_position.y - surface_y, def.sky_drop_height_m - SPAWN_HEIGHT_SLACK_M, "spawned about sky_drop_height_m above the surface")
	var tilted_in_air: bool = false
	var landed_frame: int = -1
	for frame: int in range(FALL_MAX_FRAMES):
		await wait_physics_frames(1)
		if not is_instance_valid(carrier):
			break  # the spent anvil has despawned
		var height: float = carrier.global_position.y - surface_y
		var tilting: bool = _field.tilt_vector().length() > 0.0
		if tilting and landed_frame < 0:
			landed_frame = frame
			if height > def.sky_drop_height_m * 0.5:
				tilted_in_air = true
		if landed_frame >= 0 and frame > landed_frame + POST_LAND_FRAMES:
			break
	assert_false(tilted_in_air, "no tilt while the anvil is still falling")
	assert_gte(landed_frame, MIN_FALL_FRAMES, "the disc tilts only after a real fall from the sky")
	assert_gt(_field.tilt_vector().length(), 0.0, "tilted after landing")


func test_client_builds_the_propeller_stand_from_the_replicated_trigger_without_a_carrier() -> void:
	_start()
	var fake: FakeNet = FakeNet.client(1)
	Match.set_net_provider(fake)
	var net: MatchNetScript = MatchNetScript.new()
	net.set_process(false)
	add_child_autofree(net)
	net.set_providers(fake, Match)
	var point: Vector3 = _field.to_global(Vector3(2.0, _field.surface_y(), 3.0))
	net.net_match_event(MatchNetScript.EVENT_SPECIAL_TRIGGERED, [MatchGiftActivation.IN_PLACE_NET_ID, &"propeller", point, 0])
	var stand: PropellerStand = _stand()
	assert_not_null(stand, "client draws the stand from the replicated activation")
	if stand != null:
		assert_false(stand.has_force(), "client stand is visual only")
		assert_almost_eq(stand.global_position.distance_to(point), 0.0, 0.01)
	assert_eq(_registry.tracked_block_count(), 0, "no carrier body on the client")
	assert_eq(_blocks_root.get_child_count(), 0)
	net.set_providers(null, null)


func test_high_hover_clamps_the_anvil_spawn_inside_the_snapshot_band() -> void:
	_start()
	var net_config: NetConfig = load("res://config/net_config.tres") as NetConfig
	var ghost: GhostTuning = load("res://config/ghost_tuning.tres") as GhostTuning
	assert_eq(_release(0, &"anvil", net_config.pos_max_y), PlacementRules.REASON_OK)
	var carrier: Block = _carrier()
	assert_not_null(carrier)
	if carrier != null:
		assert_lte(carrier.global_position.y, net_config.pos_max_y - ghost.hover_ceiling_margin + HEIGHT_EPSILON_M, "inside the position band")
		var surface_y: float = _field.to_global(Vector3(0.0, _field.surface_y(), 0.0)).y
		assert_lt(carrier.global_position.y, surface_y + SpecialDef.find_by_id(&"anvil").sky_drop_height_m + SPAWN_HEIGHT_SLACK_M * 2.0, "derived from the disc, not the hover height")


func test_anvil_spawns_above_a_tall_tower_under_the_point() -> void:
	_start()
	var home: Vector3 = _home_world_position(0)
	var surface_y: float = _field.to_global(Vector3(0.0, _field.surface_y(), 0.0)).y
	var tower_top: float = surface_y + TOWER_HEIGHT_M
	var tower: Block = _cube_at(Vector3(home.x, tower_top - 0.5, home.z))
	await wait_physics_frames(2)
	assert_eq(_release(0, &"anvil"), PlacementRules.REASON_OK)
	var carrier: Block = _carrier()
	assert_not_null(carrier)
	if carrier != null:
		assert_gt(carrier.global_position.y, tower_top + SpecialDef.find_by_id(&"anvil").sky_drop_height_m - SPAWN_HEIGHT_SLACK_M, "spawned above the tower top")
	assert_not_null(tower)


func test_anvil_falls_back_to_the_release_point_when_the_sky_pose_overlaps_a_block() -> void:
	_start()
	var home: Vector3 = _home_world_position(0)
	var surface_y: float = _field.to_global(Vector3(0.0, _field.surface_y(), 0.0)).y
	var sky_m: float = SpecialDef.find_by_id(&"anvil").sky_drop_height_m
	# Beside the ray (misses it) but inside the 5x carrier's footprint at the sky pose.
	_cube_at(Vector3(home.x + SIDE_BLOCK_OFFSET_M, surface_y + sky_m + 1.0, home.z))
	await wait_physics_frames(2)
	assert_eq(_release(0, &"anvil"), PlacementRules.REASON_OK)
	var carrier: Block = _carrier()
	assert_not_null(carrier)
	if carrier != null:
		assert_lt(carrier.global_position.y, surface_y + sky_m * 0.5, "fell back to the validated release point")
