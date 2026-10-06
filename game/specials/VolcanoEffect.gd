class_name VolcanoEffect
extends SpecialEffect
## Volcano gift (spec 2.6; owner 2026-10-05, Bontago-1pi.85.14): "a large mountain
## rises where you released and keeps firing blocks for 20 s+". Owner answer
## 1pi.85.4 (a): a solid cone that rides the tilting disc, pushing blocks in its
## footprint outward as it rises.
##
## Flow: the gift carrier lands (needs_landing), the effect triggers at once
## (wants_early_trigger) and detonate() spawns a VolcanoStructure on the host,
## parented to the Field so it moves with the disc. The carrier is removed at
## trigger (detaches). Clients get the structure visual from the replicated
## special_triggered (GiftFxPresenter calls VolcanoStructure.build_client_visual)
## and no physics body.
##
## Like every shared SpecialEffect resource this keeps NO per-block state; the
## structure node owns its clock.

## Seconds the cone takes to grow from flat to height_m.
@export var rise_s: float = 2.0

## Seconds the volcano erupts after it finished rising (spec: at least 20).
## effect_lifetime_s() reports it.
@export var eruption_duration_s: float = 22.0

## Final cone height in metres.
@export var height_m: float = 4.0

## Cone base radius in metres.
@export var base_radius_m: float = 2.5

## Segments of the cone's base ring (collision hull and mesh).
@export var ring_segments: int = 16

## Surface friction of the cone's collider.
@export var surface_friction: float = 0.4

## Seconds between eruption bursts, drawn uniformly from [min, max].
@export var eruption_interval_min_s: float = 0.4
@export var eruption_interval_max_s: float = 1.2

## Blocks per burst, drawn uniformly from [min, max].
@export var min_blocks_per_burst: int = 1
@export var max_blocks_per_burst: int = 3

## Half-angle (degrees) of the launch cone around the structure's up.
@export var cone_angle_deg: float = 35.0

## Launch speed of each block in m/s.
@export var launch_speed_mps: float = 9.0

## Metres above the apex a block spawns, and the horizontal spread between the
## blocks of one burst so they do not interpenetrate.
@export var spawn_clearance_m: float = 0.4
@export var burst_spread_m: float = 0.8

## Fallback single shape, used only when `shape_weights` is null.
@export var block_shape: BlockShape = preload("res://config/blocks/cube.tres")

## Per-block shape pick (shared GiftShapeWeights, Bontago-1pi.85.31); null = every block is
## `block_shape`. Blocks are owner-coloured by the spawn path.
@export var shape_weights: GiftShapeWeights = preload("res://config/gifts/gift_shape_weights.tres")

## Erupting stops once the blocks root holds this many children (same 600 cap as
## StackfallEffect).
@export var block_cap: int = 600

## Footprint push while rising: outward speed given to a block inside the base
## radius plus `push_margin_m`, at most `push_max_bodies` bodies per tick (bounded scan).
@export var push_speed_mps: float = 4.0
@export var push_margin_m: float = 0.6
@export var push_max_bodies: int = 64

## Visual model (host and client), scaled to base_radius_m / height_m. Null falls back
## to the procedural cone below.
@export var model_scene: PackedScene = null

## Fallback cone colour (used only when model_scene is null).
@export var cone_color: Color = Color(0.45, 0.18, 0.08)

## Eruption particles (Bontago-1pi.85.30); null = none.
@export var particles: VolcanoParticleTuning = preload("res://config/specials/fx/volcano_particle_tuning.tres")


## The action's length; SpecialBehavior derives its fuse backstop from it.
func effect_lifetime_s() -> float:
	return rise_s + eruption_duration_s


## A hard landing never triggers it: the structure appears when the carrier lands.
func triggers_on_impact() -> bool:
	return false


func impact_triggers(_block: Block, _behavior: SpecialBehavior) -> bool:
	return false


## The structure owns a standalone world node; the carrier goes at trigger.
func detaches() -> bool:
	return true


## Runs only once the carrier has landed (needs_landing) and armed: erupt now.
func needs_landing() -> bool:
	return true


func wants_early_trigger(_block: Block, _behavior: SpecialBehavior) -> bool:
	return true


## Spawns the host-side structure at the carrier's landing point.
func detonate(block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	if block == null or not block.is_inside_tree():
		return
	VolcanoStructure.spawn_host(self, block.global_position, block.owner_slot, block.get_rid())
