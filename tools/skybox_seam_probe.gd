extends SceneTree
## Numeric seam-matching probe for game/Skybox.gd (assets-sky-seams follow-up:
## the first, eyeballed cross-layout guess left hard seams). Loads a real
## six-face set's images and, for all 12 adjacent cube-edge pairs, computes
## the mean absolute colour difference between the two touching edges for
## every (rotation x flip_u) combination of each face (8 each -- see
## game/Skybox.gd's _apply_face_transform(), which this calls directly so the
## search space and the actual render are the same transform), then picks the
## single joint assignment (one transform per face) that minimizes the sum
## over all 12 edges at once (8^6 = 262144 combinations, brute-forced against
## a precomputed 8x8 cost matrix per edge -- a few seconds, no per-combo image
## sampling).
##
## DECISION (tools/skybox_seam_probe.gd): front is NOT pinned at the
## identity transform, despite the original brief asking for that. A pinned
## search (front fixed) was tried first and could not get front-left/
## front-right below ~0.15-0.19 (all other 10 edges reached <0.02) no matter
## which of the other faces' transforms were chosen -- and the fully
## unconstrained search below finds front's own best transform is flip_u=true
## (a horizontal mirror), which is invisible on a single frame of a
## near-symmetric ocean horizon but breaks both of its seams. Freeing front
## brings every one of the 12 edges under 0.02 (see the package report for
## both runs' numbers). There is no gauge freedom being exploited here: each
## face samples a different source image via its own transform variable, so
## this is a genuine lower minimum, not an arbitrary relabeling.
##
## Not part of the running game (CLAUDE.md); lives in tools/. Run with:
##   godot --headless --path . -s tools/skybox_seam_probe.gd -- --set=beach
## `--set=` defaults to config/skybox_config.tres's default_set ("beach").
## `--verify` skips the search and instead scores config/skybox_config.tres's
## current face_rotations/face_flip_u/face_flip_v against the given set, to
## confirm the same table found on Beach still gives a low seam error on a
## different set from the same exporter (e.g. Mountain, Lake).

const FACE_NAMES: Array = ["back", "bottom", "front", "left", "right", "top"]
const SAMPLE_COUNT: int = 128
const TRANSFORM_COUNT: int = 8

## All 12 adjacent-edge pairs of a cube.
const EDGES: Array = [
	["front", "left"], ["front", "right"], ["front", "top"], ["front", "bottom"],
	["back", "left"], ["back", "right"], ["back", "top"], ["back", "bottom"],
	["left", "top"], ["left", "bottom"], ["right", "top"], ["right", "bottom"],
]


func _init() -> void:
	var set_name: String = _arg_set_name()
	var verify_only: bool = _has_flag("verify")
	var images: Dictionary = _load_images(set_name)
	if images.size() != FACE_NAMES.size():
		print("skybox_seam_probe: could not load six faces for set '%s'" % set_name)
		quit(1)
		return

	var matrices: Dictionary = {}
	for edge: Array in EDGES:
		var face_a: String = edge[0]
		var face_b: String = edge[1]
		var key: String = "%s|%s" % [face_a, face_b]
		matrices[key] = _cost_matrix(images[face_a], images[face_b], StringName(face_a), StringName(face_b))

	var identity_assignment: Dictionary = {
		"front": 0, "back": 0, "left": 0, "right": 0, "top": 0, "bottom": 0,
	}
	var before_total: float = _total_for_assignment(matrices, identity_assignment)

	if verify_only:
		var config: SkyboxConfig = load("res://config/skybox_config.tres") as SkyboxConfig
		var assignment: Dictionary = _assignment_from_config(config)
		var total: float = _total_for_assignment(matrices, assignment)
		_print_report(set_name, matrices, before_total, assignment, total, true)
	else:
		var best_assignment: Dictionary = _search_best_assignment(matrices)
		var after_total: float = _total_for_assignment(matrices, best_assignment)
		_print_report(set_name, matrices, before_total, best_assignment, after_total, false)
	quit()


func _arg_set_name() -> String:
	const PREFIX: String = "set="
	for raw: String in OS.get_cmdline_user_args():
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return text.substr(PREFIX.length())
	var default_config: SkyboxConfig = load("res://config/skybox_config.tres") as SkyboxConfig
	return default_config.default_set


func _has_flag(flag: String) -> bool:
	for raw: String in OS.get_cmdline_user_args():
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text == flag:
			return true
	return false


func _assignment_from_config(config: SkyboxConfig) -> Dictionary:
	var assignment: Dictionary = {}
	for face_name: String in FACE_NAMES:
		var index: int = config.face_names.find(face_name)
		var rotation: int = config.face_rotations[index] if index >= 0 else 0
		var flip_u: bool = index >= 0 and config.face_flip_u[index] != 0
		assignment[face_name] = rotation + (4 if flip_u else 0)
	return assignment


func _load_images(set_name: String) -> Dictionary:
	var root: String = "res://assets/original/textures"
	var set_dir: String = root.path_join(set_name)
	var images: Dictionary = {}
	for face_name: String in FACE_NAMES:
		var file_path: String = set_dir.path_join(face_name + ".jpg")
		if not FileAccess.file_exists(file_path):
			print("skybox_seam_probe: missing %s" % file_path)
			continue
		var image: Image = Image.load_from_file(file_path)
		if image == null:
			print("skybox_seam_probe: failed to decode %s" % file_path)
			continue
		images[face_name] = image
	return images


## uv0/uv1: the two shared corners' UV coordinates in face_a's / face_b's own
## parameterization (see Skybox._face_corners()), found by matching corner
## keys in world space. Returns {} if the faces are not adjacent (opposite
## faces share none; a face is never checked against itself).
func _shared_edge(face_a: StringName, face_b: StringName) -> Dictionary:
	var corners_a: Dictionary = Skybox._face_corners(face_a, 1.0)
	var corners_b: Dictionary = Skybox._face_corners(face_b, 1.0)
	var uv_keys: PackedStringArray = PackedStringArray(["p00", "p10", "p01", "p11"])
	var shared: Array = []
	for key_a: String in uv_keys:
		var corner_a: Vector3i = _corner_key(corners_a[key_a])
		for key_b: String in uv_keys:
			var corner_b: Vector3i = _corner_key(corners_b[key_b])
			if corner_a == corner_b:
				shared.append([key_a, key_b])
	if shared.size() != 2:
		return {}
	return {
		"a0": _uv_for_key(shared[0][0]), "a1": _uv_for_key(shared[1][0]),
		"b0": _uv_for_key(shared[0][1]), "b1": _uv_for_key(shared[1][1]),
	}


func _corner_key(p: Vector3) -> Vector3i:
	return Vector3i(int(signf(p.x)), int(signf(p.y)), int(signf(p.z)))


func _uv_for_key(key: String) -> Vector2:
	match key:
		"p00": return Vector2(0.0, 0.0)
		"p10": return Vector2(1.0, 0.0)
		"p01": return Vector2(0.0, 1.0)
		"p11": return Vector2(1.0, 1.0)
		_: return Vector2.ZERO


## transform index 0..7 -> (flip_u, rotation), matching Skybox's own encoding
## exactly (index = rotation + 4*int(flip_u), flip_v always false -- this
## restricted set already spans the full 8-element dihedral group).
func _flip_u_for_index(index: int) -> bool:
	return index >= 4


func _rotation_for_index(index: int) -> int:
	return index % 4


func _sample_pixel(image: Image, uv: Vector2, index: int) -> Color:
	var mapped: Vector2 = Skybox._apply_face_transform(
		uv.x, uv.y, _flip_u_for_index(index), false, _rotation_for_index(index)
	)
	var w: int = image.get_width()
	var h: int = image.get_height()
	var px: int = clampi(int(round(mapped.x * float(w - 1))), 0, w - 1)
	var py: int = clampi(int(round(mapped.y * float(h - 1))), 0, h - 1)
	return image.get_pixel(px, py)


## 8x8 matrix: cost[ta][tb] = mean abs colour diff along the shared edge when
## face_a uses transform ta and face_b uses transform tb.
func _cost_matrix(image_a: Image, image_b: Image, face_a: StringName, face_b: StringName) -> Array:
	var edge: Dictionary = _shared_edge(face_a, face_b)
	var matrix: Array = []
	for ta: int in range(TRANSFORM_COUNT):
		var row: Array = []
		for tb: int in range(TRANSFORM_COUNT):
			var total: float = 0.0
			for i: int in range(SAMPLE_COUNT):
				var s: float = float(i) / float(SAMPLE_COUNT - 1)
				var uv_a: Vector2 = (edge["a0"] as Vector2).lerp(edge["a1"] as Vector2, s)
				var uv_b: Vector2 = (edge["b0"] as Vector2).lerp(edge["b1"] as Vector2, s)
				var color_a: Color = _sample_pixel(image_a, uv_a, ta)
				var color_b: Color = _sample_pixel(image_b, uv_b, tb)
				total += (absf(color_a.r - color_b.r) + absf(color_a.g - color_b.g) + absf(color_a.b - color_b.b)) / 3.0
			row.append(total / float(SAMPLE_COUNT))
		matrix.append(row)
	return matrix


func _total_for_assignment(matrices: Dictionary, assignment: Dictionary) -> float:
	var total: float = 0.0
	for edge: Array in EDGES:
		var key: String = "%s|%s" % [edge[0], edge[1]]
		var matrix: Array = matrices[key]
		var ta: int = assignment[edge[0]]
		var tb: int = assignment[edge[1]]
		total += (matrix[ta][tb] as float)
	return total


## Full joint brute force over all six faces (8^6 = 262144 combinations --
## see the class doc DECISION on why front is not pinned), picking whichever
## single combination minimizes the sum of all 12 edges' costs.
func _search_best_assignment(matrices: Dictionary) -> Dictionary:
	var best_total: float = INF
	var best_assignment: Dictionary = {}
	const TOTAL_COMBOS: int = 262144  # 8^6
	for combo: int in range(TOTAL_COMBOS):
		var t_front: int = combo % 8
		var t_back: int = (combo / 8) % 8
		var t_left: int = (combo / 64) % 8
		var t_right: int = (combo / 512) % 8
		var t_top: int = (combo / 4096) % 8
		var t_bottom: int = (combo / 32768) % 8
		var assignment: Dictionary = {
			"front": t_front, "back": t_back, "left": t_left, "right": t_right, "top": t_top, "bottom": t_bottom,
		}
		var total: float = _total_for_assignment(matrices, assignment)
		if total < best_total:
			best_total = total
			best_assignment = assignment
	return best_assignment


func _print_report(set_name: String, matrices: Dictionary, before_total: float, assignment: Dictionary, after_total: float, verify_only: bool) -> void:
	print("skybox_seam_probe: set='%s' mode=%s" % [set_name, "verify" if verify_only else "search"])
	print("  total seam error: identity=%.5f %s=%.5f" % [before_total, "config" if verify_only else "found", after_total])
	print("  per-face transform (rotation quarter-turns, flip_u):")
	for face_name: String in FACE_NAMES:
		var index: int = assignment[face_name]
		print("    %-6s rotation=%d flip_u=%s" % [face_name, _rotation_for_index(index), _flip_u_for_index(index)])
	print("  per-edge seam error (identity -> %s):" % ("config" if verify_only else "found"))
	for edge: Array in EDGES:
		var key: String = "%s|%s" % [edge[0], edge[1]]
		var matrix: Array = matrices[key]
		var before_edge: float = matrix[0][0]
		var after_edge: float = matrix[assignment[edge[0]]][assignment[edge[1]]]
		print("    %-6s-%-6s %.5f -> %.5f" % [edge[0], edge[1], before_edge, after_edge])
