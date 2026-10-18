class_name LoadingTipTable
extends Resource
## The tips ui/menus/LoadingScreen.gd shows, one per load. Wording is input-agnostic: no
## key or button names, so it reads the same on keyboard, mouse and gamepad.

## One or two short sentences each, at most max_tip_length characters.
@export var tips: PackedStringArray = PackedStringArray()

## Longest tip the loading card is laid out for.
@export var max_tip_length: int = 110

## Width of the tip text in the loading card, in px.
@export var tip_width_px: int = 420


## Index of the tip to show. `roll` is any non-negative random integer; the result never
## equals `previous` unless there is only one tip. -1 when the table is empty.
func pick_index(previous: int, roll: int) -> int:
	var count: int = tips.size()
	if count == 0:
		return -1
	if count == 1:
		return 0
	if previous < 0 or previous >= count:
		return roll % count
	var index: int = roll % (count - 1)
	return index + 1 if index >= previous else index
