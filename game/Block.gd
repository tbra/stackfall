class_name Block
extends RigidBody3D
## A placed or falling block (spec 2.4, 3.6). Built by BlockFactory from a
## BlockShape; carries just enough identity for M1 (which shape it is and how
## many cubes it has). Ownership, influence, and special behavior arrive in
## later milestones.

@export var shape_id: StringName = &""
@export var cube_count: int = 0

## M2 (spec 2.2 "height credit", 3.4): which PlayerSlot placed this block,
## permanently — territory influence and multiplayer attribution both key off
## this. -1 means "no owner", e.g. M1's placements before slots existed.
@export var owner_slot: int = -1

## M3's network id, assigned by game/BlockRegistry.gd when the block is
## registered. -1 until then.
@export var net_id: int = -1

## Bontago-mv0.18 (in-game tuning panel): every Block adds itself to this
## group in _ready() so ui/TuningPanel.gd can push a PhysicsTuning edit onto
## every block already standing, not just the next one BlockFactory builds
## (get_tree().get_nodes_in_group(TUNING_GROUP), never a game/BlockRegistry.gd
## change -- that file belongs to a different package).
const TUNING_GROUP: StringName = &"tuning_blocks"

## assets-audio package (revised: no contact_monitor -- an earlier revision's
## bench_rain.gd cost ~5-7 ms/step at 300 blocks, well over budget). Impacts
## are detected from the body's own motion instead: _physics_process below
## compares this tick's linear_velocity against the previous tick's, and a
## sudden drop in speed (hitting something) crosses AudioConfig.impact_speed_min.
## autoload/Sfx.gd sets both statics once at startup from AudioConfig so this
## file carries no direct dependency on the AudioConfig class.
static var impact_speed_min: float = 1.0
## Kill switch, set from AudioConfig.impacts_enabled; false costs nothing per
## tick beyond the `if` check itself.
static var impacts_enabled: bool = true

## DECISION (game/Block.gd): a fixed rate limit on how often a detected
## impact becomes an Events.block_impacted signal, not a gameplay tunable --
## it only shapes audio event frequency, never physics or rules, so it stays
## a const here rather than moving to a config/ Resource (CLAUDE.md's "no
## magic numbers" targets tunables that affect gameplay/feel).
const IMPACT_EMIT_INTERVAL_MS: int = 120

var _last_impact_emit_ms: int = -1000000
var _prev_linear_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group(TUNING_GROUP)


## Sleeping bodies (a settled pile) skip this entirely -- Jolt stops
## integrating them, so linear_velocity would otherwise read as a false,
## constant "impact" the instant they wake. DECISION: the deceleration
## magnitude (previous tick's speed minus this tick's), not a full projected
## dot product -- cheap, and correct for the case that matters (a fall
## suddenly arrested by a landing); a block that speeds up between ticks
## (still falling, or getting knocked) never crosses the threshold here.
func _physics_process(_delta: float) -> void:
	if not impacts_enabled or sleeping:
		_prev_linear_velocity = linear_velocity
		return
	var prev_speed: float = _prev_linear_velocity.length()
	var now_speed: float = linear_velocity.length()
	var decel: float = prev_speed - now_speed
	_prev_linear_velocity = linear_velocity
	if decel < impact_speed_min:
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_impact_emit_ms < IMPACT_EMIT_INTERVAL_MS:
		return
	_last_impact_emit_ms = now_ms
	Events.block_impacted.emit(decel)


## Re-applies every PhysicsTuning number a live body would otherwise only
## ever read once, at BlockFactory.build() time: damping, the friction/bounce
## material, and gravity_scale (spec 2.8 "Gravity 0.5x-2x" -- BlockFactory.
## build() sets gravity_scale from this same field for every new spawn;
## rewriting it here on an already-falling body only changes the acceleration
## RigidBody3D integrates on the *next* physics step, not any velocity it has
## already accumulated, so there is no visible "kick", just a smooth change in
## how fast it keeps falling from here.
func apply_physics_tuning(tuning: PhysicsTuning) -> void:
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = tuning.block_linear_damp
	angular_damp = tuning.block_angular_damp
	gravity_scale = tuning.gravity_multiplier
	var material: PhysicsMaterial = physics_material_override
	if material == null:
		material = PhysicsMaterial.new()
		physics_material_override = material
	material.friction = tuning.block_friction
	material.bounce = tuning.block_bounce
