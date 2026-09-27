shader_type sky;

uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float seam_blend_width = 0.025;
uniform float pole_blend_width = 0.06;
uniform float exposure = 0.8;

// Bontago-mp0.3.4 (Graphics pass 2, owner feedback "lens flare from the sun"
// + fix round "move god rays into the sky"): a warm sun glow/halo and
// crepuscular god-ray beams, drawn as part of the sky pass itself -- this
// runs behind every opaque object (the disc, blocks, beacons) for free (a
// sky shader is always the backmost thing drawn) and is naturally picked up
// by ReflectionProbe/SSR the same way the painted panorama already is,
// unlike a screen-space overlay which would have to be manually depth-
// tested against scene geometry. vfx/SunFlare.gd's screen-space CanvasLayer
// keeps only the true lens-artifact elements (a tight starburst sparkle
// directly on the sun disc, and the ghost discs along the sun->center
// axis) -- see that file's own class doc.
uniform vec3 sun_direction = vec3(0.963087, 0.069011, -0.260192);
uniform vec4 sun_core_color : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform vec4 sun_halo_color : source_color = vec4(1.0, 0.62, 0.28, 1.0);
uniform vec4 sun_ray_color : source_color = vec4(1.0, 0.72, 0.38, 1.0);
uniform float sun_core_angular_radius_deg = 1.6;
uniform float sun_halo_angular_radius_deg = 9.0;
uniform float sun_halo_softness_deg = 10.0;
uniform float sun_core_intensity = 3.2;
uniform float sun_halo_intensity = 1.1;
// Long, soft god-ray beams fanning out from the sun. Two overlaid ray
// layers (many thin + a few wide) rather than one uniform comb, matching
// "varying widths, many thin + a few wide beams" from the mockup review.
uniform float ray_count = 14.0;
uniform float ray_sharpness = 5.0;
uniform float ray_wide_count = 4.0;
uniform float ray_wide_sharpness = 2.0;
uniform float ray_length_deg = 55.0;
uniform float ray_intensity = 0.35;
// Slow, subtle brightness wobble on the ray layer only -- "slow subtle
// shimmer" from the mockup review; low amplitude so it reads as
// atmospheric drift, not a flicker.
uniform float ray_shimmer_speed = 0.15;
uniform float ray_shimmer_amount = 0.08;

void sky() {
	vec2 uv = SKY_COORDS;
	vec3 color = texture(panorama, uv).rgb;
	// Symmetric edge blend makes imperfect authored panorama boundaries continuous.
	float seam = 1.0 - smoothstep(0.0, seam_blend_width, min(uv.x, 1.0 - uv.x));
	color = mix(color, texture(panorama, vec2(1.0 - uv.x, uv.y)).rgb, seam * 0.5);
	// Longitude converges to one color at each pole, avoiding a pinwheel seam.
	float pole = 1.0 - smoothstep(0.0, pole_blend_width, min(uv.y, 1.0 - uv.y));
	vec3 pole_color = texture(panorama, vec2(0.5, uv.y < 0.5 ? 0.0 : 1.0)).rgb;
	COLOR = mix(color, pole_color, pole) * exposure;

	vec3 eyedir = normalize(EYEDIR);
	vec3 sun_dir = normalize(sun_direction);
	float cos_angle = dot(eyedir, sun_dir);
	float angle_deg = degrees(acos(clamp(cos_angle, -1.0, 1.0)));

	// Bright core + soft halo, both angular falloffs around the sun direction.
	float core = 1.0 - smoothstep(0.0, sun_core_angular_radius_deg, angle_deg);
	float halo = 1.0 - smoothstep(sun_halo_angular_radius_deg - sun_halo_softness_deg, sun_halo_angular_radius_deg, angle_deg);
	halo = clamp(halo, 0.0, 1.0);
	COLOR += sun_core_color.rgb * core * sun_core_intensity;
	COLOR += sun_halo_color.rgb * halo * sun_halo_intensity;

	// God rays: an angular position around the sun axis (tangent/bitangent
	// basis), two overlaid ray-comb frequencies, faded out by angular
	// distance from the sun so they never reach all the way across the sky.
	vec3 arbitrary = abs(sun_dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(arbitrary, sun_dir));
	vec3 bitangent = cross(sun_dir, tangent);
	vec3 offset = eyedir - sun_dir * cos_angle;
	float ray_angle = atan(dot(offset, bitangent), dot(offset, tangent));
	float ray_fade = 1.0 - smoothstep(0.0, ray_length_deg, angle_deg);
	if (ray_fade > 0.0) {
		float shimmer = 1.0 + sin(TIME * ray_shimmer_speed + ray_angle * 3.0) * ray_shimmer_amount;
		float rays_thin = pow(abs(cos(ray_angle * ray_count * 0.5)), ray_sharpness);
		float rays_wide = pow(abs(cos(ray_angle * ray_wide_count * 0.5)), ray_wide_sharpness);
		float rays = (rays_thin * 0.65 + rays_wide * 0.35) * ray_fade * ray_intensity * shimmer;
		COLOR += sun_ray_color.rgb * rays;
	}
}
