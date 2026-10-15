class_name TuningSfxTab
extends RefCounted
## pure helpers for the F4 panel's SFX tab ("wire it up so I can test it in
## game the same way I can test the arena layouts"). The tab lists one dropdown + Play row per
## sound-effect file field of AudioConfig; ui/debug/TuningPanel.gd builds the controls, this file decides
## which fields and files appear and in what order, and owns the save/reset of just those fields.
##
## DECISION: only plain String `*_file` fields get a row. The dictionary-valued ones
## (special_cue_files, special_loop_files, ui_cue_files, impact_variation_files) and the array
## thud_files do not fit one dropdown per field row (the panel's modified marker, default column and
## save/reset all key on a single property), so they stay file-only edits for now.

const TAB_NAME: String = "SFX"
const CLASS_LABEL: String = "AudioConfig"
const SECTION_TITLE: String = "Sound files"
const FILE_FIELD_SUFFIX: String = "_file"
## Music fields live in the music folder/playlists and are not effects.
const MUSIC_FIELD_PREFIX: String = "music_"
const FAMILY_SEPARATOR: String = "_"


## Exported String `*_file` properties of `config` (declaration order) whose current value is a file
## in `available` (the effects folder listing), excluding music fields.
static func sfx_fields(config: AudioConfig, available: PackedStringArray) -> Array[String]:
	var fields: Array[String] = []
	if config == null:
		return fields
	for prop: Dictionary in config.get_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if int(prop.get("type", TYPE_NIL)) != TYPE_STRING or not prop_name.ends_with(FILE_FIELD_SUFFIX):
			continue
		if prop_name.begins_with(MUSIC_FIELD_PREFIX):
			continue
		if (int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if available.has(String(config.get(prop_name)).to_lower()):
			fields.append(prop_name)
	return fields


## The file's name without extension and without its last "_x" suffix: block_drop_c.wav -> block_drop.
static func family_stem(filename: String) -> String:
	var base: String = filename.get_basename()
	var cut: int = base.rfind(FAMILY_SEPARATOR)
	return base.substr(0, cut) if cut > 0 else base


## `files` ordered for `current`'s dropdown: the current value's family first (alphabetical), then
## the rest (alphabetical). `current` is added when it is not in `files` so it can be shown.
static func ordered_choices(current: String, files: PackedStringArray) -> PackedStringArray:
	var all: Array[String] = []
	for filename: String in files:
		all.append(filename)
	if not current.is_empty() and not all.has(current):
		all.append(current)
	all.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	var stem: String = family_stem(current)
	var family: PackedStringArray = PackedStringArray()
	var others: PackedStringArray = PackedStringArray()
	for filename: String in all:
		if family_stem(filename) == stem:
			family.append(filename)
		else:
			others.append(filename)
	family.append_array(others)
	return family


## Writes just the SFX file fields of `config` into `file` under CLASS_LABEL.
static func write_overrides(file: ConfigFile, config: AudioConfig, available: PackedStringArray) -> void:
	for prop_name: String in sfx_fields(config, available):
		file.set_value(CLASS_LABEL, prop_name, config.get(prop_name))


## Restores the SFX file fields of `config` from a fresh load of its shipped .tres.
static func reset_fields(config: AudioConfig) -> void:
	if config == null or config.resource_path.is_empty():
		return
	var fresh: AudioConfig = ResourceLoader.load(config.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioConfig
	if fresh == null:
		return
	for prop: Dictionary in config.get_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if int(prop.get("type", TYPE_NIL)) == TYPE_STRING and prop_name.ends_with(FILE_FIELD_SUFFIX) \
				and (int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			config.set(prop_name, fresh.get(prop_name))
