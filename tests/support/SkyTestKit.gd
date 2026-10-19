class_name SkyTestKit
extends RefCounted
## Shared sky test set-up: tests build a Skybox on the shipped cycle and edit a fresh
## SkyCycleDef. No scene tree.

const CYCLE_PATH: String = "res://config/sky/sky_cycle.tres"
const STORM_PATH: String = "res://config/sky/storm_overlay.tres"
const GOLDEN_PATH: String = "res://tests/unit/sky/fixtures/sky_cycle_golden.json"
const SKYBOX_CONFIG_PATH: String = "res://config/sky/skybox_config.tres"


## A fresh load of the shipped cycle (CACHE_MODE_IGNORE), so a test may edit it freely.
static func cycle() -> SkyCycleDef:
	return ResourceLoader.load(CYCLE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SkyCycleDef


## A fresh load of the shipped storm overlay definition.
static func storm_overlay() -> SkyOverlayDef:
	return ResourceLoader.load(STORM_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SkyOverlayDef


## The parsed golden fixture. Empty when the file is missing or does not parse to a Dictionary.
static func golden() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(GOLDEN_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


## The cycle phase a locked sky id shows (SkyCycleDef.locked_phase_for on a fresh cycle).
static func locked_phase(sky_id: String) -> float:
	return cycle().locked_phase_for(sky_id)


## A Skybox on the shipped cycle with a duplicated SkyboxConfig, added to `parent`.
static func make_skybox(parent: Node) -> Skybox:
	var skybox: Skybox = Skybox.new()
	var shipped_config: SkyboxConfig = ResourceLoader.load(SKYBOX_CONFIG_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SkyboxConfig
	skybox.config = shipped_config.duplicate() as SkyboxConfig
	skybox.sky_def = cycle()
	parent.add_child(skybox)
	return skybox
