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

## Bontago-xtq.17 (owner feel report "heavier and more bouncy, but a dropped
## block shouldn't just bounce straight up again"): the live PhysicsTuning
## this Block was built from, kept only so _integrate_forces() below can read
## rebound_damping without a scene-tree/group lookup every physics step. Set
## once by BlockFactory.build() and refreshed by apply_physics_tuning() below,
## so the live-apply path (ui/TuningPanel.gd's apply_physics_live(), driven by
## a preset pick or a slider drag) keeps it current for a block that's
## already standing. Null-safe: a bare Block never built through
## BlockFactory (none exist today, but nothing stops it) just never damps its
## rebound, the same as rebound_damping's own 1.0 no-op default.
var tuning: PhysicsTuning = null

## Previous physics step's post-solve vertical velocity, tracked only for the
## rebound-damping heuristic below -- the same "compare this tick's velocity
## against last tick's" idiom the impact-audio code above already uses (see
## its own DECISION), kept on a separate variable because this one is read
## and written from _integrate_forces() (runs once per physics step, before
## the engine commits the body's new velocity) rather than _physics_process()
## (runs after).
var _prev_step_linear_velocity_y: float = 0.0

## Review fix (Bontago-xtq.17 SHOULD-FIX 1): set by kick()/mark_script_kick()
## below, consumed (and cleared) by the very next _integrate_forces() call.
## See kick()'s own doc comment for what this is for.
var _script_kick_pending: bool = false

## Fix round (Bontago-xtq.27 review MAJOR): the "contributing to territory
## influence" glow (BlockFactory.build()'s own DECISION: RigidBody3D.sleeping
## as the settled proxy) used to be written straight onto the BlockMesh
## MeshInstance3D from inside BlockFactory.build() and a local
## sleeping_state_changed connection -- both of which only ever fire on
## whichever peer actually runs physics for this body. A client's synced
## blocks are frozen kinematic (net/SnapshotSync.gd's freeze_body(), spec
## 3.4) and never sleep for real, so a client never saw the glow at all.
## This seam moves the write onto Block itself so a client's own
## SnapshotSync.client_tick() can drive it from the wire's `sleeping` flag
## (net/Interpolator.gd's Sample.sleeping) instead, while BlockFactory.build()
## keeps driving it from the real sleeping_state_changed signal on whichever
## peer is this body's physics authority -- both paths converge here, so
## neither has to know or care which one currently applies.
var _contributing_visual: bool = false
## Sentinel separate from _contributing_visual itself: without it, the very
## first call with `contributing == false` (BlockFactory.build()'s own
## initial call, since a freshly spawned block is never already asleep)
## would be silently skipped by a plain "value unchanged" early-out, because
## the field's own default (false) already equals that first argument.
var _contributing_visual_set: bool = false
var _block_mesh_cache: MeshInstance3D = null
var _block_mesh_looked_up: bool = false


func _ready() -> void:
	add_to_group(TUNING_GROUP)
	if tuning == null:
		# Review fix (Bontago-xtq.17 SHOULD-FIX 3): game/BlockFactory.gd's
		# build() now sets `block.tuning = tuning` itself (its own build()
		# doc comment), so this fallback only matters for a bare Block never
		# built through that factory (e.g. Block.new() directly in a test) --
		# it defaults such a block to the shared preloaded
		# config/physics_tuning.tres instance rather than leaving `tuning`
		# null (rebound_damping would just never apply otherwise, the same
		# no-op as tuning == null everywhere below already handles safely,
		# but every real gameplay default should still get the shipped
		# rebound-damping behavior instead of silently opting out of it).
		tuning = preload("res://config/physics_tuning.tres")


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
	# Bontago-xtq.29 (M7 P4 fix): additive alongside the line above -- see
	# Events.block_impacted_at's own doc comment. autoload/Sfx.gd's listener
	# on block_impacted is unchanged.
	Events.block_impacted_at.emit(decel, global_position)


## Bontago-xtq.17: damps only a fresh bounce's straight-up (world Y) velocity,
## leaving horizontal and angular velocity alone so block_bounce still gives
## lateral/tumbling liveliness off a corner or edge hit -- see
## config/PhysicsTuning.gd's rebound_damping DECISION for why this can't just
## be a lower Jolt restitution. Runs every physics step regardless of
## contact_monitor (RigidBody3D always calls a script's _integrate_forces()
## override once per step it isn't sleeping; no signal/contact-report setup
## needed) -- Block._physics_process's own DECISION above is why
## contact_monitor itself stays off. A client's synced blocks are frozen
## (RigidBody3D.FREEZE_MODE_KINEMATIC, net/SnapshotSync.gd's freeze_body()),
## so Jolt never integrates them and this never runs there -- host-only
## follows from "only the host runs physics" (CLAUDE.md) without this file
## needing to ask Net anything.
##
## Review fix (Bontago-xtq.17 SHOULD-FIX 1): a special effect's own
## intentional velocity write (a Jumping Bean hop, a Rocket's continuous
## thrust tick, a Propeller lift start, an explosion's apply_impulse) can also
## flip a block's vertical velocity from falling to rising -- indistinguishable
## from a real bounce to the heuristic below unless the writer says so.
## `_script_kick_pending` is that signal: kick()/mark_script_kick() below set
## it, this function consumes (and clears) it before ever reaching
## _damp_rebound(), so exactly the one step a special's own write lands on is
## passed through untouched, and every step after goes back to the normal
## heuristic.
##
## DECISION (game/Block.gd): a flag consumed on the very next
## _integrate_forces() call, not a real contact-detection signal
## (contact_monitor/body_entered), for the same reason contact_monitor stays
## off project-wide (this function's own opening DECISION: ~5-7 ms/step at
## 300 blocks, measured, well over budget) -- a flag costs one bool check and
## needs no per-body contact reporting turned on at all. It is also strictly
## narrower than "any velocity write": only a caller that explicitly opts in
## (kick()/mark_script_kick()) skips damping for that step; anything that
## writes `linear_velocity`/`apply_impulse()` without calling either still
## gets the normal bounce heuristic, so a bug elsewhere fails toward "damped
## like a bounce" rather than silently exempting itself.
##
## DECISION (game/Block.gd): `state.linear_velocity` is only ever *written*
## on the one step a bounce is actually being damped, never on every step
## "just to reassign the same number" -- an earlier revision wrote it every
## step (a no-op multiply by rebound_damping's own 1.0 default), and that
## alone kept tests/unit/test_tower_placement.gd's 30-cube tower from ever
## sleeping (still 30/30 awake after 10 s where it used to be 0/30):
## RigidBody3D/Jolt apparently treats any script write to a body's velocity
## from _integrate_forces() as an external disturbance for that step's sleep
## bookkeeping, even when the value written is bit-for-bit identical to what
## was already there. Reading `state.linear_velocity.y` every step to update
## `_prev_step_linear_velocity_y` is safe (a read, not a write); only a real
## bounce step's `state.linear_velocity.y = ...` assignment actually runs.
##
## DECISION (game/Block.gd): "a real bounce", not any sign flip at all --
## _damp_rebound() below gates on tuning.sleep_linear_threshold (the same
## settled-block speed floor spec 2.2 already defines, reused rather than
## inventing a second magic number for "this is noise"). A stacked tower's
## resting contacts flicker by a fraction of a mm/s of solver noise every
## step (PhysicsTuning.gd's own long comment on this exact 40-chain's
## fragility -- velocity_steps=192 and the tightened contact-cache threshold
## in tools/bootstrap_project.gd), and reacting to that noise as a "bounce"
## (bench_tower.tscn with rebound_damping=0.3, gravity_multiplier=1.4,
## block_bounce=0.4: max_top_drift_m=117.97, all_asleep=false -- reproduced
## against this exact combination) fed the tower a stream of tiny scripted
## velocity writes it never needed and never recovered from. Gating out
## anything at or below the settled-block speed floor (bounce_damping=0.3 at
## the same tuning otherwise: max_top_drift_m=0.02210, all_asleep=true,
## asleep_at_s=0.52 -- identical to the ungated tower's own baseline) fixed
## it outright; see config/physics_presets/heavy_bouncy.tres for the shipped
## values this was tuned against.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var current_y: float = state.linear_velocity.y
	if _script_kick_pending:
		# Review fix (Bontago-xtq.17 SHOULD-FIX 1): this step's velocity was
		# just written by a special effect (kick()/mark_script_kick()), not
		# produced by Jolt's own contact solver -- pass it through untouched
		# and consume the flag so only THIS step is exempt.
		_script_kick_pending = false
	elif tuning != null and tuning.rebound_damping != 1.0:
		var damped_y: float = _damp_rebound(
			_prev_step_linear_velocity_y, current_y, tuning.rebound_damping, tuning.sleep_linear_threshold
		)
		if damped_y != current_y:
			current_y = damped_y
			state.linear_velocity.y = current_y
	_prev_step_linear_velocity_y = current_y


## Sets `linear_velocity` and marks the resulting step exempt from rebound
## damping in one call -- the common case for a special effect that only ever
## overwrites the whole vector (JumpingBeanEffect's hop, RocketEffect's thrust
## tick). See mark_script_kick() below for the case that doesn't fit this
## (a partial write like Propeller's `.y` component, or an external caller
## that only has this Block as a plain RigidBody3D, like SpecialPhysics.
## explode()).
func kick(velocity: Vector3) -> void:
	linear_velocity = velocity
	mark_script_kick()


## Marks the very next _integrate_forces() step as a script-driven velocity
## write, not a natural bounce -- see _integrate_forces()'s own review-fix
## DECISION above for why a flag, not contact detection. Call this right after
## directly assigning/adding to `linear_velocity` (or apply_impulse()) from a
## special effect, whenever kick() itself doesn't fit (PropellerEffect only
## overwrites the Y component every tick; SpecialPhysics.explode() only has
## the body it hits as a plain RigidBody3D, so it casts to Block first).
func mark_script_kick() -> void:
	_script_kick_pending = true


## Pure rebound-damping rule, static and scene-tree/physics-server-free so
## tests/unit/test_physics_tuning.gd can check it directly without a real
## physics step: a step whose vertical velocity flips from clearly falling
## (`prev_step_y < -noise_floor`) to clearly rising (`current_y >
## noise_floor`) is a fresh bounce off whatever is below the block -- scale
## that step's rising velocity by `rebound_damping`. Every other case (still
## falling, still rising from an earlier bounce, at rest, or a flicker too
## small to be a real bounce) passes `current_y` through unchanged. See
## _integrate_forces()'s own DECISION above for why the noise floor is
## required, not just a nice-to-have.
static func _damp_rebound(prev_step_y: float, current_y: float, rebound_damping: float, noise_floor: float) -> float:
	if prev_step_y < -noise_floor and current_y > noise_floor:
		return current_y * rebound_damping
	return current_y


## Re-applies every PhysicsTuning number a live body would otherwise only
## ever read once, at BlockFactory.build() time: damping, the friction/bounce
## material, and gravity_scale (spec 2.8 "Gravity 0.5x-2x" -- BlockFactory.
## build() sets gravity_scale from this same field for every new spawn;
## rewriting it here on an already-falling body only changes the acceleration
## RigidBody3D integrates on the *next* physics step, not any velocity it has
## already accumulated, so there is no visible "kick", just a smooth change in
## how fast it keeps falling from here.
func apply_physics_tuning(tuning: PhysicsTuning) -> void:
	self.tuning = tuning
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


## Fix round (Bontago-xtq.27 review MAJOR): the one write site for the
## "contributing to territory influence" glow's instance shader parameter.
## Called by BlockFactory.build() (from the real RigidBody3D.sleeping /
## sleeping_state_changed on this body's physics authority) and by
## net/SnapshotSync.gd's client_tick() (from the newest wire sample's
## `sleeping` flag, net/Interpolator.gd's Sample.sleeping) -- whichever one
## actually applies for this peer, the other's writes are simply inert (a
## client's frozen kinematic body never fires sleeping_state_changed for
## real; a host has no snapshot to apply). No-ops when this block has no
## BlockMesh MeshInstance3D at all, e.g. a ghost built through
## BlockFactory.build_visual_only(), which never calls this.
func set_contributing_visual(contributing: bool) -> void:
	if _contributing_visual_set and _contributing_visual == contributing:
		return
	var mesh_instance: MeshInstance3D = _block_mesh()
	if mesh_instance == null:
		return
	mesh_instance.set_instance_shader_parameter(&"contributing", contributing)
	_contributing_visual = contributing
	_contributing_visual_set = true


## Test seam for the write above (tests/unit/test_block_factory.gd,
## tests/unit/test_snapshot_sync.gd): what the glow is currently set to,
## regardless of which peer's path last drove it. Reads back the field this
## class itself last wrote, not the shader parameter on the mesh, so it works
## the same whether or not a real Viewport/shader is present (headless tests).
func is_contributing_visual() -> bool:
	return _contributing_visual


## Cached BlockMesh lookup (looked up at most once per block, not on every
## sleeping_state_changed/snapshot tick): a ghost built through
## BlockFactory.build_visual_only() has no node named "BlockMesh" at all, so
## the miss itself is cached too rather than re-searching the tree every call.
func _block_mesh() -> MeshInstance3D:
	if not _block_mesh_looked_up:
		_block_mesh_looked_up = true
		_block_mesh_cache = get_node_or_null(^"BlockMesh") as MeshInstance3D
	return _block_mesh_cache
