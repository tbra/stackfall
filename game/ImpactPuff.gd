class_name ImpactPuff
extends MeshInstance3D
## Bontago-mp0.120: one pooled, billboarded cel dust-puff flipbook
## (assets/vfx/impact_puff_v1). Purely cosmetic. game/BlockEffectsManager.gd
## owns the pool and calls play(); the puff advances itself in _process() and
## hides when the flipbook ends (terminal frame is fully transparent), after
## which the manager may reuse it.

const SHADER: Shader = preload("res://shaders/impact_puff.gdshader")
const ATLAS_HARD: Texture2D = preload("res://assets/vfx/impact_puff_v1/impact_hard.png")
const ATLAS_SOFT: Texture2D = preload("res://assets/vfx/impact_puff_v1/impact_soft.png")

var active: bool = false
var hard: bool = true
var quad_size_m: float = 1.0
var alpha: float = 1.0
var _elapsed_s: float = 0.0
var _fps: float = 30.0
var _frame_count: int = 16
var _material: ShaderMaterial = null


func _init() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	mesh = quad
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader moves vertices on the GPU; keep culling from hiding a puff.
	extra_cull_margin = 16.0
	visible = false
	set_process(false)


## Starts the flipbook at `world_position` (the contact point).
func play(world_position: Vector3, use_hard: bool, size_m: float, tint: Color, alpha_value: float, fps: float, frames: int) -> void:
	hard = use_hard
	quad_size_m = size_m
	alpha = alpha_value
	_fps = maxf(fps, 0.001)
	_frame_count = maxi(frames, 1)
	_elapsed_s = 0.0
	global_position = world_position
	reset_physics_interpolation()
	_material.set_shader_parameter(&"atlas", ATLAS_HARD if use_hard else ATLAS_SOFT)
	_material.set_shader_parameter(&"tint", tint)
	_material.set_shader_parameter(&"quad_size", size_m)
	_material.set_shader_parameter(&"alpha_scale", alpha_value)
	_material.set_shader_parameter(&"frame", 0.0)
	active = true
	visible = true
	set_process(true)


## Advances the flipbook; returns true while still playing. Test seam too.
func advance(delta: float) -> bool:
	if not active:
		return false
	_elapsed_s += delta
	var frame: int = int(_elapsed_s * _fps)
	if frame >= _frame_count - 1:
		# Terminal frame is clear: retire instead of drawing it.
		stop()
		return false
	_material.set_shader_parameter(&"frame", float(frame))
	return true


func current_frame() -> int:
	return int(_elapsed_s * _fps)


func stop() -> void:
	active = false
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	advance(delta)
