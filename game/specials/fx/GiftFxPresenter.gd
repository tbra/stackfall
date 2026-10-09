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
## Depends on: Events, MatchContext, SpecialDef, Block

const PAINTBALL_ID: StringName = &"paintball"
const BLACK_HOLE_ID: StringName = &"black_hole"
const BOMB_ID: StringName = &"bomb"
const ROCKET_ID: StringName = &"rocket"
const VOLCANO_ID: StringName = &"volcano"
const PROPELLER_ID: StringName = &"propeller"
const MIN_FPS: float = 0.001
const EXPLOSION_TUNING: GiftExplosionFxTuning = preload("res://config/specials/fx/gift_explosion_fx_tuning.tres")

var _handlers: Dictionary = {}


func _ready() -> void:
	register(PAINTBALL_ID, _build_paintball)
	register(BLACK_HOLE_ID, _build_black_hole)
	register(BOMB_ID, _build_explosion)
	register(ROCKET_ID, _build_explosion)
	register(VOLCANO_ID, _build_volcano)
	register(PROPELLER_ID, _build_propeller)
	connect_events()


## The one spawn hook (BlockFactory.apply_gift_visual, which host and clients both run
## for a gift carrier): starts the client-derived per-gift visuals. No RPC; each peer
## derives them from block.gift_id and its own clock. Visual-only and a no-op for a
## gift without such a visual.
static func on_gift_block_spawned(block: Block) -> void:
	GiftBlink.start_for_gift(block)


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
	var registry: BlockRegistry = MatchContext.current().registry() as BlockRegistry
	if registry != null:
		block = registry.block_for_net_id(net_id)
	handler.call(block, SpecialDef.find_by_id(def_id), position)


## Paintball: expanding colour shell tinted by the thrower's slot.
func _build_paintball(block: Block, _def: SpecialDef, position: Vector3) -> void:
	var ctx: MatchContext = MatchContext.current()
	var parent: Node3D = ctx.blocks_parent()
	if parent == null or block == null or block.owner_slot < 0 or block.owner_slot >= ctx.slot_count():
		return
	var splash: PaintballSplash = PaintballSplash.new()
	splash.bind_to_match = true
	DiscAnchor.attach(splash, position, parent)
	splash.setup(ctx.slot(block.owner_slot).color)


## Black hole (Bontago-8or.25): every peer draws the placeholder disc; the
## pull itself is host-only physics.
func _build_black_hole(_block: Block, def: SpecialDef, position: Vector3) -> void:
	var parent: Node3D = MatchContext.current().blocks_parent()
	var effect: BlackHoleEffect = def.effect as BlackHoleEffect if def != null else null
	if parent == null or effect == null:
		return
	var visual: BlackHoleVisual = BlackHoleVisual.new()
	visual.bind_to_match = true
	DiscAnchor.attach(visual, position, parent)
	visual.setup(effect.visual_radius_m, effect.lifetime_s)


## Bomb and Rocket: a blast puff (the pooled impact flipbook) sized by the blast radius.
## Rides the replicated special_triggered, so every peer sees it. Visual only.
func _build_explosion(_block: Block, def: SpecialDef, position: Vector3) -> void:
	var parent: Node3D = MatchContext.current().blocks_parent()
	var blast: ExplosionTuning = null
	if def != null:
		var bomb: BombEffect = def.effect as BombEffect
		var rocket: RocketEffect = def.effect as RocketEffect
		if bomb != null:
			blast = bomb.blast
		elif rocket != null:
			blast = rocket.blast
	if parent == null or blast == null or not parent.is_inside_tree():
		return
	var puff: ImpactPuff = ImpactPuff.new()
	DiscAnchor.parent_for(parent).add_child(puff)
	var tuning: GiftExplosionFxTuning = EXPLOSION_TUNING
	puff.play(
		position, tuning.hard, blast.radius_m * tuning.size_per_blast_radius,
		tuning.tint, tuning.alpha, tuning.fps, tuning.frame_count
	)
	var lifetime_s: float = float(tuning.frame_count) / maxf(tuning.fps, MIN_FPS)
	parent.get_tree().create_timer(lifetime_s).timeout.connect(puff.queue_free)


## Volcano (Bontago-1pi.85.14): clients draw the same cone without a physics body; the
## host already has the real structure (build_client_visual returns null there).
func _build_volcano(block: Block, def: SpecialDef, position: Vector3) -> void:
	var effect: VolcanoEffect = def.effect as VolcanoEffect if def != null else null
	if effect == null:
		return
	VolcanoStructure.build_client_visual(effect, position, block.owner_slot if block != null else -1)


## Propeller (Bontago-1pi.85.45): clients draw the stand rising out of the disc at the drop
## point without a carrier body; the host already has the real stand (build_client_visual
## returns null there).
func _build_propeller(_block: Block, def: SpecialDef, position: Vector3) -> void:
	var effect: PropellerEffect = def.effect as PropellerEffect if def != null else null
	if effect == null:
		return
	PropellerStand.build_client_visual(effect, position)
