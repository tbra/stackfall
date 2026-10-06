extends GutTest
## Bontago-1pi.85.26: the owner's report "black hole correctly pulls in blocks,
## none of them are destroyed", reproduced through the REAL gift demo flow
## (game/Main.tscn -> Main.start_gift_demo_from_menu() -> config/sandbox_gift_demo.tres),
## not a hand-built field: the player's own cubes are placed through
## Match.request_place(), a Black hole gift is queued and released next to them like a
## held gift. Events (dissolve start, removal, trigger) always log with prefix BHPROBE;
## VERBOSE adds per-frame distance to the core, the capture meta, HoleDissolver state,
## the registry identity and the field's lifetime. On base 7b8bd14 five cubes dissolved
## and eight stayed jammed in the core (origins 0.5-1.5 m above the surface hole).

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const PILE_COLUMNS: int = 4
const PILE_LAYERS: int = 3
const PILE_SPACING_M: float = 1.1
## Metres from the home position toward the disc centre.
const PILE_INWARD_M: float = 2.0
const PILE_DROP_HEIGHT_M: float = 1.5
const PILE_LAYER_STEP_M: float = 1.2
const SETTLE_FRAMES: int = 150
const GIFT_INWARD_M: float = 7.0
const GIFT_DROP_HEIGHT_M: float = 3.0
## Upper bound on the watch; it ends DISSOLVE_MARGIN_FRAMES after the field is gone.
const WATCH_MAX_FRAMES: int = 720
const DISSOLVE_MARGIN_FRAMES: int = 45
const LOG_EVERY_FRAMES: int = 15
## True prints the per-frame core state (h = horizontal and dy = vertical distance of
## the block origin to the hole, capture meta, dissolving, sleep/freeze, speed).
const VERBOSE: bool = false
## Blocks that ended at least this close (horizontal) to the hole must be gone.
const NEAR_CORE_M: float = 1.6

var _main: Node3D = null
var _log: PackedStringArray = PackedStringArray()


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	DebugMode.set_override_for_test(true)
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = tiny_map
	var tiny_match_config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_match_config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(tiny_match_config as TinyMapMatchConfig).set_tiny_map(tiny_map)
	tiny_match_config.rng_seed = 4242
	_main.match_config = tiny_match_config
	add_child_autofree(_main)
	_log.clear()


func after_each() -> void:
	DebugMode.clear_override_for_test()
	Match.abort_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _note(line: String) -> void:
	_log.append(line)
	print("BHPROBE ", line)


func _black_hole_field() -> BlackHoleField:
	var parent: Node3D = Match.blocks_parent()
	if parent == null:
		return null
	for child: Node in parent.get_children():
		if child is BlackHoleField and not child.is_queued_for_deletion():
			return child as BlackHoleField
	return null


func _own_blocks() -> Array[Block]:
	var blocks: Array[Block] = []
	var parent: Node3D = Match.blocks_parent()
	if parent == null:
		return blocks
	for child: Node in parent.get_children():
		var block: Block = child as Block
		if block != null and block.owner_slot == 0 and block.gift_id == &"" and not block.is_queued_for_deletion():
			blocks.append(block)
	return blocks


## Disk-local point `inward_m` from slot 0's home toward the disc centre.
func _inward(inward_m: float) -> Vector2:
	var home: Vector2 = Match.slot(0).home_position
	return home - home.normalized() * inward_m


func _place_pile(field: Field) -> Array[Block]:
	var home: Vector2 = Match.slot(0).home_position
	var inward: Vector2 = -home.normalized()
	var side: Vector2 = Vector2(-inward.y, inward.x)
	var sandbox: Sandbox = _main._sandbox
	for layer: int in PILE_LAYERS:
		for column: int in PILE_COLUMNS:
			var spot: Vector2 = _inward(PILE_INWARD_M) + (inward * float(column >> 1) + side * float(column & 1)) * PILE_SPACING_M
			var height: float = PILE_DROP_HEIGHT_M + PILE_LAYER_STEP_M * float(layer)
			sandbox.force_next_shape(&"cube")
			var result: StringName = Match.request_place(0, field.to_global(Vector3(spot.x, height, spot.y)), 0, Quaternion.IDENTITY, false)
			_note("pile place layer=%d col=%d -> %s held_special=%s" % [layer, column, result, Match.held_special(0)])
		await wait_physics_frames(20)
	return _own_blocks()


func test_black_hole_released_in_the_gift_demo_dissolves_the_blocks_it_pulls_in() -> void:
	_main.start_gift_demo_from_menu()
	_run_countdown()
	Match.set_process(true)
	await get_tree().process_frame
	var field: Field = _main.get_node("Field") as Field
	var registry: BlockRegistry = _main.get_node("BlockRegistry") as BlockRegistry
	_note("state=%s registry_same=%s host=%s net_host=%s" % [
		Match.state(), Match.registry() == registry, registry.is_host_authority(), Net.is_host()
	])
	# Clear any crate-claimed gift so the pile is plain cubes.
	while Match.pending_special_count(0) > 0:
		Match.pop_pending_special(0)
	var pile: Array[Block] = await _place_pile(field)
	await wait_physics_frames(SETTLE_FRAMES)
	pile = _own_blocks()
	_note("pile placed: %d own blocks" % pile.size())
	assert_gt(pile.size(), PILE_COLUMNS, "the pile was placed through the real feed")

	var started: Dictionary = {}
	var removed: Dictionary = {}
	var on_started: Callable = func(block: RigidBody3D, net_id: int, delay: float) -> void:
		started[block.get_instance_id()] = true
		_note("dissolve_started net_id=%d delay=%.2f pos=%s" % [net_id, delay, block.global_position])
	var on_removed: Callable = func(block: RigidBody3D, reason: String) -> void:
		removed[block.get_instance_id()] = reason
		_note("block_removed id=%d reason=%s gift=%s" % [block.get_instance_id(), reason, (block as Block).gift_id if block is Block else &""])
	var on_triggered: Callable = func(net_id: int, def_id: StringName, position: Vector3, depth: int) -> void:
		_note("special_triggered net_id=%d id=%s pos=%s depth=%d" % [net_id, def_id, position, depth])
	Events.block_dissolve_started.connect(on_started)
	Events.block_removed.connect(on_removed)
	Events.special_triggered.connect(on_triggered)

	while Match.pending_special_count(0) > 0:
		Match.pop_pending_special(0)
	assert_true(Match.debug_queue_special(0, &"black_hole"), "black hole queued as the next gift")
	# Like the owner: the queued gift becomes the HELD piece once the current piece is placed.
	_main._sandbox.force_next_shape(&"cube")
	var feeder: StringName = Match.request_place(0, field.to_global(Vector3(_inward(0.0).x, PILE_DROP_HEIGHT_M, _inward(0.0).y)), 0, Quaternion.IDENTITY, false)
	_note("feeder place -> %s held_special=%s" % [feeder, Match.held_special(0)])
	assert_eq(Match.held_special(0), &"black_hole", "the black hole is the held gift")
	var drop: Vector2 = _inward(GIFT_INWARD_M)
	var place: StringName = Match.request_place(0, field.to_global(Vector3(drop.x, GIFT_DROP_HEIGHT_M, drop.y)), 0, Quaternion.IDENTITY, false)
	_note("gift place -> %s" % place)
	assert_eq(place, PlacementRules.REASON_OK, "the black hole gift was released")

	var hole_seen: bool = false
	var gone_frames: int = 0
	var last_centre: Vector3 = Vector3.ZERO
	var dissolver: HoleDissolver = registry.hole_dissolver()
	for frame: int in WATCH_MAX_FRAMES:
		await wait_physics_frames(1)
		var hole: BlackHoleField = _black_hole_field()
		if hole != null:
			hole_seen = true
			last_centre = hole.global_position
		elif hole_seen:
			gone_frames += 1
			if gone_frames >= DISSOLVE_MARGIN_FRAMES:
				break
		if not VERBOSE or hole == null or frame % LOG_EVERY_FRAMES != 0:
			continue
		var surface: float = field.surface_y()
		var lines: PackedStringArray = PackedStringArray()
		for block: Block in _own_blocks():
			var offset: Vector3 = block.global_position - hole.global_position
			var horizontal: float = Vector2(offset.x, offset.z).length()
			if horizontal > hole._effect.pull.radius_m:
				continue
			lines.append("h=%.2f dy=%.2f d3=%.2f cap=%s diss=%s sleep=%s frz=%s v=%.2f" % [
				horizontal, offset.y, offset.length(), block.has_meta(RadialPull.CAPTURED_META),
				dissolver.is_dissolving(block), block.sleeping, block.freeze, block.linear_velocity.length()
			])
		_note("f=%d age=%.2f centre_above_surface=%.2f pending=%d started=%d reg_phys=%s | %s" % [
			frame, hole.age(), hole.global_position.y - surface, dissolver.pending_count(),
			dissolver.dissolves_started, registry.is_physics_processing(), " ; ".join(lines)
		])

	Events.block_dissolve_started.disconnect(on_started)
	Events.block_removed.disconnect(on_removed)
	Events.special_triggered.disconnect(on_triggered)
	assert_true(hole_seen, "the gift spawned a black hole field")
	var near: Array[Block] = []
	for block: Block in _own_blocks():
		var offset: Vector3 = block.global_position - last_centre
		if Vector2(offset.x, offset.z).length() <= NEAR_CORE_M:
			near.append(block)
	_note("end: started=%d removed=%d still_near_core=%d" % [started.size(), removed.size(), near.size()])
	assert_gt(started.size(), 0, "pulled blocks start the shared hole dissolve")
	assert_eq(near.size(), 0, "no block is left sitting in the core undissolved")
