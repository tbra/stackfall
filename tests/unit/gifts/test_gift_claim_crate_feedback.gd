extends GutTest

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")

var _saved_async_min_circles: int = 0
var _saved_defer_max_s: float = 0.0
## game/gifts/GiftCrate.gd's own claim-pop effect and not-claimable
## hint pulse (see config/gifts/GiftConfig.gd's "-- Claim feedback --"/
## "-- Not-claimable hint --" sections for the tunables these read).
##
## Same tiny-map fixture as tests/unit/gifts/test_gift_claim.gd.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _saved_context: MatchContext = null


func before_each() -> void:
	# Match._process solves synchronously and without deferral under these knobs; after_each restores them.
	_saved_async_min_circles = _tuning.async_solve_min_circles
	_saved_defer_max_s = _tuning.solve_defer_max_s
	_tuning.async_solve_min_circles = 0
	_tuning.solve_defer_max_s = 0.0
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	_saved_context = MatchContext.installed()
	MatchContext.install(Match.context())


func after_each() -> void:
	_tuning.async_solve_min_circles = _saved_async_min_circles
	_tuning.solve_defer_max_s = _saved_defer_max_s
	MatchContext.current().local_held().clear()
	MatchContext.install(_saved_context)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.rng_seed = 4242
	return config


func _start_playing(config: MatchConfig) -> void:
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func _step_territory(times: int = 1) -> void:
	var step: float = 1.0 / _tuning.solve_hz
	for _i: int in range(times):
		Match._process(step)
		Match._gifts.tick_host(step)


func _make_crate(gift_id: int, disk_point: Vector2, parent: Node3D) -> GiftCrate:
	var crate: GiftCrate = autofree(GiftCrate.new())
	parent.add_child(crate)
	crate.gift_id = gift_id
	crate.global_position = _field.world_from_disk_local(disk_point, GiftCrate.CRATE_SIZE.y * 0.5)
	crate.set_falling(false)
	return crate


## Publishes the local held pose the way the player controller does each frame.
func _hold_cube_at(world_pos: Vector3) -> void:
	MatchContext.current().local_held().publish(
		Net.local_slot(), load("res://config/blocks/cube.tres") as BlockShape, world_pos,
		0, Quaternion.IDENTITY, true, 0.0
	)


# --- Claim pop ---------------------------------------------------------------

## a landing claimed the same tick frees the crate node at
## once, so its parachute is handed to the container and finishes collapsing.
func test_a_landing_claim_leaves_the_parachute_collapsing_in_the_container() -> void:
	_start_playing(_config())
	var home: Vector2 = Match.slot(0).home_position
	Match._gifts._spawn_crate_at(home)
	var fall_time: float = Match._gifts._gift_config.drop_height_m / Match._gifts._gift_config.fall_speed_m_s
	Match._gifts.tick_host(fall_time + 0.01)
	var chute: GiftParachute = Match._gifts._container.get_node_or_null("Parachute") as GiftParachute
	assert_not_null(chute, "the freed crate's canopy must survive its claim")
	assert_true(chute.is_active(), "still collapsing, not yet faded out")
	assert_true(chute.visible)
	chute.advance(Match._gifts._gift_config.chute_collapse_s + 0.1)
	assert_true(chute.is_queued_for_deletion(), "and free itself once it has faded")


func test_a_claim_spawns_a_separate_pop_effect_node_and_marks_the_crate_claimed() -> void:
	_start_playing(_config())
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	var crate: GiftCrate = _make_crate(5, Match.slot(0).home_position, parent)

	Events.gift_claimed.emit(5, 0, MatchGifts.PENDING_SPECIAL_ID)

	var pop: Node = parent.get_node_or_null("GiftClaimPop")
	assert_not_null(pop, "a claim must spawn a separate pop effect node, not animate the doomed crate itself")
	assert_true(crate._claimed, "the crate must mark itself claimed once its own gift_id is claimed")


func test_hint_pulses_when_the_local_ghost_hovers_an_unclaimable_crate() -> void:
	_start_playing(_config())
	_step_territory()
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	# Off every home flag and off-center (same off-territory position
	# test_gift_claim.gd's own life_s test uses) -- nobody's cell here.
	var crate: GiftCrate = _make_crate(1, Vector2(19.0, 19.0), parent)
	_hold_cube_at(crate.global_position)

	crate._process(0.05)

	assert_ne(
		crate._material.albedo_color, GiftCrate.UNCLAIMED_COLOR,
		"a hovered, unclaimable crate must not sit at its flat colour"
	)


func test_hint_does_not_trigger_over_a_crate_inside_the_local_players_own_territory() -> void:
	_start_playing(_config())
	_step_territory()
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	# Slot 0's own home flag: ground it already owns, uncontested.
	var crate: GiftCrate = _make_crate(1, Match.slot(0).home_position, parent)
	_hold_cube_at(crate.global_position)

	crate._process(0.05)

	assert_eq(
		crate._material.albedo_color, GiftCrate.UNCLAIMED_COLOR,
		"a crate the local player really can claim must not show the not-claimable hint"
	)


func _teams_2_config() -> MatchConfig:
	var config: MatchConfig = _config(4)
	config.team_mode = MatchConfig.TeamMode.TEAMS_2
	return config


func test_hint_does_not_trigger_over_a_teammates_territory_under_teams_2() -> void:
	# Regression for the bug this bead fixes: _crate_in_local_territory() used
	# to compare TerritoryRaster.team_at() (a TEAM id -- MatchTerritory.gd
	# seeds every home circle with slot.team_id) directly against the local
	# player's own SLOT id. Offline, the local player is always slot 0, so the
	# lobby's team picks give slot 0 team 1: slot id 0 and team id 1 then
	# differ, and the old comparison would show the hint over ground the
	# local team already owns.
	var config: MatchConfig = _teams_2_config()
	config.slot_team_ids = PackedInt32Array([1, 0, 0, 1])
	config.team_numbers = PackedInt32Array([1, 2])
	_start_playing(config)
	assert_eq(Net.local_slot(), 0, "fixture: offline, the local player is slot 0")
	assert_eq(Match.team_of(0), 1, "fixture: the local slot's team id must differ from its slot id")
	_step_territory()
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	# Slot 0's own home flag: team 1's ground, the local player's own team.
	# Slot 3 is also team 1 (team_of_slot(3) == 1), a real teammate.
	var crate: GiftCrate = _make_crate(1, Match.slot(0).home_position, parent)
	_hold_cube_at(crate.global_position)

	crate._process(0.05)

	assert_eq(
		crate._material.albedo_color, GiftCrate.UNCLAIMED_COLOR,
		"a crate over the local player's own team's territory must not show the not-claimable hint"
	)


func test_hint_does_not_pulse_when_nothing_is_held() -> void:
	_start_playing(_config())
	_step_territory()
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	var crate: GiftCrate = _make_crate(1, Vector2(19.0, 19.0), parent)
	MatchContext.current().local_held().publish(
		Net.local_slot(), null, crate.global_position, 0, Quaternion.IDENTITY, true, 0.0
	)

	crate._process(0.05)

	assert_eq(crate._material.albedo_color, GiftCrate.UNCLAIMED_COLOR, "no held shape: nobody to hint")


func test_hint_does_not_pulse_when_the_held_piece_is_far_from_the_crate() -> void:
	_start_playing(_config())
	_step_territory()
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	var crate: GiftCrate = _make_crate(1, Vector2(19.0, 19.0), parent)
	_hold_cube_at(_field.world_from_disk_local(Vector2(-19.0, -19.0), 0.0))

	crate._process(0.05)

	assert_eq(crate._material.albedo_color, GiftCrate.UNCLAIMED_COLOR, "a pose outside the hint radius must not pulse")
