extends GutTest
## Bontago-1pi.211: the F4 panel's SFX tab (ui/debug/TuningSfxTab.gd + TuningPanel._build_sfx_section).
## Sfx.config is the shared preloaded audio_config.tres, so every test restores drop_file and the
## per-PID overrides file in after_each rather than leaking a pick into later tests.

const SHIPPED_DROP: String = "block_drop_c.wav"
const PICKED_DROP: String = "block_drop_e.wav"

var _panel: TuningPanel = null
var _saved_drop: String = ""


func before_each() -> void:
	_saved_drop = Sfx.config.drop_file
	_panel = autofree(load("res://ui/debug/TuningPanel.tscn").instantiate())
	add_child_autofree(_panel)
	_panel.net_provider = FakeNet.offline()
	_panel.rebuild()


func after_each() -> void:
	Sfx.config.drop_file = _saved_drop
	if FileAccess.file_exists(TuningPanel.save_path()):
		DirAccess.remove_absolute(TuningPanel.save_path())


func _option(prop_name: String) -> OptionButton:
	var holder: Control = _panel.control_for(_panel.audio_config, prop_name)
	return holder.get_node("SfxOption") as OptionButton if holder != null else null


func _texts(option: OptionButton) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for index: int in option.item_count:
		out.append(option.get_item_text(index))
	return out


func _pick(option: OptionButton, filename: String) -> void:
	var index: int = _texts(option).find(filename)
	assert_gt(index, -1, "%s is in the dropdown" % filename)
	option.select(index)
	option.item_selected.emit(index)


func test_picking_a_file_changes_what_the_next_drop_event_plays() -> void:
	_pick(_option("drop_file"), PICKED_DROP)
	assert_eq(Sfx.config.drop_file, PICKED_DROP)
	assert_true(_panel.is_modified(Sfx.config, "drop_file"), "modified marker")
	assert_same(Sfx._pick_stream(AudioConfig.EVENT_DROP), Sfx._load_stream(PICKED_DROP), "next drop resolves the picked stream")


func test_save_reload_and_reset_round_trip() -> void:
	_pick(_option("drop_file"), PICKED_DROP)
	assert_eq(_panel.save_overrides(), OK)
	Sfx.config.drop_file = SHIPPED_DROP
	TuningPanel.apply_saved_overrides()
	assert_eq(Sfx.config.drop_file, PICKED_DROP, "saved pick is restored")
	_panel.reset_all()
	assert_eq(Sfx.config.drop_file, SHIPPED_DROP, "reset restores the shipped value")
	var shipped: AudioConfig = ResourceLoader.load("res://config/audio/audio_config.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as AudioConfig
	assert_eq(shipped.drop_file, SHIPPED_DROP, "the .tres on disk is untouched")


func test_no_music_field_has_a_row() -> void:
	var shown: Array[String] = _panel.shown_fields_for(_panel.audio_config)
	assert_gt(shown.size(), 5, "several effect fields")
	for prop_name: String in shown:
		assert_false(prop_name.begins_with("music_"), prop_name)
		assert_true(prop_name.ends_with("_file"), prop_name)
		assert_false(_panel.hints.description_for("AudioConfig", prop_name).is_empty(), "%s has a hint" % prop_name)
