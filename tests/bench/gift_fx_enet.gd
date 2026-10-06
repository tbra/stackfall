extends Node
## Bontago-1pi.85.17 (Gift fx J): host + THREE clients over real ENet, real physics,
## snapshots on. Scripted gifts are placed through the real held-gift path
## (gift slot -> request_place) and each client verifies, from replicated data only:
##   bomb:       blink visible and age-derived; the explosion moves replicated blocks;
##               the carrier despawns
##   black_hole: BlackHoleVisual appears, then goes away with the carrier
##   volcano:    body-less VolcanoStructure visual appears, rises, erupts blocks, expires
##   final:      host/client block counts converge, no gift carriers left, no duplicate ids
## Handshake (no fixed-timer races, Bontago-fca.40): every phase is announced to the
## clients, the host fires only after all clients ack "armed", and a phase ends when
## all clients ack "done" (or the per-phase timeout, which is a failure).
## Run via tests/bench/run_gift_fx_enet.ps1. Host: --headless-host --expect-peers=4.

const TAG: String = "GFXENET"
const HOST_AND_CLIENTS: int = 4
const CLIENT_COUNT: int = 3
const CONNECT_TIMEOUT: float = 25.0
const GATE_TIMEOUT: float = 40.0
const PHASE_ARM_TIMEOUT: float = 15.0
const PHASE_DONE_TIMEOUT: float = 70.0
const WATCH_TIMEOUT: float = 20.0
const VOLCANO_WATCH_TIMEOUT: float = 55.0
const FINAL_WATCH_TIMEOUT: float = 10.0
const CLIENT_LIFETIME_S: float = 400.0
const FIRE_HELD_TIMEOUT: float = 10.0
const CUBE_SETTLE_S: float = 2.5
const FINAL_SETTLE_S: float = 3.0
const QUIT_DELAY_S: float = 1.0
const PLACE_HEIGHT: float = 0.5
const CUBE_FIRST_Y: float = 0.6
const CUBE_STEP_Y: float = 1.0
const CUBES_PER_COLUMN: int = 3
const PILE_OFFSET: Vector2 = Vector2(2.0, 0.0)
const PILE_SECOND_COLUMN: Vector2 = Vector2(2.0, 1.3)
const BLINK_MIN_ALPHA: float = 0.05
const BLINK_BASELINE_AGE_S: float = 2.0
const BLINK_MAX_FIRST_AGE_S: float = 1.5
const EXPLOSION_WATCH_S: float = 1.5
const MIN_BLOCK_MOVE_M: float = 0.75
const COUNT_TOLERANCE: int = 0
const POLL_S: float = 0.05
const FRAME_S: float = 0.016
const VOLCANO_POLL_S: float = 0.1
const SEED: int = 20261006
const BOMB_SLOT: int = 1
const VOLCANO_SLOT: int = 2
const HOLE_SLOT: int = 3
const PHASES: Array[StringName] = [&"bomb", &"black_hole", &"volcano"]

var _acks: Dictionary = {}
var _failures: Array[String] = []
var _trig: Dictionary = {}
var _cube: BlockShape = null


func _ready() -> void:
	if not Net.apply_command_line():
		get_tree().quit(2)
		return
	_cube = load("res://config/blocks/cube.tres") as BlockShape
	Events.special_triggered.connect(_on_trigger)
	if Net.mode() == Net.Mode.HOST:
		await _run_host()
	else:
		await _run_client()


func _physics_process(delta: float) -> void:
	SnapshotSync.host_tick(delta)
	SnapshotSync.client_tick(delta)


func _on_trigger(_net_id: int, def_id: StringName, _position: Vector3, _depth: int) -> void:
	_trig[def_id] = int(_trig.get(def_id, 0)) + 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await _wait(POLL_S)
	return bool(condition.call())


func _build_world() -> Field:
	var field: Field = (load("res://game/Field.tscn") as PackedScene).instantiate() as Field
	field.map_def = MapDef.for_size(MapDef.MapSize.SMALL)
	add_child(field)
	var blocks: Node3D = Node3D.new()
	add_child(blocks)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child(registry)
	Match.register_world(field, registry, blocks)
	return field


# --- RPCs (bench node only; same path on every peer) ------------------------------

@rpc("authority", "call_remote", "reliable")
func net_phase(phase: String) -> void:
	_client_phase(StringName(phase))


@rpc("authority", "call_remote", "reliable")
func net_final(host_blocks: int) -> void:
	_client_final(host_blocks)


@rpc("any_peer", "call_remote", "reliable")
func net_ack(phase: String, kind: String, ok: bool, detail: String) -> void:
	var peer: int = multiplayer.get_remote_sender_id()
	var key: String = "%s/%s" % [phase, kind]
	if not _acks.has(key):
		_acks[key] = {}
	(_acks[key] as Dictionary)[peer] = [ok, detail]
	print("%s host phase=%s kind=%s peer=%d ok=%s %s" % [TAG, phase, kind, peer, ok, detail])
	if not ok and kind != "armed" and kind != "playing":
		_failures.append("%s peer %d: %s" % [key, peer, detail])


func _ack(phase: StringName, kind: String, ok: bool, detail: String = "") -> void:
	print("%s client slot=%d phase=%s kind=%s ok=%s %s" % [TAG, Net.local_slot(), phase, kind, ok, detail])
	rpc_id(Net.HOST_PEER_ID, &"net_ack", String(phase), kind, ok, detail)


func _ack_count(phase: StringName, kind: String) -> int:
	var key: String = "%s/%s" % [phase, kind]
	return (_acks[key] as Dictionary).size() if _acks.has(key) else 0


# --- Host -----------------------------------------------------------------------

func _run_host() -> void:
	var connected: bool = await _until(func() -> bool: return Net.peer_ids().size() >= HOST_AND_CLIENTS, CONNECT_TIMEOUT)
	if not connected:
		_fail_and_quit("not_all_clients_connected peers=%d" % Net.peer_ids().size())
		return
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = HOST_AND_CLIENTS
	config.hot_seat = false
	config.rng_seed = SEED
	config.gifts_enabled = false
	config.block_timer = MatchConfig.BLOCK_TIMER_MAX
	config.qol = QolExperiments.new()
	config.qol.gift_slot_enabled = true
	if OS.get_cmdline_user_args().has("--weather-off"):
		config.weather_mode = MatchConfig.WeatherMode.OFF
	Match._lifecycle.set_loading_gate_forced(true)
	var field: Field = _build_world()
	Match.start_match(config)
	get_node(^"/root/MatchNet").call(&"replicate_match_start", Match.config)
	field.place_flags(Match.config.player_count, Match.config.player_colors, Match.config.goal_flag_count)
	SnapshotSync.set_disk(field)
	SnapshotSync.begin_match(Match.registry(), Match.config.map_def())
	Net.request_loading_ready()
	var playing: bool = await _until(func() -> bool: return Match.state() == Match.State.PLAYING, GATE_TIMEOUT)
	var all_playing: bool = playing and await _until(
		func() -> bool: return _ack_count(&"world", "playing") >= CLIENT_COUNT, GATE_TIMEOUT)
	if not all_playing:
		_fail_and_quit("clients_not_playing playing=%s acks=%d" % [playing, _ack_count(&"world", "playing")])
		return
	for phase: StringName in PHASES:
		await _host_phase(phase)
	await _wait(FINAL_SETTLE_S)
	var host_blocks: int = Match.registry().all_blocks().size()
	rpc(&"net_final", host_blocks)
	await _until(func() -> bool: return _ack_count(&"final", "done") >= CLIENT_COUNT, FINAL_WATCH_TIMEOUT + GATE_TIMEOUT * 0.2)
	await _summary(host_blocks)


func _host_phase(phase: StringName) -> void:
	print("%s host phase=%s begin" % [TAG, phase])
	rpc(&"net_phase", String(phase))
	var armed: bool = await _until(func() -> bool: return _ack_count(phase, "armed") >= CLIENT_COUNT, PHASE_ARM_TIMEOUT)
	if not armed:
		_failures.append("%s: clients not armed (%d)" % [phase, _ack_count(phase, "armed")])
		return
	match phase:
		&"bomb":
			await _fire_bomb()
		&"black_hole":
			await _fire_gift(HOLE_SLOT, &"black_hole")
		&"volcano":
			await _fire_gift(VOLCANO_SLOT, &"volcano")
	var done: bool = await _until(func() -> bool: return _ack_count(phase, "done") >= CLIENT_COUNT, PHASE_DONE_TIMEOUT)
	if not done:
		_failures.append("%s: timeout waiting for done (%d)" % [phase, _ack_count(phase, "done")])


func _fire_bomb() -> void:
	var home: Vector2 = Match.slot(BOMB_SLOT).home_position
	for column: Vector2 in [PILE_OFFSET, PILE_SECOND_COLUMN]:
		for i: int in CUBES_PER_COLUMN:
			var local: Vector3 = Vector3(home.x + column.x, CUBE_FIRST_Y + CUBE_STEP_Y * float(i), home.y + column.y)
			Match.spawn_special_projectile(_cube, Match.field().to_global(local), Basis.IDENTITY, BOMB_SLOT, Vector3.ZERO, null, null)
	await _wait(CUBE_SETTLE_S)
	await _fire_gift(BOMB_SLOT, &"bomb")


func _fire_gift(slot: int, gift: StringName) -> void:
	Match._gifts._queue_claimed_special(slot, gift)
	var used: bool = Match._gifts.request_use_gift_slot(slot)
	var held: bool = used and await _until(func() -> bool: return Match.held_special(slot) == gift, FIRE_HELD_TIMEOUT)
	var home: Vector2 = Match.slot(slot).home_position
	var reason: StringName = &"not_held"
	if held:
		reason = Match.request_place(slot, Vector3(home.x, PLACE_HEIGHT, home.y), 0, Quaternion.IDENTITY, false, Match.feed_seq(slot))
	print("%s host fired gift=%s slot=%d used=%s held=%s reason=%s" % [TAG, gift, slot, used, held, reason])
	if reason != PlacementRules.REASON_OK:
		_failures.append("fire %s: reason=%s" % [gift, reason])


func _fail_and_quit(reason: String) -> void:
	_failures.append(reason)
	await _summary(-1)


func _summary(host_blocks: int) -> void:
	var gifts_left: int = 0
	if Match.registry() != null:
		for block: Block in Match.registry().all_blocks():
			if block.gift_id != &"":
				gifts_left += 1
	print("%s host summary host_blocks=%d gifts_left=%d failures=%d" % [TAG, host_blocks, gifts_left, _failures.size()])
	for failure: String in _failures:
		print("%s host FAILURE %s" % [TAG, failure])
	print("%s host result=%s" % [TAG, "PASS" if _failures.is_empty() else "FAIL"])
	await _wait(QUIT_DELAY_S)
	get_tree().quit(0 if _failures.is_empty() else 1)


# --- Client ---------------------------------------------------------------------

func _run_client() -> void:
	var field: Field = _build_world()
	Match._lifecycle.set_loading_gate_forced(true)
	var started: bool = await _until(func() -> bool: return Match.state() != Match.State.LOBBY, CONNECT_TIMEOUT + GATE_TIMEOUT)
	if not started:
		print("%s client result=FAIL reason=no_match_start" % TAG)
		get_tree().quit(2)
		return
	SnapshotSync.set_disk(field)
	SnapshotSync.begin_match(Match.registry(), Match.config.map_def())
	Net.request_loading_ready()
	var playing: bool = await _until(func() -> bool: return Match.state() == Match.State.PLAYING, GATE_TIMEOUT)
	_ack(&"world", "playing", playing, "state=%d slot=%d" % [Match.state(), Net.local_slot()])
	# Stay alive until the host ends the run (the session closes or the cap elapses).
	await _until(func() -> bool: return not Net.is_client(), CLIENT_LIFETIME_S)
	get_tree().quit(0)


func _positions() -> Dictionary:
	var result: Dictionary = {}
	for block: Block in Match.registry().all_blocks():
		if block.gift_id == &"":
			result[block.net_id] = block.global_position
	return result


func _gift_block(gift: StringName) -> Block:
	for block: Block in Match.registry().all_blocks():
		if block.gift_id == gift:
			return block
	return null


func _find_nodes(type_name: StringName, root: Node) -> Array[Node]:
	var result: Array[Node] = []
	if root != null:
		result.assign(root.find_children("*", String(type_name), true, false))
	return result


func _client_phase(phase: StringName) -> void:
	_trig.erase(phase)
	match phase:
		&"bomb":
			_watch_bomb()
		&"black_hole":
			_watch_black_hole()
		&"volcano":
			_watch_volcano()
	# Watchers run synchronously up to their first await, so their baseline exists.
	_ack(phase, "armed", true)


func _watch_bomb() -> void:
	var seen: bool = await _until(func() -> bool: return _gift_block(&"bomb") != null, WATCH_TIMEOUT)
	var gift: Block = _gift_block(&"bomb")
	if not seen or gift == null:
		_ack(&"bomb", "blink", false, "bomb carrier never replicated")
		_ack(&"bomb", "done", false, "no carrier")
		return
	var net_id: int = gift.net_id
	var driver_seen: bool = false
	var first_age: float = -1.0
	var last_age: float = -1.0
	var max_alpha: float = 0.0
	var overlay_on: bool = false
	var baseline: Dictionary = {}
	var deadline: int = Time.get_ticks_msec() + int(WATCH_TIMEOUT * 1000.0)
	while int(_trig.get(&"bomb", 0)) == 0 and Time.get_ticks_msec() < deadline:
		var driver: Node = gift.get_node_or_null(NodePath("GiftBlinkDriver")) if is_instance_valid(gift) else null
		if driver != null:
			var age: float = float(driver.get(&"age_s"))
			if not driver_seen:
				first_age = age
			driver_seen = true
			last_age = age
			var material: StandardMaterial3D = driver.get(&"_material") as StandardMaterial3D
			if material != null:
				max_alpha = maxf(max_alpha, material.albedo_color.a)
				for mesh: MeshInstance3D in (driver.get(&"_meshes") as Array):
					if is_instance_valid(mesh) and mesh.material_overlay == material:
						overlay_on = true
			if baseline.is_empty() and age >= BLINK_BASELINE_AGE_S:
				baseline = _positions()
		await _wait(FRAME_S)
	var exploded: bool = int(_trig.get(&"bomb", 0)) > 0
	if baseline.is_empty():
		baseline = _positions()
	var blink_ok: bool = driver_seen and overlay_on and max_alpha > BLINK_MIN_ALPHA \
		and first_age >= 0.0 and first_age < BLINK_MAX_FIRST_AGE_S and last_age > first_age
	_ack(&"bomb", "blink", blink_ok, "driver=%s overlay=%s max_alpha=%.2f first_age=%.2f last_age=%.2f" % [
		driver_seen, overlay_on, max_alpha, first_age, last_age])
	await _wait(EXPLOSION_WATCH_S)
	var now: Dictionary = _positions()
	var worst: float = 0.0
	var compared: int = 0
	for id: Variant in baseline.keys():
		if now.has(id):
			compared += 1
			worst = maxf(worst, (baseline[id] as Vector3).distance_to(now[id] as Vector3))
	_ack(&"bomb", "move", exploded and worst >= MIN_BLOCK_MOVE_M, "event=%s max_displacement=%.2f compared=%d" % [exploded, worst, compared])
	var gone: bool = await _until(func() -> bool: return Match.registry().block_for_net_id(net_id) == null, WATCH_TIMEOUT)
	_ack(&"bomb", "despawn", gone, "carrier_gone=%s" % gone)
	_ack(&"bomb", "done", true)


func _watch_black_hole() -> void:
	var appeared: bool = await _until(func() -> bool: return _find_nodes(&"BlackHoleVisual", Match.blocks_parent()).size() > 0, WATCH_TIMEOUT)
	_ack(&"black_hole", "visual", appeared and int(_trig.get(&"black_hole", 0)) > 0, "visual=%s event=%s" % [appeared, _trig.get(&"black_hole", 0)])
	var gone: bool = await _until(func() -> bool:
		return _find_nodes(&"BlackHoleVisual", Match.blocks_parent()).is_empty() and _gift_block(&"black_hole") == null, WATCH_TIMEOUT)
	_ack(&"black_hole", "despawn", gone, "visual_and_carrier_gone=%s" % gone)
	_ack(&"black_hole", "done", true)


func _watch_volcano() -> void:
	var before: int = Match.registry().all_blocks().size()
	var appeared: bool = await _until(func() -> bool: return not _find_nodes(&"VolcanoStructure", Match.field()).is_empty(), WATCH_TIMEOUT)
	var found: Array[Node] = _find_nodes(&"VolcanoStructure", Match.field())
	var structure: VolcanoStructure = found[0] as VolcanoStructure if not found.is_empty() else null
	appeared = appeared and structure != null
	var bodyless: bool = appeared and not structure.has_body()
	_ack(&"volcano", "visual", appeared and bodyless, "structure=%s bodyless=%s event=%s" % [appeared, bodyless, _trig.get(&"volcano", 0)])
	var max_height: float = 0.0
	var max_blocks: int = before
	var deadline: int = Time.get_ticks_msec() + int(VOLCANO_WATCH_TIMEOUT * 1000.0)
	while is_instance_valid(structure) and Time.get_ticks_msec() < deadline:
		max_height = maxf(max_height, structure.current_height())
		max_blocks = maxi(max_blocks, Match.registry().all_blocks().size())
		await _wait(VOLCANO_POLL_S)
	var gone: bool = not is_instance_valid(structure) and _gift_block(&"volcano") == null
	_ack(&"volcano", "rise_erupt", max_height > 0.0 and max_blocks > before, "max_height=%.2f blocks_before=%d blocks_max=%d" % [max_height, before, max_blocks])
	_ack(&"volcano", "despawn", gone, "structure_and_carrier_gone=%s" % gone)
	_ack(&"volcano", "done", true)


func _client_final(host_blocks: int) -> void:
	var converged: bool = await _until(func() -> bool:
		return absi(Match.registry().all_blocks().size() - host_blocks) <= COUNT_TOLERANCE, FINAL_WATCH_TIMEOUT)
	var gifts_left: int = 0
	for block: Block in Match.registry().all_blocks():
		if block.gift_id != &"":
			gifts_left += 1
	var duplicates: int = int(get_node(^"/root/MatchNet").call(&"duplicate_net_id_count"))
	var ok: bool = converged and gifts_left == 0 and duplicates == 0 and Net.is_client()
	_ack(&"final", "done", ok, "client_blocks=%d host_blocks=%d gifts_left=%d duplicate_ids=%d connected=%s" % [
		Match.registry().all_blocks().size(), host_blocks, gifts_left, duplicates, Net.is_client()])
	print("%s client slot=%d result=%s" % [TAG, Net.local_slot(), "PASS" if ok else "FAIL"])
	await _wait(QUIT_DELAY_S)
	get_tree().quit(0)
