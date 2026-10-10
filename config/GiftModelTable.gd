class_name GiftModelTable
extends Resource
## One table of per-model scale/offset for the Codex 3D gift models
## (Bontago-mp0.119). Loaded as config/gift_model_table.tres. The crate and
## its reveal have their own rows; every special has one row in `entries`.
## Physics shapes and gameplay are untouched: this only builds visuals.

const TABLE_PATH: String = "res://config/gift_model_table.tres"
const MODEL_NODE: StringName = &"GiftModel"

@export var entries: Array[GiftModelEntry] = []

## Falling/landed crate body (origin at the model's bottom centre).
@export var crate: GiftModelEntry = null

## Opening crate used by the claim pop.
@export var reveal: GiftModelEntry = null

## Reveal clip name and speed-up so the 1 s open lands inside the claim pop.
@export var reveal_animation: StringName = &"open_reveal_1s"
@export var reveal_speed: float = 2.5

## Edge of the slot-coloured glow cube shown inside the opened crate.
@export var reveal_core_size_m: float = 0.3

## Opacity of the hint/owner tint overlay painted over the crate model.
@export var crate_tint_alpha: float = 0.5

static var _shared: GiftModelTable = null


static func shared() -> GiftModelTable:
	if _shared == null:
		_shared = load(TABLE_PATH) as GiftModelTable
	return _shared


## Bontago-xtq.44: drops the shared instance on exit so its textures are freed with the tree.
static func release_shared() -> void:
	_shared = null


func entry_for(special_id: StringName) -> GiftModelEntry:
	for entry: GiftModelEntry in entries:
		if entry != null and entry.id == special_id:
			return entry
	return null


## The held/thrown gift visual for `special_id`, or null when the table has no
## usable row (callers fall back to SpecialDef.held_scene).
func build_gift_visual(special_id: StringName, world: bool = false) -> Node3D:
	var entry: GiftModelEntry = entry_for(special_id)
	if entry == null:
		return null
	return _build(entry, world)


func build_crate_visual() -> Node3D:
	return _build(crate, false)


func build_reveal_visual() -> Node3D:
	var root: Node3D = _build(reveal, false)
	if root == null:
		return null
	var player: AnimationPlayer = _player_of(root)
	if player != null and player.has_animation(reveal_animation):
		player.speed_scale = reveal_speed
		player.play(reveal_animation)
	return root


func _build(entry: GiftModelEntry, world: bool) -> Node3D:
	if entry == null or entry.scene == null:
		return null
	var model: Node3D = entry.scene.instantiate() as Node3D
	if model == null:
		return null
	var scale_factor: float = entry.model_scale
	if world and entry.world_scale > 0.0:
		scale_factor = entry.world_scale
	var root: Node3D = Node3D.new()
	root.name = MODEL_NODE
	model.scale = Vector3.ONE * scale_factor
	model.position = entry.offset * (scale_factor / maxf(entry.model_scale, 0.0001))
	if world:
		root.rotation_degrees.y = entry.world_yaw_deg
	root.add_child(model)
	if entry.loop_animation != &"":
		var player: AnimationPlayer = _player_of(model)
		if player != null and player.has_animation(entry.loop_animation):
			player.get_animation(entry.loop_animation).loop_mode = Animation.LOOP_LINEAR
			player.speed_scale = entry.animation_speed
			player.play(entry.loop_animation)
	return root


static func _player_of(node: Node) -> AnimationPlayer:
	var found: Array[Node] = node.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer
