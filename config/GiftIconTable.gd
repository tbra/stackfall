class_name GiftIconTable
extends Resource
## Maps gift ids and MatchConfig.WeatherMode names to their UI art (Bontago-mp0.125):
## the compact pictogram atlases (assets/ui/gift_pictograms_v1, weather_pictograms_v1)
## for the lobby toggles/picker, and the rendered model previews
## (assets/ui/gift_previews, assets/ui/gift_model_previews/additional_v1) for the HUD gift cards. Loaded as
## config/gift_icon_table.tres. Presentation only, so every peer reads the same
## replicated ids. Not an F4 tuning panel resource (no hints entry needed).

const TABLE_PATH: String = "res://config/gift_icon_table.tres"

## 4x4 gift atlas and its exact-id regions (assets/ui/gift_pictograms_v1/regions.json).
@export var gift_atlas: Texture2D = null
@export var gift_regions: Dictionary = {}

## Weather atlas and regions keyed by MatchConfig.WeatherMode enum name (uppercase).
@export var weather_atlas: Texture2D = null
@export var weather_regions: Dictionary = {}

## Gift id -> rendered model preview (transparent 384x384 PNG).
@export var model_previews: Dictionary = {}

## Edge of the pictograms shown in lobby rows, in px.
@export var lobby_icon_px: int = 24

static var _shared: GiftIconTable = null
var _cache: Dictionary = {}


static func shared() -> GiftIconTable:
	if _shared == null:
		_shared = load(TABLE_PATH) as GiftIconTable
	return _shared


## Pictogram for a gift id, or null when unknown.
func gift_pictogram(special_id: StringName) -> Texture2D:
	return _region_texture(&"gift", gift_atlas, gift_regions, special_id)


## Pictogram for a MatchConfig.WeatherMode value, or null when unknown.
func weather_pictogram(mode: int) -> Texture2D:
	var keys: Array = MatchConfig.WeatherMode.keys()
	if mode < 0 or mode >= keys.size():
		return null
	return _region_texture(&"weather", weather_atlas, weather_regions, StringName(keys[mode]))


## Rendered model preview for a gift id, or null when unknown.
func model_preview(special_id: StringName) -> Texture2D:
	return model_previews.get(special_id) as Texture2D


func _region_texture(kind: StringName, atlas: Texture2D, regions: Dictionary, key: StringName) -> Texture2D:
	var cache_key: String = "%s/%s" % [kind, key]
	if _cache.has(cache_key):
		return _cache[cache_key] as Texture2D
	if atlas == null or not regions.has(key):
		return null
	var tex: AtlasTexture = AtlasTexture.new()
	tex.atlas = atlas
	tex.region = regions[key] as Rect2
	_cache[cache_key] = tex
	return tex
