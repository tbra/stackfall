class_name Lobby
extends Control
## Every spec 2.8 match setting as a control, synced as lobby data so every
## client sees the host's settings (spec 3.4 "Steam lobbies store match
## settings as lobby data"; docs/M3a_PLAN.md P4).
##
## **The round trip.** The host builds a MatchConfig from its controls,
## serializes it with to_dict(), merges in the roster, and calls
## Net.set_lobby_data(). Every instance — including the host itself, so its
## own UI never waits on an echo that may not arrive over a stub or a lossy
## transport — applies the same Dictionary through _apply_data(): from_dict(),
## then sanitize() so a value that arrived out of its spec 2.8 range is
## clamped rather than trusted (docs/M3a_PLAN.md P4 "Tests first"). A guard
## flag stops that inbound apply from re-triggering another outbound publish.
##
## **Host-only editing.** Net.is_host() is true on the host and offline
## (autoload/Net.gd's docstring), so gating on it alone is exactly the "M2
## hot-seat still works" rule this project uses everywhere else. A client's
## controls are disabled; only its own Ready checkbox stays live.
##
## Connects to Events and Net only — no node paths into game/Main.gd. Start
## is a signal for whoever owns scene-building (the integrator's Main) to
## react to; this script never calls Match.start_match() itself, on the host
## or (per docs/M3a_PLAN.md P4 "Must NOT") on a client.

## Emitted when the host presses Start with every peer ready. `config` is the
## sanitized MatchConfig the lobby is currently showing.
signal start_requested(config: MatchConfig)

@export var default_config: MatchConfig = preload("res://config/match_defaults.tres")

## DECISION (ui/Lobby.gd): same `Variant` test seam as ui/MainMenu.gd and
## ui/HUD.gd's match_provider.
var net_provider: Variant = null

@onready var _map_variant_option: OptionButton = %MapVariantOption
@onready var _map_size_option: OptionButton = %MapSizeOption
@onready var _player_count_spin: SpinBox = %PlayerCountSpin
@onready var _ai_count_spin: SpinBox = %AiCountSpin
@onready var _ai_difficulty_option: OptionButton = %AiDifficultyOption
@onready var _team_mode_option: OptionButton = %TeamModeOption
@onready var _block_timer_slider: HSlider = %BlockTimerSlider
@onready var _block_timer_label: Label = %BlockTimerLabel
@onready var _gravity_slider: HSlider = %GravitySlider
@onready var _gravity_label: Label = %GravityLabel
@onready var _goal_flag_spin: SpinBox = %GoalFlagSpin
@onready var _gifts_check: CheckButton = %GiftsCheck
@onready var _special_freq_slider: HSlider = %SpecialFreqSlider
@onready var _special_freq_label: Label = %SpecialFreqLabel
@onready var _tilt_mode_option: OptionButton = %TiltModeOption
@onready var _hole_mode_option: OptionButton = %HoleModeOption
@onready var _match_timer_spin: SpinBox = %MatchTimerSpin
@onready var _sudden_death_check: CheckButton = %SuddenDeathCheck
@onready var _specials_note: Label = %SpecialsNote

@onready var _player_list: VBoxContainer = %PlayerList
@onready var _ready_check: CheckButton = %ReadyCheck
@onready var _start_button: Button = %StartButton

## Every control the round trip governs, so enabling/disabling them for a
## non-host is one loop instead of fourteen repeated lines.
var _settings_controls: Array[Control] = []
var _player_rows: Array[Node] = []

## True while _apply_data() is writing sanitized values back into the
## controls, so the value-changed signals that causes fire without
## re-publishing what was just received (an infinite echo).
var _applying_remote_data: bool = false
var _last_config: MatchConfig = null


func _ready() -> void:
	net_provider = Net
	_populate_options()
	_settings_controls = [
		_map_variant_option, _map_size_option, _player_count_spin, _ai_count_spin,
		_ai_difficulty_option, _team_mode_option, _block_timer_slider, _gravity_slider,
		_goal_flag_spin, _gifts_check, _special_freq_slider, _tilt_mode_option,
		_hole_mode_option, _match_timer_spin, _sudden_death_check,
	]
	_connect_control_signals()
	_start_button.pressed.connect(_on_start_pressed)
	_ready_check.toggled.connect(_on_ready_toggled)
	Events.net_lobby_data_changed.connect(_on_lobby_data_changed)
	Events.net_peer_joined.connect(_on_peer_joined)
	Events.net_peer_left.connect(_on_peer_left)

	_apply_data(default_config.to_dict())
	_update_host_only_state()
	_map_variant_option.grab_focus()


func _process(_delta: float) -> void:
	# DECISION (ui/Lobby.gd): no Events signal exists for "a peer's ready flag
	# changed" (Net only exposes set_peer_ready()/all_peers_ready(), see
	# autoload/Net.gd), so the Start button's gate is refreshed every frame
	# instead of invented a new cross-package signal contract. Cheap: two
	# method calls and a bool compare on a screen with a handful of controls.
	_update_host_only_state()


# --- Building settings controls ----------------------------------------------

func _populate_options() -> void:
	_fill_option(_map_variant_option, ["Round", "Oval", "Ring", "Twin", "Cross"])
	_fill_option(_map_size_option, ["Small", "Medium", "Large"])
	_fill_option(_ai_difficulty_option, ["Easy", "Normal", "Hard"])
	_fill_option(_team_mode_option, ["Off", "2 teams", "3 teams", "4 teams"])
	_fill_option(_tilt_mode_option, ["Specials only", "Physical balance"])
	_fill_option(_hole_mode_option, ["Temporary", "Permanent"])


func _fill_option(option: OptionButton, labels: Array) -> void:
	option.clear()
	for label: String in labels:
		option.add_item(label)


func _connect_control_signals() -> void:
	_map_variant_option.item_selected.connect(_on_option_changed)
	_map_size_option.item_selected.connect(_on_option_changed)
	_ai_difficulty_option.item_selected.connect(_on_option_changed)
	_team_mode_option.item_selected.connect(_on_option_changed)
	_tilt_mode_option.item_selected.connect(_on_option_changed)
	_hole_mode_option.item_selected.connect(_on_option_changed)
	_player_count_spin.value_changed.connect(_on_value_changed)
	_ai_count_spin.value_changed.connect(_on_value_changed)
	_block_timer_slider.value_changed.connect(_on_value_changed)
	_gravity_slider.value_changed.connect(_on_value_changed)
	_goal_flag_spin.value_changed.connect(_on_value_changed)
	_special_freq_slider.value_changed.connect(_on_value_changed)
	_match_timer_spin.value_changed.connect(_on_value_changed)
	_gifts_check.toggled.connect(_on_toggled)
	_sudden_death_check.toggled.connect(_on_toggled)


func _on_option_changed(_index: int) -> void:
	_on_setting_changed()


func _on_value_changed(_value: float) -> void:
	_on_setting_changed()


func _on_toggled(_pressed: bool) -> void:
	_on_setting_changed()


## The one place a host's edit turns into a publish (docs/M3a_PLAN.md P4
## "Tests first": "every setting round-trips through ... Net.set_lobby_data").
func _on_setting_changed() -> void:
	if _applying_remote_data:
		return
	if net_provider == null or not bool(net_provider.is_host()):
		return
	_publish_lobby_data(_config_from_controls())


func _publish_lobby_data(config: MatchConfig) -> void:
	config.sanitize()
	var data: Dictionary = config.to_dict()
	data["roster"] = _build_roster()
	net_provider.set_lobby_data(data)
	_apply_data(data)


func _config_from_controls() -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	# DECISION (ui/Lobby.gd, M3a integration): MatchConfig.hot_seat defaults to
	# true (config/match_defaults.tres and MatchConfig.new() alike), which
	# forces Match's strict-alternation single-timer branch (autoload/Match.gd
	# _tick_feed and friends). The lobby is reachable only for networked play —
	# hot-seat stays a separate, unlisted `--hot-seat` path straight to
	# game/HotSeat.tscn (docs/M3a_PLAN.md question 3) — so every config this
	# screen builds must run the real-time per-player-timer branch instead.
	config.hot_seat = false
	config.map_variant = _map_variant_option.selected
	config.map_size = _map_size_option.selected as MapDef.MapSize
	config.player_count = int(_player_count_spin.value)
	config.ai_count = int(_ai_count_spin.value)
	config.ai_difficulty = _ai_difficulty_option.selected
	config.team_mode = _team_mode_option.selected
	config.block_timer = _block_timer_slider.value
	config.gravity_multiplier = _gravity_slider.value
	config.goal_flag_count = int(_goal_flag_spin.value)
	config.gifts_enabled = _gifts_check.button_pressed
	config.special_frequency = int(_special_freq_slider.value)
	config.tilt_mode = _tilt_mode_option.selected
	config.hole_mode = _hole_mode_option.selected
	config.match_timer_minutes = int(_match_timer_spin.value)
	config.sudden_death = _sudden_death_check.button_pressed
	return config


## Applies a Dictionary from Events.net_lobby_data_changed (or the initial
## default) to every control. Always goes through MatchConfig.from_dict() and
## sanitize(), so a value outside its spec 2.8 range is clamped rather than
## trusted, whether it came from the wire or from this instance's own publish.
func _apply_data(data: Dictionary) -> void:
	var config: MatchConfig = MatchConfig.from_dict(data)
	config.sanitize()
	_last_config = config

	_applying_remote_data = true
	_map_variant_option.selected = config.map_variant
	_map_size_option.selected = config.map_size
	_player_count_spin.value = config.player_count
	_ai_count_spin.value = config.ai_count
	_ai_difficulty_option.selected = config.ai_difficulty
	_team_mode_option.selected = config.team_mode
	_block_timer_slider.value = config.block_timer
	_block_timer_label.text = "%.1f s" % config.block_timer
	_gravity_slider.value = config.gravity_multiplier
	_gravity_label.text = "%.2fx" % config.gravity_multiplier
	_goal_flag_spin.value = config.goal_flag_count
	_gifts_check.button_pressed = config.gifts_enabled
	_special_freq_slider.value = config.special_frequency
	_special_freq_label.text = str(config.special_frequency)
	_tilt_mode_option.selected = config.tilt_mode
	_hole_mode_option.selected = config.hole_mode
	_match_timer_spin.value = config.match_timer_minutes
	_sudden_death_check.button_pressed = config.sudden_death
	_specials_note.text = (
		"All specials enabled (none defined until M4)" if config.enabled_specials.is_empty()
		else "%d specials enabled" % config.enabled_specials.size()
	)
	_applying_remote_data = false

	if data.has("roster"):
		_apply_roster(data["roster"])


func _on_lobby_data_changed(data: Dictionary) -> void:
	_apply_data(data)


# --- Player list / ready / start --------------------------------------------

func _build_roster() -> Array[Dictionary]:
	var roster: Array[Dictionary] = []
	if net_provider == null:
		return roster
	for peer_id: int in net_provider.peer_ids():
		var info: Dictionary = net_provider.peer_info(peer_id)
		roster.append({
			"peer_id": peer_id,
			"slot_id": int(info.get("slot_id", -1)),
			"name": str(info.get("name", "")),
			"ready": bool(info.get("ready", false)),
		})
	return roster


func _apply_roster(roster_data: Variant) -> void:
	var roster: Array = roster_data as Array
	for row: Node in _player_rows:
		row.queue_free()
	_player_rows.clear()
	var palette: PackedColorArray = default_config.player_colors
	for entry_variant: Variant in roster:
		var entry: Dictionary = entry_variant as Dictionary
		var slot_id: int = int(entry.get("slot_id", -1))
		var row: HBoxContainer = HBoxContainer.new()
		var swatch: ColorRect = ColorRect.new()
		swatch.custom_minimum_size = Vector2(16.0, 16.0)
		swatch.color = palette[slot_id] if slot_id >= 0 and slot_id < palette.size() else Color.GRAY
		var label: Label = Label.new()
		var ready: bool = bool(entry.get("ready", false))
		label.text = "%s%s" % [str(entry.get("name", "?")), "  (ready)" if ready else "  (not ready)"]
		row.add_child(swatch)
		row.add_child(label)
		_player_list.add_child(row)
		_player_rows.append(row)


func _on_peer_joined(_peer_id: int, _slot_id: int, _player_name: String) -> void:
	_republish_roster_if_host()


func _on_peer_left(_peer_id: int, _slot_id: int, _reason: int) -> void:
	_republish_roster_if_host()


func _republish_roster_if_host() -> void:
	if net_provider != null and bool(net_provider.is_host()):
		_publish_lobby_data(_last_config if _last_config != null else _config_from_controls())


func _on_ready_toggled(pressed: bool) -> void:
	if net_provider != null:
		net_provider.set_local_ready(pressed)


func _on_start_pressed() -> void:
	if net_provider == null or not bool(net_provider.is_host()) or not bool(net_provider.all_peers_ready()):
		return
	start_requested.emit(_last_config if _last_config != null else _config_from_controls())


# --- Host/client control gating ----------------------------------------------

func _update_host_only_state() -> void:
	var is_host: bool = net_provider != null and bool(net_provider.is_host())
	for control: Control in _settings_controls:
		if control is Range:
			control.set("editable", is_host)
		elif control is BaseButton:
			(control as BaseButton).disabled = not is_host
	_start_button.visible = is_host
	_start_button.disabled = not is_host or not (net_provider != null and bool(net_provider.all_peers_ready()))
