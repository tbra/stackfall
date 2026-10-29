extends GutTest
## HudGiftSlot: the held-gift column beside the held/next piece row. It shows the special's
## name and a count while a gift is held, nothing when the head id is empty, and repeating
## the same refresh changes nothing visible.

const GIFT: StringName = &"rocket"
const OTHER_GIFT: StringName = &"bomb"
const CARD_SIZE: Vector2 = Vector2(72.0, 96.0)

var _row: HBoxContainer
var _slot: HudGiftSlot


func before_each() -> void:
	_row = HBoxContainer.new()
	var card: Panel = Panel.new()
	card.custom_minimum_size = CARD_SIZE
	_row.add_child(card)
	add_child_autofree(_row)
	_slot = HudGiftSlot.new(_row, card, load("res://config/ui/arcade_visual_tuning.tres") as ArcadeVisualTuning)


func _visible_texts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for node: Node in _row.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.is_visible_in_tree() and not label.text.is_empty():
			out.append(label.text)
	return out


func _shows(fragment: String) -> bool:
	for text: String in _visible_texts():
		if text.contains(fragment):
			return true
	return false


func test_a_held_gift_shows_its_name() -> void:
	_slot.refresh(GIFT, 1)
	var gift_name: String = DisplayNames.special(GIFT)
	assert_ne(gift_name, DisplayNames.special(&""), "fixture: the id is a real special")
	assert_true(_shows(gift_name))


func test_more_than_one_gift_shows_the_count() -> void:
	_slot.refresh(GIFT, 3)
	assert_true(_shows("3"))
	_slot.refresh(GIFT, 5)
	assert_true(_shows("5"))
	assert_false(_shows("3"))


func test_empty_head_hides_the_slot_even_with_a_stale_count() -> void:
	_slot.refresh(GIFT, 2)
	assert_gt(_visible_texts().size(), 0)
	_slot.refresh(&"", 4)
	assert_eq(_visible_texts().size(), 0)


func test_gift_spent_hides_the_slot() -> void:
	_slot.refresh(GIFT, 2)
	assert_gt(_visible_texts().size(), 0)
	_slot.refresh(&"", 0)
	assert_eq(_visible_texts().size(), 0)
	assert_false(_shows(DisplayNames.special(GIFT)))


func test_a_different_head_replaces_the_name() -> void:
	_slot.refresh(GIFT, 1)
	_slot.refresh(OTHER_GIFT, 1)
	assert_true(_shows(DisplayNames.special(OTHER_GIFT)))
	assert_false(_shows(DisplayNames.special(GIFT)))


func test_repeating_the_same_refresh_is_idempotent() -> void:
	_slot.refresh(GIFT, 2)
	var before: PackedStringArray = _visible_texts()
	assert_gt(before.size(), 0)
	_slot.refresh(GIFT, 2)
	assert_eq(_visible_texts(), before)
	_slot.refresh(GIFT, 2, true)
	assert_eq(_visible_texts(), before, "force redraws without changing what is shown")


func test_repeating_an_empty_refresh_stays_hidden() -> void:
	_slot.refresh(GIFT, 1)
	assert_gt(_visible_texts().size(), 0)
	_slot.refresh(&"", 0)
	_slot.refresh(&"", 0)
	assert_eq(_visible_texts().size(), 0)
