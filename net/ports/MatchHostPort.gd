class_name MatchHostPort
extends RefCounted
## Typed adapter over the Match autoload: the host-side rule entry points and reads that
## net/MatchNet, WeatherNet, SnowNet, BreezeNet and the MatchEventApplier use. The client-side
## mirror writes live on MatchReplicaPort. Every method forwards to `_match`; a signature
## drift is a parse error. Tests subclass the port (FakeHostPort) and override what they answer.
##
## The feed_* and lifecycle readers are TRANSITIONAL: they forward to Match's private `_feed`
## and `_lifecycle` collaborators and go away when Match exposes them.

var _match: MatchAutoload = null


## A null adapter is an invalid port: consumers refuse to bind it, and a forwarder called on one
## is a loud null-call engine error (what an unspied method on a spy should be).
func _init(match_node: MatchAutoload = null) -> void:
	_match = match_node


## True when the port adapts a Match; spies override it.
func is_valid() -> bool:
	return _match != null


# --- replication membrane (net/MatchNet.gd) ---------------------------------

## Installs `replicator` as the node Match replicates through (null turns replication off).
func set_replicator(replicator: Variant) -> void:
	_match.set_replicator(replicator)


## Uninstalls `replicator`, but only while it is still the installed one.
func release_replicator(replicator: Variant) -> void:
	if _match.replicator() == replicator:
		_match.set_replicator(null)


func default_ghost_origin(slot_id: int) -> Vector3:
	return _match.default_ghost_origin(slot_id)


func on_peer_left(slot_id: int) -> void:
	_match.on_peer_left(slot_id)


## Seconds left of the slot's disconnect grace, or -1.0 when it has none.
func disconnect_grace_left(slot_id: int) -> float:
	return _match.disconnect_grace_left(slot_id)


func held_shape(slot_id: int) -> BlockShape:
	return _match.held_shape(slot_id)


func next_shape(slot_id: int) -> BlockShape:
	return _match.next_shape(slot_id)


func held_special(slot_id: int) -> StringName:
	return _match.held_special(slot_id)


func next_special(slot_id: int) -> StringName:
	return _match.next_special(slot_id)


func after_next_special(slot_id: int) -> StringName:
	return _match.after_next_special(slot_id)


# --- rule entry points and intents ------------------------------------------

## Match.config, the running match's sanitized config (null in the lobby).
func config() -> MatchConfig:
	return _match.config


func state() -> int:
	return _match.state()


func slot_count() -> int:
	return _match.slot_count()


func slot(slot_id: int) -> PlayerSlot:
	return _match.slot(slot_id)


## The refusal reason (PlacementRules.REASON_OK, &"", when accepted).
func request_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq_value: int
) -> StringName:
	return _match.request_place(slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq_value)


func request_throw(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq_value: int
) -> StringName:
	return _match.request_throw(slot_id, origin, orientation_index, free_quat, velocity, feed_seq_value)


func request_use_gift_slot(slot_id: int) -> bool:
	return _match.request_use_gift_slot(slot_id)


func set_cat_target(slot_id: int, point: Vector3) -> bool:
	return _match.set_cat_target(slot_id, point)


## Records a slot's last aim.
func note_aim(slot_id: int, aim: Vector3) -> void:
	_match.note_aim(slot_id, aim)


func is_pose_well_formed(origin: Vector3, orientation_index: int, free_quat: Quaternion) -> bool:
	return _match.is_pose_well_formed(origin, orientation_index, free_quat)


func feed_seq(slot_id: int) -> int:
	return _match.feed_seq(slot_id)


func on_peer_rejoined(slot_id: int) -> void:
	_match.on_peer_rejoined(slot_id)


func abort_match() -> void:
	_match.abort_match()


func start_match(match_config: MatchConfig) -> void:
	_match.start_match(match_config)


# --- reads ---------------------------------------------------------------------

func active_cat() -> RigidBody3D:
	return _match.active_cat()


func active_slot() -> int:
	return _match.active_slot()


func blocks_parent() -> Node3D:
	return _match.blocks_parent()


func circle_render_arrays() -> Dictionary:
	return _match.circle_render_arrays()


func circle_wire_radius_max() -> float:
	return _match.circle_wire_radius_max()


func circle_wire_xz_bound() -> float:
	return _match.circle_wire_xz_bound()


func countdown_remaining() -> float:
	return _match.countdown_remaining()


func eliminated_by(slot_id: int) -> int:
	return _match.eliminated_by(slot_id)


func feed_time_left(slot_id: int) -> float:
	return _match.feed_time_left(slot_id)


func field() -> FieldBody:
	return _match.field()


func gift_slot_contents(slot_id: int) -> Array[StringName]:
	return _match.gift_slot_contents(slot_id)


func gift_slot_enabled() -> bool:
	return _match.gift_slot_enabled()


func gift_state(gift_id: int) -> Dictionary:
	return _match.gift_state(gift_id)


func gift_states() -> Array[Dictionary]:
	return _match.gift_states()


func glue_drops_left(slot_id: int) -> int:
	return _match.glue_drops_left(slot_id)


func glue_revision(slot_id: int) -> int:
	return _match.glue_revision(slot_id)


func is_release_locked(slot_id: int) -> bool:
	return _match.is_release_locked(slot_id)


func match_timer_left() -> float:
	return _match.match_timer_left()


func mode_state_snapshot() -> Dictionary:
	return _match.mode_state_snapshot()


func qol_backlog_count(slot_id: int) -> int:
	return _match.qol_backlog_count(slot_id)


func qol_timer_paused(slot_id: int) -> bool:
	return _match.qol_timer_paused(slot_id)


func raster() -> TerritoryRaster:
	return _match.raster()


func registry() -> Node:
	return _match.registry()


## The per-slot stats object (MatchStats): build_live_payload() and
## apply_live_snapshot() are called on it directly by the replication nodes.
func stats() -> RefCounted:
	return _match.stats()


func territory_share(team_id: int) -> float:
	return _match.territory_share(team_id)


func weather() -> RefCounted:
	return _match.weather()


# --- TRANSITIONAL: Match's private feed / lifecycle collaborators -----------------

## Whether `shape_id` names a known block shape (MatchFeed._shape_by_id is not
## null). False when there is no feed.
func feed_knows_shape(shape_id: StringName) -> bool:
	var feed: RefCounted = _match.feed()
	if feed == null:
		return false
	return feed.call(&"_shape_by_id", shape_id) != null


func feed_claim_carrier_shape_id(slot_id: int) -> StringName:
	var feed: RefCounted = _match.feed()
	if feed == null:
		return &""
	return StringName(feed.call(&"claim_carrier_shape_id", slot_id))


func feed_gift_after_next_active() -> bool:
	var feed: RefCounted = _match.feed()
	if feed == null:
		return false
	return bool(feed.call(&"gift_after_next_active"))


func feed_staged_gift_shape_id(slot_id: int) -> StringName:
	var feed: RefCounted = _match.feed()
	if feed == null:
		return &""
	return StringName(feed.call(&"staged_gift_shape_id", slot_id))


## QoL: a triggered special freezes block timers. No-op without a feed.
func feed_note_special_triggered() -> void:
	var feed: RefCounted = _match.feed()
	if feed != null:
		feed.call(&"note_special_triggered")


## MatchLifecycle.is_starting_match(). False when there is no lifecycle.
func is_starting_match() -> bool:
	var lifecycle: RefCounted = _match.lifecycle()
	if lifecycle == null:
		return false
	return bool(lifecycle.call(&"is_starting_match"))


## MatchLifecycle.loading_gate_replay_args(); empty without a lifecycle.
func loading_gate_replay_args() -> Array:
	var lifecycle: RefCounted = _match.lifecycle()
	if lifecycle == null:
		return []
	return lifecycle.call(&"loading_gate_replay_args") as Array
