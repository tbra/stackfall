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
	var previous: PackedScene = def.held_scene
	# Bontago-mp0.119: the GLB table wins when it has a row, so empty it here.
	var table: GiftModelTable = GiftModelTable.shared()
	var saved_entries: Array[GiftModelEntry] = table.entries
	table.entries = []
	def.held_scene = packed
	ghost.set_held_gift(&"rocket")
	def.held_scene = previous
	table.entries = saved_entries
	assert_eq(ghost.gift_visual().get_child_count(), 0, "custom scene root, not the fallback crate")


func test_footprint_survives_gift_presentation() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.update_placement(Vector3.ZERO, Vector3.UP)
	var hull_before: int = ghost._rotated_shape_hull().size()
	ghost.set_held_gift(&"rocket")
	assert_eq(ghost._rotated_shape_hull().size(), hull_before)


func test_preview_icon_falls_back_to_generic() -> void:
	assert_eq(SpecialDef.preview_icon_for(&"no_such_gift"), SpecialDef.GENERIC_PREVIEW_ICON)
	var def: SpecialDef = SpecialDef.find_by_id(&"rocket")
	var baked: Texture2D = def.preview_icon
	# Bontago-mp0.125: the model preview outranks the def icon, so hide it for this check.
	var table: GiftIconTable = GiftIconTable.shared()
	var model: Texture2D = table.model_previews[&"rocket"] as Texture2D
	table.model_previews.erase(&"rocket")
	def.preview_icon = null
	assert_eq(SpecialDef.preview_icon_for(&"rocket"), SpecialDef.GENERIC_PREVIEW_ICON)
	var icon: Texture2D = PlaceholderTexture2D.new()
	def.preview_icon = icon
	assert_eq(SpecialDef.preview_icon_for(&"rocket"), icon)
	def.preview_icon = baked
	table.model_previews[&"rocket"] = model


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
	var rocket_icon: Texture2D = GiftIconTable.shared().model_preview(&"rocket")
	assert_not_null(rocket_icon)
	assert_eq(hud.held_gift_icon(), rocket_icon)
	# FakeMatch has no next_special, so the queued gift is the generic placeholder id.
	assert_eq(hud.next_gift_icon(), SpecialDef.GENERIC_PREVIEW_ICON)
	fake.held_special_by_slot.erase(0)
	fake.pending_special_count_by_slot[0] = 0
	hud._refresh_special_indicator()
	assert_null(hud.held_gift_icon())
	assert_null(hud.next_gift_icon())


func test_held_gift_shows_validity_tint() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_held_gift(&"rocket")
	var meshes: Array[Node] = ghost.gift_visual().find_children("*", "MeshInstance3D", true, false)
	var mi: MeshInstance3D = meshes[0] as MeshInstance3D
	var valid_overlay: Material = mi.material_overlay
	assert_false(valid_overlay is StandardMaterial3D, "valid held gift has no white tint overlay (85.33)")
	ghost.set_locked(true)
	assert_true(mi.material_overlay is StandardMaterial3D, "locked gift gets the tint overlay")
	ghost.set_locked(false)
	ghost.apply_validity(PlacementRules.Result.OUTSIDE_TERRITORY)
	assert_true(mi.material_overlay is StandardMaterial3D, "invalid gift gets the tint overlay")
	ghost.apply_validity(PlacementRules.Result.VALID)
	var valid_color: Color = Color.WHITE
	ghost.set_locked(true)
	var locked_color: Color = (mi.material_overlay as StandardMaterial3D).albedo_color
	assert_ne(valid_color, locked_color, "tint follows ghost state")


func test_fallback_crate_is_tinted_too() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_held_gift(&"no_such_gift")
	var mi: MeshInstance3D = ghost.gift_visual().find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	ghost.set_locked(true)
	assert_not_null(mi.material_overlay)


## Bontago-sen.9: a held gift shows no placement projection (footprint quad,
## light-shaft prism, block decal); going back to a plain block restores it.
func test_held_gift_hides_projection_visuals_and_plain_block_restores_them() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.global_position = Vector3(0.0, 3.0, 0.0)
	ghost._update_footprint()
	assert_gt(ghost.footprint_quad_count(), 0, "fixture: plain block has a footprint")
	assert_true(ghost._footprint_quads[0].visible)
	ghost.set_held_gift(&"earthquake")
	ghost._update_footprint()
	for quad: MeshInstance3D in ghost._footprint_quads:
		assert_false(quad.visible, "gift footprint hidden")
	assert_false(ghost._projection_mesh.visible, "gift prism hidden")
	assert_false(ghost.block_projection_decal_visible(), "gift decal hidden")
	ghost.set_held_gift(&"")
	ghost._update_footprint()
	assert_true(ghost._footprint_quads[0].visible, "plain block footprint returns")
	assert_true(ghost._projection_mesh.visible)
