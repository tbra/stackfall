extends GutTest
## while a claimed gift is the current piece the ghost shows a
## held-gift presentation instead of the plain block, and the HUD held/next
## previews draw the gift icon (or the generic fallback).


func _make_ghost() -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	return ghost


func _block_meshes_visible(ghost: GhostPreview) -> bool:
	var any_visible: bool = false
	for child: Node in GhostParts.shape_visual(ghost).get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance != null and mesh_instance.visible:
			any_visible = true
	return any_visible


func test_ghost_switches_to_gift_visual_and_back() -> void:
	var ghost: GhostPreview = _make_ghost()
	assert_null(GhostParts.gift_visual(ghost))
	assert_true(_block_meshes_visible(ghost))
	ghost.set_held_gift(&"rocket")
	assert_not_null(GhostParts.gift_visual(ghost), "fallback gift visual is shown")
	assert_false(_block_meshes_visible(ghost), "plain block mesh hidden")
	ghost.set_held_gift(&"")
	assert_null(GhostParts.gift_visual(ghost))
	assert_true(_block_meshes_visible(ghost), "plain block ghost restored")


## gifts are never recoloured; no ghost state tints one.
func test_held_gift_is_never_tinted_in_any_state() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_held_gift(&"rocket")
	var meshes: Array[Node] = GhostParts.gift_visual(ghost).find_children("*", "MeshInstance3D", true, false)
	var mi: MeshInstance3D = meshes[0] as MeshInstance3D
	assert_null(mi.material_overlay, "valid")
	ghost.set_locked(true)
	assert_null(mi.material_overlay, "locked")
	ghost.set_locked(false)
	ghost.apply_validity(PlacementRules.Result.OUTSIDE_TERRITORY)
	assert_null(mi.material_overlay, "invalid")


## a held gift shows no placement projection (footprint quad,
## light-shaft prism, block decal); going back to a plain block restores it.
func test_held_gift_hides_projection_visuals_and_plain_block_restores_them() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.update_placement(Vector3(0.0, 3.0, 0.0))
	var quads: Array[MeshInstance3D] = GhostParts.footprint_quads(ghost)
	assert_gt(quads.size(), 0, "fixture: plain block has a footprint")
	assert_true(quads[0].visible)
	assert_true(GhostParts.decal(ghost).visible, "fixture: plain block over a gap has a decal")
	ghost.set_held_gift(&"earthquake")
	ghost.update_placement(Vector3(0.0, 3.0, 0.0))
	for quad: MeshInstance3D in GhostParts.footprint_quads(ghost):
		assert_false(quad.visible, "gift footprint hidden")
	assert_false(GhostParts.prism(ghost).visible, "gift prism hidden")
	assert_false(GhostParts.decal(ghost).visible, "gift decal hidden")
	ghost.set_held_gift(&"")
	ghost.update_placement(Vector3(0.0, 3.0, 0.0))
	assert_true(GhostParts.footprint_quads(ghost)[0].visible, "plain block footprint returns")
	assert_true(GhostParts.prism(ghost).visible)
	assert_true(GhostParts.decal(ghost).visible, "plain block decal returns")
