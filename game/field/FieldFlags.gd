class_name FieldFlags
extends Node3D
## The home and goal flags and the beacon body of a Field, as a child node. Field
## sets the typed properties below before add_child, then calls place(). Capture
## progress, goal control and the beacon timers follow Events by themselves.

var map_def: MapDef
var visuals: TerritoryVisuals
## Beacon friction is tuning.disk_friction.
var tuning: PhysicsTuning
var home_flag_scene: PackedScene
var goal_flag_scene: PackedScene

var _home_flags: Array[HomeFlag] = []
var _goal_flags: Array[GoalFlag] = []
var _slot_colors: PackedColorArray = PackedColorArray()
var _capture_hold_s: float = 0.0
var _timer_capture_team: int = -1
var _timer_capture_progress: float = 0.0
var _timer_mode_state: Dictionary = {}
## The last raster a control refresh saw, so a latch change can re-run it.
var _last_raster: TerritoryRaster = null
## Slot id -> PackedInt32Array of the beacon body's shape owners.
var _flag_owner_ids: Dictionary = {}
## Child body carrying every beacon's shapes; follows the field's tilt.
var _beacon_body: AnimatableBody3D = null
var _sync: bool = false


func _ready() -> void:
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.goal_capture_progress.connect(_on_goal_capture_progress)
	Events.territory_updated.connect(_on_territory_updated)
	Events.territory_replicated.connect(_refresh_goal_control)
	Events.mode_state_changed.connect(_on_mode_state_changed)


## Team/slot colours, indexed by slot. Field feeds this from place_flags and
## set_overlay_source; it takes effect at the next goal-control refresh.
func set_colors(colors: PackedColorArray) -> void:
	_slot_colors = colors


## Builds the match's flags: one home flag per slot and goal_count goal flags
## (0 for Reach the Sky / Elimination spawns none).
func place(slot_count: int, goal_count: int, goal_zone_radius: float, capture_hold_s: float, counts_up: bool) -> void:
	_capture_hold_s = capture_hold_s
	_timer_mode_state = {}
	_last_raster = null
	clear()
	for slot_id: int in range(maxi(slot_count, 0)):
		var flag: HomeFlag = home_flag_scene.instantiate() as HomeFlag
		flag.visuals = visuals
		var local: Vector2 = map_def.home_flag_position(slot_id, slot_count)
		flag.position = Vector3(local.x, 0.0, local.y)
		add_child(flag)
		flag.set_slot(slot_id, _color_for_index(slot_id))
		_home_flags.append(flag)
		_add_flag_collision(slot_id, flag)
	for local: Vector2 in PlayerSlot.goal_positions_for(goal_count, map_def):
		var flag: GoalFlag = goal_flag_scene.instantiate() as GoalFlag
		flag.visuals = visuals
		flag.position = Vector3(local.x, 0.0, local.y)
		add_child(flag)
		flag.set_claim_ring(goal_zone_radius)
		flag.set_timer_counts_up(counts_up)
		_feed_countdown(flag)
		_feed_multiplier(flag)
		_goal_flags.append(flag)


func clear() -> void:
	for slot_id: int in _flag_owner_ids.keys():
		_remove_flag_collision(slot_id)
	for flag: HomeFlag in _home_flags:
		flag.queue_free()
	for flag: GoalFlag in _goal_flags:
		flag.queue_free()
	_home_flags = []
	_goal_flags = []


func home_flags() -> Array[HomeFlag]:
	return _home_flags


func goal_flags() -> Array[GoalFlag]:
	return _goal_flags


## Mirrors the field's sync_to_physics onto the beacon body so it follows tilt.
func set_sync(on: bool) -> void:
	_sync = on
	if _beacon_body != null:
		_beacon_body.sync_to_physics = on


## A home beacon collides as extra shapes on a child AnimatableBody3D.
## DECISION: separate body on its own layer (BEACON_COLLISION_LAYER) rather than
## shape-index filtering: blocks collide with it via their mask, while the
## placement point-ray, ghost raise/shape casts, drop projection and host
## validation query PLACEMENT_QUERY_MASK and behave exactly as before beacons had
## collision.
func _ensure_beacon_body() -> AnimatableBody3D:
	if _beacon_body == null:
		_beacon_body = AnimatableBody3D.new()
		_beacon_body.name = &"BeaconBody"
		_beacon_body.collision_layer = FieldBody.BEACON_COLLISION_LAYER
		_beacon_body.collision_mask = 0
		_beacon_body.sync_to_physics = _sync
		var material: PhysicsMaterial = PhysicsMaterial.new()
		material.friction = tuning.disk_friction
		_beacon_body.physics_material_override = material
		add_child(_beacon_body)
	return _beacon_body


func _add_flag_collision(slot_id: int, flag: HomeFlag) -> void:
	var body: AnimatableBody3D = _ensure_beacon_body()
	# A shape_owner has one transform for all its shapes, so each part of the
	# compound gets its own shape_owner.
	var owners: PackedInt32Array = PackedInt32Array()
	var shapes: Array[Shape3D] = flag.collision_shapes()
	var transforms: Array[Transform3D] = flag.collision_transforms()
	for i: int in range(shapes.size()):
		var owner_id: int = body.create_shape_owner(body)
		body.shape_owner_add_shape(owner_id, shapes[i])
		body.shape_owner_set_transform(owner_id, Transform3D(Basis.IDENTITY, flag.position) * transforms[i])
		owners.append(owner_id)
	_flag_owner_ids[slot_id] = owners


func _remove_flag_collision(slot_id: int) -> void:
	if not _flag_owner_ids.has(slot_id):
		return
	for owner_id: int in (_flag_owner_ids[slot_id] as PackedInt32Array):
		_beacon_body.remove_shape_owner(owner_id)
	_flag_owner_ids.erase(slot_id)


## An eliminated slot's beacon stops colliding (its home cell opens as a hole).
func _on_player_eliminated(slot_id: int, _team_id: int) -> void:
	_remove_flag_collision(slot_id)


## Spec 1.5: "A radial progress ring appears on each goal flag while someone is
## capturing it." `progress` runs 0..1 over the capture hold; team_id -1 with
## progress 0 clears the ring.
func _on_goal_capture_progress(team_id: int, progress: float) -> void:
	var color: Color = _color_for_index(team_id)
	_timer_capture_team = team_id
	_timer_capture_progress = progress
	for goal_flag: GoalFlag in _goal_flags:
		goal_flag.set_capture(team_id, progress, color)
		_feed_countdown(goal_flag)


func _feed_countdown(flag: GoalFlag) -> void:
	if _capture_hold_s <= 0.0:
		flag.set_countdown(-1, 0.0, 0.0, Color.WHITE)
	else:
		flag.set_countdown(_timer_capture_team, _timer_capture_progress, _capture_hold_s, _color_for_index(_timer_capture_team))


func _feed_multiplier(flag: GoalFlag) -> void:
	flag.set_multiplier(BeaconTimerText.held_count_in_state(_timer_mode_state, flag.control()))


func _on_mode_state_changed(state: Dictionary) -> void:
	_timer_mode_state = state
	if _last_raster != null:
		_refresh_goal_control(_last_raster)
		return
	for flag: GoalFlag in _goal_flags:
		_feed_multiplier(flag)


func _on_territory_updated(raster: TerritoryRaster, _groups: TerritoryGroups) -> void:
	_refresh_goal_control(raster)


## Pushes each goal's controller (GoalControl, derived from the raster the host
## solved or the client mirrored) onto its beacon. Runs on host and client from
## the same raster data, so they always agree.
func _refresh_goal_control(raster: TerritoryRaster) -> void:
	_last_raster = raster
	for i: int in range(_goal_flags.size()):
		var flag: GoalFlag = _goal_flags[i]
		var point: Vector2 = Vector2(flag.position.x, flag.position.z)
		var control: int = GoalControl.owner_at(raster, point)
		# Sudden death: a latched goal shows its latch owner even when the raster says
		# neutral or contested (the latch stays with the last claimer).
		var latched: int = BeaconTimerText.latched_in_state(_timer_mode_state, i)
		if latched >= 0:
			control = latched
		var contest_colors: PackedColorArray = PackedColorArray()
		if control == GoalControl.CONTESTED:
			var teams: PackedInt32Array = GoalControl.nearby_teams(
				raster, point, flag.beacon_visuals.contested_probe_radius,
				flag.beacon_visuals.contested_probe_samples
			)
			for team: int in teams:
				contest_colors.append(_color_for_index(team))
		flag.set_control(control, _color_for_index(control) if control >= 0 else Color.WHITE, contest_colors)
		_feed_multiplier(flag)


## Slot/team colours come from set_colors(), never from a literal. The fallback
## is the goal flag's neutral colour, used before a match hands its colours over.
func _color_for_index(index: int) -> Color:
	if index < 0 or index >= _slot_colors.size():
		return visuals.goal_flag_color
	return _slot_colors[index]
