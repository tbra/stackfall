class_name LocalHeldView
extends RefCounted
## The local player's held-piece pose, published by the player controller each frame and read by
## the HUD, the perching birds and the gift presenters through MatchContext.local_held(). One
## store per context, so no reader reaches into the controller or its ghost.

var slot_id: int = -1
## null = nothing held / controller gone.
var shape: BlockShape = null
## ghost.global_position, not the controller cursor.
var origin: Vector3 = Vector3.ZERO
var orientation_index: int = 0
var free_quat: Quaternion = Quaternion.IDENTITY
var visible: bool = false
var height_above_surface: float = 0.0
var updated_msec: int = 0


func publish(slot: int, held: BlockShape, at: Vector3, orientation: int, quat: Quaternion,
		is_visible: bool, height: float, now_msec: int) -> void:
	slot_id = slot
	shape = held
	origin = at
	orientation_index = orientation
	free_quat = quat
	visible = is_visible
	height_above_surface = height
	updated_msec = now_msec


func clear() -> void:
	shape = null
	slot_id = -1
	visible = false
