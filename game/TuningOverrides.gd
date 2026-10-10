class_name TuningOverrides
extends RefCounted
## Bontago-1pi.11.84 (MF4): the boot-time half of ui/TuningPanel.gd, split out so game/Main.gd can
## apply the saved F4 overrides without compiling the whole panel (and its PlayerController
## closure) before the menu appears. TuningPanel keeps forwarders for its old names.

const SAVE_PATH: String = "user://tuning_overrides.cfg"


## The file actually read/written: SAVE_PATH, or a per-PID file in a GUT run so
## tests never touch the owner's real F4 overrides (Bontago-1pi.21).
static func save_path() -> String:
	return UserPaths.resolve(SAVE_PATH)


## Loads any saved overrides onto the shared tuning singletons, before anything else in the game
## reads them. Static and free of any node/scene-tree dependence.
static func apply_saved() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(save_path()) != OK:
		return
	_apply_saved_section(config, "CameraTuning", load("res://config/camera_tuning.tres"))
	_apply_saved_section(config, "GhostTuning", load("res://config/ghost_tuning.tres"))
	_apply_saved_section(config, "PhysicsTuning", load("res://config/physics_tuning.tres"))
	_apply_saved_section(config, "TerritoryTuning", load("res://config/territory_tuning.tres"))
	_apply_saved_section(config, "TerritoryVisuals", load("res://config/territory_visuals.tres"))
	_apply_saved_section(config, "BlockFeedConfig", load("res://config/block_feed.tres"))
	_apply_saved_section(config, "SkyboxConfig", load("res://config/skybox_config.tres"))


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
