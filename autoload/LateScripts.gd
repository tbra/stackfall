class_name LateScripts
extends RefCounted
## Bontago-1pi.11.77.3 (S2b): script paths for everything an autoload facade builds late
## (after Boot has prewarmed them). STRING PATHS ONLY: this file must never name a class_name,
## an autoload or a preload of a world script, or it would pull that script back into the
## autoloads' compile graph. Facades call script(path).new() from late_activate().

const MATCH_FEED: String = "res://autoload/match/MatchFeed.gd"
const MATCH_PLACEMENT: String = "res://autoload/match/MatchPlacement.gd"
const MATCH_TERRITORY: String = "res://autoload/match/MatchTerritory.gd"
const MATCH_LIFECYCLE: String = "res://autoload/match/MatchLifecycle.gd"
const MATCH_GIFTS: String = "res://autoload/match/MatchGifts.gd"
const MATCH_STATS: String = "res://autoload/match/MatchStats.gd"
const MATCH_WEATHER: String = "res://autoload/match/MatchWeather.gd"
const GIFT_FX_PRESENTER: String = "res://game/specials/fx/GiftFxPresenter.gd"
const CAT_CONTROLLER: String = "res://game/specials/CatController.gd"
const WEATHER_NET: String = "res://net/WeatherNet.gd"
const BLOCK_FACTORY: String = "res://game/BlockFactory.gd"
const SPECIAL_DEF: String = "res://config/specials/SpecialDef.gd"
const HONEY_COAT: String = "res://game/specials/fx/HoneyCoat.gd"
const CAT_RESOURCE: String = "res://config/specials/cat.tres"

## Method each autoload facade exposes (idempotent) to build its late state.
const ACTIVATE_METHOD: StringName = &"late_activate"
const BOOT_SCRIPT_PATH: String = "res://game/Boot.gd"
const HEADLESS_DISPLAY: String = "headless"


## Every path above, in declaration order, for Boot's prewarm.
static func paths() -> PackedStringArray:
	return PackedStringArray([
		MATCH_FEED, MATCH_PLACEMENT, MATCH_TERRITORY, MATCH_LIFECYCLE, MATCH_GIFTS,
		MATCH_STATS, MATCH_WEATHER, GIFT_FX_PRESENTER, CAT_CONTROLLER, WEATHER_NET,
		BLOCK_FACTORY, SPECIAL_DEF, HONEY_COAT, CAT_RESOURCE,
	])


static func script(path: String) -> GDScript:
	var loaded: GDScript = load(path) as GDScript
	if loaded == null:
		push_error("LateScripts: could not load script %s" % path)
	return loaded


## True while Boot is the current scene in a windowed run: the facades then wait for Boot to
## prewarm and call activate_autoloads. Headless runs activate in their own _ready.
static func boot_defers_activation(tree: SceneTree) -> bool:
	if DisplayServer.get_name() == HEADLESS_DISPLAY or tree == null or tree.current_scene == null:
		return false
	var scene_script: Script = tree.current_scene.get_script() as Script
	return scene_script != null and scene_script.resource_path == BOOT_SCRIPT_PATH


static func activate_autoloads(tree: SceneTree) -> void:
	for child: Node in tree.root.get_children():
		if child.has_method(ACTIVATE_METHOD):
			child.call(ACTIVATE_METHOD)
