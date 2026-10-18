class_name AmbientLife
extends Node3D
## The cosmetic ambient life of the world: distant bird flocks, perching birds and fireflies, and
## the day/night swap between their day and night sets. It is not part of the sky: the sky
## publishes `Events.sky_ambient_configured` (the cycle, graphics preset and disc radius) and
## `Events.sky_time_of_day_changed` (phase and night mix), and this node subscribes.
## The swap is staggered with hysteresis (on above `life_night_on_mix`, back below
## `life_night_off_mix`, both from the cycle) so its discrete configure calls happen in the dark.
## Main creates it through `build` (which injects the nodes it drives) before it enters the tree;
## nothing here looks up groups or the match context.

var birds: DistantBirds = null
var perching: PerchingBirds = null
var fireflies: Fireflies = null

var _def: SkyCycleDef = null
var _preset: GraphicsPreset = null
var _disc_radius_m: float = 0.0
var _is_night: bool = false


## Creates the AmbientLife node with its three driven nodes (child names DistantBirds,
## PerchingBirds, Fireflies) bound to the field and block registry (either may be null in
## fixtures). All properties are set before the caller adds it to the tree.
static func build(field: Field, registry: BlockRegistry) -> AmbientLife:
	var life: AmbientLife = AmbientLife.new()
	life.name = "AmbientLife"
	life.birds = DistantBirds.new()
	life.perching = PerchingBirds.new()
	life.fireflies = Fireflies.new()
	life.perching.bind_scene(field, registry)
	life.fireflies.bind_field(field)
	return life


func _ready() -> void:
	birds.name = "DistantBirds"
	add_child(birds)
	perching.name = "PerchingBirds"
	add_child(perching)
	fireflies.name = "Fireflies"
	add_child(fireflies)
	Events.sky_ambient_configured.connect(configure)
	Events.sky_time_of_day_changed.connect(_on_time_of_day_changed)


func _exit_tree() -> void:
	if Events.sky_ambient_configured.is_connected(configure):
		Events.sky_ambient_configured.disconnect(configure)
	if Events.sky_time_of_day_changed.is_connected(_on_time_of_day_changed):
		Events.sky_time_of_day_changed.disconnect(_on_time_of_day_changed)


## Rebuilds all three from the day set of `def` (never duplicates) and resets the night state.
func configure(def: Resource, preset: Resource, disc_radius_m: float) -> void:
	_def = def as SkyCycleDef
	_preset = preset as GraphicsPreset
	_disc_radius_m = disc_radius_m
	_is_night = false
	_apply()


## Swaps to the night set above the on threshold and back to the day set below the off
## threshold; rebuilds only on a change. Ignored until the first configure.
func update_night(night_mix: float) -> void:
	if _def == null:
		return
	var night: bool = night_mix > (_def.life_night_off_mix if _is_night else _def.life_night_on_mix)
	if night == _is_night:
		return
	_is_night = night
	_apply()


func _on_time_of_day_changed(_phase: float, night_mix: float) -> void:
	update_night(night_mix)


func _apply() -> void:
	var life_enabled: bool = _preset == null or _preset.ambient_life_enabled
	var birds_enabled: bool = _preset == null or _preset.birds_enabled
	var life: AmbientLifeConfig = null
	if _def != null:
		life = _def.night.ambient_life if _is_night and _def.night != null else _def.ambient_life
	if birds != null:
		birds.configure_cycle(_def, not _is_night and birds_enabled)
	if perching != null:
		perching.configure(life, life_enabled)
	if fireflies != null:
		fireflies.configure(life, life_enabled, _disc_radius_m)
