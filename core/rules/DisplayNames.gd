class_name DisplayNames
extends RefCounted
## Single source of player-facing mode / map / sky / weather / gift labels.
## Pure statics, no scene tree. Unknown ids return a
## stable fallback, never "". Plain strings, so adding tr() later is a one-file change.

## Shown when an index or id has no label.
const UNKNOWN_LABEL: String = "Unknown"
## The placeholder gift id (SpecialIds.PENDING) reads as this.
const PENDING_SPECIAL_LABEL: String = "Special"


static func mode(mode_id: int) -> String:
	return _pick(MatchConfig.GAME_MODE_LABELS, mode_id)


static func weather(index: int) -> String:
	return _enum_label(MatchConfig.WeatherMode, index)


## Lower-case enum key of a WeatherMode (matches config/weather/<id>.tres); "" when out of range.
static func weather_key(index: int) -> StringName:
	var label: String = _enum_label(MatchConfig.WeatherMode, index)
	if label == UNKNOWN_LABEL:
		return &""
	return StringName(label.to_lower())


## Capitalised weather id, the fallback when a WeatherTuning has no display_name.
static func weather_id_label(weather_id: StringName) -> String:
	return String(weather_id).capitalize()


## SpecialDef.display_name (fallback: capitalised id) for a known gift; the pending
## placeholder and an empty id are "Special" (as HUD shows them); an unknown id is its capitalised id.
static func special(special_id: StringName) -> String:
	if special_id == SpecialIds.PENDING or special_id == &"":
		return PENDING_SPECIAL_LABEL
	var def: SpecialDef = SpecialDef.find_by_id(special_id)
	if def != null:
		return def.get_display_name()
	return SpecialDef.name_from_id(special_id)


static func _pick(table: PackedStringArray, index: int) -> String:
	if index >= 0 and index < table.size():
		return table[index]
	return UNKNOWN_LABEL


static func _enum_label(enum_dict: Dictionary, value: int) -> String:
	var keys: Array = enum_dict.keys()
	for key: Variant in keys:
		if int(enum_dict[key]) == value:
			return String(key).capitalize()
	return UNKNOWN_LABEL
