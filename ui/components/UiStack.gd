class_name UiStack
extends VBoxContainer
## Bontago-1pi.159.12: a vertical stack whose row gap comes from a config value, so screens set
## `gap_px` instead of a per-node theme override (lint_ui_components R2). The override lives here,
## inside ui/components, the one place allowed to style through the theme API.

## Pixels between rows (the VBoxContainer "separation" constant).
var gap_px: int = 0:
	set(value):
		gap_px = value
		add_theme_constant_override("separation", value)
