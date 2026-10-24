class_name GiftWireGuard
extends RefCounted
## Client gift wire state and id checks (interface stub: bodies land with the MatchNet cut).
## Replaces MatchNet's gift wire phases and special-id roster check and the applier's copy.

const NOT_IMPLEMENTED: String = "GiftWireGuard: not implemented"

## First build and every rebind: refreshes the refs, KEEPS the phase/notified state.
@warning_ignore("unused_parameter")
func bind(host: MatchHostPort, config: NetConfig) -> void:
	push_error(NOT_IMPLEMENTED)


## WireLimits.special_id_ok AND (SpecialIds.PENDING OR a roster member).
@warning_ignore("unused_parameter")
func special_id_ok(special_id: StringName) -> bool:
	push_error(NOT_IMPLEMENTED)
	return false


## Check-and-mark transitions: false = refuse the event, state unchanged.
## Unknown or SPAWN_ONLY -> FALLING.
@warning_ignore("unused_parameter")
func begin_flight(gift_id: int) -> bool:
	push_error(NOT_IMPLEMENTED)
	return false


## FALLING -> LANDED.
@warning_ignore("unused_parameter")
func land(gift_id: int) -> bool:
	push_error(NOT_IMPLEMENTED)
	return false


## Not yet notified, finite and inside the field, phase not SPAWN_ONLY/LANDED/REMOVED.
@warning_ignore("unused_parameter")
func note_spawn(gift_id: int, position: Vector2) -> bool:
	push_error(NOT_IMPLEMENTED)
	return false


## gift_id >= 0 and not REMOVED -> REMOVED.
@warning_ignore("unused_parameter")
func remove(gift_id: int) -> bool:
	push_error(NOT_IMPLEMENTED)
	return false


## Match boundary.
func reset() -> void:
	push_error(NOT_IMPLEMENTED)
