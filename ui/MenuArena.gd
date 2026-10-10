class_name MenuArena
extends SubViewportContainer
## Bontago-hfa.3 (UI reskin P1, owner answer Q1 b): the main-menu backdrop is a slow orbit over a
## live arena. It reuses the real arena surface (game/TerritoryOverlay.gd with the real MapDef,
## DiscBodyVisuals and ArenaSideStyle, so the disc, rim, band and territory shader are the
## match's own), the real HomeFlag/GoalFlag beacons, and the match's block meshes and materials
## (BlockFactory). Nothing here steps physics: the blocks are bare MeshInstance3D copies with no
## collision, the territory is a pre-baked owner grid, and no Match/Field autoload state is read.
##
## Cost: one SubViewport with its own World3D, no MSAA (FXAA), no shadows, no reflection probe,
## no SSR/glow/volumetrics. ui/MenuBackdrop.gd still holds the menu render budget (30 fps cap,
## root 3D off), so this renders at the menu cap and only while visible.
## Every number comes from config/MainMenuTuning.gd.

const HOME_FLAG_SCENE: PackedScene = preload("res://game/HomeFlag.tscn")
const GOAL_FLAG_SCENE: PackedScene = preload("res://game/GoalFlag.tscn")
const PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics_tuning.tres")
const TERRITORY_TUNING: TerritoryTuning = preload("res://config/territory_tuning.tres")
const TERRITORY_VISUALS: TerritoryVisuals = preload("res://config/territory_visuals.tres")
const DISC_BODY_VISUALS: DiscBodyVisuals = preload("res://config/disc_body_visuals.tres")
const SIDE_STYLE: ArenaSideStyle = preload("res://config/arena_side_style.tres")
## Owner byte of the shader's territory texture is the slot id plus one; 0 is unclaimed.
const OWNER_BYTE_OFFSET: int = 1
const QUARTER_TURNS: int = 4
const SUN_SHADOWS: bool = false

@export var tuning: MainMenuTuning = preload("res://config/main_menu_tuning.tres")

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _overlay: TerritoryOverlay = null
var _yaw_rad: float = 0.0
var _slot_colors: PackedColorArray = PackedColorArray()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	stretch = true
	stretch_shrink = maxi(tuning.render_shrink, 1)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot_colors = _player_palette()
	_yaw_rad = deg_to_rad(tuning.orbit_start_yaw_deg)
	_viewport = SubViewport.new()
	_viewport.name = "ArenaViewport"
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if tuning.use_fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.disable_3d = false
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_build_environment()
	_build_arena()
	_build_beacons()
	_build_blocks()
	_build_camera()
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _process(delta: float) -> void:
	if _camera == null or tuning.orbit_period_s <= 0.0:
		return
	_yaw_rad = fmod(_yaw_rad + TAU / tuning.orbit_period_s * delta, TAU)
	_place_camera()


## The overlay that draws the real arena, for tests.
func overlay() -> TerritoryOverlay:
	return _overlay


func viewport() -> SubViewport:
	return _viewport


func camera() -> Camera3D:
	return _camera


## The eight player colours as the design tokens carry them (player-1 ... player-8, which the
## design pins to MatchConfig.player_colors), so the backdrop needs no match config.
func _player_palette() -> PackedColorArray:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	return PackedColorArray([
		arcade.player_1_color, arcade.player_2_color, arcade.player_3_color, arcade.player_4_color,
		arcade.player_5_color, arcade.player_6_color, arcade.player_7_color, arcade.player_8_color,
	])


func _on_visibility_changed() -> void:
	if _viewport == null:
		return
	var active: bool = is_visible_in_tree()
	set_process(active)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED


func _build_environment() -> void:
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = tuning.sky_top_color
	sky_material.sky_horizon_color = tuning.sky_horizon_color
	sky_material.ground_horizon_color = tuning.ground_horizon_color
	sky_material.ground_bottom_color = tuning.ground_bottom_color
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = tuning.ambient_energy
	environment.fog_enabled = true
	environment.fog_light_color = tuning.fog_color
	environment.fog_density = tuning.fog_density
	environment.fog_sky_affect = tuning.fog_sky_affect
	var env_node: WorldEnvironment = WorldEnvironment.new()
	env_node.environment = environment
	_viewport.add_child(env_node)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color = tuning.sun_color
	sun.light_energy = tuning.sun_energy
	sun.shadow_enabled = SUN_SHADOWS
	sun.rotation_degrees = tuning.sun_rotation_deg
	_viewport.add_child(sun)


## The real arena mesh: top surface with the territory shader plus the rim/band/bottom side
## surfaces, positioned exactly as Field places it (half a disc thickness below the flag plane).
func _build_arena() -> void:
	var map: MapDef = tuning.arena_map
	_overlay = TerritoryOverlay.new()
	_overlay.name = &"DiskMesh"
	_overlay.configure(map, TERRITORY_VISUALS, TERRITORY_TUNING, DISC_BODY_VISUALS, SIDE_STYLE)
	_overlay.position = Vector3(0.0, -map.disk_height * 0.5, 0.0)
	_viewport.add_child(_overlay)
	_overlay.set_slot_colors(_slot_colors)
	_push_claimed_ground(map)


## Bakes the claimed ground of every shown slot straight into the overlay's owner grid
## (the same bytes TerritoryRaster would hand it), so no solver or Match state is involved.
func _push_claimed_ground(map: MapDef) -> void:
	var grid: CellGrid = CellGrid.new(map.field_radius, map.cell_size, map.shape_test())
	var owner_bytes: PackedByteArray = PackedByteArray()
	owner_bytes.resize(grid.cell_count())
	var state_bytes: PackedByteArray = PackedByteArray()
	state_bytes.resize(grid.cell_count())
	var radius_m: float = tuning.territory_radius_cells * grid.cell_size
	for slot: int in range(tuning.arena_slot_count):
		var home: Vector2 = map.home_flag_position(slot, tuning.arena_slot_count)
		for cy: int in range(grid.res):
			for cx: int in range(grid.res):
				var center: Vector2 = Vector2(
					(float(cx) + 0.5) * grid.cell_size - grid.half_extent,
					(float(cy) + 0.5) * grid.cell_size - grid.half_extent)
				if center.distance_to(home) <= radius_m:
					owner_bytes[grid.cell_index(cx, cy)] = slot + OWNER_BYTE_OFFSET
	_overlay.push_cells(owner_bytes, state_bytes, grid.res)


func _build_beacons() -> void:
	var map: MapDef = tuning.arena_map
	for slot: int in range(tuning.arena_slot_count):
		var flag: HomeFlag = HOME_FLAG_SCENE.instantiate() as HomeFlag
		var local: Vector2 = map.home_flag_position(slot, tuning.arena_slot_count)
		flag.position = Vector3(local.x, 0.0, local.y)
		_viewport.add_child(flag)
		flag.set_slot(slot, SlotColors.wrapped_color(slot, _slot_colors))
	var goal: GoalFlag = GOAL_FLAG_SCENE.instantiate() as GoalFlag
	_viewport.add_child(goal)


## A fixed (seeded) still life of block piles around each beacon, built from the match's own
## block meshes and per-colour cell-grid materials but with no body or collision.
func _build_blocks() -> void:
	var map: MapDef = tuning.arena_map
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = tuning.layout_seed
	var shapes: Array[BlockShape] = tuning.block_shapes
	if shapes.is_empty():
		return
	for slot: int in range(tuning.arena_slot_count):
		var home: Vector2 = map.home_flag_position(slot, tuning.arena_slot_count)
		var color: Color = SlotColors.wrapped_color(slot, _slot_colors)
		var previous: Node3D = null
		var previous_top_m: float = 0.0
		var layer: int = 0
		for _i: int in range(tuning.blocks_per_slot):
			var shape: BlockShape = shapes[rng.randi() % shapes.size()]
			var visual: Node3D = _block_visual(shape, slot, color)
			var stack: bool = previous != null and layer < tuning.block_max_layer and rng.randf() < tuning.block_stack_chance
			var at: Vector3 = Vector3.ZERO
			if stack:
				layer += 1
				at = Vector3(previous.position.x, previous_top_m, previous.position.z)
			else:
				layer = 0
				var angle: float = rng.randf() * TAU
				var ring: float = rng.randf_range(tuning.block_ring_min_m, tuning.block_ring_max_m)
				at = Vector3(home.x + cos(angle) * ring, 0.0, home.y + sin(angle) * ring)
			visual.position = at
			visual.rotation.y = float(rng.randi() % QUARTER_TURNS) * TAU / float(QUARTER_TURNS)
			_viewport.add_child(visual)
			previous = visual
			previous_top_m = at.y + _shape_height_m(shape)


func _shape_height_m(shape: BlockShape) -> float:
	var top: int = 0
	for cell: Vector3i in shape.cells:
		top = maxi(top, cell.y + 1)
	return float(top) * PHYSICS_TUNING.cube_size


## The mesh of a freshly built match block without its body: BlockFactory builds the real Block
## (mesh, shared colour material, outline pass); only its MeshInstance3D children are kept.
func _block_visual(shape: BlockShape, slot: int, color: Color) -> Node3D:
	var block: Block = BlockFactory.build(shape, PHYSICS_TUNING, slot, color)
	var visual: Node3D = Node3D.new()
	for child: Node in block.get_children():
		if child is MeshInstance3D:
			block.remove_child(child)
			visual.add_child(child)
	block.free()
	return visual


func _build_camera() -> void:
	_camera = Camera3D.new()
	# DECISION: the orbit moves in _process(), so physics interpolation would lag it.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = tuning.camera_fov_deg
	_camera.far = tuning.camera_far_m
	_camera.h_offset = tuning.camera_h_offset_m
	_viewport.add_child(_camera)
	_place_camera()


func _place_camera() -> void:
	var target: Vector3 = Vector3(0.0, tuning.camera_target_height_m, 0.0)
	_camera.position = Vector3(cos(_yaw_rad) * tuning.camera_radius_m, tuning.camera_height_m, sin(_yaw_rad) * tuning.camera_radius_m)
	_camera.look_at(target, Vector3.UP)
