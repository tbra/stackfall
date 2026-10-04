extends SceneTree
func _initialize() -> void:
	for id: String in ["mesa","shelf","crag"]:
		var packed:=load("res://assets/models/horizon_islands_v1/"+id+".tscn") as PackedScene
		assert(packed!=null)
		var root:=packed.instantiate() as Node3D
		for lod: int in range(3):
			var mesh:=root.get_node("LOD%d"%lod) as MeshInstance3D
			assert(mesh.visible==(lod==0))
			assert(mesh.material_override is ShaderMaterial)
			assert((mesh.material_override as ShaderMaterial).shader.code.contains("COLOR.rgb"))
		root.free()
	print("3ready-to-instance wrappers: oneLOD visible; shared cel material PASS")
	quit()
