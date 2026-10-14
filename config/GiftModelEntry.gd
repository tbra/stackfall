class_name GiftModelEntry
extends Resource
## One row of the gift model table (config/gift_model_table.tres): how a
## Codex GLB (assets/models/<id>_v1) is placed where the game used a
## placeholder. Presentation only.

## Special id (SpecialDef.id), or a crate role name for the crate rows.
@export var id: StringName = &""

## The imported GLB.
@export var scene: PackedScene = null

## Uniform scale applied to the GLB root.
@export var model_scale: float = 1.0

## Offset applied after scaling (centres the model on the gift cell / crate).
@export var offset: Vector3 = Vector3.ZERO

## Looping clip to play while shown (empty: static model).
@export var loop_animation: StringName = &""

## One-shot clip played when the gift is activated (released/thrown/placed as a live gift body),
## on every peer that builds the body's visual (BlockFactory.apply_gift_visual). The held ghost
## never plays it. Empty: none. Bontago-mp0.160 (paintball 'fire'); reusable by any gift.
@export var activate_animation: StringName = &""

## Playback speed of the clip.
@export var animation_speed: float = 1.0

## In-world (non-held) scale, for specials with their own body such as the
## cat. 0 means "use model_scale".
@export var world_scale: float = 0.0

## Yaw (degrees) turning the model's +Z front to the host's body forward.
@export var world_yaw_deg: float = 0.0

## Model-space axis that is the gift's nose (Rocket, Magnet: +Y in their GLBs). Non-zero turns
## the HELD model so this axis points along the aim/launch direction instead of standing
## upright (Bontago-1pi.85.61). Zero: held upright, no turn.
@export var held_nose_axis: Vector3 = Vector3.ZERO

## Turn the held nose axis onto the aim as a yaw + pitch only, so the model keeps its up
## (FlightFacing.upright_nose_basis). For models with a fixed "up" such as the slingshot
## (Bontago-1pi.85.79); Rocket and Magnet use the shortest arc.
@export var held_keep_upright: bool = false
