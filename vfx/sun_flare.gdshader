shader_type canvas_item;
render_mode blend_add, unshaded;
// Bontago-mp0.3.4 (Graphics pass 2, owner feedback "lens flare from the
// sun"; fix round "move god rays into the sky, keep only the true lens
// artifact here"): the big warm halo/god-ray beams now live in
// shaders/sunset_clouds.gdshader (drawn as part of the sky pass, so they sit
// behind every opaque object for free). This screen-space layer keeps only
// the camera-lens artifacts: a small, tight starburst sparkle directly on
// the sun's own screen position, plus a handful of "ghost" discs sampled
// along the line from the sun through the screen center. Every uniform
// below is written every frame by vfx/SunFlare.gd from
// config/SunFlareConfig.gd; nothing here is a magic number, only the shape
// of the falloff math itself.
//
// DECISION (vfx/sun_flare.gdshader, fix round): `render_mode blend_add` --
// the previous candidate used ordinary alpha blending, which reads as a
// DARK overlay wherever this shader's own accumulated color is dimmer than
// a bright background behind it (the sky/disc/existing bloom): alpha-mixing
// a moderately-bright warm value over a near-white background darkens it.
// Additive blending only ever brightens, never darkens, matching how a real
// lens flare/glow actually looks and fixing exactly the "dark grey spokes
// painting over the disc/beacons" symptom reported against the pre-fix
// screen-space rays (now removed; see the sky shader's own rays instead).
//
// All positions/sizes below are in aspect-corrected UV space: `uv` is
// SCREEN_UV (0..1 x 0..1, origin top-left) with x rescaled by the viewport's
// own aspect ratio so a "radius" reads as the same visual size along both
// axes instead of stretching into an ellipse on a widescreen viewport.

uniform vec2 sun_uv;
uniform float visibility; // 0..1, computed on the CPU side (facing/edge/occlusion).
uniform vec4 sun_color : source_color;
uniform float core_radius;
uniform float core_softness;
uniform float core_intensity;
uniform float ray_count;
uniform float ray_length;
uniform float ray_sharpness;
uniform float ray_intensity;
uniform float ghost_count;
uniform vec4 ghost_positions; // up to 4 fractions along the sun->center axis; unused slots < 0.
uniform float ghost_base_size;
uniform float ghost_size_falloff;
uniform float ghost_alpha;
uniform float ghost_ring_width; // fraction of a ghost's radius that is ring; 0 = solid disc.
uniform vec4 ghost_color_b : source_color;
uniform float aspect_ratio;
uniform float max_intensity;

// Soft disc: 1.0 at the center, falling smoothly to 0.0 past `radius`, with
// `softness` (0..1) controlling how much of that falloff is a smooth-step
// gradient versus a hard-edged core.
float soft_disc(vec2 p, vec2 center, float radius) {
	float d = length(p - center);
	return 1.0 - smoothstep(radius * (1.0 - core_softness), radius, d);
}

vec2 aspect_uv(vec2 uv) {
	return vec2(uv.x * aspect_ratio, uv.y);
}

void fragment() {
	// DECISION (vfx/sun_flare.gdshader): no early `return` inside fragment()
	// -- Godot's shader compiler rejects a `return` statement directly in the
	// fragment()/vertex()/light() entry points (they are inlined into a
	// larger generated function), so the "nothing visible" case below is a
	// branch around the whole body instead of an early exit.
	float v = visibility * max_intensity;
	if (v > 0.001) {
		vec2 p = aspect_uv(UV);
		vec2 sun_p = aspect_uv(sun_uv);
		vec2 center_p = aspect_uv(vec2(0.5, 0.5));

		vec3 accum = vec3(0.0);
		float alpha_accum = 0.0;

		// Bright core.
		float core = soft_disc(p, sun_p, core_radius) * core_intensity;
		accum += sun_color.rgb * core;
		alpha_accum += core;

		// Radiating starburst rays: an angular falloff around the sun
		// position, modulated by distance so rays fade out by ray_length.
		vec2 to_sun = p - sun_p;
		float dist = length(to_sun);
		if (dist < ray_length && dist > 0.0001) {
			float angle = atan(to_sun.y, to_sun.x);
			float ray_shape = pow(abs(cos(angle * ray_count * 0.5)), ray_sharpness);
			float ray_fade = 1.0 - smoothstep(0.0, ray_length, dist);
			float ray = ray_shape * ray_fade * ray_intensity;
			accum += sun_color.rgb * ray;
			alpha_accum += ray;
		}

		// Ghost discs sampled along the sun -> screen-center axis.
		vec2 axis = center_p - sun_p;
		float positions[4] = float[4](ghost_positions.x, ghost_positions.y, ghost_positions.z, ghost_positions.w);
		int count = int(clamp(ghost_count, 0.0, 4.0));
		for (int i = 0; i < 4; i++) {
			if (i < count && positions[i] >= 0.0) {
				vec2 ghost_center = sun_p + axis * positions[i];
				float size = ghost_base_size * pow(ghost_size_falloff, float(i));
				// DECISION (Bontago-t8x.3): a hollow ring, not a solid disc. A solid warm
				// disc a third of the way toward screen centre read as a second sun
				// whenever the real sun sat off-axis (owner 2026-10-01).
				float ghost = soft_disc(p, ghost_center, size);
				ghost = max(ghost - soft_disc(p, ghost_center, size * (1.0 - clamp(ghost_ring_width, 0.0, 1.0))), 0.0) * ghost_alpha;
				vec3 tint = mix(sun_color.rgb, ghost_color_b.rgb, mod(float(i), 2.0));
				accum += tint * ghost;
				alpha_accum += ghost;
			}
		}

		COLOR = vec4(accum * v, clamp(alpha_accum * v, 0.0, 1.0));
	} else {
		COLOR = vec4(0.0);
	}
}
