class_name SkyAmbientLife
extends RefCounted
## Owns the sky's cosmetic ambient life: distant bird flocks, perching birds and fireflies, and
## the day/night swap between their day and night sets. The swap is staggered with hysteresis
## (on above `life_night_on_mix`, back below `life_night_off_mix`, both from the cycle) so its
## discrete configure calls happen in the dark. Dependencies are passed in; nothing here looks
## up groups or the match context.

var _birds: DistantBirds = null
var _perching: PerchingBirds = null
var _fireflies: Fireflies = null
var _is_night: bool = false


## Creates the three nodes under `parent` (child names DistantBirds, PerchingBirds, Fireflies)
## and binds the field and block registry (either may be null in fixtures).
func build(parent: Node3D, field: Field, registry: BlockRegistry) -> void:
	_birds = DistantBirds.new()
	_birds.name = "DistantBirds"
	parent.add_child(_birds)
	_perching = PerchingBirds.new()
	_perching.name = "PerchingBirds"
	parent.add_child(_perching)
	_fireflies = Fireflies.new()
	_fireflies.name = "Fireflies"
	parent.add_child(_fireflies)
	_perching.bind_scene(field, registry)
	_fireflies.bind_field(field)


## Rebuilds all three from the day set of `def` (never duplicates) and resets the night state.
func configure(def: SkyCycleDef, preset: GraphicsPreset, disc_radius_m: float) -> void:
	_is_night = false
	_apply(def, preset, disc_radius_m)


## Swaps to the night set above the on threshold and back to the day set below the off
## threshold; rebuilds only on a change.
func update_night(def: SkyCycleDef, night_mix: float, preset: GraphicsPreset, disc_radius_m: float) -> void:
	var on_mix: float = def.life_night_on_mix if def != null else 1.0
	var off_mix: float = def.life_night_off_mix if def != null else 0.0
	var night: bool = night_mix > (off_mix if _is_night else on_mix)
	if night == _is_night:
		return
	_is_night = night
	_apply(def, preset, disc_radius_m)


func is_night() -> bool:
	return _is_night


func _apply(def: SkyCycleDef, preset: GraphicsPreset, disc_radius_m: float) -> void:
	var life_enabled: bool = preset == null or preset.ambient_life_enabled
	var birds_enabled: bool = preset == null or preset.birds_enabled
	var life: AmbientLifeConfig = null
	if def != null:
		life = def.night.ambient_life if _is_night and def.night != null else def.ambient_life
	if _birds != null:
		_birds.configure_cycle(def, not _is_night and birds_enabled)
	if _perching != null:
		_perching.configure(life, life_enabled)
	if _fireflies != null:
		_fireflies.configure(life, life_enabled, disc_radius_m)
