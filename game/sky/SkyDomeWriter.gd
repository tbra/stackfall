class_name SkyDomeWriter
extends RefCounted
## The one writer of the sky dome material and of the sky shader globals. `bind` duplicates the
## shipped template once, so the template (shared with other resources) is never written.
## `stage` copies a SkyFrame's sky channel into a wanted-value table; `flush` writes only the
## uniforms whose value differs from the last write and returns how many it wrote. Every
## material uniform write dirties the sky radiance (engine sky.cpp), so an unchanged frame must
## write nothing: a flush that returns 0 leaves the radiance untouched. Floats compare with ==,
## Color and Vector3 compare exactly (never is_equal_approx), so a real change is never lost.

const SKY_TIME_GLOBAL: StringName = &"sky_time"
const SKY_SUN_DIR_GLOBAL: StringName = &"sky_sun_dir"
const SKY_MOON_DIR_GLOBAL: StringName = &"sky_moon_dir"
## Sea mix of the cycle's procedural sky look (0 would be a black sky): a constant the evaluator does
## not carry, written once at bind.
const PROCEDURAL_SEA_MIX: float = 1.0
const MOON_DISC_TEXTURE: Texture2D = preload("res://assets/textures/sky/moon/moon_disc.png")
const MOON_HALO_TEXTURE: Texture2D = preload("res://assets/textures/sky/moon/moon_halo.png")

var _material: ShaderMaterial = null
## Uniform name -> value staged for the next flush.
var _wanted: Dictionary[StringName, Variant] = {}
## Uniform name -> value last written to the material.
var _written: Dictionary[StringName, Variant] = {}


## Duplicates `template` once, installs the duplicate as `sky`'s material and returns it.
## `sky` may be null (tests, headless): the duplicate is still created.
func bind(sky: Sky, template: ShaderMaterial) -> ShaderMaterial:
	forget()
	_material = template.duplicate() as ShaderMaterial
	# Constant uniforms, written once (a per-tick write would dirty the radiance for nothing).
	_material.set_shader_parameter(&"moon_disc_tex", MOON_DISC_TEXTURE)
	_material.set_shader_parameter(&"moon_halo_tex", MOON_HALO_TEXTURE)
	_material.set_shader_parameter(&"procedural_sea_mix", PROCEDURAL_SEA_MIX)
	if sky != null:
		sky.sky_material = _material
	return _material


## Caches the sky channel of `frame` as the wanted uniform values. Writes nothing.
func stage(frame: SkyFrame) -> void:
	_wanted[&"sun_direction"] = frame.sun_direction
	_wanted[&"use_global_dirs"] = frame.use_global_dirs
	_wanted[&"exposure"] = frame.exposure
	_wanted[&"proc_sea_coverage"] = frame.proc_sea_coverage
	_wanted[&"proc_zenith_color"] = frame.proc_zenith_color
	_wanted[&"proc_mid_color"] = frame.proc_mid_color
	_wanted[&"proc_horizon_color"] = frame.proc_horizon_color
	_wanted[&"proc_horizon_glow_color"] = frame.proc_horizon_glow_color
	_wanted[&"proc_gradient_mid_height"] = frame.proc_gradient_mid_height
	_wanted[&"proc_gradient_power"] = frame.proc_gradient_power
	_wanted[&"proc_horizon_glow_width"] = frame.proc_horizon_glow_width
	_wanted[&"proc_sun_glow_strength"] = frame.proc_sun_glow_strength
	_wanted[&"proc_sea_color_near"] = frame.proc_sea_color_near
	_wanted[&"proc_sea_color_far"] = frame.proc_sea_color_far
	_wanted[&"proc_sea_horizon_fade"] = frame.proc_sea_horizon_fade
	_wanted[&"sun_core_color"] = frame.sun_core_color
	_wanted[&"sun_halo_color"] = frame.sun_halo_color
	_wanted[&"sun_ray_color"] = frame.sun_ray_color
	_wanted[&"cloud_shadow_color"] = frame.cloud_shadow_color
	_wanted[&"cloud_mid_color"] = frame.cloud_mid_color
	_wanted[&"cloud_lit_color"] = frame.cloud_lit_color
	_wanted[&"cloud_rim_color"] = frame.cloud_rim_color
	_wanted[&"cycle_night_mix"] = frame.cycle_night_mix
	_wanted[&"cycle_night_zenith"] = frame.cycle_night_zenith
	_wanted[&"cycle_night_horizon"] = frame.cycle_night_horizon
	_wanted[&"cycle_night_below"] = frame.cycle_night_below
	_wanted[&"cycle_star_brightness"] = frame.cycle_star_brightness
	_wanted[&"cycle_star_cells"] = frame.cycle_star_cells
	_wanted[&"cycle_star_threshold"] = frame.cycle_star_threshold
	_wanted[&"cycle_star_radius"] = frame.cycle_star_radius
	_wanted[&"cycle_star_horizon_fade"] = frame.cycle_star_horizon_fade
	_wanted[&"moon_direction"] = frame.moon_direction
	_wanted[&"moon_visibility"] = frame.moon_visibility
	_wanted[&"moon_angular_radius_deg"] = frame.moon_angular_radius_deg
	_wanted[&"moon_halo_radius_deg"] = frame.moon_halo_radius_deg
	_wanted[&"moon_halo_strength"] = frame.moon_halo_strength
	_wanted[&"moon_brightness"] = frame.moon_brightness
	_wanted[&"aurora_visibility"] = frame.aurora_visibility
	# The look is staged only while the aurora is visible (it is never drawn otherwise).
	if frame.aurora_visibility > 0.0:
		_wanted[&"aurora_intensity"] = frame.aurora_intensity
		_wanted[&"aurora_color_low"] = frame.aurora_color_low
		_wanted[&"aurora_color_mid"] = frame.aurora_color_mid
		_wanted[&"aurora_color_top"] = frame.aurora_color_top
		_wanted[&"aurora_speed"] = frame.aurora_speed
		_wanted[&"aurora_base_height"] = frame.aurora_base_height
		_wanted[&"aurora_curtain_height"] = frame.aurora_curtain_height
	_wanted[&"sun_effect_scale"] = frame.sun_effect_scale


## Writes the staged uniforms that differ from the last write; returns the count written
## (0 = the material was not touched, so the radiance stays clean).
func flush() -> int:
	if _material == null:
		return 0
	var count: int = 0
	for key: StringName in _wanted:
		var value: Variant = _wanted[key]
		if _written.has(key) and _written[key] == value:
			continue
		_written[key] = value
		_material.set_shader_parameter(key, value)
		count += 1
	return count


## The shader globals (no material dirty): sky_time, sky_sun_dir and sky_moon_dir (opposite the sun).
func publish_globals(sun_dir: Vector3, sky_time_s: float) -> void:
	RenderingServer.global_shader_parameter_set(SKY_TIME_GLOBAL, sky_time_s)
	RenderingServer.global_shader_parameter_set(SKY_SUN_DIR_GLOBAL, sun_dir)
	RenderingServer.global_shader_parameter_set(SKY_MOON_DIR_GLOBAL, -sun_dir)


## Drops the equal-value cache and the staged values (new material or a reset): the next
## flush writes everything.
func forget() -> void:
	_wanted.clear()
	_written.clear()
