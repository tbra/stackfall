class_name ReadyPill
extends UiStatusBadge
## The icon-only Ready / Not ready tile (Bontago-1pi.94 S3): a mint badge with a tick when ready,
## a dark one with an hourglass otherwise, the words kept as the accessible tooltip. Since
## Bontago-1pi.159.4 this is a thin wrapper over ui/components/UiStatusBadge.gd (icon_only, look
## READY / NOT_READY); it only keeps the `create` / `set_ready` / `is_ready` API the lobby's seat
## rows (ui/lobby/LobbySeatRow.gd) and the loading screen's player rows (ui/LoadingScreen.gd)
## call, so both draw the exact same component.

var is_ready: bool = false


## The accessible text of a Ready / Not ready pill (the pill itself shows only its icon).
static func tooltip_for(ready: bool) -> String:
	return "Ready" if ready else "Not ready"


## [param min_size] sizes the tile (the loading screen's is smaller than the row height so eight
## rows fit); [param margin_y_px] >= 0 overrides the vertical content margin.
static func create(ready: bool, min_size: Vector2, margin_y_px: float = -1.0) -> ReadyPill:
	var pill: ReadyPill = ReadyPill.new()
	pill.icon_only = true
	pill.pad_y_override_px = margin_y_px
	pill.custom_minimum_size = min_size
	pill.set_ready(ready)
	return pill


## Restyles the pill for the new state (cheap; callers may call it every refresh).
func set_ready(ready: bool) -> void:
	is_ready = ready
	variant = Look.READY if ready else Look.NOT_READY
	text = tooltip_for(ready)
