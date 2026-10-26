class_name GiftWireGuard
extends RefCounted
## Client gift wire state and id checks: which phase each crate is in on the wire, and whether a
## special id is one of ours. A refused transition leaves the state unchanged.
## DECISION: a transition is marked before the replica write instead of after it; the replica
## port's apply calls return nothing and cannot refuse, so the order is unobservable.

## A spawn position may sit this far outside the field disc (wire rounding).
const FIELD_RADIUS_SLACK: float = 0.01

var _host: MatchHostPort = null
var _config: NetConfig = null
## gift_id -> GiftWirePhase value.
var _phases: Dictionary = {}
var _spawn_notified: Dictionary = {}


## First build and every rebind: refreshes the refs, keeps the phase and notified state.
func bind(host: MatchHostPort, config: NetConfig) -> void:
	_host = host
	_config = config


## WireLimits.special_id_ok AND (SpecialIds.PENDING OR a roster member).
func special_id_ok(special_id: StringName) -> bool:
	if not WireLimits.special_id_ok(special_id, _config):
		return false
	if special_id == SpecialIds.PENDING:
		return true
	return LateScripts.script(LateScripts.SPECIAL_DEF).call(&"find_by_id", special_id) != null


## Unknown or spawn-only -> falling.
func begin_flight(gift_id: int) -> bool:
	if gift_id < 0 or (_phases.has(gift_id) and int(_phases[gift_id]) != GiftWirePhase.WIRE_SPAWN_ONLY):
		return false
	_phases[gift_id] = GiftWirePhase.FALLING
	return true


## Falling -> landed.
func land(gift_id: int) -> bool:
	if gift_id < 0 or _phases.get(gift_id, -1) != GiftWirePhase.FALLING:
		return false
	_phases[gift_id] = GiftWirePhase.LANDED
	return true


## Not yet notified, finite and inside the field, and the phase not spawn-only, landed or removed.
## An unknown gift becomes spawn-only.
func note_spawn(gift_id: int, position: Vector2) -> bool:
	if gift_id < 0 or _spawn_notified.has(gift_id) or not position.is_finite():
		return false
	var running: MatchConfig = _host.config()
	if running == null or position.length() > running.map_def().field_radius + FIELD_RADIUS_SLACK:
		return false
	if _phases.get(gift_id, -1) in [GiftWirePhase.WIRE_SPAWN_ONLY, GiftWirePhase.LANDED, GiftWirePhase.WIRE_REMOVED]:
		return false
	if not _phases.has(gift_id):
		_phases[gift_id] = GiftWirePhase.WIRE_SPAWN_ONLY
	_spawn_notified[gift_id] = true
	return true


## Any non-removed, non-negative id -> removed.
func remove(gift_id: int) -> bool:
	if gift_id < 0 or _phases.get(gift_id, -1) == GiftWirePhase.WIRE_REMOVED:
		return false
	_phases[gift_id] = GiftWirePhase.WIRE_REMOVED
	return true


## Match boundary.
func reset() -> void:
	_phases.clear()
	_spawn_notified.clear()
