shader_type spatial;
render_mode unshaded, world_vertex_coords, cull_back, depth_draw_always, fog_disabled, shadows_disabled;
#include "res://shaders/include/cloud_common.gdshaderinc"

// Bontago-adt.1: stylized cumulus puffs below the floating disc
// (vfx/CloudSea.gd builds one MultiMesh of flat-bottomed low-poly spheres
// clustered into cumulus clumps). Opaque and toon-lit in the shader itself
// (no scene lights, shadows or fog), so the same material works at sunset
// and at night from theme colours alone.
//
// Per-pixel shape: the mesh is only an inflated bounding hull. Each fragment
// intersects its view ray with the puff's ellipsoid, whose radius is pushed
// out by round cauliflower domes (cellular noise, triplanar on the unit
// sphere) and a slow billow wave, and discards rays that miss -- so
// silhouettes are round and lumpy at any distance with no mesh facets, and
// shading uses the true entry point and ellipsoid normal.
//
// Motion is all here, driven by TIME and per-instance custom data, so it
// runs in the game, the editor and the baked demo with no script:
//  - drift: every puff orbits the disc's vertical axis at its clump's own
//    angular speed (INSTANCE_CUSTOM.x), so clumps slide past each other;
//  - billow/boil: the silhouette breathes and the dome pattern slides slowly.
// Shading: wrap-lit N.L against the (elevation-lifted) sun/moon plus a
// height-in-clump term and the dome pattern, split into three flat cel tones
// (shadow/mid/lit) with pixel-crisp edges; a sun-side and backlit fresnel
// rim; darker flat undersides.
// Seamless far fade: with distance (and depth below the disc) the colour
// blends into exactly the sky colour behind the puff -- the theme's
// panorama sampled along the view ray (moonlit-graded at night) -- so
// distant clumps melt into the painted far cloud sea with no seam or edge.
// Near fade: fragments close to the camera dissolve (ordered dither) so a
// camera orbiting under the disc is never blocked by a puff.
//
// DECISION (Bontago-adt.1): drawn in the transparent pass (writes ALPHA = 1,
// still writes depth, vfx/CloudSea.gd gives it the lowest render_priority so
// every other transparent draws over it). In the opaque pass the puffs' depth
// fed the disc's screen-space reflections, which then "hit" puffs below the
// disc and painted cloud patches onto the disc surface; the transparent pass
// is not part of the SSR/SSAO depth, and it also skips the depth prepass that
// a discarding opaque shader pays for twice.

// Shared with the sky material (vfx/CloudSea.gd copies these from it).
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float exposure = 0.8;
uniform float seam_blend_width = 0.025;
uniform float sky_yaw_offset_deg = 0.0;
uniform float sky_pitch_offset_deg = 0.0;
uniform float grade_amount = 0.0;
uniform vec3 grade_dark : source_color = vec3(0.02, 0.03, 0.08);
uniform vec3 grade_mid : source_color = vec3(0.12, 0.17, 0.33);
uniform vec3 grade_light : source_color = vec3(0.55, 0.64, 0.82);
uniform float grade_gamma = 1.2;
// Copied from SkyThemeDef.cloud_flat_base: the mesh's flat base plane, in
// unit-sphere space below each puff's centre.
uniform float flat_base = 0.15;

// Direction toward the sun / moon.
uniform vec3 light_direction = vec3(0.963087, 0.069011, -0.260192);
// Shading light is lifted to at least this elevation so tops read lit even
// with the sun on the horizon.
uniform float min_light_elevation = 0.3;
uniform vec3 shadow_color : source_color = vec3(0.27, 0.32, 0.48);
uniform vec3 mid_color : source_color = vec3(0.57, 0.41, 0.49);
uniform vec3 lit_color : source_color = vec3(1.0, 0.6, 0.3);
uniform vec3 rim_color : source_color = vec3(1.0, 0.78, 0.42);
// Shade value thresholds between the three flat tones (shadow | mid | lit)
// and their anti-aliased edge width in pixels.
uniform float mid_threshold = 0.38;
uniform float lit_threshold = 0.64;
uniform float band_edge_px = 1.0;
uniform float light_weight = 0.7;
uniform float height_weight = 0.2;
uniform float ambient_shade = -0.05;
uniform float underside_shade = 0.25;
uniform float rim_power = 4.0;
uniform float rim_sun_side = 0.9;
uniform float rim_backlight = 1.4;
uniform float rim_threshold = 0.5;
uniform float rim_softness = 0.08;

// Cauliflower domes from a cellular (F1 distance) noise texture
// (config/sky_themes/puff_noise.tres). The silhouette octave is
// lump_vertex_scale x the shading frequency and pushes the radius out by up
// to lump_height (fraction of radius, centred on lump_bias); the shading
// uses the base frequency plus a finer octave (lump_detail_scale, lump_detail_weight) that scallops
// the band edges (lump_shade). The pattern slides slowly (lump_speed).
uniform sampler2D puff_noise : filter_linear_mipmap, repeat_enable;
uniform float lump_frequency = 0.4;
uniform float lump_cell_radius = 1.0;
uniform float lump_height = 0.35;
uniform float lump_vertex_scale = 0.7;
uniform float lump_detail_scale = 2.3;
uniform float lump_detail_weight = 0.4;
uniform float lump_shade = 0.35;
uniform float lump_bias = 0.6;
uniform float lump_speed = 0.004;
// The fine octave is skipped beyond this camera distance (faded out from 60%).
uniform float detail_lod_m = 260.0;
// Silhouette breathing: amplitude (fraction of radius), speed, and how many
// wave crests run around a puff.
uniform float billow_amount = 0.03;
uniform float billow_speed = 0.35;
uniform float billow_frequency = 2.0;
// Extra hull inflation (fraction of radius) covering the low-poly chord error.
uniform float hull_margin = 0.04;

uniform float fade_start_m = 160.0;
uniform float fade_end_m = 500.0;
uniform float depth_fade_start_m = 40.0;
uniform float depth_fade_end_m = 140.0;
uniform float depth_fade_amount = 0.45;
uniform float near_fade_start_m = 5.0;
uniform float near_fade_end_m = 16.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 puff_centre;
varying vec2 puff_axes;
varying float puff_seed;
varying float base_y;
varying float clump_height;

// Round dome (1 at a cell centre, 0 on the crease between cells); 0..1.
// lump_cell_radius is the normalized F1 distance treated as a cell's edge.
float dome(vec2 p) {
	float f1 = clamp(texture(puff_noise, p).r / lump_cell_radius, 0.0, 1.0);
	return 1.0 - f1 * f1;
}

// Triplanar domes on a unit-sphere direction, `scale` x the base frequency.
float lumps(vec3 u, float seed, float t, float scale) {
	vec3 w = abs(u);
	w = w * w * w;
	w /= max(w.x + w.y + w.z, 0.0001);
	vec2 o = vec2(seed * 0.137 + t, seed * 0.291 - t * 0.7);
	float f = lump_frequency * scale;
	return dome(u.yz * f + o) * w.x + dome(u.xz * f + o) * w.y + dome(u.xy * f + o) * w.z;
}

mat2 rot2(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

void vertex() {
	// world_vertex_coords: VERTEX and NORMAL arrive in world space.
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec2 axes = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	// Inflate the hull to the largest silhouette the fragment stage can carve
	// (the flat base stays put).
	float inflate = lump_height * (1.0 - lump_bias) + billow_amount + hull_margin;
	// NORMAL is not unit length under the instance scale: normalize first.
	vec3 hull_normal = normalize(NORMAL);
	VERTEX += hull_normal * inflate * max(axes.x, axes.y) * smoothstep(-0.3, 0.3, hull_normal.y);
	mat2 r = rot2(TIME * INSTANCE_CUSTOM.x);
	VERTEX.xz = r * VERTEX.xz;
	NORMAL = hull_normal;
	NORMAL.xz = r * NORMAL.xz;
	centre.xz = r * centre.xz;
	world_pos = VERTEX;
	world_normal = NORMAL;
	puff_centre = centre;
	puff_axes = axes;
	puff_seed = INSTANCE_CUSTOM.y;
	base_y = INSTANCE_CUSTOM.z;
	clump_height = max(INSTANCE_CUSTOM.w, 0.001);
}

// 4x4 ordered dither threshold in 0..1.
float bayer4(vec2 frag) {
	ivec2 p = ivec2(mod(frag, 4.0));
	int i = p.x + p.y * 4;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 to_frag = world_pos - cam;
	float dist = length(to_frag);
	float near = smoothstep(near_fade_start_m, near_fade_end_m, dist);
	if (near < bayer4(FRAGCOORD.xy)) {
		discard;
	}
	vec3 view_dir = to_frag / max(dist, 0.001);
	vec3 axes = vec3(puff_axes.x, puff_axes.y, puff_axes.x);
	float t_boil = TIME * lump_speed;
	vec3 mesh_n = normalize(world_normal);
	bool on_base = mesh_n.y < -0.7;

	// Ray against the lumpy ellipsoid, in the puff's unit-sphere space.
	vec3 o = (cam - puff_centre) / axes;
	vec3 v = view_dir / axes;
	float vv = dot(v, v);
	float t_close = -dot(o, v) / vv;
	vec3 closest = o + v * t_close;
	float closest_sq = dot(closest, closest);
	vec3 unit = (world_pos - puff_centre) / axes;
	// Silhouette: the dome radius in the ray's closest-approach direction.
	// Rays that cannot reach even the largest possible puff skip the fetches.
	if (!on_base) {
		float max_radius = 1.0 + (1.0 - lump_bias) * lump_height + billow_amount;
		if (closest_sq > max_radius * max_radius) {
			discard;
		}
		vec3 dir = normalize(closest);
		float coarse = lumps(dir, puff_seed, t_boil, lump_vertex_scale);
		float wave = sin(TIME * billow_speed + puff_seed + dot(dir, vec3(1.0, 0.7, 1.3)) * billow_frequency);
		float radius = 1.0 + (coarse - lump_bias) * lump_height + wave * billow_amount;
		float miss = closest_sq - radius * radius;
		if (miss > 0.0) {
			discard;
		}
		vec3 entry = o + v * (t_close - sqrt(-miss / vv));
		// The part of the ellipsoid below the flat base does not exist.
		if (entry.y < -flat_base) {
			discard;
		}
		if (t_close > 0.0) {
			unit = entry;
		}
	}
	vec3 surface = puff_centre + unit * axes;

	// Ellipsoid normal at the entry point; the flat base faces straight down.
	vec3 n = on_base ? vec3(0.0, -1.0, 0.0) : normalize(unit / axes);
	vec3 sun = normalize(light_direction);
	vec3 light = normalize(vec3(sun.x, max(sun.y, min_light_elevation), sun.z));

	// Shading domes at the entry point (the flat base stays plain); the fine
	// octave is dropped with distance.
	float lump = lump_bias;
	if (!on_base) {
		lump = lumps(normalize(unit), puff_seed, t_boil, 1.0);
		if (dist < detail_lod_m && lump_detail_weight > 0.0) {
			float detail = lumps(normalize(unit), puff_seed + 3.1, t_boil, lump_detail_scale);
			lump = mix(lump, detail, lump_detail_weight * (1.0 - smoothstep(detail_lod_m * 0.6, detail_lod_m, dist)));
		}
	}
	float wrap = dot(n, light) * 0.5 + 0.5;
	float height_rel = clamp((surface.y - base_y) / clump_height, 0.0, 1.0);
	float shade = wrap * light_weight + height_rel * height_weight + ambient_shade + (lump - lump_bias) * lump_shade;
	shade -= underside_shade * clamp(-n.y, 0.0, 1.0);
	float edge = max(fwidth(shade) * band_edge_px, 0.0001);
	vec3 col = mix(shadow_color, mid_color, smoothstep(mid_threshold - edge, mid_threshold + edge, shade));
	col = mix(col, lit_color, smoothstep(lit_threshold - edge, lit_threshold + edge, shade));

	// Rim: silhouette edges facing the sun, much stronger looking toward it.
	float fresnel = pow(1.0 - clamp(dot(n, -view_dir), 0.0, 1.0), rim_power);
	float toward_sun = clamp(dot(view_dir, sun), 0.0, 1.0);
	float sun_side = clamp(dot(n, light), 0.0, 1.0);
	float rim = fresnel * (sun_side * rim_sun_side + toward_sun * toward_sun * rim_backlight);
	// The distance fade below would leave bright rim outlines around puffs
	// whose bodies already match the sky, so the rim fades out first.
	float fade = smoothstep(fade_start_m, fade_end_m, dist);
	rim *= (1.0 - fade) * (1.0 - fade);
	col = mix(col, rim_color, smoothstep(rim_threshold, rim_threshold + rim_softness, rim));
	// Same exposure as the sky, so theme colours can be picked straight from
	// the painted panorama.
	col *= exposure;

	// Blend into the sky drawn behind: distance haze plus depth below the disc.
	float depth = smoothstep(depth_fade_start_m, depth_fade_end_m, -surface.y) * depth_fade_amount;
	fade = 1.0 - (1.0 - fade) * (1.0 - depth);
	if (fade > 0.001) {
		vec2 sky_uv = sky_panorama_uv(view_dir, sky_yaw_offset_deg, sky_pitch_offset_deg);
		vec3 sky = panorama_lod(panorama, sky_uv, seam_blend_width) * exposure;
		sky = moonlit_grade(sky, grade_amount, grade_dark, grade_mid, grade_light, grade_gamma);
		col = mix(col, sky, fade);
	}
	ALBEDO = col;
	ALPHA = 1.0;
}
