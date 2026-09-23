shader_type sky;
// Bontago-xtq.8 (owner, 2026-09-23: "it reflects whatever light source
// you've put in but not the skybox we added recently"). game/Skybox.gd's box
// (six unshaded quads) draws the loaded set directly in front of the camera,
// but the WorldEnvironment's Sky resource never saw it, so
// ambient_light_source = AMBIENT_SOURCE_SKY (Main.tscn) and every reflective
// surface (shaders/territory.gdshader's disk) kept sampling the
// ProceduralSkyMaterial instead -- a gradient sky no set installs into.
//
// This shader is installed by game/Skybox.gd (as the Environment's own
// Sky.sky_material) once load_set() succeeds, so the render server's sky pass
// -- and so both the background AND the irradiance/radiance maps every
// reflection and ambient sample draws from -- shows the same six faces the
// box shows, not a fallback gradient.
//
// **Same convention as the box, deliberately.** game/Skybox.gd builds the box
// from _face_corners() (which face sits where in world space) and
// _apply_face_transform() (the per-face flip/rotation correction
// tools/skybox_seam_probe.gd found numerically, config/SkyboxConfig.gd's
// face_rotations/face_flip_u/face_flip_v). This shader is the same two
// pieces read backwards: given a view direction (EYEDIR) instead of a mesh
// position, pick_face_uv() below inverts _face_corners()' corner mapping
// algebraically (see game/Skybox.gd's class doc for the full derivation this
// mirrors face by face -- every one of the six was checked against its own
// four UV corners), then apply_face_transform() is a literal line-for-line
// port of Skybox._apply_face_transform() so both draw the exact same pixel
// for the exact same direction -- there is no second, independently-tuned
// table to keep in sync.

uniform sampler2D front_tex : source_color, filter_linear;
uniform sampler2D back_tex : source_color, filter_linear;
uniform sampler2D left_tex : source_color, filter_linear;
uniform sampler2D right_tex : source_color, filter_linear;
uniform sampler2D top_tex : source_color, filter_linear;
uniform sampler2D bottom_tex : source_color, filter_linear;

uniform int front_rotation = 0;
uniform bool front_flip_u = false;
uniform bool front_flip_v = false;
uniform int back_rotation = 0;
uniform bool back_flip_u = false;
uniform bool back_flip_v = false;
uniform int left_rotation = 0;
uniform bool left_flip_u = false;
uniform bool left_flip_v = false;
uniform int right_rotation = 0;
uniform bool right_flip_u = false;
uniform bool right_flip_v = false;
uniform int top_rotation = 0;
uniform bool top_flip_u = false;
uniform bool top_flip_v = false;
uniform int bottom_rotation = 0;
uniform bool bottom_flip_u = false;
uniform bool bottom_flip_v = false;

// Line-for-line port of game/Skybox.gd's static _apply_face_transform():
// an optional horizontal flip, then an optional vertical flip, then
// `rotation` quarter turns ((u, v) -> (v, 1 - u) each turn).
vec2 apply_face_transform(vec2 uv, bool flip_u, bool flip_v, int rotation) {
	float uu = flip_u ? 1.0 - uv.x : uv.x;
	float vv = flip_v ? 1.0 - uv.y : uv.y;
	int turns = ((rotation % 4) + 4) % 4;
	for (int i = 0; i < 4; i++) {
		if (i >= turns) {
			break;
		}
		float next_u = vv;
		float next_v = 1.0 - uu;
		uu = next_u;
		vv = next_v;
	}
	return vec2(uu, vv);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 ad = abs(d);
	vec2 raw_uv;
	vec3 color;

	if (ad.x >= ad.y && ad.x >= ad.z) {
		if (d.x > 0.0) {
			// right (x = +h): p00=(h,h,-h)->uv(0,0), p10=(h,h,h)->uv(1,0).
			raw_uv = vec2((d.z / d.x + 1.0) * 0.5, (1.0 - d.y / d.x) * 0.5);
			color = texture(right_tex, apply_face_transform(raw_uv, right_flip_u, right_flip_v, right_rotation)).rgb;
		} else {
			// left (x = -h): p00=(-h,h,h)->uv(0,0), p10=(-h,h,-h)->uv(1,0).
			raw_uv = vec2((1.0 - d.z / (-d.x)) * 0.5, (1.0 - d.y / (-d.x)) * 0.5);
			color = texture(left_tex, apply_face_transform(raw_uv, left_flip_u, left_flip_v, left_rotation)).rgb;
		}
	} else if (ad.y >= ad.x && ad.y >= ad.z) {
		if (d.y > 0.0) {
			// top (y = +h): p00=(-h,h,h)->uv(0,0), p10=(h,h,h)->uv(1,0).
			raw_uv = vec2((d.x / d.y + 1.0) * 0.5, (1.0 - d.z / d.y) * 0.5);
			color = texture(top_tex, apply_face_transform(raw_uv, top_flip_u, top_flip_v, top_rotation)).rgb;
		} else {
			// bottom (y = -h): p00=(-h,-h,-h)->uv(0,0), p10=(h,-h,-h)->uv(1,0).
			raw_uv = vec2((d.x / (-d.y) + 1.0) * 0.5, (d.z / (-d.y) + 1.0) * 0.5);
			color = texture(bottom_tex, apply_face_transform(raw_uv, bottom_flip_u, bottom_flip_v, bottom_rotation)).rgb;
		}
	} else {
		if (d.z < 0.0) {
			// front (z = -h): p00=(-h,h,-h)->uv(0,0), p10=(h,h,-h)->uv(1,0).
			raw_uv = vec2((d.x / (-d.z) + 1.0) * 0.5, (1.0 - d.y / (-d.z)) * 0.5);
			color = texture(front_tex, apply_face_transform(raw_uv, front_flip_u, front_flip_v, front_rotation)).rgb;
		} else {
			// back (z = +h): p00=(h,h,h)->uv(0,0), p10=(-h,h,h)->uv(1,0).
			raw_uv = vec2((1.0 - d.x / d.z) * 0.5, (1.0 - d.y / d.z) * 0.5);
			color = texture(back_tex, apply_face_transform(raw_uv, back_flip_u, back_flip_v, back_rotation)).rgb;
		}
	}

	COLOR = color;
}
