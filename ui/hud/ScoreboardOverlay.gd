class_name ScoreboardOverlay
extends CanvasLayer
## A glanceable score tracker players can bring up during the game: tab / r-stick click
## by default (shows while held down).
##
## Shown while the `show_scores` action is held during a live round, hidden on
## release, focus loss, pause, a non-live state or a sandbox. It draws the same
## table as the results screen (ui/menus/ScoreTable.gd) from the context's stats().live_payload():
## the host's own counters, or on a client the snapshot the host replicates
## (MatchWireEvents.LIVE_SCORES via net/MatchEventApplier.gd). Display only; no input is consumed.

## Above the HUD, below the pause menu / loading screen.
const SCOREBOARD_LAYER: int = 20

@export var tuning: MenuVisualTuning = preload("res://config/ui/menu_visual_tuning.tres")

## The match port the scoreboard reads (state, config, live stats); the builder assigns it.
var match_context: MatchContext = MatchContext.new()
## game/main/Main.gd sets this true while a sandbox is running: there Tab keeps its
## sandbox_next_slot meaning and no scoreboard exists (DECISION).
var suppressed: bool = false

var _holding: bool = false
var _paused: bool = false
var _last_rows: Array = []
var _last_mode: Variant = null
## Chat mute strip: one toggle per remote player, built while a chat session runs.
var _mute_box: HFlowContainer = null
var _mute_peers: PackedInt32Array = PackedInt32Array()
var _mute_buttons: Dictionary = {}

const MUTE_TEXT: String = "Mute %s"
const UNMUTE_TEXT: String = "Unmute %s"
## Names longer than this are cut in the button so the strip stays one tidy row.
const MUTE_NAME_MAX_CHARS: int = 14

@onready var _root: Control = %Root
@onready var _card: PanelContainer = %Card
@onready var _mode_title: Label = %ModeTitle
@onready var _mode_outcome: Label = %ModeOutcome
@onready var _rows_list: VBoxContainer = %RowsList


func _ready() -> void:
	layer = SCOREBOARD_LAYER
	_apply_visual_style()
	_root.visible = false
	_refresh_layout()
	get_viewport().size_changed.connect(_refresh_layout)
	Events.pause_menu_opened.connect(_on_pause_opened)
	Events.pause_menu_closed.connect(_on_pause_closed)
	Events.match_state_changed.connect(_on_match_state_changed)
	Events.match_scope_reset.connect(release)


## Stackfall Arcade: the same disc-800 plate and rim kicker as the results
## card, on a lighter disc-950 scrim so the match stays visible behind the held table.
func _apply_visual_style() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var look: ResultsTableTuning = ScoreTable.table_tuning()
	(%Background as ColorRect).color = Color(arcade.disc_950_color, look.overlay_scrim_alpha)
	_card.add_theme_stylebox_override("panel", MenuStyleFactory.make_plate())
	%Layout.add_theme_constant_override("separation", look.card_gap_px)
	_rows_list.add_theme_constant_override("separation", look.row_gap_px)
	_mode_title.add_theme_color_override("font_color", arcade.rim_color)
	_mode_title.add_theme_font_size_override("font_size", look.kicker_font_size_px)
	_mode_outcome.add_theme_font_size_override("font_size", look.outcome_font_size_px)
	_mode_outcome.add_theme_color_override("font_color", arcade.sand_color)


func _refresh_layout() -> void:
	var available: Vector2 = get_viewport().get_visible_rect().size - Vector2.ONE * tuning.menu_edge_margin_px * 2.0
	_card.custom_minimum_size.x = minf(available.x, tuning.menu_max_width_px)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"show_scores", false, true):
		# tools/bootstrap_project.gd: the pad half is R3, which also completes the
		# debug perf-overlay chord (Back held + R3, ui/debug/PerfOverlay.gd); that chord
		# must not also pop the scoreboard.
		if event is InputEventJoypadButton and Input.is_action_pressed(&"camera_snap_home"):
			return
		_holding = true
		_update_visibility()
	elif event.is_action_released(&"show_scores", true):
		release()
	elif _root.visible and not _mute_peers.is_empty() and _is_focus_nav(event) and not _mute_has_focus():
		# DECISION: the strip takes focus only after an explicit D-pad / arrow press while the
		# table is held, so opening it never lets a stray accept mute someone. The press is not
		# consumed (gameplay keeps its input).
		(_mute_buttons[_mute_peers[0]] as Button).grab_focus()


static func _is_focus_nav(event: InputEvent) -> bool:
	for action: StringName in [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		if event.is_action_pressed(action):
			return true
	return false


func _mute_has_focus() -> bool:
	var owner: Control = get_viewport().gui_get_focus_owner()
	return owner != null and _mute_box != null and _mute_box.is_ancestor_of(owner)


func _release_mute_focus() -> void:
	if _mute_has_focus():
		get_viewport().gui_release_focus()


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
	if suppressed or _paused or not _holding:
		return false
	return MatchAutoload.is_live(match_context.state())


func _update_visibility() -> void:
	var show_now: bool = _can_show()
	if show_now and not _root.visible:
		_last_rows = []
		_last_mode = null
		_refresh_table()
	_root.visible = show_now
	if show_now:
		_refresh_mute_strip()
	if not show_now:
		_release_mute_focus()


## Rebuilds the table only when the snapshot's rows or mode block changed
## (the match clock alone changes every frame).
func _refresh_table() -> void:
	var stats: RefCounted = match_context.stats()
	if stats == null:
		return
	var payload: Dictionary = stats.live_payload()
	if payload.is_empty():
		return
	var rows: Array = ResultsPayload.rows(payload)
	var mode: Variant = payload.get(ResultsPayload.KEY_MODE)
	if rows == _last_rows and mode == _last_mode:
		return
	_last_rows = rows.duplicate(true)
	_last_mode = mode
	var config: MatchConfig = match_context.config()
	var team_numbers: PackedInt32Array = PackedInt32Array()
	if config != null and config.teams_resolved():
		team_numbers = config.team_numbers
	_mode_title.text = ResultsScreen.mode_title(payload).to_upper()
	# DECISION: null makes ScoreTable read the Match autoload for tier labels and slot colours (its provider
	# reads `config` as a field, which MatchContext answers as a method); it takes the context once it is typed.
	ScoreTable.populate(_rows_list, payload, tuning, team_numbers, null)
	var outcome: String = ResultsScreen.mode_outcome_text(payload, team_numbers).strip_edges()
	_mode_outcome.text = outcome
	_mode_outcome.visible = not outcome.is_empty()


## The chat mute strip: a toggle per remote human, so a held scoreboard (mouse click, or pad focus
## which is grabbed on the first button) can silence one player's chat. Hidden offline and on the
## private local host. Rebuilt only when the set of remote peers changes.
func _refresh_mute_strip() -> void:
	var peers: PackedInt32Array = PackedInt32Array()
	if not Net.is_offline() and not Net.is_private_session():
		for peer_id: int in Net.peer_ids():
			if peer_id != Net.local_peer_id():
				peers.append(peer_id)
	if _mute_box == null:
		_mute_box = HFlowContainer.new()
		_mute_box.name = "MuteStrip"
		_mute_box.alignment = FlowContainer.ALIGNMENT_CENTER
		%Layout.add_child(_mute_box)
	if peers != _mute_peers:
		_mute_peers = peers
		_rebuild_mute_buttons()
	_mute_box.visible = not peers.is_empty()
	for peer_id: int in _mute_buttons:
		_set_mute_text(_mute_buttons[peer_id] as Button, peer_id)


func _rebuild_mute_buttons() -> void:
	for child: Node in _mute_box.get_children():
		_mute_box.remove_child(child)
		child.queue_free()
	_mute_buttons.clear()
	for peer_id: int in _mute_peers:
		var button: UiBlockButton = UiBlockButton.new()
		button.name = "Mute%d" % peer_id
		button.pressed.connect(_on_mute_pressed.bind(peer_id))
		_mute_box.add_child(button)
		_mute_buttons[peer_id] = button
		_set_mute_text(button, peer_id)


func _set_mute_text(button: Button, peer_id: int) -> void:
	var shown: String = String(Net.peer_info(peer_id).get(LobbySeats.FIELD_NAME, "Player"))
	if shown.length() > MUTE_NAME_MAX_CHARS:
		shown = shown.substr(0, MUTE_NAME_MAX_CHARS)
	button.text = (UNMUTE_TEXT if ChatMute.is_muted(peer_id) else MUTE_TEXT) % shown


func _on_mute_pressed(peer_id: int) -> void:
	ChatMute.toggle(peer_id)
	_refresh_mute_strip()
