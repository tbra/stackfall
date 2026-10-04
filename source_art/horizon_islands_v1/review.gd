extends Node
var viewport: SubViewport
var camera: Camera3D
var env: Environment
var key: DirectionalLight3D
var roots: Array[Node3D] = []
var out: String
var shader: Shader
var clouds: Node3D
var report: Array[Dictionary] = []
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	var args := OS.get_cmdline_user_args()
	out=args[1]
	DirAccess.make_dir_recursive_absolute(out)
	shader=Shader.new()
	shader.code=FileAccess.get_file_as_string(args[0].path_join("island_cel.gdshader"))
	viewport=SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	env=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color(0.63,0.70,0.81)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(0.75,0.79,0.88)
	env.ambient_light_energy=0.45
	var world_env:=WorldEnvironment.new()
	world_env.environment=env
	viewport.add_child(world_env)
	key=DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-38,-30,0)
	key.light_color=Color(1.0,0.93,0.84)
	key.light_energy=0.8
	viewport.add_child(key)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=100
	viewport.add_child(camera)
	for id: String in ["mesa","shelf","crag"]:
		var document:=GLTFDocument.new()
		var state:=GLTFState.new()
		assert(document.append_from_file(args[0].path_join(id+".glb"),state)==OK)
		var root:=document.generate_scene(state) as Node3D
		root.name=id
		viewport.add_child(root)
		roots.append(root)
		var counts: Array[int] = []
		for lod: int in range(3):
			var mesh:=root.get_node("LOD%d"%lod) as MeshInstance3D
			var material:=ShaderMaterial.new()
			material.shader=shader
			mesh.material_override=material
			var triangles: int = 0
			for surface: int in range(mesh.mesh.get_surface_count()):
				var arrays:=mesh.mesh.surface_get_arrays(surface)
				assert(arrays[Mesh.ARRAY_COLOR].size()>0,"vertex colors missing")
				triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
			counts.append(triangles)
			assert(mesh.get_aabb().position.y<0 and mesh.get_aabb().end.y>0,"surface pivot invalid")
		assert(counts==[320,96,32],"LOD triangle counts")
		report.append({"id":id,"triangles":counts,"native_color_and_pivot_check":true})
	# Neutral multiview plus explicit silhouette LOD comparison; fixed framing per island.
	for index: int in range(roots.size()):
		for j: int in range(roots.size()):
			roots[j].visible=j==index
		for yaw: int in [0,60,120]:
			var radians:=deg_to_rad(float(yaw))
			camera.position=Vector3(sin(radians)*135,38,cos(radians)*135)
			camera.look_at(Vector3(0,-12,0))
			for lod: int in range(3):
				select_lod(roots[index],lod)
				await capture("%s_yaw%d_lod%d.png"%[roots[index].name,yaw,lod])
	# Genuine3D haze/cloud occlusion review. This does not instantiate the game's sky.
	clouds=Node3D.new()
	viewport.add_child(clouds)
	var cloudmat:=StandardMaterial3D.new()
	cloudmat.albedo_color=Color(0.83,0.83,0.9)
	cloudmat.roughness=1
	for i: int in range(15):
		var cloud:=MeshInstance3D.new()
		var sphere:=SphereMesh.new()
		sphere.radial_segments=16
		sphere.rings=8
		sphere.radius=25
		sphere.height=50
		cloud.mesh=sphere
		cloud.material_override=cloudmat
		cloud.position=Vector3(float(i%5)*58-116,-33+float(i%3)*2,float(i/5)*47-28)
		cloud.scale=Vector3(1.5,0.4,1.1)
		clouds.add_child(cloud)
	for i: int in range(roots.size()):
		roots[i].visible=true
		roots[i].position=Vector3(float(i)*85-85,0,float(i%2)*-35)
		select_lod(roots[i],0)
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	camera.fov=55
	env.fog_enabled=true
	env.fog_density=0.004
	env.fog_light_color=Color(0.7,0.75,0.86)
	for shot: int in range(9):
		var angle:=deg_to_rad(-20.0+float(shot)*5)
		camera.position=Vector3(sin(angle)*260,28,cos(angle)*260)
		camera.look_at(Vector3(0,-4,0))
		await capture("cloud_orbit_%02d.png"%shot)
	for phase: String in ["sunset","night"]:
		env.background_color=Color(0.75,0.48,0.54) if phase=="sunset" else Color(0.08,0.12,0.24)
		env.fog_light_color=env.background_color
		env.ambient_light_color=Color(0.9,0.64,0.61) if phase=="sunset" else Color(0.25,0.34,0.56)
		key.light_color=Color(1.0,0.67,0.44) if phase=="sunset" else Color(0.5,0.65,1.0)
		await capture("cloud_"+phase+".png")
	var file:=FileAccess.open(out.path_join("native_geometry.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	# Release viewport resources before exit.
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("3islands x3LODs x3angles +9cloud camera views +2palette views: native review PASS")
	get_tree().quit()
func select_lod(root: Node3D,lod: int) -> void:
	for i: int in range(3):
		(root.get_node("LOD%d"%i) as MeshInstance3D).visible=i==lod
func capture(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png(out.path_join(name))==OK)
