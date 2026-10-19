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

const _NO_STRINGS: Array[StringName] = []
const _NO_DICTS: Array[Dictionary] = []

var _match: Object = null
var _valid: bool = false
var _has_note_aim: bool = false
var _bound: Dictionary = {}
var _reported: Dictionary = {}


## `required` is the subset of REQUIRED_METHODS (plus `config`, the property) the
## consumer actually calls (empty = all of them); a name that is neither makes the
## port invalid. See SessionPort.
func _init(match_node: Object, required: PackedStringArray = PackedStringArray()) -> void:
	_match = match_node
	if match_node == null:
		push_error("MatchHostPort: the adapted match object is null")
		return
	var wanted: Array[StringName] = _wanted(required)
	var unknown: Array[StringName] = []
	var missing: Array[StringName] = []
	for name_wanted: StringName in wanted:
		if name_wanted == REQUIRED_PROPERTY:
			if not _has_property(match_node, REQUIRED_PROPERTY):
				missing.append(name_wanted)
		elif not REQUIRED_METHODS.has(name_wanted):
			unknown.append(name_wanted)
		elif not match_node.has_method(name_wanted):
			missing.append(name_wanted)
	_has_note_aim = match_node.has_method(NOTE_AIM_METHOD)
	if not unknown.is_empty():
		push_error("MatchHostPort: %s is not a port method: %s" % [_describe(match_node), unknown])
		return
	if not missing.is_empty():
		push_error("MatchHostPort: %s lacks %s" % [_describe(match_node), missing])
		return
	for name_wanted: StringName in wanted:
		_bound[name_wanted] = true
	_valid = true


## True when the adapted object has every method the port was bound to.
func is_valid() -> bool:
	return _valid


# --- rule entry points and intents ------------------------------------------

## Match.config, the running match's sanitized config (null in the lobby).
func config() -> MatchConfig:
	if not _bound.has(REQUIRED_PROPERTY) and (_match == null or not _has_property(_match, REQUIRED_PROPERTY)):
		_report_missing(REQUIRED_PROPERTY)
		return null
	_bound[REQUIRED_PROPERTY] = true
	return _match.get(REQUIRED_PROPERTY) as MatchConfig


func state() -> int:
	return int(_call(&"state", [], 0))


func slot_count() -> int:
	return int(_call(&"slot_count", [], 0))


func slot(slot_id: int) -> PlayerSlot:
	return _call(&"slot", [slot_id], null) as PlayerSlot


## The refusal reason (PlacementRules.REASON_OK, &"", when accepted).
func request_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq_value: int
) -> StringName:
	return StringName(_call(&"request_place", [slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq_value], &""))


func request_throw(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq_value: int
) -> StringName:
	return StringName(_call(&"request_throw", [slot_id, origin, orientation_index, free_quat, velocity, feed_seq_value], &""))


func request_use_gift_slot(slot_id: int) -> bool:
	return bool(_call(&"request_use_gift_slot", [slot_id], false))


func set_cat_target(slot_id: int, point: Vector3) -> bool:
	return bool(_call(&"set_cat_target", [slot_id, point], false))


## Records a slot's last aim. A match object without note_aim (a test double)
## ignores it, exactly as MatchNet's has_method guard did.
func note_aim(slot_id: int, aim: Vector3) -> void:
	if _has_note_aim:
		_match.call(NOTE_AIM_METHOD, slot_id, aim)


func is_pose_well_formed(origin: Vector3, orientation_index: int, free_quat: Quaternion) -> bool:
	return bool(_call(&"is_pose_well_formed", [origin, orientation_index, free_quat], false))


func feed_seq(slot_id: int) -> int:
	return int(_call(&"feed_seq", [slot_id], 0))


func on_peer_left(slot_id: int) -> void:
	_call(&"on_peer_left", [slot_id], null)


func on_peer_rejoined(slot_id: int) -> void:
	_call(&"on_peer_rejoined", [slot_id], null)


func abort_match() -> void:
	_call(&"abort_match", [], null)


func start_match(match_config: MatchConfig) -> void:
	_call(&"start_match", [match_config], null)


## Installs the replication membrane (null turns replication off).
func set_replicator(replicator_node: Variant) -> void:
	_call(&"set_replicator", [replicator_node], null)


## The installed membrane, so MatchNet can release it on exit without reading
## Match's private `_replicator`.
func replicator() -> Variant:
	return _call(&"replicator", [], null)


# --- reads ---------------------------------------------------------------------

func active_cat() -> RigidBody3D:
	return _call(&"active_cat", [], null) as RigidBody3D


func active_slot() -> int:
	return int(_call(&"active_slot", [], -1))


func after_next_special(slot_id: int) -> StringName:
	return StringName(_call(&"after_next_special", [slot_id], &""))


func blocks_parent() -> Node3D:
	return _call(&"blocks_parent", [], null) as Node3D


func circle_render_arrays() -> Dictionary:
	return _call(&"circle_render_arrays", [], {}) as Dictionary


func circle_wire_radius_max() -> float:
	return float(_call(&"circle_wire_radius_max", [], 0.0))


func circle_wire_xz_bound() -> float:
	return float(_call(&"circle_wire_xz_bound", [], 0.0))


func countdown_remaining() -> float:
	return float(_call(&"countdown_remaining", [], 0.0))


func default_ghost_origin(slot_id: int) -> Vector3:
	return _call(&"default_ghost_origin", [slot_id], Vector3.ZERO) as Vector3


func disconnect_grace_left(slot_id: int) -> float:
	return float(_call(&"disconnect_grace_left", [slot_id], 0.0))


func eliminated_by(slot_id: int) -> int:
	return int(_call(&"eliminated_by", [slot_id], -1))


func feed_time_left(slot_id: int) -> float:
	return float(_call(&"feed_time_left", [slot_id], 0.0))


func field() -> FieldBody:
	return _call(&"field", [], null) as FieldBody


func gift_slot_contents(slot_id: int) -> Array[StringName]:
	return _call(&"gift_slot_contents", [slot_id], _NO_STRINGS) as Array[StringName]


func gift_slot_enabled() -> bool:
	return bool(_call(&"gift_slot_enabled", [], false))


func gift_state(gift_id: int) -> Dictionary:
	return _call(&"gift_state", [gift_id], {}) as Dictionary


func gift_states() -> Array[Dictionary]:
	return _call(&"gift_states", [], _NO_DICTS) as Array[Dictionary]


func glue_drops_left(slot_id: int) -> int:
	return int(_call(&"glue_drops_left", [slot_id], 0))


func glue_revision(slot_id: int) -> int:
	return int(_call(&"glue_revision", [slot_id], 0))


func held_shape(slot_id: int) -> BlockShape:
	return _call(&"held_shape", [slot_id], null) as BlockShape


func held_special(slot_id: int) -> StringName:
	return StringName(_call(&"held_special", [slot_id], &""))


func is_release_locked(slot_id: int) -> bool:
	return bool(_call(&"is_release_locked", [slot_id], false))


func match_timer_left() -> float:
	return float(_call(&"match_timer_left", [], 0.0))


func mode_state_snapshot() -> Dictionary:
	return _call(&"mode_state_snapshot", [], {}) as Dictionary


func next_shape(slot_id: int) -> BlockShape:
	return _call(&"next_shape", [slot_id], null) as BlockShape


func next_special(slot_id: int) -> StringName:
	return StringName(_call(&"next_special", [slot_id], &""))


func qol_backlog_count(slot_id: int) -> int:
	return int(_call(&"qol_backlog_count", [slot_id], 0))


func qol_timer_paused(slot_id: int) -> bool:
	return bool(_call(&"qol_timer_paused", [slot_id], false))


func raster() -> TerritoryRaster:
	return _call(&"raster", [], null) as TerritoryRaster


func registry() -> Node:
	return _call(&"registry", [], null) as Node


## The per-slot stats object (MatchStats): build_live_payload() and
## apply_live_snapshot() are called on it directly by the replication nodes.
func stats() -> RefCounted:
	return _call(&"stats", [], null) as RefCounted


func territory_share(team_id: int) -> float:
	return float(_call(&"territory_share", [team_id], 0.0))


func weather() -> RefCounted:
	return _call(&"weather", [], null) as RefCounted


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


## Forwards to the adapted object. A method the bind verified goes straight
## through; any other one is checked, and a missing one logs once and answers
## `fallback` (the documented default) instead of crashing.
func _call(method_name: StringName, args: Array, fallback: Variant) -> Variant:
	if _bound.has(method_name):
		return _match.callv(method_name, args)
	if _match == null or not _match.has_method(method_name):
		_report_missing(method_name)
		return fallback
	_bound[method_name] = true
	return _match.callv(method_name, args)


func _report_missing(member: StringName) -> void:
	if _reported.has(member):
		return
	_reported[member] = true
	push_error("MatchHostPort: %s has no %s (outside the bound subset); answering the default" % [_describe(_match), member])


static func _wanted(required: PackedStringArray) -> Array[StringName]:
	var names: Array[StringName] = []
	if required.is_empty():
		names.assign(REQUIRED_METHODS)
		names.append(REQUIRED_PROPERTY)
		return names
	for entry: String in required:
		names.append(StringName(entry))
	return names


func _collaborator(property_name: StringName) -> Object:
	if _match == null:
		return null
	return _match.get(property_name) as Object


static func _has_property(node: Object, property_name: StringName) -> bool:
	for property: Dictionary in node.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


static func _describe(node: Object) -> String:
	if node == null:
		return "null"
	var script: Script = node.get_script() as Script
	if script != null and not script.resource_path.is_empty():
		return script.resource_path
	return node.get_class()
