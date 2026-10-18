class_name SunCloudCover
extends RefCounted
## How much the cloud puffs hide the sun along one ray, refreshed on a timer. CloudShadows (sun
## dimming, origin above the arena) and SunFlare (flare, origin at the camera) each own one, with
## their own refresh period; the bounds query itself is CloudOcclusionBounds.ray_cover through
## CloudSea.sun_ray_cloud_occlusion().
## DECISION: the query goes through CloudSea.sun_ray_cloud_occlusion() rather than straight to
## occlusion().ray_cover(), so the hidden-sea check and the live drift stay in one place and the
## answer is bit-identical to before.
## The CloudSea is injected as a resolver (a Callable returning a CloudSea or null), called only
## while no valid sea is held, so this class needs neither the scene tree nor a group lookup.

var _resolver: Callable = Callable()
var _sea: CloudSea = null
var _cover: float = 0.0
var _age_s: float = 0.0
## True when the next query() must refresh now (a fresh cover starts so only if built so).
var _queried: bool = false
var _immediate_first: bool = false


## `sea_resolver` returns the live CloudSea (or null); `immediate_first` makes the first query()
## refresh at once instead of waiting a full period.
func _init(sea_resolver: Callable, immediate_first: bool) -> void:
	_resolver = sea_resolver
	_immediate_first = immediate_first
	_queried = not immediate_first


## Ages the last answer by `delta` seconds.
func advance(delta: float) -> void:
	_age_s += delta


## The cover (0..1) of the ray `from` along `dir`: re-queried once `refresh_s` has passed (or at
## the first call when immediate_first), otherwise the last answer. A scene without a CloudSea
## hides nothing.
func query(from: Vector3, dir: Vector3, tuning: SunFlareConfig, refresh_s: float) -> float:
	if not _queried or _age_s >= refresh_s:
		_age_s = 0.0
		_queried = true
		_cover = _measure(from, dir, tuning)
	return _cover


## Forgets the last answer (sun below the horizon) but keeps its age.
func clear() -> void:
	_cover = 0.0


## Back to the freshly built state.
func reset() -> void:
	_cover = 0.0
	_age_s = 0.0
	_queried = not _immediate_first


func _measure(from: Vector3, dir: Vector3, tuning: SunFlareConfig) -> float:
	if _sea == null or not is_instance_valid(_sea):
		_sea = _resolver.call() as CloudSea
	if _sea == null:
		return 0.0
	return _sea.sun_ray_cloud_occlusion(from, dir, tuning)
