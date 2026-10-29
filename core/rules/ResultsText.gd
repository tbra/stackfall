class_name ResultsText
extends RefCounted
## Results-screen wording and ordering from a results dictionary; pure and static.
## Stub: bodies return the null answers.


static func winner_ids(_results: Dictionary) -> PackedInt32Array:
	return PackedInt32Array()


static func shared_winners_text(_results: Dictionary, _team_numbers: PackedInt32Array = PackedInt32Array()) -> String:
	return ""


static func mode_outcome_text(_results: Dictionary, _team_numbers: PackedInt32Array = PackedInt32Array()) -> String:
	return ""


static func mode_title(_results: Dictionary) -> String:
	return ""


static func has_mode_stat(_results: Dictionary) -> bool:
	return false


static func player_label(_results: Dictionary, _slot_id: int) -> String:
	return ""


static func row_name_text(_row: Dictionary, _difficulty_label: String = "") -> String:
	return ""


static func team_number_in(_team_numbers: PackedInt32Array, _team_id: int) -> int:
	return -1


static func survivor_text(_alive: int) -> String:
	return ""


static func sorted_rows(_results: Dictionary) -> Array[Dictionary]:
	return []


static func mode_stat_header(_results: Dictionary) -> String:
	return ""


static func mode_stat_text(_results: Dictionary, _row: Dictionary) -> String:
	return ""
