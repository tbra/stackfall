class_name TerritoryReplicator
extends RefCounted
## Territory replication for MatchNet's net_territory RPC. The host encodes the raster (a full
## keyframe, or the cells that changed), the team shares, the capture ring values and the analytic
## circle list into ONE packet; a client validates and applies it. The capture values are cached
## from Events.goal_capture_progress, the same signal the client re-emits from a packet.
##
## Packet layout, little endian:
##   u8 version | u8 flags (bit 0 = full keyframe) | i16 capture_team | f32 capture_progress |
##   u8 share_count | f32 share * share_count | u32 raster_len | raster payload | circle payload
## The raster payload is its own versioned, optionally zstd-compressed block (see _finish_raster).

## Packet and raster payload version, bumped whenever either layout changes. Like
## SnapshotSync.PACKET_VERSION this is architecture, not a tunable.
const VERSION: int = 1
const RASTER_HEADER_BYTES: int = 6
const RASTER_FLAG_COMPRESSED: int = 1 << 0
## One diff entry: u32 cell index, u8 owner, u8 state.
const RASTER_ENTRY_BYTES: int = 6
const PACKET_FLAG_FULL: int = 1 << 0
## version, flags, team, progress, share_count.
const PACKET_HEADER_BYTES: int = 9
const SHARE_BYTES: int = 4
const PROGRESS_OFFSET: int = 4
const SHARE_COUNT_OFFSET: int = 8
## Offsets of the owner and state bytes inside one diff entry (after its u32 cell index).
const ENTRY_OWNER_OFFSET: int = 4
const ENTRY_STATE_OFFSET: int = 5
const RASTER_LEN_BYTES: int = 4
## Bytes per cell of a full raster body (one owner byte, one state byte).
const FULL_CELL_BYTES: int = 2

var _host: MatchHostPort = null
var _replica: MatchReplicaPort = null
var _config: NetConfig = null

## The slot/state bytes the last packet carried: the baseline diffs are computed against.
var _last_owners: PackedByteArray = PackedByteArray()
var _last_states: PackedByteArray = PackedByteArray()
## Set at match start and whenever a peer joins: the next packet is a full keyframe.
var _force_full: bool = true
var _capture_team: int = -1
var _capture_progress: float = 0.0
## The capture values the last packet carried, and whether that last one was a falling value.
var _sent_capture_team: int = -1
var _sent_capture_progress: float = 0.0
var _capture_fading: bool = false


## `host` needs raster, circle_render_arrays, circle_wire_xz_bound, circle_wire_radius_max,
## territory_share and config; `replica` needs apply_replicated_territory. MatchNet wires them.
func _init(host: MatchHostPort, replica: MatchReplicaPort, config: NetConfig) -> void:
	_host = host
	_replica = replica
	_config = config
	Events.goal_capture_progress.connect(_on_goal_capture_progress)


## A full keyframe for a peer that holds nothing yet. Diffs to everyone else are computed against
## the baseline already sent, so that is what a joiner gets; with no baseline yet the current
## raster goes out and the next encode_diff is forced to a keyframe, so every peer converges.
## Empty with no raster.
func encode_full() -> PackedByteArray:
	var raster: TerritoryRaster = _host.raster()
	if raster == null:
		return PackedByteArray()
	var owners: PackedByteArray = _last_owners
	var states: PackedByteArray = _last_states
	if _force_full or owners.is_empty() or owners.size() != raster.owner_bytes().size():
		owners = raster.owner_bytes().duplicate()
		states = raster.state_bytes().duplicate()
		_force_full = true
	if owners.is_empty():
		return PackedByteArray()
	return _packet(true, _finish_raster(_full_body(owners, states)))


## The packet for this tick: a diff of the cells that changed since the last packet, or a full
## keyframe when the host forced one or more than raster_full_threshold_fraction changed. A
## decaying home claim changes no raster cell, so an empty diff still goes out while the capture
## ring is falling, changed team or (once falling) moving, until it clears; a rising hold on a
## static board sends nothing (the client extrapolates). Empty = nothing to send.
func encode_diff() -> PackedByteArray:
	var raster: TerritoryRaster = _host.raster()
	if raster == null:
		return PackedByteArray()
	var raw_owners: PackedByteArray = raster.owner_bytes()
	var raw_states: PackedByteArray = raster.state_bytes()
	if (
		not _force_full
		and raw_owners.size() == _last_owners.size()
		and raw_owners == _last_owners
		and raw_states == _last_states
		and not _capture_update_due()
	):
		return PackedByteArray()
	var owners: PackedByteArray = raw_owners.duplicate()
	var states: PackedByteArray = raw_states.duplicate()
	var count: int = owners.size()
	if count == 0:
		return PackedByteArray()
	var changed: PackedInt32Array = PackedInt32Array()
	var full: bool = _force_full or _last_owners.size() != count
	if not full:
		for index: int in range(count):
			if owners[index] != _last_owners[index] or states[index] != _last_states[index]:
				changed.append(index)
		if changed.size() == 0 and not _capture_update_due():
			return PackedByteArray()
		full = float(changed.size()) / float(count) > _config.raster_full_threshold_fraction
	var body: PackedByteArray = _full_body(owners, states) if full else _diff_body(changed, owners, states)
	var packet: PackedByteArray = _packet(full, _finish_raster(body))
	_last_owners = owners
	_last_states = states
	_force_full = false
	_note_capture_sent()
	return packet


## Client: validates one packet and applies it to the mirror raster, then re-emits the territory,
## share and capture signals. False (nothing applied, nothing emitted) for a truncated, foreign or
## out-of-range packet.
func apply(packet: PackedByteArray) -> bool:
	var raster: TerritoryRaster = _host.raster()
	if raster == null:
		return false
	var decoded: Dictionary = _decode(packet, raster.owner_bytes().size())
	if decoded.is_empty():
		return false
	var circles: Dictionary = CircleWire.decode(
		decoded["circles"] as PackedByteArray, _host.circle_wire_xz_bound(), _host.circle_wire_radius_max()
	)
	_replica.apply_replicated_territory(
		decoded["cells"],
		decoded["owners"],
		decoded["states"],
		bool(decoded["full"]),
		circles.get("xs", PackedFloat32Array()),
		circles.get("zs", PackedFloat32Array()),
		circles.get("radii", PackedFloat32Array()),
		circles.get("teams", PackedInt32Array()),
		circles.get("goal_positions", PackedVector2Array()),
		circles.get("goal_radii", PackedFloat32Array()),
		bool(circles.get("argmax_mode", false))
	)
	var opened: PackedInt32Array = raster.holes_opened()
	var closed: PackedInt32Array = raster.holes_closed()
	if opened.size() > 0 or closed.size() > 0:
		Events.hole_cells_changed.emit(opened, closed)
	Events.territory_replicated.emit(raster)
	Events.territory_share_changed.emit(decoded["shares"])
	Events.goal_capture_progress.emit(int(decoded["capture_team"]), float(decoded["capture_progress"]))
	return true


## Makes the next encode_diff a full keyframe (a match started or a peer needs a fresh baseline).
## The capture values are kept: they follow Events.goal_capture_progress, not the baseline.
func force_full() -> void:
	_last_owners = PackedByteArray()
	_last_states = PackedByteArray()
	_force_full = true


func _on_goal_capture_progress(team_id: int, progress: float) -> void:
	_capture_team = team_id
	_capture_progress = progress


func _capture_update_due() -> bool:
	if _sent_capture_progress <= 0.0:
		return false
	if _capture_team != _sent_capture_team:
		return true
	if is_equal_approx(_capture_progress, _sent_capture_progress):
		return false
	return _capture_progress < _sent_capture_progress or _capture_fading


func _note_capture_sent() -> void:
	_capture_fading = (
		_capture_team == _sent_capture_team and _capture_progress < _sent_capture_progress
	)
	_sent_capture_team = _capture_team
	_sent_capture_progress = _capture_progress


func _team_shares() -> PackedFloat32Array:
	var shares: PackedFloat32Array = PackedFloat32Array()
	var match_config: MatchConfig = _host.config()
	if match_config == null:
		return shares
	for team: int in range(match_config.team_count()):
		shares.append(_host.territory_share(team))
	return shares


## The host's last-built circle list, packed with the map's own quantization bounds so a client's
## decode uses the identical numbers the host encoded with.
func _encode_circles() -> PackedByteArray:
	var arrays: Dictionary = _host.circle_render_arrays()
	if arrays.is_empty():
		return PackedByteArray()
	return CircleWire.encode(
		arrays["xs"],
		arrays["zs"],
		arrays["radii"],
		arrays["teams"],
		arrays["goal_positions"],
		arrays["goal_radii"],
		bool(arrays["argmax_mode"]),
		_host.circle_wire_xz_bound(),
		_host.circle_wire_radius_max()
	)


func _packet(full: bool, raster_payload: PackedByteArray) -> PackedByteArray:
	var shares: PackedFloat32Array = _team_shares()
	var circles: PackedByteArray = _encode_circles()
	var packet: PackedByteArray = PackedByteArray()
	packet.resize(PACKET_HEADER_BYTES + shares.size() * SHARE_BYTES + RASTER_LEN_BYTES)
	packet.encode_u8(0, VERSION)
	packet.encode_u8(1, PACKET_FLAG_FULL if full else 0)
	packet.encode_s16(2, _capture_team)
	packet.encode_float(PROGRESS_OFFSET, _capture_progress)
	packet.encode_u8(SHARE_COUNT_OFFSET, shares.size())
	var offset: int = PACKET_HEADER_BYTES
	for share: float in shares:
		packet.encode_float(offset, share)
		offset += SHARE_BYTES
	packet.encode_u32(offset, raster_payload.size())
	packet.append_array(raster_payload)
	packet.append_array(circles)
	return packet


## Splits and validates a packet: {full, capture_team, capture_progress, shares, cells, owners,
## states, circles}, or {} for anything truncated, foreign, non-finite, out of range or whose raster
## body could not belong to a raster of `cell_count` cells.
func _decode(packet: PackedByteArray, cell_count: int) -> Dictionary:
	if packet.size() < PACKET_HEADER_BYTES + RASTER_LEN_BYTES or packet.decode_u8(0) != VERSION:
		return {}
	var full: bool = (packet.decode_u8(1) & PACKET_FLAG_FULL) != 0
	var team: int = packet.decode_s16(2)
	var progress: float = packet.decode_float(PROGRESS_OFFSET)
	var share_count: int = packet.decode_u8(SHARE_COUNT_OFFSET)
	if is_nan(progress) or is_inf(progress) or progress < 0.0 or progress > 1.0:
		return {}
	if team < -1 or team >= share_count:
		return {}
	var offset: int = PACKET_HEADER_BYTES
	if packet.size() < offset + share_count * SHARE_BYTES + RASTER_LEN_BYTES:
		return {}
	var shares: PackedFloat32Array = PackedFloat32Array()
	for _i: int in range(share_count):
		shares.append(packet.decode_float(offset))
		offset += SHARE_BYTES
	var raster_len: int = packet.decode_u32(offset)
	offset += RASTER_LEN_BYTES
	if raster_len > packet.size() - offset:
		return {}
	var raster: Dictionary = _decode_raster(packet.slice(offset, offset + raster_len), full, cell_count)
	if raster.is_empty():
		return {}
	raster["full"] = full
	raster["capture_team"] = team
	raster["capture_progress"] = progress
	raster["shares"] = shares
	raster["circles"] = packet.slice(offset + raster_len)
	return raster


func _full_body(owners: PackedByteArray, states: PackedByteArray) -> PackedByteArray:
	var body: PackedByteArray = PackedByteArray()
	body.append_array(owners)
	body.append_array(states)
	return body


func _diff_body(cells: PackedInt32Array, owners: PackedByteArray, states: PackedByteArray) -> PackedByteArray:
	var body: PackedByteArray = PackedByteArray()
	body.resize(cells.size() * RASTER_ENTRY_BYTES)
	var offset: int = 0
	for index: int in cells:
		body.encode_u32(offset, index)
		body.encode_u8(offset + ENTRY_OWNER_OFFSET, owners[index])
		body.encode_u8(offset + ENTRY_STATE_OFFSET, states[index])
		offset += RASTER_ENTRY_BYTES
	return body


## Prefixes the version, the compression flag and the uncompressed size, then compresses the body
## when NetConfig.raster_compress is on. The size has to travel: PackedByteArray.decompress()
## needs the output length, and the packet is reliable, so an honest 4 bytes beats guessing.
func _finish_raster(body: PackedByteArray) -> PackedByteArray:
	var flags: int = 0
	var payload_body: PackedByteArray = body
	if _config.raster_compress and body.size() > 0:
		var compressed: PackedByteArray = body.compress(FileAccess.COMPRESSION_ZSTD)
		if compressed.size() < body.size():
			payload_body = compressed
			flags |= RASTER_FLAG_COMPRESSED
	var block: PackedByteArray = PackedByteArray()
	block.resize(RASTER_HEADER_BYTES)
	block.encode_u8(0, VERSION)
	block.encode_u8(1, flags)
	block.encode_u32(2, body.size())
	block.append_array(payload_body)
	return block


## Inverse of _finish_raster: {"cells", "owners", "states"} or {} for a truncated, foreign,
## wrong-version or oversized block. The claimed uncompressed size is bounded by `cell_count`
## before anything is allocated for it.
func _decode_raster(block: PackedByteArray, full: bool, cell_count: int) -> Dictionary:
	if block.size() < RASTER_HEADER_BYTES or block.decode_u8(0) != VERSION:
		return {}
	var flags: int = block.decode_u8(1)
	var raw_size: int = block.decode_u32(2)
	var max_size: int = cell_count * (FULL_CELL_BYTES if full else RASTER_ENTRY_BYTES)
	if raw_size > max_size:
		return {}
	var body: PackedByteArray = block.slice(RASTER_HEADER_BYTES)
	if (flags & RASTER_FLAG_COMPRESSED) != 0:
		body = body.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if body.size() != raw_size:
		return {}
	if full:
		if raw_size != cell_count * FULL_CELL_BYTES:
			return {}
		var half: int = raw_size / FULL_CELL_BYTES
		return {"cells": PackedInt32Array(), "owners": body.slice(0, half), "states": body.slice(half)}
	if raw_size % RASTER_ENTRY_BYTES != 0:
		return {}
	var cells: PackedInt32Array = PackedInt32Array()
	var owners: PackedByteArray = PackedByteArray()
	var states: PackedByteArray = PackedByteArray()
	for i: int in range(raw_size / RASTER_ENTRY_BYTES):
		var offset: int = i * RASTER_ENTRY_BYTES
		var cell: int = body.decode_u32(offset)
		if cell >= cell_count:
			return {}
		cells.append(cell)
		owners.append(body.decode_u8(offset + ENTRY_OWNER_OFFSET))
		states.append(body.decode_u8(offset + ENTRY_STATE_OFFSET))
	return {"cells": cells, "owners": owners, "states": states}
