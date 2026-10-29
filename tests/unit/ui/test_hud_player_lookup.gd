extends GutTest
## HudPlayerLookup answers "which team / colour / name / eliminated" for a slot or team from
## the match read port. Pure RefCounted logic: asserted through its public functions only.

const PALETTE: PackedColorArray = [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW]
const LIVE_COLOR: Color = Color(0.1, 0.2, 0.3)
const ROSTER_NAME: String = "Roster Rae"
const SLOT_COUNT: int = 4
## Resolved lobby teams: slots 0,1 are team 0 and slots 2,3 are team 1 (not the interleave).
const RESOLVED_SLOT_TEAMS: PackedInt32Array = [0, 0, 1, 1]
const RESOLVED_TEAM_NUMBERS: PackedInt32Array = [2, 4]

var _roster: Dictionary = {}


func before_each() -> void:
	_roster = {}


func _roster_name(slot_id: int) -> String:
	return String(_roster.get(slot_id, ""))


func _make(context: MatchContext) -> HudPlayerLookup:
	return HudPlayerLookup.new(context, PALETTE, _roster_name)


func _config(team_mode: MatchConfig.TeamMode = MatchConfig.TeamMode.OFF, resolved: bool = false) -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.player_count = SLOT_COUNT
	config.team_mode = team_mode
	if resolved:
		config.slot_team_ids = RESOLVED_SLOT_TEAMS
		config.team_numbers = RESOLVED_TEAM_NUMBERS
	return config


func _fake(config: MatchConfig) -> FakeMatchContext:
	var fake: FakeMatchContext = FakeMatchContext.new()
	fake.config_value = config
	return fake


func _seat(fake: FakeMatchContext, slot_id: int, display_name: String = "", is_bot: bool = false, alive: bool = true) -> PlayerSlot:
	var slot: PlayerSlot = PlayerSlot.new(slot_id, slot_id, display_name, LIVE_COLOR)
	slot.is_bot = is_bot
	slot.home_flag_alive = alive
	fake.slot_by_id[slot_id] = slot
	return slot


# --- team / resolved numbers ---------------------------------------------------------

func test_no_match_means_every_slot_is_its_own_team() -> void:
	var lookup: HudPlayerLookup = _make(MatchContext.new())
	assert_eq(lookup.team_of_slot(2), 2)
	assert_eq(lookup.team_of_slot(0), 0)
	assert_eq(lookup.resolved_team_numbers(), PackedInt32Array())


func test_free_for_all_team_is_the_slot() -> void:
	var lookup: HudPlayerLookup = _make(_fake(_config()))
	for slot_id: int in range(SLOT_COUNT):
		assert_eq(lookup.team_of_slot(slot_id), slot_id)


func test_unresolved_team_mode_interleaves() -> void:
	var lookup: HudPlayerLookup = _make(_fake(_config(MatchConfig.TeamMode.TEAMS_2)))
	assert_eq(lookup.team_of_slot(0), 0)
	assert_eq(lookup.team_of_slot(1), 1)
	assert_eq(lookup.team_of_slot(2), 0)
	assert_eq(lookup.team_of_slot(3), 1)
	assert_eq(lookup.resolved_team_numbers(), PackedInt32Array(), "unresolved teams report no numbers")


func test_resolved_teams_use_the_lobby_picks() -> void:
	var lookup: HudPlayerLookup = _make(_fake(_config(MatchConfig.TeamMode.TEAMS_2, true)))
	assert_eq(lookup.team_of_slot(1), 0)
	assert_eq(lookup.team_of_slot(2), 1)
	assert_eq(lookup.resolved_team_numbers(), RESOLVED_TEAM_NUMBERS)


# --- colour --------------------------------------------------------------------------

func test_slot_colour_prefers_the_live_slot() -> void:
	var fake: FakeMatchContext = _fake(_config())
	_seat(fake, 1)
	var lookup: HudPlayerLookup = _make(fake)
	assert_eq(lookup.color_for_slot(1), LIVE_COLOR)


func test_slot_colour_falls_back_to_the_palette_then_white() -> void:
	var lookup: HudPlayerLookup = _make(_fake(_config()))
	assert_eq(lookup.color_for_slot(2), PALETTE[2])
	assert_eq(lookup.color_for_slot(PALETTE.size() + 3), Color.WHITE, "outside the palette")
	assert_eq(lookup.color_for_slot(-1), Color.WHITE)


func test_team_colour_is_the_slot_colour_without_resolved_teams() -> void:
	var lookup: HudPlayerLookup = _make(_fake(_config()))
	assert_eq(lookup.color_for_team(1), PALETTE[1])
	assert_eq(_make(MatchContext.new()).color_for_team(3), PALETTE[3])


func test_resolved_team_colour_is_its_lowest_slots_territory_colour() -> void:
	var config: MatchConfig = _config(MatchConfig.TeamMode.TEAMS_2, true)
	config.player_colors = PALETTE
	var lookup: HudPlayerLookup = _make(_fake(config))
	assert_eq(lookup.color_for_team(0), PALETTE[0])
	assert_eq(lookup.color_for_team(1), PALETTE[2], "team 1 starts at slot 2")


# --- elimination -----------------------------------------------------------------------

func test_slot_is_eliminated_once_its_home_flag_is_gone() -> void:
	var fake: FakeMatchContext = _fake(_config())
	_seat(fake, 0)
	_seat(fake, 1, "", false, false)
	var lookup: HudPlayerLookup = _make(fake)
	assert_false(lookup.is_slot_eliminated(0))
	assert_true(lookup.is_slot_eliminated(1))
	assert_false(lookup.is_slot_eliminated(3), "a slot nobody sits in is not eliminated")


func test_nothing_is_eliminated_without_a_match() -> void:
	var fake: FakeMatchContext = _fake(_config())
	_seat(fake, 0, "", false, false)
	var lookup: HudPlayerLookup = _make(fake)
	assert_true(lookup.is_slot_eliminated(0), "fixture: the slot is out")
	lookup.context = MatchContext.new()
	assert_false(lookup.is_slot_eliminated(0))
	assert_false(lookup.is_team_eliminated(0))


func test_team_elimination_without_resolved_teams_is_the_slot() -> void:
	var fake: FakeMatchContext = _fake(_config())
	_seat(fake, 0)
	_seat(fake, 1, "", false, false)
	var lookup: HudPlayerLookup = _make(fake)
	assert_false(lookup.is_team_eliminated(0))
	assert_true(lookup.is_team_eliminated(1))


func test_resolved_team_is_out_only_when_every_member_is_out() -> void:
	var fake: FakeMatchContext = _fake(_config(MatchConfig.TeamMode.TEAMS_2, true))
	_seat(fake, 0, "", false, false)
	_seat(fake, 1)
	_seat(fake, 2, "", false, false)
	_seat(fake, 3, "", false, false)
	var lookup: HudPlayerLookup = _make(fake)
	assert_false(lookup.is_team_eliminated(0), "slot 1 still has its flag")
	assert_true(lookup.is_team_eliminated(1))
	fake.slot_by_id[1].home_flag_alive = false
	assert_true(lookup.is_team_eliminated(0), "last member out")


func test_resolved_team_with_no_members_is_not_eliminated() -> void:
	var fake: FakeMatchContext = _fake(_config(MatchConfig.TeamMode.TEAMS_2, true))
	_seat(fake, 2, "", false, false)
	_seat(fake, 3, "", false, false)
	var lookup: HudPlayerLookup = _make(fake)
	assert_true(lookup.is_team_eliminated(1), "fixture: a real team is out")
	assert_false(lookup.is_team_eliminated(7))


# --- names -------------------------------------------------------------------------------

func test_name_falls_back_to_player_number() -> void:
	var lookup: HudPlayerLookup = _make(MatchContext.new())
	assert_eq(lookup.name_for_slot(0), PlayerNames.fallback_for_slot(0))
	assert_eq(lookup.name_for_slot(2), "Player 3")


func test_name_uses_the_slot_label_when_the_roster_is_silent() -> void:
	var fake: FakeMatchContext = _fake(_config())
	_seat(fake, 1, "Slotty")
	assert_eq(_make(fake).name_for_slot(1), "Slotty")


func test_human_roster_name_beats_the_slot_label() -> void:
	var fake: FakeMatchContext = _fake(_config())
	_seat(fake, 1, "Slotty")
	_roster[1] = ROSTER_NAME
	assert_eq(_make(fake).name_for_slot(1), ROSTER_NAME)


func test_roster_name_without_a_slot_still_shows() -> void:
	_roster[0] = ROSTER_NAME
	assert_eq(_make(MatchContext.new()).name_for_slot(0), ROSTER_NAME)


func test_bot_keeps_its_own_label() -> void:
	var fake: FakeMatchContext = _fake(_config())
	_seat(fake, 1, "Botty", true)
	_roster[1] = ROSTER_NAME
	assert_eq(_make(fake).name_for_slot(1), "Botty")


func test_team_name_without_config_is_the_slot_name() -> void:
	_roster[1] = ROSTER_NAME
	assert_eq(_make(MatchContext.new()).name_for_team(1), ROSTER_NAME)


func test_free_for_all_team_name_is_the_slot_name() -> void:
	var fake: FakeMatchContext = _fake(_config())
	_seat(fake, 2, "Slotty")
	assert_eq(_make(fake).name_for_team(2), "Slotty")


func test_team_name_joins_every_member_with_ampersand() -> void:
	var fake: FakeMatchContext = _fake(_config(MatchConfig.TeamMode.TEAMS_2, true))
	for slot_id: int in range(SLOT_COUNT):
		_seat(fake, slot_id, "P%d" % slot_id)
	var lookup: HudPlayerLookup = _make(fake)
	assert_eq(lookup.name_for_team(0), "P0 & P1")
	assert_eq(lookup.name_for_team(1), "P2 & P3")


# --- the context is swappable -----------------------------------------------------------

func test_reassigning_context_changes_the_answers() -> void:
	var lookup: HudPlayerLookup = _make(MatchContext.new())
	assert_eq(lookup.team_of_slot(1), 1)
	lookup.context = _fake(_config(MatchConfig.TeamMode.TEAMS_2, true))
	assert_eq(lookup.team_of_slot(1), 0)
	assert_eq(lookup.resolved_team_numbers(), RESOLVED_TEAM_NUMBERS)
