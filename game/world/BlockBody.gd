class_name BlockBody
extends RigidBody3D
## The light base class of game/blocks/Block.gd (it lets the autoload facades name
## the block without compiling the full Block). It carries the identity fields and the
## two audio statics that autoload facades (Match, MatchNet, Sfx, SnapshotSync)
## read and write, plus no-op virtual stubs for the Block methods those facades
## call, so they can name this type instead of the heavy Block script. It
## references no other game class. Block overrides every stub with the same
## signature.

## Which BlockShape this block was built from (BlockFactory sets it).
@export var shape_id: StringName = &""

## M2 (spec 1.5 "height credit", 3.4): which PlayerSlot placed this block,
## permanently -- territory influence and multiplayer attribution both key off
## this. -1 means no slot, e.g. placements made before slots existed.
@export var owner_slot: int = -1

## the gift this body delivers (set by BlockFactory.
## apply_gift_visual() on the host and, from the spawn RPC, on clients), or
## &"" for an ordinary block. Presentation only; the effect is SpecialBehavior.
var gift_id: StringName = &""

## M3's network id, assigned by game/blocks/BlockRegistry.gd when the block is
## registered. -1 until then.
@export var net_id: int = -1

## autoload/Sfx.gd sets both statics once at startup from AudioConfig so
## game/blocks/Block.gd carries no direct dependency on the AudioConfig class.
static var impact_speed_min: float = 1.0
## Kill switch, set from AudioConfig.impacts_enabled; false costs nothing per
## tick beyond the `if` check itself.
static var impacts_enabled: bool = true


# --- Virtual stubs (D8): overridden by Block with identical signatures --------

func set_contributing_visual(_contributing: bool) -> void:
	pass


func set_frozen_visual(_frozen: bool) -> void:
	pass


func is_frozen_visual() -> bool:
	return false


## Glue fusion: the FusedBody this block belongs to,
## or null. Block and FusedBody override; no behaviour yet.
func fused_carrier() -> RigidBody3D:
	return null


## Glue fusion: the replicated sleep flag (RigidBody3D.sleeping) for the wire.
func net_sleeping() -> bool:
	return sleeping
