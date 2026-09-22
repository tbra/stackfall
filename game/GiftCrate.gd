class_name GiftCrate
extends Area3D
## A gift crate (spec 2.6): a stationary pickup that shows which player it
## belongs to once claimed. Presence-only for M4 P1 -- a block or a thrown
## special can be seen to strike it, matching the chain-reaction flavor text,
## even though nothing here currently *reacts* to that contact: body_entered
## is wired to a documented, harmless no-op a later milestone can fill in
## (P3/P4/P5's specials do not need to know about crates this milestone).
##
## Built from meshes, the same reason game/HomeFlag.gd is: M2-era placeholder
## art, replaced whole in M7. autoload/match/MatchGifts.gd owns the only two
## calls that matter here -- instancing this scene and calling
## set_owner_tint() -- so no rule of any kind lives on this script.
##
## DECISION (game/GiftCrate.gd): CRATE_SIZE/UNCLAIMED_COLOR are fixed visual
## constants, not gameplay tunables -- this package owns no config file
## (docs/M4_P1b brief); move them into GiftConfig if a later package needs
## them configurable (flagged under Unresolved in the P1b report).
const CRATE_SIZE: Vector3 = Vector3(0.6, 0.6, 0.6)
const UNCLAIMED_COLOR: Color = Color(0.85, 0.75, 0.15)

## Set by MatchGifts right after instancing. -1 (this crate is not tracked by
## anything) is never a real id (MatchGifts._next_gift_id starts at 0).
var gift_id: int = -1
var owner_slot: int = -1

var _mesh: MeshInstance3D = null
var _material: StandardMaterial3D = null


func _ready() -> void:
	_build()
	body_entered.connect(_on_body_entered)


func _build() -> void:
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	shape_node.name = &"Collision"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = CRATE_SIZE
	shape_node.shape = box_shape
	add_child(shape_node)

	_mesh = MeshInstance3D.new()
	_mesh.name = &"Mesh"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = CRATE_SIZE
	_mesh.mesh = box_mesh
	_material = StandardMaterial3D.new()
	_material.albedo_color = UNCLAIMED_COLOR
	_mesh.material_override = _material
	add_child(_mesh)


## Tints the crate the claiming slot's color. Nothing in M4 P1 calls this yet
## (a claimed crate is freed the same tick it is claimed -- see
## MatchGifts._claim_gift()), but it is the documented seam a later package
## can use if a claimed-but-not-yet-despawned state is ever wanted.
func set_owner_tint(slot_id: int, color: Color) -> void:
	owner_slot = slot_id
	if _material != null:
		_material.albedo_color = color


## Documented no-op (see class doc): a later milestone may want a thrown
## special or an ordinary block striking a crate to do something. Nothing in
## M4 P1 needs it.
func _on_body_entered(_body: Node3D) -> void:
	pass
