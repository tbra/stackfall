extends GutTest
## Golden-file test for autoload/Settings.gd: settings files written by earlier builds must load to
## the same values, and a save must write the same section/key set. Guards refactors of Settings.

const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")
const FULL_FILE: String = """[graphics]
preset="high"
adaptive_quality=true
camera_shake_enabled=false
fov_override_deg=82.5
window_mode="windowed"
ui_scale=1.25
hud_scale=0.75
minimap_size=2

[gamepad]
rumble_enabled=false
rumble_strength=0.4

[audio]
master_volume_percent=0.5
master_muted=true
music_volume_percent=0.25
music_muted=false
sfx_volume_percent=0.75
sfx_muted=true
weather_volume_percent=0.1
weather_muted=false

[player]
name="Golden"

[controls]
mouse_move_speed_scale=1.5
stick_move_speed_scale=1.8
stick_speed_basis=2

[debug]
enabled=true
"""
const SAVED_KEYS: Dictionary = {
	"graphics": ["preset", "adaptive_quality", "camera_shake_enabled", "fov_override_deg", "window_mode",
		"ui_scale", "hud_scale", "minimap_size"],
	"gamepad": ["rumble_enabled", "rumble_strength"],
	"audio": ["master_volume_percent", "master_muted", "music_volume_percent", "music_muted",
		"sfx_volume_percent", "sfx_muted", "weather_volume_percent", "weather_muted"],
	"player": ["name"],
	"controls": ["mouse_move_speed_scale", "stick_move_speed_scale", "stick_speed_basis"],
}

var _settings: Node


func before_each() -> void:
	_delete_file()


func after_each() -> void:
	_delete_file()
	UiScaleTuning.current_scale = -1.0
	UiScaleTuning.current_hud_scale = -1.0
	UiScaleTuning.current_minimap_preset = -1


func _delete_file() -> void:
	if FileAccess.file_exists(Settings.effective_path()):
		DirAccess.remove_absolute(Settings.effective_path())


func _load_from(text: String) -> void:
	var file: FileAccess = FileAccess.open(Settings.effective_path(), FileAccess.WRITE)
	file.store_string(text)
	file.close()
	_settings = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(_settings)


func test_full_file_loads_every_value() -> void:
	_load_from(FULL_FILE)
	assert_eq(_settings.graphics_base_preset_id(), &"high")
	assert_true(_settings.adaptive_quality_enabled())
	assert_false(_settings.camera_shake_enabled())
	assert_almost_eq(_settings.fov_override_deg(), 82.5, 0.0001)
	assert_eq(_settings.window_mode(), &"windowed")
	assert_almost_eq(_settings.ui_scale(), 1.25, 0.0001)
	assert_almost_eq(_settings.hud_scale(), 0.75, 0.0001)
	assert_eq(_settings.minimap_size_preset(), 2)
	assert_false(_settings.rumble_enabled())
	assert_almost_eq(_settings.rumble_strength(), 0.4, 0.0001)
	assert_almost_eq(_settings.master_volume_percent(), 0.5, 0.0001)
	assert_true(_settings.master_muted())
	assert_almost_eq(_settings.music_volume_percent(), 0.25, 0.0001)
	assert_false(_settings.music_muted())
	assert_almost_eq(_settings.sfx_volume_percent(), 0.75, 0.0001)
	assert_true(_settings.sfx_muted())
	assert_almost_eq(_settings.weather_volume_percent(), 0.1, 0.0001)
	assert_false(_settings.weather_muted())
	assert_eq(_settings.player_name(), "Golden")
	assert_almost_eq(_settings.mouse_move_speed_scale(), 1.5, 0.0001)
	assert_almost_eq(_settings.stick_move_speed_scale(), 1.8, 0.0001)
	assert_eq(_settings.debug_setting(), 1)


func test_preset_only_file_keeps_defaults_elsewhere() -> void:
	_load_from("[graphics]\npreset=\"low\"\n")
	assert_eq(_settings.graphics_base_preset_id(), &"low")
	assert_false(_settings.graphics_preset_is_custom())
	assert_false(_settings.adaptive_quality_enabled())
	assert_true(_settings.camera_shake_enabled())
	assert_eq(_settings.fov_override_deg(), 0.0)
	assert_eq(_settings.window_mode(), &"borderless_fullscreen")
	assert_eq(_settings.master_volume_percent(), 1.0)
	assert_false(_settings.master_muted())
	assert_eq(_settings.sfx_volume_percent(), 1.0)
	assert_eq(_settings.player_name(), "")
	assert_eq(_settings.mouse_move_speed_scale(), 1.0)
	assert_eq(_settings.stick_move_speed_scale(), 1.0)
	assert_eq(_settings.debug_setting(), -1)


func test_stick_scale_without_basis_marker_is_migrated_and_clamped() -> void:
	_load_from("[controls]\nstick_move_speed_scale=1.8\n")
	assert_almost_eq(_settings.stick_move_speed_scale(), 1.5, 0.0001, "1.8 / 1.2")
	_settings.queue_free()
	await get_tree().process_frame
	_delete_file()
	_load_from("[controls]\nstick_move_speed_scale=0.3\n")
	assert_almost_eq(_settings.stick_move_speed_scale(), 0.5, 0.0001, "0.3 / 1.2 clamps up to the slider minimum")


func test_save_writes_the_same_section_and_key_set() -> void:
	_load_from(FULL_FILE)
	_settings.set_player_name("Golden")
	_settings.set_player_name("Golden2")  # a real change forces a _save()
	var cfg: ConfigFile = ConfigFile.new()
	assert_eq(cfg.load(Settings.effective_path()), OK)
	var sections: Array = Array(cfg.get_sections())
	sections.sort()
	var expected_sections: Array = SAVED_KEYS.keys() + ["debug"]
	expected_sections.sort()
	assert_eq(sections, expected_sections)
	for section: String in SAVED_KEYS:
		var keys: Array = Array(cfg.get_section_keys(section))
		keys.sort()
		var expected: Array = SAVED_KEYS[section].duplicate()
		expected.sort()
		assert_eq(keys, expected, "keys of [%s]" % section)
	assert_eq(cfg.get_value("player", "name"), "Golden2")
	assert_eq(cfg.get_value("graphics", "preset"), "high")
	assert_eq(cfg.get_value("controls", "stick_speed_basis"), 2)
	assert_true(cfg.get_value("debug", "enabled"))
