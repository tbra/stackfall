extends GutTest
## Bontago-mp0.163: the volcano GLB carries a looping smoke clip, and the large spawned
## volcano reuses the same model (smoke excluded from its footprint fit).

const CLIP: StringName = &"smoke_rise_2s"


func _smoke_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in root.find_children("Smoke*", "MeshInstance3D", true, false):
		out.append(node)
	return out


func test_held_volcano_has_a_playing_smoke_loop() -> void:
	var entry: GiftModelEntry = GiftModelTable.shared().entry_for(&"volcano")
	assert_eq(entry.loop_animation, CLIP)
	var visual: Node3D = autofree(GiftModelTable.shared().build_gift_visual(&"volcano"))
	assert_gt(_smoke_nodes(visual).size(), 1, "several smoke puffs")
	var player: AnimationPlayer = GiftModelTable._player_of(visual)
	assert_not_null(player)
	assert_eq(player.current_animation, String(CLIP))
	var clip: Animation = player.get_animation(CLIP)
	assert_eq(clip.loop_mode, Animation.LOOP_LINEAR)
	assert_between(clip.length, 1.5, 2.5, "about two seconds")


func test_spawned_volcano_uses_the_same_model_glb() -> void:
	var def: SpecialDef = SpecialDef.find_by_id(&"volcano")
	var effect: VolcanoEffect = def.effect as VolcanoEffect
	assert_not_null(effect)
	var entry: GiftModelEntry = GiftModelTable.shared().entry_for(&"volcano")
	assert_eq(effect.model_scene.resource_path, entry.scene.resource_path)


func test_smoke_does_not_change_the_fitted_footprint_or_height() -> void:
	var def: SpecialDef = SpecialDef.find_by_id(&"volcano")
	var effect: VolcanoEffect = def.effect as VolcanoEffect
	var model: Node3D = autofree(effect.model_scene.instantiate() as Node3D)
	var bounds: AABB = VolcanoStructure._model_bounds(model, Transform3D.IDENTITY)
	# The cone + base rocks + lava, without smoke, top out below the puffs' start height.
	assert_lt(bounds.end.y, 0.35, "bounds ignore the smoke rising above the crater")
	assert_gt(bounds.size.y, 0.4)
