class_name ScoreboardOverlay
extends CanvasLayer
## Bontago-1pi.69 (owner playtest: "a glanceable score tracker players can bring
## up during the game ... tab / r-stick click by default (shows while held down)").
##
## Shown while the `show_scores` action is held during a live round, hidden on
## release, focus loss, pause, a non-live state or a sandbox. It draws the same
## table as the results screen (ui/ScoreTable.gd) from MatchStats.live_payload():
## the host's own counters, or on a client the snapshot the host replicates
## (net/MatchNet.gd EVENT_LIVE_SCORES). Display only; no input is consumed.

## Above the HUD, below the pause menu / loading screen.
const SCOREBOARD_LAYER: int = 20

@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")

## Test seam (Variant): defaults to the Match autoload; needs state(), stats()
## (with live_payload()) and `config`.
var match_provider: Variant = null
## game/Main.gd sets this true while a sandbox is running: there Tab keeps its
## sandbox_next_slot meaning and no scoreboard exists (DECISION, Bontago-1pi.69).
var suppressed: bool = false

var _holding: bool = false
var _paused: bool = false
var _last_rows: Array = []
var _last_mode: Variant = null

@onready var _root: Control = %Root
@onready var _card: PanelContainer = %Card
@onready var _mode_title: Label = %ModeTitle
@onready var _mode_outcome: Label = %ModeOutcome
@onready var _rows_list: VBoxContainer = %RowsList


func _ready() -> void:
	layer = SCOREBOARD_LAYER
	if match_provider == null:
		match_provider = Match
	_card.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(tuning.card_cream_color, tuning))
	_root.visible = false
	_mode_title.add_theme_font_size_override("font_size", tuning.score_card_title_font_size)
	_refresh_layout()
	get_viewport().size_changed.connect(_refresh_layout)
	Events.pause_menu_opened.connect(_on_pause_opened)
	Events.pause_menu_closed.connect(_on_pause_closed)
	Events.match_state_changed.connect(_on_match_state_changed)
	Events.match_scope_reset.connect(release)


func _refresh_layout() -> void:
	var available: Vector2 = get_viewport().get_visible_rect().size - Vector2.ONE * tuning.menu_edge_margin_px * 2.0
	_card.custom_minimum_size.x = minf(available.x, tuning.menu_max_width_px)


func is_showing() -> bool:
	return _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"show_scores", false, true):
		# tools/bootstrap_project.gd: the pad half is R3, which also completes the
		# debug perf-overlay chord (Back held + R3, ui/PerfOverlay.gd); that chord
		# must not also pop the scoreboard.
		if event is InputEventJoypadButton and Input.is_action_pressed(&"camera_snap_home"):
			return
		_holding = true
		_update_visibility()
	elif event.is_action_released(&"show_scores", true):
		release()


## Drops the hold and hides (release, focus loss, pause, scope reset).
func release() -> void:
	_holding = false
	_update_visibility()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release()


func _process(_delta: float) -> void:
	if _holding and not Input.is_action_pressed(&"show_scores"):
		_holding = false
	_update_visibility()
	if _root.visible:
		_refresh_table()


func _on_pause_opened() -> void:
	_paused = true
	release()


func _on_pause_closed() -> void:
	_paused = false


func _on_match_state_changed(_from_state: int, _to_state: int) -> void:
	_update_visibility()


func _can_show() -> bool:
	if suppressed or _paused or not _holding or match_provider == null:
		return false
	return MatchLifecycle.is_live_state(match_provider.state())


func _update_visibility() -> void:
	var show_now: bool = _can_show()
	if show_now and not _root.visible:
		_last_rows = []
		_last_mode = null
		_refresh_table()
	_root.visible = show_now


## Rebuilds the table only when the snapshot's rows or mode block changed
## (the match clock alone changes every frame).
func _refresh_table() -> void:
	var payload: Dictionary = match_provider.stats().live_payload()
	if payload.is_empty():
		return
	var rows: Array = ResultsPayload.rows(payload)
	var mode: Variant = payload.get(ResultsPayload.KEY_MODE)
	if rows == _last_rows and mode == _last_mode:
		return
	_last_rows = rows.duplicate(true)
	_last_mode = mode
	var config: MatchConfig = match_provider.config as MatchConfig
	var team_numbers: PackedInt32Array = PackedInt32Array()
	if config != null and config.teams_resolved():
		team_numbers = config.team_numbers
	_mode_title.text = ResultsScreen.mode_title(payload)
	ScoreTable.populate(_rows_list, payload, tuning, team_numbers, match_provider)
	var outcome: String = ResultsScreen.mode_outcome_text(payload, team_numbers).strip_edges()
	_mode_outcome.text = outcome
	_mode_outcome.visible = not outcome.is_empty()
