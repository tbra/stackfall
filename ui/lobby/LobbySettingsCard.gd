class_name LobbySettingsCard extends VBoxContainer
## The lobby settings form: every match setting as a control (GAME, ROUND, GIFTS and EXPERIMENTS
## sections), built from ui/components. It maps controls to a MatchConfig and back, hides the rows
## the chosen mode or a master switch governs, and gates every control to the host. It knows
## nothing of seats, the roster, the network or the focus loop: the lobby reads [method config],
## feeds [method apply], and rewires focus on [signal layout_changed].
##
## Seat budget, roster, bot names and the rng seed are not here (the lobby owns them).

## A user edit of any control (never emitted while [method apply] writes inbound data).
signal changed
## A row, section or Advanced visibility change; the lobby rewires focus.
signal layout_changed
## The settings column scrolled; the lobby's layout-dependent focus pass reruns.
signal scrolled

## DECISION: MatchConfig.enabled_specials already means "empty = every special enabled", so
## unchecking every gift chip cannot publish an empty array (that would mean the opposite). This
## sentinel id published as the sole entry means "spawn nothing"; autoload/match/MatchGifts.gd
## carries the identical literal (it cannot import a ui/ script).
const ALL_DISABLED_SENTINEL: StringName = &"__none__"

## The shared F4 experiments resource. The five enable flags come from the Experiments chips; every
## numeric parameter is copied from here, so those stay F4-tunable. Never modified:
## QolExperiments.with_toggles() works on a copy. A static var, not a const: GDScript folds
## `CONST.prop` reads of a const Resource at compile time, which left every F4 edit of it dead.
static var QOL_SHARED: QolExperiments = preload("res://config/match/qol_experiments.tres")

## Each UiRow node carries its label text as this metadata key (read once by _prepare_rows());
## every VBox of rows is in STACK_GROUP and gets the design-system row gap.
const ROW_LABEL_META: StringName = &"row_label"
const STACK_GROUP: StringName = &"lobby_stack"
## The help-line key the round-length row is explained under in Domination (any other mode uses the
## row's own name); the sentences live in config/ui/option_help_table.tres.
const ROUND_HELP_KEY_DOMINATION: String = "RoundTimerDominationCol"
## Index == MatchConfig.SkyThemeMode, so the stored ints and the wire format are stable; DAY is
## labelled "Sunset" because it is the day/night cycle locked at a sunset time.
const SKY_THEME_LABELS: PackedStringArray = ["Sunset", "Night", "Random", "Cycle", "Dawn"]
## The leftmost stop of a timer stepper whose mode may switch its timer off reads "Off".
const TIMER_OFF_TEXT: String = "Off"
const TIMER_VALUE_FORMAT: String = "%d min"
## A stepper shows the bare number; the unit lives in the row label (the summary keeps its units).
const TIMER_STEPPER_FORMAT: String = "%d"
## One stepper step is half a second of block timer; the gift-frequency meter has FREQUENCY_CELLS lit
## steps between its MatchConfig bounds, the gravity meter one per MatchConfig.GRAVITY_STEP.
const BLOCK_TIMER_STEP_S: float = 0.5
const GRAVITY_CELLS: int = roundi(MatchConfig.GRAVITY_MAX / MatchConfig.GRAVITY_STEP)
const FREQUENCY_CELLS: int = 10
const GRAVITY_READOUT_FORMAT: String = "%.2fx"
const FREQUENCY_READOUT_FORMAT: String = "%d"
const DISC_SIZE_READOUT_FORMAT: String = "%d%%"
const PERCENT_SCALE: float = 100.0
const SUMMARY_SEPARATOR: String = " · "
const SUMMARY_BLOCK_TIMER_FORMAT: String = "Block %.1f s"
const BLOCK_TIMER_VALUE_FORMAT: String = "%.1f"
const SUMMARY_GOAL_FLAGS_FORMAT: String = "%d goal flags"
const SUMMARY_GOAL_FLAG_FORMAT: String = "%d goal flag"
const SUMMARY_GIFTS_ON_FORMAT: String = "On%sfrequency %d"
## Appended to the GIFTS summary while some (not all) gifts are switched off: the enabled count.
const SUMMARY_GIFT_COUNT_FORMAT: String = "%d/%d gifts"
const SUMMARY_GIFTS_OFF: String = "Off"
const SUMMARY_EXPERIMENTS_FORMAT: String = "%d on"

@onready var _settings_scroll: ScrollContainer = %SettingsScroll
@onready var _help_line: UiHelpLine = %HelpLine
@onready var _settings_column: VBoxContainer = %Settings
@onready var _game_section: UiSection = %GameSection
@onready var _round_section: UiSection = %RoundSection
@onready var _gifts_section: UiSection = %GiftsSection
@onready var _experiments_section: UiSection = %ExperimentsSection
## The disc size is the one visible map control: a UiSegmentMeter whose value is the step + 1 (cells
## lit), never 0 (see _disc_size_step()).
@onready var _disc_size_meter: UiSegmentMeter = %DiscSizeMeter
@onready var _game_mode_option: UiCycler = %GameModeOption
@onready var _sky_theme_option: UiCycler = %SkyThemeOption
@onready var _weather_option: UiCycler = %WeatherOption
@onready var _tilt_mode_option: UiCycler = %TiltModeOption
@onready var _hole_mode_option: UiCycler = %HoleModeOption
@onready var _turn_based_check: UiToggle = %TurnBasedCheck
@onready var _mid_join_check: UiToggle = %MidJoinCheck
## Gravity and gift frequency are UiSegmentMeters (cells). The exact stored values live here, so a
## value that arrives from the wire (e.g. 1.0) is kept as is and read back unchanged; only a
## player's own nudge snaps to the next cell.
@onready var _gravity_meter: UiSegmentMeter = %GravityMeter
@onready var _special_freq_meter: UiSegmentMeter = %SpecialFreqMeter
var _gravity_value: float = MatchConfig.GRAVITY_DEFAULT
var _special_frequency_value: int = 0
## ONE timer control is shown: Classic shows the match-timer row (+ sudden death), every other mode
## the round-length row; each keeps mapping its own MatchConfig field.
@onready var _match_timer_stepper: UiStepper = %MatchTimerStepper
@onready var _round_timer_stepper: UiStepper = %RoundTimerStepper
@onready var _match_timer_col: Control = %MatchTimerCol
@onready var _round_timer_col: Control = %RoundTimerCol
@onready var _sudden_death_col: Control = %SuddenDeathCol
@onready var _sudden_death_check: UiToggle = %SuddenDeathCheck
@onready var _sudden_death_seconds_stepper: UiStepper = %SuddenDeathSecondsStepper
@onready var _block_timer_stepper: UiStepper = %BlockTimerStepper
@onready var _goal_flag_stepper: UiStepper = %GoalFlagStepper
## Goal flags apply only to the modes MatchConfig.mode_uses_goal_flags() names.
@onready var _goal_flag_col: Control = %GoalFlagCol
## Reach the Sky only: shown while that mode is selected.
@onready var _sky_team_col: Control = %SkyTeamCol
@onready var _sky_team_sum_check: UiToggle = %SkyTeamSumCheck
@onready var _gifts_check: UiToggle = %GiftsCheck
## The Frequency row, greyed with the gifts switch off (with the Advanced bar).
@onready var _special_freq_group: Control = %SpecialFreqGroup
## The per-gift checklist is the GIFTS section's Advanced block, a grid of UiChipToggles.
@onready var _specials_checklist: GridContainer = %SpecialsChecklist
@onready var _experiments_check: UiToggle = %ExperimentsCheck
@onready var _experiments_checklist: GridContainer = %ExperimentsChecklist
## The Experiments trials row, shown only while the Experiments switch is on.
@onready var _experiments_group: Control = %ExperimentsGroup
## The Experiments chips, in QolExperiments.with_toggles() argument order.
@onready var _qol_timer_pause_check: UiChipToggle = %QolTimerPauseCheck
@onready var _qol_backlog_check: UiChipToggle = %QolBacklogCheck
@onready var _qol_goal_radius_check: UiChipToggle = %QolGoalRadiusCheck
@onready var _qol_gift_slot_check: UiChipToggle = %QolGiftSlotCheck
@onready var _qol_gift_loads_next_check: UiChipToggle = %QolGiftLoadsNextCheck
@onready var _qol_checks: Array[UiChipToggle] = [
	_qol_timer_pause_check, _qol_backlog_check, _qol_goal_radius_check, _qol_gift_slot_check,
	_qol_gift_loads_next_check,
]

## Every control the host gating governs.
var _settings_controls: Array[Control] = []
## Built once by _build_specials_checklist(), in SpecialDef.load_selectable_specials() order:
## parallel arrays, so config() and apply() walk both together.
var _special_checkboxes: Array[UiChipToggle] = []
var _special_ids: Array[StringName] = []
var _host: bool = false
## True while apply() writes values back into the controls, so the value-changed signals that causes
## never re-emit `changed` (an infinite echo).
var _applying_remote_data: bool = false
var _timer_mode: int = MatchConfig.GameMode.CLASSIC
## Last minutes each timer stepper settled on, so a step through the 1-minute gap knows which way
## it was moving (_on_timer_stepper_changed()).
var _timer_previous_minutes: Dictionary[UiStepper, int] = {}


func _ready() -> void:
	_prepare_rows()
	_populate_options()
	_settings_controls = [
		_disc_size_meter, _block_timer_stepper, _gravity_meter, _goal_flag_stepper, _gifts_check,
		_experiments_check, _special_freq_meter, _tilt_mode_option, _hole_mode_option,
		_match_timer_stepper, _sudden_death_check, _sudden_death_seconds_stepper, _turn_based_check,
		_mid_join_check, _weather_option, _sky_theme_option, _game_mode_option, _round_timer_stepper,
		_sky_team_sum_check,
	]
	_settings_controls.append_array(_special_checkboxes)
	_settings_controls.append_array(_qol_checks)
	_connect_control_signals()
	for section: UiSection in sections():
		section.advanced_changed.connect(_on_section_toggled)
	var art: UiArtTable = UiArtTable.shared()
	_game_section.set_header_icon(art.lobby_icon(UiArtTable.KEY_SECTION_GAME))
	_round_section.set_header_icon(art.lobby_icon(UiArtTable.KEY_SECTION_ROUND))
	_gifts_section.set_header_icon(art.lobby_icon(UiArtTable.KEY_SECTION_GIFTS))
	_experiments_section.set_header_icon(art.lobby_icon(UiArtTable.KEY_SECTION_EXPERIMENTS))
	# Hierarchy: sections one section_gap apart, then rows one space-3 apart (_prepare_rows).
	_settings_column.add_theme_constant_override("separation", MenuStyleFactory.arcade_tuning().section_gap_px)
	_settings_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: scrolled.emit())


# --- Public API -------------------------------------------------------------------

## Everything except seat budget, roster, bot names and rng seed.
func config() -> MatchConfig:
	var result: MatchConfig = MatchConfig.new()
	# there is one map; the disc size is the choice.
	result.disc_size_step = _disc_size_step()
	result.block_timer = _block_timer_seconds()
	result.gravity_multiplier = _gravity_value
	result.goal_flag_count = _goal_flag_stepper.value
	result.gifts_enabled = _gifts_check.button_pressed
	result.experiments_enabled = _experiments_check.button_pressed
	result.special_frequency = _special_frequency_value
	result.tilt_mode = _tilt_mode_option.selected()
	result.hole_mode = _hole_mode_option.selected()
	result.weather_mode = _weather_option.selected() as MatchConfig.WeatherMode
	result.sky_theme_mode = _sky_theme_option.selected() as MatchConfig.SkyThemeMode
	result.match_timer_minutes = _match_timer_stepper.value
	result.game_mode = MatchConfig.resolve_game_mode(_game_mode_option.selected())
	result.round_timer_minutes = _round_timer_stepper.value
	result.sky_team_sum = _sky_team_sum_check.button_pressed
	result.sudden_death = _sudden_death_check.button_pressed
	result.sudden_death_seconds = _sudden_death_seconds_stepper.value
	result.turn_based = _turn_based_check.button_pressed
	result.allow_mid_match_join = _mid_join_check.button_pressed
	result.enabled_specials = _enabled_specials_from_checkboxes()
	# DECISION: always publish an explicit qol (never null) so the chips are the single source of the
	# enable flags: a toggle left on in the F4 panel cannot leak into a lobby match the host sees as
	# "all off". Numeric parameters stay in the shared resource.
	result.qol = QolExperiments.with_toggles(
		QOL_SHARED, _qol_timer_pause_check.button_pressed, _qol_backlog_check.button_pressed,
		_qol_goal_radius_check.button_pressed, _qol_gift_slot_check.button_pressed,
		_qol_gift_loads_next_check.button_pressed
	)
	return result


## Wires data into the controls without emitting `changed`. A value outside its MatchConfig range is
## clamped (sanitize) rather than trusted, whether it came from the wire or from the host itself.
func apply(source: MatchConfig) -> void:
	var data: MatchConfig = source.duplicate(true) as MatchConfig
	data.sanitize()
	_applying_remote_data = true
	_disc_size_meter.set_value_silent(data.disc_size_step + 1)
	_block_timer_stepper.set_value_silent(roundi(data.block_timer / BLOCK_TIMER_STEP_S))
	_gravity_value = data.gravity_multiplier
	_gravity_meter.set_value_silent(_gravity_cells_for(_gravity_value))
	_gravity_meter.queue_redraw()
	_goal_flag_stepper.set_value_silent(data.goal_flag_count)
	_toggle_silent(_gifts_check, data.gifts_enabled)
	_toggle_silent(_experiments_check, data.experiments_enabled)
	_special_frequency_value = data.special_frequency
	_special_freq_meter.set_value_silent(_frequency_cells_for(_special_frequency_value))
	_special_freq_meter.queue_redraw()
	_tilt_mode_option.select(data.tilt_mode)
	_hole_mode_option.select(data.hole_mode)
	_weather_option.select(data.weather_mode)
	_sky_theme_option.select(data.sky_theme_mode)
	# the timer control's minimum follows the mode, so it is retargeted before either value is
	# written (Elimination may hold 0).
	_game_mode_option.select(data.game_mode)
	_refresh_timer_control(data.game_mode)
	_match_timer_stepper.value = data.match_timer_minutes
	_round_timer_stepper.value = data.round_timer_minutes
	_toggle_silent(_sky_team_sum_check, data.sky_team_sum)
	_refresh_sky_controls()
	_toggle_silent(_sudden_death_check, data.sudden_death)
	_sudden_death_seconds_stepper.set_value_silent(data.sudden_death_seconds)
	_toggle_silent(_turn_based_check, data.turn_based)
	_toggle_silent(_mid_join_check, data.allow_mid_match_join)
	_apply_enabled_specials_to_checkboxes(data.enabled_specials)
	# a null qol (an older host, or match_defaults.tres) reads as every experiment off.
	var qol: QolExperiments = data.qol
	_chip_silent(_qol_timer_pause_check, qol != null and qol.timer_pause_enabled)
	_chip_silent(_qol_backlog_check, qol != null and qol.backlog_enabled)
	_chip_silent(_qol_goal_radius_check, qol != null and qol.goal_radius_enabled)
	_chip_silent(_qol_gift_slot_check, qol != null and qol.gift_slot_enabled)
	_chip_silent(_qol_gift_loads_next_check, qol != null and qol.gift_loads_next)
	_applying_remote_data = false
	_refresh_master_toggles()
	_update_section_summaries()


## Host-only gating of every control. Written only when a value changes: the lobby calls this every
## frame, and a stepper or meter repaints on every write.
func set_editable(host: bool) -> void:
	_host = host
	_apply_editable()


## Ordered settings focus stops, gated-off and hidden ones removed. A client keeps its stops (it
## reads the settings with the pad too).
func focus_stops() -> Array[Control]:
	var chain: Array[Control] = []
	var game_main: Array[Control] = [_game_mode_option, _disc_size_meter, _sky_theme_option, _weather_option]
	var game_advanced: Array[Control] = [
		_gravity_meter, _tilt_mode_option, _hole_mode_option, _turn_based_check, _mid_join_check,
	]
	chain.append_array(_section_chain(_game_section, game_main, game_advanced))
	var round_main: Array[Control] = [
		_round_timer_stepper, _match_timer_stepper, _sudden_death_check, _sudden_death_seconds_stepper,
		_block_timer_stepper, _goal_flag_stepper, _sky_team_sum_check,
	]
	chain.append_array(_section_chain(_round_section, round_main, []))
	var gifts_advanced: Array[Control] = []
	gifts_advanced.append_array(_special_checkboxes)
	chain.append_array(_section_chain(_gifts_section, [_gifts_check, _special_freq_meter], gifts_advanced))
	var experiments_main: Array[Control] = [_experiments_check]
	experiments_main.append_array(_qol_checks)
	chain.append_array(_section_chain(_experiments_section, experiments_main, []))
	var live: Array[Control] = []
	for control: Control in chain:
		if _is_shown(control) and not _is_gated_off(control):
			live.append(control)
	return live


## Y on the pad: toggles the Advanced block of the section that holds focus, falling back to the
## first section that has one (GAME). Collapsing a block that holds focus hands focus to its chip
## (UiSection.set_advanced_open()).
func toggle_focused_advanced() -> void:
	var target: UiSection = null
	for section: UiSection in sections():
		if section.has_advanced() and section.has_focus_inside():
			target = section
			break
	if target == null:
		for section: UiSection in sections():
			if section.has_advanced():
				target = section
				break
	if target != null:
		target.toggle_advanced()


func sections() -> Array[UiSection]:
	return [_game_section, _round_section, _gifts_section, _experiments_section]


## The lobby opens on the disc-size meter.
func focus_entry() -> void:
	_disc_size_meter.grab_focus()


## Menus with scrollbars don't start at the top: deferred so it lands after the layout pass and any
## focus-follow scroll that the opening focus triggered.
func scroll_to_top() -> void:
	_settings_scroll.set_deferred(&"scroll_vertical", 0)


# --- Building the controls ---------------------------------------------------------

## Every UiRow gets its label from the scene's `row_label` metadata (the scene authors the text next
## to the control it names); a long caption wraps inside the fixed label column instead of widening
## it. Every stack of rows gets the design-system row gap.
func _prepare_rows() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	for node: Node in _settings_column.find_children("*", "HBoxContainer", true, false):
		var row: UiRow = node as UiRow
		if row == null:
			continue
		row.label.text = str(row.get_meta(ROW_LABEL_META, ""))
		row.label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiHelpLine.tag(row, String(row.name))
	_help_line.bind(_settings_scroll)
	for chip: UiChipToggle in _qol_checks:
		UiHelpLine.tag(chip, String(chip.name))
	for node: Node in _settings_column.find_children("*", "", true, false):
		if node.is_in_group(STACK_GROUP):
			node.add_theme_constant_override("separation", arcade.space_3_px)
	for grid: GridContainer in [_specials_checklist, _experiments_checklist]:
		grid.add_theme_constant_override("h_separation", arcade.space_2_px)
		grid.add_theme_constant_override("v_separation", arcade.space_2_px)


## The visible option rows are UiCyclers ("<" value ">" blocks, wrapping, ui_left / ui_right step).
func _populate_options() -> void:
	_configure_timer_steppers()
	_configure_value_controls()
	_fill_cycle(_tilt_mode_option, ["Specials only", "Physical balance"])
	# "Off" must still be the option list's third item, at the same index as the enum value, or
	# selecting 2 on a 2-item list is silently ignored and a config asking for OFF is stuck on the
	# old holes. The lobby shows whatever config/match/match_defaults.tres stores.
	_fill_cycle(_hole_mode_option, ["Temporary", "Permanent", "Off"])
	# order must match MatchConfig.WeatherMode; labels come from the enum names.
	var weather_labels: Array = MatchWeather.mode_labels()
	for weather_index: int in range(weather_labels.size()):
		_weather_option.add_item(weather_labels[weather_index] as String)
	_fill_cycle(_sky_theme_option, Array(SKY_THEME_LABELS))
	# order must match MatchConfig.GameMode. Reserved modes are listed but disabled, so neither the
	# mouse nor the gamepad popup can pick one; MatchConfig.resolve_game_mode() also rejects them on
	# the wire.
	_fill_cycle(_game_mode_option, Array(MatchConfig.GAME_MODE_LABELS))
	for mode_index: int in range(_game_mode_option.get_item_count()):
		_game_mode_option.set_item_disabled(mode_index, not MatchConfig.is_game_mode_selectable(mode_index))
	_align_cyclers()
	_build_specials_checklist()


## Range and step of the timer steppers come from MatchConfig, so the .tscn's authored numbers can
## never drift from the clamp the host applies. The match stepper runs Off (0) to the maximum; the
## round stepper's minimum is retargeted per mode by _refresh_timer_control().
func _configure_timer_steppers() -> void:
	for stepper: UiStepper in [_match_timer_stepper, _round_timer_stepper]:
		stepper.max_value = MatchConfig.ROUND_TIMER_MAX_MINUTES
	_match_timer_stepper.min_value = MatchConfig.ROUND_TIMER_OFF_MINUTES
	_round_timer_stepper.min_value = MatchConfig.ROUND_TIMER_MIN_MINUTES
	_match_timer_stepper.formatter = _timer_stepper_text
	_round_timer_stepper.formatter = _timer_stepper_text
	_match_timer_stepper.set_value_silent(MatchConfig.ROUND_TIMER_OFF_MINUTES)
	_round_timer_stepper.set_value_silent(MatchConfig.ROUND_TIMER_DEFAULT_MINUTES)
	# An unchanged value emits no signal, so seed what _on_timer_stepper_changed() compares against.
	_timer_previous_minutes[_match_timer_stepper] = _match_timer_stepper.value
	_timer_previous_minutes[_round_timer_stepper] = _round_timer_stepper.value
	_sudden_death_seconds_stepper.min_value = MatchConfig.SUDDEN_DEATH_MIN_SECONDS
	_sudden_death_seconds_stepper.max_value = MatchConfig.SUDDEN_DEATH_MAX_SECONDS
	_sudden_death_seconds_stepper.step = MatchConfig.SUDDEN_DEATH_STEP_SECONDS
	_sudden_death_seconds_stepper.formatter = BeaconTimerText.clock
	_sudden_death_seconds_stepper.set_value_silent(MatchConfig.SUDDEN_DEATH_DEFAULT_SECONDS)


## Block timer (half-second steps between MatchConfig's bounds), goal flags, disc size, gravity and
## gift-frequency meters: ranges and readouts come from MatchConfig and DiscSizeTuning, never from
## the scene's authored numbers.
func _configure_value_controls() -> void:
	_block_timer_stepper.min_value = roundi(MatchConfig.BLOCK_TIMER_MIN / BLOCK_TIMER_STEP_S)
	_block_timer_stepper.max_value = roundi(MatchConfig.BLOCK_TIMER_MAX / BLOCK_TIMER_STEP_S)
	_block_timer_stepper.formatter = func(steps: int) -> String: return BLOCK_TIMER_VALUE_FORMAT % _block_timer_seconds_for(steps)
	_block_timer_stepper.set_value_silent(_block_timer_stepper.min_value)
	_goal_flag_stepper.min_value = MatchConfig.GOAL_FLAG_MIN
	_goal_flag_stepper.max_value = MatchConfig.GOAL_FLAG_MAX
	_goal_flag_stepper.set_value_silent(MatchConfig.GOAL_FLAG_MIN)
	var disc: DiscSizeTuning = DiscSizeTuning.shared()
	_disc_size_meter.step_count = disc.step_count()
	_disc_size_meter.formatter = func(cells: int) -> String: return DISC_SIZE_READOUT_FORMAT % roundi(disc.factor_for(cells - 1) * PERCENT_SCALE)
	_disc_size_meter.set_value_silent(MatchConfig.DISC_SIZE_STEP_DEFAULT + 1)
	_gravity_meter.step_count = GRAVITY_CELLS
	_gravity_meter.formatter = func(_cells: int) -> String: return GRAVITY_READOUT_FORMAT % _gravity_value
	_special_freq_meter.step_count = FREQUENCY_CELLS
	_special_freq_meter.formatter = func(_cells: int) -> String: return FREQUENCY_READOUT_FORMAT % _special_frequency_value


## Every cycler of the GAME section (main rows and Advanced) shares the widest value area, so the
## "<" / ">" blocks line up from row to row.
func _align_cyclers() -> void:
	var cyclers: Array[UiCycler] = [
		_game_mode_option, _sky_theme_option, _weather_option, _tilt_mode_option, _hole_mode_option,
	]
	var widest: float = 0.0
	for cycler: UiCycler in cyclers:
		widest = maxf(widest, cycler.content_width())
	for cycler: UiCycler in cyclers:
		cycler.min_value_width = widest


func _fill_cycle(selector: UiCycler, labels: Array) -> void:
	selector.clear()
	for label: String in labels:
		selector.add_item(label)


## Enabled-specials checklist: config/gifts/specials/*.tres with enabled_by_default
## (SpecialDef.load_selectable_specials()), in id order (the same sorted, deterministic order every
## peer's own load produces, so two peers never see a differently-ordered list). Checked = enabled,
## mirroring MatchConfig.enabled_specials's own "empty = all enabled" default. Disabled gifts (Cat)
## are not listed: the checklist walks the same roster the match draws from.
func _build_specials_checklist() -> void:
	for child: Node in _specials_checklist.get_children():
		_specials_checklist.remove_child(child)
		child.queue_free()
	_special_checkboxes.clear()
	_special_ids.clear()
	for special: SpecialDef in SpecialDef.load_selectable_specials():
		var chip: UiChipToggle = UiChipToggle.new()
		# SpecialDef has no display_name: DisplayNames turns the id (e.g. &"jumping_bean") into the label.
		chip.label = DisplayNames.special(special.id)
		chip.chip_icon = GiftIconTable.shared().gift_pictogram(special.id)
		chip.set_on_silent(true)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.toggled.connect(_on_toggled)
		UiHelpLine.tag(chip, OptionHelpTable.gift_key(special.id))
		_specials_checklist.add_child(chip)
		_special_checkboxes.append(chip)
		_special_ids.append(special.id)


func _connect_control_signals() -> void:
	_tilt_mode_option.item_selected.connect(_on_option_changed)
	_hole_mode_option.item_selected.connect(_on_option_changed)
	_weather_option.item_selected.connect(_on_option_changed)
	# retarget the timer control before the publish reads it.
	_game_mode_option.item_selected.connect(_on_game_mode_picked)
	_game_mode_option.item_selected.connect(_on_option_changed)
	_game_mode_option.item_selected.connect(_refresh_sky_controls)
	_sky_theme_option.item_selected.connect(_on_option_changed)
	_round_timer_stepper.value_changed.connect(_on_timer_stepper_changed.bind(_round_timer_stepper))
	_match_timer_stepper.value_changed.connect(_on_timer_stepper_changed.bind(_match_timer_stepper))
	_block_timer_stepper.value_changed.connect(_on_stepper_changed)
	_goal_flag_stepper.value_changed.connect(_on_stepper_changed)
	_sudden_death_seconds_stepper.value_changed.connect(_on_stepper_changed)
	_gravity_meter.value_changed.connect(_on_gravity_cells_changed)
	_special_freq_meter.value_changed.connect(_on_frequency_cells_changed)
	_disc_size_meter.value_changed.connect(_on_disc_size_changed)
	for toggle: UiToggle in [
		_sky_team_sum_check, _gifts_check, _experiments_check, _sudden_death_check, _turn_based_check,
		_mid_join_check,
	]:
		toggle.toggled.connect(_on_toggled)
	for qol_check: UiChipToggle in _qol_checks:
		qol_check.toggled.connect(_on_toggled)


# --- Focus stops -------------------------------------------------------------------

## One section's focus stops in visual order: main controls, Advanced chip, Advanced controls (the
## header is static and not a stop).
func _section_chain(section: UiSection, main_controls: Array[Control], advanced_controls: Array[Control]) -> Array[Control]:
	var out: Array[Control] = []
	out.append_array(main_controls)
	if section.advanced_button != null:
		out.append(section.advanced_button)
	out.append_array(advanced_controls)
	return out


## A control is a focus stop only while it and every ancestor up to this card are visible: a
## collapsed section or Advanced block, a hidden conditional column (the Reach the Sky toggle
## outside its mode, the timer column the mode does not use, goal flags in a mode without them).
func _is_shown(control: Control) -> bool:
	var node: Node = control
	while node != null and node != self:
		var item: CanvasItem = node as CanvasItem
		if item != null and not item.visible:
			return false
		node = node.get_parent()
	return true


## True for a control a master switch has greyed out (gifts off: Frequency and the per-gift bar):
## visible but not a focus stop, for every role.
func _is_gated_off(control: Control) -> bool:
	return not _gifts_check.button_pressed and (control == _special_freq_meter or control == _gifts_section.advanced_button)


# --- Handlers ---------------------------------------------------------------------

func _emit_changed() -> void:
	if not _applying_remote_data:
		changed.emit()


func _on_section_toggled(state: bool) -> void:
	Events.lobby_ui_cue.emit(&"section_expanded" if state else &"section_collapsed")
	layout_changed.emit()


func _on_option_changed(_index: int) -> void:
	_emit_changed()


func _on_stepper_changed(_value: int) -> void:
	_emit_changed()


func _on_toggled(_pressed: bool) -> void:
	_refresh_master_toggles()
	_emit_changed()


## The disc-size meter moved; republish like any host edit.
## DECISION: the meter lights step + 1 cells (Tiny = one cell), so an empty meter is not a size: a
## click on its far left edge (0 cells) settles on the smallest size.
func _on_disc_size_changed(cells: int) -> void:
	if cells < 1:
		_disc_size_meter.set_value_silent(1)
	_emit_changed()


## The disc-size step (0 .. DiscSizeTuning.step_count() - 1) the meter shows.
func _disc_size_step() -> int:
	return maxi(_disc_size_meter.value, 1) - 1


## "Medium - 100%" for the current disc size; the Game section's summary entry.
func _disc_size_text() -> String:
	return DiscSizeTuning.shared().value_text(_disc_size_step())


## The block timer in seconds for [param steps] stepper steps.
static func _block_timer_seconds_for(steps: int) -> float:
	return float(steps) * BLOCK_TIMER_STEP_S


func _block_timer_seconds() -> float:
	return _block_timer_seconds_for(_block_timer_stepper.value)


## A player moved the gravity meter: each lit cell is MatchConfig.GRAVITY_STEP, so cell n reads
## n * 0.1 and 1.0 is cell 10; an empty meter settles on MatchConfig.GRAVITY_MIN.
func _on_gravity_cells_changed(cells: int) -> void:
	_gravity_value = clampf(
		snappedf(float(cells) * MatchConfig.GRAVITY_STEP, MatchConfig.GRAVITY_STEP),
		MatchConfig.GRAVITY_MIN, MatchConfig.GRAVITY_MAX
	)
	_emit_changed()


func _on_frequency_cells_changed(cells: int) -> void:
	var span: int = MatchConfig.SPECIAL_FREQUENCY_MAX - MatchConfig.SPECIAL_FREQUENCY_MIN
	_special_frequency_value = MatchConfig.SPECIAL_FREQUENCY_MIN + roundi(float(span) * float(cells) / float(FREQUENCY_CELLS))
	_emit_changed()


## The cell a gravity multiplier / gift frequency lights (nearest), for values applied from lobby data.
static func _gravity_cells_for(gravity: float) -> int:
	return clampi(roundi(gravity / MatchConfig.GRAVITY_STEP), 0, GRAVITY_CELLS)


static func _frequency_cells_for(frequency: int) -> int:
	var span: int = MatchConfig.SPECIAL_FREQUENCY_MAX - MatchConfig.SPECIAL_FREQUENCY_MIN
	return clampi(roundi(float(frequency - MatchConfig.SPECIAL_FREQUENCY_MIN) / float(span) * float(FREQUENCY_CELLS)), 0, FREQUENCY_CELLS)


## A host picked a mode. The team-aggregation toggle exists only for Reach the Sky. Moving between
## timer families (classic <-> timed, Elimination <-> CTF/Sky) resets the control to the new mode's
## default; CTF <-> Reach the Sky keeps the chosen length.
func _on_game_mode_picked(index: int) -> void:
	var old_mode: int = _timer_mode
	var new_mode: int = MatchConfig.resolve_game_mode(index)
	_refresh_timer_control(new_mode)
	if old_mode != new_mode and (old_mode == MatchConfig.GameMode.ELIMINATION or new_mode == MatchConfig.GameMode.ELIMINATION):
		_hole_mode_option.select(MatchConfig.default_hole_mode(new_mode))
		_emit_changed()
	if not MatchConfig.same_timer_family(old_mode, new_mode):
		_timer_stepper_for(new_mode).value = MatchConfig.timer_default_minutes(new_mode)


func _timer_stepper_for(mode: int) -> UiStepper:
	return _match_timer_stepper if MatchConfig.timer_is_match_timer(mode) else _round_timer_stepper


## Shows the one timer control `mode` uses, with its label and minimum, and hides the sudden-death
## toggle outside classic (the only mode that has it).
func _refresh_timer_control(mode: int) -> void:
	_timer_mode = mode
	var classic: bool = MatchConfig.timer_is_match_timer(mode)
	_match_timer_col.visible = classic
	_sudden_death_col.visible = classic
	_round_timer_col.visible = not classic
	_goal_flag_col.visible = MatchConfig.mode_uses_goal_flags(mode)
	var was_applying: bool = _applying_remote_data
	_applying_remote_data = true
	_round_timer_stepper.min_value = MatchConfig.timer_min_minutes(mode) if not classic else MatchConfig.ROUND_TIMER_MIN_MINUTES
	# A stepper does not re-clamp its value when its minimum moves (a Range did).
	_round_timer_stepper.value = maxi(_round_timer_stepper.value, _round_timer_stepper.min_value)
	_applying_remote_data = was_applying
	UiHelpLine.tag(_round_timer_col, ROUND_HELP_KEY_DOMINATION if mode == MatchConfig.GameMode.DOMINATION else String(_round_timer_col.name))
	layout_changed.emit()


## DECISION: the timer stepper reads a bare number; the match timer's lowest stop stays the word "Off".
static func _timer_stepper_text(minutes: int) -> String:
	if minutes <= MatchConfig.ROUND_TIMER_OFF_MINUTES:
		return TIMER_OFF_TEXT
	return TIMER_STEPPER_FORMAT % minutes


static func _timer_value_text(minutes: int) -> String:
	if minutes <= MatchConfig.ROUND_TIMER_OFF_MINUTES:
		return TIMER_OFF_TEXT
	return TIMER_VALUE_FORMAT % minutes


## Either timer stepper moved (host click or hold, gamepad left/right, or a programmatic write).
## Host edits skip the 1-minute gap so the stops read Off, 2, 3 ... 30: stepping up from Off lands
## on 2 and stepping down from 2 lands on Off. A value applied from lobby data is shown as-is (the
## host's sanitize() already decided).
func _on_timer_stepper_changed(value: int, stepper: UiStepper) -> void:
	var minutes: int = value
	var previous: int = _timer_previous_minutes.get(stepper, minutes)
	var in_gap: bool = minutes > MatchConfig.ROUND_TIMER_OFF_MINUTES and minutes < MatchConfig.ROUND_TIMER_MIN_MINUTES
	if in_gap and not _applying_remote_data:
		minutes = MatchConfig.ROUND_TIMER_MIN_MINUTES if minutes > previous else MatchConfig.ROUND_TIMER_OFF_MINUTES
		stepper.set_value_silent(minutes)
	_timer_previous_minutes[stepper] = minutes
	_emit_changed()


func _refresh_sky_controls(_index: int = 0) -> void:
	_refresh_timer_control(MatchConfig.resolve_game_mode(_game_mode_option.selected()))
	_sky_team_col.visible = _game_mode_option.selected() == MatchConfig.GameMode.REACH_THE_SKY
	layout_changed.emit()


## A master switch that is off governs its section: gifts off -> the Frequency row and the GIFTS
## Advanced bar stay visible but greyed (dimmed, read-only, not focus stops); experiments off -> the
## trials row is hidden. Turning it back on restores them (the Advanced bar closed); the selections
## themselves are untouched. Runs on a local toggle and after an apply.
func _refresh_master_toggles() -> void:
	var gifts_on: bool = _gifts_check.button_pressed
	_special_freq_group.modulate.a = 1.0 if gifts_on else MenuStyleFactory.arcade_tuning().disabled_alpha
	_special_freq_meter.focus_mode = Control.FOCUS_ALL if gifts_on else Control.FOCUS_NONE
	_gifts_section.set_advanced_enabled(gifts_on)
	_experiments_group.visible = _experiments_check.button_pressed
	_apply_editable()
	layout_changed.emit()


# --- Summaries ----------------------------------------------------------------------

## The one-line summary on each section header, read straight off the same controls config() reads.
## Called after every apply, so a host edit and a remote update both refresh it.
func _update_section_summaries() -> void:
	_game_section.set_summary(SUMMARY_SEPARATOR.join([
		_game_mode_option.selected_text(), _disc_size_text(),
		_sky_theme_option.selected_text(), _weather_option.selected_text(),
	]))
	var timer_stepper: UiStepper = _timer_stepper_for(_timer_mode)
	var round_parts: Array[String] = [
		_timer_value_text(timer_stepper.value),
		SUMMARY_BLOCK_TIMER_FORMAT % _block_timer_seconds(),
	]
	if _goal_flag_col.visible:
		var flags: int = _goal_flag_stepper.value
		round_parts.append((SUMMARY_GOAL_FLAG_FORMAT if flags == 1 else SUMMARY_GOAL_FLAGS_FORMAT) % flags)
	_round_section.set_summary(SUMMARY_SEPARATOR.join(round_parts))
	if _gifts_check.button_pressed:
		var gifts_summary: String = SUMMARY_GIFTS_ON_FORMAT % [SUMMARY_SEPARATOR, _special_frequency_value]
		var enabled_gifts: int = 0
		for box: UiChipToggle in _special_checkboxes:
			if box.button_pressed:
				enabled_gifts += 1
		if enabled_gifts != _special_checkboxes.size():
			gifts_summary += SUMMARY_SEPARATOR + SUMMARY_GIFT_COUNT_FORMAT % [enabled_gifts, _special_checkboxes.size()]
		_gifts_section.set_summary(gifts_summary)
	else:
		_gifts_section.set_summary(SUMMARY_GIFTS_OFF)
	var experiments_on: int = 0
	for qol_check: UiChipToggle in _qol_checks:
		if qol_check.button_pressed:
			experiments_on += 1
	if _experiments_check.button_pressed:
		_experiments_section.set_summary(SUMMARY_EXPERIMENTS_FORMAT % experiments_on)
	else:
		_experiments_section.set_summary(SUMMARY_GIFTS_OFF)


# --- Specials checklist round trip ---------------------------------------------------

## MatchConfig.enabled_specials's own doc: "Empty means every special enabled" -- so "every chip
## checked" (the state the checklist starts in) must publish an empty array, not the full id list.
## Only "every chip unchecked" gets the ALL_DISABLED_SENTINEL; anything in between is the literal
## checked-id list.
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


## apply()'s round trip for the specials checklist: empty -> every chip checked, the sentinel alone
## -> every chip unchecked, otherwise check exactly the ids named.
func _apply_enabled_specials_to_checkboxes(enabled: Array[StringName]) -> void:
	var all_enabled: bool = enabled.is_empty()
	var all_disabled: bool = enabled.has(ALL_DISABLED_SENTINEL)
	for i: int in range(_special_checkboxes.size()):
		if all_enabled:
			_chip_silent(_special_checkboxes[i], true)
		elif all_disabled:
			_chip_silent(_special_checkboxes[i], false)
		else:
			_chip_silent(_special_checkboxes[i], enabled.has(_special_ids[i]))


## DECISION: a remote apply runs 3-4 times per lobby open and every set_on_silent() rebuilds the
## chip's five block styleboxes (~1 ms each, ~20 chips), even when the state is already right.
## Writing only a changed state keeps the view identical and skips that.
func _chip_silent(chip: UiChipToggle, on: bool) -> void:
	if chip.is_on() != on:
		chip.set_on_silent(on)


func _toggle_silent(toggle: UiToggle, on: bool) -> void:
	if toggle.is_on() != on:
		toggle.set_on_silent(on)


# --- Host gating --------------------------------------------------------------------

func _apply_editable() -> void:
	for control: Control in _settings_controls:
		var governed_on: bool = control != _special_freq_meter or _gifts_check.button_pressed
		_set_control_editable(control, _host and governed_on)
	# The sudden-death length only exists while the toggle is on (host and client read it).
	_sudden_death_seconds_stepper.visible = _sudden_death_check.button_pressed


## Host edits, client reads: each component family has its own switch (only written when it changes,
## because the lobby calls this every frame and a stepper / meter repaints on every write).
func _set_control_editable(control: Control, editable: bool) -> void:
	if control is UiStepper:
		var stepper: UiStepper = control as UiStepper
		if stepper.disabled == editable:
			stepper.disabled = not editable
	elif control is UiCycler:
		var cycler: UiCycler = control as UiCycler
		if cycler.disabled == editable:
			cycler.disabled = not editable
	elif control is UiSegmentMeter:
		var meter: UiSegmentMeter = control as UiSegmentMeter
		if meter.editable != editable:
			meter.editable = editable
	elif control is BaseButton:
		(control as BaseButton).disabled = not editable
