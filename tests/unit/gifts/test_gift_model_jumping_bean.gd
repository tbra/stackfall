extends GutTest
## the Jumping Bean gift is a jelly blob on a coil spring (not a bean),
## keeps its face, its gameplay id and its idle hop loop.


func _names(root: Node) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for node: Node in root.find_children("*", "", true, false):
		out.append(String(node.name).to_lower())
	return out


func _has_part(names: PackedStringArray, part: String) -> bool:
	for n: String in names:
		if n.contains(part):
			return true
	return false


func test_table_row_uses_the_spring_blob_model_and_keeps_the_hop_loop() -> void:
	var entry: GiftModelEntry = GiftModelTable.shared().entry_for(&"jumping_bean")
	assert_not_null(entry)
	assert_true(entry.scene.resource_path.contains("assets/models/gifts/jumping_bean.glb"), "the shipped jumping_bean model (version suffix dropped by P10)")
	assert_eq(entry.loop_animation, &"idle_hop_1p5s")


func test_model_has_blob_spring_and_face_but_no_bean_body() -> void:
	var visual: Node3D = autofree(GiftModelTable.shared().build_gift_visual(&"jumping_bean"))
	assert_not_null(visual)
	var names: PackedStringArray = _names(visual)
	for part: String in ["spring", "jelly", "eye", "pupil", "cheek", "smile"]:
		assert_true(_has_part(names, part), "has %s" % part)
	for n: String in names:
		assert_false(n.begins_with("bean"), "no bean body part: %s" % n)


func test_hop_clip_plays_and_loops() -> void:
	var visual: Node3D = autofree(GiftModelTable.shared().build_gift_visual(&"jumping_bean"))
	var player: AnimationPlayer = GiftModelTable._player_of(visual)
	assert_not_null(player)
	assert_true(player.has_animation(&"idle_hop_1p5s"))
	assert_eq(player.current_animation, "idle_hop_1p5s")
	assert_eq(player.get_animation(&"idle_hop_1p5s").loop_mode, Animation.LOOP_LINEAR)
