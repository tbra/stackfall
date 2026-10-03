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

## Emitted when the player presses the header's Back pill (Bontago-xtq.32
## redo #3, mockup 11's top-right "< Back"). Whoever owns scene transitions
## (game/Main.gd) is the only listener this package expects; see this file's
## own header docstring, "no node paths into game/Main.gd" -- a signal keeps
## that boundary intact instead of calling a scene-tree path directly.
signal back_requested

@export var default_config: MatchConfig = preload("res://config/match_defaults.tres")

## Bontago-xtq.32 redo: same layered-pastel tunable set ui/MainMenu.gd draws
## its visual style from (config/MenuVisualTuning.gd), so the Lobby matches
## the Main Menu's look with zero magic numbers here (CLAUDE.md "No magic
## numbers").
@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")

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

## Bontago-1pi.18.5 (docs/QOL_EXPERIMENTS_PLAN.md, Q1): the shared experiments
## resource the F4 panel edits. The four enable flags come from the lobby's
## "Experiments" checkboxes; every numeric parameter (pause_event_s,
## backlog_max, goal_radius_multiplier, ...) is copied from here, so those stay
## F4-tunable. Never modified: QolExperiments.with_toggles() works on a copy.
const QOL_SHARED: QolExperiments = preload("res://config/qol_experiments.tres")

## Bontago-mp0.3.5 (review r2, item 1): the hidden %MapVariantOption/
## %MapSizeOption labels, reused to build %MapComboOption's own "Round ·
## Medium" style combined list in MatchConfig.MapVariant * MapDef.MapSize
## order -- variant major, size minor (index = variant * 3 + size), so
## _map_combo_index()/_decode_map_combo() only need arithmetic, not a lookup
## table, matching the hidden options' own selected-index encoding exactly.
const MAP_VARIANT_LABELS: Array[String] = ["Round", "Oval", "Ring", "Twin", "Cross"]
const MAP_SIZE_LABELS: Array[String] = ["Small", "Medium", "Large"]

## DECISION (ui/Lobby.gd): same `Variant` test seam as ui/MainMenu.gd and
## ui/HUD.gd's match_provider.
var net_provider: Variant = null

## Bontago-mp0.3.5 (review r2, item 1): %MapVariantOption/%MapSizeOption stay
## the hidden source of truth (same pattern as _team_buttons over the hidden
## %TeamModeOption) -- %MapComboOption is the single visible "Round · Medium"
## style dropdown listing every variant*size combo, decoded/encoded by
## _map_combo_index(), with %MapThumbnail (a small disc icon) beside it.
@onready var _map_variant_option: OptionButton = %MapVariantOption
@onready var _map_size_option: OptionButton = %MapSizeOption
@onready var _map_combo_option: OptionButton = %MapComboOption
@onready var _map_thumbnail: PanelContainer = %MapThumbnail
@onready var _player_count_spin: SpinBox = %PlayerCountSpin
@onready var _ai_count_spin: SpinBox = %AiCountSpin
## Bontago-mp0.3.5 (polish pass, problem 2): mockup 11 puts "Players"/"AI"
## inside their own stepper pill's left end, not on a separate row above it
## -- _add_stepper_buttons() reuses these tscn-authored Labels' text and
## hides the originals rather than duplicating the strings in code.
@onready var _players_sub_label: Label = %PlayersSubLabel
@onready var _ai_sub_label: Label = %AiSubLabel
@onready var _ai_difficulty_option: OptionButton = %AiDifficultyOption
@onready var _team_mode_option: OptionButton = %TeamModeOption
## Bontago-mp0.3.5 (mockup 11's TEAMS segmented control): %TeamModeOption
## stays the single source of truth for config.team_mode (kept, but hidden,
## so every existing read/write of `.selected` and its `item_selected` wiring
## is untouched) -- these four toggle buttons are a visible front end over it,
## in MatchConfig.team_mode enum order (Off, 2, 3, 4 teams), driven by a
## shared ButtonGroup so pressing one always releases the others.
@onready var _team_buttons: Array[Button] = [%TeamOffButton, %Team2Button, %Team3Button, %Team4Button]
@onready var _block_timer_slider: HSlider = %BlockTimerSlider
@onready var _block_timer_label: Label = %BlockTimerLabel
@onready var _gravity_slider: HSlider = %GravitySlider
@onready var _gravity_label: Label = %GravityLabel
## Bontago-mp0.3.5 (review r1, item 10): "uppercase label + value chip on one
## row, full-width slider below" for BLOCK TIMER/GRAVITY/SPECIAL FREQUENCY --
## these three PanelContainers wrap the existing %BlockTimerLabel etc. Labels
## as a coral value badge instead of a plain trailing number.
@onready var _block_timer_chip: PanelContainer = %BlockTimerChip
@onready var _gravity_chip: PanelContainer = %GravityChip
@onready var _special_freq_chip: PanelContainer = %SpecialFreqChip
@onready var _goal_flag_spin: SpinBox = %GoalFlagSpin
@onready var _gifts_check: CheckButton = %GiftsCheck
@onready var _special_freq_slider: HSlider = %SpecialFreqSlider
@onready var _special_freq_label: Label = %SpecialFreqLabel
@onready var _tilt_mode_option: OptionButton = %TiltModeOption
@onready var _hole_mode_option: OptionButton = %HoleModeOption
@onready var _match_timer_slider: HSlider = %MatchTimerSlider
@onready var _weather_option: OptionButton = %WeatherOption
@onready var _game_mode_option: OptionButton = %GameModeOption
@onready var _round_timer_slider: HSlider = %RoundTimerSlider
## Bontago-6fc.1: ONE timer control is shown. Classic shows the match-timer
## column (+ sudden death); every other mode shows the round-length column.
## Bontago-1pi.30: both are HSliders (step 1 min, value label under them); each
## keeps mapping its own MatchConfig field.
@onready var _match_timer_col: Control = %MatchTimerCol
@onready var _round_timer_col: Control = %RoundTimerCol
@onready var _sudden_death_col: Control = %SuddenDeathCol
@onready var _match_timer_value: Label = %MatchTimerValue
@onready var _round_timer_value: Label = %RoundTimerValue
## Reach the Sky only (Bontago-22y.9): shown while that mode is selected.
@onready var _sky_team_col: Control = %SkyTeamCol
@onready var _sky_team_sum_check: CheckButton = %SkyTeamSumCheck
## Bontago-470.4: the "Map" time-of-day dropdown (MatchConfig.SkyThemeMode).
@onready var _sky_theme_option: OptionButton = %SkyThemeOption
@onready var _sudden_death_check: CheckButton = %SuddenDeathCheck
@onready var _turn_based_check: CheckButton = %TurnBasedCheck
## Bontago-8or.20: host-only toggle for MatchConfig.allow_mid_match_join.
@onready var _mid_join_check: CheckButton = %MidJoinCheck
## Bontago-xtq.32 redo #3: a compact wrap grid of small toggle chips
## (mockup 11), not the round-1 full-width red bars -- HFlowContainer (a
## Container sibling of VBoxContainer, not a subclass) wraps children onto as
## many rows as the card's width needs instead of stacking one per row.
@onready var _specials_checklist: HFlowContainer = %SpecialsChecklist
@onready var _specials_label: Label = %SpecialsLabel
@onready var _advanced_rules_label: Label = %AdvancedRulesLabel
## Bontago-1pi.18.5: the "Experiments" section of the Advanced rules popup, in
## QolExperiments.with_toggles() argument order (timer pause, backlog, goal
## radius, gift slot). Host-editable, read-only for a client (_settings_controls).
@onready var _experiments_label: Label = %ExperimentsLabel
@onready var _qol_timer_pause_check: CheckBox = %QolTimerPauseCheck
@onready var _qol_backlog_check: CheckBox = %QolBacklogCheck
@onready var _qol_goal_radius_check: CheckBox = %QolGoalRadiusCheck
@onready var _qol_gift_slot_check: CheckBox = %QolGiftSlotCheck
@onready var _qol_checks: Array[CheckBox] = [
	_qol_timer_pause_check, _qol_backlog_check, _qol_goal_radius_check, _qol_gift_slot_check,
]

## Bontago-mp0.3.5 (review r3, problem 2): the specials checklist + the five
## rule controls above moved out of the always-visible card into this modal
## popup (mockup 11 has no room for them inline at 1280x720 without either a
## horizontal scrollbar or clipped chips -- review r2's own disclosed gap).
## %AdvRulesBar is the always-visible summary row that opens it.
##
## Bontago-mp0.3.5 (polish pass, problem 1): %AdvRulesBarPanel is the visible
## pill background; %AdvRulesBar (a Button, styled transparent) and
## %AdvRulesBarContent (label + chips) are both its children, stacked over
## the same rect by PanelContainer's own multi-child layout, so the whole bar
## grows in height when %AdvRulesChips wraps onto a second row instead of the
## old fixed-height anchored-Button layout letting wrapped chips spill out.
@onready var _adv_rules_bar_panel: PanelContainer = %AdvRulesBarPanel
@onready var _adv_rules_bar: Button = %AdvRulesBar
@onready var _adv_chip_tilt: Label = %AdvChipTilt
@onready var _adv_chip_hole: Label = %AdvChipHole
@onready var _adv_chip_sudden: Label = %AdvChipSudden
@onready var _adv_chip_turn: Label = %AdvChipTurn
@onready var _adv_chip_specials: Label = %AdvChipSpecials
@onready var _adv_chip_experiments: Label = %AdvChipExperiments
@onready var _advanced_popup: Control = %AdvancedPopup
@onready var _advanced_popup_card: PanelContainer = %AdvancedPopupCard
@onready var _advanced_popup_close: Button = %AdvancedPopupClose

@onready var _player_list: VBoxContainer = %PlayerList
@onready var _ready_check: CheckButton = %ReadyCheck
@onready var _start_button: Button = %StartButton
@onready var _invite_friends_button: Button = %InviteFriendsButton
@onready var _player_count_label: Label = %PlayerCountLabel

@onready var _settings_card: PanelContainer = %SettingsCard
@onready var _players_card: PanelContainer = %PlayersCard
@onready var _status_badge: PanelContainer = %StatusBadge
@onready var _status_badge_label: Label = %StatusBadgeLabel
@onready var _header_title: Label = %HeaderTitle
@onready var _header_eyebrow: Label = %Eyebrow
@onready var _back_button: Button = %BackButton
## Bontago-mp0.3.5 (review r1, item 13): kept for its shared styling helper,
## but hidden in ui/Lobby.tscn -- the bottom-right corner is %StartButton's
## spot on this screen now, unlike ui/MainMenu.gd where the hint still owns it.
@onready var _gamepad_hint_pill: PanelContainer = %GamepadHintPill
## Bontago-mp0.3.5 (review r1, item 13): mockup 11's bottom-left "Waiting for
## players * X of Y ready" pill, updated every _apply_roster() call.
@onready var _waiting_status_pill: PanelContainer = %WaitingStatusPill
@onready var _waiting_status_label: Label = %WaitingStatusLabel
## Bontago-mp0.3.5 (review r1, item 10): the sunken pill track %TeamsTrack
## wraps _team_buttons, so the selected segment reads as a raised white pill
## inside a track instead of a bare coral toggle chip.
@onready var _teams_track: PanelContainer = %TeamsTrack

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

## Bontago-mp0.3.5 (review r2, item 2): the round "-"/"+" buttons
## _add_stepper_buttons() builds around each stepper SpinBox, in insertion
## order (minus, plus, minus, plus, ...) -- read by _wire_focus_chain() so
## they're gamepad-focusable, same as every other settings control.
## All visible steppers belong to the main settings card's focus loop.
var _main_stepper_buttons: Array[Button] = []

## True while _apply_data() is writing sanitized values back into the
## controls, so the value-changed signals that causes fire without
## re-publishing what was just received (an infinite echo).
var _applying_remote_data: bool = false
## Game mode the timer control currently describes (Bontago-6fc.1).
const TIMER_TIP_MATCH: String = "Optional time limit. Off: the match runs until a team holds every goal. With sudden death on, the arena shrinks when time is up."
const TIMER_TIP_ROUND: String = "How long the round lasts; when it ends the highest score wins. Elimination can run with no limit."
## Bontago-1pi.25.1: one-line description per mode (tooltip on the mode picker),
## indexed by MatchConfig.GameMode.
const MODE_TIPS: PackedStringArray = [
	"Hold every goal flag to win.",
	"Hold beacons to score; the highest score wins when the round ends.",
	"Knock out every other team's home flag; the last team standing wins.",
	"Build the tallest tower; the highest block wins when the round ends.",
	"Control the biggest territory when the round timer ends; a timer is always on.",
]
const TIMER_TIP_DOMINATION: String = "How long the round lasts; when it ends the largest territory share wins. Domination always has a timer."
## Bontago-1pi.30: the timer sliders' value text. DECISION: the leftmost stop of a
## slider whose mode may switch its timer off (Classic, Elimination) reads "Off"
## (Elimination used to read "No limit"); every other value reads "<n> min".
const TIMER_OFF_TEXT: String = "Off"
const TIMER_VALUE_FORMAT: String = "%d min"
const TIMER_REQUIRED_FORMAT: String = "%d min (required)"
## One minute per slider step (keyboard/gamepad left/right and the mouse drag).
const TIMER_SLIDER_STEP_MINUTES: float = 1.0
var _timer_mode: int = MatchConfig.GameMode.CLASSIC
## Last minutes each timer slider settled on, so a step through the 1-minute gap
## knows which way it was moving (_on_timer_slider_changed()).
var _timer_previous_minutes: Dictionary[HSlider, int] = {}
var _last_config: MatchConfig = null


func _ready() -> void:
	net_provider = Net
	_populate_options()
	_settings_controls = [
		_map_combo_option, _player_count_spin, _ai_count_spin,
		_ai_difficulty_option, _team_mode_option, _block_timer_slider, _gravity_slider,
		_goal_flag_spin, _gifts_check, _special_freq_slider, _tilt_mode_option,
		_hole_mode_option, _match_timer_slider, _sudden_death_check, _turn_based_check,
		_mid_join_check,
	]
	_settings_controls.append(_weather_option)
	_settings_controls.append(_sky_theme_option)
	_settings_controls.append(_game_mode_option)
	_settings_controls.append(_round_timer_slider)
	_settings_controls.append(_sky_team_sum_check)
	_settings_controls.append_array(_special_checkboxes)
	_settings_controls.append_array(_qol_checks)
	_settings_controls.append_array(_team_buttons)
	_connect_control_signals()
	_start_button.pressed.connect(_on_start_pressed)
	_ready_check.toggled.connect(_on_ready_toggled)
	_invite_friends_button.pressed.connect(_on_invite_friends_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_adv_rules_bar.pressed.connect(_open_advanced_popup)
	_advanced_popup_close.pressed.connect(_close_advanced_popup)
	_connect_click_and_hover_sounds()
	Events.net_lobby_data_changed.connect(_on_lobby_data_changed)
	Events.net_peer_joined.connect(_on_peer_joined)
	Events.net_peer_left.connect(_on_peer_left)
	Events.net_roster_changed.connect(_on_roster_changed)

	# Returning from results creates a fresh Lobby while Net keeps its hosted
	# session. Read the last published settings so quick edits made there are
	# reflected by the controls and the next Start action.
	var initial_data: Dictionary = net_provider.lobby_data()
	_apply_data(initial_data if not initial_data.is_empty() else default_config.to_dict())
	# Bontago-mp0.3.5 (review r1, item 12): Net.host_game() populates its own
	# HOST_PEER_ID roster entry directly and only emits net_mode_changed, not
	# net_roster_changed / a lobby-data publish -- so a Lobby scene opened
	# straight after hosting never received the host's own row until a second
	# peer actually joined and triggered _on_peer_joined()'s republish. This
	# host-only kick (a no-op for a client, whose _republish_roster_if_host()
	# guard is already false) draws the host's own row on the very first frame
	# instead of leaving the Players card at "0 / N" until someone else connects.
	_republish_roster_if_host()
	# Bontago-mp0.3.5 (review r2, item 2): _apply_visual_style() now also
	# builds the stepper "-"/"+" buttons (_add_stepper_buttons()), so it must
	# run before _wire_focus_chain() -- the same "every dynamic row already
	# exists before the chain is built" ordering _build_specials_checklist()
	# already depends on (this file's own _wire_focus_chain() docstring).
	_apply_visual_style()
	_update_host_only_state()
	_wire_focus_chain()
	# Bontago-mp0.3.5 (review r2, item 1): %MapVariantOption is hidden now
	# (%MapComboOption is its visible front end) -- grabbing focus on a
	# hidden control left ScrollContainer's own "scroll the focused control
	# into view" behavior scrolling to that control's stale/zero rect,
	# shifting the whole card sideways in every capture.
	_map_combo_option.grab_focus()


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

## Bontago-1pi.30: range and step of both timer sliders come from MatchConfig, so
## the .tscn's authored numbers can never drift from the clamp the host applies.
## The match slider runs Off (0) to the maximum; the round slider's minimum is
## retargeted per mode by _refresh_timer_control().
func _configure_timer_sliders() -> void:
	for slider: HSlider in [_match_timer_slider, _round_timer_slider]:
		slider.step = TIMER_SLIDER_STEP_MINUTES
		slider.max_value = MatchConfig.ROUND_TIMER_MAX_MINUTES
	_match_timer_slider.min_value = MatchConfig.ROUND_TIMER_OFF_MINUTES
	_round_timer_slider.min_value = MatchConfig.ROUND_TIMER_MIN_MINUTES
	_match_timer_slider.value = MatchConfig.ROUND_TIMER_OFF_MINUTES
	_round_timer_slider.value = MatchConfig.ROUND_TIMER_DEFAULT_MINUTES
	# An unchanged value emits no signal, so seed what _on_timer_slider_changed() compares against.
	_timer_previous_minutes[_match_timer_slider] = int(_match_timer_slider.value)
	_timer_previous_minutes[_round_timer_slider] = int(_round_timer_slider.value)


func _populate_options() -> void:
	_configure_timer_sliders()
	_fill_option(_map_variant_option, MAP_VARIANT_LABELS)
	_fill_option(_map_size_option, MAP_SIZE_LABELS)
	var combo_labels: Array[String] = []
	for variant_label: String in MAP_VARIANT_LABELS:
		for size_label: String in MAP_SIZE_LABELS:
			combo_labels.append("%s · %s" % [variant_label, size_label])
	_fill_option(_map_combo_option, combo_labels)
	_map_combo_option.item_selected.connect(_on_map_combo_selected)
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
	# Bontago-22y.10: order must match MatchConfig.WeatherMode.
	# Labels come from the enum names, so a new weather type needs no edit here.
	_fill_option(_weather_option, MatchWeather.mode_labels())
	# Bontago-470.4: order must match MatchConfig.SkyThemeMode.
	_fill_option(_sky_theme_option, ["Day", "Night", "Random", "Cycle", "Dawn"])
	# Bontago-22y.11: order must match MatchConfig.GameMode. Reserved modes are
	# listed but disabled, so neither the mouse nor the gamepad popup can pick
	# one; MatchConfig.resolve_game_mode() also rejects them on the wire.
	# DECISION (Bontago-6fc.1): one timer control per mode (_refresh_timer_control).
	_fill_option(_game_mode_option, Array(MatchConfig.GAME_MODE_LABELS))
	for mode_index: int in range(_game_mode_option.item_count):
		_game_mode_option.set_item_disabled(mode_index, not MatchConfig.is_game_mode_selectable(mode_index))
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


## DECISION (ui/Lobby.gd, Bontago-xtq.32): ui/Lobby.tscn carries zero static
## focus_neighbor_* NodePaths (unlike ui/MainMenu.tscn's authored chain) --
## the specials checklist is built dynamically by _build_specials_checklist()
## and doesn't exist yet when the scene file is authored, so any chain
## covering it has to be computed at runtime. Mirrors ui/OptionsMenu.gd's own
## _wire_focus_chain() (get_path_to()-based circular top/bottom wiring,
## called once from _ready() after every dynamic row exists). Player rows
## (_player_rows, rebuilt on every roster change) are plain
## HBoxContainer(ColorRect, Label) with no focusable child, so they never
## enter the chain and a later roster change can't invalidate it.
## Bontago-mp0.3.5 (review r3, problem 2): the specials checklist and the
## optional rule controls now live inside %AdvancedPopup, only reachable
## once it's open -- they get their *own* closed loop (_wire_loop() again,
## just called a second time) instead of sharing the main card's loop, so a
## Tab press on the main screen can never land on a control the popup hasn't
## opened yet. %AdvRulesBar replaces them in the main loop as the single
## always-visible entry point (test_focus_chain_is_a_closed_loop_through_
## every_row() only asserts every one of these unique names has *a* neighbor
## on both sides, not that they share one loop with %StartButton).
func _wire_focus_chain() -> void:
	# Focus order follows the visual order: Round section (mode, timers), then
	# map, players, AI, teams, then the right-hand column.
	var chain: Array[Control] = [
		_game_mode_option, _round_timer_slider, _match_timer_slider,
		_map_combo_option, _sky_theme_option, _player_count_spin, _ai_count_spin, _ai_difficulty_option,
	]
	chain.append_array(_team_buttons)
	chain.append_array([_block_timer_slider, _gravity_slider, _goal_flag_spin, _gifts_check, _special_freq_slider])
	# Bontago-mp0.3.5 (review r2, item 2): the round "-"/"+" stepper buttons
	# aren't slotted into their exact visual rows here -- only that every one
	# of them is somewhere in the closed loop with a focus neighbor on both
	# sides, same as every other control this chain covers.
	chain.append_array(_main_stepper_buttons)
	chain.append_array([_adv_rules_bar, _back_button, _invite_friends_button, _ready_check, _start_button])
	_main_chain = chain
	_wire_loop(_visible_chain(_main_chain))

	var popup_chain: Array[Control] = _popup_chain
	popup_chain.clear()
	for box: CheckBox in _special_checkboxes:
		popup_chain.append(box)
	popup_chain.append_array([_tilt_mode_option, _hole_mode_option])
	popup_chain.append(_sky_team_sum_check)
	popup_chain.append(_weather_option)
	popup_chain.append_array([_sudden_death_check, _turn_based_check, _mid_join_check])
	# Bontago-1pi.18.5: the Experiments checkboxes sit below the rules grid in the
	# popup, so they come after it and before Done (visual order = focus order).
	popup_chain.append_array(_qol_checks)
	popup_chain.append(_advanced_popup_close)
	_wire_loop(_visible_chain(popup_chain))


## Assigns focus_neighbor_top/bottom so [param chain] forms one closed loop,
## wrapping from its last entry back to its first. Shared by the main card's
## loop and the advanced-rules popup's own separate loop (_wire_focus_chain()).
## The advanced-popup focus chain; hidden controls (the Reach the Sky toggle
## outside its mode) are skipped so gamepad focus can never land on them.
var _popup_chain: Array[Control] = []
var _main_chain: Array[Control] = []


func _visible_chain(chain: Array[Control]) -> Array[Control]:
	var conditional: Array[Control] = [_sky_team_col, _match_timer_col, _round_timer_col, _sudden_death_col]
	var out: Array[Control] = []
	for control: Control in chain:
		var hidden: bool = false
		for column: Control in conditional:
			if not column.visible and column.is_ancestor_of(control):
				hidden = true
		if not hidden:
			out.append(control)
	return out


func _wire_loop(chain: Array[Control]) -> void:
	for i: int in range(chain.size()):
		var current: Control = chain[i]
		var prev: Control = chain[(i - 1 + chain.size()) % chain.size()]
		var next: Control = chain[(i + 1) % chain.size()]
		current.focus_neighbor_top = current.get_path_to(prev)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_mode = Control.FOCUS_ALL


func _connect_control_signals() -> void:
	_ai_difficulty_option.item_selected.connect(_on_option_changed)
	_team_mode_option.item_selected.connect(_on_option_changed)
	_tilt_mode_option.item_selected.connect(_on_option_changed)
	_hole_mode_option.item_selected.connect(_on_option_changed)
	_weather_option.item_selected.connect(_on_option_changed)
	# Bontago-6fc.1: retarget the timer control before the publish below reads it.
	_game_mode_option.item_selected.connect(_on_game_mode_picked)
	_game_mode_option.item_selected.connect(_on_option_changed)
	_round_timer_slider.value_changed.connect(_on_timer_slider_changed.bind(_round_timer_slider))
	_round_timer_slider.gui_input.connect(_on_timer_slider_gui_input.bind(_round_timer_slider))
	_sky_team_sum_check.toggled.connect(_on_toggled)
	_game_mode_option.item_selected.connect(_refresh_sky_controls)
	_sky_theme_option.item_selected.connect(_on_option_changed)
	_player_count_spin.value_changed.connect(_on_value_changed)
	# Bontago-1pi.9b: a seat-count edit can shrink the room left for bots, so
	# this recomputes %AiCountSpin's own max_value on every host edit too, not
	# only on a roster event (_on_roster_changed already covers "a human
	# joined/left"; this covers "the host changed the seat count").
	_player_count_spin.value_changed.connect(func(_v: float) -> void: _clamp_ai_count_to_seats())
	_ai_count_spin.value_changed.connect(_on_value_changed)
	_block_timer_slider.value_changed.connect(_on_value_changed)
	_gravity_slider.value_changed.connect(_on_value_changed)
	_goal_flag_spin.value_changed.connect(_on_value_changed)
	_special_freq_slider.value_changed.connect(_on_value_changed)
	_match_timer_slider.value_changed.connect(_on_timer_slider_changed.bind(_match_timer_slider))
	_match_timer_slider.gui_input.connect(_on_timer_slider_gui_input.bind(_match_timer_slider))
	_gifts_check.toggled.connect(_on_toggled)
	_sudden_death_check.toggled.connect(_on_toggled)
	_turn_based_check.toggled.connect(_on_toggled)
	_mid_join_check.toggled.connect(_on_toggled)
	for qol_check: CheckBox in _qol_checks:
		qol_check.toggled.connect(_on_toggled)
	for i: int in range(_team_buttons.size()):
		_team_buttons[i].pressed.connect(_on_team_button_pressed.bind(i))


## Bontago-mp0.3.5: the segmented control's own handler -- writes the picked
## index into the hidden %TeamModeOption (the actual source of truth
## _config_from_controls()/_apply_data() already read/write) and republishes
## exactly like any other host edit (_on_setting_changed()), rather than
## duplicating that publish logic here.
func _on_team_button_pressed(index: int) -> void:
	_team_mode_option.selected = index
	_on_setting_changed()


## Mirrors [param team_mode] onto the segmented buttons' pressed state
## without re-emitting `pressed` (ButtonGroup would otherwise fight a
## programmatic `button_pressed = true` on the wrong index during
## _apply_data()'s remote-data guard).
func _sync_team_segmented(team_mode: int) -> void:
	for i: int in range(_team_buttons.size()):
		_team_buttons[i].button_pressed = i == team_mode


## Bontago-mp0.3.5 (review r2, item 2): inserts a round "-" button before
## [param spin] and a round "+" button after it, in [param spin]'s own
## parent HBoxContainer -- both just nudge [param spin].value by one step()
## and let SpinBox's own existing value_changed -> _on_value_changed()
## wiring do the rest, so this never duplicates the round-trip/clamp logic.
## Appends both to [param target] (the main card's or the popup's own
## _wire_focus_chain() loop -- review r3, problem 2) so
## _update_host_only_state() (which walks _settings_controls, populated from
## both target arrays in _ready()) gates them exactly like every other
## host-only control.
##
## Bontago-mp0.3.5 (review r3, problem 3): the SpinBox itself keeps min/max/
## step/value/value_changed exactly as before (every get_node("%...").value
## read/write in this file and in tests/unit/test_lobby.gd is untouched) --
## only its native up/down spinner buttons are hidden, via the "buttons_width"
## theme constant SpinBox itself exposes for exactly this (confirmed against
## the running engine's ThemeDB.get_default_theme().get_constant_list(
## "SpinBox"), not guessed), so the round pill buttons are the only visible
## way to nudge it and it reads as a plain bordered value field.
## Bontago-mp0.3.5 (polish pass, problem 2): mockup 11 draws each stepper as
## ONE sunken pill -- "[label] (-) value (+)" -- not a bordered SpinBox field
## flanked by two separate button pills. [param spin] keeps its min/max/step/
## value/value_changed exactly as before (every get_node("%...").value read/
## write in this file and in tests/unit/test_lobby.gd is untouched) but is
## hidden (`visible = false`, so a Container skips it entirely -- no reparent,
## no owner-reassignment bug like the old wrapper-HBoxContainer approach had
## to work around); a plain borderless Label shows its value, kept in sync by
## [param spin]'s own value_changed (which Range emits for a program matic
## `.value = x` too, so a remote _apply_data() update reaches it exactly like
## a button press does). [param inline_label], when given, is one of this
## file's own tscn-authored captions (%PlayersSubLabel/%AiSubLabel) -- hidden
## and its text folded into the pill's own left end instead of sitting on a
## separate row above it (mockup 11 has no separate "Players"/"AI" caption
## row; the word lives inside the pill).
func _add_stepper_buttons(spin: SpinBox, target: Array[Button], inline_label: Label = null) -> void:
	MenuStyleFactory.hide_spinbox_arrows(spin)
	spin.visible = false

	var parent: Node = spin.get_parent()
	var index: int = spin.get_index()
	var scene_owner: Node = spin.owner
	var pill: PanelContainer = PanelContainer.new()
	pill.size_flags_horizontal = spin.size_flags_horizontal
	pill.add_theme_stylebox_override("panel", MenuStyleFactory.make_well_pill(tuning))
	parent.add_child(pill)
	parent.move_child(pill, index)
	pill.owner = scene_owner

	var content: HBoxContainer = HBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	pill.add_child(content)

	if inline_label != null:
		inline_label.visible = false
		var name_label: Label = Label.new()
		name_label.text = inline_label.text
		name_label.add_theme_font_size_override("font_size", 13)
		content.add_child(name_label)
		var spacer: Control = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(spacer)

	var minus: Button = Button.new()
	minus.text = "−"
	minus.pressed.connect(func() -> void: spin.value = maxf(spin.min_value, spin.value - spin.step))
	var value_label: Label = Label.new()
	value_label.custom_minimum_size = Vector2(20.0, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.text = str(int(spin.value))
	spin.value_changed.connect(func(_v: float) -> void: value_label.text = str(int(spin.value)))
	var plus: Button = Button.new()
	plus.text = "+"
	plus.pressed.connect(func() -> void: spin.value = minf(spin.max_value, spin.value + spin.step))
	content.add_child(minus)
	content.add_child(value_label)
	content.add_child(plus)
	MenuStyleFactory.apply_flat_stepper_button(minus, tuning)
	MenuStyleFactory.apply_flat_stepper_button(plus, tuning)
	value_label.add_theme_color_override("font_color", tuning.ink_color)
	target.append(minus)
	target.append(plus)
	_settings_controls.append(minus)
	_settings_controls.append(plus)


## assets-audio package: UI button press/hover has no Events signal of its
## own (it isn't gameplay), so this calls Sfx directly -- the one named
## exception to "Sfx listens, nothing calls it" (autoload/Sfx.gd's header).
## Scoped to actual buttons, not every settings control, so dragging a
## slider doesn't spam hover sounds.
func _connect_click_and_hover_sounds() -> void:
	var buttons: Array[BaseButton] = [_start_button, _invite_friends_button, _ready_check, _back_button]
	for button: BaseButton in buttons:
		button.pressed.connect(_on_sound_button_pressed)
		button.mouse_entered.connect(_on_sound_button_hovered)


func _on_sound_button_pressed() -> void:
	Sfx.play(AudioConfig.EVENT_CLICK)


func _on_sound_button_hovered() -> void:
	Sfx.play(AudioConfig.EVENT_HOVER)


## Bontago-xtq.32 redo: mirrors ui/MainMenu.gd's _apply_visual_style() -- the
## same cream-card + pastel-pill language (docs/art_mockups/
## 11-lobby-layered-pastel.png), built entirely from ui/theme/
## MenuStyleFactory.gd's StyleBoxFlat helpers on top of the shared
## ui/theme/stackfall_theme.tres Theme (no image assets, per the brief).
##
## DECISION (ui/Lobby.gd, Bontago-xtq.32): mockup 11 shows each column as a
## front card with two peeking mint/apricot "shadow" cards behind it, the
## same triple-stack ui/MainMenu.gd's %ShadowApricot/%ShadowMint achieve via
## a CenterContainer sized to each child's own minimum size. ui/Lobby.tscn's
## "Settings"/"Players" columns instead need size_flags_horizontal/vertical
## = 3 to fill the available width of their HBoxContainer ("Columns"), which
## a CenterContainer would collapse back down to minimum size -- so this
## keeps a single flat cream PanelContainer card per column (no doubled
## shadow cards) rather than risk breaking that fill layout within the
## remaining verification budget. Reported as a known simplification versus
## the mockup in the handback.
##
## DECISION (ui/Lobby.gd + ui/Lobby.tscn, Bontago-xtq.32 redo #3): the redo #2
## DECISION directly above this one shipped without a Back button, reasoning
## a decorative button with no listener was worse than none. The redo #3
## brief now explicitly requires one, so %BackButton emits back_requested
## (this file's new signal, just above start_requested) instead of calling
## into game/Main.gd directly -- keeping this file's own "no node paths into
## game/Main.gd" rule intact while giving Main.gd something to connect to.
func _apply_visual_style() -> void:
	_settings_card.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(tuning.card_cream_color, tuning))
	_players_card.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(tuning.card_cream_color, tuning))

	# Bontago-mp0.3.5 (review r2, item 2): round "-"/"+" stepper pills flanking
	# every SpinBox (mockup 11) -- the SpinBox itself stays exactly as it was
	# (same min/max/step, same value_changed wiring), these just give it a
	# second, gamepad-focusable way to nudge the value by one step, and (review
	# r3, problem 3) hides the native up/down spinner entirely.
	_add_stepper_buttons(_player_count_spin, _main_stepper_buttons, _players_sub_label)
	_add_stepper_buttons(_ai_count_spin, _main_stepper_buttons, _ai_sub_label)
	_add_stepper_buttons(_goal_flag_spin, _main_stepper_buttons)
	# Bontago-1pi.30: the two timer controls are sliders now (no stepper pills);
	# gamepad left/right is the Slider's own ui_left/ui_right handling, up/down
	# moves focus along _wire_focus_chain().

	# Bontago-mp0.3.5 (review r2, item 1): a small round disc icon (dark
	# slate fill, light rim) beside %MapComboOption -- the same two-tone
	# read as ui/MenuDiorama.gd's own island, just flattened into a 2D chip.
	var thumb_box: StyleBoxFlat = StyleBoxFlat.new()
	thumb_box.bg_color = tuning.pill_dark_slate_color
	thumb_box.border_color = tuning.island_rim_color
	thumb_box.set_border_width_all(2)
	thumb_box.set_corner_radius_all(14)
	_map_thumbnail.add_theme_stylebox_override("panel", thumb_box)

	MenuStyleFactory.apply_pill(
		_start_button, tuning.pill_coral_color, tuning.pill_coral_hover_color, tuning.label_ink_light_color, tuning
	)
	MenuStyleFactory.apply_pill(
		_invite_friends_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning
	)
	MenuStyleFactory.apply_pill(
		_back_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning
	)

	var well_box: StyleBoxFlat = MenuStyleFactory.make_well(tuning)
	_block_timer_slider.add_theme_stylebox_override("slider", well_box)
	_match_timer_slider.add_theme_stylebox_override("slider", well_box)
	_round_timer_slider.add_theme_stylebox_override("slider", well_box)
	_gravity_slider.add_theme_stylebox_override("slider", well_box)
	_special_freq_slider.add_theme_stylebox_override("slider", well_box)
	for chip: PanelContainer in [_block_timer_chip, _gravity_chip, _special_freq_chip]:
		chip.add_theme_stylebox_override("panel", MenuStyleFactory.make_badge(tuning.pill_coral_color, tuning))
		var chip_label: Label = chip.get_child(0) as Label
		chip_label.add_theme_color_override("font_color", tuning.label_ink_light_color)

	# Bontago-xtq.32 redo #3: compact toggle chips (specials grid + the
	# Advanced Rules strip's two CheckButtons) replace round-1's full-width
	# red CheckBox bars -- off = cream pill, on = mint pill, reusing the same
	# tunables apply_pill() above already draws from (no new MenuVisualTuning
	# exports). _gifts_check keeps its own %GoalFlagRow placement in the
	# tscn but is visually the same chip family.
	for box: CheckBox in _special_checkboxes:
		MenuStyleFactory.apply_toggle_chip(
			box, tuning.pill_cream_color, tuning.pill_cream_hover_color,
			tuning.pill_mint_color, tuning.pill_mint_hover_color, tuning.ink_color, tuning
		)
	_teams_track.add_theme_stylebox_override("panel", MenuStyleFactory.make_well(tuning))
	for team_button: Button in _team_buttons:
		MenuStyleFactory.apply_toggle_chip(
			team_button, tuning.well_color, tuning.well_color,
			tuning.pill_cream_hover_color, tuning.card_cream_color, tuning.ink_color, tuning
		)
		# Bontago-mp0.3.5 (review r2 width fix): a smaller font just for these
		# four buttons keeps "2 teams"/"3 teams"/"4 teams" from being the
		# single widest row in %SettingsLeft -- the segmented track is a
		# secondary control, not body text, so a slightly denser size reads
		# fine here without touching the shared pill font size anywhere else.
		team_button.add_theme_font_size_override("font_size", 13)
	# Bontago-1pi.18.5: the Experiments checkboxes are the same chip family as the
	# specials grid above (no new colours, no new tunables).
	for qol_check: CheckBox in _qol_checks:
		MenuStyleFactory.apply_toggle_chip(
			qol_check, tuning.pill_cream_color, tuning.pill_cream_hover_color,
			tuning.pill_mint_color, tuning.pill_mint_hover_color, tuning.ink_color, tuning
		)
	var chips: Array[Button] = [_gifts_check, _sudden_death_check, _turn_based_check, _mid_join_check, _ready_check]
	for chip: Button in chips:
		MenuStyleFactory.apply_toggle_chip(
			chip, tuning.pill_cream_color, tuning.pill_cream_hover_color,
			tuning.pill_mint_color, tuning.pill_mint_hover_color, tuning.ink_color, tuning
		)

	var captions: Array[Label] = [_specials_label, _advanced_rules_label, _experiments_label]
	for caption: Label in captions:
		caption.add_theme_color_override("font_color", tuning.label_muted_color)

	_apply_advanced_rules_popup_style()

	_status_badge.add_theme_stylebox_override("panel", MenuStyleFactory.make_badge(tuning.pill_cream_color, tuning))
	_gamepad_hint_pill.add_theme_stylebox_override("panel", MenuStyleFactory.make_badge(tuning.pill_cream_color, tuning))
	_waiting_status_pill.add_theme_stylebox_override("panel", MenuStyleFactory.make_badge(tuning.pill_cream_color, tuning))
	_waiting_status_label.add_theme_color_override("font_color", tuning.ink_color)
	_status_badge_label.add_theme_color_override("font_color", tuning.ink_color)
	_header_title.add_theme_color_override("font_color", tuning.ink_color)
	# Bontago-mp0.3.5 (review r1, item 2): same soft offset shadow treatment as
	# ui/MainMenu.gd's %TitleShadow, using Label's own shadow theme overrides
	# instead of a second node (a plain Label, unlike %Title's two-tone
	# RichTextLabel, can draw its own shadow without a duplicate copy).
	_header_title.add_theme_color_override("font_shadow_color", tuning.title_shadow_color)
	_header_title.add_theme_constant_override("shadow_offset_x", int(tuning.title_shadow_offset_px.x))
	_header_title.add_theme_constant_override("shadow_offset_y", int(tuning.title_shadow_offset_px.y))
	# Bontago-mp0.3.5 (review r3, problem 6): mockup 11's small "Stackfall"
	# wordmark reads bold and dark, not the tiny letter-spaced grey caption
	# treatment every other eyebrow label on this screen uses -- %Eyebrow's
	# own theme_type_variation is TitleLabel (ui/Lobby.tscn), same bold font
	# as %HeaderTitle, just a smaller font_size (set in the tscn); only the
	# color needs to flip from muted grey to the shared ink color here.
	_header_eyebrow.add_theme_color_override("font_color", tuning.ink_color)
	_player_count_label.add_theme_color_override("font_color", tuning.ink_color)
	_update_status_badge()


## Bontago-mp0.3.5 (review r3, problem 2): the bar itself is a cream pill
## Button (its text stays empty; %AdvRulesBarLabel + %AdvRulesChips are child
## Controls with mouse_filter = MOUSE_FILTER_IGNORE, so clicks fall through
## to %AdvRulesBar (the Button) underneath them -- the same "icon + label
## inside a Button" pattern used everywhere else in Godot's own UI).
##
## Bontago-mp0.3.5 (polish pass, problem 1): %AdvRulesBarPanel (a
## PanelContainer, not the Button) is now the visible background -- a flat
## cream pill with real content-margin padding -- and %AdvRulesBar itself is
## styled fully transparent (apply_flat_stepper_button(), same "no background
## in any state, keep the shared focus ring" helper the stepper glyphs use)
## so the two don't double-draw a background. Each chip is a flat, shadow-
## less make_flat_chip() pill (not make_badge()'s raised/shadowed pill) in a
## lighter beige than the bar itself, smaller text (set in ui/Lobby.tscn),
## so they read as light summary tokens rather than a second row of buttons.
func _apply_advanced_rules_popup_style() -> void:
	_adv_rules_bar_panel.add_theme_stylebox_override("panel", MenuStyleFactory.make_badge(tuning.pill_cream_color, tuning))
	MenuStyleFactory.apply_flat_stepper_button(_adv_rules_bar, tuning)
	for chip_label: Label in [
		_adv_chip_tilt, _adv_chip_hole,
		_adv_chip_sudden, _adv_chip_turn, _adv_chip_specials, _adv_chip_experiments,
	]:
		var chip_panel: PanelContainer = chip_label.get_parent() as PanelContainer
		chip_panel.add_theme_stylebox_override("panel", MenuStyleFactory.make_flat_chip(tuning.pill_cream_hover_color, tuning))
		chip_label.add_theme_color_override("font_color", tuning.ink_color)
	_advanced_popup_card.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(tuning.card_cream_color, tuning))
	MenuStyleFactory.apply_pill(
		_advanced_popup_close, tuning.pill_coral_color, tuning.pill_coral_hover_color, tuning.label_ink_light_color, tuning
	)


## Bontago-mp0.3.5 (review r3, problem 2): "Activating the bar (click /
## ui_accept) opens a modal popup ... focus returns to the bar" -- Button's
## own `pressed` signal already fires for both a mouse click and ui_accept
## while focused (BaseButton's default shortcut behavior), so this is the
## bar's sole `pressed` handler, wired in _ready().
func _open_advanced_popup() -> void:
	_advanced_popup.visible = true
	var first: Control = _special_checkboxes[0] if not _special_checkboxes.is_empty() else _tilt_mode_option
	first.grab_focus()


func _close_advanced_popup() -> void:
	_advanced_popup.visible = false
	_adv_rules_bar.grab_focus()


## ui_cancel closes the popup from anywhere inside it (brief: "closable with
## a Close/Done pill and ui_cancel"). %AdvancedPopupClose's own `pressed`
## already covers the pill; this covers the Esc/gamepad-B path, consuming the
## event so it doesn't also trigger whatever ui_cancel does one layer up
## (e.g. game/Main.gd's own pause/back handling).
##
## Bontago-1pi.15.1 fix: with the popup closed, ui_cancel now backs all the
## way out of the lobby too (%BackButton's own back_requested, same as a
## click/ui_accept on it) -- previously B did nothing here at all unless the
## advanced-rules popup happened to be open, the reported "B never goes back
## in any menu" gap.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"lobby_quick_advanced"):
		if _advanced_popup.visible:
			_close_advanced_popup()
		else:
			_open_advanced_popup()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"lobby_quick_start"):
		if not _advanced_popup.visible and _start_button.visible and not _start_button.disabled:
			_on_start_pressed()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if _advanced_popup.visible:
		_close_advanced_popup()
	else:
		_on_back_pressed()
	get_viewport().set_input_as_handled()


## Live summary chips on %AdvRulesBar (brief: "label + summary chips that
## update live"), driven straight off the same controls _config_from_controls()
## reads -- called once from _apply_data() so every path that can change one
## of these five settings (a host's own edit, which round-trips through
## _publish_lobby_data() -> _apply_data(), or a remote update) refreshes the
## bar without a second signal wiring.
func _update_advanced_rules_summary() -> void:
	_update_timer_values()
	_adv_chip_tilt.text = "Tilt: %s" % (
		"specials only" if _tilt_mode_option.selected == MatchConfig.TiltMode.SPECIALS_ONLY else "physical balance"
	)
	var hole_labels: Array[String] = ["temporary", "permanent", "off"]
	_adv_chip_hole.text = "Holes: %s" % hole_labels[clampi(_hole_mode_option.selected, 0, hole_labels.size() - 1)]
	_adv_chip_sudden.text = "Sudden death: %s" % ("on" if _sudden_death_check.button_pressed else "off")
	_adv_chip_turn.text = "Turn-based: %s" % ("on" if _turn_based_check.button_pressed else "off")
	var enabled_count: int = 0
	for box: CheckBox in _special_checkboxes:
		if box.button_pressed:
			enabled_count += 1
	_adv_chip_specials.text = "Specials: %d/%d" % [enabled_count, _special_checkboxes.size()]
	# Bontago-1pi.18.5: how many of the four opt-in experiments are on.
	var experiments_on: int = 0
	for qol_check: CheckBox in _qol_checks:
		if qol_check.button_pressed:
			experiments_on += 1
	_adv_chip_experiments.text = "Experiments: %d on" % experiments_on


## Bontago-mp0.3.5: tools/capture_mockup08.gd's own `--lobby-advanced` frame
## (public wrapper so the capture tool, which isn't part of this package's
## own private-method surface, doesn't reach into `_open_advanced_popup()`
## directly).
func debug_open_advanced_rules_popup() -> void:
	_open_advanced_popup()


func _on_back_pressed() -> void:
	back_requested.emit()


func _on_option_changed(_index: int) -> void:
	_on_setting_changed()


## Bontago-mp0.3.5 (review r2, item 1): %MapComboOption's own handler --
## decodes the combined index back into the hidden %MapVariantOption/
## %MapSizeOption selections (the real source of truth _config_from_controls()
## already reads) and republishes exactly like any other host edit, the same
## pattern ui/Lobby.gd's _on_team_button_pressed() uses for the segmented
## Teams control.
func _on_map_combo_selected(index: int) -> void:
	var size_count: int = MAP_SIZE_LABELS.size()
	_map_variant_option.selected = index / size_count
	_map_size_option.selected = index % size_count
	_on_setting_changed()


func _on_value_changed(_value: float) -> void:
	_on_setting_changed()


## The team-aggregation toggle exists only for Reach the Sky.
## Bontago-6fc.1: a host picked a mode. Moving between timer families (classic
## <-> timed, Elimination <-> CTF/Sky) resets the control to the new mode's
## default; CTF <-> Reach the Sky keeps the chosen length.
func _on_game_mode_picked(index: int) -> void:
	var old_mode: int = _timer_mode
	var new_mode: int = MatchConfig.resolve_game_mode(index)
	_refresh_timer_control(new_mode)
	if not MatchConfig.same_timer_family(old_mode, new_mode):
		_timer_slider_for(new_mode).value = MatchConfig.timer_default_minutes(new_mode)
	_update_timer_values()


func _timer_slider_for(mode: int) -> HSlider:
	return _match_timer_slider if MatchConfig.timer_is_match_timer(mode) else _round_timer_slider


## Shows the one timer control `mode` uses, with its label and minimum, and
## hides the sudden-death toggle outside classic (the only mode that has it).
func _refresh_timer_control(mode: int) -> void:
	_timer_mode = mode
	var classic: bool = MatchConfig.timer_is_match_timer(mode)
	_match_timer_col.visible = classic
	_sudden_death_col.visible = classic
	_round_timer_col.visible = not classic
	var was_applying: bool = _applying_remote_data
	_applying_remote_data = true
	_round_timer_slider.min_value = MatchConfig.timer_min_minutes(mode) if not classic else MatchConfig.ROUND_TIMER_MIN_MINUTES
	_applying_remote_data = was_applying
	_match_timer_col.tooltip_text = TIMER_TIP_MATCH
	_round_timer_col.tooltip_text = TIMER_TIP_DOMINATION if mode == MatchConfig.GameMode.DOMINATION else TIMER_TIP_ROUND
	_game_mode_option.tooltip_text = MODE_TIPS[mode] if mode >= 0 and mode < MODE_TIPS.size() else ""
	_update_timer_values()
	if not _main_chain.is_empty():
		_wire_loop(_visible_chain(_main_chain))
	if not _popup_chain.is_empty():
		_wire_loop(_visible_chain(_popup_chain))


## The value label under each timer slider ("5 min", or "Off" at its leftmost stop).
func _update_timer_values() -> void:
	_match_timer_value.text = _timer_value_text(int(_match_timer_slider.value), false)
	_round_timer_value.text = _timer_value_text(
		int(_round_timer_slider.value), _timer_mode == MatchConfig.GameMode.DOMINATION
	)


static func _timer_value_text(minutes: int, required: bool) -> String:
	if minutes <= MatchConfig.ROUND_TIMER_OFF_MINUTES:
		return TIMER_OFF_TEXT
	return (TIMER_REQUIRED_FORMAT if required else TIMER_VALUE_FORMAT) % minutes


## Either timer slider moved (host drag, gamepad left/right, or a programmatic
## write). Host edits skip the 1-minute gap so the stops read Off, 2, 3 ... 30:
## stepping up from Off lands on 2 and stepping down from 2 lands on Off. A value
## applied from lobby data is shown as-is (the host's sanitize() already decided).
func _on_timer_slider_changed(value: float, slider: HSlider) -> void:
	var minutes: int = int(value)
	var previous: int = int(_timer_previous_minutes.get(slider, minutes))
	var in_gap: bool = minutes > MatchConfig.ROUND_TIMER_OFF_MINUTES and minutes < MatchConfig.ROUND_TIMER_MIN_MINUTES
	if in_gap and not _applying_remote_data:
		minutes = MatchConfig.ROUND_TIMER_MIN_MINUTES if minutes > previous else MatchConfig.ROUND_TIMER_OFF_MINUTES
		slider.set_value_no_signal(minutes)
	_timer_previous_minutes[slider] = minutes
	_update_timer_values()
	_on_setting_changed()


## Gamepad / keyboard left-right on a focused timer slider steps it one minute (ui_up
## and ui_down stay with the focus chain). DECISION: the lobby steps the slider itself
## and accepts the event instead of leaving it to Slider's built-in ui_left/ui_right
## handling, so this rule is exercised by a plain `gui_input` emit in tests (GUT cannot
## route key/pad events to a focused control) and a read-only (client) slider is skipped
## explicitly. The 1-minute gap is skipped by _on_timer_slider_changed().
func _on_timer_slider_gui_input(event: InputEvent, slider: HSlider) -> void:
	if not slider.editable:
		return
	var direction: int = 0
	if event.is_action_pressed(&"ui_left", true):
		direction = -1
	elif event.is_action_pressed(&"ui_right", true):
		direction = 1
	if direction == 0:
		return
	slider.accept_event()
	slider.value += direction * slider.step


func _refresh_sky_controls(_index: int = 0) -> void:
	_refresh_timer_control(MatchConfig.resolve_game_mode(_game_mode_option.selected))
	_sky_team_col.visible = _game_mode_option.selected == MatchConfig.GameMode.REACH_THE_SKY
	if not _popup_chain.is_empty():
		_wire_loop(_visible_chain(_popup_chain))


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
	config.weather_mode = _weather_option.selected as MatchConfig.WeatherMode
	config.sky_theme_mode = _sky_theme_option.selected as MatchConfig.SkyThemeMode
	config.match_timer_minutes = int(_match_timer_slider.value)
	config.game_mode = MatchConfig.resolve_game_mode(_game_mode_option.selected)
	config.round_timer_minutes = int(_round_timer_slider.value)
	config.sky_team_sum = _sky_team_sum_check.button_pressed
	config.sudden_death = _sudden_death_check.button_pressed
	config.turn_based = _turn_based_check.button_pressed
	config.allow_mid_match_join = _mid_join_check.button_pressed
	config.enabled_specials = _enabled_specials_from_checkboxes()
	# DECISION (ui/Lobby.gd, Bontago-1pi.18.5): always publish an explicit qol
	# (never null) so the four checkboxes are the single source of the enable
	# flags -- a toggle left on in the F4 panel cannot leak into a lobby match
	# the host sees as "all off". Numeric parameters stay in the shared resource.
	config.qol = _qol_from_controls()
	return config


## The four Experiments checkboxes folded onto a copy of the shared F4 resource
## (QolExperiments.with_toggles() never modifies QOL_SHARED).
func _qol_from_controls() -> QolExperiments:
	return QolExperiments.with_toggles(
		QOL_SHARED, _qol_timer_pause_check.button_pressed, _qol_backlog_check.button_pressed,
		_qol_goal_radius_check.button_pressed, _qol_gift_slot_check.button_pressed
	)


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
	_map_combo_option.selected = int(config.map_variant) * MAP_SIZE_LABELS.size() + int(config.map_size)
	_player_count_spin.value = config.player_count
	_ai_count_spin.value = config.ai_count
	_ai_difficulty_option.selected = config.ai_difficulty
	_team_mode_option.selected = config.team_mode
	_sync_team_segmented(config.team_mode)
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
	_weather_option.selected = config.weather_mode
	_sky_theme_option.selected = config.sky_theme_mode
	# Bontago-6fc.1: the timer control's minimum follows the mode, so it is
	# retargeted before either value is written (Elimination may hold 0).
	_game_mode_option.selected = config.game_mode
	_refresh_timer_control(config.game_mode)
	_match_timer_slider.value = config.match_timer_minutes
	_round_timer_slider.value = config.round_timer_minutes
	_sky_team_sum_check.button_pressed = config.sky_team_sum
	_refresh_sky_controls()
	_sudden_death_check.button_pressed = config.sudden_death
	_turn_based_check.button_pressed = config.turn_based
	_mid_join_check.button_pressed = config.allow_mid_match_join
	_apply_enabled_specials_to_checkboxes(config.enabled_specials)
	# Bontago-1pi.18.5: a null qol (an older host, or config/match_defaults.tres)
	# reads as every experiment off. Inside the guard, so a client mirrors the
	# host without re-publishing.
	var qol: QolExperiments = config.qol
	_qol_timer_pause_check.button_pressed = qol != null and qol.timer_pause_enabled
	_qol_backlog_check.button_pressed = qol != null and qol.backlog_enabled
	_qol_goal_radius_check.button_pressed = qol != null and qol.goal_radius_enabled
	_qol_gift_slot_check.button_pressed = qol != null and qol.gift_slot_enabled
	_applying_remote_data = false
	_update_advanced_rules_summary()
	# Bontago-1pi.9b: re-bound %AiCountSpin's max after every value assignment
	# above (player_count and ai_count both just moved, possibly from a wire
	# value that predates this clamp) -- see _clamp_ai_count_to_seats()'s own
	# header for why this can't just live in _mirror_player_count_to_peers().
	_clamp_ai_count_to_seats()

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
	roster.append_array(_bot_roster_entries(config))
	return roster


## M5 P4 (docs/M5_PLAN.md): one synthetic row per bot seat, slot_id running
## from player_count - ai_count to player_count - 1 -- the same formula
## autoload/match/MatchLifecycle.gd's _build_slots() uses for
## PlayerSlot.is_bot, so the lobby preview and the real match slots never
## disagree about which ids are bots. A bot has no connected peer behind it
## to ready up, so ready is always true; Net.all_peers_ready() only ever
## iterates real peers (its own header), so this can never let an unready
## human's Start gate open.
##
## Split out of _build_roster() (Bontago-1pi.9b) so _apply_roster() can
## re-derive "how many bots exist right now" from [param config] alone,
## instead of trusting an incoming roster's own bot rows -- a live
## Events.net_roster_changed payload (autoload/Net.gd's _broadcast_roster())
## never includes them, only _build_roster()'s own outbound publish does, so
## the two payload shapes used to disagree about whether bots were "in" the
## roster at all (see _apply_roster()'s own header for the confusion that
## caused).
func _bot_roster_entries(config: MatchConfig) -> Array[Dictionary]:
	var bots: Array[Dictionary] = []
	var difficulty: String = _AI_DIFFICULTY_LABELS[
		clampi(config.ai_difficulty, 0, _AI_DIFFICULTY_LABELS.size() - 1)
	]
	var bot_start: int = config.player_count - config.ai_count
	for slot_id: int in range(bot_start, config.player_count):
		var bot_index: int = slot_id - bot_start + 1
		bots.append({
			"peer_id": -1,
			"slot_id": slot_id,
			"name": "Bot %d (%s)" % [bot_index, difficulty],
			"ready": true,
		})
	return bots


## Bontago-mp0.3.5 (review r2, item 4): one white pill row per roster entry --
## a clay-cube icon in the slot's colour (a flat rounded square standing in
## for mockup 11's iso cube glyph, given the time budget), bold name, a small
## muted subtitle ("Host · you" / "LAN · <ping> ms" / "AI · <difficulty>"),
## and a Ready (mint)/Not ready (peach) badge on the right, replacing the
## previous plain "Mira  (ready)" Label row.
func _build_player_row(entry: Dictionary, ready: bool) -> PanelContainer:
	var slot_id: int = int(entry.get("slot_id", -1))
	var peer_id: int = int(entry.get("peer_id", -1))
	var raw_name: String = str(entry.get("name", "?"))
	var display_name: String = raw_name
	var subtitle: String = ""
	if peer_id == -1:
		# Bot rows: _build_roster() packs the difficulty into the name as
		# "Bot 1 (Normal)" -- split it back into a name + subtitle pair.
		var open_paren: int = raw_name.find("(")
		if open_paren != -1:
			display_name = raw_name.substr(0, open_paren).strip_edges()
			subtitle = "AI · %s" % raw_name.substr(open_paren + 1, raw_name.length() - open_paren - 2)
		else:
			subtitle = "AI"
	else:
		var is_local: bool = net_provider != null and peer_id == int(net_provider.local_peer_id())
		# Net.HOST_PEER_ID's own value (ENet convention: the host is always
		# peer id 1) -- autoload/Net.gd's own const, read directly off the
		# real autoload class since net_provider is a Variant test seam here.
		if peer_id == Net.HOST_PEER_ID:
			subtitle = "Host · you" if is_local else "Host"
		elif is_local:
			subtitle = "you"
		else:
			var transport: String = "Steam" if (net_provider != null and bool(net_provider.is_steam_session())) else "LAN"
			subtitle = "%s · %d ms" % [transport, int(entry.get("ping_ms", 0.0))]

	var palette: PackedColorArray = default_config.player_colors
	var slot_color: Color = palette[slot_id] if slot_id >= 0 and slot_id < palette.size() else Color.GRAY

	var row: PanelContainer = PanelContainer.new()
	# Bontago-mp0.3.5 (review r3, problem 5): make_flat_list() draws
	# pill_cream_hover_color, which is the *exact same* Color as
	# card_cream_color (config/MenuVisualTuning.gd) -- the row was blending
	# invisibly into %PlayersCard's own background instead of reading as a
	# raised white pill (mockup 11). tuning.pill_white_color is a real near-
	# white the card can never match.
	row.add_theme_stylebox_override("panel", MenuStyleFactory.make_badge(tuning.pill_white_color, tuning))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var layout: HBoxContainer = HBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	row.add_child(layout)

	var icon: PanelContainer = PanelContainer.new()
	icon.custom_minimum_size = Vector2(24.0, 24.0)
	var icon_box: StyleBoxFlat = StyleBoxFlat.new()
	icon_box.bg_color = slot_color
	icon_box.set_corner_radius_all(6)
	icon.add_theme_stylebox_override("panel", icon_box)
	layout.add_child(icon)

	var text_column: VBoxContainer = VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 0)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label: Label = Label.new()
	name_label.theme_type_variation = &"TitleLabel"
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.text = display_name
	var subtitle_label: Label = Label.new()
	subtitle_label.theme_type_variation = &"CaptionLabel"
	subtitle_label.text = subtitle
	text_column.add_child(name_label)
	text_column.add_child(subtitle_label)
	layout.add_child(text_column)

	var badge: PanelContainer = PanelContainer.new()
	var badge_color: Color = tuning.pill_mint_color if ready else tuning.ground_band_apricot_color
	badge.add_theme_stylebox_override("panel", MenuStyleFactory.make_badge(badge_color, tuning))
	var badge_label: Label = Label.new()
	badge_label.text = ("%s Ready" % char(0x2713)) if ready else ("%s Not ready" % char(0x231A))
	badge_label.add_theme_color_override("font_color", tuning.ink_color)
	badge.add_child(badge_label)
	layout.add_child(badge)
	return row


## DECISION (ui/Lobby.gd, Bontago-1pi.9b): owner playtest -- "the right panel
## lists 'players+bots'/'players', I can add bots up to the player limit" --
## traced to two different roster payload shapes landing here: Net's own
## live roster events (autoload/Net.gd's _broadcast_roster(), reached via
## _on_roster_changed) never include bot rows (Net has no concept of
## ai_count), while a full lobby-data apply's own _build_roster() roster
## does. Whichever happened to run last decided whether the header (and the
## row list) showed bots at all, even though ai_count itself hadn't changed
## -- read by the owner as an inconsistent, confusing count. [param
## roster_data] now only ever supplies the human rows (bot rows inside it,
## if any, are dropped and rebuilt); _bot_roster_entries(_last_config) is the
## single source of truth for the bot rows actually drawn, on every call
## path alike.
func _apply_roster(roster_data: Variant) -> void:
	var incoming: Array = roster_data as Array
	var humans: Array[Dictionary] = []
	for entry_variant: Variant in incoming:
		var entry: Dictionary = entry_variant as Dictionary
		if int(entry.get("peer_id", -1)) != -1:
			humans.append(entry)
	var bots: Array[Dictionary] = (
		_bot_roster_entries(_last_config) if _last_config != null else []
	)
	var display_roster: Array[Dictionary] = humans.duplicate()
	display_roster.append_array(bots)

	# "3 players * 2 bots * 5/8 seats" (or, with no bots, "3 players * 3/8
	# seats") -- unambiguous about how many of each are seated, unlike the
	# old bare "roster.size() / seats" this replaces.
	var seats: int = int(_player_count_spin.value)
	_player_count_label.text = _format_roster_header(humans.size(), bots.size(), seats)

	for row: Node in _player_rows:
		row.queue_free()
	_player_rows.clear()
	var ready_count: int = 0
	for entry: Dictionary in display_roster:
		var ready: bool = bool(entry.get("ready", false))
		if ready:
			ready_count += 1
		var row: PanelContainer = _build_player_row(entry, ready)
		_player_list.add_child(row)
		_player_rows.append(row)
	# Bontago-mp0.3.5 (review r1, item 13): mockup 11's bottom-left status
	# pill ("Waiting for players * 3 of 4 ready"), derived from the exact
	# roster rows just drawn above rather than a second net_provider query.
	_waiting_status_label.text = "%s Waiting for players %s %d of %d ready" % [
		char(0x25CF), char(0xB7), ready_count, display_roster.size(),
	]


## DECISION (ui/Lobby.gd, Bontago-1pi.9b): "3 players" (plural handled),
## "2 bots" only appended when there are any (a 0-bot lobby doesn't need to
## announce that), then the seat fraction against [param seats] -- the
## player_count spin's own current value, i.e. how many seats this lobby is
## configured for, not a hardcoded MatchConfig.PLAYER_COUNT_MAX.
func _format_roster_header(humans: int, bots: int, seats: int) -> String:
	var human_word: String = "player" if humans == 1 else "players"
	if bots <= 0:
		return "%d %s · %d/%d seats" % [humans, human_word, humans, seats]
	var bot_word: String = "bot" if bots == 1 else "bots"
	return "%d %s · %d %s · %d/%d seats" % [humans, human_word, bots, bot_word, humans + bots, seats]


## DECISION (ui/Lobby.gd, Bontago-mv0.6): Events.net_roster_changed's payload
## is the roster Net just built (autoload/Net.gd's _broadcast_roster() /
## _rpc_roster_update()), so this applies it straight to the rows rather than
## re-deriving one from net_provider.peer_ids()/peer_info() the way
## _build_roster() does for the host's own outbound publish — one less round
## trip, and it is the single source of truth for "what does the list show
## right now" (net_lobby_data_changed's own embedded roster only matters for
## the late-joiner snapshot _apply_data() already handles).
func _on_roster_changed(roster: Array[Dictionary]) -> void:
	_mirror_player_count_to_peers(roster.size())
	# Bontago-1pi.9b: a human joining/leaving changes how many seats are left
	# for bots even when the host never touches %PlayerCountSpin itself (e.g.
	# player_count already sits above the connected-peer count to leave bot
	# headroom) -- _mirror_player_count_to_peers() above only republishes the
	# spin when the seat count itself needs to move, so this clamp call is
	# not redundant with it.
	_clamp_ai_count_to_seats()
	_apply_roster(roster)


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
## override the moment Start is pressed.
##
## DECISION (ui/Lobby.gd, Bontago-1pi.9b): this used to force
## `_player_count_spin.value = peer_count` outright ("Bots don't exist until
## M5, so ... the spin simply tracks the peer count exactly" -- true when it
## was written, false now that M5 shipped ai_count). Left as-is, every human
## join/leave would silently erase any seat headroom a host had set aside
## for bots (seats == humans exactly => 0 room left), directly breaking the
## owner's "I can add bots up to the player limit" expectation. Mirrors
## MatchConfig.clamp_to_connected_peers()'s own "humans outrank bots, but an
## existing bot count is preserved if there's room" rule instead: the seat
## count only ever grows to admit every connected human, and shrinks no
## further than the greater of the peer count or (peers + existing bots).
func _mirror_player_count_to_peers(peer_count: int) -> void:
	if net_provider == null or not bool(net_provider.is_host()):
		return
	var wanted_total: int = clampi(peer_count + int(_ai_count_spin.value), peer_count, MatchConfig.PLAYER_COUNT_MAX)
	var target: int = clampi(wanted_total, MatchConfig.PLAYER_COUNT_MIN, MatchConfig.PLAYER_COUNT_MAX)
	if int(_player_count_spin.value) != target:
		_player_count_spin.value = target


## Bontago-1pi.9b: owner playtest ("I can add bots up to the player limit")
## found the bot count could silently exceed the number of empty seats --
## nothing stopped ai_count + connected humans from exceeding player_count.
## Recomputes %AiCountSpin's own max_value from the current seat count minus
## the connected-peer count; Range.set_max() re-clamps a current value above
## the new max on its own (Godot core, `Range::set_max` calls `set_value()`),
## so this is the single place that both bounds future edits and corrects an
## already-too-high value the moment seats shrink or a human joins. Called
## from _mirror_player_count_to_peers()'s own callers (a roster event) and
## from every %PlayerCountSpin edit (_connect_control_signals()) and
## _apply_data() (so a value that arrives over the wire is bounded here too,
## on host and client alike -- harmless on a client since its controls are
## already disabled).
func _clamp_ai_count_to_seats() -> void:
	if net_provider == null:
		return
	var seats: int = int(_player_count_spin.value)
	var humans: int = net_provider.peer_ids().size()
	_ai_count_spin.max_value = maxi(0, seats - humans)


func _on_ready_toggled(pressed: bool) -> void:
	if net_provider != null:
		net_provider.set_local_ready(pressed)


func _on_start_pressed() -> void:
	if net_provider == null or not bool(net_provider.is_host()) or not bool(net_provider.all_peers_ready()):
		return
	Sfx.play(AudioConfig.EVENT_START_GAME)
	var config: MatchConfig = (
		_last_config if _last_config != null else _config_from_controls()
	).duplicate(true) as MatchConfig
	# DECISION (ui/Lobby.gd, Bontago-1pi.18.5): the numeric experiment parameters
	# in _last_config.qol were copied at the last publish; re-fold the toggles onto
	# the shared resource now so an F4 edit made while the lobby was open takes
	# effect. The start config always carries a non-null qol, so
	# MatchLifecycle keeps the lobby's choice instead of snapshotting F4.
	config.qol = _qol_from_controls()
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
	_update_status_badge()


## Header badge (Bontago-xtq.32 redo, mockup 11's top-right "Hosting * LAN"
## pill): reads the same net_provider calls _update_host_only_state() above
## already gates on, so it never assumes a transport (CLAUDE.md
## "Multiplayer"). Runs every _update_host_only_state() call (once per
## _process() frame, see that method's own DECISION) -- cheap, a Dictionary-
## free string format on two bools.
func _update_status_badge() -> void:
	if net_provider == null:
		return
	var is_host: bool = bool(net_provider.is_host())
	var is_steam: bool = bool(net_provider.is_steam_session())
	_status_badge_label.text = "%s %s %s" % [
		"Hosting" if is_host else "Joined", char(0xB7), "Steam" if is_steam else "LAN"
	]
