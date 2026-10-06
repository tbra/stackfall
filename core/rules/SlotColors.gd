class_name SlotColors
extends RefCounted
## Single owner of "what colour is this slot" (Bontago-1pi.86 D1). Pure statics, no
## scene tree. Precedence: the live PlayerSlot.color, else the palette entry for the
## slot, else the caller's fallback. The runtime accessor is Match.slot_color();
## a UI with a test seam passes its own slot colour and palette to resolve().


## `live_color` is the slot's own colour (a Color) or null when no PlayerSlot exists.
static func resolve(slot_id: int, live_color: Variant, palette: PackedColorArray, fallback: Color = Color.WHITE) -> Color:
	if live_color is Color:
		return live_color as Color
	return palette_color(slot_id, palette, fallback)


## palette[index], or `fallback` when the index is out of range.
static func palette_color(index: int, palette: PackedColorArray, fallback: Color = Color.WHITE) -> Color:
	if index >= 0 and index < palette.size():
		return palette[index]
	return fallback


## palette entry for the slot, wrapping when there are more slots than colours.
static func wrapped_color(index: int, palette: PackedColorArray, fallback: Color = Color.WHITE) -> Color:
	if palette.is_empty():
		return fallback
	return palette[posmod(index, palette.size())]
