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

## DECISION (ui/Lobby.gd, M6 A4): MatchConfig.enabled_specials already means
## "empty = every special enabled" (config/MatchConfig.gd's own doc comment),
## so unchecking every %SpecialsChecklist box can't publish an empty array --
## that would mean the opposite of what the host asked for. This sentinel id
## published as the sole entry instead means "spawn nothing"; it isn't a
## MatchConfig constant (this package doesn't own config/MatchConfig.gd) and
## autoload/match/MatchGifts.gd can't import a ui/ script, so its
## _ensure_special_drawer_installed() carries the identical literal with a
## matching DECISION comment pointing back here.
const ALL_DISABLED_SENTINEL: StringName = &"__none__"

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
@onready var _specials_checklist: VBoxContainer = %SpecialsChecklist

@onready var _player_list: VBoxContainer = %PlayerList
@onready var _ready_check: CheckButton = %ReadyCheck
@onready var _start_button: Button = %StartButton
@onready var _invite_friends_button: Button = %InviteFriendsButton

## Every control the round trip governs, so enabling/disabling them for a
## non-host is one loop instead of fourteen repeated lines.
var _settings_controls: Array[Control] = []
var _player_rows: Array[Node] = []

## Built once by _build_specials_checklist(), in SpecialDef.load_all_specials()
## order -- parallel arrays (the same convention _player_rows pairs with
## roster entries by index) so _config_from_controls()/_apply_data() can walk
## both together without a per-frame dictionary lookup.
var _special_checkboxes: Array[CheckBox] = []
var _special_ids: Array[StringName] = []

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
	_settings_controls.append_array(_special_checkboxes)
	_connect_control_signals()
	_start_button.pressed.connect(_on_start_pressed)
	_ready_check.toggled.connect(_on_ready_toggled)
	_invite_friends_button.pressed.connect(_on_invite_friends_pressed)
	_connect_click_and_hover_sounds()
	Events.net_lobby_data_changed.connect(_on_lobby_data_changed)
	Events.net_peer_joined.connect(_on_peer_joined)
	Events.net_peer_left.connect(_on_peer_left)
	Events.net_roster_changed.connect(_on_roster_changed)

	_apply_data(default_config.to_dict())
	_update_host_only_state()
	_map_variant_option.grab_focus()


func _process(_delta: float) -> void:
	# DECISION (ui/Lobby.gd, Bontago-mv0.6): Events.net_roster_changed (added
	# below) tells this screen a peer's ready flag flipped, but Net's
	# aggregate all_peers_ready() is still just a plain method, and deriving
	# the same bool from the roster payload here would duplicate Net's own
	# rule. Refreshing the Start button's gate every frame stays simpler than
	# inventing a second cross-package signal just for that one aggregate.
	# Cheap: two method calls and a bool compare on a screen with a handful
	# of controls.
	_update_host_only_state()


# --- Building settings controls ----------------------------------------------

func _populate_options() -> void:
	_fill_option(_map_variant_option, ["Round", "Oval", "Ring", "Twin", "Cross"])
	_fill_option(_map_size_option, ["Small", "Medium", "Large"])
	_fill_option(_ai_difficulty_option, ["Easy", "Normal", "Hard"])
	_fill_option(_team_mode_option, ["Off", "2 teams", "3 teams", "4 teams"])
	_fill_option(_tilt_mode_option, ["Specials only", "Physical balance"])
	# Territory v2 (docs/TERRITORY_V2_PLAN.md) added HoleMode.OFF (= 2,
	# appended after TEMPORARY/PERMANENT) as the optional no-overlap mode.
	# "Off" must still be the option list's third item, at the same index as
	# the enum value, or OptionButton.selected = 2 on a 2-item list is
	# silently ignored and a config asking for OFF is stuck on legacy holes
	# (found by package A, Bontago-cmc.4). MatchConfig.hole_mode's own default
	# reverted to TEMPORARY (Bontago-cmc.7, SPEC.md's 2026-09-20 evidence
	# audit); the lobby shows whatever config/match_defaults.tres stores
	# (_ready()'s _apply_data(default_config.to_dict())), so no lobby-side
	# default needs to move separately.
	_fill_option(_hole_mode_option, ["Temporary", "Permanent", "Off"])
	_build_specials_checklist()


func _fill_option(option: OptionButton, labels: Array) -> void:
	option.clear()
	for label: String in labels:
		option.add_item(label)


## M6 A4 (docs/M6_PLAN.md "A4 -- Enabled-specials checklist"): one CheckBox per
## config/specials/*.tres, in SpecialDef.load_all_specials() id order (the
## same sorted, deterministic order every peer's own load produces, so the
## checklist never shows two peers a differently-ordered list). Checked =
## enabled, mirroring MatchConfig.enabled_specials's own "empty = all enabled"
## default (every box starts checked here; _apply_data() below is the only
## place that can later uncheck one, from a published config). Called once
## from _populate_options(), before _ready() builds _settings_controls, the
## same "every row already exists before the host/client gate runs" ordering
## _build_roster()/_apply_roster() (player rows) also depends on.
func _build_specials_checklist() -> void:
	for child: Node in _specials_checklist.get_children():
		_specials_checklist.remove_child(child)
		child.queue_free()
	_special_checkboxes.clear()
	_special_ids.clear()

	for special: SpecialDef in SpecialDef.load_all_specials():
		var box: CheckBox = CheckBox.new()
		# SpecialDef has no display_name (config/specials/SpecialDef.gd) -- the
		# id itself (e.g. &"jumping_bean") is the only per-special label this
		# package has to show; capitalize() turns "jumping_bean" into
		# "Jumping Bean" the way String.capitalize() already title-cases an
		# underscore-joined identifier.
		box.text = String(special.id).capitalize()
		box.button_pressed = true
		box.toggled.connect(_on_toggled)
		_specials_checklist.add_child(box)
		_special_checkboxes.append(box)
		_special_ids.append(special.id)


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


## assets-audio package: UI button press/hover has no Events signal of its
## own (it isn't gameplay), so this calls Sfx directly -- the one named
## exception to "Sfx listens, nothing calls it" (autoload/Sfx.gd's header).
## Scoped to actual buttons, not every settings control, so dragging a
## slider doesn't spam hover sounds.
func _connect_click_and_hover_sounds() -> void:
	var buttons: Array[BaseButton] = [_start_button, _invite_friends_button, _ready_check]
	for button: BaseButton in buttons:
		button.pressed.connect(_on_sound_button_pressed)
		button.mouse_entered.connect(_on_sound_button_hovered)


func _on_sound_button_pressed() -> void:
	Sfx.play(AudioConfig.EVENT_CLICK)


func _on_sound_button_hovered() -> void:
	Sfx.play(AudioConfig.EVENT_HOVER)


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
	data["roster"] = _build_roster(config)
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
	config.enabled_specials = _enabled_specials_from_checkboxes()
	return config


## MatchConfig.enabled_specials's own doc: "Empty means every special enabled
## by default" -- so "every box checked" (the default state _build_specials_
## checklist() starts every box in) must publish an empty array, not the full
## id list, to keep matching that convention exactly (and so a match started
## before any SpecialDef.tres existed, or before this package landed, still
## reads identically). Only "every box unchecked" gets the special-cased
## ALL_DISABLED_SENTINEL; anything in between is the literal checked-id list.
func _enabled_specials_from_checkboxes() -> Array[StringName]:
	var checked: Array[StringName] = []
	for i: int in range(_special_checkboxes.size()):
		if _special_checkboxes[i].button_pressed:
			checked.append(_special_ids[i])
	if checked.is_empty() and not _special_ids.is_empty():
		return [ALL_DISABLED_SENTINEL]
	if checked.size() == _special_ids.size():
		return []
	return checked


## Applies a Dictionary from Events.net_lobby_data_changed (or the initial
## default) to every control. Always goes through MatchConfig.from_dict() and
## sanitize(), so a value outside its spec 2.8 range is clamped rather than
## trusted, whether it came from the wire or from this instance's own publish.
func _apply_data(data: Dictionary) -> void:
	var config: MatchConfig = MatchConfig.from_dict(data)
	config.sanitize()
	# DECISION (ui/Lobby.gd, Bontago-mv0.7 root cause): this screen is
	# reachable only for networked play (see _config_from_controls()'s own
	# matching DECISION), but that hot_seat=false override only ever ran
	# through _config_from_controls() -- reached the *first* time only when a
	# host actually touched a setting control. _ready()'s own first call
	# below feeds this function config/match_defaults.tres's dict verbatim,
	# whose hot_seat is true (M2's own default resource), so a host who never
	# touched a slider before pressing Start sent hot_seat=true into
	# Match.start_match(): Match then ran strict single-active-slot turn
	# alternation across every slot, including the ones player_count left
	# unowned. Windowed repro (host + client, default settings, Start with no
	# edits): the HUD's turn banner cycled "Player 2's turn" -> "Player 3's
	# turn" on *both* instances (Match's own _active_slot advancing on every
	# auto-drop, not a per-slot real-time timer), and the host's own clicks
	# were refused REASON_NOT_YOUR_TURN because PlayerController's networked
	# _acting_slot() (Net.local_slot(), always 0 for the host) rarely lined
	# up with Match's one shared _active_slot -- read by the owner as "player
	# 2, 3, 4 place; player 1 is skipped". Forcing it false on every apply,
	# not just the controls' own publish, closes the gap for the implicit
	# initial default and for any (malformed or stale) config a client might
	# ever receive over the wire.
	config.hot_seat = false
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
	_apply_enabled_specials_to_checkboxes(config.enabled_specials)
	_applying_remote_data = false

	if data.has("roster"):
		_apply_roster(data["roster"])


## _apply_data()'s round trip for the specials checklist: empty -> every box
## checked (MatchConfig.enabled_specials's own "empty = all enabled"
## convention), the ALL_DISABLED_SENTINEL alone -> every box unchecked,
## otherwise check exactly the ids named. Runs inside _apply_data()'s existing
## _applying_remote_data guard, so toggling a box here doesn't loop back into
## _on_toggled() -> _on_setting_changed() -> another publish.
func _apply_enabled_specials_to_checkboxes(enabled: Array[StringName]) -> void:
	var all_enabled: bool = enabled.is_empty()
	var all_disabled: bool = enabled.has(ALL_DISABLED_SENTINEL)
	for i: int in range(_special_checkboxes.size()):
		if all_enabled:
			_special_checkboxes[i].button_pressed = true
		elif all_disabled:
			_special_checkboxes[i].button_pressed = false
		else:
			_special_checkboxes[i].button_pressed = enabled.has(_special_ids[i])


func _on_lobby_data_changed(data: Dictionary) -> void:
	_apply_data(data)


# --- Player list / ready / start --------------------------------------------

## Difficulty labels for the synthetic bot rows _build_roster() appends
## below, in MatchConfig.AiDifficulty enum order (EASY, NORMAL, HARD) -- the
## same order _populate_options() fills %AiDifficultyOption with, so
## config.ai_difficulty indexes both consistently (P4, Bontago-d5c.5).
const _AI_DIFFICULTY_LABELS: Array[String] = ["Easy", "Normal", "Hard"]


func _build_roster(config: MatchConfig) -> Array[Dictionary]:
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
	# M5 P4 (docs/M5_PLAN.md): one synthetic row per bot seat, slot_id running
	# from player_count - ai_count to player_count - 1 -- the same formula
	# autoload/match/MatchLifecycle.gd's _build_slots() uses for
	# PlayerSlot.is_bot, so the lobby preview and the real match slots never
	# disagree about which ids are bots. A bot has no connected peer behind
	# it to ready up, so ready is always true; Net.all_peers_ready() only
	# ever iterates real peers (its own header), so this can never let an
	# unready human's Start gate open.
	var difficulty: String = _AI_DIFFICULTY_LABELS[
		clampi(config.ai_difficulty, 0, _AI_DIFFICULTY_LABELS.size() - 1)
	]
	var bot_start: int = config.player_count - config.ai_count
	for slot_id: int in range(bot_start, config.player_count):
		var bot_index: int = slot_id - bot_start + 1
		roster.append({
			"peer_id": -1,
			"slot_id": slot_id,
			"name": "Bot %d (%s)" % [bot_index, difficulty],
			"ready": true,
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


## DECISION (ui/Lobby.gd, Bontago-mv0.6): Events.net_roster_changed's payload
## is the roster Net just built (autoload/Net.gd's _broadcast_roster() /
## _rpc_roster_update()), so this applies it straight to the rows rather than
## re-deriving one from net_provider.peer_ids()/peer_info() the way
## _build_roster() does for the host's own outbound publish — one less round
## trip, and it is the single source of truth for "what does the list show
## right now" (net_lobby_data_changed's own embedded roster only matters for
## the late-joiner snapshot _apply_data() already handles).
func _on_roster_changed(roster: Array[Dictionary]) -> void:
	_apply_roster(roster)
	_mirror_player_count_to_peers(roster.size())


func _on_peer_joined(_peer_id: int, _slot_id: int, _player_name: String) -> void:
	_republish_roster_if_host()


func _on_peer_left(_peer_id: int, _slot_id: int, _reason: int) -> void:
	_republish_roster_if_host()


func _republish_roster_if_host() -> void:
	if net_provider != null and bool(net_provider.is_host()):
		_publish_lobby_data(_last_config if _last_config != null else _config_from_controls())


## Bontago-mv0.7: player_count above the number of connected peers leaves a
## slot nobody holds (see MatchConfig.clamp_to_connected_peers()'s matching
## DECISION); _on_start_pressed() below is the authoritative clamp (it runs
## even if a roster event was somehow missed), so this is display-only —
## keeping the spin from ever *showing* a count the match is about to
## override the moment Start is pressed. Bots don't exist until M5, so until
## then the spin simply tracks the peer count exactly rather than letting a
## host pre-configure a headroom no bot can fill yet.
func _mirror_player_count_to_peers(peer_count: int) -> void:
	if net_provider == null or not bool(net_provider.is_host()):
		return
	var target: int = clampi(peer_count, MatchConfig.PLAYER_COUNT_MIN, MatchConfig.PLAYER_COUNT_MAX)
	if int(_player_count_spin.value) != target:
		_player_count_spin.value = target


func _on_ready_toggled(pressed: bool) -> void:
	if net_provider != null:
		net_provider.set_local_ready(pressed)


func _on_start_pressed() -> void:
	if net_provider == null or not bool(net_provider.is_host()) or not bool(net_provider.all_peers_ready()):
		return
	var config: MatchConfig = (
		_last_config if _last_config != null else _config_from_controls()
	).duplicate(true) as MatchConfig
	# DECISION (ui/Lobby.gd, Bontago-mv0.7): the authoritative peer-count
	# clamp lives here rather than in autoload/Match.gd's start_match() (the
	# spec/plan's stated preference) because Match.start_match() is also the
	# exact call tests/unit/test_match_lifecycle.gd drives through
	# game/Main.gd's real (peerless) hosted Net session with player_count
	# values chosen to differ from the connected peer count on purpose, to
	# prove the *world-rebuild* dance across repeated starts -- a concern
	# orthogonal to "no phantom slots" that a Match-level clamp would have
	# broken. ui/Lobby.gd's own Start button is the one call site that both
	# is exclusively the real product path (game/Main.gd never calls
	# start_match() for networked play except from here) and already knows
	# how many peers are actually connected, so the clamp runs here and
	# Match.start_match() is left exactly as it was.
	config.clamp_to_connected_peers(net_provider.peer_ids().size())
	start_requested.emit(config)


## M3b (docs/M3b_PLAN.md P3): opens the Steam overlay's invite dialog. Only
## `net_provider.invite_friends()` is called here — never a raw Steam call —
## the same discipline every other button handler in this file keeps.
func _on_invite_friends_pressed() -> void:
	if net_provider != null:
		net_provider.invite_friends()


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
	_invite_friends_button.visible = is_host and net_provider != null and bool(net_provider.is_steam_session())
