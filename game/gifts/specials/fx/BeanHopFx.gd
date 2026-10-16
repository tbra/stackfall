class_name BeanHopFx
extends Node
## "the jumping beans jump" need an effect: a visual-only
## driver on a Jumping Bean gift carrier that marks every hop with a spring ring
## and a dust kick where the bean left the ground (and Events.bean_hopped, which
## autoload/Sfx.gd turns into the hop sound), and every landing with a dust puff
## (BeanHopFxTuning).
##
## Client-derived, like GiftBlink: started from GiftFxPresenter.on_gift_block_spawned
## on every peer and driven only by the carrier's own measured motion (position
## delta per physics tick, so it reads the same on the host's real body and a
## client's interpolated one). No RPC, no gameplay effect.
##
## A take-off is an upward speed of at least takeoff_speed_mps after the bean rested
## for rest_ticks; a throw or a bounce never rests first, so neither reads as a hop.
##
## DECISION: the carrier is typed Node3D and its gift id read by property name, so this
## file adds no compile edge back to Block (tools/lint_layers.py L2 SCC ratchet).

const DRIVER_NAME: StringName = &"BeanHopFxDriver"
const BEAN_ID: StringName = &"jumping_bean"
const DEFAULT_TUNING: BeanHopFxTuning = preload("res://config/gifts/specials/fx/bean_hop_fx_tuning.tres")
const GIFT_ID_PROPERTY: StringName = &"gift_id"

var tuning: BeanHopFxTuning = DEFAULT_TUNING
var hops: int = 0
var landings: int = 0
var _block: Node3D = null
var _prev_y: float = 0.0
var _has_prev: bool = false
var _rest_ticks: int = 0
var _fall_speed: float = 0.0
var _airborne: bool = false


## Attaches the driver to a Jumping Bean carrier (idempotent; any other gift is
## left alone). Returns whether `block` now carries a driver.
static func start_for_gift(block: Node3D) -> bool:
	if block == null or not is_instance_valid(block) or block.get(GIFT_ID_PROPERTY) != BEAN_ID:
		return false
	if block.get_node_or_null(NodePath(String(DRIVER_NAME))) != null:
		return true
	var driver: BeanHopFx = BeanHopFx.new()
	driver.name = DRIVER_NAME
	block.add_child(driver)
	return true


func _ready() -> void:
	_block = get_parent() as Node3D


func _physics_process(delta: float) -> void:
	if _block == null or not is_instance_valid(_block) or delta <= 0.0:
		return
	observe(_block.global_position.y, delta)


## One motion sample (test seam): the carrier's height `y` after `delta` seconds.
func observe(y: float, delta: float) -> void:
	if not _has_prev:
		_prev_y = y
		_has_prev = true
		return
	var vertical: float = (y - _prev_y) / delta
	_prev_y = y
	if absf(vertical) < tuning.rest_speed_mps:
		if _airborne and _fall_speed >= tuning.land_speed_mps:
			_airborne = false
			landings += 1
			_spawn_landing()
		_rest_ticks += 1
		_fall_speed = 0.0
		return
	if vertical >= tuning.takeoff_speed_mps and _rest_ticks >= tuning.rest_ticks:
		hops += 1
		_spawn_takeoff()
		_airborne = true
	elif vertical < 0.0:
		_airborne = true
		_fall_speed = maxf(_fall_speed, -vertical)
	_rest_ticks = 0


func _spawn_takeoff() -> void:
	var host: Node = _fx_parent()
	if host == null:
		return
	var ground: Vector3 = _ground_point()
	Events.bean_hopped.emit(ground)
	var ring: FxRing = FxRing.new()
	DiscAnchor.attach(ring, ground, host)
	ring.setup(tuning.ring_color, tuning.ring_radius_m, tuning.ring_width_m, tuning.ring_s)
	ring.play()
	_spawn_dust(host, ground, tuning.takeoff_dust_size_m)


func _spawn_landing() -> void:
	var host: Node = _fx_parent()
	if host != null:
		_spawn_dust(host, _ground_point(), tuning.landing_dust_size_m)


func _spawn_dust(host: Node, at: Vector3, size_m: float) -> void:
	var dust: ImpactPuff = ImpactPuff.new()
	var parent: Node = DiscAnchor.parent_for(host)
	parent.add_child(dust)
	dust.play(at, false, size_m, tuning.dust_tint, tuning.dust_alpha, tuning.dust_fps, tuning.dust_frame_count)
	dust.get_tree().create_timer(float(tuning.dust_frame_count) / maxf(tuning.dust_fps, 1.0)).timeout.connect(
		dust.queue_free
	)


## The bean's lowest visible point (its gift collider's bottom), lifted a hair.
func _ground_point() -> Vector3:
	var point: Vector3 = _block.global_position
	for child: Node in _block.get_children():
		var collider: CollisionShape3D = child as CollisionShape3D
		var box: BoxShape3D = collider.shape as BoxShape3D if collider != null else null
		if box != null:
			point = collider.global_position + Vector3.DOWN * box.size.y * 0.5
			break
	return point + Vector3.UP * tuning.ground_lift_m


## Where hop effects hang without a live Field: the carrier's own parent.
func _fx_parent() -> Node:
	return _block.get_parent() if _block.is_inside_tree() else null
