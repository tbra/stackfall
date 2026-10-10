class_name SearchingCells
extends Control
## Three pulsing mint cells under a "Searching for games..." line (components.md ServerRow:
## "Empty list: one dust line ... with three pulsing cells"; Bontago-1pi.149). Purely
## decorative: it draws, takes no input and only animates while it is visible in the tree.
## Cell size and gap reuse the LoadingCard's (config/loading_screen_tuning.tres).

const LOADING_TUNING: LoadingScreenTuning = preload("res://config/loading_screen_tuning.tres")
## DECISION (Bontago-1pi.149): the pulse values are presentation constants of this one
## decorative widget, not gameplay tunables: three cells, one full pulse per PULSE_PERIOD_SEC,
## each cell a third of a period behind the last, alpha swinging between MIN_ALPHA and 1.
const CELL_COUNT: int = 3
const PULSE_PERIOD_SEC: float = 1.2
const MIN_ALPHA: float = 0.25
const MSEC_PER_SEC: float = 1000.0

var _arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(row_width(), float(LOADING_TUNING.loading_cell_height_px))
	size = custom_minimum_size
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


static func row_width() -> float:
	return float(CELL_COUNT * (LOADING_TUNING.loading_cell_width_px + LOADING_TUNING.loading_cell_gap_px)
		- LOADING_TUNING.loading_cell_gap_px)


## Alpha of cell `index` at `time_sec` (a testable pure function of time).
static func cell_alpha(index: int, time_sec: float) -> float:
	var phase: float = fposmod(time_sec / PULSE_PERIOD_SEC - float(index) / float(CELL_COUNT), 1.0)
	var wave: float = 0.5 + 0.5 * cos(phase * TAU)
	return lerpf(MIN_ALPHA, 1.0, wave)


func _on_visibility_changed() -> void:
	set_process(is_visible_in_tree())
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.set_corner_radius_all(_arcade.radius_cell_px)
	var time_sec: float = float(Time.get_ticks_msec()) / MSEC_PER_SEC
	var cell_size: Vector2 = Vector2(float(LOADING_TUNING.loading_cell_width_px), float(LOADING_TUNING.loading_cell_height_px))
	for index: int in range(CELL_COUNT):
		box.bg_color = Color(_arcade.mint_color, cell_alpha(index, time_sec))
		var origin: Vector2 = Vector2(float(index * (LOADING_TUNING.loading_cell_width_px + LOADING_TUNING.loading_cell_gap_px)), 0.0)
		draw_style_box(box, Rect2(origin, cell_size))
