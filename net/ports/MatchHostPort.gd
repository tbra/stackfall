class_name MatchHostPort
extends RefCounted
## Typed adapter over the Match autoload (or a test double): the host-side rule
## entry points and reads that net/MatchNet, WeatherNet, SnowNet, BreezeNet and
## the MatchEventApplier use. The client-side mirror writes live on
## MatchReplicaPort.
##
## DECISION: see SessionPort for why this is an adapter holding the autoload
## (one dynamic call per method) with a runtime is_valid() instead of an assert.
## The adapted object is an Object so RefCounted doubles (FakeMatch) fit.
##
## The surface is the list `_authority().` / `authority.` reads in net/ at the
## time of writing, with return types copied from autoload/Match.gd. Match is
## not edited. Entries marked TRANSITIONAL forward to Match's private `_feed`
## and `_lifecycle` collaborators (which the consumers reach into today); they
## answer a neutral default when the adapted object has no such collaborator,
## as the test doubles do, and go away when Match exposes them.

## Every method (plus the `config` property, checked separately) a real Match
## answers. `note_aim` and the TRANSITIONAL forwarders are not required: the
## doubles (FakeMatch) never implemented them and the callers treat that as
## "no such feature".
const REQUIRED_METHODS: Array[StringName] = [
	&"state",
	&"slot_count",
	&"slot",
	&"request_place",
	&"request_throw",
	&"request_use_gift_slot",
	&"set_cat_target",
	&"is_pose_well_formed",
	&"feed_seq",
	&"on_peer_left",
	&"on_peer_rejoined",
	&"abort_match",
	&"start_match",
	&"set_replicator",
	&"replicator",
	&"active_cat",
	&"active_slot",
	&"after_next_special",
	&"blocks_parent",
	&"circle_render_arrays",
	&"circle_wire_radius_max",
	&"circle_wire_xz_bound",
	&"countdown_remaining",
	&"default_ghost_origin",
	&"disconnect_grace_left",
	&"eliminated_by",
	&"feed_time_left",
	&"field",
	&"gift_slot_contents",
	&"gift_slot_enabled",
	&"gift_state",
	&"gift_states",
	&"glue_drops_left",
	&"glue_revision",
	&"held_shape",
	&"held_special",
	&"is_release_locked",
	&"match_timer_left",
	&"mode_state_snapshot",
	&"next_shape",
	&"next_special",
	&"qol_backlog_count",
	&"qol_timer_paused",
	&"raster",
	&"registry",
	&"stats",
	&"territory_share",
	&"weather",
]

const REQUIRED_PROPERTY: StringName = &"config"
const NOTE_AIM_METHOD: StringName = &"note_aim"
const FEED_PROPERTY: StringName = &"_feed"
const LIFECYCLE_PROPERTY: StringName = &"_lifecycle"

var _match: Object = null
var _valid: bool = false
var _has_note_aim: bool = false


func _init(match_node: Object) -> void:
	_match = match_node
	if match_node == null:
		push_error("MatchHostPort: the adapted match object is null")
		return
	var missing: Array[StringName] = []
	for method_name: StringName in REQUIRED_METHODS:
		if not match_node.has_method(method_name):
			missing.append(method_name)
	if not _has_property(match_node, REQUIRED_PROPERTY):
		missing.append(REQUIRED_PROPERTY)
	_has_note_aim = match_node.has_method(NOTE_AIM_METHOD)
	if not missing.is_empty():
		push_error("MatchHostPort: %s lacks %s" % [_describe(match_node), missing])
		return
	_valid = true


## True when the adapted object has every REQUIRED_METHODS entry and `config`.
func is_valid() -> bool:
	return _valid


# --- rule entry points and intents ------------------------------------------

## Match.config, the running match's sanitized config (null in the lobby).
func config() -> MatchConfig:
	return _match.get(REQUIRED_PROPERTY) as MatchConfig


func state() -> int:
	return int(_match.call(&"state"))


func slot_count() -> int:
	return int(_match.call(&"slot_count"))


func slot(slot_id: int) -> PlayerSlot:
	return _match.call(&"slot", slot_id) as PlayerSlot


## The refusal reason (PlacementRules.REASON_OK, &"", when accepted).
func request_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq_value: int
) -> StringName:
	return StringName(_match.call(&"request_place", slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq_value))


func request_throw(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq_value: int
) -> StringName:
	return StringName(_match.call(&"request_throw", slot_id, origin, orientation_index, free_quat, velocity, feed_seq_value))


func request_use_gift_slot(slot_id: int) -> bool:
	return bool(_match.call(&"request_use_gift_slot", slot_id))


func set_cat_target(slot_id: int, point: Vector3) -> bool:
	return bool(_match.call(&"set_cat_target", slot_id, point))


## Records a slot's last aim. A match object without note_aim (a test double)
## ignores it, exactly as MatchNet's has_method guard did.
func note_aim(slot_id: int, aim: Vector3) -> void:
	if _has_note_aim:
		_match.call(NOTE_AIM_METHOD, slot_id, aim)


func is_pose_well_formed(origin: Vector3, orientation_index: int, free_quat: Quaternion) -> bool:
	return bool(_match.call(&"is_pose_well_formed", origin, orientation_index, free_quat))


func feed_seq(slot_id: int) -> int:
	return int(_match.call(&"feed_seq", slot_id))


func on_peer_left(slot_id: int) -> void:
	_match.call(&"on_peer_left", slot_id)


func on_peer_rejoined(slot_id: int) -> void:
	_match.call(&"on_peer_rejoined", slot_id)


func abort_match() -> void:
	_match.call(&"abort_match")


func start_match(match_config: MatchConfig) -> void:
	_match.call(&"start_match", match_config)


## Installs the replication membrane (null turns replication off).
func set_replicator(replicator_node: Variant) -> void:
	_match.call(&"set_replicator", replicator_node)


## The installed membrane, so MatchNet can release it on exit without reading
## Match's private `_replicator`.
func replicator() -> Variant:
	return _match.call(&"replicator")


# --- reads ---------------------------------------------------------------------

func active_cat() -> RigidBody3D:
	return _match.call(&"active_cat") as RigidBody3D


func active_slot() -> int:
	return int(_match.call(&"active_slot"))


func after_next_special(slot_id: int) -> StringName:
	return StringName(_match.call(&"after_next_special", slot_id))


func blocks_parent() -> Node3D:
	return _match.call(&"blocks_parent") as Node3D


func circle_render_arrays() -> Dictionary:
	return _match.call(&"circle_render_arrays") as Dictionary


func circle_wire_radius_max() -> float:
	return float(_match.call(&"circle_wire_radius_max"))


func circle_wire_xz_bound() -> float:
	return float(_match.call(&"circle_wire_xz_bound"))


func countdown_remaining() -> float:
	return float(_match.call(&"countdown_remaining"))


func default_ghost_origin(slot_id: int) -> Vector3:
	return _match.call(&"default_ghost_origin", slot_id) as Vector3


func disconnect_grace_left(slot_id: int) -> float:
	return float(_match.call(&"disconnect_grace_left", slot_id))


func eliminated_by(slot_id: int) -> int:
	return int(_match.call(&"eliminated_by", slot_id))


func feed_time_left(slot_id: int) -> float:
	return float(_match.call(&"feed_time_left", slot_id))


func field() -> FieldBody:
	return _match.call(&"field") as FieldBody


func gift_slot_contents(slot_id: int) -> Array[StringName]:
	return _match.call(&"gift_slot_contents", slot_id) as Array[StringName]


func gift_slot_enabled() -> bool:
	return bool(_match.call(&"gift_slot_enabled"))


func gift_state(gift_id: int) -> Dictionary:
	return _match.call(&"gift_state", gift_id) as Dictionary


func gift_states() -> Array[Dictionary]:
	return _match.call(&"gift_states") as Array[Dictionary]


func glue_drops_left(slot_id: int) -> int:
	return int(_match.call(&"glue_drops_left", slot_id))


func glue_revision(slot_id: int) -> int:
	return int(_match.call(&"glue_revision", slot_id))


func held_shape(slot_id: int) -> BlockShape:
	return _match.call(&"held_shape", slot_id) as BlockShape


func held_special(slot_id: int) -> StringName:
	return StringName(_match.call(&"held_special", slot_id))


func is_release_locked(slot_id: int) -> bool:
	return bool(_match.call(&"is_release_locked", slot_id))


func match_timer_left() -> float:
	return float(_match.call(&"match_timer_left"))


func mode_state_snapshot() -> Dictionary:
	return _match.call(&"mode_state_snapshot") as Dictionary


func next_shape(slot_id: int) -> BlockShape:
	return _match.call(&"next_shape", slot_id) as BlockShape


func next_special(slot_id: int) -> StringName:
	return StringName(_match.call(&"next_special", slot_id))


func qol_backlog_count(slot_id: int) -> int:
	return int(_match.call(&"qol_backlog_count", slot_id))


func qol_timer_paused(slot_id: int) -> bool:
	return bool(_match.call(&"qol_timer_paused", slot_id))


func raster() -> TerritoryRaster:
	return _match.call(&"raster") as TerritoryRaster


func registry() -> Node:
	return _match.call(&"registry") as Node


## The per-slot stats object (MatchStats): build_live_payload() and
## apply_live_snapshot() are called on it directly by the replication nodes.
func stats() -> RefCounted:
	return _match.call(&"stats") as RefCounted


func territory_share(team_id: int) -> float:
	return float(_match.call(&"territory_share", team_id))


func weather() -> RefCounted:
	return _match.call(&"weather") as RefCounted


# --- TRANSITIONAL: Match's private feed / lifecycle collaborators -----------------

## Whether `shape_id` names a known block shape (MatchFeed._shape_by_id is not
## null). False when there is no feed.
func feed_knows_shape(shape_id: StringName) -> bool:
	var feed: Object = _collaborator(FEED_PROPERTY)
	if feed == null:
		return false
	return feed.call(&"_shape_by_id", shape_id) != null


func feed_claim_carrier_shape_id(slot_id: int) -> StringName:
	var feed: Object = _collaborator(FEED_PROPERTY)
	if feed == null:
		return &""
	return StringName(feed.call(&"claim_carrier_shape_id", slot_id))


func feed_gift_after_next_active() -> bool:
	var feed: Object = _collaborator(FEED_PROPERTY)
	if feed == null:
		return false
	return bool(feed.call(&"gift_after_next_active"))


func feed_staged_gift_shape_id(slot_id: int) -> StringName:
	var feed: Object = _collaborator(FEED_PROPERTY)
	if feed == null:
		return &""
	return StringName(feed.call(&"staged_gift_shape_id", slot_id))


## QoL: a triggered special freezes block timers. No-op without a feed.
func feed_note_special_triggered() -> void:
	var feed: Object = _collaborator(FEED_PROPERTY)
	if feed != null:
		feed.call(&"note_special_triggered")


## MatchLifecycle.is_starting_match(). False when there is no lifecycle.
func is_starting_match() -> bool:
	var lifecycle: Object = _collaborator(LIFECYCLE_PROPERTY)
	if lifecycle == null:
		return false
	return bool(lifecycle.call(&"is_starting_match"))


## MatchLifecycle.loading_gate_replay_args(); empty without a lifecycle.
func loading_gate_replay_args() -> Array:
	var lifecycle: Object = _collaborator(LIFECYCLE_PROPERTY)
	if lifecycle == null:
		return []
	return lifecycle.call(&"loading_gate_replay_args") as Array


func _collaborator(property_name: StringName) -> Object:
	return _match.get(property_name) as Object


static func _has_property(node: Object, property_name: StringName) -> bool:
	for property: Dictionary in node.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


static func _describe(node: Object) -> String:
	var script: Script = node.get_script() as Script
	if script != null and not script.resource_path.is_empty():
		return script.resource_path
	return node.get_class()
