class_name GiftFxPresenter
extends Node
## Central dispatcher for per-gift client visuals.
##
## Owned by Match. Subscribes once to Events.special_triggered (every peer gets
## the replicated event) and asks the def's effect to `build_client_fx`. `block` is the
## carrier looked up by net id and may be null (already despawned). Unknown def ids and
## non-finite positions are ignored.
##
## Depends on: Events, MatchContext, SpecialDef, Block

const PAINTBALL_ID: StringName = &"paintball"


func _ready() -> void:
	connect_events()


## The one spawn hook (BlockFactory.apply_gift_visual, which host and clients both run
## for a gift carrier): starts the client-derived per-gift visuals. No RPC; each peer
## derives them from block.gift_id and its own clock. Visual-only and a no-op for a
## gift without such a visual. A THROWN Bomb blinks only from its landing: the host announces the
## throw and the landing (Events.special_launch_state) and on_special_launch_state() below stops
## and starts the blink on every peer.
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
	if not Events.special_launch_state.is_connected(on_special_launch_state):
		Events.special_launch_state.connect(on_special_launch_state)


## A thrown gift's launch state on every peer: `landed` false = just thrown (its spawn blink stops,
## nothing counts down in flight), true = first landing contact (the blink starts).
func on_special_launch_state(net_id: int, landed: bool) -> void:
	var registry: BlockRegistry = MatchContext.current().registry() as BlockRegistry
	var block: Block = registry.block_for_net_id(net_id) if registry != null else null
	if block == null:
		return
	if landed:
		GiftBlink.start_for_gift(block)
	else:
		GiftBlink.stop(block)


## Receives special_triggered events and asks the def's effect to draw its visual.
func on_special_triggered(net_id: int, def_id: StringName, position: Vector3, _chain_depth: int) -> void:
	if not position.is_finite():
		return
	var def: SpecialDef = SpecialDef.find_by_id(def_id)
	if def == null or def.effect == null:
		return
	var block: Block = null
	var registry: BlockRegistry = MatchContext.current().registry() as BlockRegistry
	if registry != null:
		block = registry.block_for_net_id(net_id)
	var owner_slot: int = block.owner_slot if block != null else SpecialIds.in_place_slot(net_id)
	def.effect.build_client_fx(MatchContext.current(), block, position, owner_slot)
