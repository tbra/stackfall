class_name TuningOverrides
extends RefCounted
## The boot-time half of ui/debug/TuningPanel.gd, split out so game/main/Main.gd can
## apply the saved F4 overrides without compiling the whole panel (and its PlayerController
## closure) before the menu appears.

const SAVE_PATH: String = "user://tuning_overrides.cfg"

## Ordered label -> res path: the one list apply_saved(), write_sections() and copy_text() walk.
## AudioConfig stays outside it: TuningSfxTab writes its file keys, apply_saved restores it separately.
const SECTIONS: Dictionary = {
	"CameraTuning": "res://config/player/camera_tuning.tres",
	"GhostTuning": "res://config/blocks/tuning/ghost_tuning.tres",
	"PhysicsTuning": "res://config/physics/physics_tuning.tres",
	"TerritoryTuning": "res://config/territory/territory_tuning.tres",
	"TerritoryVisuals": "res://config/territory/territory_visuals.tres",
	"BlockFeedConfig": "res://config/match/block_feed.tres",
	"SkyboxConfig": "res://config/sky/skybox_config.tres",
	"ArenaSideStyle": "res://config/territory/arena_side_style.tres",
}

const EXPORT_USAGE_MASK: int = PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE


## The file actually read/written: SAVE_PATH, or a per-PID file in a GUT run or agent
## probe so neither touches the owner's real F4 overrides.
static func save_path() -> String:
	return UserPaths.gut_path(SAVE_PATH) if UserPaths.is_isolated_run() else SAVE_PATH


## Loads any saved overrides onto the shared tuning singletons, before anything else in the game
## reads them. Static and free of any node/scene-tree dependence.
static func apply_saved() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(save_path()) != OK:
		return
	for label: String in SECTIONS:
		_apply_saved_section(config, label, load(SECTIONS[label] as String))
	# the F4 SFX tab's file picks (TuningSfxTab.write_overrides writes only *_file keys).
	_apply_saved_section(config, "AudioConfig", load("res://config/audio/audio_config.tres"))


## True for a script `@export` field (the ones saved, copied and reset).
static func is_exported_field(prop: Dictionary) -> bool:
	var usage: int = int(prop.get("usage", 0))
	return (usage & EXPORT_USAGE_MASK) == EXPORT_USAGE_MASK


## Writes one section per SECTIONS key present in `instances` (label -> live resource): every
## exported bool/int/float/Color/String field. TYPE_STRING is included so SkyboxConfig.theme_name
## round-trips like the rest.
static func write_sections(config: ConfigFile, instances: Dictionary) -> void:
	for label: String in SECTIONS:
		var resource: Resource = instances.get(label) as Resource
		if resource == null:
			continue
		for prop_name: String in _saved_field_names(resource):
			config.set_value(label, prop_name, resource.get(prop_name))


## ".tres"-style `name = value` lines under a "# Label" header per SECTIONS entry, in SECTIONS
## order, meant to be pasted into the matching config/*.tres file.
static func copy_text(instances: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for label: String in SECTIONS:
		var resource: Resource = instances.get(label) as Resource
		if resource == null:
			parts.append("# %s\n(none)" % label)
			continue
		var lines: PackedStringArray = PackedStringArray(["# %s" % label])
		for prop_name: String in _saved_field_names(resource):
			lines.append("%s = %s" % [prop_name, _format_value(resource.get(prop_name))])
		parts.append("\n".join(lines))
	return "\n\n".join(parts)


## Reloads the resource's file (cache ignored) onto the live instance.
static func reset_resource(resource: Resource) -> void:
	if resource == null or resource.resource_path.is_empty():
		return
	var fresh: Resource = ResourceLoader.load(resource.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if fresh == null:
		return
	for prop: Dictionary in resource.get_property_list():
		if not is_exported_field(prop):
			continue
		var prop_name: String = str(prop.get("name", ""))
		resource.set(prop_name, fresh.get(prop_name))


## Names of the exported fields whose type is persisted and copied.
static func _saved_field_names(resource: Resource) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for prop: Dictionary in resource.get_property_list():
		if not is_exported_field(prop):
			continue
		match int(prop.get("type", TYPE_NIL)):
			TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_COLOR, TYPE_STRING:
				names.append(str(prop.get("name", "")))
	return names


static func _format_value(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			var text: String = str(float(value))
			return text if (text.contains(".") or text.contains("e")) else "%s.0" % text
		TYPE_COLOR:
			return var_to_str(value)
		TYPE_STRING:
			return "\"%s\"" % String(value)
		_:
			return str(value)


static func _apply_saved_section(config: ConfigFile, section: String, resource: Resource) -> void:
	if resource == null or not config.has_section(section):
		return
	# A stale key from an older build (a renamed/removed field) must not
	# reach Object.set() -- collect the resource's own current field names
	# first rather than trusting whatever the file on disk happens to say.
	var valid_props: Dictionary = {}
	for prop: Dictionary in resource.get_property_list():
		valid_props[str(prop.get("name", ""))] = true
	for key: String in config.get_section_keys(section):
		if not valid_props.has(key):
			continue
		resource.set(key, config.get_value(section, key))
