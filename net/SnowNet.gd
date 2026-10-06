class_name SnowNet
extends Node
## Snow replication and client rendering (Bontago-22y.6), a child of
## WeatherNet so its RPC path (/root/MatchNet/WeatherNet/SnowNet) is the same
## on every instance.
##
## Host -> clients only. The host's SnowEffect publishes its compact patch
## list (SnowGeometry wire format: per block net_id, face axis and
## (cell, level) pairs; per disc cell a level) through SnowRelay; this node
## sends it, throttled to SnowTuning.send_min_interval_s, and resends the
## latest one to a peer that joins late. An empty state (snow melted or the
## event restored) is sent at once, so it always precedes the weather's own
## stop message on the same reliable channel.
##
## A client validates the payload, then draws the caps with SnowCaps without
## colliders: it never creates a snow collider and never decides anything.
## There is no client -> host message.

var states_sent: int = 0
var states_applied: int = 0
var states_refused: int = 0
var last_sent_state: Dictionary = {}

var _tuning: SnowTuning = preload("res://config/weather/snow.tres") as SnowTuning
var _net_provider: Variant = null
var _match_provider: Variant = null
var _pending: Dictionary = {}
var _has_pending: bool = false
var _since_send: float = INF

## Client render state: the last applied sanitized state, the blocks drawn
## (net_id -> Block) and the records they were drawn from.
var _client_state: Dictionary = {}
var _rendered: Dictionary = {}
var _rendered_records: Dictionary = {}
var _rendered_disc: Dictionary = {}
var _unresolved: bool = false
var _render_queued: bool = false
var _builder: SnowCapBuilder = null


func _ready() -> void:
	SnowRelay.instance().state_published.connect(_on_published)
	Events.net_peer_joined.connect(_on_net_peer_joined)
	Events.match_state_changed.connect(_on_match_state_changed)
	Events.weather_stopped.connect(_on_weather_stopped)
	Events.block_placed.connect(_on_block_placed)


func _exit_tree() -> void:
	# The relay is process-wide; a freed SnowNet must not stay subscribed.
	var relay: SnowRelay = SnowRelay.instance()
	if relay.state_published.is_connected(_on_published):
		relay.state_published.disconnect(_on_published)


## Same seam as WeatherNet.set_providers(); null keeps the real autoload.
## Same gate as WeatherNet.awaiting_world (set by WeatherNet).
var awaiting_world: Callable = Callable()


func set_providers(net_provider: Variant, match_provider: Variant) -> void:
	_net_provider = net_provider
	_match_provider = match_provider


func set_tuning(tuning: SnowTuning) -> void:
	_tuning = tuning


func _session() -> Variant:
	return _net_provider if _net_provider != null else Net


func _authority() -> Variant:
	return _match_provider if _match_provider != null else Match


func _is_host() -> bool:
	return bool(_session().is_host())


func _can_send() -> bool:
	if bool(_session().is_offline()):
		return false
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _process(delta: float) -> void:
	step_client(_tuning.rebuild_patches_per_frame)
	_since_send += delta
	if _has_pending and _since_send >= _tuning.send_min_interval_s:
		_send(_pending)


# --- Host -> clients ------------------------------------------------------------------

func _on_published(state: Dictionary) -> void:
	if not _is_host():
		return
	if SnowRelay.is_empty_state(state) or _since_send >= _tuning.send_min_interval_s:
		_send(state)
	else:
		_pending = state
		_has_pending = true


func _send(state: Dictionary) -> void:
	_has_pending = false
	_pending = {}
	_since_send = 0.0
	last_sent_state = state
	states_sent += 1
	if _can_send():
		NetFanout.broadcast(self, _session(), &"net_snow_state", [state])


func _on_net_peer_joined(peer_id: int, _slot_id: int, _player_name: String) -> void:
	if not _is_host():
		return
	if multiplayer.has_multiplayer_peer() and peer_id == multiplayer.get_unique_id():
		return
	var state: Dictionary = SnowRelay.instance().last_state
	if SnowRelay.is_empty_state(state):
		return
	states_sent += 1
	if _can_send():
		rpc_id(peer_id, &"net_snow_state", state)


@rpc("authority", "call_remote", "reliable")
func net_snow_state(state: Dictionary) -> void:
	if _is_host():
		states_refused += 1
		return
	if awaiting_world.is_valid() and bool(awaiting_world.call()):
		states_refused += 1
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != MultiplayerPeer.TARGET_PEER_SERVER:
		states_refused += 1
		return
	apply_state(state)


# --- Client --------------------------------------------------------------------------------

## Client: validates and draws a replicated state. Returns false (and changes
## nothing) on the host, for a malformed payload, or for snow arriving while
## no snow event is live (an empty state is always accepted: it clears).
func apply_state(raw: Variant) -> bool:
	if _is_host():
		states_refused += 1
		return false
	var authority: Variant = _authority()
	var field: Field = authority.field() as Field
	var max_cell: int = field.grid().cell_count() - 1 if field != null else -1
	var data: Dictionary = SnowGeometry.sanitize_state(raw, _tuning, max_cell)
	if data.is_empty():
		states_refused += 1
		return false
	var has_snow: bool = int(data["cover"]) > 0 or not (data["blocks"] as Dictionary).is_empty() or not (data["disc"] as Dictionary).is_empty()
	if has_snow and not _snow_live(authority):
		states_refused += 1
		return false
	_client_state = data
	_render()
	states_applied += 1
	return true


func _snow_live(authority: Variant) -> bool:
	if not MatchAutoload.is_replicating(int(authority.state())):
		return false
	var weather: MatchWeather = authority.weather() as MatchWeather
	return weather != null and weather.active_id() == &"snow"


## Client: removes every drawn cap.
func clear_client() -> void:
	if _builder != null:
		_builder.clear_all()
	for key: Variant in _rendered.keys():
		var held: Variant = _rendered[key]
		if is_instance_valid(held):
			SnowCaps.clear_block(held as Block)
	_rendered.clear()
	_rendered_records.clear()
	_rendered_disc.clear()
	_client_state = {}
	_unresolved = false
	var field: Field = _authority().field() as Field
	if field != null:
		SnowCaps.clear_disc(field)


## Client: steps the geometry builder (budgeted like the host's).
func step_client(budget: int) -> void:
	if _builder != null and not _builder.is_idle():
		_builder.step(budget)


func is_client_building() -> bool:
	return _builder != null and not _builder.is_idle()


## Diffs the applied state against what is drawn and hands the changes to
## the builder; drawing happens over the next frames in step_client().
func _render() -> void:
	_render_queued = false
	if _client_state.is_empty():
		return
	if _builder == null or _builder.tuning != _tuning:
		_builder = SnowCapBuilder.new(_tuning, false)
	var authority: Variant = _authority()
	var registry: BlockRegistry = authority.registry() as BlockRegistry
	var seed_value: int = int(_client_state["seed"])
	var blocks: Dictionary = _client_state["blocks"]
	for key: Variant in _rendered.keys():
		# A freed block (gift blast/despawn) is a stale key even if the host still lists it.
		if not blocks.has(key) or not is_instance_valid(_rendered[key]):
			var gone: Variant = _rendered[key]
			_builder.drop_owner("b%d" % int(key))
			if is_instance_valid(gone):
				SnowCaps.clear_block(gone as Block)
			_rendered.erase(key)
			_rendered_records.erase(key)
	_unresolved = false
	for key: Variant in blocks.keys():
		var net_id: int = int(key)
		var record: Array = blocks[key]
		var block: Block = registry.block_for_net_id(net_id) if registry != null else null
		if block == null or not is_instance_valid(block):
			_unresolved = true
			continue
		if _rendered.get(net_id) == block and _rendered_records.get(net_id) == record:
			continue
		_set_block_record(block, net_id, record, _rendered_records.get(net_id, []) as Array, seed_value)
		_rendered[net_id] = block
		_rendered_records[net_id] = record
	var field: Field = authority.field() as Field
	if field == null:
		return
	var disc: Dictionary = _client_state["disc"]
	if disc != _rendered_disc:
		var grid: CellGrid = field.grid()
		var edge: float = SnowCaps.disc_patch_edge(grid, _tuning)
		for key: Variant in _rendered_disc.keys():
			if not disc.has(key):
				_set_disc_cell(field, grid, edge, int(key), 0, seed_value)
		for key: Variant in disc.keys():
			if int(_rendered_disc.get(key, 0)) != int(disc[key]):
				_set_disc_cell(field, grid, edge, int(key), int(disc[key]), seed_value)
		_rendered_disc = disc
	SnowCaps.set_disc_cover(field, seed_value, int(_client_state["cover"]), _tuning, _client_blocks)


func _client_blocks() -> Array:
	var registry: BlockRegistry = _authority().registry() as BlockRegistry
	return registry.all_blocks() if registry != null else []


func _set_block_record(block: Block, net_id: int, record: Array, previous: Array, seed_value: int) -> void:
	var axis: int = int(record[0])
	var cells: PackedInt32Array = record[1]
	var levels: PackedInt32Array = record[2]
	var cube_size: float = SnowCaps.cube_size_of(block)
	var centers: PackedVector3Array = SnowCaps.block_cells(block)
	var key: String = "b%d" % net_id
	if not previous.is_empty() and int(previous[0]) != axis:
		_builder.drop_owner(key)
		previous = []
	if not previous.is_empty():
		var old_cells: PackedInt32Array = previous[1]
		for cell: int in old_cells:
			if not cells.has(cell) and cell < centers.size():
				_builder.set_patch(key, block, -1, cell, SnowGeometry.block_patch_transform(centers[cell], axis, cube_size), 0.0, 0, 0)
	for k: int in range(cells.size()):
		var cell: int = cells[k]
		if cell >= centers.size():
			continue
		_builder.set_patch(
			key, block, -1, cell, SnowGeometry.block_patch_transform(centers[cell], axis, cube_size),
			SnowCaps.block_patch_edge(cube_size, _tuning), SnowGeometry.patch_seed(seed_value, net_id, cell, axis), levels[k]
		)


func _set_disc_cell(field: Field, grid: CellGrid, edge: float, cell: int, level: int, seed_value: int) -> void:
	var region: int = SnowCaps.disc_region(grid, cell, _tuning)
	_builder.set_patch(
		"d%d" % region, field, region, cell, SnowCaps.disc_patch_frame(grid, cell, _tuning), edge,
		SnowGeometry.patch_seed(seed_value, SnowGeometry.DISC_OWNER, cell, SnowGeometry.AXIS_UP), level
	)


func _on_match_state_changed(_from_state: int, to_state: int) -> void:
	if _is_host():
		return
	if MatchAutoload.is_resetting(to_state):
		clear_client()


func _on_weather_stopped(weather_id: StringName) -> void:
	if weather_id == &"snow" and not _is_host():
		clear_client()


## A block spawned on a client after the state that names it: draw it once
## its net_id is bound (MatchNet binds right after emitting block_placed).
func _on_block_placed(_block: RigidBody3D, _shape_id: StringName) -> void:
	if _unresolved and not _render_queued and not _is_host():
		_render_queued = true
		_render.call_deferred()
