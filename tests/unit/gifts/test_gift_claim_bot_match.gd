extends GutTest
## (P2 bug report: "I grabbed a yellow cube but nothing seemed to
## happen", windowed `godot --path . -- --headless-host --bots=3 --players=4`,
## human is slot 0).
##
## Verifies MatchGifts.claim_or_expire_gifts() end to end through a
## MatchConfig built the way game/main/Main.gd's `--headless-host --bots=<n>`
## entry point builds it (_bot_match_config() below mirrors its
## _build_headless_bot_config()). The tiny-map override (TinyMapMatchConfig,
## the same seam test_gift_claim.gd's own _config() uses) is the one addition
## Main.gd's real builder does not make -- needed here only so the territory
## solve is fast and deterministic in a unit test, per this project's existing
## test-fixture convention.
##
## Two things fall out of this:
## 1. The claim path is not broken: a crate landing inside slot 0's own
##    territory in a bot-hosted match is claimed and fires Events.gift_claimed
##    (test_crate_inside_the_human_slots_territory_is_claimed_in_a_bot_hosted_match).
## 2. Spec 1.6's claim rule really is territory-only [ORIGINAL]: a crate that
##    is not inside anyone's territory is not claimed just because it exists
##    on the field (test_crate_outside_every_slots_territory_is_not_claimed_
##    in_a_bot_hosted_match) -- "nothing happened" for that crate is the
##    documented design, not a bug.
##
## Root cause of the report: the claim mechanics above were already correct;
## a successful claim simply had no visible feedback at all (the claimed
## crate's node was queue_free()d the same frame with no animation, and the
## HUD only silently refreshed a small text counter). game/gifts/GiftCrate.gd's and
## ui/hud/HUD.gd's own changes address that half; this file only
## re-confirms the claim mechanics themselves are sound end to end through
## the exact config shape the bug was reported against.

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
	Match._gifts._gift_config = load("res://config/gifts/gift_config.tres") as GiftConfig
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


## Mirrors game/main/Main.gd's _build_headless_bot_config(): duplicate, ai_count
## set, player_count = maxi(bots, players), hot_seat/sandbox forced false --
## plus the tiny-map swap (see class doc above) applied first, exactly the
## order TinyMapMatchConfig's own doc comment requires (set_script() resets
## every one of MatchConfig's own @export fields to their script defaults, so
## anything meaningful must be set after the swap, not before it).
func _bot_match_config(bots: int = 3, players: int = 4) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.ai_count = bots
	config.player_count = maxi(bots, players)
	config.hot_seat = false
	config.sandbox = false
	config.rng_seed = 4242
	# gifts_enabled deliberately NOT set here: it comes from match_defaults.tres,
	# exactly as game/main/Main.gd's _build_headless_bot_config() leaves it, so
	# the claim tests below run with the gifts setting a bot-hosted match has.
	return config


func _start_playing(config: MatchConfig) -> void:
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func _step_territory(times: int = 1) -> void:
	var step: float = 1.0 / Match._territory_tuning.solve_hz
	for _i: int in range(times):
		Match._run_territory_step(step)


## Same direct-injection seam test_gift_claim.gd's own _inject_crate() uses
## (a real crate node is not needed to exercise claim_or_expire_gifts() --
## only its {"position", "age", "node"} entry in MatchGifts._crates).
func _inject_crate(position: Vector2) -> int:
	var gift_id: int = Match._gifts._next_gift_id
	Match._gifts._next_gift_id += 1
	Match._gifts._crates[gift_id] = {"position": position, "age": 0.0, "node": null}
	return gift_id


func test_crate_inside_the_human_slots_territory_is_claimed_in_a_bot_hosted_match() -> void:
	_start_playing(_bot_match_config())
	# Slot 0 is the human, per the owner's own bug report ("human is slot 0");
	# its home flag is ground it already owns uncontested -- the same fixture
	# test_gift_claim.gd's own
	# test_crate_on_owned_uncontested_cell_is_claimed_and_grants_special uses.
	var home: Vector2 = Match.slot(0).home_position
	var gift_id: int = _inject_crate(home)
	watch_signals(Events)

	_step_territory()

	assert_false(Match._gifts._crates.has(gift_id), "a crate inside slot 0's own territory must be claimed")
	assert_signal_emitted(Events, "gift_claimed")
	assert_eq(Match.pending_special_count(0), 1)


func test_crate_outside_every_slots_territory_is_not_claimed_in_a_bot_hosted_match() -> void:
	_start_playing(_bot_match_config())
	# Off every home flag and off-center (the same off-territory position
	# test_gift_claim.gd's own test_crate_expires_after_life_s_without_being_
	# claimed uses) -- nobody's raster cell claims it, so "driving a held
	# block/ghost over this crate" does nothing, by spec 1.6's own claim rule
	# [ORIGINAL], not because anything is broken.
	var gift_id: int = _inject_crate(Vector2(19.0, 19.0))
	watch_signals(Events)

	_step_territory()

	assert_true(Match._gifts._crates.has(gift_id), "a crate outside every slot's territory must not be claimed")
	assert_signal_not_emitted(Events, "gift_claimed")
