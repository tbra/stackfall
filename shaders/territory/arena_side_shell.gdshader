shader_type spatial;
render_mode cull_disabled, specular_disabled, fog_disabled;

// The arena's side and underside for ArenaSideStyle.Style.SHADER_DOME
// (round 4; owner: "the arenas have modelled details while the
// top is just a shader - extend the shader down the side"). Smooth geometry with
// NO modelled relief: this shader draws the same procedural plating as the top
// (shaders/include/disc_plating.gdshaderinc, shared with territory.gdshader) and
// shades it the same way (base tint, cool fill, sky and sun sheen, damped diffuse),
// so the top, the wall and the dome read as one object.
//
// DECISION: this is its own small shader rather than the
// territory material on the side surfaces: territory.gdshader's per-pixel
// territory/hole/snow paths are top-only (they read the disc plane through
// v_local.xz), and the side should carry the base look, not player territory.
// The material's uniforms are copied from the territory material by
// game/field/TerritoryOverlay.gd, so every tuning edit reaches both.
//
// Plating coordinates: the plate pattern is read at the disc-local point
// p = direction(xz) * UV.x. The builder (game/field/ArenaSideBuilder.gd) writes UV.x as the
// radius for the underside and as radius + metres below the top edge for the wall,
// so the top's rings simply continue over the edge and down the wall.

uniform float top_local_y = 0.0;
uniform vec4 base_color : source_color = vec4(0.68, 0.70, 0.74, 1.0);
uniform float base_metallic : hint_range(0.0, 1.0) = 0.1;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.3;
uniform vec3 sun_direction = vec3(0.963087, 0.069011, -0.260192);
uniform vec3 disk_sheen_color : source_color = vec3(1.0, 0.78, 0.4);
uniform float disk_sheen_strength : hint_range(0.0, 2.0) = 0.6;
uniform float disk_sheen_exponent : hint_range(0.5, 16.0) = 2.5;
uniform float disk_diffuse_response : hint_range(0.0, 1.0) = 0.45;
uniform float disk_diffuse_desaturate : hint_range(0.0, 1.0) = 0.85;
uniform vec3 disk_fill_color : source_color = vec3(0.045, 0.05, 0.065);
uniform float disk_ambient_scale : hint_range(0.0, 1.0) = 0.35;
uniform float disk_specular : hint_range(0.0, 1.0) = 0.5;
uniform vec3 disk_sky_sheen_color : source_color = vec3(0.45, 0.42, 0.62);
uniform float disk_sky_sheen_strength : hint_range(0.0, 2.0) = 0.35;
uniform float disk_sky_sheen_power : hint_range(0.5, 10.0) = 3.0;
uniform float wet_darken : hint_range(0.0, 1.0) = 0.0;

#include "res://shaders/include/disc_plating.gdshaderinc"

varying vec3 v_local;
varying float v_plate_radius;

void vertex() {
	v_local = VERTEX;
	v_plate_radius = UV.x;
}

void light() {
	float luma = dot(LIGHT_COLOR.rgb, vec3(0.299, 0.587, 0.114));
	vec3 cool_light = mix(LIGHT_COLOR.rgb, vec3(luma), disk_diffuse_desaturate);
	DIFFUSE_LIGHT += ALBEDO * cool_light * ATTENUATION * disk_diffuse_response;
}

void fragment() {
	vec2 dir = v_local.xz;
	float dir_len = length(dir);
	vec2 plate_p = dir_len > 0.0001 ? dir / dir_len * v_plate_radius : vec2(0.0);
	vec3 albedo = base_color.rgb;
	vec3 emission = vec3(0.0);
	vec3 tex_mod = vec3(1.0);
	float proc_highlight = 0.0;
	float proc_brush = 0.0;
	float proc_rough = base_roughness;
	vec3 proc_plate_n = vec3(0.0, 1.0, 0.0);
	vec3 sun_local = transpose(mat3(MODEL_MATRIX)) * sun_direction;
	vec2 sun2 = length(sun_local.xz) > 0.0001 ? normalize(sun_local.xz) : vec2(1.0, 0.0);
	if (disc_procedural) {
		float proc_tone;
		float proc_seam_occ;
		// Height above the top face (world y), as on the top.
		float top_world_y = (MODEL_MATRIX * vec4(0.0, top_local_y, 0.0, 1.0)).y;
		float cam_height = max(CAMERA_POSITION_WORLD.y - top_world_y, 0.0);
		proc_plating(plate_p, sun2, cam_height, proc_tone, proc_highlight, proc_seam_occ,
			proc_plate_n, proc_rough, proc_brush);
		tex_mod = proc_tone * disc_proc_base_tint;
		albedo *= tex_mod;
	}
	vec3 sheen_normal = normalize(NORMAL);
	vec3 sheen_view = normalize(VIEW);
	vec3 sun_view_dir = normalize((VIEW_MATRIX * vec4(sun_direction, 0.0)).xyz);
	vec3 reflected = reflect(-sheen_view, sheen_normal);
	float alignment = clamp(dot(normalize(reflected), sun_view_dir), 0.0, 1.0);
	emission += disk_sheen_color * disk_sheen_strength * pow(alignment, disk_sheen_exponent);
	emission += disk_fill_color * tex_mod;
	float sky_fresnel = pow(1.0 - clamp(dot(sheen_normal, sheen_view), 0.0, 1.0), disk_sky_sheen_power);
	emission += disk_sky_sheen_color * disk_sky_sheen_strength * sky_fresnel;
	if (disc_procedural) {
		// The plate tilt is a horizontal wobble of the plate normal; added to the
		// surface normal so it works on a wall and a dome as it does on the flat top.
		vec3 tilt_view = mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * vec3(proc_plate_n.x, 0.0, proc_plate_n.z);
		vec3 plate_view_n = normalize(sheen_normal + tilt_view);
		float sun_lobe = pow(alignment, disc_proc_sheen_exponent);
		float sky_lobe = pow(1.0 - clamp(dot(plate_view_n, sheen_view), 0.0, 1.0), disc_proc_sky_sheen_power)
			* disc_proc_sky_sheen_weight;
		float bands = max(float(disc_proc_sheen_bands), 1.0);
		float q = clamp(sky_lobe, 0.0, 1.0) * bands;
		float band = floor(q);
		float band_aa = max(disc_proc_sheen_band_softness, fwidth(q));
		band += smoothstep(1.0 - band_aa, 1.0, q - band);
		float banded_sky = band / bands;
		float sun_weight = sun_lobe / max(sun_lobe + sky_fresnel, 0.0001);
		emission += disc_proc_sheen_strength * (
			mix(disk_sky_sheen_color * banded_sky * (1.0 + proc_brush),
				disc_proc_highlight_color * sun_lobe, sun_weight)
		);
		emission += disc_proc_highlight_color * proc_highlight;
	}
	ALBEDO = albedo * (1.0 - wet_darken);
	EMISSION = emission;
	METALLIC = base_metallic;
	SPECULAR = disk_specular;
	AO = disk_ambient_scale;
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = clamp(proc_rough, 0.0, 1.0);
}
