extends GutTest
## Bontago-mp0.119: the Codex 3D gift models are loaded through
## config/gift_model_table.tres and actually instanced by the crate, its
## claim reveal, the held ghost and the cat.

const SPECIAL_IDS: Array[StringName] = [
	&"anvil", &"black_hole", &"bomb", &"cat", &"earthquake", &"freeze", &"glue",
	&"jumping_bean", &"magnet", &"paintball", &"propeller", &"rocket", &"stackfall", &"volcano",
]
const CELL_LIMIT: float = 1.01


func _bounds(root: Node3D) -> AABB:
	var bounds: AABB = AABB()
	var first: bool = true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		var xform: Transform3D = Transform3D.IDENTITY
		var walker: Node = mi
		while walker != root and walker != null:
			xform = (walker as Node3D).transform * xform
			walker = walker.get_parent()
		var box: AABB = xform * mi.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


func test_table_has_every_special_model_and_fits_one_cell() -> void:
	var table: GiftModelTable = GiftModelTable.shared()
	assert_not_null(table)
	for id: StringName in SPECIAL_IDS:
		var visual: Node3D = table.build_gift_visual(id)
		assert_not_null(visual, "%s model loads" % id)
		if visual == null:
			continue
		autofree(visual)
		var size: Vector3 = _bounds(visual).size
		assert_gt(size.length(), 0.1, "%s has geometry" % id)
		assert_lt(maxf(size.x, maxf(size.y, size.z)), CELL_LIMIT, "%s fits one cell" % id)


func test_crate_and_reveal_models_load() -> void:
	var table: GiftModelTable = GiftModelTable.shared()
	var crate: Node3D = autofree(table.build_crate_visual())
	var reveal: Node3D = autofree(table.build_reveal_visual())
	assert_not_null(crate)
	assert_not_null(reveal)
	assert_lt(_bounds(crate).size.y, 0.65, "crate body fits the 0.6 collision box")
	var player: AnimationPlayer = GiftModelTable._player_of(reveal)
	assert_not_null(player)
	assert_eq(player.current_animation, String(table.reveal_animation))


func test_crate_node_instances_the_model_and_keeps_its_collision() -> void:
	var crate: GiftCrate = autofree(GiftCrate.new())
	add_child_autofree(crate)
	var model: Node = crate.get_node_or_null("Mesh")
	assert_not_null(model)
	assert_gt(model.find_children("*", "MeshInstance3D", true, false).size(), 1, "multi-part crate model")
	var shape: CollisionShape3D = crate.get_node("Collision") as CollisionShape3D
	assert_eq((shape.shape as BoxShape3D).size, GiftCrate.CRATE_SIZE)


func test_claim_pop_uses_the_reveal_model() -> void:
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	GiftCrate.spawn_claim_pop(parent, Vector3.ZERO, Color.RED, load("res://config/gift_config.tres") as GiftConfig)
	var pop: Node3D = parent.get_node("GiftClaimPop") as Node3D
	assert_not_null(pop.get_child(0) as MeshInstance3D, "slot-coloured core stays child 0")
	assert_not_null(pop.get_node_or_null("GiftModel"), "reveal model is instanced")


func test_held_ghost_shows_the_model_for_every_special() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	for id: StringName in SPECIAL_IDS:
		ghost.set_held_gift(id)
		var visual: Node3D = ghost.gift_visual()
		assert_not_null(visual, String(id))
		assert_eq(visual.name, &"HeldGift")
		assert_eq(visual.get_child_count(), 1, "%s: GLB wrapper only" % id)
		var entry: GiftModelEntry = GiftModelTable.shared().entry_for(id)
		assert_eq(visual.get_child(0).scene_file_path, entry.scene.resource_path, "%s uses the table model" % id)


func test_cat_controller_uses_the_cat_model() -> void:
	var cat: CatController = autofree(CatController.new())
	add_child_autofree(cat)
	assert_not_null(cat.get_node_or_null("CatModel"))
