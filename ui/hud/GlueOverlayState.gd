class_name GlueOverlayState
extends RefCounted
## Whether the HUD's held/next block previews wear the glue jelly tint. The HUD sets it
## from the local slot's remaining Glue charges and clears it on leaving a match, then
## queries `active` on every preview draw.

var active: bool = false


## Returns true when the value changed (the previews need a redraw).
func set_active(value: bool) -> bool:
	if value == active:
		return false
	active = value
	return true
