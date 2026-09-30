class_name StackfallRain
extends Node
## One Stackfall activation. The host chooses seeded positions and sends each
## ordinary block through Match's existing registry and snapshot spawn path.

var owner_slot: int = -1
var attempted: int = 0
var spawned: int = 0
var _count: int = 0
var _rate: float = 1.0
var _radius: float = 1.0
var _height: float = 1.0
var _spacing: float = 0.0
var _position_attempts: int = 1
var _body_cap: int = 600
var _center: Vector2 = Vector2.ZERO
var _shape: BlockShape = null
var _elapsed: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _positions: Array[Vector2] = []


func bind(
	slot_id: int, center: Vector2, seed_value: int, shape: BlockShape,
	count: int, rate: float, radius: float, height: float, spacing: float,
	position_attempts: int, body_cap: int
) -> void:
	owner_slot = slot_id
	_center = center
	_rng.seed = seed_value
	_shape = shape
	_count = maxi(count, 0)
	_rate = maxf(rate, 0.1)
	_radius = maxf(radius, 0.0)
	_height = maxf(height, 0.0)
	_spacing = maxf(spacing, 0.0)
	_position_attempts = maxi(position_attempts, 1)
	_body_cap = maxi(body_cap, 1)


func _ready() -> void:
	Events.match_state_changed.connect(_on_match_state_changed)


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not Match._is_host() or Match.state() != Match.State.PLAYING:
		queue_free()
		return
	_elapsed += maxf(delta, 0.0)
	var due: int = mini(_count, int(floor(_elapsed * _rate)))
	while attempted < due:
		attempted += 1
		_spawn_one()
	if attempted >= _count:
		queue_free()


func _spawn_one() -> void:
	var field: Field = Match.field()
	var blocks: Node3D = Match.blocks_parent()
	if field == null or blocks == null or _shape == null or blocks.get_child_count() >= _body_cap:
		return
	var point: Vector2 = _sample_position(field.map_def)
	if not point.is_finite():
		return
	var origin: Vector3 = field.world_from_disk_local(point, _height)
	var placed: Block = Match.spawn_special_projectile(
		_shape, origin, Basis.IDENTITY, owner_slot, Vector3.ZERO, null, null
	)
	if placed != null:
		_positions.append(point)
		spawned += 1


func _sample_position(map_def: MapDef) -> Vector2:
	for _i: int in range(_position_attempts):
		var angle: float = _rng.randf_range(0.0, TAU)
		var radius: float = sqrt(_rng.randf()) * _radius
		var point: Vector2 = _center + Vector2(cos(angle), sin(angle)) * radius
		if not map_def.shape_contains(point):
			continue
		var separated: bool = true
		for prior: Vector2 in _positions:
			if prior.distance_to(point) < _spacing:
				separated = false
				break
		if separated:
			return point
	return Vector2.INF


func _on_match_state_changed(_old_state: int, new_state: int) -> void:
	if new_state == Match.State.LOBBY or new_state == Match.State.END:
		queue_free()
