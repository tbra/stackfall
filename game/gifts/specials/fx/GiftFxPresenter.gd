class_name GiftFxPresenter
extends Node
## Central dispatcher for per-gift client visuals.
##
## Owned by Match. Subscribes once to Events.special_triggered (every peer gets
## the replicated event) and routes it by def id to a builder Callable
## `(block: Block, def: SpecialDef, position: Vector3) -> void`. `block` is the
## carrier looked up by net id and may be null (already despawned); handlers
## must tolerate that. Unknown def ids and non-finite positions are ignored.
## Add new gift visuals with `register`.
##
## Depends on: Events, MatchContext, SpecialDef, Block

const PAINTBALL_ID: StringName = &"paintball"
const BLACK_HOLE_ID: StringName = &"black_hole"
const BOMB_ID: StringName = &"bomb"
const ROCKET_ID: StringName = &"rocket"
const VOLCANO_ID: StringName = &"volcano"
const PROPELLER_ID: StringName = &"propeller"
const FREEZE_ID: StringName = &"freeze"
const EXPLOSION_TUNING: GiftExplosionFxTuning = preload("res://config/gifts/specials/fx/gift_explosion_fx_tuning.tres")
const FREEZE_TUNING: FreezeFxTuning = preload("res://config/gifts/specials/fx/freeze_fx_tuning.tres")

var _handlers: Dictionary = {}


func _ready() -> void:
	register(PAINTBALL_ID, _build_paintball)
	register(BLACK_HOLE_ID, _build_black_hole)
	register(BOMB_ID, _build_explosion)
	register(ROCKET_ID, _build_explosion)
	register(VOLCANO_ID, _build_volcano)
	register(PROPELLER_ID, _build_propeller)
	register(FREEZE_ID, _build_freeze)
	connect_events()


## The one spawn hook (BlockFactory.apply_gift_visual, which host and clients both run
## for a gift carrier): starts the client-derived per-gift visuals. No RPC; each peer
## derives them from block.gift_id and its own clock. Visual-only and a no-op for a
## gift without such a visual.
static func on_gift_block_spawned(block: Block) -> void:
	GiftBlink.start_for_gift(block)
	BeanHopFx.start_for_gift(block)
	spawn_paintball_sling(block)


## Paintball: the thrown body keeps only the loaded glob and a slingshot copy (PaintballSling)
## stays at the launch pose to release, hold and fade. Client-derived like the other spawn
## visuals; false when `block` is not a Paintball body or its model has no separable glob.
static func spawn_paintball_sling(block: Block) -> bool:
	if block == null or not is_instance_valid(block) or not block.is_inside_tree() or block.gift_id != PAINTBALL_ID:
		return false
	var def: SpecialDef = SpecialDef.find_by_id(block.gift_id)
	# Duck-typed (PaintballEffect) so the layer lint keeps the effect out of this closure.
	var effect: Resource = def.effect if def != null else null
	var body_visual: Node3D = block.get_node_or_null(NodePath(String(BlockFactory.GIFT_VISUAL_NODE))) as Node3D
	var parent: Node3D = block.get_parent() as Node3D
	if effect == null or effect.get(&"glob_node_name") == null or body_visual == null or parent == null:
		return false
	var glob_name: StringName = effect.get(&"glob_node_name") as StringName
	var sling_visual: Node3D = GiftModelTable.shared().build_gift_visual(block.gift_id)
	if sling_visual == null:
		return false
	if not PaintballSling.strip_to_glob(body_visual, glob_name):
		sling_visual.free()
		return false
	var sling: PaintballSling = PaintballSling.new()
	sling.name = &"PaintballSling"
	parent.add_child(sling)
	parent.move_child(sling, block.get_index())  # the body stays the parent's newest child
	sling.global_transform = block.global_transform
	sling_visual.transform = body_visual.transform
	sling.add_child(sling_visual)
	PaintballSling.hide_glob(sling_visual, glob_name)
	var entry: GiftModelEntry = GiftModelTable.shared().entry_for(block.gift_id)
	var speed: float = entry.animation_speed if entry != null else 1.0
	sling.begin(sling_visual, effect.get(&"release_animation") as StringName, speed,
		effect.get(&"sling_hold_s") as float, effect.get(&"sling_fade_s") as float)
	return true


## Idempotent: a second call never adds a second subscription.
func connect_events() -> void:
	if not Events.special_triggered.is_connected(on_special_triggered):
		Events.special_triggered.connect(on_special_triggered)


func register(def_id: StringName, handler: Callable) -> void:
	_handlers[def_id] = handler


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


## Black hole: every peer draws the placeholder disc; the
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


## Bomb and Rocket: a CartoonBlast (flash, toon fireballs, shock ring,
## debris, dust) sized by the blast radius. Rides the replicated special_triggered, so
## every peer sees it; hangs under the Field so it rides a tilt. Visual only, frees itself.
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
	var effect: CartoonBlast = CartoonBlast.new()
	DiscAnchor.attach(effect, position, parent)
	effect.setup(EXPLOSION_TUNING, blast.radius_m, hash(position))


## Volcano: clients draw the same cone without a physics body; the
## host already has the real structure (build_client_visual returns null there).
func _build_volcano(block: Block, def: SpecialDef, position: Vector3) -> void:
	var effect: VolcanoEffect = def.effect as VolcanoEffect if def != null else null
	if effect == null:
		return
	VolcanoStructure.build_client_visual(effect, position, block.owner_slot if block != null else -1)


## Propeller: clients draw the stand rising out of the disc at the drop
## point without a carrier body; the host already has the real stand (build_client_visual
## returns null there).
func _build_propeller(_block: Block, def: SpecialDef, position: Vector3) -> void:
	var effect: PropellerEffect = def.effect as PropellerEffect if def != null else null
	if effect == null:
		return
	PropellerStand.build_client_visual(effect, position)


## Freeze: an ice-shard burst with a frost ring grown to the freeze radius.
## Every peer draws it from the replicated trigger; the freeze itself is host physics.
func _build_freeze(_block: Block, def: SpecialDef, position: Vector3) -> void:
	var parent: Node3D = MatchContext.current().blocks_parent()
	var effect: FreezeEffect = def.effect as FreezeEffect if def != null else null
	if parent == null or effect == null or not parent.is_inside_tree():
		return
	var burst: FreezeBurst = FreezeBurst.new()
	DiscAnchor.attach(burst, position, parent)
	burst.setup(FREEZE_TUNING, effect.freeze_radius_m, hash(position))
