class_name GiftFlight
extends RefCounted
## One gift crate's host-authored flight record (replaces the untyped dictionary of
## MatchGifts._crates). Pure data and maths, no scene tree.
## Stub revision: the bodies below are neutral until the core package fills them.

var gift_id: int = 0
## Disk-local, host-authored.
var position: Vector2 = Vector2.ZERO
var origin: Vector3 = Vector3.ZERO
var landing: Vector3 = Vector3.ZERO
## GiftWirePhase.FALLING or GiftWirePhase.LANDED.
var phase: int = GiftWirePhase.FALLING
var elapsed: float = 0.0
## Seconds spent LANDED.
var age: float = 0.0
## Client: the flight event was already applied.
var flight_received: bool = false


func _init(id: int, point: Vector2, from: Vector3, to: Vector3, start_phase: int) -> void:
	gift_id = id
	position = point
	origin = from
	landing = to
	phase = start_phase


## Advances `elapsed` by `delta` and returns the fall progress 0..1 (1.0 when origin == landing).
func advance_fall(_delta: float, _config: GiftConfig) -> float:
	return 0.0


## Crate position at `progress`: origin at <= 0, landing at >= 1, swaying between.
func world_position(_config: GiftConfig, _progress: float) -> Vector3:
	return origin


## Marks the crate LANDED at `at` with age 0.
func land(_at: Vector3) -> void:
	pass


## The copy safe for minimap and network consumers (the shape MatchGifts.gift_state returns).
func snapshot() -> Dictionary:
	return {}
