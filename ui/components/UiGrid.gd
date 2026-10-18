class_name UiGrid
extends GridContainer
## a grid whose horizontal and vertical gaps come from config values, so screens set `h_gap_px` / `v_gap_px`
## instead of per-node theme overrides (lint_ui_components R2). The overrides live here, inside ui/components.

## Pixels between cells on a line (the "h_separation" constant).
var h_gap_px: int = 0:
	set(value):
		h_gap_px = value
		add_theme_constant_override(&"h_separation", value)
## Pixels between lines (the "v_separation" constant).
var v_gap_px: int = 0:
	set(value):
		v_gap_px = value
		add_theme_constant_override(&"v_separation", value)
