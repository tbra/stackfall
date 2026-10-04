class_name UiArtTable
extends Resource
## Maps map variants and lobby icon keys to their UI art (Bontago-mp0.124 part A):
## the arena pictograms (assets/ui/map_pictograms_v1) for the lobby map picker and the
## loading screen, and the white-source lobby rework icons (assets/ui/icons/lobby_v1)
## for section headers, bot/team controls and the Advanced chips. Loaded as
## config/ui_art_table.tres. Presentation only: every peer reads replicated ids, so host
## and client match. Not an F4 tuning panel resource (no hints entry needed).

const TABLE_PATH: String = "res://config/ui_art_table.tres"

## Icon keys (the catalog ids of assets/ui/icons/lobby_v1/catalog.json).
const KEY_SECTION_GAME: StringName = &"section_game"
const KEY_SECTION_ROUND: StringName = &"section_round"
const KEY_SECTION_GIFTS: StringName = &"section_gifts"
const KEY_SECTION_EXPERIMENTS: StringName = &"section_experiments"
const KEY_BOT_ADD: StringName = &"bot_add"
const KEY_BOT_REMOVE: StringName = &"bot_remove"
const KEY_TEAMS: StringName = &"teams"
const KEY_TEAM_RANDOM: StringName = &"team_random"
const KEY_COLOUR_SWAP: StringName = &"colour_swap"
const KEY_ADVANCED_OPEN: StringName = &"advanced_open"
const KEY_ADVANCED_CLOSED: StringName = &"advanced_closed"
const KEY_DIFFICULTY: Array[StringName] = [&"difficulty_easy", &"difficulty_normal", &"difficulty_hard"]

## 4x2 map atlas and its regions keyed by MatchConfig.MapVariant enum name.
@export var map_atlas: Texture2D = null
@export var map_regions: Dictionary = {}

## Icon key -> white-source 24x24 SVG texture.
@export var lobby_icons: Dictionary = {}

## Edge of the map pictogram in the lobby thumbnail and picker rows, in px.
@export var map_icon_px: int = 28
## Edge of the pictogram on the loading screen card, in px.
@export var loading_map_icon_px: int = 64
## Edge of the section header and control icons, in px.
@export var lobby_icon_px: int = 20

static var _shared: UiArtTable = null
var _cache: Dictionary = {}


static func shared() -> UiArtTable:
	if _shared == null:
		_shared = load(TABLE_PATH) as UiArtTable
	return _shared


## Pictogram for a MatchConfig.MapVariant value, or null when unknown.
func map_pictogram(variant: int) -> Texture2D:
	var keys: Array = MatchConfig.MapVariant.keys()
	if variant < 0 or variant >= keys.size():
		return null
	var key: StringName = StringName(keys[variant])
	if _cache.has(key):
		return _cache[key] as Texture2D
	if map_atlas == null or not map_regions.has(key):
		return null
	var tex: AtlasTexture = AtlasTexture.new()
	tex.atlas = map_atlas
	tex.region = map_regions[key] as Rect2
	tex.filter_clip = true
	_cache[key] = tex
	return tex


## Lobby icon for a catalog key, or null when unknown.
func lobby_icon(key: StringName) -> Texture2D:
	return lobby_icons.get(key) as Texture2D


## Difficulty icon for a MatchConfig.AiDifficulty value (clamped), or null.
func difficulty_icon(difficulty: int) -> Texture2D:
	return lobby_icon(KEY_DIFFICULTY[clampi(difficulty, 0, KEY_DIFFICULTY.size() - 1)])


## Shows [param texture] on a button at the table's icon size.
func apply_button_icon(button: Button, texture: Texture2D) -> void:
	button.icon = texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", lobby_icon_px)
