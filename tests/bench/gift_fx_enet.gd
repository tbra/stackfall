extends Node
## Bontago-1pi.85.17 (Gift fx J): host + THREE clients over real ENet, real physics,
## snapshots on. Scripted gifts are placed through the real held-gift path
## (gift slot -> request_place) and each client verifies, from replicated data only:
##   bomb:       blink visible and age-derived; the explosion moves replicated blocks;
##               the carrier despawns
##   black_hole: BlackHoleVisual appears, then goes away with the carrier
##   volcano:    body-less VolcanoStructure visual appears, rises, erupts blocks, expires
##   Round 2 (Bontago-1pi.85.36, docs/GIFT_PLAYTEST2_PLAN.md PJ), all from replicated data:
##   volcano/stackfall/earthquake: in-place, so the effect happens and NO gift carrier (and,
##               for earthquake, no extra block at all) ever exists on a client
##   anvil:      released carrier has the 5x activation scale (collider box and visual)
##   rocket:     fired upward, keeps rising, nose (model_nose_axis) along its velocity
##   black_hole: cubes beside the hole are captured and removed on clients
##   magnet:     thrown throwable leaves with the host-computed velocity (GiftAim)
##   Bontago-1pi.85.53: first received Rocket/Magnet pose already faced; Propeller stand and
##               Black-hole visual exist with no carrier body
##   final:      host/client block counts converge, no gift carriers left, no duplicate ids
## Handshake (no fixed-timer races, Bontago-fca.40): every phase is announced to the
## clients, the host fires only after all clients ack "armed", and a phase ends when
## all clients ack "done" (or the per-phase timeout, which is a failure).
## Run via tools/run_gift_fx_enet.ps1. Host: --headless-host --expect-peers=4.

const TAG: String = "GFXENET"
const HOST_AND_CLIENTS: int = 4
const CLIENT_COUNT: int = 3
const CONNECT_TIMEOUT: float = 25.0
const GATE_TIMEOUT: float = 40.0
const PHASE_ARM_TIMEOUT: float = 15.0
const PHASE_DONE_TIMEOUT: float = 90.0
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
const PHASES: Array[StringName] = [
	&"bomb", &"black_hole", &"volcano", &"anvil", &"rocket", &"magnet", &"earthquake", &"stackfall", &"propeller"]
const ANVIL_SLOT: int = 1
const ROCKET_SLOT: int = 2
## Bontago-1pi.85.54: after the earlier phases several floor columns around slot 2's home have no
## collider (the cursor ray misses: a throw there is refused as off_disk, not outside_territory), so
## the Rocket is released from a cursor point this far toward the disk centre, where the floor is intact.
const ROCKET_CURSOR_OFFSET_M: float = 20.0
const MAGNET_SLOT: int = 3
const QUAKE_SLOT: int = 1
const STACKFALL_SLOT: int = 2
const PROPELLER_SLOT: int = 3
const PROPELLER_OBSERVE_S: float = 3.0
## Bontago-1pi.85.53: the FIRST replicated pose of a thrown Rocket/Magnet is already faced.
const FIRST_POSE_MAX_DEG: float = 5.0
const ROCKET_AIM: Vector3 = Vector3(0.3, 1.0, 0.2)
const MAGNET_AIM: Vector3 = Vector3(0.8, 0.1, 0.6)
const HOLE_CUBE_OFFSET: Vector2 = Vector2(1.0, 0.0)
const HOLE_CUBES: int = 3
const HOLE_SETTLE_S: float = 2.0
const HOLE_REMOVE_TIMEOUT: float = 30.0
const CARRIER_GONE_TIMEOUT: float = 60.0
const INPLACE_EVENT_TIMEOUT: float = 20.0
const STACKFALL_OBSERVE_S: float = 9.0
const QUAKE_OBSERVE_S: float = 6.0
const SCALE_TOLERANCE: float = 0.02
const ROCKET_WATCH_S: float = 8.0
const ROCKET_MIN_RISE_M: float = 5.0
const ROCKET_MAX_DROP_M: float = 0.3
const ROCKET_MIN_STEP_M: float = 0.05
const ROCKET_NOSE_MAX_DEG: float = 20.0
const ROCKET_NOSE_MIN_FRACTION: float = 0.8
const ROCKET_AIM_MAX_DEG: float = 15.0
const ROCKET_MIN_SAMPLES: int = 6
const THROW_MIN_SPAN_S: float = 0.3
const THROW_MAX_DEG: float = 15.0
const THROW_SPEED_TOLERANCE: float = 0.4
const THROW_VELOCITY_EPS: float = 0.05
const THROW_SAMPLE_TIMEOUT: float = 8.0
const EXPECT_TIMEOUT: float = 10.0
const MSEC_PER_S: float = 1000.0
const ROCKET_BOUNDS_MARGIN_M: float = 2.0
const ROCKET_DIAG_SAMPLES: int = 6
const ROCKET_DIAG_STEP_S: float = 0.15

var _acks: Dictionary = {}
var _failures: Array[String] = []
var _trig: Dictionary = {}
var _cube: BlockShape = null
var _expect: Dictionary = {}


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


@rpc("authority", "call_remote", "reliable")
func net_expect(phase: String, vector: Vector3, ids: PackedInt32Array) -> void:
	_expect[phase] = [vector, ids]


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
	# Bontago-1pi.126: this harness checks replication timing, not throw scaling; pin the throw
	# reference radius to the harness map so thrown gifts keep their unscaled flight (scale 1.0).
	(load("res://config/special_tuning.tres") as SpecialTuning).gift_throw_reference_radius = field.map_def.field_radius
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
			await _fire_hole()
		&"volcano":
			await _fire_gift(VOLCANO_SLOT, &"volcano")
		&"anvil":
			await _fire_gift(ANVIL_SLOT, &"anvil")
		&"rocket":
			await _fire_throw(ROCKET_SLOT, &"rocket", ROCKET_AIM, Vector2(ROCKET_CURSOR_OFFSET_M, 0.0))
		&"magnet":
			await _fire_throw(MAGNET_SLOT, &"magnet", MAGNET_AIM)
		&"earthquake":
			await _fire_gift(QUAKE_SLOT, &"earthquake")
		&"stackfall":
			await _fire_gift(STACKFALL_SLOT, &"stackfall")
		&"propeller":
			await _fire_gift(PROPELLER_SLOT, &"propeller")
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


func _fire_hole() -> void:
	var home: Vector2 = Match.slot(HOLE_SLOT).home_position
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in HOLE_CUBES:
		var local: Vector3 = Vector3(home.x + HOLE_CUBE_OFFSET.x, CUBE_FIRST_Y + CUBE_STEP_Y * float(i), home.y + HOLE_CUBE_OFFSET.y)
		var cube: Block = Match.spawn_special_projectile(_cube, Match.field().to_global(local), Basis.IDENTITY, HOLE_SLOT, Vector3.ZERO, null, null)
		if cube != null:
			ids.append(cube.net_id)
	rpc(&"net_expect", "black_hole", Vector3.ZERO, ids)
	print("%s host hole cubes=%s" % [TAG, ids])
	await _wait(HOLE_SETTLE_S)
	await _fire_gift(HOLE_SLOT, &"black_hole")


## Releases the held gift through request_throw (camera forward `aim`) and tells the clients
## what the host computed: the launch velocity (magnet) or the aim (rocket).
func _fire_throw(slot: int, gift: StringName, aim: Vector3, cursor_offset: Vector2 = Vector2.ZERO) -> void:
	Match._gifts._queue_claimed_special(slot, gift)
	var used: bool = Match._gifts.request_use_gift_slot(slot)
	var held: bool = used and await _until(func() -> bool: return Match.held_special(slot) == gift, FIRE_HELD_TIMEOUT)
	var home: Vector2 = Match.slot(slot).home_position + cursor_offset
	var reason: StringName = &"not_held"
	if held:
		reason = Match.request_throw(slot, Vector3(home.x, PLACE_HEIGHT, home.y), 0, Quaternion.IDENTITY, aim, Match.feed_seq(slot))
	print("%s host threw gift=%s slot=%d used=%s held=%s reason=%s" % [TAG, gift, slot, used, held, reason])
	if reason != PlacementRules.REASON_OK:
		_failures.append("throw %s: reason=%s" % [gift, reason])
		return
	var carrier: Block = _gift_block(gift)
	var sent: Vector3 = aim.normalized()
	if gift == &"rocket" and carrier != null:
		for _i: int in ROCKET_DIAG_SAMPLES:
			await _wait(ROCKET_DIAG_STEP_S)
			if is_instance_valid(carrier):
				print("%s host rocket diag pos=%s vel_dir=%s speed=%.1f nose_dir=%s aim=%s" % [TAG, carrier.global_position, carrier.linear_velocity.normalized(), carrier.linear_velocity.length(), (carrier.global_basis * Vector3.UP).normalized(), aim.normalized()])
	if gift == &"magnet" and carrier != null:
		var tuning: SpecialTuning = load("res://config/special_tuning.tres") as SpecialTuning
		var expected_scale: float = GiftAim.range_scale(Match.field().map_definition().field_radius, tuning)
		var expected: Vector3 = GiftAim.throw_velocity(aim, tuning, expected_scale).limit_length(tuning.throw_max_speed * GiftAim.speed_factor(expected_scale))
		sent = carrier.linear_velocity
		if sent.distance_to(expected) > THROW_VELOCITY_EPS:
			_failures.append("host throw velocity %s != GiftAim %s" % [sent, expected])
		print("%s host throw velocity=%s expected=%s" % [TAG, sent, expected])
	rpc(&"net_expect", String(gift), sent, PackedInt32Array())


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
		&"anvil":
			_watch_anvil()
		&"rocket":
			_watch_rocket()
		&"magnet":
			_watch_magnet()
		&"earthquake":
			_watch_in_place(&"earthquake", QUAKE_OBSERVE_S, false)
		&"stackfall":
			_watch_in_place(&"stackfall", STACKFALL_OBSERVE_S, true)
		&"propeller":
			_watch_propeller()
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
	_watch_hole_cubes()
	var saw_carrier: bool = _gift_block(&"black_hole") != null
	var appeared: bool = await _until(func() -> bool:
		saw_carrier = saw_carrier or _gift_block(&"black_hole") != null
		return _find_nodes(&"BlackHoleVisual", Match.blocks_parent()).size() > 0, WATCH_TIMEOUT)
	saw_carrier = saw_carrier or _gift_block(&"black_hole") != null
	_ack(&"black_hole", "no_carrier", not saw_carrier, "in_place_carrier_seen=%s" % saw_carrier)
	_ack(&"black_hole", "visual", appeared and int(_trig.get(&"black_hole", 0)) > 0, "visual=%s event=%s" % [appeared, _trig.get(&"black_hole", 0)])
	var gone: bool = await _until(func() -> bool:
		saw_carrier = saw_carrier or _gift_block(&"black_hole") != null
		return _find_nodes(&"BlackHoleVisual", Match.blocks_parent()).is_empty() and _gift_block(&"black_hole") == null, WATCH_TIMEOUT)
	_ack(&"black_hole", "no_carrier_whole_run", not saw_carrier, "in_place_carrier_seen=%s" % saw_carrier)
	_ack(&"black_hole", "despawn", gone, "visual_and_carrier_gone=%s" % gone)
	_ack(&"black_hole", "done", true)


func _watch_hole_cubes() -> void:
	var got: bool = await _until(func() -> bool: return _expect.has("black_hole"), PHASE_ARM_TIMEOUT + PHASE_ARM_TIMEOUT)
	var ids: PackedInt32Array = PackedInt32Array()
	if got:
		ids = (_expect["black_hole"] as Array)[1] as PackedInt32Array
	var present: bool = got and not ids.is_empty() and await _until(func() -> bool:
		for id: int in ids:
			if Match.registry().block_for_net_id(id) == null:
				return false
		return true, WATCH_TIMEOUT)
	var removed: bool = present and await _until(func() -> bool:
		for id: int in ids:
			if Match.registry().block_for_net_id(id) != null:
				return false
		return true, HOLE_REMOVE_TIMEOUT)
	var left: int = 0
	for id: int in ids:
		if Match.registry().block_for_net_id(id) != null:
			left += 1
	_ack(&"black_hole", "captured_removed", removed, "cubes=%d present_first=%s still_alive=%d" % [ids.size(), present, left])


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
	var saw_carrier: bool = _gift_block(&"volcano") != null
	var particles: int = _find_nodes(&"GPUParticles3D", structure).size() if is_instance_valid(structure) else 0
	var deadline: int = Time.get_ticks_msec() + int(VOLCANO_WATCH_TIMEOUT * 1000.0)
	while is_instance_valid(structure) and Time.get_ticks_msec() < deadline:
		saw_carrier = saw_carrier or _gift_block(&"volcano") != null
		particles = maxi(particles, _find_nodes(&"GPUParticles3D", structure).size())
		max_height = maxf(max_height, structure.current_height())
		max_blocks = maxi(max_blocks, Match.registry().all_blocks().size())
		await _wait(VOLCANO_POLL_S)
	var gone: bool = not is_instance_valid(structure) and _gift_block(&"volcano") == null
	_ack(&"volcano", "rise_erupt", max_height > 0.0 and max_blocks > before, "max_height=%.2f blocks_before=%d blocks_max=%d" % [max_height, before, max_blocks])
	_ack(&"volcano", "no_carrier", not saw_carrier, "in_place_carrier_seen=%s" % saw_carrier)
	# Informational: the particle node is a PF deliverable and may be gated off headless.
	_ack(&"volcano", "particles_info", true, "gpu_particles_nodes=%d" % particles)
	_ack(&"volcano", "despawn", gone, "structure_and_carrier_gone=%s" % gone)
	_ack(&"volcano", "done", true)


# --- Round 2 watchers (Bontago-1pi.85.36) -------------------------------------------

## In-place gifts (Stackfall, Earthquake): the effect event reaches the client and no gift
## carrier is ever replicated. `rains` = the effect legitimately adds blocks (Stackfall);
## otherwise the block count must never exceed the baseline (Earthquake).
func _watch_in_place(gift: StringName, observe_s: float, rains: bool) -> void:
	var before: int = Match.registry().all_blocks().size()
	var saw_carrier: bool = false
	var max_blocks: int = before
	var event: bool = false
	var deadline: int = Time.get_ticks_msec() + int(INPLACE_EVENT_TIMEOUT * MSEC_PER_S)
	while Time.get_ticks_msec() < deadline:
		saw_carrier = saw_carrier or _gift_block(gift) != null
		max_blocks = maxi(max_blocks, Match.registry().all_blocks().size())
		if not event and int(_trig.get(gift, 0)) > 0:
			event = true
			deadline = Time.get_ticks_msec() + int(observe_s * MSEC_PER_S)
		await _wait(FRAME_S)
	_ack(gift, "event", event, "special_triggered=%d" % int(_trig.get(gift, 0)))
	_ack(gift, "no_carrier", not saw_carrier, "in_place_carrier_seen=%s" % saw_carrier)
	if rains:
		_ack(gift, "rain_blocks", max_blocks > before, "blocks_before=%d blocks_max=%d" % [before, max_blocks])
	else:
		_ack(gift, "no_extra_block", max_blocks <= before, "blocks_before=%d blocks_max=%d" % [before, max_blocks])
	_ack(gift, "done", true)


## Bontago-1pi.85.53: the Propeller is in-place; a client builds the stand visual (under the Field)
## from the effect event and never receives a carrier body.
func _watch_propeller() -> void:
	var saw_carrier: bool = _gift_block(&"propeller") != null
	var stand_up: bool = await _until(func() -> bool:
		saw_carrier = saw_carrier or _gift_block(&"propeller") != null
		return not _find_nodes(&"PropellerStand", Match.field()).is_empty(), WATCH_TIMEOUT)
	var found: Array[Node] = _find_nodes(&"PropellerStand", Match.field())
	var stand: PropellerStand = found[0] as PropellerStand if not found.is_empty() else null
	_ack(&"propeller", "stand_visual", stand_up and stand != null and int(_trig.get(&"propeller", 0)) > 0, "stand=%s event=%s" % [stand_up, _trig.get(&"propeller", 0)])
	var deadline: int = Time.get_ticks_msec() + int(PROPELLER_OBSERVE_S * MSEC_PER_S)
	while Time.get_ticks_msec() < deadline:
		saw_carrier = saw_carrier or _gift_block(&"propeller") != null
		await _wait(FRAME_S)
	_ack(&"propeller", "no_carrier", not saw_carrier, "in_place_carrier_seen=%s" % saw_carrier)
	_ack(&"propeller", "done", true)


func _watch_anvil() -> void:
	var seen: bool = await _until(func() -> bool: return _gift_block(&"anvil") != null, WATCH_TIMEOUT)
	var gift: Block = _gift_block(&"anvil")
	if not seen or gift == null:
		_ack(&"anvil", "scale", false, "anvil carrier never replicated")
		_ack(&"anvil", "done", false, "no carrier")
		return
	var net_id: int = gift.net_id
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var factor: float = BlockFactory.activation_scale_for(&"anvil")
	var box_size: float = -1.0
	for child: Node in gift.get_children():
		var collision: CollisionShape3D = child as CollisionShape3D
		if collision != null and collision.shape is BoxShape3D:
			box_size = maxf(box_size, (collision.shape as BoxShape3D).size.x)
	var expected_box: float = (tuning.cube_size - tuning.cube_margin) * factor
	var visual: Node3D = gift.get_node_or_null(NodePath(String(BlockFactory.GIFT_VISUAL_NODE))) as Node3D
	var reference: Node3D = GiftModelTable.shared().build_gift_visual(&"anvil")
	var visual_ratio: float = -1.0
	if visual != null and reference != null and reference.scale.x != 0.0:
		visual_ratio = visual.scale.x / reference.scale.x
	if reference != null:
		reference.free()
	var ok: bool = factor > 1.0 and absf(box_size - expected_box) <= SCALE_TOLERANCE * expected_box \
		and absf(visual_ratio - factor) <= SCALE_TOLERANCE * factor
	_ack(&"anvil", "scale", ok, "factor=%.2f collider_box=%.3f expected=%.3f visual_ratio=%.3f" % [factor, box_size, expected_box, visual_ratio])
	var gone: bool = await _until(func() -> bool: return Match.registry().block_for_net_id(net_id) == null, CARRIER_GONE_TIMEOUT)
	_ack(&"anvil", "despawn", gone, "carrier_gone=%s" % gone)
	_ack(&"anvil", "done", true)


func _watch_rocket() -> void:
	var seen: bool = await _until(func() -> bool: return _gift_block(&"rocket") != null, WATCH_TIMEOUT)
	var gift: Block = _gift_block(&"rocket")
	if not seen or gift == null:
		_ack(&"rocket", "rising", false, "rocket carrier never replicated")
		_ack(&"rocket", "done", false, "no carrier")
		return
	var net_id: int = gift.net_id
	var def: SpecialDef = SpecialDef.find_by_id(&"rocket")
	var nose: Vector3 = (def.effect as RocketEffect).model_nose_axis.normalized()
	# Bontago-1pi.85.53: the pose the client holds the moment the carrier first exists.
	var first_off_deg: float = rad_to_deg((gift.global_basis * nose).normalized().angle_to(ROCKET_AIM.normalized()))
	_ack(&"rocket", "first_pose_faced", first_off_deg <= FIRST_POSE_MAX_DEG, "first_nose_off_aim_deg=%.1f" % first_off_deg)
	var points: Array[Vector3] = []
	var noses: Array[Vector3] = []
	var rocket_left_bounds: bool = false
	var deadline: int = Time.get_ticks_msec() + int(ROCKET_WATCH_S * MSEC_PER_S)
	# Samples are kept only while the rocket is inside the snapshot position bounds: the wire clamps
	# a body that leaves them (finding on 1pi.85.36), which is a transport limit, not a facing bug.
	var inside: AABB = SnapshotSync._bounds.grow(-ROCKET_BOUNDS_MARGIN_M)
	while Time.get_ticks_msec() < deadline and is_instance_valid(gift) and int(_trig.get(&"rocket", 0)) == 0:
		if not inside.has_point(gift.global_position):
			rocket_left_bounds = true
			break
		elif not rocket_left_bounds and (points.is_empty() or gift.global_position.distance_to(points[points.size() - 1]) >= ROCKET_MIN_STEP_M):
			points.append(gift.global_position)
			noses.append((gift.global_basis * nose).normalized())
		await _wait(FRAME_S)
	var rise: float = 0.0
	var worst_drop: float = 0.0
	var aligned: int = 0
	var checked: int = 0
	for i: int in points.size():
		rise = maxf(rise, points[i].y - points[0].y)
		if i > 0:
			worst_drop = maxf(worst_drop, points[i - 1].y - points[i].y)
		if i >= 2:
			var velocity: Vector3 = points[i] - points[i - 2]
			if velocity.length() > ROCKET_MIN_STEP_M:
				checked += 1
				if rad_to_deg(noses[i].angle_to(velocity.normalized())) <= ROCKET_NOSE_MAX_DEG:
					aligned += 1
	var heading_deg: float = 180.0
	if points.size() >= 2:
		heading_deg = rad_to_deg((points[points.size() - 1] - points[0]).normalized().angle_to(ROCKET_AIM.normalized()))
	if points.size() >= 2:
		print("%s client rocket diag first=%s last=%s nose_first=%s nose_last=%s n=%d" % [TAG, points[0], points[points.size() - 1], noses[0], noses[noses.size() - 1], points.size()])
	var fraction: float = float(aligned) / float(maxi(checked, 1))
	var enough: bool = points.size() >= ROCKET_MIN_SAMPLES
	_ack(&"rocket", "rising", enough and rise >= ROCKET_MIN_RISE_M and worst_drop <= ROCKET_MAX_DROP_M, "samples=%d rise=%.2f worst_drop=%.2f left_wire_bounds=%s" % [points.size(), rise, worst_drop, rocket_left_bounds])
	_ack(&"rocket", "nose_along_velocity", enough and checked > 0 and fraction >= ROCKET_NOSE_MIN_FRACTION, "aligned=%d/%d (%.2f) within %.0f deg" % [aligned, checked, fraction, ROCKET_NOSE_MAX_DEG])
	_ack(&"rocket", "aim_heading", enough and heading_deg <= ROCKET_AIM_MAX_DEG, "heading_off_aim_deg=%.1f" % heading_deg)
	var gone: bool = await _until(func() -> bool: return Match.registry().block_for_net_id(net_id) == null, CARRIER_GONE_TIMEOUT)
	_ack(&"rocket", "despawn", gone, "carrier_gone=%s" % gone)
	_ack(&"rocket", "done", true)


func _watch_magnet() -> void:
	var seen: bool = await _until(func() -> bool: return _gift_block(&"magnet") != null, WATCH_TIMEOUT)
	var gift: Block = _gift_block(&"magnet")
	if not seen or gift == null:
		_ack(&"magnet", "velocity", false, "magnet carrier never replicated")
		_ack(&"magnet", "done", false, "no carrier")
		return
	var net_id: int = gift.net_id
	var magnet_def: SpecialDef = SpecialDef.find_by_id(&"magnet")
	var magnet_nose: Vector3 = (magnet_def.effect as MagnetEffect).model_nose_axis.normalized()
	var first_nose: Vector3 = (gift.global_basis * magnet_nose).normalized()
	var first_pos: Vector3 = gift.global_position
	var first_ms: int = Time.get_ticks_msec()
	var span_pos: Vector3 = first_pos
	var span_s: float = 0.0
	var deadline: int = first_ms + int(THROW_SAMPLE_TIMEOUT * MSEC_PER_S)
	while Time.get_ticks_msec() < deadline and is_instance_valid(gift) and span_s < THROW_MIN_SPAN_S:
		await _wait(FRAME_S)
		if is_instance_valid(gift):
			span_pos = gift.global_position
			span_s = float(Time.get_ticks_msec() - first_ms) / MSEC_PER_S
	var got: bool = await _until(func() -> bool: return _expect.has("magnet"), EXPECT_TIMEOUT)
	var expected: Vector3 = Vector3.ZERO
	if got:
		expected = (_expect["magnet"] as Array)[0] as Vector3
	var delta: Vector3 = span_pos - first_pos
	var angle_deg: float = 180.0
	var speed_ratio: float = 0.0
	if got and span_s >= THROW_MIN_SPAN_S and delta.length() > 0.0 and expected.length() > 0.0:
		angle_deg = rad_to_deg(delta.normalized().angle_to(expected.normalized()))
		speed_ratio = (delta.length() / span_s) / expected.length()
	var ok: bool = angle_deg <= THROW_MAX_DEG and absf(speed_ratio - 1.0) <= THROW_SPEED_TOLERANCE
	var first_off_deg: float = 180.0
	if got and expected.length() > 0.0:
		first_off_deg = rad_to_deg(first_nose.angle_to(expected.normalized()))
	_ack(&"magnet", "first_pose_faced", first_off_deg <= FIRST_POSE_MAX_DEG, "first_nose_off_velocity_deg=%.1f" % first_off_deg)
	_ack(&"magnet", "velocity", ok, "expected=%s angle_deg=%.1f speed_ratio=%.2f span_s=%.2f" % [expected, angle_deg, speed_ratio, span_s])
	var gone: bool = await _until(func() -> bool: return Match.registry().block_for_net_id(net_id) == null, CARRIER_GONE_TIMEOUT)
	_ack(&"magnet", "despawn", gone, "carrier_gone=%s" % gone)
	_ack(&"magnet", "done", true)


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
