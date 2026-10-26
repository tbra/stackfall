extends Node
## P6 parity recipe: a scripted, tick-indexed run of the special-effect and gift-crate stack in a real
## hosted Main + Match whose recorded state must not change across the P6 refactor. Public API only
## (Match.spawn_special_projectile, request_place, submit_cursor, grant/consume_glue_drop, GlueFusion.fuse,
## the effects' set_launch_direction); one scripted step per physics tick; no ENet peer.
##
## Part A (effect state): a Rocket and a Paintball aimed along a fixed direction, a chaining Bomb pair, a
## Freeze beside plain blocks, a glue-fused pair with glue charges, a Black hole, a Magnet, an Anvil, an
## Earthquake and a Propeller, each dropped at a fixed tick.
## Part R (random effects): a Volcano and a Jumping Bean. Their game code draws from an unseeded
## RandomNumberGenerator, so this part is not reproducible tick for tick; it has its own floor.
## Part B (crate lifecycle): special frequency at its maximum and a block placed every PLACE_SPACING ticks, so
## each feed window rolls a seeded crate spawn; the second crate is air-touched by a cursor posted at its
## position, later crates land (a claim when the point is in a team's territory) or expire and relocate.
##
## Record a run (the committed reference comes from an unmodified main):
##   godot --headless --fixed-fps 60 --path . res://tests/bench/bench_p6_parity.tscn -- --out=run.json [--rng-seed=N] [--part=a|r|b]
## With no --part the scene runs each part in its own child process (a match cannot be restarted cleanly in
## one process, and a Volcano or the elimination rules can end it) and merges them under the keys "a.", "r." and "b.".
## Compare two recordings (exit 1 on any difference above --tol, default 0):
##   godot --headless --path . res://tests/bench/bench_p6_parity.tscn -- --compare=a.json,b.json [--tol=0.0001]
## Run it with APPDATA pointed at an empty folder so the user's settings.cfg cannot reach the run.
##
## Determinism rules: wall-clock fields are never recorded; ticks are counted from the first PLAYING tick;
## weather is off; no bot seat; the feed timer is off so only the scripted placements issue blocks.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const CUBE_PATH: String = "res://config/blocks/cube.tres"
const MAP_PATH: String = "res://config/match/maps/round.tres"
const DEFAULTS_PATH: String = "res://config/match/match_defaults.tres"
const GLUE_TUNING: GlueDropTuning = preload("res://config/gifts/glue_drop_tuning.tres")
const GIFT_CONFIG: GiftConfig = preload("res://config/gifts/gift_config.tres")
const PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
const OUT_ARG: String = "--out="
const COMPARE_ARG: String = "--compare="
const TOL_ARG: String = "--tol="
const SEED_ARG: String = "--rng-seed="
const PART_ARG: String = "--part="
const PART_ALL: String = "all"
const PARTS: PackedStringArray = ["a", "r", "b"]
const PART_FILE: String = "user://bench_p6_parity_%s.json"
const DEFAULT_SEED: int = 20261026
const HOST_SLOT: int = 0
const OTHER_SLOT: int = 1
const PLAYER_COUNT: int = 2
const FIELD_RADIUS_M: float = 20.0
const MAX_LOAD_TICKS: int = 3000
const ROUND_STEP: float = 0.0001
const RECORD_EVERY: int = 30
const DROP_HEIGHT_M: float = 0.6
const ANVIL_HEIGHT_M: float = 5.0
const PAIR_GAP_M: float = 1.0
const GLUE_GAP_M: float = 1.1
const SCATTER_RING_M: float = 1.6
const SCATTER_COUNT: int = 4

## Part A timeline, in ticks since PLAYING. Spots are disk-local metres.
const A_END_TICK: int = 1500
const R_END_TICK: int = 1500
const ROCKET_TICK: int = 30
const ROCKET_SPOT: Vector2 = Vector2(-8.0, -4.0)
const ROCKET_AIM: Vector3 = Vector3(1.0, -0.35, 0.25)
const BOMB_TICK: int = 60
const BOMB_SPOT: Vector2 = Vector2(6.0, 6.0)
const FREEZE_TICK: int = 90
const FREEZE_SPOT: Vector2 = Vector2(-6.0, 6.0)
const GLUE_DROP_TICK: int = 120
const GLUE_FUSE_TICK: int = 200
const GLUE_CONSUME_TICK: int = 230
const GLUE_SPOT: Vector2 = Vector2(4.0, -8.0)
const GLUE_CHARGES: int = 2
const BLACK_HOLE_TICK: int = 150
const BLACK_HOLE_SPOT: Vector2 = Vector2(0.0, 8.0)
const VOLCANO_TICK: int = 30
const VOLCANO_SPOT: Vector2 = Vector2(-9.0, 0.0)
const PAINTBALL_TICK: int = 210
const PAINTBALL_SPOT: Vector2 = Vector2(9.0, 2.0)
const PAINTBALL_AIM: Vector3 = Vector3(-0.6, -0.5, 0.3)
const MAGNET_TICK: int = 240
const MAGNET_SPOT: Vector2 = Vector2(9.0, -3.0)
const ANVIL_TICK: int = 270
const ANVIL_SPOT: Vector2 = Vector2(2.0, 2.0)
const BEAN_TICK: int = 30
const BEAN_SPOT: Vector2 = Vector2(-3.0, -8.0)
const QUAKE_TICK: int = 330
const QUAKE_SPOT: Vector2 = Vector2(0.0, -2.0)
const PROPELLER_TICK: int = 360
const PROPELLER_SPOT: Vector2 = Vector2(-4.0, 3.0)

## Part B timeline: placements start once the grace period before the first crate roll has passed.
const B_START_TICK: int = 1500
const B_END_TICK: int = 7500
const PLACE_SPACING: int = 40
const PLACE_COUNT: int = 80
const PLACE_INWARD_M: float = 2.0
const PLACE_COLUMNS: int = 3
const PLACE_LAYERS: int = 8
const PLACE_ROW_SPACING_M: float = 1.5
const PLACE_COLUMN_SPACING_M: float = 1.2
const PLACE_BASE_HEIGHT_M: float = 1.0
const PLACE_LAYER_STEP_M: float = 1.1
## The cursor follows the air-touch crate once it is within this distance (m) of its landing height.
## The crate (by spawn order) the cursor follows; the one before it is left to land and the ones after it to expire.
const AIR_TOUCH_GIFT_ID: int = 1
const CURSOR_PROCESS_PRIORITY: int = 1000
const AIR_TOUCH_RANGE_M: float = 3.0

var _out_path: String = ""
var _part: String = PART_ALL
var _record: Dictionary = {}
var _events: Array = []
var _tick: int = -1
var _main: Node = null
var _field: Field = null
var _registry: BlockRegistry = null
var _shape: BlockShape = null
var _load_ticks: int = 0
var _placed: int = 0
var _fuse_pair: Array[Block] = []
var _end_tick: int = 0
var _rng_seed: int = DEFAULT_SEED
var _counts: Dictionary = {}


func _ready() -> void:
	process_priority = CURSOR_PROCESS_PRIORITY
	var compare: String = ""
	var tol: float = 0.0
	var rng_seed: int = DEFAULT_SEED
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_ARG):
			_out_path = arg.substr(OUT_ARG.length())
		elif arg.begins_with(COMPARE_ARG):
			compare = arg.substr(COMPARE_ARG.length())
		elif arg.begins_with(TOL_ARG):
			tol = arg.substr(TOL_ARG.length()).to_float()
		elif arg.begins_with(SEED_ARG):
			rng_seed = arg.substr(SEED_ARG.length()).to_int()
		elif arg.begins_with(PART_ARG):
			_part = arg.substr(PART_ARG.length())
	if not compare.is_empty():
		get_tree().quit(_compare(compare, tol))
		set_physics_process(false)
		return
	if _part == PART_ALL:
		get_tree().quit(_run_parts(rng_seed))
		set_physics_process(false)
		return
	_end_tick = {"a": A_END_TICK, "r": R_END_TICK, "b": B_END_TICK}.get(_part, A_END_TICK)
	_rng_seed = rng_seed
	_build_world(rng_seed)
	Events.special_triggered.connect(_on_special_triggered)
	Events.gift_spawned.connect(_on_gift_spawned)
	Events.gift_flight_spawned.connect(_on_gift_flight_spawned)
	Events.gift_landed.connect(_on_gift_landed)
	Events.gift_claimed.connect(_on_gift_claimed)
	Events.gift_expired.connect(_on_gift_expired)
	Events.glue_charges_changed.connect(_on_glue_charges_changed)
	Events.block_frozen_changed.connect(_on_block_frozen_changed)
	Events.block_removed.connect(_on_block_removed)
	Events.bean_hopped.connect(_on_bean_hopped)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.match_won.connect(_on_match_won)
	Events.player_eliminated.connect(_on_player_eliminated)


## The hosted Main of bench_p3_parity on a small map, no bot seat, feed timer off. Gifts are on at the maximum
## frequency but not sandbox: the first-crate grace period and the territory claim rule are the shipped ones.
func _build_world(rng_seed: int) -> void:
	assert(Net.host_game(AgentProbe.free_udp_port(), "Hostie") == OK)
	_main = MAIN_SCENE.instantiate()
	var map: MapDef = (load(MAP_PATH) as MapDef).duplicate(true)
	map.field_radius = FIELD_RADIUS_M
	_field = _main.get_node("Field") as Field
	_field.map_def = map
	add_child(_main)
	_registry = _main.get_node("BlockRegistry") as BlockRegistry
	_shape = load(CUBE_PATH) as BlockShape
	var config: MatchConfig = (load(DEFAULTS_PATH) as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.rng_seed = rng_seed
	config.ai_count = 0
	config.player_count = PLAYER_COUNT
	config.sandbox = false
	config.scripted_gifts = true
	config.gifts_enabled = true
	config.special_frequency = MatchConfig.SPECIAL_FREQUENCY_MAX
	config.weather_mode = MatchConfig.WeatherMode.OFF
	config.countdown_seconds = 0.0
	var pinned: BlockFeedConfig = Match._block_feed_config.duplicate() as BlockFeedConfig
	pinned.shapes = [_shape]
	pinned.weight_overrides = PackedFloat32Array()
	Match._block_feed_config = pinned
	Match.register_world(_field, _registry, _main.get_node("BlocksContainer"))
	Match.start_match(config)
	Match.set_feed_timer_enabled(false)


## Runs each part in a child process of this same scene and merges the three recordings into one.
func _run_parts(rng_seed: int) -> int:
	var merged: Dictionary = {}
	for part: String in PARTS:
		var path: String = PART_FILE % part
		var args: PackedStringArray = [
			"--headless", "--fixed-fps", "60", "--path", ProjectSettings.globalize_path("res://"),
			"res://tests/bench/bench_p6_parity.tscn", "--", "--part=" + part, "--out=" + ProjectSettings.globalize_path(path),
			"--rng-seed=%d" % rng_seed,
		]
		var output: Array = []
		var code: int = OS.execute(OS.get_executable_path(), args, output, true)
		if code != 0:
			push_error("bench_p6_parity: part %s exited %d" % [part, code])
			return 1
		var recorded: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not recorded is Dictionary:
			push_error("bench_p6_parity: part %s left no recording" % part)
			return 1
		for key: String in (recorded as Dictionary).keys():
			merged["%s.%s" % [part, key]] = (recorded as Dictionary)[key]
	_record = merged
	return _write(PART_ALL, 0)


func _physics_process(_delta: float) -> void:
	if _tick < 0 and Match.state() != Match.State.PLAYING:
		_load_ticks += 1
		if _load_ticks > MAX_LOAD_TICKS:
			push_error("bench_p6_parity: world never reached PLAYING")
			get_tree().quit(1)
			set_physics_process(false)
		return
	if _tick < 0:
		seed(_rng_seed)
	_tick += 1
	match _part:
		"a":
			_script_effects()
		"r":
			_script_random_effects()
		"b":
			_script_crates()
	if _tick % RECORD_EVERY == 0:
		_sample()
	if _tick >= _end_tick:
		set_physics_process(false)
		_finish()


## Runs after every other node's _process (CURSOR_PROCESS_PRIORITY), so the host cursor this posts is the one
## the next physics tick reads, not the local ghost's own submit.
func _process(_delta: float) -> void:
	if _part == "b" and _tick >= B_START_TICK:
		_follow_air_touch_crate()


# --- part A: effect state -------------------------------------------------------------------

func _script_effects() -> void:
	match _tick:
		ROCKET_TICK:
			RocketEffect.set_launch_direction(_drop(&"rocket", ROCKET_SPOT, DROP_HEIGHT_M), ROCKET_AIM)
		BOMB_TICK:
			_drop(&"bomb", BOMB_SPOT, DROP_HEIGHT_M)
			_drop(&"bomb", BOMB_SPOT + Vector2(PAIR_GAP_M, 0.0), DROP_HEIGHT_M)
		FREEZE_TICK:
			_scatter(FREEZE_SPOT)
			_drop(&"freeze", FREEZE_SPOT, DROP_HEIGHT_M)
		GLUE_DROP_TICK:
			_fuse_pair.append(_drop(&"", GLUE_SPOT, DROP_HEIGHT_M))
			_fuse_pair.append(_drop(&"", GLUE_SPOT, DROP_HEIGHT_M + GLUE_GAP_M))
			Match.grant_glue_drops(HOST_SLOT, GLUE_CHARGES)
		GLUE_FUSE_TICK:
			if _fuse_pair.size() == 2:
				var fused: FusedBody = GlueFusion.fuse(_fuse_pair[1], _fuse_pair[0], GLUE_TUNING)
				_events.append("%d|glue_fused|%s" % [_tick, fused != null])
		GLUE_CONSUME_TICK:
			_events.append("%d|glue_consumed|%s" % [_tick, Match.consume_glue_drop(HOST_SLOT)])
		BLACK_HOLE_TICK:
			_scatter(BLACK_HOLE_SPOT)
			_drop(&"black_hole", BLACK_HOLE_SPOT, DROP_HEIGHT_M)
		PAINTBALL_TICK:
			PaintballEffect.set_launch_direction(_drop(&"paintball", PAINTBALL_SPOT, DROP_HEIGHT_M), PAINTBALL_AIM)
		MAGNET_TICK:
			_scatter(MAGNET_SPOT)
			_drop(&"magnet", MAGNET_SPOT, DROP_HEIGHT_M)
		ANVIL_TICK:
			_drop(&"anvil", ANVIL_SPOT, ANVIL_HEIGHT_M)
		QUAKE_TICK:
			_drop(&"earthquake", QUAKE_SPOT, DROP_HEIGHT_M)
		PROPELLER_TICK:
			_drop(&"propeller", PROPELLER_SPOT, DROP_HEIGHT_M)


## The specials whose game code draws from an unseeded RandomNumberGenerator (Volcano bursts, Jumping Bean
## hops), kept apart so part A stays exactly reproducible.
func _script_random_effects() -> void:
	match _tick:
		VOLCANO_TICK:
			_drop(&"volcano", VOLCANO_SPOT, DROP_HEIGHT_M)
		BEAN_TICK:
			_drop(&"jumping_bean", BEAN_SPOT, DROP_HEIGHT_M)


## A cube block at a disk-local spot, armed with special `def_id` (a plain block for &"").
func _drop(def_id: StringName, spot: Vector2, height: float) -> Block:
	var def: SpecialDef = SpecialDef.find_by_id(def_id)
	return Match.spawn_special_projectile(_shape, _field.world_from_disk_local(spot, height), Basis.IDENTITY, HOST_SLOT, Vector3.ZERO, def, null)


## A ring of plain blocks of the other slot around `centre`, the targets a Freeze, Magnet or Black hole acts on.
func _scatter(centre: Vector2) -> void:
	for i: int in range(SCATTER_COUNT):
		var angle: float = TAU * float(i) / float(SCATTER_COUNT)
		var spot: Vector2 = centre + Vector2(cos(angle), sin(angle)) * SCATTER_RING_M
		Match.spawn_special_projectile(_shape, _field.world_from_disk_local(spot, DROP_HEIGHT_M), Basis.IDENTITY, OTHER_SLOT, Vector3.ZERO, null, null)


# --- part B: crate lifecycle ----------------------------------------------------------------

func _script_crates() -> void:
	if _tick < B_START_TICK:
		return
	if (_tick - B_START_TICK) % PLACE_SPACING == 0 and _placed < PLACE_COUNT:
		_place_next()


## One request_place on a column pile beside the host's home, the way the sandbox pile does.
func _place_next() -> void:
	var home: Vector2 = Match.slot(HOST_SLOT).home_position
	var inward: Vector2 = -home.normalized()
	var side: Vector2 = Vector2(-inward.y, inward.x)
	var column: int = _placed % PLACE_COLUMNS
	var layer: int = (_placed / PLACE_COLUMNS) % PLACE_LAYERS
	var row: int = _placed / (PLACE_COLUMNS * PLACE_LAYERS)
	var spot: Vector2 = home + inward * (PLACE_INWARD_M + PLACE_ROW_SPACING_M * float(row)) + side * float(column - 1) * PLACE_COLUMN_SPACING_M
	var height: float = PLACE_BASE_HEIGHT_M + PLACE_LAYER_STEP_M * float(layer)
	var reason: StringName = Match.request_place(HOST_SLOT, _field.world_from_disk_local(spot, height), 0, Quaternion.IDENTITY, false)
	_events.append("%d|place|%d|%s" % [_tick, _placed, reason])
	_placed += 1


## Posts the host cursor at the air-touch crate's position for its last metres of descent: the air-touch claim.
func _follow_air_touch_crate() -> void:
	var state: Dictionary = Match.gift_state(AIR_TOUCH_GIFT_ID)
	if state.is_empty() or int(state["phase"]) != MatchGifts.FALLING:
		return
	var origin: Vector3 = state["origin"]
	var landing: Vector3 = state["landing"]
	var height_left: float = origin.distance_to(landing) - float(state["elapsed"]) * GIFT_CONFIG.fall_speed_m_s
	if height_left > AIR_TOUCH_RANGE_M:
		return
	var crate: Vector3 = landing + Vector3.UP * maxf(height_left, 0.0)
	Match.context().submit_cursor(HOST_SLOT, crate - Vector3.UP * (PHYSICS_TUNING.cube_size * 0.5), 0, Quaternion.IDENTITY, Vector3.ZERO)


# --- recording ------------------------------------------------------------------------------

func _count(kind: String) -> void:
	_counts[kind] = int(_counts.get(kind, 0)) + 1


func _on_special_triggered(net_id: int, def_id: StringName, position: Vector3, chain_depth: int) -> void:
	_count("special_triggered")
	_events.append("%d|special_triggered|%d|%s|%s|%s|%s|%d" % [_tick, net_id, def_id, _r(position.x), _r(position.y), _r(position.z), chain_depth])


func _on_gift_spawned(gift_id: int, position: Vector2) -> void:
	_count("gift_spawned")
	_events.append("%d|gift_spawned|%d|%s|%s" % [_tick, gift_id, _r(position.x), _r(position.y)])


func _on_gift_flight_spawned(gift_id: int, origin: Vector3, landing: Vector3) -> void:
	_count("gift_flight_spawned")
	_events.append("%d|gift_flight_spawned|%d|%s|%s|%s|%s" % [_tick, gift_id, _r(origin.y), _r(landing.x), _r(landing.y), _r(landing.z)])


func _on_gift_landed(gift_id: int, landing: Vector3) -> void:
	_count("gift_landed")
	_events.append("%d|gift_landed|%d|%s|%s|%s" % [_tick, gift_id, _r(landing.x), _r(landing.y), _r(landing.z)])


func _on_gift_claimed(gift_id: int, slot_id: int, special_id: StringName) -> void:
	_count("gift_claimed")
	_events.append("%d|gift_claimed|%d|%d|%s" % [_tick, gift_id, slot_id, special_id])


func _on_gift_expired(gift_id: int) -> void:
	_count("gift_expired")
	_events.append("%d|gift_expired|%d" % [_tick, gift_id])


func _on_glue_charges_changed(slot_id: int, charges: int, revision: int) -> void:
	_count("glue_charges_changed")
	_events.append("%d|glue_charges_changed|%d|%d|%d" % [_tick, slot_id, charges, revision])


func _on_block_frozen_changed(net_id: int, frozen: bool) -> void:
	_count("block_frozen_changed")
	_events.append("%d|block_frozen_changed|%d|%s" % [_tick, net_id, frozen])


func _on_block_removed(block: RigidBody3D, reason: String) -> void:
	_count("block_removed")
	var net_id: int = (block as Block).net_id if block is Block else -1
	_events.append("%d|block_removed|%d|%s" % [_tick, net_id, reason])


func _on_bean_hopped(position: Vector3) -> void:
	_count("bean_hopped")
	_events.append("%d|bean_hopped|%s|%s|%s" % [_tick, _r(position.x), _r(position.y), _r(position.z)])


func _on_placement_rejected(slot_id: int, reason: StringName) -> void:
	_events.append("%d|placement_rejected|%d|%s" % [_tick, slot_id, reason])


func _on_match_won(winning_team: int) -> void:
	_events.append("%d|match_won|%d" % [_tick, winning_team])


func _on_player_eliminated(slot_id: int, team_id: int) -> void:
	_events.append("%d|player_eliminated|%d|%d" % [_tick, slot_id, team_id])


func _r(value: float) -> float:
	return snappedf(value, ROUND_STEP) + 0.0


## Every live block (ordered by net id) and crate, sampled every RECORD_EVERY ticks.
func _sample() -> void:
	var prefix: String = "t%04d." % _tick
	var blocks: Array[Block] = _registry.all_blocks()
	blocks.sort_custom(func(a: Block, b: Block) -> bool: return a.net_id < b.net_id)
	_record[prefix + "blocks"] = blocks.size()
	for block: Block in blocks:
		var key: String = "%sb%d." % [prefix, block.net_id]
		var at: Vector3 = block.global_position
		var q: Quaternion = block.global_transform.basis.get_rotation_quaternion()
		_record[key + "owner"] = block.owner_slot
		_record[key + "gift"] = String(block.gift_id)
		_record[key + "sleeping"] = int(block.sleeping)
		_record[key + "frozen"] = int(block.is_frozen_visual()) + 2 * int(block.is_freeze_static())
		_record[key + "pos"] = [_r(at.x), _r(at.y), _r(at.z)]
		_record[key + "quat"] = [_r(q.x), _r(q.y), _r(q.z), _r(q.w)]
	for crate: Dictionary in Match.gift_states():
		var key: String = "%sc%d." % [prefix, int(crate["id"])]
		var position: Vector2 = crate["position"]
		_record[key + "phase"] = int(crate["phase"])
		_record[key + "pos"] = [_r(position.x), _r(position.y)]
		_record[key + "age"] = _r(float(crate["landed_age"]))
	_record[prefix + "glue0"] = Match.glue_drops_left(HOST_SLOT)
	_record[prefix + "state"] = int(Match.state())


func _finish() -> void:
	_record["events"] = _events
	get_tree().quit(_write(_part, _end_tick))


## Writes `_record` to --out as canonical JSON and prints the one result line; returns the exit code.
func _write(part: String, ticks: int) -> int:
	var text: String = JSON.stringify(_record, "	", true)
	if not _out_path.is_empty():
		var file: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
		if file == null:
			push_error("bench_p6_parity: cannot write %s" % _out_path)
			return 1
		file.store_string(text)
		file.close()
	var kinds: Array = _counts.keys()
	kinds.sort()
	var summary: PackedStringArray = PackedStringArray()
	for kind: String in kinds:
		summary.append("%s=%d" % [kind, _counts[kind]])
	print("BENCH_P6_PARITY sha256=%s part=%s ticks=%d keys=%d events=%d %s" % [text.sha256_text(), part, ticks, _record.size(), _events.size(), " ".join(summary)])
	return 0


## Prints the per-field maximum difference and returns the exit code (1 on any difference above `tol`).
func _compare(arg: String, tol: float) -> int:
	var parts: PackedStringArray = arg.split(",")
	if parts.size() != 2:
		push_error("bench_p6_parity: --compare needs a.json,b.json")
		return 1
	var a: Variant = JSON.parse_string(FileAccess.get_file_as_string(parts[0]))
	var b: Variant = JSON.parse_string(FileAccess.get_file_as_string(parts[1]))
	if not (a is Dictionary and b is Dictionary):
		push_error("bench_p6_parity: unreadable recording")
		return 1
	var left: Dictionary = a as Dictionary
	var right: Dictionary = b as Dictionary
	var tolerances: Dictionary = {"": tol} if tol > 0.0 else {}
	var differing: PackedStringArray = MatchFingerprint.diff(left, right, tolerances)
	var worst: Dictionary = {}
	for line: String in differing:
		var key: String = line.get_slice(": ", 0)
		var field: String = key.substr(key.rfind(".") + 1)
		if key.substr(1, 1) == ".":
			field = key.substr(0, 1) + "." + field
		worst[field] = maxf(worst.get(field, 0.0), _max_diff(left.get(key), right.get(key)))
	var fields: Array = worst.keys()
	fields.sort()
	for field: String in fields:
		print("BENCH_P6_PARITY field=%s max_diff=%s" % [field, worst[field]])
	print("BENCH_P6_PARITY compare keys=%d differing=%d tol=%s" % [left.size(), differing.size(), tol])
	return 1 if not differing.is_empty() else 0


## Largest absolute numeric difference between two recorded values; INF for a missing key, a type or
## length mismatch, or a non-numeric difference.
func _max_diff(a: Variant, b: Variant) -> float:
	var a_num: bool = a is float or a is int
	var b_num: bool = b is float or b is int
	if a_num and b_num:
		return absf(float(a) - float(b))
	if a is Array and b is Array and (a as Array).size() == (b as Array).size():
		var worst: float = 0.0
		for i: int in range((a as Array).size()):
			worst = maxf(worst, _max_diff((a as Array)[i], (b as Array)[i]))
		return worst
	return INF
