extends GutTest
## RejectMessageTable: every refusal reason has a plain sentence, unknown ids fall back.

const TABLE_PATH: String = "res://config/ui/reject_message_table.tres"


func _table() -> RejectMessageTable:
	return load(TABLE_PATH) as RejectMessageTable


func _all_reasons() -> Array[StringName]:
	return [
		PlacementRules.REASON_OUTSIDE_TERRITORY, PlacementRules.REASON_CONTESTED,
		PlacementRules.REASON_HOLE, PlacementRules.REASON_OFF_DISK,
		PlacementRules.REASON_EMPTY, PlacementRules.REASON_GOAL_ZONE,
		PlacementRules.REASON_NOT_YOUR_TURN, PlacementRules.REASON_NO_BLOCK,
		ThrowRules.REASON_NOT_A_SPECIAL,
	]


func test_every_reason_has_a_sentence() -> void:
	var table: RejectMessageTable = _table()
	for reason: StringName in _all_reasons():
		assert_true(table.has_message(reason), "missing message for %s" % reason)
		var text: String = table.message_for(reason)
		assert_ne(text, table.fallback_message, "%s uses the fallback" % reason)
		assert_false(text.contains("—"), "no em dash in %s" % reason)
		assert_false(text.contains("_"), "no raw id in %s" % reason)


func test_every_placement_rules_reason_constant_is_covered() -> void:
	var table: RejectMessageTable = _table()
	var consts: Dictionary = (PlacementRules as Script).get_script_constant_map()
	for key: String in consts:
		if not key.begins_with("REASON_") or key == "REASON_OK":
			continue
		assert_true(table.has_message(consts[key] as StringName), "no entry for %s" % key)


func test_unknown_reason_falls_back() -> void:
	var table: RejectMessageTable = _table()
	assert_false(table.has_message(&"made_up"))
	assert_eq(table.message_for(&"made_up"), table.fallback_message)
	assert_ne(table.fallback_message, "")
