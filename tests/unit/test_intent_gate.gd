extends GutTest
## Bontago-fca.36.2: pins the host-side guard preamble of every authoritative
## intent entry point (request_place manual + auto-drop, request_throw,
## request_use_gift_slot, spawn_special_projectile) across match states and
## the main guard cases. Written against the pre-refactor code and kept green
## across the MatchPlacement._intent_gate() extraction: each entry point must
## keep its accept/refuse behaviour and refusal reason.

const FakeNet: GDScript = preload("res://tests/unit/support/FakeNet.gd")

const OK: String = "ok"
const REFUSED_FALSE: String = "false"
const REFUSED_NULL: String = "null"

enum Entry { PLACE, AUTO_DROP, THROW, GIFT_USE, PROJECTILE }

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
	Match.set_net_provider(null)
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _start_playing() -> void:
	var qol: QolExperiments = QolExperiments.new()
	qol.gift_slot_enabled = true
	qol.gift_slot_capacity = 1
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 13579
	config.qol = qol
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	assert_eq(Match.state(), Match.State.PLAYING)


func _home(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


## Gives `slot_id` a held special (throw baseline), as test_match_throw does.
func _hold_special(slot_id: int) -> void:
	Match._gifts._ensure_capacity(slot_id)
	Match._gifts._held_specials[slot_id] = &"test_special"
	Match._feed._held_is_gift[slot_id] = true


## Runs one entry point for `slot_id` and returns OK / the refusal reason / a
## bool-or-null refusal tag, so one expectation table covers every return type.
func _call(entry: Entry, slot_id: int, feed_seq: int = -1, origin_override: Variant = null, velocity: Vector3 = Vector3.RIGHT) -> String:
	var origin: Vector3 = _home(0) if origin_override == null else origin_override as Vector3
	match entry:
		Entry.PLACE, Entry.AUTO_DROP:
			var reason: StringName = Match.request_place(
				slot_id, origin, 0, Quaternion.IDENTITY, entry == Entry.AUTO_DROP, feed_seq
			)
			return OK if reason == PlacementRules.REASON_OK else String(reason)
		Entry.THROW:
			var reason: StringName = Match.request_throw(
				slot_id, origin, 0, Quaternion.IDENTITY, velocity, feed_seq
			)
			return OK if reason == PlacementRules.REASON_OK else String(reason)
		Entry.GIFT_USE:
			return OK if Match.request_use_gift_slot(slot_id) else REFUSED_FALSE
		Entry.PROJECTILE:
			var shape: BlockShape = Match.held_shape(0) if slot_id >= 0 else null
			var block: Block = Match._placement.spawn_special_projectile(
				shape, origin, Basis.IDENTITY, 0, Vector3.ZERO, null, Match._placement._special_tuning
			)
			return OK if block != null else REFUSED_NULL
	return "unreachable"


func _prepare(entry: Entry) -> void:
	match entry:
		Entry.THROW:
			_hold_special(0)
		Entry.GIFT_USE:
			Match._gifts._store_in_gift_slot(0, &"anvil")


func _refusal_for(entry: Entry) -> String:
	match entry:
		Entry.GIFT_USE:
			return REFUSED_FALSE
		Entry.PROJECTILE:
			return REFUSED_NULL
	return String(PlacementRules.REASON_NO_BLOCK)


func _name(entry: Entry) -> String:
	return Entry.keys()[entry]


# --- Baseline: every entry point accepts a valid live intent -------------------

func test_every_entry_accepts_in_live_states() -> void:
	for state: int in [Match.State.PLAYING, Match.State.SUDDEN_DEATH]:
		for entry: Entry in Entry.values():
			_start_playing()
			_prepare(entry)
			Match._lifecycle._state = state
			assert_eq(_call(entry, 0), OK, "%s accepts in state %d" % [_name(entry), state])
			Match.abort_match()
			for child: Node in _blocks_root.get_children():
				child.free()


func test_every_entry_refuses_in_non_live_states() -> void:
	for state: int in [Match.State.LOBBY, Match.State.LOADING, Match.State.COUNTDOWN, Match.State.END]:
		for entry: Entry in Entry.values():
			_start_playing()
			_prepare(entry)
			Match._lifecycle._state = state
			assert_eq(_call(entry, 0), _refusal_for(entry), "%s refuses in state %d" % [_name(entry), state])
			Match.abort_match()
			for child: Node in _blocks_root.get_children():
				child.free()


# --- Guard table (PLAYING) -----------------------------------------------------

func test_not_host_refuses_everything() -> void:
	for entry: Entry in Entry.values():
		_start_playing()
		_prepare(entry)
		Match.set_net_provider(FakeNet.client(0))
		assert_eq(_call(entry, 0), _refusal_for(entry), "%s refuses off-host" % _name(entry))
		Match.set_net_provider(null)
		Match.abort_match()
		for child: Node in _blocks_root.get_children():
			child.free()


func test_slot_out_of_range_refused() -> void:
	for entry: Entry in [Entry.PLACE, Entry.AUTO_DROP, Entry.THROW, Entry.GIFT_USE]:
		for bad: int in [-1, 2, 99]:
			_start_playing()
			_prepare(entry)
			assert_eq(_call(entry, bad), _refusal_for(entry), "%s slot %d" % [_name(entry), bad])
			Match.abort_match()


func test_stale_feed_seq_refused_current_accepted_and_negative_sentinel_skips() -> void:
	for entry: Entry in [Entry.PLACE, Entry.AUTO_DROP, Entry.THROW]:
		_start_playing()
		_prepare(entry)
		var seq: int = Match.feed_seq(0)
		assert_eq(_call(entry, 0, seq + 1), String(PlacementRules.REASON_NO_BLOCK), "%s stale seq" % _name(entry))
		assert_eq(_call(entry, 0, seq), OK, "%s current seq" % _name(entry))
		Match.abort_match()
		for child: Node in _blocks_root.get_children():
			child.free()


func test_dead_home_flag_refused_with_no_block() -> void:
	for entry: Entry in [Entry.PLACE, Entry.AUTO_DROP, Entry.THROW, Entry.GIFT_USE]:
		_start_playing()
		_prepare(entry)
		Match.slot(0).home_flag_alive = false
		assert_eq(_call(entry, 0), _refusal_for(entry), "%s dead home" % _name(entry))
		Match.abort_match()


func test_turn_gate_reason_and_ordering_against_dead_home() -> void:
	for entry: Entry in [Entry.PLACE, Entry.AUTO_DROP, Entry.THROW, Entry.GIFT_USE]:
		_start_playing()
		_prepare(entry)
		Match.config.turn_based = true
		var off_turn: int = 1 - Match.active_slot()
		# Slot 0 is the only slot the baseline prepares; flip which one acts.
		Match.config.turn_based = true
		Match._lifecycle._active_slot = off_turn
		var expected: String = REFUSED_FALSE if entry == Entry.GIFT_USE else String(PlacementRules.REASON_NOT_YOUR_TURN)
		assert_eq(_call(entry, 0), expected, "%s off-turn" % _name(entry))
		# Dead home outranks the turn gate for place/throw (NO_BLOCK, not NOT_YOUR_TURN).
		Match.slot(0).home_flag_alive = false
		assert_eq(_call(entry, 0), _refusal_for(entry), "%s dead home outranks turn gate" % _name(entry))
		Match.slot(0).home_flag_alive = true
		Match._lifecycle._active_slot = 0
		if entry != Entry.GIFT_USE:
			assert_eq(_call(entry, 0), OK, "%s on-turn accepted" % _name(entry))
		Match.abort_match()
		for child: Node in _blocks_root.get_children():
			child.free()


func test_release_lock_manual_refused_auto_drop_exempt_gift_use_unaffected() -> void:
	var no_block: String = String(PlacementRules.REASON_NO_BLOCK)
	_start_playing()
	Match._feed._release_locked[0] = true
	assert_eq(_call(Entry.PLACE, 0), no_block, "manual place locked")
	assert_eq(_call(Entry.AUTO_DROP, 0), OK, "auto-drop exempt")
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()

	_start_playing()
	_hold_special(0)
	Match._feed._release_locked[0] = true
	# A held gift is never "locked" (MatchFeed.is_release_locked); pin that too.
	assert_eq(Match.is_release_locked(0), false)
	Match._feed._held_is_gift[0] = false
	assert_eq(_call(Entry.THROW, 0), no_block, "throw locked is unconditional")
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()

	_start_playing()
	_prepare(Entry.GIFT_USE)
	Match._feed._release_locked[0] = true
	assert_eq(_call(Entry.GIFT_USE, 0), OK, "gift use ignores the release lock")


func test_malformed_pose_refused() -> void:
	var no_block: String = String(PlacementRules.REASON_NO_BLOCK)
	for entry: Entry in [Entry.PLACE, Entry.AUTO_DROP, Entry.THROW]:
		_start_playing()
		_prepare(entry)
		var bad_origin: Vector3 = Vector3(NAN, 0.0, 0.0)
		assert_eq(_call(entry, 0, -1, bad_origin), no_block, "%s NaN origin" % _name(entry))
		Match.abort_match()
	_start_playing()
	_prepare(Entry.THROW)
	assert_eq(_call(Entry.THROW, 0, -1, null, Vector3(INF, 0.0, 0.0)), no_block, "throw non-finite velocity")


func test_throw_kind_specific_refusals_follow_the_gate() -> void:
	_start_playing()
	assert_eq(_call(Entry.THROW, 0), String(ThrowRules.REASON_NOT_A_SPECIAL), "no held special")
	_hold_special(0)
	assert_eq(_call(Entry.THROW, 0, -1, null, Vector3.ZERO), String(PlacementRules.REASON_NO_BLOCK), "zero aim refused")


func test_gift_use_kind_specific_refusals() -> void:
	_start_playing()
	assert_eq(_call(Entry.GIFT_USE, 0), REFUSED_FALSE, "empty slot")
	Match.abort_match()
	_start_playing()
	_prepare(Entry.GIFT_USE)
	_hold_special(0)
	assert_eq(_call(Entry.GIFT_USE, 0), REFUSED_FALSE, "gift already held")


func test_projectile_null_shape_and_missing_world_refused() -> void:
	_start_playing()
	var tuning: SpecialTuning = Match._placement._special_tuning
	assert_null(Match._placement.spawn_special_projectile(null, _home(0), Basis.IDENTITY, 0, Vector3.ZERO, null, tuning))
	var field_before: Field = Match._field
	Match._field = null
	assert_null(Match._placement.spawn_special_projectile(Match.held_shape(0), _home(0), Basis.IDENTITY, 0, Vector3.ZERO, null, tuning))
	Match._field = field_before


# --- Order-sensitive pairs: two guards fail at once, the reason pins the order ---

func _off_turn_setup(entry: Entry) -> void:
	_start_playing()
	_prepare(entry)
	Match.config.turn_based = true
	Match._lifecycle._active_slot = 1


func test_off_turn_outranks_release_lock() -> void:
	var not_your_turn: String = String(PlacementRules.REASON_NOT_YOUR_TURN)
	for entry: Entry in [Entry.PLACE, Entry.THROW]:
		_off_turn_setup(entry)
		Match._feed._release_locked[0] = true
		Match._feed._held_is_gift[0] = false
		assert_eq(_call(entry, 0), not_your_turn, "%s off-turn + locked" % _name(entry))
		Match.abort_match()
		for child: Node in _blocks_root.get_children():
			child.free()


func test_off_turn_outranks_missing_held_shape() -> void:
	var not_your_turn: String = String(PlacementRules.REASON_NOT_YOUR_TURN)
	for entry: Entry in [Entry.PLACE, Entry.AUTO_DROP, Entry.THROW]:
		_off_turn_setup(entry)
		Match._feed._held_shapes[0] = null
		assert_eq(_call(entry, 0), not_your_turn, "%s off-turn + no shape" % _name(entry))
		Match._lifecycle._active_slot = 0
		assert_eq(_call(entry, 0), String(PlacementRules.REASON_NO_BLOCK), "%s on-turn + no shape" % _name(entry))
		Match.abort_match()


func test_stale_feed_seq_outranks_turn_gate() -> void:
	for entry: Entry in [Entry.PLACE, Entry.AUTO_DROP, Entry.THROW]:
		_off_turn_setup(entry)
		assert_eq(
			_call(entry, 0, Match.feed_seq(0) + 1), String(PlacementRules.REASON_NO_BLOCK),
			"%s stale seq + off-turn" % _name(entry)
		)
		Match.abort_match()


func test_hot_seat_off_turn_reasons_and_dead_home_ordering() -> void:
	var not_your_turn: String = String(PlacementRules.REASON_NOT_YOUR_TURN)
	for entry: Entry in [Entry.PLACE, Entry.AUTO_DROP, Entry.THROW]:
		_start_playing()
		_prepare(entry)
		Match.config.hot_seat = true
		Match._lifecycle._active_slot = 1
		assert_eq(_call(entry, 0), not_your_turn, "%s hot-seat off-turn" % _name(entry))
		Match._feed._release_locked[0] = true
		Match._feed._held_is_gift[0] = false
		assert_eq(_call(entry, 0), not_your_turn, "%s hot-seat off-turn + locked" % _name(entry))
		Match.abort_match()
		for child: Node in _blocks_root.get_children():
			child.free()
