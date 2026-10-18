class_name PropellerStand
extends Node3D
## Standalone Propeller entrance (the gift id stays `propeller`; its look is a party
## balloon): it activates where the gift is dropped, with no falling carrier. A team-colour
## balloon (BalloonRig) is clipped to the disc at the drop point, inflates over `inflate_s`,
## rises to the end of its string over `rise_s`, and POPs when the blow ends. The host stand
## also runs the disc blow (DiscForce sign -1) every physics tick for
## `disc_force.duration_s`, then frees itself. Clients build the same visual only
## (GiftFxPresenter -> build_client_visual) and no force; they receive the tilt through the
## normal host-authoritative field state.
##
## Phases (`phase_at`): INFLATE -> RISE -> HOLD -> POPPED. At expiry the rig is handed to
## the Field to play the pop (confetti, falling rag) and frees itself.
##
## Parented under the Field like VolcanoStructure so the balloon rides the tilting disc.
## Keeps its own clock; PropellerEffect (a shared Resource) holds no state.

const PROPELLER_ID: StringName = &"propeller"
## Floor for the phase durations (avoids a divide by zero).
const MIN_PHASE_S: float = 0.001
## DiscForce sign: the balloon raises the side it stands on (the Anvil in reverse).
const RAISE_SIGN: float = -1.0

## The balloon's life, in order.
enum Phase { INFLATE, RISE, HOLD, POPPED }

var _effect: PropellerEffect = null
var _physics: bool = false
var _owner_slot: int = -1
var _shape_seed: int = 0
var _age: float = 0.0
var _rig: BalloonRig = null
## Set when spawned into a match world: the stand frees itself once the match is no
## longer live (ended or restarted).
var bind_to_match: bool = false


## Host spawn: visual plus the disc blow. Null without a field, an effect or a finite point.
## `owner_slot` picks the balloon colour (-1: the fallback colour).
static func spawn_host(effect: PropellerEffect, world_position: Vector3, owner_slot: int = -1) -> PropellerStand:
	return _spawn(effect, world_position, true, owner_slot)


## Client visual: no force. Null on the host (its own stand already draws it).
static func build_client_visual(effect: PropellerEffect, world_position: Vector3, owner_slot: int = -1) -> PropellerStand:
	if MatchContext.current().has_authority():
		return null
	return _spawn(effect, world_position, false, owner_slot)


static func _spawn(effect: PropellerEffect, world_position: Vector3, physics: bool, owner_slot: int) -> PropellerStand:
	var field: FieldBody = MatchContext.current().field()
	if effect == null or field == null or not world_position.is_finite() or not field.is_inside_tree():
		return null
	var stand: PropellerStand = PropellerStand.new()
	stand.configure(effect, physics, owner_slot, seed_for(world_position))
	stand.bind_to_match = true
	field.add_child(stand)
	stand.global_position = world_position
	return stand


## The confetti seed for a stand spawned at `world_position`.
static func seed_for(world_position: Vector3) -> int:
	return hash(world_position)


## `shape_seed` varies the confetti (set before add_child, as the global position is only
## written afterwards).
func configure(effect: PropellerEffect, physics: bool, owner_slot: int = -1, shape_seed: int = 0) -> void:
	_shape_seed = shape_seed
	_effect = effect
	_physics = physics
	_owner_slot = owner_slot


func _ready() -> void:
	if _effect == null or _effect.fx == null:
		return
	_rig = BalloonRig.new()
	add_child(_rig)
	_rig.setup(_effect.fx, _team_color(), _shape_seed)
	_apply_pose()


func _team_color() -> Color:
	return MatchContext.current().slot_color(_owner_slot, _effect.fx.fallback_color)


func is_expired() -> bool:
	return phase_at(_age) == Phase.POPPED


## The balloon phase `age_s` into the effect.
func phase_at(age_s: float) -> Phase:
	if _effect == null or age_s >= _effect.disc_force.duration_s:
		return Phase.POPPED
	if age_s < _effect.inflate_s:
		return Phase.INFLATE
	if age_s < _effect.inflate_s + _effect.rise_s:
		return Phase.RISE
	return Phase.HOLD


## Knot height (m) above the clip, `age_s` into the effect: 0 while inflating, then up to
## the string length over `rise_s` (smoothstepped).
func height_at(age_s: float) -> float:
	if _effect == null:
		return 0.0
	var up: float = smoothstep(0.0, 1.0, (age_s - _effect.inflate_s) / maxf(_effect.rise_s, MIN_PHASE_S))
	return _effect.string_length_m * up


## Inflate progress 0..1 `age_s` into the effect.
func inflate_at(age_s: float) -> float:
	if _effect == null:
		return 0.0
	return clampf(age_s / maxf(_effect.inflate_s, MIN_PHASE_S), 0.0, 1.0)


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
		_pop_and_free()
		return
	_apply_pose()


## The blow is over: the balloon pops. The rig moves to the Field to play the pop out
## (confetti, the rag falling), then frees itself; the stand is done.
func _pop_and_free() -> void:
	if _rig != null and is_instance_valid(_rig) and is_inside_tree():
		var field_parent: Node = get_parent()
		var rig_transform: Transform3D = _rig.global_transform
		remove_child(_rig)
		field_parent.add_child(_rig)
		_rig.global_transform = rig_transform
		_rig.begin_pop()
		_rig = null
	queue_free()


func _apply_pose() -> void:
	if _rig == null:
		return
	var rise: float = height_at(_age) / maxf(_effect.string_length_m, MIN_PHASE_S)
	_rig.pose(height_at(_age), inflate_at(_age), rise, _age)
