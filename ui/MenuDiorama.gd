class_name MenuDiorama
extends SubViewportContainer
## M7 P7 (docs/M7_PLAN.md "P7 -- Main menu / lobby reskin", Bontago-xtq.32):
## a small, purely decorative 3D scene behind the main menu / lobby panels --
## a home-flag disk with two HomeFlag banners, one GoalFlag, and a loose
## block, seen from a slowly orbiting camera. Builds everything itself in
## _ready() (the same "script-only, no authored .tscn children" convention
## game/HomeFlag.tscn already uses for its own procedural geometry), so this
## node can be dropped straight into ui/MainMenu.tscn / ui/Lobby.tscn as a
## `[node type="SubViewportContainer" script=...]` with no companion scene.
##
## Never runs match logic (hard constraint, Bontago-xtq.32 brief): the
## decorative block is built with BlockFactory.build_visual_only(), which
## returns a plain Node3D + MeshInstance3D -- no RigidBody3D, no
## CollisionShape3D, no _physics_process(), so it cannot ever emit
## Events.block_impacted / block_impacted_at. HomeFlag/GoalFlag are already
## non-physics decorative Node3D trees (game/HomeFlag.gd's own header).
## Degrades cleanly headless (GUT): SubViewport/Camera3D/lighting nodes all
## construct fine with no window; _process() only advances a camera angle,
## touching no autoload and no gameplay signal.

@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")

const HOME_FLAG_SCENE: PackedScene = preload("res://game/HomeFlag.tscn")
const GOAL_FLAG_SCENE: PackedScene = preload("res://game/GoalFlag.tscn")
const BLOCK_SHAPE: BlockShape = preload("res://config/blocks/L4.tres")
const PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics_tuning.tres")

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _orbit_angle_rad: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	# DECISION (ui/MenuDiorama.gd, Bontago-xtq.32): reframed from a full-screen
	# background into a small framed rectangle in the right third of the
	# screen (mockup 10: "floating ... island ... small, framed on the right
	# third"). Anchors are applied here from tuning rather than authored per
	# scene so ui/MainMenu.tscn and ui/Lobby.tscn share one source of layout.
	anchor_left = tuning.diorama_anchor_left
	anchor_top = tuning.diorama_anchor_top
	anchor_right = tuning.diorama_anchor_right
	anchor_bottom = tuning.diorama_anchor_bottom
	_viewport = SubViewport.new()
	_viewport.name = "DioramaViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.disable_3d = false
	add_child(_viewport)

	_build_environment()
	_build_disk()
	_build_props()
	_build_camera()


func _process(delta: float) -> void:
	if _camera == null or tuning.camera_orbit_period_s <= 0.0:
		return
	var angular_speed: float = TAU / tuning.camera_orbit_period_s
	_orbit_angle_rad = fmod(_orbit_angle_rad + angular_speed * delta, TAU)
	var height: float = tuning.camera_height_m
	var radius: float = tuning.camera_radius_m
	_camera.position = Vector3(cos(_orbit_angle_rad) * radius, height, sin(_orbit_angle_rad) * radius)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _build_environment() -> void:
	var env_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = tuning.sky_top_color
	sky_material.sky_horizon_color = tuning.sky_horizon_color
	sky_material.ground_horizon_color = tuning.ground_horizon_color
	sky_material.ground_bottom_color = tuning.ground_horizon_color
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = tuning.ambient_energy
	env_node.environment = environment
	_viewport.add_child(env_node)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color = tuning.sun_color
	sun.light_energy = tuning.sun_energy
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	_viewport.add_child(sun)


## The floating layered-plate island (mockup 10): a slate/deep-teal disk with
## a thin, lighter rim ring carried along its top edge.
func _build_disk() -> void:
	var disk: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = tuning.disk_radius_m
	mesh.bottom_radius = tuning.disk_radius_m
	mesh.height = tuning.disk_thickness_m
	disk.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = tuning.disk_color
	disk.material_override = material
	disk.position = Vector3(0.0, -tuning.disk_thickness_m * 0.5, 0.0)
	_viewport.add_child(disk)

	var rim: MeshInstance3D = MeshInstance3D.new()
	var rim_mesh: TorusMesh = TorusMesh.new()
	rim_mesh.inner_radius = tuning.disk_radius_m - tuning.island_rim_height_m
	rim_mesh.outer_radius = tuning.disk_radius_m
	var rim_material: StandardMaterial3D = StandardMaterial3D.new()
	rim_material.albedo_color = tuning.island_rim_color
	rim.material_override = rim_material
	rim.mesh = rim_mesh
	rim.position = Vector3(0.0, 0.0, 0.0)
	_viewport.add_child(rim)


## Two HomeFlag banners, one GoalFlag at the centre, and one loose decorative
## block -- the same still-life the mockups (docs/art_mockups/10-*.png,
## 11-*.png) show behind the panels.
func _build_props() -> void:
	var pos_a: Vector3 = Vector3(-tuning.disk_radius_m * 0.55, 0.0, tuning.disk_radius_m * 0.35)
	var flag_a: HomeFlag = HOME_FLAG_SCENE.instantiate()
	_viewport.add_child(flag_a)
	flag_a.set_slot(0, tuning.home_flag_a_color)
	flag_a.position = pos_a

	var pos_b: Vector3 = Vector3(tuning.disk_radius_m * 0.55, 0.0, -tuning.disk_radius_m * 0.35)
	var flag_b: HomeFlag = HOME_FLAG_SCENE.instantiate()
	_viewport.add_child(flag_b)
	flag_b.set_slot(1, tuning.home_flag_b_color)
	flag_b.position = pos_b

	var goal: GoalFlag = GOAL_FLAG_SCENE.instantiate()
	_viewport.add_child(goal)
	goal.position = Vector3.ZERO

	_build_territory_patch(pos_a, tuning.territory_patch_color_a)
	_build_territory_patch(pos_b, tuning.territory_patch_color_b)
	_build_block_stack(pos_a, tuning.home_flag_a_color)
	_build_block_stack(pos_b, tuning.home_flag_b_color)


## A flat, low-opacity colored disc on the island's top surface under a
## flag's block stack -- the "flat territory polygon" the mockup shows
## claimed ground with (gap item 1). Purely decorative, no CollisionShape3D.
func _build_territory_patch(flag_position: Vector3, color: Color) -> void:
	var patch: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = tuning.territory_patch_radius_m
	mesh.bottom_radius = tuning.territory_patch_radius_m
	mesh.height = 0.01
	patch.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	patch.material_override = material
	patch.position = flag_position + Vector3(0.0, 0.006, 0.0)
	_viewport.add_child(patch)


## A small (3-5 block) still-life stack of loose blocks in an owner's color
## next to their HomeFlag (gap item 1), built with BlockFactory's non-physics
## visual-only path -- never a RigidBody3D, so it can never emit a gameplay
## signal.
func _build_block_stack(flag_position: Vector3, color: Color) -> void:
	for i: int in range(tuning.stack_block_count):
		var block: Node3D = BlockFactory.build_visual_only(BLOCK_SHAPE, PHYSICS_TUNING)
		for child: Node in block.get_children():
			if child is MeshInstance3D:
				var material: StandardMaterial3D = StandardMaterial3D.new()
				material.albedo_color = color
				(child as MeshInstance3D).material_override = material
		var height: float = PHYSICS_TUNING.cube_size * 0.5 + PHYSICS_TUNING.cube_size * tuning.stack_block_spacing_m * float(i)
		var jitter: Vector3 = Vector3(0.18 * float(i % 2), 0.0, 0.12 * float((i + 1) % 2))
		block.position = flag_position + Vector3(0.0, height, 0.0) + jitter
		_viewport.add_child(block)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = tuning.camera_fov_deg
	# DECISION (ui/MenuDiorama.gd, Bontago-xtq.32): Node3D.look_at() asserts
	# is_inside_tree() (Godot's own error points at look_at_from_position()
	# instead), so the camera must join _viewport as a child *before* it is
	# aimed -- calling look_at() first (on a freshly-constructed, still
	# treeless Camera3D) fails every time, headless or windowed, found via
	# the targeted GUT run's engine error, not a headless-only quirk.
	_viewport.add_child(_camera)
	_camera.position = Vector3(0.0, tuning.camera_height_m, tuning.camera_radius_m)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
