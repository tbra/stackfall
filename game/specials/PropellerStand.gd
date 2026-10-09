class_name PropellerStand
extends Node3D
## Standalone propeller entrance (Bontago-1pi.85.45, docs/GIFT_PLAYTEST3_PLAN.md P1):
## the propeller activates where the gift is dropped, with no falling carrier. It rises
## out of the disc over `emerge_s`, keeps spinning, and sinks back for the last
## `sink_s`. The host stand also runs the disc blow (DiscForce sign -1) every physics
## tick for `disc_force.duration_s`, then frees itself. Clients build the same visual
## only (GiftFxPresenter -> build_client_visual) and no force; they receive the tilt
## through the normal host-authoritative field state.
##
## Parented under the Field like VolcanoStructure so the model rides the tilting disc.
## Keeps its own clock; PropellerEffect (a shared Resource) holds no state.

const PROPELLER_ID: StringName = &"propeller"
## Floor for the rise/sink durations (avoids a divide by zero).
const MIN_PHASE_S: float = 0.001
## DiscForce sign: the propeller raises the side it stands on (the Anvil in reverse).
const RAISE_SIGN: float = -1.0

var _effect: PropellerEffect = null
var _physics: bool = false
var _age: float = 0.0
var _visual: Node3D = null
var _visual_scale: float = 1.0
## Set when spawned into a match world: the stand frees itself once the match is no
## longer live (ended or restarted).
var bind_to_match: bool = false


## Host spawn: visual plus the disc blow. Null without a field, an effect or a finite point.
static func spawn_host(effect: PropellerEffect, world_position: Vector3) -> PropellerStand:
	return _spawn(effect, world_position, true)


## Client visual: no force. Null on the host (its own stand already draws it).
static func build_client_visual(effect: PropellerEffect, world_position: Vector3) -> PropellerStand:
	if MatchContext.current().has_authority():
		return null
	return _spawn(effect, world_position, false)


static func _spawn(effect: PropellerEffect, world_position: Vector3, physics: bool) -> PropellerStand:
	var field: FieldBody = MatchContext.current().field()
	if effect == null or field == null or not world_position.is_finite() or not field.is_inside_tree():
		return null
	var stand: PropellerStand = PropellerStand.new()
	stand.configure(effect, physics)
	stand.bind_to_match = true
	field.add_child(stand)
	stand.global_position = world_position
	return stand


func configure(effect: PropellerEffect, physics: bool) -> void:
	_effect = effect
	_physics = physics
	var def: SpecialDef = SpecialDef.find_by_id(PROPELLER_ID)
	_visual_scale = def.activation_scale if def != null else 1.0


func _ready() -> void:
	if _effect == null:
		return
	_visual = GiftModelTable.shared().build_gift_visual(PROPELLER_ID, true)
	if _visual == null:
		_visual = Node3D.new()
	_visual.scale = Vector3.ONE * _visual_scale
	add_child(_visual)
	_apply_height()


func has_force() -> bool:
	return _physics


func visual() -> Node3D:
	return _visual


func is_expired() -> bool:
	return _effect == null or _age >= _effect.disc_force.duration_s


## Visual height (m) of the model's rest point relative to the surface, `age_s` into
## the effect: -start_depth_m (hidden) -> +emerge_height_m over emerge_s, then back down
## over the last sink_s of the duration.
func height_at(age_s: float) -> float:
	if _effect == null:
		return 0.0
	var up: float = smoothstep(0.0, 1.0, age_s / maxf(_effect.emerge_s, MIN_PHASE_S))
	var sink_start_s: float = _effect.disc_force.duration_s - _effect.sink_s
	var down: float = smoothstep(0.0, 1.0, (age_s - sink_start_s) / maxf(_effect.sink_s, MIN_PHASE_S))
	var level: float = up * (1.0 - down)
	return lerpf(-_effect.start_depth_m, _effect.emerge_height_m, level)


func _physics_process(delta: float) -> void:
	tick(delta)


func _match_is_live() -> bool:
	return MatchPhase.is_live(MatchContext.current().state())


## One simulation step; public so tests drive it without the physics loop.
func tick(delta: float) -> void:
	if _effect == null or (bind_to_match and not _match_is_live()):
		queue_free()
		return
	if _physics and not is_expired():
		DiscForce.apply(MatchContext.current().field(), global_position, RAISE_SIGN, _effect.disc_force, delta)
	_age += delta
	if is_expired():
		queue_free()
		return
	_apply_height()


func _apply_height() -> void:
	if _visual != null:
		_visual.position.y = height_at(_age)
