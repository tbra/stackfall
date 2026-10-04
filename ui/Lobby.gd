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

## Scene groups of the settings grid (see _apply_row_layout()).
const ROW_GROUP: StringName = &"lobby_row"
const ROWS_GROUP: StringName = &"lobby_rows"
const CHECKLIST_GROUP: StringName = &"lobby_checklist"
const LABEL_CELL_GROUP: StringName = &"lobby_label_cell"
const VALUE_CELL_GROUP: StringName = &"lobby_value_cell"

## Bontago-1pi.53 (E1): sizes and spacings new to the lobby rework (section
## spacing, seat colour box, row height, advanced indent); also handed to the
## players panel. Never touches the MenuVisualTuning look above.
@export var layout_tuning: LobbyLayoutTuning = preload("res://config/lobby_layout_tuning.tres")

## Bontago-1pi.53 (PL1b): the lobby-data key of the seat table (LobbySeats: humans + bots
## with colour / team / difficulty), next to "roster". Published by _publish_lobby_data,
## read by _apply_data, and carried across the results screen's republish
## (ResultsScreen.LOBBY_SEATS_KEY points here).
const SEATS_KEY: String = "seats"

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
## ui/HUD.gd's match_provider. Bontago-1pi.53 (E1): the players panel reads the
## same seam (peer ids/info for the roster, local peer id for the "you" subtitle),
## so a swap here is forwarded to it -- tests assign this after _ready().
var net_provider: Variant = null:
	set(value):
		net_provider = value
		if _players_panel != null:
			_players_panel.net_provider = value

## Bontago-mp0.3.5 (review r2, item 1): %MapVariantOption/%MapSizeOption stay
## the hidden source of truth (same pattern as the hidden %TeamModeOption and
## seat spins) -- %MapComboOption is the single visible "Round · Medium"
## style dropdown listing every variant*size combo, decoded/encoded by
## _map_combo_index(), with %MapThumbnail (a small disc icon) beside it.
@onready var _map_variant_option: OptionButton = %MapVariantOption
@onready var _map_size_option: OptionButton = %MapSizeOption
@onready var _map_combo_option: OptionButton = %MapComboOption
@onready var _map_thumbnail: PanelContainer = %MapThumbnail
## Bontago-1pi.53 (S1b): the Players/AI steppers, the default-difficulty dropdown and the
## segmented Teams control left the settings card -- seats, bots and teams are managed in
## the players panel (docs/LOBBY_REWORK_PLAN.md section 2). These four stay as HIDDEN
## sources of truth under %HiddenSources (the pattern the map combo already uses): every
## read and write of `.value` / `.selected`, the host-only gating, the bot clamp and
## the round trip are unchanged, and the panel drives them (_on_teams_toggled,
## _set_bot_count). They are never focus stops.
## DECISION (ui/Lobby.gd, PL1b): with the panel's Teams toggle and "+ Add bot" button now
## the only way to change them (PL1b), they are no longer a temporary fallback but the
## state holders docs/LOBBY_REWORK_PLAN.md D6 chose: _config_from_controls() /
## _apply_data() / _clamp_ai_count_to_seats() and every existing lobby test read and
## write them, so removing them would rewrite the whole config round trip (and
## tests/unit/test_lobby.gd's 31 references) for no player-visible change.
@onready var _player_count_spin: SpinBox = %PlayerCountSpin
@onready var _ai_count_spin: SpinBox = %AiCountSpin
@onready var _ai_difficulty_option: OptionButton = %AiDifficultyOption
@onready var _team_mode_option: OptionButton = %TeamModeOption
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
## Bontago-1pi.53 (S1b): the per-gift checklist is the GIFTS section's Advanced block.
@onready var _specials_checklist: GridContainer = %SpecialsChecklist
@onready var _specials_label: Label = %SpecialsLabel
## Bontago-1pi.18.5: the Experiments checkboxes, in QolExperiments.with_toggles()
## argument order (timer pause, backlog, goal radius, gift slot). Bontago-1pi.53 (S1b):
## they are the EXPERIMENTS section's Advanced block (plan D2). Host-editable,
## read-only for a client (_settings_controls).
@onready var _experiments_label: Label = %ExperimentsLabel
@onready var _qol_timer_pause_check: CheckBox = %QolTimerPauseCheck
@onready var _qol_backlog_check: CheckBox = %QolBacklogCheck
@onready var _qol_goal_radius_check: CheckBox = %QolGoalRadiusCheck
@onready var _qol_gift_slot_check: CheckBox = %QolGiftSlotCheck
@onready var _qol_checks: Array[CheckBox] = [
	_qol_timer_pause_check, _qol_backlog_check, _qol_goal_radius_check, _qol_gift_slot_check,
]

## Bontago-1pi.53 (S1a/S1b): the settings column is a stack of collapsible LobbySections
## (ui/lobby/LobbySection.gd): GAME (mode, map, time of day, weather; Advanced:
## gravity, tilt, holes, turn-based, mid-match join), ROUND (round length / match
## timer, sudden death, block timer, goal flags, Reach the Sky team height), GIFTS
## (on/off, frequency; Advanced: the per-gift checklist) and EXPERIMENTS (the opt-in
## experiment checks, behind its header). %Settings is their column (its separation
## comes from LobbyLayoutTuning.section_spacing_px).
@onready var _settings_column: VBoxContainer = %Settings
@onready var _game_section: LobbySection = %GameSection
@onready var _round_section: LobbySection = %RoundSection
@onready var _gifts_section: LobbySection = %GiftsSection
@onready var _experiments_section: LobbySection = %ExperimentsSection
## Goal flags apply only to the modes MatchConfig.mode_uses_goal_flags() names.
@onready var _goal_flag_col: Control = %GoalFlagCol

## Bontago-1pi.53 (E1): the right-hand roster (title row, header text, seat rows)
## lives in ui/lobby/LobbyPlayersPanel.gd; this script keeps only the hooks
## (_publish_lobby_data/_apply_data/_on_roster_changed/_on_start_pressed/
## _update_host_only_state) that feed it. %PlayerList and %PlayerCountLabel are
## its own unique names now, so they resolve through %PlayersPanel.
@onready var _players_panel: LobbyPlayersPanel = %PlayersPanel
@onready var _ready_check: CheckButton = %ReadyCheck
@onready var _start_button: Button = %StartButton
@onready var _invite_friends_button: Button = %InviteFriendsButton

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
@onready var _hint_row: InputPromptFlow = %GamepadHintBar
## Bontago-mp0.3.5 (review r1, item 13): mockup 11's bottom-left "Waiting for
## players * X of Y ready" pill, updated every time the players panel rebuilds its rows (_on_roster_rendered()).
@onready var _waiting_status_pill: PanelContainer = %WaitingStatusPill
@onready var _waiting_status_label: Label = %WaitingStatusLabel

## Every control the round trip governs, so enabling/disabling them for a
## non-host is one loop instead of fourteen repeated lines.
var _settings_controls: Array[Control] = []

## Built once by _build_specials_checklist(), in SpecialDef.load_all_specials()
## order -- parallel arrays (the same convention the panel's rows pair with
## roster entries by index) so _config_from_controls()/_apply_data() can walk
## both together without a per-frame dictionary lookup.
var _special_checkboxes: Array[CheckBox] = []
var _special_ids: Array[StringName] = []

## Bontago-mp0.3.5 (review r2, item 2): the round "-"/"+" buttons
## _add_stepper_buttons() builds around the goal-flag SpinBox (minus, plus) -- read by
## _wire_focus_chain() so they're gamepad-focusable, same as every other settings
## control. Bontago-1pi.53 (S1a): they sit inside the ROUND section (focus order =
## visual order).
var _goal_stepper_buttons: Array[Button] = []

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
## Bontago-59o.18 (U1): the time-of-day dropdown. Index == MatchConfig.SkyThemeMode
## (DAY, NIGHT, RANDOM, CYCLE, DAWN), so the stored ints and the wire format are
## unchanged; DAY is relabelled "Sunset" because it is now the day/night cycle
## locked at a sunset time, not a separate painted sky.
const SKY_THEME_LABELS: PackedStringArray = ["Sunset", "Night", "Random", "Cycle", "Dawn"]
const SKY_THEME_TIP: String = "Time of day for the match sky. Cycle runs through dawn, day, sunset and night; the other options hold the cycle at one fixed time."
const SKY_THEME_ITEM_TIPS: PackedStringArray = [
	"Locked time: the sky stays at sunset for the whole match.",
	"Locked time: the sky stays at night for the whole match.",
	"Locked time: the host picks sunset, night or dawn at random when the match starts.",
	"Running cycle: the sky moves through dawn, day, sunset and night as the match goes on.",
	"Locked time: the sky stays at dawn for the whole match.",
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
## Bontago-1pi.53 (S1a): the one-line section summaries shown on each LobbySection header.
const SUMMARY_SEPARATOR: String = " · "
const SUMMARY_BLOCK_TIMER_FORMAT: String = "Block %.1f s"
const SUMMARY_GOAL_FLAGS_FORMAT: String = "%d goal flags"
const SUMMARY_GOAL_FLAG_FORMAT: String = "%d goal flag"
const SUMMARY_GIFTS_ON_FORMAT: String = "On%sfrequency %d"
## Appended to the GIFTS summary while some (not all) gifts are switched off in its Advanced
## block -- the at-a-glance count the old "Specials: n/m" chip showed.
const SUMMARY_GIFT_COUNT_FORMAT: String = "%d/%d gifts"
const SUMMARY_GIFTS_OFF: String = "Off"
const SUMMARY_EXPERIMENTS_FORMAT: String = "%d on"
var _timer_mode: int = MatchConfig.GameMode.CLASSIC
## Last minutes each timer slider settled on, so a step through the 1-minute gap
## knows which way it was moving (_on_timer_slider_changed()).
var _timer_previous_minutes: Dictionary[HSlider, int] = {}
var _last_config: MatchConfig = null
## Footer buttons' visibility the focus loop was last wired for (_update_host_only_state()).
var _start_was_shown: bool = false
var _invite_was_shown: bool = false


func _ready() -> void:
	net_provider = Net
	_configure_players_panel()
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
	_connect_control_signals()
	for section: LobbySection in _sections():
		section.advanced_changed.connect(_on_section_toggled)
	_start_button.pressed.connect(_on_start_pressed)
	_ready_check.toggled.connect(_on_ready_toggled)
	_invite_friends_button.pressed.connect(_on_invite_friends_pressed)
	_back_button.pressed.connect(_on_back_pressed)
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
	_reset_roster_ready_on_entry()
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


## Bontago-1pi.53 (E1): hands the players panel everything it renders from (the
## Lobby's own tunables, the per-slot palette, the net seam) and connects its
## signals -- the narrow Lobby <-> panel contract documented in
## ui/lobby/LobbyPlayersPanel.gd. Runs before the first _apply_data() so even the
## first rows are built from the Lobby's own resources.
func _configure_players_panel() -> void:
	_players_panel.net_provider = net_provider
	_players_panel.tuning = tuning
	_players_panel.layout_tuning = layout_tuning
	_players_panel.palette = default_config.player_colors
	_players_panel.seats_changed.connect(_on_seats_changed)
	_players_panel.teams_toggled.connect(_on_teams_toggled)
	_players_panel.add_bot_requested.connect(_on_add_bot_requested)
	_players_panel.remove_bot_requested.connect(_on_remove_bot_requested)
	_players_panel.roster_rendered.connect(_on_roster_rendered)
	_players_panel.focus_entries_changed.connect(_on_players_focus_entries_changed)


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
	# Bontago-59o.18 (U1): the DAY entry is the cycle locked at sunset, so it
	# reads "Sunset"; Cycle is the default through MatchConfig.sky_theme_mode.
	_fill_option(_sky_theme_option, Array(SKY_THEME_LABELS))
	_sky_theme_option.tooltip_text = SKY_THEME_TIP
	for sky_index: int in range(SKY_THEME_ITEM_TIPS.size()):
		_sky_theme_option.set_item_tooltip(sky_index, SKY_THEME_ITEM_TIPS[sky_index])
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
## the players panel's row rebuild also depends on.
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
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
## (rebuilt by the players panel on every roster change) enter the chain through
## the panel's focus_entries().
##
## Bontago-1pi.53 (S1a/S1b): ONE closed loop in visual order. Each LobbySection
## contributes its main controls, its Advanced chip and (when open) its
## Advanced controls -- GAME, ROUND, GIFTS (Advanced: the per-gift checklist), EXPERIMENTS
## (chip opens its checks) -- then the players panel's entries and the footer. The
## Advanced rules popup and its separate loop are gone. _visible_chain() drops whatever a
## collapsed block or a mode hides, so there is never an invisible focus stop; every
## section toggle and mode change rewires.
func _wire_focus_chain() -> void:
	var chain: Array[Control] = []
	var game_main: Array[Control] = [_game_mode_option, _map_combo_option, _sky_theme_option, _weather_option]
	var game_advanced: Array[Control] = [
		_gravity_slider, _tilt_mode_option, _hole_mode_option, _turn_based_check, _mid_join_check,
	]
	chain.append_array(_section_chain(_game_section, game_main, game_advanced))
	var round_main: Array[Control] = [_round_timer_slider, _match_timer_slider, _sudden_death_check, _block_timer_slider]
	round_main.append_array(_goal_stepper_buttons)
	round_main.append(_sky_team_sum_check)
	chain.append_array(_section_chain(_round_section, round_main, []))
	var gifts_main: Array[Control] = [_gifts_check, _special_freq_slider]
	var gifts_advanced: Array[Control] = []
	gifts_advanced.append_array(_special_checkboxes)
	chain.append_array(_section_chain(_gifts_section, gifts_main, gifts_advanced))
	var experiments_advanced: Array[Control] = []
	experiments_advanced.append_array(_qol_checks)
	chain.append_array(_section_chain(_experiments_section, [], experiments_advanced))
	# Bontago-1pi.53 (E1): the players panel's own focusable controls sit between the
	# settings and the footer, in visual order; the panel asks for a rewire through
	# focus_entries_changed.
	chain.append_array(_players_panel.focus_entries())
	chain.append_array([_back_button, _invite_friends_button, _ready_check, _start_button])
	_main_chain = chain
	_rewire_focus()


## One section's focus stops in visual order: main controls, Advanced chip, Advanced
## controls (the header is static and not a stop; Bontago-1pi.61).
func _section_chain(section: LobbySection, main_controls: Array[Control], advanced_controls: Array[Control]) -> Array[Control]:
	var out: Array[Control] = []
	out.append_array(main_controls)
	if section.advanced_button != null:
		out.append(section.advanced_button)
	out.append_array(advanced_controls)
	return out


func _sections() -> Array[LobbySection]:
	return [_game_section, _round_section, _gifts_section, _experiments_section]


## Rewires the main loop from the chain built by _wire_focus_chain(): called on every
## state change that can hide or show a stop (a section or Advanced toggle, a game
## mode change, the panel's entries) -- never per frame (_process only gates
## editability). A no-op until the first build.
func _rewire_focus() -> void:
	if _main_chain.is_empty():
		return
	_wire_loop(_visible_chain(_main_chain))


## Bontago-1pi.61: one shared column grid for every settings row. Each row (group
## `lobby_row`) is label cell | control (expands) | optional value cell, so the label and
## value columns share one x/width in every section; widths and gaps come from
## [member layout_tuning] (scaled by the one project UI scale), not per-node pixels.
func _apply_row_layout() -> void:
	for node: Node in _settings_column.find_children("*", "", true, false):
		if node.is_in_group(ROW_GROUP):
			node.add_theme_constant_override("separation", layout_tuning.row_separation_px)
		elif node.is_in_group(ROWS_GROUP):
			node.add_theme_constant_override("separation", layout_tuning.row_spacing_px)
		elif node.is_in_group(CHECKLIST_GROUP):
			node.add_theme_constant_override("h_separation", layout_tuning.row_separation_px)
			node.add_theme_constant_override("v_separation", layout_tuning.row_spacing_px)
		elif node.is_in_group(LABEL_CELL_GROUP):
			(node as Control).custom_minimum_size.x = layout_tuning.label_column_width_px
		elif node.is_in_group(VALUE_CELL_GROUP):
			(node as Control).custom_minimum_size.x = layout_tuning.value_column_width_px


func _on_section_toggled(state: bool) -> void:
	Events.lobby_ui_cue.emit(&"section_expanded" if state else &"section_collapsed")
	_rewire_focus()


## Every control the focus loop may visit, in visual order (built by _wire_focus_chain());
## _visible_chain() filters it to what is shown right now.
var _main_chain: Array[Control] = []


## Bontago-1pi.53 (S1a): a control is a focus stop only while it and every ancestor up to
## this screen are visible -- a collapsed section or Advanced block, a hidden
## conditional column (the Reach the Sky toggle outside its mode, the timer column
## the mode does not use, goal flags in a mode without them) and the hidden
## SpinBox/OptionButton sources of truth all drop out, so gamepad focus can never
## land on an invisible control. (Visibility is judged relative to this screen, not
## is_visible_in_tree(), so the loop is the same whatever shows the lobby.)
func _visible_chain(chain: Array[Control]) -> Array[Control]:
	var out: Array[Control] = []
	for control: Control in chain:
		if _is_shown(control):
			out.append(control)
	return out


func _is_shown(control: Control) -> bool:
	var node: Node = control
	while node != null and node != self:
		var item: CanvasItem = node as CanvasItem
		if item != null and not item.visible:
			return false
		node = node.get_parent()
	return true


## Assigns focus_neighbor_top/bottom so [param chain] forms one closed loop,
## wrapping from its last entry back to its first.
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


## Bontago-mp0.3.5 (review r2, item 2): inserts a round "-" button before
## [param spin] and a round "+" button after it, in [param spin]'s own
## parent -- both just nudge [param spin].value by one step() and let SpinBox's own
## existing value_changed -> _on_value_changed() wiring do the rest, so this never
## duplicates the round-trip/clamp logic. Appends both to [param target] (read by
## _wire_focus_chain()) and to _settings_controls, so _update_host_only_state() gates
## them exactly like every other host-only control.
##
## Bontago-mp0.3.5 (review r3, problem 3 / polish pass, problem 2): mockup 11 draws a
## stepper as ONE sunken pill -- "(-) value (+)". [param spin] keeps its min/max/step/
## value/value_changed exactly as before (every get_node("%...").value read/write in this
## file and in the tests is untouched) but is hidden (`visible = false`, so a Container
## skips it entirely -- no reparent); a plain borderless Label shows its value, kept in
## sync by [param spin]'s own value_changed (which Range emits for a programmatic
## `.value = x` too, so a remote _apply_data() update reaches it exactly like a button
## press does). Bontago-1pi.53 (S1b): only the goal-flag count still uses it -- the
## Players/AI steppers left the card.
func _add_stepper_buttons(spin: SpinBox, target: Array[Button]) -> void:
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
## slider doesn't spam hover sounds. DECISION (Bontago-mp0.117): the ready toggle
## is not here -- it has its own ready_on/ready_off cue (no double click).
func _connect_click_and_hover_sounds() -> void:
	var buttons: Array[BaseButton] = [_start_button, _invite_friends_button, _back_button]
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
	_settings_column.add_theme_constant_override("separation", layout_tuning.section_spacing_px)
	_apply_row_layout()
	for section: LobbySection in _sections():
		section.apply_style(tuning, layout_tuning)

	# Bontago-mp0.3.5 (review r2, item 2): a round "-"/"+" stepper pill around the
	# goal-flag SpinBox (mockup 11) -- the SpinBox itself stays exactly as it was
	# (same min/max/step, same value_changed wiring), this just gives it a second,
	# gamepad-focusable way to nudge the value by one step, and (review r3, problem 3)
	# hides the native up/down spinner entirely.
	_add_stepper_buttons(_goal_flag_spin, _goal_stepper_buttons)
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
	# Bontago-1pi.18.5: the Experiments checkboxes are the same chip family as the
	# specials grid above (no new colours, no new tunables).
	for qol_check: CheckBox in _qol_checks:
		MenuStyleFactory.apply_toggle_chip(
			qol_check, tuning.pill_cream_color, tuning.pill_cream_hover_color,
			tuning.pill_mint_color, tuning.pill_mint_hover_color, tuning.ink_color, tuning
		)
	var chips: Array[Button] = [
		_gifts_check, _sudden_death_check, _turn_based_check, _mid_join_check, _sky_team_sum_check, _ready_check,
	]
	for chip: Button in chips:
		MenuStyleFactory.apply_toggle_chip(
			chip, tuning.pill_cream_color, tuning.pill_cream_hover_color,
			tuning.pill_mint_color, tuning.pill_mint_hover_color, tuning.ink_color, tuning
		)

	var captions: Array[Label] = [_specials_label, _experiments_label]
	for caption: Label in captions:
		caption.add_theme_color_override("font_color", tuning.label_muted_color)

	_status_badge.add_theme_stylebox_override("panel", MenuStyleFactory.make_badge(tuning.pill_cream_color, tuning))
	_gamepad_hint_pill.add_theme_stylebox_override("panel", MenuStyleFactory.make_badge(tuning.pill_cream_color, tuning))
	_hint_row.set_text_color(tuning.ink_color)
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
	_players_panel.apply_visual_style()
	_update_status_badge()


## Gamepad/keyboard shortcuts and back-out (Bontago-1pi.53, S1b; the Advanced rules popup is
## gone):
## - lobby_quick_advanced (Y) opens/closes the Advanced block of the section holding focus
##   (the first section with one when focus is elsewhere or in a section without one);
## - lobby_quick_start (X) starts the match when the Start button is usable;
## - ui_cancel (Esc / gamepad B) backs out of the lobby, same as %BackButton. (An open
##   OptionButton popup consumes its own ui_cancel before this runs.)
## Bontago-1pi.15.1 fix: B used to do nothing here unless the popup was open, the reported
## "B never goes back in any menu" gap.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"lobby_quick_advanced"):
		toggle_focused_advanced()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"lobby_quick_start"):
		if _start_button.visible and not _start_button.disabled:
			_on_start_pressed()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return
	_on_back_pressed()
	get_viewport().set_input_as_handled()


## Y on the pad: toggles the Advanced block of the section that holds focus, falling back to
## the first section that has one (GAME). Collapsing a block that holds focus hands focus
## to its chip, so the loop never loses its place (LobbySection.set_advanced_open()).
func toggle_focused_advanced() -> void:
	var target: LobbySection = null
	for section: LobbySection in _sections():
		if section.has_advanced() and section.has_focus_inside():
			target = section
			break
	if target == null:
		for section: LobbySection in _sections():
			if section.has_advanced():
				target = section
				break
	if target != null:
		target.toggle_advanced()


## Bontago-1pi.53 (S1a/S1b): the one-line summary on each section header, read straight off
## the same controls _config_from_controls() reads (and the timer value labels). Called
## from _apply_data(), i.e. after every lobby-data apply, so a host edit and a remote
## update both refresh it. Replaces the old Advanced rules bar's live chips.
func _update_section_summaries() -> void:
	_update_timer_values()
	_game_section.set_summary(SUMMARY_SEPARATOR.join([
		_selected_text(_game_mode_option), _selected_text(_map_combo_option),
		_selected_text(_sky_theme_option), _selected_text(_weather_option),
	]))
	var timer_slider: HSlider = _timer_slider_for(_timer_mode)
	var round_parts: Array[String] = [
		_timer_value_text(int(timer_slider.value), _timer_mode == MatchConfig.GameMode.DOMINATION),
		SUMMARY_BLOCK_TIMER_FORMAT % _block_timer_slider.value,
	]
	if _goal_flag_col.visible:
		var flags: int = int(_goal_flag_spin.value)
		round_parts.append((SUMMARY_GOAL_FLAG_FORMAT if flags == 1 else SUMMARY_GOAL_FLAGS_FORMAT) % flags)
	_round_section.set_summary(SUMMARY_SEPARATOR.join(round_parts))
	if _gifts_check.button_pressed:
		var gifts_summary: String = SUMMARY_GIFTS_ON_FORMAT % [SUMMARY_SEPARATOR, int(_special_freq_slider.value)]
		var enabled_gifts: int = 0
		for box: CheckBox in _special_checkboxes:
			if box.button_pressed:
				enabled_gifts += 1
		if enabled_gifts != _special_checkboxes.size():
			gifts_summary += SUMMARY_SEPARATOR + SUMMARY_GIFT_COUNT_FORMAT % [enabled_gifts, _special_checkboxes.size()]
		_gifts_section.set_summary(gifts_summary)
	else:
		_gifts_section.set_summary(SUMMARY_GIFTS_OFF)
	var experiments_on: int = 0
	for qol_check: CheckBox in _qol_checks:
		if qol_check.button_pressed:
			experiments_on += 1
	_experiments_section.set_summary(SUMMARY_EXPERIMENTS_FORMAT % experiments_on)


func _selected_text(option: OptionButton) -> String:
	return option.get_item_text(option.selected) if option.selected >= 0 else ""


## Bontago-mp0.3.5: tools/capture_mockup08.gd's own `--lobby-advanced` frame (public wrapper
## so the capture tool, which isn't part of this package's own private-method surface,
## has a seam). DECISION (ui/Lobby.gd, Bontago-1pi.53 S1b): the popup is gone, so the
## seam keeps its name and now opens every section's Advanced block -- the lobby's
## equivalent of "show the advanced rules" -- instead of breaking that tool.
func debug_open_advanced_rules_popup() -> void:
	for section: LobbySection in _sections():
		section.set_advanced_open(true)


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
	_goal_flag_col.visible = MatchConfig.mode_uses_goal_flags(mode)
	var was_applying: bool = _applying_remote_data
	_applying_remote_data = true
	_round_timer_slider.min_value = MatchConfig.timer_min_minutes(mode) if not classic else MatchConfig.ROUND_TIMER_MIN_MINUTES
	_applying_remote_data = was_applying
	_match_timer_col.tooltip_text = TIMER_TIP_MATCH
	_round_timer_col.tooltip_text = TIMER_TIP_DOMINATION if mode == MatchConfig.GameMode.DOMINATION else TIMER_TIP_ROUND
	_game_mode_option.tooltip_text = MODE_TIPS[mode] if mode >= 0 and mode < MODE_TIPS.size() else ""
	_update_timer_values()
	_rewire_focus()


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
	_rewire_focus()


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
	data["roster"] = _players_panel.build_roster(config)
	# Bontago-1pi.53 (E1): the seat table (per-seat colour/team/difficulty) is
	# lobby data next to the roster, not a MatchConfig field; an empty table writes no
	# key, so a lobby without one publishes the exact dict it always did.
	var seats: Dictionary = _players_panel.seats_data()
	if not seats.is_empty():
		data[SEATS_KEY] = seats
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
	config.bot_names = _reconciled_bot_names(config.ai_count)
	return config


## Bontago-1pi.62: the host's bot names, by bot ordinal. Assigned the moment a bot
## seat exists (so the lobby and the match show the same name), replicated in the
## published MatchConfig.bot_names, and reused by Match.start_match.
var _bot_names: PackedStringArray = PackedStringArray()


## Keeps the names still valid, drops those of removed seats, draws fresh distinct
## ones (not any human's name, not another bot's) for new seats.
func _reconciled_bot_names(bot_count: int) -> PackedStringArray:
	var human_names: PackedStringArray = PackedStringArray()
	if net_provider != null:
		for peer_id: int in net_provider.peer_ids():
			human_names.append(str(net_provider.peer_info(peer_id).get("name", "")))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	_bot_names = BotNames.assign(_bot_names, bot_count, human_names, rng)
	return _bot_names.duplicate()


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
	_bot_names = config.bot_names.duplicate()

	_applying_remote_data = true
	_map_variant_option.selected = config.map_variant
	_map_size_option.selected = config.map_size
	_map_combo_option.selected = int(config.map_variant) * MAP_SIZE_LABELS.size() + int(config.map_size)
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
	_update_section_summaries()
	# Bontago-1pi.9b: re-bound %AiCountSpin's max after every value assignment
	# above (player_count and ai_count both just moved, possibly from a wire
	# value that predates this clamp) -- see _clamp_ai_count_to_seats()'s own
	# header for why this can't just live in _mirror_player_count_to_peers().
	_clamp_ai_count_to_seats()

	# Bontago-1pi.53 (E1): the panel gets the applied config, the dict's roster (null
	# when it carried none: the rows stay) and its seat table ({} when absent or not a
	# Dictionary off the wire).
	var seats_variant: Variant = data.get(SEATS_KEY, {})
	var seats: Dictionary = seats_variant as Dictionary if seats_variant is Dictionary else {}
	_players_panel.apply(config, data["roster"] if data.has("roster") else null, seats)


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


## Bontago-1pi.53 (E1): the panel's seat table changed (colour, team pick, bot
## difficulty). Republishes like any other host edit, so the dict carries
## _players_panel.seats_data(); a client's edit travels as an intent instead.
func _on_seats_changed() -> void:
	_on_setting_changed()


## The Teams toggle. DECISION (ui/Lobby.gd, E1, plan D8): the toggle writes only
## OFF or TEAMS_4 ("on, up to 4 teams") into the hidden %TeamModeOption, the
## source of truth for config.team_mode; legacy TEAMS_2/3 data stays valid when it
## arrives. Host only: a client's controls are read-only.
## PL1b: the panel's Teams toggle emits teams_toggled (it re-seeded its team picks first);
## %TeamModeOption stays hidden-but-functional (see the %HiddenSources DECISION above), so
## lobby data carrying a team_mode round-trips unchanged.
func _on_teams_toggled(enabled: bool) -> void:
	if not _is_host_session():
		return
	_team_mode_option.selected = MatchConfig.TeamMode.TEAMS_4 if enabled else MatchConfig.TeamMode.OFF
	_on_setting_changed()


func _on_add_bot_requested() -> void:
	var before: int = int(_ai_count_spin.value)
	_set_bot_count(before + 1)
	if int(_ai_count_spin.value) > before:
		Events.lobby_ui_cue.emit(&"bot_added")


func _on_remove_bot_requested(ordinal: int) -> void:
	# Bontago-1pi.62: the removed bot's name is freed; later bots keep theirs.
	if ordinal >= 0 and ordinal < _bot_names.size():
		_bot_names.remove_at(ordinal)
	var before: int = int(_ai_count_spin.value)
	_set_bot_count(maxi(0, before - 1))
	if int(_ai_count_spin.value) < before:
		Events.lobby_ui_cue.emit(&"bot_removed")


## Add/remove bot through the hidden spins, so the existing clamps and the one
## publish path stay the only rules. DECISION (ui/Lobby.gd, E1, plan D6): the seat
## count follows humans + bots (never below the 2-seat minimum), the same rule
## _mirror_player_count_to_peers() applies on every roster event; a request that
## would exceed the seat cap does nothing. The seat spin moves first when growing
## (so the bot spin's max rises before it is set) and last when shrinking.
func _set_bot_count(new_ai_count: int) -> void:
	if not _is_host_session():
		return
	var humans: int = net_provider.peer_ids().size()
	var seats: int = clampi(humans + new_ai_count, MatchConfig.PLAYER_COUNT_MIN, MatchConfig.PLAYER_COUNT_MAX)
	if humans + new_ai_count > seats:
		return
	if seats >= int(_player_count_spin.value):
		_player_count_spin.value = seats
		_ai_count_spin.value = new_ai_count
	else:
		_ai_count_spin.value = new_ai_count
		_player_count_spin.value = seats


## The panel rebuilt its rows: feeds mockup 11's bottom-left "Waiting for players *
## 3 of 4 ready" pill, derived from the exact rows just drawn rather than a second
## net_provider query.
func _on_roster_rendered(ready_count: int, row_count: int) -> void:
	_waiting_status_label.text = "%s Waiting for players %s %d of %d ready" % [
		char(0x25CF), char(0xB7), ready_count, row_count,
	]


## The panel's focusable controls changed: rewire the loop (only once the first
## wiring exists -- _ready() builds it after every dynamic row).
func _on_players_focus_entries_changed() -> void:
	if not _main_chain.is_empty():
		_wire_focus_chain()


func _is_host_session() -> bool:
	return net_provider != null and bool(net_provider.is_host())


# --- Player list / ready / start --------------------------------------------

## DECISION (ui/Lobby.gd, Bontago-mv0.6): Events.net_roster_changed's payload
## is the roster Net just built (autoload/Net.gd's _broadcast_roster() /
## _rpc_roster_update()), so this applies it straight to the rows rather than
## re-deriving one from net_provider.peer_ids()/peer_info() the way
## LobbyPlayersPanel.build_roster() does for the host's own outbound publish — one less round
## trip, and it is the single source of truth for "what does the list show
## right now" (net_lobby_data_changed's own embedded roster only matters for
## the late-joiner snapshot _apply_data() already handles).
## Bontago-1pi.53 (E1): the rows themselves are the players panel's
## (on_roster_changed); the spin mirror and the bot clamp stay here.
func _on_roster_changed(roster: Array[Dictionary]) -> void:
	_mirror_player_count_to_peers(roster.size())
	# Bontago-1pi.9b: a human joining/leaving changes how many seats are left
	# for bots even when the host never touches %PlayerCountSpin itself (e.g.
	# player_count already sits above the connected-peer count to leave bot
	# headroom) -- _mirror_player_count_to_peers() above only republishes the
	# spin when the seat count itself needs to move, so this clamp call is
	# not redundant with it.
	_clamp_ai_count_to_seats()
	_players_panel.on_roster_changed(roster)


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


## Bontago-1pi.73: the Ready toggle starts off on every (re)entry, so the host
## clears the roster's flags to match (DECISION: reset both, not restore).
func _reset_roster_ready_on_entry() -> void:
	if net_provider != null and bool(net_provider.is_host()):
		net_provider.reset_ready_flags()


func _on_ready_toggled(pressed: bool) -> void:
	Events.lobby_ui_cue.emit(&"ready_on" if pressed else &"ready_off")
	if net_provider != null:
		net_provider.set_local_ready(pressed)


func _on_start_pressed() -> void:
	if net_provider == null or not bool(net_provider.is_host()) or not bool(net_provider.all_peers_ready()):
		return
	# Bontago-1pi.53 (E1, P1 review F4): the Start button is already disabled while
	# the panel names a blocker, but the X shortcut and a direct call skip the
	# button -- so the gate is rechecked here.
	if _players_panel.start_blocker() != "":
		return
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
	# Bontago-1pi.53 (E1, P1 review F1): the panel resolves/flattens its seat picks
	# into the start config only AFTER the clamp above -- MatchConfig.sanitize()
	# silently drops team arrays whose length differs from player_count, and the
	# clamp is what settles player_count/ai_count. PL1b: it reconciles the seat table with
	# Net's CURRENT slot map first (slots move on a lobby leave/kick) and returns the reason
	# when the seats cannot become match slots; the config is then untouched and nothing
	# starts.
	if _players_panel.finalize_start_config(config) != "":
		return
	Sfx.play(AudioConfig.EVENT_START_GAME)
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
	_players_panel.set_editable(is_host)
	# Bontago-1pi.53 (E1, P1 review F4): a start blocker (e.g. teams on and every
	# seat on one team) disables Start and is explained in its tooltip; "" when
	# nothing blocks, which is also the tooltip's default.
	var start_blocker: String = _players_panel.start_blocker() if is_host else ""
	_start_button.visible = is_host
	_start_button.disabled = (
		not is_host or not (net_provider != null and bool(net_provider.all_peers_ready())) or start_blocker != ""
	)
	_start_button.tooltip_text = start_blocker
	_invite_friends_button.visible = is_host and net_provider != null and bool(net_provider.is_steam_session())
	# Bontago-1pi.53 (S1a): Start and Invite Friends are focus stops only while shown, so
	# the loop is rewired when their visibility flips (a role or transport change), not
	# every frame.
	if _start_button.visible != _start_was_shown or _invite_friends_button.visible != _invite_was_shown:
		_start_was_shown = _start_button.visible
		_invite_was_shown = _invite_friends_button.visible
		_rewire_focus()
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
