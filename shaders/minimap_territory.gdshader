shader_type canvas_item;
render_mode unshaded;

// Bontago-1pi.11.11: colours the minimap's territory from the raster's per-cell
// textures on the GPU (was a 160x160 GDScript per-pixel loop, 55-100 ms).
// One output pixel looks up the cell under it through the inverse of the
// image basis (image_right / image_forward), exactly as the old loop did.

const int MAX_SLOTS = 16;

uniform sampler2D team_tex : filter_nearest, repeat_disable;
uniform sampler2D hole_tex : filter_nearest, repeat_disable;
uniform sampler2D disk_tex : filter_nearest, repeat_disable;
uniform vec4 slot_colors[MAX_SLOTS];
uniform int slot_count = 0;
uniform vec4 unowned_color = vec4(0.0);
// Bontago-1pi.11.42: holes read as the disc's void colour (HoleVisualTuning).
uniform vec4 hole_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float half_extent = 1.0;
uniform vec2 image_right = vec2(1.0, 0.0);
uniform vec2 image_forward = vec2(0.0, 1.0);
uniform float grid_half_extent = 1.0;
uniform float grid_cell_size = 1.0;
uniform int grid_res = 1;

void fragment() {
	float u = (UV.x * 2.0 - 1.0) * half_extent;
	float v = (1.0 - UV.y * 2.0) * half_extent;
	vec2 world = u * image_right + v * image_forward;
	vec2 cellf = floor((world + vec2(grid_half_extent)) / grid_cell_size);
	ivec2 cell = ivec2(cellf);
	if (cell.x < 0 || cell.y < 0 || cell.x >= grid_res || cell.y >= grid_res) {
		COLOR = vec4(0.0);
	} else if (texelFetch(disk_tex, cell, 0).r < 0.001) {
		COLOR = vec4(0.0);
	} else {
		int team = int(texelFetch(team_tex, cell, 0).r * 255.0 + 0.5);
		bool hole = texelFetch(hole_tex, cell, 0).r > 0.001;
		if (hole) {
			COLOR = hole_color;
		} else if (team >= slot_count || team >= MAX_SLOTS) {
			COLOR = unowned_color;
		} else {
			COLOR = slot_colors[team];
		}
	}
}
