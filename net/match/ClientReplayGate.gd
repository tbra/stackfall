class_name ClientReplayGate
extends RefCounted
## Client-side world gate and replay span.
##
## Awaiting: true from the moment this instance becomes a CLIENT until the first match start lands.
## Every host -> client gameplay RPC in that window was broadcast before this peer's replay was built,
## so the replay already contains its effect; applying it to a world that does not exist yet could only
## corrupt the mirror.
## Replay span: the late-join/reconnect world replay being applied (id 0 = none), opened by the match
## start that carries it and closed by the matching end, or early by a new start, a mode change,
## teardown or the ack timeout, so a replay that never completes cannot mute live feedback.

const MS_PER_S: float = 1000.0

var _session: SessionPort = null
var _config: NetConfig = null
var _awaiting: bool = false
var _replaying_id: int = 0
var _replaying_since_ms: int = 0


## Refreshes the refs; KEEPS the awaiting/replay-span state.
func bind(session: SessionPort, config: NetConfig) -> void:
	_session = session
	_config = config


func awaiting_world() -> bool:
	return _awaiting and not _session.is_host()


## Awaiting = client; ends any replay span.
func on_mode_changed(is_client: bool) -> void:
	_awaiting = is_client
	end_replay()


func on_match_start(replay_id: int, now_ms: int) -> void:
	_awaiting = false
	end_replay()
	if replay_id > 0 and not _session.is_host():
		_replaying_id = replay_id
		_replaying_since_ms = now_ms
		Events.world_replay_changed.emit(true)


## True = send net_replay_ack.
func on_replay_end(replay_id: int) -> bool:
	if _session.is_host() or awaiting_world() or replay_id <= 0:
		return false
	if replay_id == _replaying_id:
		end_replay()
	return true


## A replay's messages all land in one network poll, so one that has not finished by the host's own
## ack timeout never will: expiry at config.replay_ack_timeout.
func tick(now_ms: int) -> void:
	if _replaying_id == 0:
		return
	var elapsed_s: float = float(now_ms - _replaying_since_ms) / MS_PER_S
	if elapsed_s >= _config.replay_ack_timeout:
		end_replay()


## Idempotent; emits only on a real true -> false transition.
func end_replay() -> void:
	if _replaying_id == 0:
		return
	_replaying_id = 0
	Events.world_replay_changed.emit(false)
