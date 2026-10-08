class_name BlockStepBatch
extends RefCounted
## Bontago-bth.1: one batched pass per physics tick over Block's awake set
## replacing the two GDScript callbacks Godot used to make per awake Block per
## tick (Block._integrate_forces() and Block._physics_process(); the
## Bontago-bth REPORT attributed ~40-55% of a 250-block moving pile's step to
## them). It runs the rebound
## damping / kick pass-through bookkeeping and the impact-audio detection for
## every awake Block in ONE engine->script call (SceneTree.physics_frame).
##
## Timing contract (game/Block.gd's old per-node hooks, Godot 4.7.2 main loop
## and Jolt): a tick is [PhysicsServer3D.flush_queries() -> every called-back
## body's state sync (where _integrate_forces ran) -> SceneTree.physics_frame
## -> every node's _physics_process -> deferred calls/timers -> step]. This
## hook is connected FIRST on physics_frame (install() moves any earlier
## listener behind it), so it runs after every state sync of the tick and
## before any other script reads or writes a block for that tick: exactly
## where the old _integrate_forces work became visible. Step N's result is
## still adjusted before step N+1, never later.
##
## Which blocks Jolt would have called back is reconstructed, not guessed:
## a body is synced at tick F iff it was active at step F-1 or woke during
## it. Block keeps _sync_from_frame for that (see Block._next_sync_frame());
## the engine's own sleep/wake transition (sleeping_state_changed, raised
## from inside that body's state sync) pins it, and a block falling asleep
## runs its early-out right inside that signal (Block._on_sleeping_state_
## changed()). The one-shot release tilt stays a real per-body engine
## callback (Block._on_first_integration()) because it moves the body and
## casts a ray against bodies tilted earlier in the same flush.

## The installed hook object (kept alive here: a signal connection does not
## hold a reference to its target).
static var _instance: BlockStepBatch = null
static var _install_queued: bool = false
## For tests and the callback-count bench: how many times the batched hook ran.
static var hook_runs: int = 0


## Queues install() once per process: a block can enter the tree while the
## physics_frame signal is mid-emission (a test resumed from an awaited
## physics frame), and reordering connections there is unsafe. The deferred
## call runs before the next tick's physics_frame; a block entering now is
## not synced before then anyway (Block._next_sync_frame()).
static func ensure_installed() -> void:
	if _instance != null or _install_queued:
		return
	_install_queued = true
	BlockStepBatch.install.call_deferred()


## Connects the hook as the FIRST physics_frame listener (re-appending any
## listener connected earlier, e.g. GUT's awaiter, with its own flags).
static func install() -> void:
	_install_queued = false
	if _instance != null:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var batch: BlockStepBatch = BlockStepBatch.new()
	var earlier: Array = tree.physics_frame.get_connections()
	for connection: Dictionary in earlier:
		tree.physics_frame.disconnect(connection["callable"] as Callable)
	tree.physics_frame.connect(batch._on_physics_frame)
	for connection: Dictionary in earlier:
		tree.physics_frame.connect(connection["callable"] as Callable, int(connection["flags"]))
	_instance = batch


static func is_installed() -> bool:
	return _instance != null


func _on_physics_frame() -> void:
	hook_runs += 1
	var frame: int = Engine.get_physics_frames()
	# DECISION (game/BlockStepBatch.gd): the per-block body is Block._batch_tick()
	# (a script-to-script call whose ~20 field reads are indexed `self` member
	# reads) rather than inline here, where each would be a by-name lookup on
	# another instance; either way it is one engine->script call per tick.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var physics_active: bool = tree != null and not tree.paused
	for block: Block in Block._awake.values():
		block._batch_tick(frame, physics_active)
