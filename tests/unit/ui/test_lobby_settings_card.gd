extends GutTest
## LobbySettingsCard contract: what a Lobby observes of the settings form. apply() then config()
## round-trips every control group, host gating leaves every setting control read-only, `changed`
## is a host edit and never an apply, `layout_changed` fires when a row or the Advanced block
## shows or hides, and the focus stops are a set of live controls (membership, never order).

const CARD_SCENE: PackedScene = preload("res://ui/lobby/LobbySettingsCard.tscn")
## The wire marker for "every special unchecked" (an empty list means "all enabled").
const ALL_DISABLED_SENTINEL: StringName = &"__none__"
const FLOAT_TOLERANCE: float = 0.01

var _changed_count: int = 0
var _layout_count: int = 0


func _make_card(host: bool = true) -> LobbySettingsCard:
	var card: LobbySettingsCard = CARD_SCENE.instantiate() as LobbySettingsCard
	card.changed.connect(func() -> void: _changed_count += 1)
	card.layout_changed.connect(func() -> void: _layout_count += 1)
	add_child_autofree(card)
	card.set_editable(host)
	_changed_count = 0
	_layout_count = 0
	return card


func _round_trip(card: LobbySettingsCard, config: MatchConfig) -> MatchConfig:
	card.apply(config)
	var got: MatchConfig = card.config()
	assert_not_null(got, "config() returns the form's values")
	return got


func _controls_under(node: Node, out: Array[Control]) -> Array[Control]:
	for child: Node in node.get_children():
		var control: Control = child as Control
		if control != null:
			out.append(control)
		_controls_under(child, out)
	return out


func _section_bars(card: LobbySettingsCard) -> Array[Button]:
	var bars: Array[Button] = []
	for section: UiSection in card.sections():
		if section.advanced_button != null:
			bars.append(section.advanced_button)
	return bars


## True when a player cannot change this control: the class query the lobby gating uses.
func _is_read_only(control: Control) -> bool:
	if control is UiStepper:
		return (control as UiStepper).disabled
	if control is UiCycler:
		return (control as UiCycler).disabled
	if control is UiSegmentMeter:
		return not (control as UiSegmentMeter).editable
	if control is BaseButton:
		return (control as BaseButton).disabled
	return false


## A setting control; a section's Advanced bar is not one (a read-only client may still open it).
func _is_setting_control(control: Control, bars: Array[Button]) -> bool:
	if bars.has(control):
		return false
	return control is UiStepper or control is UiCycler or control is UiSegmentMeter or control is BaseButton


# --- apply / config round trip -----------------------------------------------

func test_classic_settings_round_trip() -> void:
	var card: LobbySettingsCard = _make_card()
	var config: MatchConfig = MatchConfig.new()
	config.game_mode = MatchConfig.GameMode.CLASSIC
	config.disc_size_step = 3
	config.block_timer = 9.5
	config.gravity_multiplier = 1.2
	config.goal_flag_count = 3
	config.gifts_enabled = true
	config.special_frequency = 80
	config.tilt_mode = MatchConfig.TiltMode.PHYSICAL_BALANCE
	config.hole_mode = MatchConfig.HoleMode.PERMANENT
	config.match_timer_minutes = 20
	config.sudden_death = true
	config.sudden_death_seconds = 180
	config.turn_based = true
	config.allow_mid_match_join = true
	config.weather_mode = MatchConfig.WeatherMode.SNOW
	config.sky_theme_mode = MatchConfig.SkyThemeMode.NIGHT
	var got: MatchConfig = _round_trip(card, config)
	if got == null:
		return
	assert_eq(got.game_mode, MatchConfig.GameMode.CLASSIC)
	assert_eq(got.disc_size_step, 3)
	assert_almost_eq(got.block_timer, 9.5, FLOAT_TOLERANCE)
	assert_almost_eq(got.gravity_multiplier, 1.2, FLOAT_TOLERANCE)
	assert_eq(got.goal_flag_count, 3)
	assert_true(got.gifts_enabled)
	assert_eq(got.special_frequency, 80)
	assert_eq(got.tilt_mode, MatchConfig.TiltMode.PHYSICAL_BALANCE)
	assert_eq(got.hole_mode, MatchConfig.HoleMode.PERMANENT)
	assert_eq(got.match_timer_minutes, 20)
	assert_true(got.sudden_death)
	assert_eq(got.sudden_death_seconds, 180)
	assert_true(got.turn_based)
	assert_true(got.allow_mid_match_join)
	assert_eq(got.weather_mode, MatchConfig.WeatherMode.SNOW)
	assert_eq(got.sky_theme_mode, MatchConfig.SkyThemeMode.NIGHT)


func test_toggles_round_trip_in_both_states() -> void:
	var card: LobbySettingsCard = _make_card()
	var config: MatchConfig = MatchConfig.new()
	config.gifts_enabled = false
	config.sudden_death = false
	config.turn_based = false
	config.allow_mid_match_join = false
	config.experiments_enabled = true
	var got: MatchConfig = _round_trip(card, config)
	if got == null:
		return
	assert_false(got.gifts_enabled)
	assert_false(got.sudden_death)
	assert_false(got.turn_based)
	assert_false(got.allow_mid_match_join)
	assert_true(got.experiments_enabled)
	config.gifts_enabled = true
	config.experiments_enabled = false
	got = _round_trip(card, config)
	if got == null:
		return
	assert_true(got.gifts_enabled)
	assert_false(got.experiments_enabled)


func test_timed_mode_settings_round_trip() -> void:
	var card: LobbySettingsCard = _make_card()
	var config: MatchConfig = MatchConfig.new()
	config.game_mode = MatchConfig.GameMode.ELIMINATION
	config.round_timer_minutes = 12
	var got: MatchConfig = _round_trip(card, config)
	if got == null:
		return
	assert_eq(got.game_mode, MatchConfig.GameMode.ELIMINATION)
	assert_eq(got.round_timer_minutes, 12)
	config.game_mode = MatchConfig.GameMode.REACH_THE_SKY
	config.round_timer_minutes = 7
	config.sky_team_sum = true
	got = _round_trip(card, config)
	if got == null:
		return
	assert_eq(got.game_mode, MatchConfig.GameMode.REACH_THE_SKY)
	assert_eq(got.round_timer_minutes, 7)
	assert_true(got.sky_team_sum)


func test_every_game_mode_round_trips() -> void:
	var card: LobbySettingsCard = _make_card()
	for mode: int in MatchConfig.SELECTABLE_GAME_MODES:
		var config: MatchConfig = MatchConfig.new()
		config.game_mode = mode as MatchConfig.GameMode
		var got: MatchConfig = _round_trip(card, config)
		if got == null:
			return
		assert_eq(got.game_mode, mode, "game mode %d" % mode)


func test_experiments_round_trip() -> void:
	var card: LobbySettingsCard = _make_card()
	var config: MatchConfig = MatchConfig.new()
	config.experiments_enabled = true
	config.qol = QolExperiments.new()
	config.qol.timer_pause_enabled = true
	config.qol.backlog_enabled = true
	config.qol.goal_radius_enabled = false
	config.qol.gift_slot_enabled = true
	config.qol.gift_loads_next = true
	var got: MatchConfig = _round_trip(card, config)
	if got == null:
		return
	assert_not_null(got.qol, "the card always publishes an explicit qol")
	if got.qol == null:
		return
	assert_true(got.qol.timer_pause_enabled)
	assert_true(got.qol.backlog_enabled)
	assert_false(got.qol.goal_radius_enabled)
	assert_true(got.qol.gift_slot_enabled)
	assert_true(got.qol.gift_loads_next)


func test_specials_default_is_the_empty_all_enabled_list() -> void:
	var card: LobbySettingsCard = _make_card()
	var got: MatchConfig = _round_trip(card, MatchConfig.new())
	if got == null:
		return
	assert_true(got.enabled_specials.is_empty(), "every special enabled publishes an empty list")


func test_specials_sentinel_round_trips_as_every_special_off() -> void:
	var card: LobbySettingsCard = _make_card()
	var config: MatchConfig = MatchConfig.new()
	config.enabled_specials = [ALL_DISABLED_SENTINEL]
	var got: MatchConfig = _round_trip(card, config)
	if got == null:
		return
	assert_eq(got.enabled_specials.size(), 1)
	assert_true(got.enabled_specials.has(ALL_DISABLED_SENTINEL), "not an empty array: that would mean all enabled")
	# Applying the empty list afterwards turns every special back on.
	got = _round_trip(card, MatchConfig.new())
	if got != null:
		assert_true(got.enabled_specials.is_empty())


func test_a_subset_of_specials_round_trips_exactly() -> void:
	var defs: Array[SpecialDef] = SpecialDef.load_selectable_specials()
	if defs.size() < 2:
		pass_test("fewer than 2 selectable specials in this checkout; no subset to distinguish")
		return
	var card: LobbySettingsCard = _make_card()
	var config: MatchConfig = MatchConfig.new()
	config.enabled_specials = [defs[0].id]
	var got: MatchConfig = _round_trip(card, config)
	if got == null:
		return
	assert_eq(got.enabled_specials.size(), 1)
	assert_true(got.enabled_specials.has(defs[0].id))


func test_out_of_range_values_are_clamped_on_apply() -> void:
	var card: LobbySettingsCard = _make_card()
	var config: MatchConfig = MatchConfig.new()
	config.block_timer = 999.0
	config.goal_flag_count = 99
	config.special_frequency = 500
	var got: MatchConfig = _round_trip(card, config)
	if got == null:
		return
	assert_almost_eq(got.block_timer, MatchConfig.BLOCK_TIMER_MAX, FLOAT_TOLERANCE)
	assert_eq(got.goal_flag_count, MatchConfig.GOAL_FLAG_MAX)
	assert_eq(got.special_frequency, MatchConfig.SPECIAL_FREQUENCY_MAX)


# --- host gating --------------------------------------------------------------

func test_set_editable_false_leaves_every_setting_control_read_only() -> void:
	var card: LobbySettingsCard = _make_card(true)
	card.apply(MatchConfig.new())
	card.set_editable(false)
	var bars: Array[Button] = _section_bars(card)
	var checked: int = 0
	for control: Control in _controls_under(card, [] as Array[Control]):
		if _is_setting_control(control, bars):
			checked += 1
			assert_true(_is_read_only(control), "%s is read-only for a client" % control.get_path())
	assert_gt(checked, 0, "the card has setting controls to gate")


func test_set_editable_true_restores_the_setting_controls() -> void:
	var card: LobbySettingsCard = _make_card(false)
	card.set_editable(true)
	var bars: Array[Button] = _section_bars(card)
	var live: int = 0
	for control: Control in _controls_under(card, [] as Array[Control]):
		if _is_setting_control(control, bars) and control.is_visible_in_tree():
			live += 1
			assert_false(_is_read_only(control), "%s is editable for the host" % control.get_path())
	assert_gt(live, 0)


func test_a_read_only_card_still_applies_host_data() -> void:
	var card: LobbySettingsCard = _make_card(false)
	var config: MatchConfig = MatchConfig.new()
	config.block_timer = 8.0
	config.turn_based = true
	var got: MatchConfig = _round_trip(card, config)
	if got == null:
		return
	assert_almost_eq(got.block_timer, 8.0, FLOAT_TOLERANCE)
	assert_true(got.turn_based)
	assert_eq(_changed_count, 0)


# --- changed ------------------------------------------------------------------

func test_apply_does_not_emit_changed() -> void:
	var card: LobbySettingsCard = _make_card()
	var config: MatchConfig = MatchConfig.new()
	config.block_timer = 10.0
	config.game_mode = MatchConfig.GameMode.ELIMINATION
	config.gifts_enabled = false
	config.enabled_specials = [ALL_DISABLED_SENTINEL]
	card.apply(config)
	card.apply(MatchConfig.new())
	assert_eq(_changed_count, 0, "an inbound update must not bounce back out")


func test_one_host_edit_emits_changed_once() -> void:
	var card: LobbySettingsCard = _make_card(true)
	card.apply(MatchConfig.new())
	var turn_based: UiToggle = card.find_child("TurnBasedCheck", true, false) as UiToggle
	assert_not_null(turn_based, "the turn-based toggle keeps its node name")
	if turn_based == null:
		return
	turn_based.button_pressed = true
	assert_eq(_changed_count, 1)
	var got: MatchConfig = card.config()
	assert_not_null(got)
	if got != null:
		assert_true(got.turn_based, "the edit is what config() reports")


func test_edit_after_apply_still_emits_changed() -> void:
	var card: LobbySettingsCard = _make_card(true)
	card.apply(MatchConfig.new())
	card.apply(MatchConfig.new())
	var stepper: UiStepper = card.find_child("GoalFlagStepper", true, false) as UiStepper
	assert_not_null(stepper)
	if stepper == null:
		return
	stepper.value = MatchConfig.GOAL_FLAG_MAX
	assert_eq(_changed_count, 1, "the apply guard is released once apply returns")


# --- layout_changed -----------------------------------------------------------

func test_opening_and_closing_advanced_emits_layout_changed() -> void:
	var card: LobbySettingsCard = _make_card()
	var advanced: UiSection = null
	for section: UiSection in card.sections():
		if section.has_advanced():
			advanced = section
			break
	assert_not_null(advanced, "at least one section has an Advanced block")
	if advanced == null:
		return
	advanced.set_advanced_open(true)
	assert_eq(_layout_count, 1, "opening Advanced")
	advanced.set_advanced_open(false)
	assert_eq(_layout_count, 2, "closing Advanced")


func test_toggle_focused_advanced_emits_layout_changed_when_focus_is_on_a_bar() -> void:
	var card: LobbySettingsCard = _make_card()
	var bars: Array[Button] = _section_bars(card)
	if bars.is_empty():
		pass_test("no section with an Advanced bar")
		return
	bars[0].grab_focus()
	card.toggle_focused_advanced()
	assert_eq(_layout_count, 1)


func test_a_gated_row_hiding_emits_layout_changed() -> void:
	var card: LobbySettingsCard = _make_card()
	var config: MatchConfig = MatchConfig.new()
	config.game_mode = MatchConfig.GameMode.CLASSIC
	card.apply(config)
	_layout_count = 0
	config = MatchConfig.new()
	config.game_mode = MatchConfig.GameMode.ELIMINATION
	card.apply(config)
	assert_gt(_layout_count, 0, "the match-timer row swapped for the round timer")
	assert_eq(_changed_count, 0)


func test_sudden_death_edit_shows_its_length_row_and_signals_layout() -> void:
	var card: LobbySettingsCard = _make_card(true)
	card.apply(MatchConfig.new())
	var sudden: UiToggle = card.find_child("SuddenDeathCheck", true, false) as UiToggle
	assert_not_null(sudden)
	if sudden == null:
		return
	_layout_count = 0
	sudden.button_pressed = true
	assert_gt(_layout_count, 0, "the sudden-death length row appears")
	assert_eq(_changed_count, 1)


# --- focus stops: set membership ---------------------------------------------

func test_every_live_focusable_control_is_a_stop_for_the_default_host_card() -> void:
	var card: LobbySettingsCard = _make_card(true)
	card.apply(MatchConfig.new())
	var stops: Array[Control] = card.focus_stops()
	assert_false(stops.is_empty())
	for control: Control in FocusWalk.live_focusable(card):
		assert_true(stops.has(control), "%s is live and focusable but not a stop" % control.get_path())


func test_every_stop_is_a_live_control_in_each_game_mode() -> void:
	var card: LobbySettingsCard = _make_card(true)
	for mode: int in MatchConfig.SELECTABLE_GAME_MODES:
		var config: MatchConfig = MatchConfig.new()
		config.game_mode = mode as MatchConfig.GameMode
		card.apply(config)
		var stops: Array[Control] = card.focus_stops()
		assert_false(stops.is_empty(), "mode %d has stops" % mode)
		for stop: Control in stops:
			assert_true(card.is_ancestor_of(stop), "%s belongs to the card" % stop.name)
			assert_true(FocusWalk.is_live(stop), "%s is shown and enabled (mode %d)" % [stop.name, mode])
			assert_ne(stop.focus_mode, Control.FOCUS_NONE, "%s takes focus (mode %d)" % [stop.name, mode])


func test_a_row_hidden_by_game_mode_is_not_a_stop() -> void:
	var card: LobbySettingsCard = _make_card(true)
	var config: MatchConfig = MatchConfig.new()
	config.game_mode = MatchConfig.GameMode.ELIMINATION
	card.apply(config)
	var flags: Control = card.find_child("GoalFlagStepper", true, false) as Control
	assert_not_null(flags)
	if flags == null:
		return
	assert_false(flags.is_visible_in_tree(), "Elimination has no goal flags")
	for stop: Control in card.focus_stops():
		assert_false(stop == flags or flags.is_ancestor_of(stop), "a hidden row is no focus stop")
	config.game_mode = MatchConfig.GameMode.CLASSIC
	card.apply(config)
	var shown: bool = false
	for stop: Control in card.focus_stops():
		shown = shown or stop == flags or flags.is_ancestor_of(stop)
	assert_true(shown, "the goal-flag row is a stop again in Classic")


func test_gifts_off_removes_gated_controls_from_the_stops() -> void:
	var card: LobbySettingsCard = _make_card(true)
	card.apply(MatchConfig.new())
	var with_gifts: int = card.focus_stops().size()
	var config: MatchConfig = MatchConfig.new()
	config.gifts_enabled = false
	card.apply(config)
	var stops: Array[Control] = card.focus_stops()
	assert_lt(stops.size(), with_gifts, "the gift controls drop out while gifts are off")
	for stop: Control in stops:
		assert_true(FocusWalk.is_live(stop), "%s is live" % stop.name)
		if stop is UiSegmentMeter:
			assert_true((stop as UiSegmentMeter).editable, "a greyed-out meter is not a stop")


func test_a_closed_advanced_block_contributes_no_stop() -> void:
	var card: LobbySettingsCard = _make_card(true)
	card.apply(MatchConfig.new())
	for section: UiSection in card.sections():
		if not section.has_advanced():
			continue
		section.set_advanced_open(false)
		for stop: Control in card.focus_stops():
			assert_false(section.advanced.is_ancestor_of(stop), "closed Advanced hides its controls")
		section.set_advanced_open(true)
		var inside: bool = false
		for stop: Control in card.focus_stops():
			inside = inside or section.advanced.is_ancestor_of(stop)
		assert_true(inside, "an open Advanced block offers stops")
		section.set_advanced_open(false)


func test_a_client_card_still_has_stops_to_read_the_settings() -> void:
	var card: LobbySettingsCard = _make_card(false)
	card.apply(MatchConfig.new())
	assert_false(card.focus_stops().is_empty())


# --- sections -----------------------------------------------------------------

func test_each_section_offers_a_reachable_stop() -> void:
	var card: LobbySettingsCard = _make_card(true)
	card.apply(MatchConfig.new())
	var sections: Array[UiSection] = card.sections()
	assert_false(sections.is_empty())
	var stops: Array[Control] = card.focus_stops()
	for section: UiSection in sections:
		var offered: bool = false
		for stop: Control in stops:
			offered = offered or section.is_ancestor_of(stop)
		assert_true(offered, "section %s offers at least one focus stop" % section.title)
