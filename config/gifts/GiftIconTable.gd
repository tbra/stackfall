class_name GiftIconTable
extends Resource
## Maps gift ids to their UI art:
## the compact pictogram atlases (assets/ui/gift_pictograms)
## for the lobby toggles/picker, and the rendered model previews
## (assets/ui/gift_previews, assets/ui/gift_model_previews) for the HUD gift cards. Loaded as
## config/gifts/gift_icon_table.tres. Presentation only, so every peer reads the same
## replicated ids. Not an F4 tuning panel resource (no hints entry needed).

const TABLE_PATH: String = "res://config/gifts/gift_icon_table.tres"

## 4x4 gift atlas and its exact-id regions (`gift_regions`, rects in the atlas).
@export var gift_atlas: Texture2D = null
@export var gift_regions: Dictionary = {}

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


## drops the shared instance on exit so its textures are freed with the tree.
static func release_shared() -> void:
	_shared = null


## Pictogram for a gift id, or null when unknown.
func gift_pictogram(special_id: StringName) -> Texture2D:
	return _region_texture(&"gift", gift_atlas, gift_regions, special_id)


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
