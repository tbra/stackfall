extends GutTest
## Bontago-d04: game/GiftCrate.gd's own claim-pop effect and not-claimable
## hint pulse (see config/GiftConfig.gd's "-- Claim feedback --"/
## "-- Not-claimable hint --" sections for the tunables these read).
##
## Same tiny-map fixture as tests/unit/test_gift_claim.gd.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
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
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
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
		Match._run_territory_step(step)


func _make_crate(gift_id: int, disk_point: Vector2, parent: Node3D) -> GiftCrate:
	var crate: GiftCrate = autofree(GiftCrate.new())
	parent.add_child(crate)
	crate.gift_id = gift_id
	crate.global_position = _field.world_from_disk_local(disk_point, GiftCrate.CRATE_SIZE.y * 0.5)
	return crate


func _make_local_ghost() -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	ghost.add_to_group(GhostPreview.LOCAL_HELD_GROUP)
	return ghost


# --- Claim pop ---------------------------------------------------------------

func test_a_claim_spawns_a_separate_pop_effect_node_and_marks_the_crate_claimed() -> void:
	_start_playing(_config())
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	var crate: GiftCrate = _make_crate(5, Match.slot(0).home_position, parent)

	Events.gift_claimed.emit(5, 0, MatchGifts.PENDING_SPECIAL_ID)

	var pop: Node = parent.get_node_or_null("GiftClaimPop")
	assert_not_null(pop, "a claim must spawn a separate pop effect node, not animate the doomed crate itself")
	assert_true(crate._claimed, "the crate must mark itself claimed once its own gift_id is claimed")


func test_pop_effect_frees_itself_after_its_own_configured_duration() -> void:
	_start_playing(_config())
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	var crate: GiftCrate = _make_crate(5, Match.slot(0).home_position, parent)

	Events.gift_claimed.emit(5, 0, MatchGifts.PENDING_SPECIAL_ID)
	var pop: Node = parent.get_node_or_null("GiftClaimPop")
	assert_not_null(pop, "fixture: the pop effect must exist right after the claim")

	var total: float = crate.gift_config.claim_pop_grow_duration_s + crate.gift_config.claim_pop_shrink_duration_s
	await get_tree().create_timer(total + 0.15).timeout

	assert_false(is_instance_valid(pop), "the pop effect must free itself once grow+shrink finishes")


func test_a_claim_for_a_different_gift_id_is_ignored() -> void:
	_start_playing(_config())
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	var crate: GiftCrate = _make_crate(5, Match.slot(0).home_position, parent)

	Events.gift_claimed.emit(999, 0, MatchGifts.PENDING_SPECIAL_ID)

	assert_null(parent.get_node_or_null("GiftClaimPop"), "a different crate's claim must not spawn a pop effect here")
	assert_false(crate._claimed, "a different crate's claim must not mark this one claimed")


# --- Not-claimable hint -------------------------------------------------------

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


func test_hint_resets_once_the_ghost_moves_away() -> void:
	_start_playing(_config())
	_step_territory()
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	var crate: GiftCrate = _make_crate(1, Vector2(19.0, 19.0), parent)
	var ghost: GhostPreview = _make_local_ghost()
	ghost.global_position = crate.global_position
	crate._process(0.05)
	assert_ne(crate._material.albedo_color, GiftCrate.UNCLAIMED_COLOR, "fixture: hint active while hovering")

	ghost.global_position = crate.global_position + Vector3(100.0, 0.0, 0.0)
	crate._process(0.05)

	assert_eq(
		crate._material.albedo_color, GiftCrate.UNCLAIMED_COLOR,
		"moving the ghost away must reset the flat colour"
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


func test_hint_does_not_trigger_with_no_local_ghost_held() -> void:
	_start_playing(_config())
	_step_territory()
	var parent: Node3D = autofree(Node3D.new())
	add_child_autofree(parent)
	var crate: GiftCrate = _make_crate(1, Vector2(19.0, 19.0), parent)

	crate._process(0.05)

	assert_eq(
		crate._material.albedo_color, GiftCrate.UNCLAIMED_COLOR,
		"no held ghost at all must never show the hint"
	)
