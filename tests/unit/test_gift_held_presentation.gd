extends GutTest
## Bontago-59o.13: while a claimed gift is the current piece the ghost shows a
## held-gift presentation instead of the plain block, and the HUD held/next
## previews draw the gift icon (or the generic fallback).


func _make_ghost() -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	return ghost


func _block_meshes_visible(ghost: GhostPreview) -> bool:
	var any_visible: bool = false
	for child: Node in ghost._shape_visual.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance != null and mesh_instance.visible:
			any_visible = true
	return any_visible


func test_ghost_switches_to_gift_visual_and_back() -> void:
	var ghost: GhostPreview = _make_ghost()
	assert_null(ghost.gift_visual())
	assert_true(_block_meshes_visible(ghost))
	ghost.set_held_gift(&"rocket")
	assert_not_null(ghost.gift_visual(), "fallback gift visual is shown")
	assert_false(_block_meshes_visible(ghost), "plain block mesh hidden")
	assert_eq(ghost.held_gift_id(), &"rocket")
	ghost.set_held_gift(&"")
	assert_null(ghost.gift_visual())
	assert_true(_block_meshes_visible(ghost), "plain block ghost restored")


func test_gift_presentation_survives_shape_change() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_held_gift(&"rocket")
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	assert_not_null(ghost.gift_visual())
	assert_false(_block_meshes_visible(ghost))


func test_held_scene_overrides_fallback() -> void:
	var ghost: GhostPreview = _make_ghost()
	var def: SpecialDef = SpecialDef.find_by_id(&"rocket")
	assert_not_null(def)
	var packed: PackedScene = PackedScene.new()
	var node: Node3D = Node3D.new()
	node.name = &"CustomArt"
	packed.pack(node)
	node.free()
	def.held_scene = packed
	ghost.set_held_gift(&"rocket")
	def.held_scene = null
	assert_eq(ghost.gift_visual().get_child_count(), 0, "custom scene root, not the fallback crate")


func test_footprint_survives_gift_presentation() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.update_placement(Vector3.ZERO, Vector3.UP)
	var hull_before: int = ghost._rotated_shape_hull().size()
	ghost.set_held_gift(&"rocket")
	assert_eq(ghost._rotated_shape_hull().size(), hull_before)


func test_preview_icon_falls_back_to_generic() -> void:
	assert_eq(SpecialDef.preview_icon_for(&"rocket"), SpecialDef.GENERIC_PREVIEW_ICON)
	assert_eq(SpecialDef.preview_icon_for(&"no_such_gift"), SpecialDef.GENERIC_PREVIEW_ICON)
	var def: SpecialDef = SpecialDef.find_by_id(&"rocket")
	var icon: Texture2D = PlaceholderTexture2D.new()
	def.preview_icon = icon
	assert_eq(SpecialDef.preview_icon_for(&"rocket"), icon)
	def.preview_icon = null


func test_hud_uses_gift_icon_for_held_and_next() -> void:
	var hud: HUD = autofree((load("res://ui/HUD.tscn") as PackedScene).instantiate())
	add_child_autofree(hud)
	var fake: FakeMatch = FakeMatch.new()
	hud.match_provider = fake
	hud.set_active_slot(0, Color.RED)
	hud._refresh_special_indicator()
	assert_null(hud.held_gift_icon())
	assert_null(hud.next_gift_icon())
	fake.held_special_by_slot[0] = &"rocket"
	fake.pending_special_count_by_slot[0] = 2
	hud._refresh_special_indicator()
	assert_eq(hud.held_gift_icon(), SpecialDef.GENERIC_PREVIEW_ICON)
	assert_eq(hud.next_gift_icon(), SpecialDef.GENERIC_PREVIEW_ICON)
	fake.held_special_by_slot.erase(0)
	fake.pending_special_count_by_slot[0] = 0
	hud._refresh_special_indicator()
	assert_null(hud.held_gift_icon())
	assert_null(hud.next_gift_icon())
