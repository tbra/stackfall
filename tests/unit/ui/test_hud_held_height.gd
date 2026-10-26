extends GutTest
## HUD height line seen from outside: the local held view published through
## MatchContext.local_held() decides whether the line shows the block height. A held view
## with a shape adds "Block: <h> m" to the tower height; the cleared view (nothing held)
## leaves the plain tower height. Nothing reads the ghost node group.

const SLOT: int = 0
const TOWER_M: float = 3.0
const BLOCK_M: float = 12.0
const NEXT_BLOCK_M: float = 7.5
const WAIT_FRAMES: int = 3
const FAR: Vector3 = Vector3(100.0, 100.0, 100.0)

var _saved_context: MatchContext = null
var _fake_context: FakeMatchContext = null
var _shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape


func before_each() -> void:
	Match.abort_match()
	_saved_context = MatchContext.installed()
	_fake_context = FakeMatchContext.new()
	MatchContext.install(_fake_context)


func after_each() -> void:
	MatchContext.install(_saved_context)
	Match.abort_match()


func _publish(shape: BlockShape, height: float, is_visible: bool = true) -> void:
	_fake_context.local_held().publish(SLOT, shape, FAR, 0, Quaternion.IDENTITY, is_visible, height, 0)


func _hud() -> Label:
	var hud: HUD = autofree((load("res://ui/hud/HUD.tscn") as PackedScene).instantiate()) as HUD
	add_child_autofree(hud)
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.max_height_by_slot[SLOT] = TOWER_M
	hud.match_provider = fake_match
	hud.set_local_slot(SLOT)
	return hud.get_node("%HeightLabel") as Label


func test_held_view_height_is_the_block_reading() -> void:
	_publish(_shape, BLOCK_M)
	var label: Label = _hud()
	await wait_process_frames(WAIT_FRAMES)
	assert_string_contains(label.text, "Tower: %.2f m" % TOWER_M)
	assert_string_contains(label.text, "Block: %.1f m" % BLOCK_M)


func test_block_reading_follows_the_view_each_frame() -> void:
	_publish(_shape, BLOCK_M)
	var label: Label = _hud()
	await wait_process_frames(WAIT_FRAMES)
	_publish(_shape, NEXT_BLOCK_M)
	await wait_process_frames(WAIT_FRAMES)
	assert_string_contains(label.text, "Block: %.1f m" % NEXT_BLOCK_M)
	assert_false(label.text.contains("%.1f m" % BLOCK_M), "the stale reading is gone")


func test_null_view_shows_only_the_tower_height() -> void:
	var label: Label = _hud()
	await wait_process_frames(WAIT_FRAMES)
	assert_eq(label.text, "Height: %.2f m" % TOWER_M)
	assert_false(label.text.contains("Block"))


func test_cleared_view_drops_the_block_reading() -> void:
	_publish(_shape, BLOCK_M)
	var label: Label = _hud()
	await wait_process_frames(WAIT_FRAMES)
	_fake_context.local_held().clear()
	await wait_process_frames(WAIT_FRAMES)
	assert_eq(label.text, "Height: %.2f m" % TOWER_M)


func test_view_without_a_shape_shows_no_block_reading() -> void:
	_publish(null, BLOCK_M)
	var label: Label = _hud()
	await wait_process_frames(WAIT_FRAMES)
	assert_eq(label.text, "Height: %.2f m" % TOWER_M)


func test_zero_block_height_is_still_a_reading() -> void:
	_publish(_shape, 0.0)
	var label: Label = _hud()
	await wait_process_frames(WAIT_FRAMES)
	assert_string_contains(label.text, "Block: 0.0 m")
