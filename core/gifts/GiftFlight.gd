class_name GiftFlight
extends RefCounted
## One gift crate's host-authored flight record (replaces the untyped dictionary of
## MatchGifts._crates). Pure data and maths, no scene tree.

## Floor for the fall speed so a zero config never divides by zero.
const MIN_FALL_SPEED_M_S: float = 0.001
## Golden angle: spreads each crate's sway phase by id.
const SWAY_PHASE_PER_ID: float = 2.39996323
const SWAY_Z_FREQUENCY_RATIO: float = 0.73
const SWAY_Z_PHASE: float = 0.8

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
func advance_fall(delta: float, config: GiftConfig) -> float:
	var distance: float = origin.distance_to(landing)
	elapsed += delta
	return 1.0 if distance <= 0.0 else minf(elapsed * maxf(config.fall_speed_m_s, MIN_FALL_SPEED_M_S) / distance, 1.0)


## Crate position at `progress`: origin at <= 0, landing at >= 1, swaying between. Height stays
## linear, and sway fades to the exact landing point.
func world_position(config: GiftConfig, progress: float) -> Vector3:
	if progress <= 0.0:
		return origin
	if progress >= 1.0:
		return landing
	var straight: Vector3 = origin.lerp(landing, progress)
	var amplitude: float = maxf(config.sway_amplitude_m, 0.0) * sin(PI * progress)
	var angle: float = TAU * maxf(config.sway_frequency_hz, 0.0) * elapsed + float(gift_id) * SWAY_PHASE_PER_ID
	return straight + Vector3(sin(angle), 0.0, sin(angle * SWAY_Z_FREQUENCY_RATIO + SWAY_Z_PHASE)) * amplitude


## Marks the crate LANDED at `at` with age 0.
func land(at: Vector3) -> void:
	phase = GiftWirePhase.LANDED
	landing = at
	age = 0.0


## The copy safe for minimap and network consumers (the shape MatchGifts.gift_state returns).
func snapshot() -> Dictionary:
	return {"id": gift_id, "phase": phase, "position": position, "origin": origin,
		"landing": landing, "elapsed": elapsed, "landed_age": age}
