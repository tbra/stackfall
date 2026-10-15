class_name GiftModelTable
extends Resource
## One table of per-model scale/offset for the Codex 3D gift models
## . Loaded as config/gifts/gift_model_table.tres. The crate and
## its reveal have their own rows; every special has one row in `entries`.
## Physics shapes and gameplay are untouched: this only builds visuals.

const TABLE_PATH: String = "res://config/gifts/gift_model_table.tres"
const MODEL_NODE: StringName = &"GiftModel"
## the imported models carry plain (PBR) Blender materials; every
## built visual swaps them for cel-shaded copies with the gift ink outline.
const TOON_SHADER: Shader = preload("res://shaders/gifts/gift_toon.gdshader")
const OUTLINE_MATERIAL: Material = preload("res://assets/models/gifts/gift_outline.tres")

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

## Opacity of the hint/owning-slot tint overlay painted over the crate model.
@export var crate_tint_alpha: float = 0.5

## cel-shade every built model (gift_toon shader + ink outline).
@export var toon_enabled: bool = true

static var _shared: GiftModelTable = null
## Source material instance id -> its cel-shaded copy, shared by every visual.
static var _toon_cache: Dictionary = {}


static func shared() -> GiftModelTable:
	if _shared == null:
		_shared = load(TABLE_PATH) as GiftModelTable
	return _shared


## drops the shared instance on exit so its textures are freed with the tree.
static func release_shared() -> void:
	_shared = null
	_toon_cache.clear()


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
	if toon_enabled:
		apply_toon(model)
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


## plays `special_id`'s one-shot activate_animation on a visual built by
## build_gift_visual (the released gift body); returns whether a clip started. The clip is
## forced non-looping so the final pose (e.g. the fired slingshot) holds.
func play_activate_animation(special_id: StringName, visual: Node) -> bool:
	var entry: GiftModelEntry = entry_for(special_id)
	if entry == null or visual == null or entry.activate_animation == &"":
		return false
	var player: AnimationPlayer = _player_of(visual)
	if player == null or not player.has_animation(entry.activate_animation):
		return false
	player.get_animation(entry.activate_animation).loop_mode = Animation.LOOP_NONE
	player.speed_scale = entry.animation_speed
	player.play(entry.activate_animation)
	return true


static func _player_of(node: Node) -> AnimationPlayer:
	var found: Array[Node] = node.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer


## gives every opaque surface under `model` the cel-shaded copy of its
## material (surface overrides, so the shared imported mesh is untouched and
## material_overlay tints/blinks still layer on top). Transparent or non-standard
## materials are left as they are.
static func apply_toon(model: Node) -> void:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface: int in range(mesh_instance.mesh.get_surface_count()):
			var toon: ShaderMaterial = toon_for(mesh_instance.get_active_material(surface))
			if toon != null:
				mesh_instance.set_surface_override_material(surface, toon)


## The cached cel-shaded copy of `source`, or null when it should stay as is.
static func toon_for(source: Material) -> ShaderMaterial:
	var standard: BaseMaterial3D = source as BaseMaterial3D
	if standard == null or standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return null
	var key: int = standard.get_instance_id()
	var cached: ShaderMaterial = _toon_cache.get(key) as ShaderMaterial
	if cached != null:
		return cached
	var toon: ShaderMaterial = ShaderMaterial.new()
	toon.shader = TOON_SHADER
	toon.set_shader_parameter(&"albedo_color", standard.albedo_color)
	if standard.albedo_texture != null:
		toon.set_shader_parameter(&"albedo_texture", standard.albedo_texture)
		toon.set_shader_parameter(&"use_albedo_texture", true)
	toon.set_shader_parameter(&"use_vertex_color", standard.vertex_color_use_as_albedo)
	if standard.emission_enabled:
		toon.set_shader_parameter(&"emission_color", standard.emission)
		toon.set_shader_parameter(&"emission_energy", standard.emission_energy_multiplier)
	toon.next_pass = OUTLINE_MATERIAL
	_toon_cache[key] = toon
	return toon
