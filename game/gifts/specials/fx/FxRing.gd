class_name FxRing
extends MeshInstance3D
## a flat ring (shaders/gifts/fx_ring.gdshader) that grows from nothing to
## `radius_m` with an ease-out while it fades over `lifetime_s`. Shared by the
## cartoon blast's shock ring, the Freeze frost ring and the Jumping Bean hop ring.
## Visual only. A caller either drives advance() itself, or calls play() and the
## ring runs on its own _process and frees itself when done.

const SHADER: Shader = preload("res://shaders/gifts/fx_ring.gdshader")
## The plane spans -1..1 so its UV edge is radius 1; node scale is the live radius.
const PLANE_SIZE: Vector2 = Vector2(2.0, 2.0)

var radius_m: float = 1.0
var width_m: float = 0.5
var lifetime_s: float = 1.0
var _age_s: float = 0.0
var _material: ShaderMaterial = null


func _init() -> void:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = PLANE_SIZE
	mesh = plane
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	set_process(false)


## Configures the ring; `fill` (0..1) adds a faint disc inside the band.
func setup(color: Color, final_radius_m: float, band_width_m: float, life_s: float, fill: float = 0.0) -> void:
	radius_m = maxf(final_radius_m, band_width_m)
	width_m = band_width_m
	lifetime_s = life_s
	_age_s = 0.0
	_material.set_shader_parameter(&"ring_color", color)
	_material.set_shader_parameter(&"fill", fill)
	advance(0.0)


## Self-driven: runs on _process and frees itself at the end.
func play() -> void:
	set_process(true)


## Moves the ring `delta` seconds on; returns true while it is still visible.
func advance(delta: float) -> bool:
	_age_s += delta
	var k: float = clampf(_age_s / lifetime_s, 0.0, 1.0) if lifetime_s > 0.0 else 1.0
	var grown: float = FxEase.out_quad(k)
	var radius: float = maxf(radius_m * grown, width_m)
	scale = Vector3(radius, 1.0, radius)
	_material.set_shader_parameter(&"width_frac", clampf(width_m / radius, 0.0, 1.0))
	_material.set_shader_parameter(&"alpha_scale", 1.0 - k * k)
	visible = k < 1.0
	return visible


func _process(delta: float) -> void:
	if not advance(delta):
		queue_free()
