class_name GiftBlink
## Visual-only blinking effect for a gift warning (Bomb).
##
## `apply` attaches a small driver node to the block that flashes an overlay
## on the gift visual. Phase is local: it starts when `apply` is called and
## speeds up from `period_s` to `period_s * tuning.end_period_ratio` over
## `duration_s`; no RPC. Calling it again restarts the blink.
## `start_for_gift` is the client-derived entry point: from a block's `gift_id`
## alone it finds the gift's blink timing and starts the blink (idempotent), so a
## client needs nothing but the replicated spawn.
##
## Colour, peak opacity and the end-period ratio are GiftBlinkTuning (moved out of
## consts, Bontago-1pi.85.10); a null tuning means the shipped
## config/specials/fx/gift_blink_tuning.tres.
##
## Depends on: Block, BlockFactory.GIFT_VISUAL_NODE, GiftBlinkTuning, SpecialDef, BombEffect

const DRIVER_NAME: StringName = &"GiftBlinkDriver"
const DEFAULT_TUNING: GiftBlinkTuning = preload("res://config/specials/fx/gift_blink_tuning.tres")


## Pure: blink period `age_s` seconds in. `tuning` null means DEFAULT_TUNING.
static func period_at(age_s: float, period_s: float, duration_s: float, tuning: GiftBlinkTuning = null) -> float:
	var ratio: float = (tuning if tuning != null else DEFAULT_TUNING).end_period_ratio
	var progress: float = clampf(age_s / duration_s, 0.0, 1.0) if duration_s > 0.0 else 1.0
	return lerpf(period_s, period_s * ratio, progress)


## Pure: flash intensity 0..1 for a phase measured in blink cycles.
static func intensity_at(phase: float) -> float:
	return 0.5 - 0.5 * cos(phase * TAU)


## Client-derived start (plan section 7: no RPC). Looks `block.gift_id` up in the gift
## roster and, when that gift blinks (Bomb), starts the blink on `block` with the
## gift's own timing. `elapsed_s` is how long the gift has already existed (a late
## caller, e.g. the host's first armed tick, passes its age so the blink still ends
## with the explosion). Idempotent: a block that already carries a blink driver is
## left alone. Returns whether the block is (now) blinking.
static func start_for_gift(block: Block, elapsed_s: float = 0.0) -> bool:
	if block == null or not is_instance_valid(block) or block.gift_id == &"":
		return false
	var def: SpecialDef = SpecialDef.find_by_id(block.gift_id)
	var effect: BombEffect = def.effect as BombEffect if def != null else null
	if effect == null:
		return false
	if block.get_node_or_null(NodePath(String(DRIVER_NAME))) != null:
		return true
	apply(block, effect.blink_period_s, effect.blink_duration_s, effect.blink_tuning, elapsed_s)
	return block.get_node_or_null(NodePath(String(DRIVER_NAME))) != null


## Starts (or restarts) the blink on `block`. `elapsed_s` is the blink's age at the
## moment of the call (0 for a fresh blink). No-op for a null/freed block or
## non-positive timings.
static func apply(
	block: Block, period_s: float, duration_s: float, tuning: GiftBlinkTuning = null, elapsed_s: float = 0.0
) -> void:
	if block == null or not is_instance_valid(block) or period_s <= 0.0 or duration_s <= 0.0:
		return
	var old: Node = block.get_node_or_null(NodePath(String(DRIVER_NAME)))
	if old != null:
		block.remove_child(old)
		old.queue_free()
	var driver: GiftBlinkDriver = GiftBlinkDriver.new()
	driver.name = DRIVER_NAME
	driver.period_s = period_s
	driver.duration_s = duration_s
	driver.tuning = tuning if tuning != null else DEFAULT_TUNING
	driver.age_s = maxf(elapsed_s, 0.0)
	block.add_child(driver)


class GiftBlinkDriver:
	extends Node

	var period_s: float = 0.0  # set by GiftBlink.apply()
	var duration_s: float = 0.0  # set by GiftBlink.apply()
	var tuning: GiftBlinkTuning = null  # set by GiftBlink.apply()
	var age_s: float = 0.0
	var phase: float = 0.0
	var _material: StandardMaterial3D = null
	var _meshes: Array[MeshInstance3D] = []


	func _ready() -> void:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.albedo_color = Color(tuning.flash_color, 0.0)
		var visual: Node = get_parent().get_node_or_null(NodePath(String(BlockFactory.GIFT_VISUAL_NODE)))
		if visual != null:
			_collect(visual)
		for mesh: MeshInstance3D in _meshes:
			mesh.material_overlay = _material


	func _collect(node: Node) -> void:
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh != null:
			_meshes.append(mesh)
		for child: Node in node.get_children():
			_collect(child)


	func _process(delta: float) -> void:
		age_s += delta
		if age_s >= duration_s:
			_finish()
			return
		phase += delta / GiftBlink.period_at(age_s, period_s, duration_s, tuning)
		_material.albedo_color = Color(tuning.flash_color, GiftBlink.intensity_at(phase) * tuning.flash_max_alpha)


	func _finish() -> void:
		for mesh: MeshInstance3D in _meshes:
			if is_instance_valid(mesh) and mesh.material_overlay == _material:
				mesh.material_overlay = null
		queue_free()
