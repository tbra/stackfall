class_name OptionHelpTable
extends Resource
## The explanation shown in a UiHelpLine for each unclear lobby / Options row (Bontago-1pi.159.35,
## owner 2026-10-12: "explanation of options next to them when unclear ... instead of tooltips").
## Screens only tag a row with a key ([method UiHelpLine.tag]); every sentence lives in
## config/ui/option_help_table.tres. A row with no entry shows no help. Keys are the row's node name
## (lobby), its unique name (Options Game / Controls), or the GraphicsPreset field (Graphics).
## A row whose items differ (a cycler / dropdown) may add "<key>/<item index>" entries that
## replace the row text while that item is shown.

const RESOURCE_PATH: String = "res://config/ui/option_help_table.tres"
const ITEM_KEY_FORMAT: String = "%s/%d"
## Gift chips are tagged "gift_<special id>".
const GIFT_KEY_PREFIX: String = "gift_"

static var _shared: OptionHelpTable = null

## key -> one sentence.
@export var entries: Dictionary[String, String] = {}
## The help line always keeps this many text lines of height, so showing / clearing a hint never
## moves the rows around it.
@export var reserved_lines: int = 1


static func shared() -> OptionHelpTable:
	if _shared == null:
		_shared = load(RESOURCE_PATH) as OptionHelpTable
	return _shared


static func release_shared() -> void:
	_shared = null


static func gift_key(special_id: StringName) -> String:
	return GIFT_KEY_PREFIX + String(special_id)


## The text for [param key], preferring the "<key>/<item>" entry when [param item] >= 0 and one
## exists. "" when the key has no text at all.
func text_for(key: String, item: int = -1) -> String:
	if item >= 0:
		var item_key: String = ITEM_KEY_FORMAT % [key, item]
		if entries.has(item_key):
			return entries[item_key]
	return entries.get(key, "")


func has_text(key: String) -> bool:
	return entries.has(key)
