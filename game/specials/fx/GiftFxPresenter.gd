class_name GiftFxPresenter
extends Node
## Central dispatcher for per-gift client visuals.
##
## Owned by Match. Subscribes once to Events.special_triggered (every peer gets
## the replicated event) and routes it by def id to a builder Callable
## `(block: Block, def: SpecialDef, position: Vector3) -> void`. `block` is the
## carrier looked up by net id and may be null (already despawned); handlers
## must tolerate that. Unknown def ids and non-finite positions are ignored.
## Replaces Match's former per-gift _on_paintball_triggered /
## _on_black_hole_triggered handlers; add new gift visuals with `register`.
##
## Depends on: Events, SpecialDef, Block

const PAINTBALL_ID: StringName = &"paintball"
const BLACK_HOLE_ID: StringName = &"black_hole"

var _handlers: Dictionary = {}


func _ready() -> void:
	register(PAINTBALL_ID, _build_paintball)
	register(BLACK_HOLE_ID, _build_black_hole)
	connect_events()


## Idempotent: a second call never adds a second subscription.
func connect_events() -> void:
	if not Events.special_triggered.is_connected(on_special_triggered):
		Events.special_triggered.connect(on_special_triggered)


func register(def_id: StringName, handler: Callable) -> void:
	_handlers[def_id] = handler


func unregister(def_id: StringName) -> void:
	_handlers.erase(def_id)


func has_handler(def_id: StringName) -> bool:
	return _handlers.has(def_id)


## Receives special_triggered events and dispatches to the handler for `def_id`.
func on_special_triggered(net_id: int, def_id: StringName, position: Vector3, _chain_depth: int) -> void:
	if not position.is_finite() or not _handlers.has(def_id):
		return
	var handler: Callable = _handlers[def_id] as Callable
	if not handler.is_valid():
		return
	var block: Block = null
	var registry: BlockRegistry = Match.registry()
	if registry != null:
		block = registry.block_for_net_id(net_id)
	handler.call(block, SpecialDef.find_by_id(def_id), position)


## Paintball: expanding colour shell tinted by the thrower's slot.
func _build_paintball(block: Block, _def: SpecialDef, position: Vector3) -> void:
	var parent: Node3D = Match.blocks_parent()
	if parent == null or block == null or block.owner_slot < 0 or block.owner_slot >= Match.slot_count():
		return
	var splash: PaintballSplash = PaintballSplash.new()
	parent.add_child(splash)
	splash.global_position = position
	splash.setup(Match.slot(block.owner_slot).color)


## Black hole (Bontago-8or.25): every peer draws the placeholder disc; the
## pull itself is host-only physics.
func _build_black_hole(_block: Block, def: SpecialDef, position: Vector3) -> void:
	var parent: Node3D = Match.blocks_parent()
	var effect: BlackHoleEffect = def.effect as BlackHoleEffect if def != null else null
	if parent == null or effect == null:
		return
	var visual: BlackHoleVisual = BlackHoleVisual.new()
	parent.add_child(visual)
	visual.global_position = position
	visual.setup(effect.visual_radius_m, effect.lifetime_s)
