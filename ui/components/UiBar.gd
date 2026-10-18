class_name UiBar
extends HBoxContainer
## a horizontal bar whose gap comes from a config value, so screens set `gap_px` instead of a per-node theme
## override (lint_ui_components R2). The override lives here, inside ui/components.

## Pixels between items (the HBoxContainer "separation" constant).
var gap_px: int = 0:
	set(value):
		gap_px = value
		add_theme_constant_override("separation", value)
