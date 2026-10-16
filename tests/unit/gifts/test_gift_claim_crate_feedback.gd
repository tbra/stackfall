extends GutTest
## game/gifts/GiftCrate.gd's own claim-pop effect and not-claimable
## hint pulse (see config/gifts/GiftConfig.gd's "-- Claim feedback --"/
## "-- Not-claimable hint --" sections for the tunables these read).
##
## Same tiny-map fixture as tests/unit/gifts/test_gift_claim.gd.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
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


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.rng_seed = 4242
	return config


func _start_playing(config: MatchConfig) -> void:
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func _step_territory(times: int = 1) -> void:
	var step: float = 1.0 / Match._territory_tuning.solve_hz
	for _i: int in range(times):
		Match._territory._run_territory_step(step)
		Match._gifts.tick_host(step)


func _make_crate(gift_id: int, disk_point: Vector2, parent: Node3D) -> GiftCrate:
	var crate: GiftCrate = autofree(GiftCrate.new())
	parent.add_child(crate)
	crate.gift_id = gift_id
	crate.global_position = _field.world_from_disk_local(disk_point, GiftCrate.CRATE_SIZE.y * 0.5)
	crate.set_falling(false)
	return crate


func _make_local_ghost() -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	ghost.add_to_group(GhostPreview.LOCAL_HELD_GROUP)
	return ghost


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
	assert_eq(chute.phase(), ParachuteAnim.Phase.COLLAPSING)
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
	var ghost: GhostPreview = _make_local_ghost()
	ghost.global_position = crate.global_position

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
	var ghost: GhostPreview = _make_local_ghost()
	ghost.global_position = crate.global_position

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
	# player's own SLOT id. A local player on a real team whose slot id
	# differs from its team id (slot 2, team 0 here) would then see the
	# not-claimable hint over ground its own team already owns.
	var config: MatchConfig = _teams_2_config()
	config.hot_seat = true
	_start_playing(config)
	Match.advance_turn()
	Match.advance_turn()
	assert_eq(Match.active_slot(), 2, "fixture: hot-seat's local watch slot must now be slot 2")
	_step_territory()
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	# Slot 0's own home flag: team 0's ground (team_of_slot(0) == 0), and
	# slot 2 is also team 0 (team_of_slot(2) == 0 under TEAMS_2).
	var crate: GiftCrate = _make_crate(1, Match.slot(0).home_position, parent)
	var ghost: GhostPreview = _make_local_ghost()
	ghost.global_position = crate.global_position

	crate._process(0.05)

	assert_eq(
		crate._material.albedo_color, GiftCrate.UNCLAIMED_COLOR,
		"a crate over the local player's own team's territory must not show the not-claimable hint"
	)
