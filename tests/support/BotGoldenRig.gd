class_name BotGoldenRig
extends RefCounted
## Test support of tests/unit/bots/test_bot_controller_golden.gd: builds one scripted bot scene (a bare
## Field, a duck fake of the match, real frozen blocks and SpecialBehavior nodes, a BotController with
## forced-huge think budgets) and steps the controller by hand until it sends. No physics stepping, no wall clock.
## `wire` and `view_of` are the only two places that know how the controller gets its match and its snapshot.

const CUBE_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")
const PILLAR_SHAPE: BlockShape = preload("res://config/blocks/pillar.tres")
const PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
const TERRITORY_TUNING: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
const SPECIAL_TUNING: SpecialTuning = preload("res://config/gifts/special_tuning.tres")
const BOT_TUNING: BotTuning = preload("res://config/bots/bot_tuning.tres")

const BOT_SLOT: int = 0
## Slot 2 is the bot's teammate (team 0): its throws are not incoming.
const HOMES: Array[Vector2] = [Vector2(-6.0, 0.0), Vector2(6.0, 0.0), Vector2(-6.0, 6.0)]
const TEAMS: Array[int] = [0, 1, 0]
const FIELD_RADIUS_M: float = 10.0
const GRID_RADIUS_M: float = 20.0
const GRID_CELL_M: float = 1.0
## Seconds left on the block timer: far above any think, so the clamps never act.
const FEED_TIME_LEFT_S: float = 99.0
const FEED_SEQ: int = 5
## A think that finishes in its first slice and a point appetite (the draw still consumes one rng value).
const HUGE_BUDGET_US: int = 1000000000
const POINT_APPETITE: float = 0.6
## Ceiling of the by-hand loop (reaction delay + think deadline + acting are about 40 frames).
const MAX_FRAMES: int = 400
const STEP_S: float = 1.0 / 60.0
const STACK_CIRCLE_TEAM_SLOT: int = 0
const HEIGHT_PROBE_BODY_ID: int = 7
const TILT_X_RAD: float = 0.15
const TILT_Z_RAD: float = 0.1
const SHRINK_RIM_M: float = 14.0


class GoldenFakeNet:
	func is_host() -> bool:
		return true


class GoldenFakeBreeze:
	var gust_list: Array[Dictionary] = []

	func gusts() -> Array[Dictionary]:
		return gust_list


class GoldenFakeWeather:
	var id: StringName = &""
	var intensity: float = 0.0
	var seed_number: int = 0
	var event_number: int = 0
	var breeze_ref: GoldenFakeBreeze = GoldenFakeBreeze.new()

	func active_id() -> StringName:
		return id

	func active_intensity() -> float:
		return intensity

	func seed_value() -> int:
		return seed_number

	func event_index() -> int:
		return event_number

	func breeze() -> GoldenFakeBreeze:
		return breeze_ref


## The duck fake of the match: answers reads from scene data, records every request as var_to_str text.
class GoldenFakeMatch:
	var config: MatchConfig = null
	var slots: Array[PlayerSlot] = []
	var raster_value: TerritoryRaster = null
	var circle_arrays_value: Dictionary = {}
	var held_shape_value: BlockShape = null
	var next_shape_value: BlockShape = null
	var held_special_value: StringName = &""
	var gift_states_value: Array[Dictionary] = []
	var sudden_death_value: bool = false
	var mode_goal_value: BotModeGoal = null
	var weather_value: GoldenFakeWeather = null
	var requests: Array[String] = []

	func state() -> int:
		return MatchAutoload.State.PLAYING

	func slot_count() -> int:
		return slots.size()

	func slot(slot_id: int) -> PlayerSlot:
		return slots[slot_id] if slot_id >= 0 and slot_id < slots.size() else null

	func team_of(slot_id: int) -> int:
		return TEAMS[slot_id]

	func held_shape(_slot_id: int) -> BlockShape:
		return held_shape_value

	func next_shape(_slot_id: int) -> BlockShape:
		return next_shape_value

	func held_special(_slot_id: int) -> StringName:
		return held_special_value

	func is_release_locked(_slot_id: int) -> bool:
		return false

	func feed_time_left(_slot_id: int) -> float:
		return FEED_TIME_LEFT_S

	func feed_seq(_slot_id: int) -> int:
		return FEED_SEQ

	func gift_slot_head(_slot_id: int) -> StringName:
		return &""

	func request_use_gift_slot(_slot_id: int) -> bool:
		return false

	func raster() -> TerritoryRaster:
		return raster_value

	func circle_render_arrays() -> Dictionary:
		return circle_arrays_value

	func gift_states() -> Array[Dictionary]:
		return gift_states_value

	func sudden_death_active() -> bool:
		return sudden_death_value

	func bot_mode_goal(_slot_id: int) -> BotModeGoal:
		return mode_goal_value

	func weather() -> GoldenFakeWeather:
		return weather_value

	func note_aim(slot_id: int, aim: Vector3) -> void:
		requests.append(var_to_str(["note_aim", slot_id, aim]))

	func request_place(
		slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, auto_drop: bool, feed_seq_arg: int = -1
	) -> StringName:
		requests.append(var_to_str(["place", slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq_arg]))
		return PlacementRules.REASON_OK

	func request_throw(
		slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, velocity: Vector3, feed_seq_arg: int = -1
	) -> StringName:
		requests.append(var_to_str(["throw", slot_id, origin, orientation_index, free_quat, velocity, feed_seq_arg]))
		return PlacementRules.REASON_OK


var field: Field = null
var registry: BlockRegistry = null
var fake: GoldenFakeMatch = null
var controller: BotController = null
## Frames the controller needed before it sent.
var frames: int = 0
var _owned: Array[Node] = []


## Builds `scene` (see test_bot_controller_golden.gd for its keys) for a controller seeded `seed_value`.
static func build(test: GutTest, scene: Dictionary, seed_value: int, held_special: StringName = &"") -> BotGoldenRig:
	var rig: BotGoldenRig = BotGoldenRig.new()
	rig._build(test, scene, seed_value, held_special)
	return rig


## The one seam that hands the controller its match and its session.
static func wire(controller_node: BotController, fake_match: GoldenFakeMatch) -> void:
	controller_node.set_match_provider(fake_match)
	controller_node.set_net_provider(GoldenFakeNet.new())


## The snapshot the controller's current think read.
static func view_of(controller_node: BotController) -> BotWorldView:
	# SHORTCUT: reads the private _special_view until BotWorldReader.read() exists, replaced by P11-Tsnap
	return controller_node._special_view


## Steps the controller until it has sent (a place or a throw); returns false when it never does.
func run() -> bool:
	frames = 0
	Events.feed_block_issued.emit(BOT_SLOT, &"", &"")
	while frames < MAX_FRAMES:
		controller._physics_process(STEP_S)
		frames += 1
		for request: String in fake.requests:
			if request.begins_with("[\"place\"") or request.begins_with("[\"throw\""):
				return true
	return false


## Frees every node the rig made at once (a queued free would leave a SpecialBehavior in its group).
func dispose() -> void:
	for node: Node in _owned:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_owned.clear()


func _adopt(test: GutTest, node: Node, parent: Node = null) -> void:
	_owned.append(node)
	if parent != null:
		parent.add_child(node)
	else:
		test.add_child(node)


func _build(test: GutTest, scene: Dictionary, seed_value: int, held_special: StringName) -> void:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"golden_disk"
	map_def.field_radius = FIELD_RADIUS_M
	map_def.cell_size = GRID_CELL_M
	map_def.disk_height = 1.0
	map_def.territory_res = 16
	field = Field.new()
	field.map_def = map_def
	_adopt(test, field)
	if bool(scene.get("tilt", false)):
		field.global_transform = Transform3D(Basis(Vector3.RIGHT, TILT_X_RAD) * Basis(Vector3.BACK, TILT_Z_RAD), Vector3.ZERO)
	registry = BlockRegistry.new()
	_adopt(test, registry)
	var blocks_root: Node3D = Node3D.new()
	_adopt(test, blocks_root)

	fake = GoldenFakeMatch.new()
	fake.config = MatchConfig.new()
	fake.config.rng_seed = seed_value
	fake.config.goal_flag_count = 1
	fake.config.disc_size_step = 1
	fake.config.gifts_enabled = bool(scene.get("gifts_enabled", false))
	for slot_id: int in range(HOMES.size()):
		fake.slots.append(PlayerSlot.new(slot_id, TEAMS[slot_id], "Slot %d" % slot_id, Color.WHITE, HOMES[slot_id]))
	fake.held_shape_value = CUBE_SHAPE
	fake.next_shape_value = PILLAR_SHAPE
	fake.held_special_value = held_special
	for state: Dictionary in scene.get("gift_states", []) as Array:
		fake.gift_states_value.append(state)
	fake.sudden_death_value = bool(scene.get("sudden_death", false))
	_build_weather(scene)
	_build_goal(scene)
	_build_territory(scene, blocks_root, test)
	_build_specials(scene, blocks_root, test)

	controller = BotController.new()
	controller.tuning = _pinned_tuning()
	wire(controller, fake)
	_adopt(test, controller)
	controller.setup(BOT_SLOT, MatchConfig.AiDifficulty.NORMAL, field, registry)


## A copy of the shipped tuning whose Normal tier finishes a think in one slice, with a point appetite
## and no release hold.
func _pinned_tuning() -> BotTuning:
	var tuning: BotTuning = BOT_TUNING.duplicate() as BotTuning
	tuning.release_delay_min_s = 0.0
	tuning.release_delay_max_s = 0.0
	var profile: BotDifficultyProfile = tuning.profile_for(MatchConfig.AiDifficulty.NORMAL).duplicate() as BotDifficultyProfile
	profile.think_budget_us = HUGE_BUDGET_US
	profile.think_frame_cap_us = HUGE_BUDGET_US
	profile.appetite_range = Vector2(POINT_APPETITE, POINT_APPETITE)
	tuning.normal = profile
	return tuning


func _build_weather(scene: Dictionary) -> void:
	var weather: Dictionary = scene.get("weather", {}) as Dictionary
	if weather.is_empty():
		return
	var fake_weather: GoldenFakeWeather = GoldenFakeWeather.new()
	fake_weather.id = weather["id"] as StringName
	fake_weather.intensity = float(weather["intensity"])
	fake_weather.seed_number = int(weather["seed"])
	fake_weather.event_number = int(weather["event"])
	for gust: Dictionary in weather.get("gusts", []) as Array:
		fake_weather.breeze_ref.gust_list.append(gust)
	fake.weather_value = fake_weather


func _build_goal(scene: Dictionary) -> void:
	var mode: int = int(scene.get("mode", MatchConfig.GameMode.CLASSIC))
	fake.config.game_mode = mode as MatchConfig.GameMode
	if mode == MatchConfig.GameMode.CLASSIC and not scene.has("tower"):
		return
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = mode
	if scene.has("tower"):
		goal.has_tower = true
		goal.tower_origin = scene["tower"] as Vector2
	fake.mode_goal_value = goal


## Home circles, the scene's block stacks (real frozen cubes plus their influence circle) and the raster.
func _build_territory(scene: Dictionary, blocks_root: Node3D, test: GutTest) -> void:
	var grid: CellGrid = CellGrid.new(GRID_RADIUS_M, GRID_CELL_M)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, TERRITORY_TUNING)
	var circles: Array[InfluenceCircle] = []
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	for slot_id: int in range(HOMES.size()):
		circles.append(InfluenceCircle.for_home(HOMES[slot_id], TEAMS[slot_id], slot_id, TERRITORY_TUNING))
		xs.append(HOMES[slot_id].x)
		zs.append(HOMES[slot_id].y)
		radii.append(TERRITORY_TUNING.home_radius)
		teams.append(TEAMS[slot_id])
	for stack: Dictionary in scene.get("stacks", []) as Array:
		var at: Vector2 = stack["at"] as Vector2
		var count: int = int(stack["cubes"])
		var slot_id: int = int(stack.get("slot", STACK_CIRCLE_TEAM_SLOT))
		for i: int in range(count):
			_add_frozen_cube(test, blocks_root, at, i, slot_id)
		var radius: float = InfluenceCircle.radius_for_height(
			float(count) * PHYSICS_TUNING.cube_size, TERRITORY_TUNING, GRID_RADIUS_M
		)
		circles.append(InfluenceCircle.new(at, radius, TEAMS[slot_id], slot_id, false, HEIGHT_PROBE_BODY_ID))
		xs.append(at.x)
		zs.append(at.y)
		radii.append(radius)
		teams.append(TEAMS[slot_id])
	raster.fill_ownership(circles, TerritorySolver.new(TERRITORY_TUNING).solve(circles), false)
	raster.adopt_fill(raster, 0.1, false, false)
	if bool(scene.get("sudden_death", false)):
		_shrink(raster, grid)
	fake.raster_value = raster
	fake.circle_arrays_value = {"xs": xs, "zs": zs, "radii": radii, "teams": teams}


## Opens a permanent hole in every rim cell so the surviving disc is smaller than the original.
func _shrink(raster: TerritoryRaster, grid: CellGrid) -> void:
	for index: int in grid.in_disk_cells():
		if grid.index_center(index).length() > SHRINK_RIM_M:
			var xy: Vector2i = grid.cell_coords(index)
			raster.force_hole_cell(xy.x, xy.y, 0.0, true)


func _add_frozen_cube(test: GutTest, blocks_root: Node3D, at: Vector2, level: int, slot_id: int) -> void:
	var block: Block = BlockFactory.build(CUBE_SHAPE, PHYSICS_TUNING, slot_id)
	_adopt(test, block, blocks_root)
	block.global_position = field.to_global(Vector3(at.x, (float(level) + 0.5) * PHYSICS_TUNING.cube_size, at.y))
	block.freeze = true
	Events.block_placed.emit(block, CUBE_SHAPE.id)


## Specials: "armed" ones sit on the disc, "incoming" ones fly. Each is a real SpecialBehavior child of a Block.
func _build_specials(scene: Dictionary, blocks_root: Node3D, test: GutTest) -> void:
	for entry: Dictionary in scene.get("specials", []) as Array:
		var block: Block = BlockFactory.build(CUBE_SHAPE, PHYSICS_TUNING, int(entry["slot"]))
		_adopt(test, block, blocks_root)
		block.global_position = field.to_global(entry["at"] as Vector3)
		block.linear_velocity = field.global_transform.basis * (entry.get("velocity", Vector3.ZERO) as Vector3)
		var behavior: SpecialBehavior = SpecialBehavior.new()
		block.add_child(behavior)
		behavior.bind(block, SpecialDef.find_by_id(entry["id"] as StringName), SPECIAL_TUNING)
		block.freeze = bool(entry.get("freeze", false))
