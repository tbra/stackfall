class_name BlackHoleVisual
extends Node3D
## Cel vortex for the black hole (Bontago-8or.26): a dark core sphere plus a flat
## disc (shaders/black_hole_vortex.gdshader) sized to the pull radius, which grows
## in on spawn and collapses out at the end of the lifetime. Built on every peer
## from the replicated special_triggered event; presentation only. The Low graphics
## preset uses fewer arms and no inward streaks.

const TUNING: BlackHoleVisualTuning = preload("res://config/black_hole_visual.tres")
const SHADER: Shader = preload("res://shaders/black_hole_vortex.gdshader")
const BLACK_HOLE_ID: StringName = &"black_hole"
## Smallest divisor/exponent used by the growth curve (avoids a zero division).
const MIN_SPAN: float = 0.001
const PARAM_GROW: StringName = &"grow"
const PARAM_TIME: StringName = &"time_s"

var _remaining_s: float = 0.0
var _age_s: float = 0.0
var _lifetime_s: float = 0.0
var _material: ShaderMaterial = null
var _core: MeshInstance3D = null
var _last_grow: float = -1.0
## Set when spawned into a match world (GiftFxPresenter): the visual frees itself once the
## match is no longer live, since it now hangs under the persistent Field (1pi.85.66)
## rather than the per-match blocks container.
var bind_to_match: bool = false


## radius_m is the core sphere radius; the disc covers the pull radius read from the
## black hole SpecialDef (falls back to radius_m * 2 if it cannot be found).
func setup(radius_m: float, lifetime_s: float) -> void:
	_remaining_s = lifetime_s
	_lifetime_s = lifetime_s
	var pull_radius_m: float = radius_m * 2.0
	var def: SpecialDef = SpecialDef.find_by_id(BLACK_HOLE_ID)
	var effect: BlackHoleEffect = def.effect as BlackHoleEffect if def != null else null
	if effect != null:
		pull_radius_m = effect.pull_radius_m
	var low: bool = false
	var preset: GraphicsPreset = Settings.current_graphics_preset()
	if preset != null and not preset.ambient_life_enabled:
		low = true
	_material = _build_material(low)
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(pull_radius_m * 2.0, pull_radius_m * 2.0)
	var disc: MeshInstance3D = MeshInstance3D.new()
	disc.mesh = plane
	disc.material_override = _material
	disc.position.y = TUNING.disc_lift_m
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	var core_material: StandardMaterial3D = StandardMaterial3D.new()
	core_material.albedo_color = TUNING.core_color
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius_m
	sphere.height = radius_m * 2.0
	_core = MeshInstance3D.new()
	_core.mesh = sphere
	_core.material_override = core_material
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	_apply_growth(scale_at(0.0, lifetime_s))


## 0..1 size envelope: ease-in growth (start fraction up to 1 over grow_in_s, slow start
## then accelerating), multiplied by a smoothstep collapse over the last collapse_out_s.
## Defaults give the plain smoothstep-free ease-in from 0.
static func growth(age_s: float, remaining_s: float, grow_in_s: float, collapse_out_s: float,
		start_fraction: float = 0.0, ease_power: float = 1.0) -> float:
	var t: float = clampf(age_s / maxf(grow_in_s, MIN_SPAN), 0.0, 1.0)
	var grown: float = start_fraction + (1.0 - start_fraction) * pow(t, maxf(ease_power, MIN_SPAN))
	var collapse: float = clampf(remaining_s / maxf(collapse_out_s, MIN_SPAN), 0.0, 1.0)
	return grown * collapse * collapse * (3.0 - 2.0 * collapse)


## Size fraction from the shared tuning: used by the visual and by BlackHoleField's
## pull/capture radius so both follow the same curve.
static func scale_at(age_s: float, lifetime_s: float) -> float:
	return growth(age_s, lifetime_s - age_s, TUNING.grow_in_s, TUNING.collapse_out_s,
		TUNING.grow_start_fraction, TUNING.grow_ease_power)


func _build_material(low: bool) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"core_fraction", TUNING.core_fraction)
	material.set_shader_parameter(&"ring_inner", TUNING.ring_inner)
	material.set_shader_parameter(&"ring_outer", TUNING.ring_outer)
	material.set_shader_parameter(&"arm_count", TUNING.arm_count_low if low else TUNING.arm_count_high)
	material.set_shader_parameter(&"arm_twist", TUNING.arm_twist)
	material.set_shader_parameter(&"spin_speed", TUNING.spin_speed)
	material.set_shader_parameter(&"streaks_on", 0.0 if low else 1.0)
	material.set_shader_parameter(&"streak_count", TUNING.streak_count)
	material.set_shader_parameter(&"streak_density", TUNING.streak_density)
	material.set_shader_parameter(&"streak_speed", TUNING.streak_speed)
	material.set_shader_parameter(&"streak_width", TUNING.streak_width)
	material.set_shader_parameter(&"streak_alpha", TUNING.streak_alpha)
	material.set_shader_parameter(&"dash_threshold", TUNING.dash_threshold)
	material.set_shader_parameter(&"streak_fade_start", TUNING.streak_fade_start)
	material.set_shader_parameter(&"cel_steps", TUNING.cel_steps)
	material.set_shader_parameter(&"core_color", TUNING.core_color)
	material.set_shader_parameter(&"ring_color_a", TUNING.ring_color_a)
	material.set_shader_parameter(&"ring_color_b", TUNING.ring_color_b)
	material.set_shader_parameter(&"streak_color", TUNING.streak_color)
	return material


func _apply_growth(grow: float) -> void:
	if is_equal_approx(grow, _last_grow):
		return
	_last_grow = grow
	_material.set_shader_parameter(PARAM_GROW, grow)
	_core.scale = Vector3.ONE * grow
	# Opens up from underneath: the core rises from core_emerge_depth_m below the surface.
	_core.position.y = -TUNING.core_emerge_depth_m * (1.0 - grow)
	_core.visible = grow > 0.0


func _process(delta: float) -> void:
	if bind_to_match and not MatchAutoload.is_live(Match.state()):
		queue_free()
		return
	_remaining_s -= delta
	_age_s += delta
	if _remaining_s <= 0.0:
		queue_free()
		return
	if _material != null:
		_material.set_shader_parameter(PARAM_TIME, _age_s)
		_apply_growth(scale_at(_age_s, _lifetime_s))
