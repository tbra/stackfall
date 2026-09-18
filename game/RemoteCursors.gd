class_name RemoteCursors
extends Node3D
## Other players' held blocks (spec 3.4: "update_cursor(pos): unreliable,
## 15 Hz. Only used to show other players' ghosts").
##
## One GhostPreview per non-local slot, created the first time that slot's
## cursor arrives and kept in this subtree for the rest of the match. It reads
## the Events bus only — Events.remote_cursor_updated for the pose,
## Events.feed_block_issued for the shape, Events.player_eliminated and
## Events.match_state_changed for when to stop drawing — so it needs no node
## path out of itself and no idea which transport is underneath.
##
## It is pure presentation: nothing here validates, tints by territory or
## sends anything. A remote ghost is other people's intention, not a
## placement, and the host's answer arrives as a real block either way.

@export var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")

## slot_id -> GhostPreview.
var _ghosts: Dictionary = {}

## DECISION (game/RemoteCursors.gd): the same Net seam the rest of P3 uses,
## for the same reason (GUT cannot double an autoload). null is the real Net.
var _session_provider: Variant = null
var _match_provider: Variant = null

var _shapes_by_id: Dictionary = {}


func _ready() -> void:
	Events.remote_cursor_updated.connect(_on_remote_cursor_updated)
	Events.feed_block_issued.connect(_on_feed_block_issued)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.match_state_changed.connect(_on_match_state_changed)


func set_providers(session_provider: Variant, match_provider: Variant) -> void:
	_session_provider = session_provider
	_match_provider = match_provider


func _session() -> Variant:
	return _session_provider if _session_provider != null else Net


func _authority() -> Variant:
	return _match_provider if _match_provider != null else Match


## The ghost drawn for `slot_id`, or null when that slot has none — this
## instance's own slot never gets one, and neither does a slot that has not
## moved its cursor yet.
func ghost_for_slot(slot_id: int) -> GhostPreview:
	return _ghosts.get(slot_id) as GhostPreview


func tracked_slot_count() -> int:
	return _ghosts.size()


## Drops every remote ghost. Called when a match ends.
func clear() -> void:
	for slot_id: Variant in _ghosts.keys():
		var ghost: GhostPreview = _ghosts[slot_id]
		if is_instance_valid(ghost):
			ghost.queue_free()
	_ghosts.clear()


func _on_remote_cursor_updated(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion
) -> void:
	if bool(_session().is_local_slot(slot_id)):
		# The local player already has a ghost of their own, drawn from their
		# own input with no interpolation delay at all.
		return
	var ghost: GhostPreview = _ensure_ghost(slot_id)
	if ghost == null:
		return
	# free_quaternion first: set_orientation_index() re-applies the basis from
	# both, so setting the index last is what makes one pose out of the two.
	ghost.free_quaternion = free_quat
	ghost.set_orientation_index(orientation_index)
	# DECISION (game/RemoteCursors.gd): spec 3.4's update_cursor carries a
	# position, not the surface it was raycast against, so a remote ghost's
	# drop shadow and guide line are drawn straight down from it rather than
	# onto whatever it is really hovering over. Going through
	# update_placement() (rather than writing global_position) is what keeps
	# those two children with the ghost at all; subtracting the hover first
	# lands the ghost on exactly the position the sender reported.
	var hover: float = ghost.tuning.hover_height + ghost.manual_hover_offset
	ghost.update_placement(origin - Vector3.UP * hover, Vector3.UP)


func _on_feed_block_issued(slot_id: int, shape_id: StringName, _next_shape_id: StringName) -> void:
	var ghost: GhostPreview = ghost_for_slot(slot_id)
	if ghost == null:
		return
	var shape: BlockShape = _shape_for_id(shape_id)
	if shape != null:
		ghost.set_shape(shape)


func _on_player_eliminated(slot_id: int, _team_id: int) -> void:
	var ghost: GhostPreview = ghost_for_slot(slot_id)
	if ghost == null:
		return
	ghost.queue_free()
	_ghosts.erase(slot_id)


func _on_match_state_changed(_from_state: int, to_state: int) -> void:
	if to_state == Match.State.LOBBY or to_state == Match.State.END:
		clear()


func _ensure_ghost(slot_id: int) -> GhostPreview:
	var existing: GhostPreview = ghost_for_slot(slot_id)
	if existing != null and is_instance_valid(existing):
		return existing

	var ghost: GhostPreview = GhostPreview.new()
	ghost.name = "RemoteGhost%d" % slot_id
	add_child(ghost)
	_ghosts[slot_id] = ghost

	var slot: PlayerSlot = _authority().slot(slot_id)
	if slot != null:
		ghost.set_player_color(slot.color)
	var held: BlockShape = _authority().held_shape(slot_id)
	if held != null:
		ghost.set_shape(held)
	# Someone else's ghost is always drawn as valid: only the host knows
	# whether their spot is, and telling every player about every other
	# player's territory check would be both noisy and a small information
	# leak in a game about walling people in.
	ghost.apply_validity(PlacementRules.Result.VALID)
	return ghost


func _shape_for_id(shape_id: StringName) -> BlockShape:
	if _shapes_by_id.is_empty():
		for shape: BlockShape in BlockShape.load_all_shapes():
			_shapes_by_id[shape.id] = shape
	return _shapes_by_id.get(shape_id) as BlockShape
