class_name InputGlyphTable
extends Resource
## Stick direction, stick click and chord (combo) glyph art for ui/InputGlyph
## (assets/ui/input_glyphs, Bontago-mp0.105 art, wired by Bontago-mp0.124).
## Loaded as config/input_glyph_table.tres. Gamepad-only: InputGlyph is only fed
## gamepad events while the gamepad prompt family is active, so keyboard/mouse
## prompts never reach this table.
##
## Keys: stick_directions "<left|right>_<up|down|left|right>"; stick_clicks
## "left"/"right"; combos are the sorted component ids joined by "+"
## (InputGlyph.pad_component_id(): lb, rb, lt, rt, stick_left, stick_right, ...).
## Not an F4 tuning panel resource (no hints entry needed).

const TABLE_PATH: String = "res://config/input_glyph_table.tres"

@export var stick_directions: Dictionary = {}
@export var stick_clicks: Dictionary = {}
@export var combos: Dictionary = {}

static var _shared: InputGlyphTable = null


static func shared() -> InputGlyphTable:
	if _shared == null:
		_shared = load(TABLE_PATH) as InputGlyphTable
	return _shared


func stick_direction(side: StringName, direction: StringName) -> Texture2D:
	return stick_directions.get("%s_%s" % [side, direction]) as Texture2D


func stick_click(side: StringName) -> Texture2D:
	return stick_clicks.get(side) as Texture2D


## Combo art for component ids in any order, or null when none is authored.
func combo(component_ids: PackedStringArray) -> Texture2D:
	var sorted: Array = Array(component_ids)
	sorted.sort()
	return combos.get("+".join(PackedStringArray(sorted))) as Texture2D
