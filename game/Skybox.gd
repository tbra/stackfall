class_name Skybox
extends Node3D
## Runtime-loaded six-face placeholder skybox from the original 2003 Bontago
## install (spec 2.10, presentation). The faces are third-party assets and
## never shipped in this public repo (CLAUDE.md); tools/install_original_assets.ps1
## (owned by another package) copies them to
## `res://assets/original/textures/<set>/<face>.jpg` for local testing, and
## load_set() falls back to the existing ProceduralSkyMaterial untouched
## whenever that folder or a face inside it is missing.
##
## DECISION (game/Skybox.gd, Bontago-1en/assets-sky): six unshaded quads on a
## big inverted box, not a `shader_type sky` sampling a Cubemap. The box does
## not follow the camera -- box_half_extent (400 m) is far larger than any
## map's field_radius (60 m max) or the camera's zoom range
## (config/camera_tuning.tres: zoom_max 100 m), so the parallax from orbiting
## within the field is invisible in practice, at zero extra cost.
##
## DECISION (game/Skybox.gd, Bontago-xtq.8, owner 2026-09-23: "it reflects
## whatever light source you've put in but not the skybox we added
## recently"): the box alone was never enough -- the WorldEnvironment's own
## Sky resource is a separate thing the render server samples for reflections
## and ambient light (Main.tscn: ambient_light_source = AMBIENT_SOURCE_SKY),
## and drawing a box in front of the camera does not change what that
## resource shows. load_set() success now ALSO installs a `shader_type sky`
## ShaderMaterial (shaders/cubemap_sky.gdshader) onto `environment.sky.
## sky_material`, sampling the same six face textures with the same
## SkyboxConfig.face_rotations/face_flip_u/face_flip_v correction the box
## uses (shaders/cubemap_sky.gdshader's own doc has the per-face direction
## algebra, derived by inverting Skybox._face_corners()' corner mapping and
## checked against all four UV corners of all six faces). Reflections/ambient
## now show the loaded set's horizon instead of the ProceduralSkyMaterial
## gradient; a missing/failed set restores the original ProceduralSkyMaterial
## on the Sky resource exactly as it restores the box's fallback.
##
## The box mesh itself is deliberately kept rather than dropped now that the
## sky shader exists: the box is the one part of this system whose
## correctness was verified pixel-by-pixel (tools/skybox_seam_probe.gd's
## measured seam error) and is trivially checkable by eye in a single
## screenshot; the sky shader's face-selection math (its sky() function) was
## checked algebraically against all six faces' corners (see
## shaders/cubemap_sky.gdshader) and
## against two live camera yaws (docs/sky-reflection-before.png/-after.png),
## but a shader bug that only shows up at a grazing reflection angle this
## package's screenshots did not happen to catch would otherwise have no
## direct-view fallback to catch it visually during play. Once the sky
## shader has more mileage (e.g. the seam probe or an equivalent check is
## extended to score it the same way it scores the box), dropping the box and
## letting the sky alone draw the background is a safe, mechanical follow-up.

@export var config: SkyboxConfig = preload("res://config/skybox_config.tres")
## The live Environment resource Main.tscn's WorldEnvironment displays
## (wired there by a plain node-property reference to the same sub-resource,
## not a node path -- CLAUDE.md's "no deep node paths" is about get_node()
## chains, not sharing one Resource two nodes both already own a reference
## to). Optional (null in a fixture test that only cares about the box/
## fallback_active state, e.g. most of tests/unit/test_skybox.gd): every sky-
## material write below is skipped when this or its .sky is unset.
@export var environment: Environment = null

const SKY_SHADER: Shader = preload("res://shaders/cubemap_sky.gdshader")

## The Sky's own material before this node ever touched it (Main.tscn's
## ProceduralSkyMaterial, captured once in _ready()) -- restored whenever
## load_set() falls back, the same moment the box itself is hidden.
var _fallback_sky_material: Material = null

## True whenever no textured box is showing (initial state, a missing
## set/face, or config.enabled == false) -- the existing ProceduralSkyMaterial
## is what's visible in every one of those cases. Read by tests and by a
## manual tester checking print() output.
var fallback_active: bool = true

var _face_textures: Dictionary = {}
var _face_meshes: Dictionary = {}


func _ready() -> void:
	if environment != null and environment.sky != null:
		_fallback_sky_material = environment.sky.sky_material
	for face_name: String in config.face_names:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.name = face_name.capitalize()
		mesh_instance.visible = false
		# The box is static and much larger than the play field (see class
		# doc), so there is nothing worth frustum-culling per frame against a
		# camera that is always deep inside it.
		mesh_instance.extra_cull_margin = config.box_half_extent
		add_child(mesh_instance)
		_face_meshes[face_name] = mesh_instance


## Called once per match/scene start (game/Main.gd) with the map's chosen set
## (config/MapDef.gd's skybox_set). `root_override` lets tests point this at a
## temp directory instead of the real asset root. Returns true and shows the
## textured box on success; returns false, prints one info line, and leaves
## the box hidden (so the ProceduralSkyMaterial fallback shows through) on
## any failure -- never a Godot error for the ordinary "assets not installed"
## case, since both existence checks below run before any file is opened.
##
## Face lookup is exact-case (FileAccess.file_exists() against
## config.face_names, which are lowercase): tools/install_original_assets.ps1
## (owned by another package) already lowercases every face file it copies,
## so this never needs to special-case the original install's mixed-case
## source names itself (see tests/unit/test_skybox.gd's DECISION on why that
## is not separately tested here).
func load_set(set_name: String, root_override: String = "") -> bool:
	_face_textures.clear()
	if not config.enabled:
		fallback_active = true
		_hide_faces()
		return false

	var root: String = root_override if root_override != "" else _resolve_asset_root()
	var set_dir: String = root.path_join(set_name)
	if not DirAccess.dir_exists_absolute(set_dir):
		fallback_active = true
		_hide_faces()
		print("Skybox: set '%s' not found at %s -- using procedural sky" % [set_name, set_dir])
		return false

	for face_name: String in config.face_names:
		var file_path: String = set_dir.path_join(face_name + ".jpg")
		if not FileAccess.file_exists(file_path):
			fallback_active = true
			_hide_faces()
			print("Skybox: face '%s' missing for set '%s' at %s -- using procedural sky" % [
				face_name, set_name, file_path,
			])
			return false
		# Load through an absolute filesystem path: Image.load_from_file on a
		# res:// path prints an engine warning about bypassing the import
		# pipeline (GUT counts it as an error) and the editor would import the
		# gitignored jpgs; assets/original carries a .gdignore for the same
		# reason (tools/install_original_assets.ps1 writes it).
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path(file_path))
		if image == null:
			fallback_active = true
			_hide_faces()
			print("Skybox: face '%s' for set '%s' failed to decode -- using procedural sky" % [
				face_name, set_name,
			])
			return false
		_face_textures[face_name] = ImageTexture.create_from_image(image)

	fallback_active = false
	_build_faces()
	return true


## Test/inspection seam: the ImageTexture load_set() produced for one face,
## or null if load_set() has not succeeded for that face (fallback or not yet
## called).
func get_face_texture(face_name: String) -> ImageTexture:
	return _face_textures.get(face_name) as ImageTexture


func _resolve_asset_root() -> String:
	if OS.has_feature("editor"):
		return "res://assets/original/textures"
	return OS.get_executable_path().get_base_dir().path_join("assets/original/textures")


func _hide_faces() -> void:
	for mesh_instance: MeshInstance3D in _face_meshes.values():
		mesh_instance.visible = false
	_restore_fallback_sky()


func _build_faces() -> void:
	for face_name: String in config.face_names:
		var mesh_instance: MeshInstance3D = _face_meshes.get(face_name) as MeshInstance3D
		if mesh_instance == null:
			continue
		mesh_instance.mesh = _build_face_mesh(face_name)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# CULL_DISABLED: the box's faces face inward toward the camera, and
		# with this set the triangle winding below does not have to be
		# reasoned about at all -- both sides render regardless.
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_texture = _face_textures.get(face_name)
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.visible = true
	_install_sky_material()


## Restores the Environment's Sky to whatever material it carried before this
## node ever touched it (Main.tscn's ProceduralSkyMaterial) -- a no-op when no
## `environment` was wired (most of tests/unit/test_skybox.gd) or _ready()
## never captured one (environment.sky was null at the time).
func _restore_fallback_sky() -> void:
	if environment == null or environment.sky == null or _fallback_sky_material == null:
		return
	environment.sky.sky_material = _fallback_sky_material


## Bontago-xtq.8: installs shaders/cubemap_sky.gdshader onto the Environment's
## Sky, with the same six face textures and the same SkyboxConfig.
## face_rotations/face_flip_u/face_flip_v the box's own quads use -- see the
## class doc and the shader's doc for why the two are the same convention
## read two different ways. A no-op when no `environment` was wired.
func _install_sky_material() -> void:
	if environment == null or environment.sky == null:
		return
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SKY_SHADER
	for index: int in range(config.face_names.size()):
		var face_name: String = config.face_names[index]
		var rotation: int = config.face_rotations[index] if index < config.face_rotations.size() else 0
		var flip_u: bool = index < config.face_flip_u.size() and config.face_flip_u[index] != 0
		var flip_v: bool = index < config.face_flip_v.size() and config.face_flip_v[index] != 0
		material.set_shader_parameter(face_name + "_tex", _face_textures.get(face_name))
		material.set_shader_parameter(face_name + "_rotation", rotation)
		material.set_shader_parameter(face_name + "_flip_u", flip_u)
		material.set_shader_parameter(face_name + "_flip_v", flip_v)
	environment.sky.sky_material = material
	# DECISION (game/Skybox.gd): PROCESS_MODE_QUALITY, not the default
	# AUTOMATIC/INCREMENTAL. Reflections/ambient are read from the sky's own
	# radiance/irradiance maps, not the background pixels directly --
	# INCREMENTAL mode (meant for a sky that keeps changing, e.g. a day/night
	# cycle) spreads that recompute over many frames, so a freshly-loaded set
	# would keep showing the *previous* sky's (or the fallback gradient's)
	# stale reflection for a visible stretch of play. QUALITY recomputes fully
	# on the next frame instead; this skybox only ever changes at
	# load_set() (once per match/map), so the one-frame cost is negligible.
	environment.sky.process_mode = Sky.PROCESS_MODE_QUALITY


## One quad per face of a box_half_extent-sided cube, in Skybox-local space
## (this node sits at the world origin -- see class doc on why it does not
## follow the camera). Built directly rather than from BoxMesh/QuadMesh so
## each face's UV orientation is an explicit, checkable base mapping (see
## _face_corners()) with a per-face correction on top of it
## (config.face_rotations/face_flip_u/face_flip_v, applied by
## _apply_face_transform() below) -- the base mapping alone ("front" unrotated
## with back/left/right as the 90-degree turns around it, top/bottom attached
## to front's edges unrotated) turned out NOT to match the original install's
## own per-face orientation for any of the six files; every face needs its
## correction. See tools/skybox_seam_probe.gd, which found that correction
## numerically, for why and the measured seam error.
func _build_face_mesh(face_name: String) -> ArrayMesh:
	var corners: Dictionary = _face_corners(StringName(face_name), config.box_half_extent)
	if corners.is_empty():
		return null

	var index: int = config.face_names.find(face_name)
	var rotation: int = config.face_rotations[index] if index >= 0 and index < config.face_rotations.size() else 0
	var flip_u: bool = index >= 0 and index < config.face_flip_u.size() and config.face_flip_u[index] != 0
	var flip_v: bool = index >= 0 and index < config.face_flip_v.size() and config.face_flip_v[index] != 0

	var positions: PackedVector3Array = PackedVector3Array([
		corners["p00"], corners["p10"], corners["p01"], corners["p11"],
	])
	var uvs: PackedVector2Array = PackedVector2Array([
		_apply_face_transform(0.0, 0.0, flip_u, flip_v, rotation),
		_apply_face_transform(1.0, 0.0, flip_u, flip_v, rotation),
		_apply_face_transform(0.0, 1.0, flip_u, flip_v, rotation),
		_apply_face_transform(1.0, 1.0, flip_u, flip_v, rotation),
	])
	var indices: PackedInt32Array = PackedInt32Array([0, 2, 1, 1, 2, 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Applies (in order) an optional horizontal flip, an optional vertical
## flip, then `rotation` quarter turns (each turn: (u,v) -> (v, 1-u)) to a
## face's base UV coordinate. Shared, as a static method, with
## tools/skybox_seam_probe.gd so the probe's search space and Skybox's actual
## render are provably the same transform -- the probe's printed table is
## meaningless otherwise. rotation is taken mod 4 (any int is accepted so a
## config value never has to be pre-clamped).
static func _apply_face_transform(u: float, v: float, flip_u: bool, flip_v: bool, rotation: int) -> Vector2:
	var uu: float = 1.0 - u if flip_u else u
	var vv: float = 1.0 - v if flip_v else v
	var turns: int = ((rotation % 4) + 4) % 4
	for _i: int in range(turns):
		var next_u: float = vv
		var next_v: float = 1.0 - uu
		uu = next_u
		vv = next_v
	return Vector2(uu, vv)


## p00/p10/p01/p11 are this face's UV (0,0)/(1,0)/(0,1)/(1,1) corners in
## world space (h = box_half_extent), before any face_rotations/flip
## correction is applied (that happens in _build_face_mesh() above via
## _apply_face_transform()). See the class/method doc above for the
## convention these follow. Static (and called that way by the seam probe
## too) since it is a pure function of face + h, with no instance state.
static func _face_corners(face: StringName, h: float) -> Dictionary:
	match face:
		&"front":
			return {
				"p00": Vector3(-h, h, -h), "p10": Vector3(h, h, -h),
				"p01": Vector3(-h, -h, -h), "p11": Vector3(h, -h, -h),
			}
		&"back":
			return {
				"p00": Vector3(h, h, h), "p10": Vector3(-h, h, h),
				"p01": Vector3(h, -h, h), "p11": Vector3(-h, -h, h),
			}
		&"right":
			return {
				"p00": Vector3(h, h, -h), "p10": Vector3(h, h, h),
				"p01": Vector3(h, -h, -h), "p11": Vector3(h, -h, h),
			}
		&"left":
			return {
				"p00": Vector3(-h, h, h), "p10": Vector3(-h, h, -h),
				"p01": Vector3(-h, -h, h), "p11": Vector3(-h, -h, -h),
			}
		&"top":
			return {
				"p00": Vector3(-h, h, h), "p10": Vector3(h, h, h),
				"p01": Vector3(-h, h, -h), "p11": Vector3(h, h, -h),
			}
		&"bottom":
			return {
				"p00": Vector3(-h, -h, -h), "p10": Vector3(h, -h, -h),
				"p01": Vector3(-h, -h, h), "p11": Vector3(h, -h, h),
			}
		_:
			return {}
