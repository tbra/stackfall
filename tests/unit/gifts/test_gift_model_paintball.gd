extends GutTest
## Bontago-mp0.160: the paintball is a loaded slingshot; releasing the gift plays its baked
## 'fire' clip on the gift body's visual (every peer builds it through BlockFactory), the held
## ghost visual stays still, and non-paintball gifts are unaffected.

const CLIP: StringName = &"fire_500ms"
const CLIP_LENGTH_S: float = 0.5
const MAX_CLIP_S: float = 1.0

var _tuning: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")


func _body(id: StringName) -> Block:
	var shape: BlockShape = BlockShape.load_all_shapes()[0]
	var block: Block = autofree(BlockFactory.build(shape, _tuning, 0))
	BlockFactory.apply_gift_visual(block, shape, _tuning, id)
	return block


func _player(root: Node) -> AnimationPlayer:
	var found: Array[Node] = root.find_children("*", "AnimationPlayer", true, false)
	return null if found.is_empty() else found[0] as AnimationPlayer


func test_entry_declares_the_fire_clip_and_the_glb_has_it() -> void:
	var entry: GiftModelEntry = GiftModelTable.shared().entry_for(&"paintball")
	assert_eq(entry.activate_animation, CLIP)
	var visual: Node3D = autofree(GiftModelTable.shared().build_gift_visual(&"paintball"))
	var player: AnimationPlayer = _player(visual)
	assert_not_null(player)
	assert_true(player.has_animation(CLIP))
	var length: float = player.get_animation(CLIP).length
	assert_gt(length, 0.0)
	assert_lt(length, MAX_CLIP_S, "a short fire clip")
	assert_almost_eq(length, CLIP_LENGTH_S, 0.1)


func test_held_visual_is_loaded_and_not_playing() -> void:
	var visual: Node3D = autofree(GiftModelTable.shared().build_gift_visual(&"paintball"))
	assert_false(_player(visual).is_playing(), "held slingshot stays loaded")
	assert_not_null(visual.find_child("Blob*", true, false), "the blob is cradled in the pouch")


func test_released_body_plays_the_fire_clip_once() -> void:
	var block: Block = _body(&"paintball")
	var visual: Node = block.get_node(NodePath(BlockFactory.GIFT_VISUAL_NODE))
	var player: AnimationPlayer = _player(visual)
	assert_not_null(player)
	assert_true(player.is_playing())
	assert_eq(player.current_animation, CLIP)
	assert_eq(player.get_animation(CLIP).loop_mode, Animation.LOOP_NONE)


func test_other_gifts_do_not_play_an_activate_clip() -> void:
	var table: GiftModelTable = GiftModelTable.shared()
	for entry: GiftModelEntry in table.entries:
		if entry.id != &"paintball":
			assert_eq(entry.activate_animation, &"", "%s" % entry.id)
	assert_false(table.play_activate_animation(&"bomb", autofree(Node3D.new())))
