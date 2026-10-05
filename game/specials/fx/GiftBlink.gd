class_name GiftBlink
## Visual-only blinking effect for a gift warning (Bomb).
##
## `apply` attaches a small driver node to the block that flashes an overlay
## on the gift visual. Phase is local: it starts when `apply` is called and
## speeds up from `period_s` to `period_s * END_PERIOD_RATIO` over
## `duration_s`; no RPC. Calling it again restarts the blink.
##
## Depends on: Block, BlockFactory.GIFT_VISUAL_NODE

## DECISION (Bontago-1pi.85.8): the final blink period as a share of the start
## period (plan: 0.25 s accelerating to 0.1 s). A presentation constant, not a
## gameplay tunable.
const END_PERIOD_RATIO: float = 0.4
const DRIVER_NAME: StringName = &"GiftBlinkDriver"
const FLASH_COLOR: Color = Color(1.0, 0.25, 0.1)
const FLASH_MAX_ALPHA: float = 0.55


## Pure: blink period `age_s` seconds in.
static func period_at(age_s: float, period_s: float, duration_s: float) -> float:
	var progress: float = clampf(age_s / duration_s, 0.0, 1.0) if duration_s > 0.0 else 1.0
	return lerpf(period_s, period_s * END_PERIOD_RATIO, progress)


## Pure: flash intensity 0..1 for a phase measured in blink cycles.
static func intensity_at(phase: float) -> float:
	return 0.5 - 0.5 * cos(phase * TAU)


## Starts (or restarts) the blink on `block`. No-op for a null/freed block or
## non-positive timings.
static func apply(block: Block, period_s: float, duration_s: float) -> void:
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
	block.add_child(driver)


class GiftBlinkDriver:
	extends Node

	var period_s: float = 0.25
	var duration_s: float = 3.0
	var age_s: float = 0.0
	var phase: float = 0.0
	var _material: StandardMaterial3D = null
	var _meshes: Array[MeshInstance3D] = []


	func _ready() -> void:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.albedo_color = Color(GiftBlink.FLASH_COLOR, 0.0)
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
		phase += delta / GiftBlink.period_at(age_s, period_s, duration_s)
		_material.albedo_color = Color(GiftBlink.FLASH_COLOR, GiftBlink.intensity_at(phase) * GiftBlink.FLASH_MAX_ALPHA)


	func _finish() -> void:
		for mesh: MeshInstance3D in _meshes:
			if is_instance_valid(mesh) and mesh.material_overlay == _material:
				mesh.material_overlay = null
		queue_free()
