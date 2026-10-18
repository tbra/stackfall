class_name SkyEnvironmentWriter
extends RefCounted
## The sole writer of the sky-driven Environment fields (fog, volumetric fog, ambient, background
## energy, glow, aerial perspective, height fog), the key DirectionalLight3D (colour, energy,
## orientation), the CloudDeck FogVolume and the scenery haze push. Every field is written only
## when its value differs from the last write, so an unchanged frame writes nothing and a
## sun-dim-only change writes only `light_energy`. `apply_preset` is the only writer of
## `glow_enabled`, `volumetric_fog_enabled` and the deck visibility. Dependencies are injected
## (bind, spawn_deck and apply take everything they touch); nothing here looks anything up.

const DECK_NODE_NAME: StringName = &"CloudDeck"
## Depth fog curve while weather fog is on (linear).
const WEATHER_FOG_CURVE: float = 1.0

## Names of the fields written by the last `apply` / `apply_preset` call (tests read it).
var last_written: Array[StringName] = []
## Total field writes since bind.
var total_writes: int = 0

var _environment: Environment = null
var _light: DirectionalLight3D = null
var _deck: FogVolume = null
## Last written value per field name.
var _written: Dictionary[StringName, Variant] = {}
var _deck_visible: bool = true
var _background_energy_base: float = 1.0
var _fog_base_mode: int = 0
var _fog_base_begin: float = 0.0
var _fog_base_end: float = 0.0
var _fog_base_curve: float = 1.0
var _haze_pushed: bool = false
var _haze_strength: float = 0.0
var _haze_begin: float = 0.0
var _haze_end: float = 0.0
var _haze_color: Color = Color.WHITE


## Captures the Environment's own background energy and fog mode/range as the bases the frame
## scales or restores, and clears the equal-value cache. `light` may be null.
func bind(environment: Environment, light: DirectionalLight3D) -> void:
	_environment = environment
	_light = light
	_written.clear()
	_haze_pushed = false
	last_written.clear()
	if environment == null:
		return
	_background_energy_base = environment.background_energy_multiplier
	_fog_base_mode = environment.fog_mode
	_fog_base_begin = environment.fog_depth_begin
	_fog_base_end = environment.fog_depth_end
	_fog_base_curve = environment.fog_depth_curve


## Creates the CloudDeck FogVolume (properties set before it is added) as a child of `parent`.
func spawn_deck(parent: Node3D, def: SkyCycleDef) -> FogVolume:
	var deck: FogVolume = FogVolume.new()
	deck.name = DECK_NODE_NAME
	deck.size = def.cloud_deck_size_m
	deck.position = Vector3(0.0, def.cloud_deck_height_m, 0.0)
	deck.visible = _deck_visible
	deck.material = FogMaterial.new()
	parent.add_child(deck)
	_deck = deck
	return deck


## Resyncs the deck's footprint and height to `def` (a live definition edit).
func sync_deck(def: SkyCycleDef) -> void:
	if _deck == null:
		return
	_deck.size = def.cloud_deck_size_m
	_deck.position = Vector3(0.0, def.cloud_deck_height_m, 0.0)


## The deck node (null before spawn_deck).
func deck() -> FogVolume:
	return _deck


## The deck is shown only when the preset enables volumetric fog; it is never created or freed.
func set_deck_visible(preset: GraphicsPreset) -> void:
	if preset == null:
		return
	_deck_visible = preset.volumetric_fog_enabled
	if _deck != null and _deck.visible != _deck_visible:
		_deck.visible = _deck_visible


## Writes `glow_enabled`, `volumetric_fog_enabled` and the deck visibility from `preset`.
func apply_preset(preset: GraphicsPreset) -> void:
	last_written.clear()
	if preset == null:
		return
	if _environment != null:
		_put_environment(&"glow_enabled", preset.glow_enabled)
		_put_environment(&"volumetric_fog_enabled", preset.volumetric_fog_enabled)
	set_deck_visible(preset)


## Writes the environment, light and deck channels of `frame` (equal values are skipped) and
## pushes the scenery haze when one of its inputs changed.
func apply(frame: SkyFrame, tree: SceneTree) -> void:
	last_written.clear()
	if _environment == null:
		return
	_put_environment(&"fog_enabled", true)
	_put_environment(&"fog_light_color", frame.fog_light_color)
	_put_environment(&"fog_sky_affect", frame.fog_sky_affect)
	# Environment.set_fog_mode resets fog_density (engine environment.cpp), so the mode is
	# written first and the density is rewritten whenever the mode was.
	var mode_written: bool = false
	if frame.fog_depth_mode:
		mode_written = _put_environment(&"fog_mode", Environment.FOG_MODE_DEPTH)
		_put_environment(&"fog_depth_begin", frame.fog_depth_begin)
		_put_environment(&"fog_depth_end", frame.fog_depth_end)
		_put_environment(&"fog_depth_curve", WEATHER_FOG_CURVE)
	else:
		mode_written = _put_environment(&"fog_mode", _fog_base_mode)
		_put_environment(&"fog_depth_begin", _fog_base_begin)
		_put_environment(&"fog_depth_end", _fog_base_end)
		_put_environment(&"fog_depth_curve", _fog_base_curve)
	if mode_written:
		_written.erase(&"fog_density")
	_put_environment(&"fog_density", frame.fog_density)
	_put_environment(&"volumetric_fog_density", frame.volumetric_fog_density)
	_put_environment(&"volumetric_fog_albedo", frame.volumetric_fog_albedo)
	_put_environment(&"ambient_light_energy", frame.ambient_light_energy)
	_put_environment(&"background_energy_multiplier", _background_energy_base * frame.background_energy_scale)
	_put_environment(&"glow_intensity", frame.glow_intensity)
	_put_environment(&"glow_hdr_threshold", frame.glow_hdr_threshold)
	_put_environment(&"fog_aerial_perspective", frame.fog_aerial_perspective)
	_put_environment(&"fog_sun_scatter", frame.fog_sun_scatter)
	_put_environment(&"fog_height", frame.fog_height)
	_put_environment(&"fog_height_density", frame.fog_height_density)
	_apply_light(frame)
	_apply_deck(frame)
	_apply_haze(frame, tree)


## The fog colour currently in the Environment (the disc's own fog uses it).
func weather_fog_color() -> Color:
	return _environment.fog_light_color if _environment != null else Color.WHITE


func _apply_light(frame: SkyFrame) -> void:
	if _light == null:
		return
	_put_light(&"light_color", frame.light_color)
	_put_light(&"light_energy", frame.light_energy)
	if frame.light_uses_sun_basis:
		if _changed(&"light_sun_direction", frame.sun_direction):
			_light.global_basis = Basis.looking_at(-frame.sun_direction, Vector3.UP)
		_written.erase(&"light_rotation_deg")
	else:
		if _changed(&"light_rotation_deg", frame.light_rotation_deg):
			_light.rotation_degrees = frame.light_rotation_deg
		_written.erase(&"light_sun_direction")


func _apply_deck(frame: SkyFrame) -> void:
	if _deck == null:
		return
	var fog_material: FogMaterial = _deck.material as FogMaterial
	if fog_material == null:
		return
	if _changed(&"deck_density", frame.deck_density):
		fog_material.density = frame.deck_density
	if _changed(&"deck_albedo", frame.deck_albedo):
		fog_material.albedo = frame.deck_albedo


func _apply_haze(frame: SkyFrame, tree: SceneTree) -> void:
	if _haze_pushed and _haze_strength == frame.haze_strength and _haze_begin == frame.haze_begin \
			and _haze_end == frame.haze_end and _haze_color == frame.fog_light_color:
		return
	_haze_pushed = true
	_haze_strength = frame.haze_strength
	_haze_begin = frame.haze_begin
	_haze_end = frame.haze_end
	_haze_color = frame.fog_light_color
	WeatherFogShader.set_ambient(_haze_strength, _haze_begin, _haze_end, _haze_color, tree)


## True (and records the value) when `value` differs from the last one written under `key`.
func _changed(key: StringName, value: Variant) -> bool:
	if _written.has(key) and _written[key] == value:
		return false
	_written[key] = value
	last_written.append(key)
	total_writes += 1
	return true


func _put_environment(key: StringName, value: Variant) -> bool:
	if not _changed(key, value):
		return false
	_environment.set(key, value)
	return true


func _put_light(key: StringName, value: Variant) -> void:
	if _changed(key, value):
		_light.set(key, value)
