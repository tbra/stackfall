extends GutTest
## game/Skybox.gd (spec 2.10): load_set() against a temp fixture root, so
## these tests never touch the real (gitignored, third-party)
## assets/original/textures folder. Config/MapDef.gd's skybox_set field is
## covered here too, since Skybox.load_set() is the only consumer of it.

const FIXTURE_ROOT: String = "user://skybox_test_fixture"

var _skybox: Skybox = null


func before_each() -> void:
	_skybox = Skybox.new()
	_skybox.config = SkyboxConfig.new()
	add_child_autofree(_skybox)


func after_each() -> void:
	_remove_dir_recursive(FIXTURE_ROOT)


func test_load_set_returns_true_and_produces_a_texture_per_face() -> void:
	_write_fixture_set("beach_like", _skybox.config.face_names)

	var result: bool = _skybox.load_set("beach_like", FIXTURE_ROOT)

	assert_true(result)
	assert_false(_skybox.fallback_active)
	for face_name: String in _skybox.config.face_names:
		var texture: ImageTexture = _skybox.get_face_texture(face_name)
		assert_not_null(texture, "expected a texture for face '%s'" % face_name)


func test_load_set_with_missing_face_returns_false_and_sets_fallback() -> void:
	var faces: PackedStringArray = _skybox.config.face_names
	var partial: PackedStringArray = PackedStringArray()
	for i: int in range(faces.size() - 1):
		partial.append(faces[i])
	_write_fixture_set("partial", partial)

	var result: bool = _skybox.load_set("partial", FIXTURE_ROOT)

	assert_false(result)
	assert_true(_skybox.fallback_active)
	assert_null(_skybox.get_face_texture(faces[faces.size() - 1]))


func test_load_set_with_missing_folder_returns_false_and_sets_fallback() -> void:
	var result: bool = _skybox.load_set("does-not-exist", FIXTURE_ROOT)

	assert_false(result)
	assert_true(_skybox.fallback_active)


## DECISION (tests/unit/test_skybox.gd): case-insensitive face lookup is NOT
## tested here (and NOT implemented in Skybox.load_set(), which does one
## exact FileAccess.file_exists() check per config.face_names entry).
## tools/install_original_assets.ps1 (owned by another package) already
## lowercases every face file it copies, so ordinary use never needs it. A
## real behavioral test would also be platform-dependent in a way that would
## make it flaky here: Windows' filesystem resolves a mismatched-case path
## anyway (with an engine warning), while a case-sensitive export target
## would fail the exact same missing-face path the tests above already
## cover. Documented instead of pinned.


func test_map_def_skybox_set_defaults_to_beach() -> void:
	var map: MapDef = MapDef.new()
	assert_eq(map.skybox_set, "beach")


func test_map_resources_carry_their_assigned_skybox_set() -> void:
	var small: MapDef = load("res://config/maps/round_small.tres") as MapDef
	var medium: MapDef = load("res://config/maps/round_medium.tres") as MapDef
	var large: MapDef = load("res://config/maps/round_large.tres") as MapDef
	assert_eq(small.skybox_set, "beach")
	assert_eq(medium.skybox_set, "lake")
	assert_eq(large.skybox_set, "mountain")


# --- Fixture helpers ---------------------------------------------------------

func _write_fixture_set(set_name: String, faces: PackedStringArray) -> void:
	var dir_path: String = FIXTURE_ROOT.path_join(set_name)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var image: Image = Image.create(4, 4, false, Image.FORMAT_RGB8)
	image.fill(Color.BLUE)
	for face_name: String in faces:
		image.save_jpg(dir_path.path_join(face_name + ".jpg"))


func _remove_dir_recursive(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full: String = path.path_join(entry)
			if dir.current_is_dir():
				_remove_dir_recursive(full)
			else:
				dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
